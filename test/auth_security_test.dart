import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:docsift/features/auth/data/auth_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Use 2,000 PBKDF2 iterations in unit tests for fast execution while
  // exercising the exact same PBKDF2-HMAC-SHA256 + AES-256-GCM code paths.
  const testIterations = 2000;

  group('AuthRepository Envelope Cryptography & PIN Lifecycle', () {
    test('setupPin wraps VEK with AES-256-GCM and stores zero raw VEK when biometrics is off', () async {
      final store = InMemorySecureStore();
      final auth = AuthRepository(
        store: store,
        pbkdf2Iterations: testIterations,
      );

      expect(await auth.isPinSetup(), isFalse);
      await auth.setupPin('482910');

      expect(auth.isLocked, isFalse);
      expect(auth.hasPinConfiguredSync, isTrue);
      final originalVek = auth.vaultEncryptionKey;
      expect(originalVek, isNotNull);
      expect(originalVek!.length, 32);

      // Verify raw VEK is NOT stored anywhere in storage when biometrics is off
      expect(store.containsKey('docsift_wrapped_vek'), isTrue);
      expect(store.containsKey('docsift_vault_key'), isFalse);
      expect(store.containsKey('docsift_biometric_vek'), isFalse);

      // Lock wipes in-memory VEK
      auth.lock();
      expect(auth.isLocked, isTrue);
      expect(auth.vaultEncryptionKey, isNull);

      // Wrong PIN fails; right PIN unwraps the exact same 32-byte VEK
      expect(await auth.unlock('999999'), isFalse);
      expect(auth.isLocked, isTrue);

      expect(await auth.unlock('482910'), isTrue);
      expect(auth.isLocked, isFalse);
      expect(auth.vaultEncryptionKey, equals(originalVek));
    });

    test('changePin requires valid currentPin and preserves VEK across KEK rotation', () async {
      final store = InMemorySecureStore();
      final auth = AuthRepository(
        store: store,
        pbkdf2Iterations: testIterations,
      );

      await auth.setupPin('123456');
      final vekBefore = auth.vaultEncryptionKey!;

      // Rejects wrong current PIN
      expect(await auth.changePin('000000', '654321'), isFalse);

      // Accepts right current PIN and re-wraps identical VEK
      expect(await auth.changePin('123456', '654321'), isTrue);
      expect(auth.vaultEncryptionKey, equals(vekBefore));

      auth.lock();
      expect(await auth.unlock('123456'), isFalse);
      expect(await auth.unlock('654321'), isTrue);
      expect(auth.vaultEncryptionKey, equals(vekBefore));
    });

    test('biometric VEK escrow is written only when enabled while unlocked and scrubbed on disable', () async {
      final store = InMemorySecureStore();
      final auth = AuthRepository(
        store: store,
        pbkdf2Iterations: testIterations,
      );

      await auth.setupPin('246810');
      expect(store.containsKey('docsift_biometric_vek'), isFalse);

      // Enabling while unlocked stores biometric VEK
      expect(await auth.setBiometricUnlockEnabled(true), isTrue);
      expect(store.containsKey('docsift_biometric_vek'), isTrue);

      // Disabling immediately scrubs biometric VEK from storage
      expect(await auth.setBiometricUnlockEnabled(false), isTrue);
      expect(store.containsKey('docsift_biometric_vek'), isFalse);

      // Cannot enable biometrics while vault is locked
      auth.lock();
      expect(await auth.setBiometricUnlockEnabled(true), isFalse);
      expect(store.containsKey('docsift_biometric_vek'), isFalse);
    });
  });

  group('Persistent Brute-Force Counter & Progressive Cooldown', () {
    test('persists failed attempts and cooldown across simulated app restarts', () async {
      final store = InMemorySecureStore();
      DateTime now = DateTime.utc(2026, 11, 7, 12, 0, 0);

      final auth1 = AuthRepository(
        store: store,
        pbkdf2Iterations: testIterations,
        clock: () => now,
      );
      await auth1.setupPin('777888');
      auth1.lock();

      // 3 failed attempts trigger 30s cooldown
      await auth1.recordFailedAttempt();
      await auth1.recordFailedAttempt();
      final s3 = await auth1.recordFailedAttempt();
      expect(s3.failedAttempts, 3);
      expect(s3.remainingCooldownSeconds, 30);

      // Simulate force-closing the app and creating a brand-new AuthRepository
      final authRestarted = AuthRepository(
        store: store,
        pbkdf2Iterations: testIterations,
        clock: () => now,
      );

      final restored = await authRestarted.getLockoutStatus();
      expect(restored.failedAttempts, 3);
      expect(restored.isCoolingDown, isTrue);
      expect(restored.remainingCooldownSeconds, 30);

      // Even the valid PIN is rejected while cooling down
      expect(await authRestarted.unlock('777888'), isFalse);

      // Advance clock past 30s cooldown -> valid PIN unlocks & resets counter
      now = now.add(const Duration(seconds: 31));
      expect((await authRestarted.getLockoutStatus()).isCoolingDown, isFalse);
      expect(await authRestarted.unlock('777888'), isTrue);

      final afterSuccess = await authRestarted.getLockoutStatus();
      expect(afterSuccess.failedAttempts, 0);
      expect(afterSuccess.remainingCooldownSeconds, 0);
    });

    test('applies progressive exponential cooldown on repeated brute-force tiers', () async {
      final store = InMemorySecureStore();
      DateTime now = DateTime.utc(2026, 11, 7, 12, 0, 0);
      final auth = AuthRepository(
        store: store,
        pbkdf2Iterations: testIterations,
        clock: () => now,
      );

      await auth.recordFailedAttempt(); // 1
      await auth.recordFailedAttempt(); // 2
      final tier1 = await auth.recordFailedAttempt(); // 3 -> 30s
      expect(tier1.remainingCooldownSeconds, 30);

      now = now.add(const Duration(seconds: 35));
      await auth.recordFailedAttempt(); // 4
      await auth.recordFailedAttempt(); // 5
      final tier2 = await auth.recordFailedAttempt(); // 6 -> 60s
      expect(tier2.remainingCooldownSeconds, 60);
    });
  });

  group('Low-level cryptographic primitives', () {
    test('unwrapVek rejects tampered envelope or wrong KEK via GCM MAC check', () {
      final vek = Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
      final kek = Uint8List.fromList(List<int>.generate(32, (i) => 200 - i));
      final wrongKek = Uint8List.fromList(List<int>.generate(32, (i) => 100 + i));

      final wrapped = AuthRepository.wrapVek(vek, kek);
      expect(AuthRepository.unwrapVek(wrapped, kek), equals(vek));
      expect(() => AuthRepository.unwrapVek(wrapped, wrongKek), throwsA(anything));

      final tampered = Uint8List.fromList(wrapped);
      tampered[tampered.length - 3] ^= 0xFF;
      expect(() => AuthRepository.unwrapVek(tampered, kek), throwsA(anything));
    });

    test('constantTimeEquals compares byte sequences accurately', () {
      expect(AuthRepository.constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(AuthRepository.constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(AuthRepository.constantTimeEquals([1, 2, 3], [1, 2]), isFalse);
    });
  });
}

