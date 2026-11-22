import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pointycastle/export.dart';

const _pinHashKey = 'docsift_pin_hash';
const _pinSaltKey = 'docsift_pin_salt';
const _kdfVersionKey = 'docsift_kdf_version';
const _wrappedVekKey = 'docsift_wrapped_vek';
const _biometricVekKey = 'docsift_biometric_vek';
const _legacyVekKey = 'docsift_vault_key';
const _failedAttemptsKey = 'docsift_failed_pin_attempts';
const _cooldownUntilMsKey = 'docsift_cooldown_until_ms';

/// Storage abstraction over hardware-backed Keystore / Keychain to allow
/// deterministic security unit testing without platform channels.
abstract interface class SecureKeyValueStore {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
  Future<void> deleteAll();
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  const FlutterSecureKeyValueStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'docsift_secure_prefs',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

class InMemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> _data = <String, String>{};

  bool containsKey(String key) => _data.containsKey(key);

  @override
  Future<String?> read({required String key}) async => _data[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _data[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _data.clear();
  }
}

class LockoutStatus {
  const LockoutStatus({
    required this.failedAttempts,
    required this.remainingCooldownSeconds,
  });

  final int failedAttempts;
  final int remainingCooldownSeconds;

  bool get isCoolingDown => remainingCooldownSeconds > 0;
}

class _DerivedPinKeys {
  const _DerivedPinKeys({
    required this.authVerifier,
    required this.kek,
  });

  final Uint8List authVerifier; // 32 bytes — PIN authentication verifier
  final Uint8List kek; // 32 bytes — AES-256-GCM Key-Encryption Key
}

class AuthRepository {
  AuthRepository({
    SecureKeyValueStore? store,
    LocalAuthentication? localAuth,
    this.pbkdf2Iterations = defaultPbkdf2Iterations,
    DateTime Function()? clock,
  })  : _store = store ?? const FlutterSecureKeyValueStore(),
        _localAuth = localAuth ?? LocalAuthentication(),
        _clock = clock ?? DateTime.now;

  static const int defaultPbkdf2Iterations = 100000;

  final SecureKeyValueStore _store;
  final LocalAuthentication _localAuth;
  final int pbkdf2Iterations;
  final DateTime Function() _clock;

  bool _isLocked = true;
  bool _hasPinConfiguredSync = false;
  Uint8List? _vek; // Vault Encryption Key — held in RAM only while unlocked
  bool isBypassAutoLock = false; // Prevents auto-lock during system pickers

  bool get isLocked => _isLocked;
  bool get hasPinConfiguredSync => _hasPinConfiguredSync;

  /// Returns a defensive copy of the 256-bit VEK while unlocked, or `null` when locked.
  List<int>? get vaultEncryptionKey =>
      _isLocked || _vek == null ? null : Uint8List.fromList(_vek!);

  Future<bool> isPinSetup() async {
    final hash = await _store.read(key: _pinHashKey);
    final configured = hash != null && hash.isNotEmpty;
    _hasPinConfiguredSync = configured;
    return configured;
  }

  /// Initial vault PIN creation (onboarding). Derives a 512-bit master secret
  /// via PBKDF2-HMAC-SHA256, wraps the 256-bit VEK with AES-256-GCM under the
  /// derived KEK, and unlocks the vault.
  Future<void> setupPin(String pin) async {
    final salt = _generateRandomBytes(32);
    final derived = await _derivePinKeysAsync(pin, salt, pbkdf2Iterations);

    // Preserve existing VEK if present in memory or storage
    Uint8List vek;
    if (_vek != null && _vek!.length == 32) {
      vek = Uint8List.fromList(_vek!);
    } else {
      final bioVekB64 = await _store.read(key: _biometricVekKey) ??
          await _store.read(key: _legacyVekKey);
      if (bioVekB64 != null && bioVekB64.isNotEmpty) {
        vek = Uint8List.fromList(base64Decode(bioVekB64));
      } else {
        vek = _generateRandomBytes(32);
      }
    }

    final wrappedVek = wrapVek(vek, derived.kek);
    _wipeBytes(derived.kek);

    await _store.write(key: _pinSaltKey, value: base64Encode(salt));
    await _store.write(key: _pinHashKey, value: base64Encode(derived.authVerifier));
    await _store.write(key: _kdfVersionKey, value: '2');
    await _store.write(key: _wrappedVekKey, value: base64Encode(wrappedVek));
    await _store.delete(key: _legacyVekKey);
    await resetFailedAttempts();

    // Sync biometric VEK slot if biometrics was already enabled
    final existingBio = await _store.read(key: _biometricVekKey);
    if (existingBio != null && existingBio.isNotEmpty) {
      await _store.write(key: _biometricVekKey, value: base64Encode(vek));
    }

    _vek = vek;
    _isLocked = false;
    _hasPinConfiguredSync = true;
  }

  /// Verifies [pin] against the stored verifier without altering lock state.
  Future<bool> verifyCurrentPin(String pin) async {
    final saltB64 = await _store.read(key: _pinSaltKey);
    final storedHashB64 = await _store.read(key: _pinHashKey);
    if (saltB64 == null || storedHashB64 == null) return false;

    final kdfVer = await _store.read(key: _kdfVersionKey);
    final salt = Uint8List.fromList(base64Decode(saltB64));
    final storedVerifier = base64Decode(storedHashB64);

    if (kdfVer == '2') {
      final derived = await _derivePinKeysAsync(pin, salt, pbkdf2Iterations);
      _wipeBytes(derived.kek);
      return constantTimeEquals(derived.authVerifier, storedVerifier);
    } else {
      final legacyB64 = await _hashLegacyPinAsync(pin, salt);
      return constantTimeEquals(base64Decode(legacyB64), storedVerifier);
    }
  }

  /// Verifies [pin], unwraps the AES-256-GCM VEK into RAM, resets the persistent
  /// brute-force counter, and unlocks the vault. Automatically upgrades v1
  /// vaults to PBKDF2-HMAC-SHA256 + envelope-wrapped VEK on first unlock.
  Future<bool> unlock(String pin) async {
    final lockout = await getLockoutStatus();
    if (lockout.isCoolingDown) {
      return false;
    }

    final saltB64 = await _store.read(key: _pinSaltKey);
    final storedHashB64 = await _store.read(key: _pinHashKey);
    if (saltB64 == null || storedHashB64 == null) {
      return false;
    }

    _hasPinConfiguredSync = true;
    final kdfVer = await _store.read(key: _kdfVersionKey);
    final salt = Uint8List.fromList(base64Decode(saltB64));
    final storedVerifier = base64Decode(storedHashB64);

    if (kdfVer == '2') {
      final wrappedB64 = await _store.read(key: _wrappedVekKey);
      if (wrappedB64 == null || wrappedB64.isEmpty) return false;

      final derived = await _derivePinKeysAsync(pin, salt, pbkdf2Iterations);
      try {
        if (!constantTimeEquals(derived.authVerifier, storedVerifier)) {
          return false;
        }
        final unwrapped = unwrapVek(base64Decode(wrappedB64), derived.kek);
        _vek = unwrapped;
        _isLocked = false;
        await resetFailedAttempts();
        return true;
      } catch (_) {
        return false;
      } finally {
        _wipeBytes(derived.kek);
      }
    }

    // Legacy v1 vault migration path
    final legacyVekB64 = await _store.read(key: _legacyVekKey);
    if (legacyVekB64 == null) return false;

    final legacyHashB64 = await _hashLegacyPinAsync(pin, salt);
    if (!constantTimeEquals(base64Decode(legacyHashB64), storedVerifier)) {
      return false;
    }

    // Transparently upgrade v1 -> v2 PBKDF2-HMAC-SHA256 + wrapped VEK
    final migratedVek = Uint8List.fromList(base64Decode(legacyVekB64));
    final newSalt = _generateRandomBytes(32);
    final derived = await _derivePinKeysAsync(pin, newSalt, pbkdf2Iterations);
    final wrapped = wrapVek(migratedVek, derived.kek);
    _wipeBytes(derived.kek);

    await _store.write(key: _pinSaltKey, value: base64Encode(newSalt));
    await _store.write(key: _pinHashKey, value: base64Encode(derived.authVerifier));
    await _store.write(key: _kdfVersionKey, value: '2');
    await _store.write(key: _wrappedVekKey, value: base64Encode(wrapped));
    await _store.delete(key: _legacyVekKey);
    await resetFailedAttempts();

    _vek = migratedVek;
    _isLocked = false;
    return true;
  }

  /// Enables or disables hardware-keystore biometric unlock. When disabled,
  /// immediately scrubs any biometric VEK material from secure storage so the
  /// VEK exists solely inside the PIN-wrapped envelope.
  Future<bool> setBiometricUnlockEnabled(bool enabled) async {
    if (!enabled) {
      await _store.delete(key: _biometricVekKey);
      await _store.delete(key: _legacyVekKey);
      return true;
    }
    if (_isLocked || _vek == null) {
      return false;
    }
    await _store.write(key: _biometricVekKey, value: base64Encode(_vek!));
    return true;
  }

  /// Verifies strict biometric hardware authentication (`biometricOnly: true`)
  /// and loads the biometric-escrowed VEK if enabled and not in cooldown.
  Future<bool> unlockWithBiometrics(String reason) async {
    final lockout = await getLockoutStatus();
    if (lockout.isCoolingDown) return false;

    final bioVekB64 = await _store.read(key: _biometricVekKey);
    if (bioVekB64 == null || bioVekB64.isEmpty) {
      return false;
    }

    isBypassAutoLock = true;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (!canCheck || !isSupported) return false;

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (didAuthenticate) {
        _vek = Uint8List.fromList(base64Decode(bioVekB64));
        _isLocked = false;
        _hasPinConfiguredSync = true;
        await resetFailedAttempts();
        return true;
      }
    } catch (_) {
      // Ignore user cancellation or platform biometric errors
    } finally {
      isBypassAutoLock = false;
    }
    return false;
  }

  /// Changes PIN after verifying [currentPin] in constant time and re-wrapping
  /// the existing VEK under the new PIN's KEK without re-encrypting vault files.
  Future<bool> changePin(String currentPin, String newPin) async {
    Uint8List? activeVek =
        (!_isLocked && _vek != null) ? Uint8List.fromList(_vek!) : null;

    if (activeVek != null) {
      final ok = await verifyCurrentPin(currentPin);
      if (!ok) {
        _wipeBytes(activeVek);
        return false;
      }
    } else {
      final ok = await unlock(currentPin);
      if (!ok || _vek == null) return false;
      activeVek = Uint8List.fromList(_vek!);
    }

    final newSalt = _generateRandomBytes(32);
    final derived = await _derivePinKeysAsync(newPin, newSalt, pbkdf2Iterations);
    final rewrapped = wrapVek(activeVek, derived.kek);
    _wipeBytes(derived.kek);

    await _store.write(key: _pinSaltKey, value: base64Encode(newSalt));
    await _store.write(
        key: _pinHashKey, value: base64Encode(derived.authVerifier));
    await _store.write(key: _kdfVersionKey, value: '2');
    await _store.write(key: _wrappedVekKey, value: base64Encode(rewrapped));
    await resetFailedAttempts();

    _vek = activeVek;
    _isLocked = false;
    _hasPinConfiguredSync = true;
    return true;
  }

  /// Adopts a 256-bit [restoredVek] recovered from an authenticated `.docsift`
  /// backup archive, wrapping it under [currentPin]'s PBKDF2-derived KEK and
  /// syncing the biometric escrow slot according to [biometricsEnabled].
  Future<bool> adoptRestoredVek(
    Uint8List restoredVek, {
    required String currentPin,
    required bool biometricsEnabled,
  }) async {
    if (restoredVek.length != 32) {
      throw ArgumentError('Restored VEK must be 32 bytes (256 bits).');
    }
    final validPin = await verifyCurrentPin(currentPin);
    if (!validPin) {
      return false;
    }

    final newVek = Uint8List.fromList(restoredVek);
    final newSalt = _generateRandomBytes(32);
    final derived =
        await _derivePinKeysAsync(currentPin, newSalt, pbkdf2Iterations);
    final wrapped = wrapVek(newVek, derived.kek);
    _wipeBytes(derived.kek);

    await _store.write(key: _pinSaltKey, value: base64Encode(newSalt));
    await _store.write(
        key: _pinHashKey, value: base64Encode(derived.authVerifier));
    await _store.write(key: _kdfVersionKey, value: '2');
    await _store.write(key: _wrappedVekKey, value: base64Encode(wrapped));
    await _store.delete(key: _legacyVekKey);
    if (biometricsEnabled) {
      await _store.write(key: _biometricVekKey, value: base64Encode(newVek));
    } else {
      await _store.delete(key: _biometricVekKey);
    }
    await resetFailedAttempts();

    if (_vek != null) {
      _wipeBytes(_vek!);
    }
    _vek = newVek;
    _isLocked = false;
    _hasPinConfiguredSync = true;
    return true;
  }

  /// Reads persistent failed-attempt count & active cooldown remaining seconds
  /// from secure storage (survives app force-close and device reboot).
  Future<LockoutStatus> getLockoutStatus() async {
    final rawAttempts = await _store.read(key: _failedAttemptsKey);
    final rawCooldownMs = await _store.read(key: _cooldownUntilMsKey);

    final attempts = int.tryParse(rawAttempts ?? '') ?? 0;
    final untilMs = int.tryParse(rawCooldownMs ?? '') ?? 0;
    final nowMs = _clock().millisecondsSinceEpoch;
    final remainingSec =
        untilMs > nowMs ? ((untilMs - nowMs + 999) ~/ 1000) : 0;

    return LockoutStatus(
      failedAttempts: attempts,
      remainingCooldownSeconds: remainingSec,
    );
  }

  /// Atomically increments persistent failed PIN attempts and applies a
  /// progressive cooldown (`30s`, `60s`, `120s`, ...) every [cooldownEvery] tries.
  Future<LockoutStatus> recordFailedAttempt({
    int cooldownEvery = 3,
    int baseCooldownSeconds = 30,
  }) async {
    final current = await getLockoutStatus();
    final nextAttempts = current.failedAttempts + 1;
    await _store.write(
        key: _failedAttemptsKey, value: nextAttempts.toString());

    int cooldownSec = 0;
    if (cooldownEvery > 0 && nextAttempts % cooldownEvery == 0) {
      final tier = (nextAttempts ~/ cooldownEvery) - 1;
      final multiplier = 1 << tier.clamp(0, 4); // 1x, 2x, 4x, 8x, 16x
      cooldownSec = baseCooldownSeconds * multiplier;
      final untilMs =
          _clock().millisecondsSinceEpoch + (cooldownSec * 1000);
      await _store.write(
          key: _cooldownUntilMsKey, value: untilMs.toString());
    }

    return LockoutStatus(
      failedAttempts: nextAttempts,
      remainingCooldownSeconds: cooldownSec,
    );
  }

  /// Clears persistent failed-attempt counter and cooldown timer.
  Future<void> resetFailedAttempts() async {
    await _store.delete(key: _failedAttemptsKey);
    await _store.delete(key: _cooldownUntilMsKey);
  }

  /// Locks the vault, zeroes the VEK in RAM, and scrubs the system clipboard.
  void lock() {
    if (_vek != null) {
      _wipeBytes(_vek!);
      _vek = null;
    }
    _isLocked = true;
    try {
      Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {}
  }

  /// Permanently deletes all auth keys, verifiers, and VEK material.
  Future<void> destroyVault() async {
    await _store.deleteAll();
    _hasPinConfiguredSync = false;
    lock();
  }

  // --- Pure cryptographic helpers (visible for testing) ---

  /// Constant-time byte comparison to prevent timing side-channels.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= (a[i] ^ b[i]);
    }
    return diff == 0;
  }

  /// Wraps 256-bit [vek] under 256-bit [kek] using AES-256-GCM (`12B IV + CT + 16B tag`).
  static Uint8List wrapVek(Uint8List vek, Uint8List kek) {
    final rng = Random.secure();
    final iv = Uint8List.fromList(
        List<int>.generate(12, (_) => rng.nextInt(256)));
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(kek),
          128,
          iv,
          Uint8List.fromList(utf8.encode('docsift-vek-v2')),
        ),
      );
    final ctAndTag = cipher.process(vek);
    final out = Uint8List(iv.length + ctAndTag.length);
    out.setRange(0, iv.length, iv);
    out.setRange(iv.length, out.length, ctAndTag);
    return out;
  }

  /// Unwraps AES-256-GCM wrapped VEK using [kek]; throws on tampered MAC or wrong KEK.
  static Uint8List unwrapVek(Uint8List wrapped, Uint8List kek) {
    if (wrapped.length < 28) {
      throw const FormatException('Invalid wrapped VEK envelope');
    }
    final iv = wrapped.sublist(0, 12);
    final ctAndTag = wrapped.sublist(12);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(kek),
          128,
          iv,
          Uint8List.fromList(utf8.encode('docsift-vek-v2')),
        ),
      );
    return cipher.process(ctAndTag);
  }

  static Uint8List _generateRandomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
        List<int>.generate(length, (_) => rng.nextInt(256)));
  }

  static void _wipeBytes(List<int> bytes) {
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }

  static Future<_DerivedPinKeys> _derivePinKeysAsync(
    String pin,
    Uint8List salt,
    int iterations,
  ) {
    final saltCopy = Uint8List.fromList(salt);
    return Isolate.run(() => _derivePbkdf2Keys(pin, saltCopy, iterations));
  }

  static _DerivedPinKeys _derivePbkdf2Keys(
    String pin,
    Uint8List salt,
    int iterations,
  ) {
    // NIST SP 800-132 PBKDF2-HMAC-SHA256 deriving 64 bytes (32B verifier + 32B KEK)
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 64));
    final pinBytes = Uint8List.fromList(utf8.encode(pin));
    final master = derivator.process(pinBytes);
    for (int i = 0; i < pinBytes.length; i++) {
      pinBytes[i] = 0;
    }
    final verifier = Uint8List.fromList(master.sublist(0, 32));
    final kek = Uint8List.fromList(master.sublist(32, 64));
    for (int i = 0; i < master.length; i++) {
      master[i] = 0;
    }
    return _DerivedPinKeys(authVerifier: verifier, kek: kek);
  }

  static Future<String> _hashLegacyPinAsync(String pin, List<int> salt) {
    final saltCopy = List<int>.from(salt);
    return Isolate.run(() => _computeLegacyPinHash(pin, saltCopy));
  }

  static String _computeLegacyPinHash(String pin, List<int> salt) {
    List<int> derived = utf8.encode(pin) + salt;
    for (int i = 0; i < 100000; i++) {
      derived = sha256.convert(derived).bytes;
    }
    return base64Encode(derived);
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);
