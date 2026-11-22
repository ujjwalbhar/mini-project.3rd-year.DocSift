import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final biometricsEnabledProvider =
    StateNotifierProvider<PersistedBoolNotifier, bool>((ref) {
  return PersistedBoolNotifier('docsift_biometrics_enabled', false);
});

final ocrProcessingEnabledProvider =
    StateNotifierProvider<PersistedBoolNotifier, bool>((ref) {
  return PersistedBoolNotifier('docsift_ocr_processing_enabled', true);
});

final autoLockTimerProvider =
    StateNotifierProvider<PersistedIntNotifier, int>((ref) {
  return PersistedIntNotifier('docsift_auto_lock_timer_mins', 1);
});

final vaultUserNameProvider =
    StateNotifierProvider<PersistedStringNotifier, String>((ref) {
  return PersistedStringNotifier('docsift_user_name', 'User');
});

// Anti-bruteforce: Max failed attempts before wiping the vault
final maxFailedAttemptsProvider =
    StateNotifierProvider<MaxFailedAttemptsNotifier, int>((ref) {
  return MaxFailedAttemptsNotifier();
});

class PersistedBoolNotifier extends StateNotifier<bool> {
  PersistedBoolNotifier(this._key, super.defaultValue) {
    _load();
  }

  final String _key;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_key)) {
      super.state = prefs.getBool(_key)!;
    }
  }

  @override
  set state(bool value) {
    super.state = value;
    SharedPreferences.getInstance().then((prefs) => prefs.setBool(_key, value));
  }

  Future<void> setEnabled(bool value) async {
    super.state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}

class PersistedIntNotifier extends StateNotifier<int> {
  PersistedIntNotifier(this._key, super.defaultValue) {
    _load();
  }

  final String _key;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_key)) {
      super.state = prefs.getInt(_key)!;
    }
  }

  @override
  set state(int value) {
    super.state = value;
    SharedPreferences.getInstance().then((prefs) => prefs.setInt(_key, value));
  }

  Future<void> setValue(int value) async {
    super.state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, value);
  }
}

class PersistedStringNotifier extends StateNotifier<String> {
  PersistedStringNotifier(this._key, super.defaultValue) {
    _load();
  }

  final String _key;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_key)) {
      final val = prefs.getString(_key);
      if (val != null && val.trim().isNotEmpty) {
        super.state = val;
      }
    }
  }

  @override
  set state(String value) {
    super.state = value;
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_key, value));
  }
}

class MaxFailedAttemptsNotifier extends StateNotifier<int> {
  MaxFailedAttemptsNotifier() : super(5) {
    _load();
  }

  static const _key = 'docsift_max_failed_attempts';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getInt(_key) ?? 5;
  }

  Future<void> setAttempts(int attempts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, attempts);
    state = attempts;
  }
}

