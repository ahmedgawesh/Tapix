import 'dart:async';
import 'dart:ui';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tapix/core/bloc/localization_bloc.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
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
    test('initial state is RealtimeSuccess with default locale', () {
      final bloc = LocalizationBloc(mockLocalizationService);
      expect(bloc.state, isA<RealtimeSuccess<Locale>>());
      expect((bloc.state as RealtimeSuccess<Locale>).data, const Locale('en'));
    });

    blocTest<LocalizationBloc, RealtimeState<Locale>>(
      'emits new locale when stream updates',
      build: () => LocalizationBloc(mockLocalizationService),
      act: (bloc) => localeStreamController.add(const Locale('ar')),
      expect: () => [
        isA<RealtimeSuccess<Locale>>()
            .having((s) => s.data, 'data', const Locale('ar')),
      ],
    );

    blocTest<LocalizationBloc, RealtimeState<Locale>>(
      'calls setLocale on LocaleChanged event',
      build: () {
        when(mockLocalizationService.setLocale(any)).thenAnswer((_) async {});
        return LocalizationBloc(mockLocalizationService);
      },
      act: (bloc) => bloc.add(const LocaleChanged(Locale('fr'))),
      verify: (_) {
        verify(mockLocalizationService.setLocale(const Locale('fr'))).called(1);
      },
    );

    blocTest<LocalizationBloc, RealtimeState<Locale>>(
      'optimistic update works correctly',
      build: () {
        when(mockLocalizationService.setLocale(any)).thenAnswer((_) async {});
        return LocalizationBloc(mockLocalizationService);
      },
      seed: () => RealtimeSuccess(data: const Locale('en')),
      act: (bloc) => bloc.add(const LocaleChanged(Locale('ar'))),
      expect: () => [
        isA<RealtimeOptimistic<Locale>>()
            .having((s) => s.optimisticData, 'optimisticData', const Locale('ar')),
        isA<RealtimeSuccess<Locale>>()
            .having((s) => s.data, 'data', const Locale('ar')),
      ],
    );
  });
}
