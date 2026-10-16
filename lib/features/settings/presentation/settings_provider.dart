import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final biometricsEnabledProvider = StateProvider<bool>((ref) => false);
final ocrProcessingEnabledProvider = StateProvider<bool>((ref) => true);
final autoLockTimerProvider = StateProvider<int>((ref) => 1);

// Anti-bruteforce: Max failed attempts before wiping the vault
final maxFailedAttemptsProvider = StateNotifierProvider<MaxFailedAttemptsNotifier, int>((ref) {
  return MaxFailedAttemptsNotifier();
});

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

