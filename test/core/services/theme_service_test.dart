import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/services/theme_service.dart';

import 'theme_service_test.mocks.dart';

@GenerateMocks([SharedPreferences])
void main() {
  late ThemeService themeService;
  late MockSharedPreferences mockSharedPreferences;

  setUp(() {
    mockSharedPreferences = MockSharedPreferences();
    themeService = ThemeService(mockSharedPreferences);
  });

  group('ThemeService', () {
    const themeKey = 'theme_mode';

    test('getThemeMode returns system when no preference is saved', () {
      when(mockSharedPreferences.getString(themeKey)).thenReturn(null);

      final result = themeService.getThemeMode();

      expect(result, ThemeMode.system);
      verify(mockSharedPreferences.getString(themeKey)).called(1);
    });

    test('getThemeMode returns light when light is saved', () {
      when(mockSharedPreferences.getString(themeKey)).thenReturn('light');

      final result = themeService.getThemeMode();

      expect(result, ThemeMode.light);
      verify(mockSharedPreferences.getString(themeKey)).called(1);
    });

    test('getThemeMode returns dark when dark is saved', () {
      when(mockSharedPreferences.getString(themeKey)).thenReturn('dark');

      final result = themeService.getThemeMode();

      expect(result, ThemeMode.dark);
      verify(mockSharedPreferences.getString(themeKey)).called(1);
    });

    test('setThemeMode saves light theme', () async {
      when(mockSharedPreferences.setString(themeKey, 'light'))
          .thenAnswer((_) async => true);

      await themeService.setThemeMode(ThemeMode.light);

      verify(mockSharedPreferences.setString(themeKey, 'light')).called(1);
    });

    test('setThemeMode saves dark theme', () async {
      when(mockSharedPreferences.setString(themeKey, 'dark'))
          .thenAnswer((_) async => true);

      await themeService.setThemeMode(ThemeMode.dark);

      verify(mockSharedPreferences.setString(themeKey, 'dark')).called(1);
    });

    test('setThemeMode saves system theme', () async {
      when(mockSharedPreferences.setString(themeKey, 'system'))
          .thenAnswer((_) async => true);

      await themeService.setThemeMode(ThemeMode.system);

      verify(mockSharedPreferences.setString(themeKey, 'system')).called(1);
    });

    test('themeModeStream emits updates', () async {
      when(mockSharedPreferences.setString(themeKey, 'dark'))
          .thenAnswer((_) async => true);

      expectLater(
        themeService.themeModeStream,
        emitsInOrder([ThemeMode.dark]),
      );

      await themeService.setThemeMode(ThemeMode.dark);
    });

    test('dispose closes the stream', () async {
      await themeService.dispose();
      expect(themeService.themeModeStream, emitsDone);
    });
  });
}
