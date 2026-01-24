import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeService {
  final SharedPreferences _prefs;
  static const String _themeKey = 'theme_mode';
  final _themeController = StreamController<ThemeMode>.broadcast();

  ThemeService(this._prefs);

  Stream<ThemeMode> get themeModeStream => _themeController.stream;

  ThemeMode getThemeMode() {
    final themeString = _prefs.getString(_themeKey);
    switch (themeString) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    String themeString;
    switch (mode) {
      case ThemeMode.light:
        themeString = 'light';
        break;
      case ThemeMode.dark:
        themeString = 'dark';
        break;
      case ThemeMode.system:
        themeString = 'system';
        break;
    }
    await _prefs.setString(_themeKey, themeString);
    _themeController.add(mode);
  }

  Future<void> dispose() async {
    await _themeController.close();
  }
}
