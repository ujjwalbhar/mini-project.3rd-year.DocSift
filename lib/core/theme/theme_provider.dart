import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _themeKey = 'theme_mode';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }

  final _storage = const FlutterSecureStorage();

  Future<void> _loadTheme() async {
    final value = await _storage.read(key: _themeKey);
    if (value == 'light') {
      state = ThemeMode.light;
    } else {
      state = ThemeMode.dark;
    }
  }

  Future<void> toggleTheme() async {
    final newMode =
        state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    state = newMode;
    await _storage.write(
      key: _themeKey,
      value: newMode == ThemeMode.light ? 'light' : 'dark',
    );
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    await _storage.write(
      key: _themeKey,
      value: mode == ThemeMode.light ? 'light' : 'dark',
    );
  }

  bool get isDark => state == ThemeMode.dark;
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeMode>(
  (ref) => ThemeNotifier(),
);
