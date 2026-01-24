import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/services/localization_service.dart';

import 'localization_service_test.mocks.dart';

@GenerateMocks([SharedPreferences])
void main() {
  late LocalizationService localizationService;
  late MockSharedPreferences mockSharedPreferences;

  setUp(() {
    mockSharedPreferences = MockSharedPreferences();
    localizationService = LocalizationService(mockSharedPreferences);
  });

  group('LocalizationService', () {
    const localeKey = 'locale_code';

    test('getLocale returns default (en) when no preference is saved', () {
      when(mockSharedPreferences.getString(localeKey)).thenReturn(null);

      final result = localizationService.getLocale();

      expect(result, const Locale('en'));
      verify(mockSharedPreferences.getString(localeKey)).called(1);
    });

    test('getLocale returns saved locale', () {
      when(mockSharedPreferences.getString(localeKey)).thenReturn('ar');

      final result = localizationService.getLocale();

      expect(result, const Locale('ar'));
      verify(mockSharedPreferences.getString(localeKey)).called(1);
    });

    test('setLocale saves locale and emits update', () async {
      when(mockSharedPreferences.setString(localeKey, 'fr'))
          .thenAnswer((_) async => true);

      expectLater(
        localizationService.localeStream,
        emitsInOrder([const Locale('fr')]),
      );

      await localizationService.setLocale(const Locale('fr'));

      verify(mockSharedPreferences.setString(localeKey, 'fr')).called(1);
    });

    test('dispose closes the stream', () async {
      await localizationService.dispose();
      expect(localizationService.localeStream, emitsDone);
    });
    
    test('isRTL returns true for Arabic', () {
      expect(localizationService.isRTL(const Locale('ar')), true);
    });

    test('isRTL returns false for English and French', () {
      expect(localizationService.isRTL(const Locale('en')), false);
      expect(localizationService.isRTL(const Locale('fr')), false);
    });
  });
}
