import 'dart:async';
import 'dart:ui';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tapix/core/bloc/localization_bloc.dart';
import 'package:tapix/core/services/localization_service.dart';

import 'localization_bloc_test.mocks.dart';

@GenerateMocks([LocalizationService])
void main() {
  late MockLocalizationService mockLocalizationService;
  late StreamController<Locale> localeStreamController;

  setUp(() {
    mockLocalizationService = MockLocalizationService();
    localeStreamController = StreamController<Locale>.broadcast();

    when(mockLocalizationService.localeStream)
        .thenAnswer((_) => localeStreamController.stream);
    when(mockLocalizationService.getLocale()).thenReturn(const Locale('en'));
  });

  tearDown(() {
    localeStreamController.close();
  });

  group('LocalizationBloc', () {
    test('initial state is LocalizationReady with default locale', () {
      final bloc = LocalizationBloc(mockLocalizationService);
      expect(bloc.state, isA<LocalizationReady>());
      expect(bloc.state.locale, const Locale('en'));
    });

    blocTest<LocalizationBloc, LocalizationState>(
      'emits new locale when stream updates with different locale',
      build: () => LocalizationBloc(mockLocalizationService),
      act: (bloc) => localeStreamController.add(const Locale('ar')),
      expect: () => [
        isA<LocalizationReady>()
            .having((s) => s.locale, 'locale', const Locale('ar')),
      ],
    );

    blocTest<LocalizationBloc, LocalizationState>(
      'emits locale immediately on LocaleChanged and calls setLocale',
      build: () {
        when(mockLocalizationService.setLocale(any)).thenAnswer((_) async {});
        return LocalizationBloc(mockLocalizationService);
      },
      act: (bloc) => bloc.add(const LocaleChanged(Locale('fr'))),
      expect: () => [
        isA<LocalizationReady>()
            .having((s) => s.locale, 'locale', const Locale('fr')),
      ],
      verify: (_) {
        verify(mockLocalizationService.setLocale(const Locale('fr'))).called(1);
      },
    );

    blocTest<LocalizationBloc, LocalizationState>(
      'ignores stream update with same locale as current',
      build: () {
        when(mockLocalizationService.setLocale(any)).thenAnswer((_) async {});
        return LocalizationBloc(mockLocalizationService);
      },
      act: (bloc) {
        // Change to ar, then stream echoes ar — should not emit twice
        bloc.add(const LocaleChanged(Locale('ar')));
        localeStreamController.add(const Locale('ar'));
      },
      expect: () => [
        isA<LocalizationReady>()
            .having((s) => s.locale, 'locale', const Locale('ar')),
        // Stream echo of 'ar' is ignored because it matches current
      ],
    );
  });
}
