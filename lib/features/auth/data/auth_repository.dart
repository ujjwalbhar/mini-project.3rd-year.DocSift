import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';
import 'dart:convert';
import 'dart:math';

const _pinHashKey = 'docsift_pin_hash';
const _pinSaltKey = 'docsift_pin_salt';
const _vekKey = 'docsift_vault_key';

class AuthRepository {
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'docsift_secure_prefs',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  final LocalAuthentication _localAuth = LocalAuthentication();

  bool _isLocked = true;
  List<int>? _vek; // Vault Encryption Key — in memory only
  bool isBypassAutoLock = false; // Prevents auto-lock during file picker

  bool get isLocked => _isLocked;
  List<int>? get vaultEncryptionKey => _isLocked ? null : _vek;

  Future<bool> isPinSetup() async {
    final hash = await _storage.read(key: _pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  /// Sets PIN for the first time. Generates VEK and stores salt + hash.
  Future<void> setupPin(String pin) async {
    // Generate random salt
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);

    // Generate Vault Encryption Key (32 random bytes)
    final vek = _generateVek();

    await _storage.write(key: _pinSaltKey, value: base64Encode(salt));
    await _storage.write(key: _pinHashKey, value: hash);
    await _storage.write(key: _vekKey, value: base64Encode(vek));

    // Unlock immediately after setup
    _vek = vek;
    _isLocked = false;
  }

  /// Verifies PIN and unlocks the vault if correct. Returns true on success.
  Future<bool> unlock(String pin) async {
    final saltB64 = await _storage.read(key: _pinSaltKey);
    final storedHash = await _storage.read(key: _pinHashKey);
    final vekB64 = await _storage.read(key: _vekKey);

    if (saltB64 == null || storedHash == null || vekB64 == null) {
      return false;
    }

    final salt = base64Decode(saltB64);
    final inputHash = _hashPin(pin, salt);

    if (inputHash != storedHash) {
      return false;
    }

    // Load VEK into memory
    _vek = base64Decode(vekB64);
    _isLocked = false;
    return true;
  }

  /// Verifies biometrics and unlocks the vault if successful. Returns true on success.
  Future<bool> unlockWithBiometrics(String reason) async {
    try {
      final canAuthenticate = await _localAuth.canCheckBiometrics ||
          await _localAuth.isDeviceSupported();

      if (!canAuthenticate) return false;

      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      if (didAuthenticate) {
        final vekB64 = await _storage.read(key: _vekKey);
        if (vekB64 != null) {
          _vek = base64Decode(vekB64);
          _isLocked = false;
          return true;
        }
      }
    } catch (e) {
      // Ignore auth errors or cancellation
    }
    return false;
  }

  /// Locks the vault and wipes VEK from memory.
  void lock() {
    if (_vek != null) {
      // Wipe memory
      for (int i = 0; i < _vek!.length; i++) {
        _vek![i] = 0;
      }
      _vek = null;
    }
    _isLocked = true;
  }

  /// Changes PIN. Requires current PIN verification.
  Future<bool> changePin(String currentPin, String newPin) async {
    final isValid = await unlock(currentPin);
    if (!isValid) return false;

    final salt = _generateSalt();
    final hash = _hashPin(newPin, salt);
    await _storage.write(key: _pinSaltKey, value: base64Encode(salt));
    await _storage.write(key: _pinHashKey, value: hash);
    return true;
  }

  /// Permanently deletes all auth data and VEK (destroy vault).
  Future<void> destroyVault() async {
    await _storage.deleteAll();
    lock();
  }

  // --- Private helpers ---

  List<int> _generateSalt() {
    final rng = Random.secure();
    return List<int>.generate(32, (_) => rng.nextInt(256));
  }

  List<int> _generateVek() {
    final rng = Random.secure();
    return List<int>.generate(32, (_) => rng.nextInt(256));
  }

  String _hashPin(String pin, List<int> salt) {
    // PBKDF2-like: SHA-256 with salt, 100k iterations for brute-force resistance
    // Note: Use argon2_flutter when available; this is a fallback
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
