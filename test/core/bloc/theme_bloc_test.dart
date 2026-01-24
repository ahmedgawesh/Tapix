import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/bloc/theme_bloc.dart';
import 'package:tapix/core/services/theme_service.dart';

import 'theme_bloc_test.mocks.dart';

@GenerateMocks([ThemeService])
void main() {
  late MockThemeService mockThemeService;
  late StreamController<ThemeMode> themeStreamController;

  setUp(() {
    mockThemeService = MockThemeService();
    themeStreamController = StreamController<ThemeMode>.broadcast();

    when(mockThemeService.themeModeStream)
        .thenAnswer((_) => themeStreamController.stream);
    when(mockThemeService.getThemeMode()).thenReturn(ThemeMode.system);
  });

  tearDown(() {
    themeStreamController.close();
  });

  group('ThemeBloc', () {
    test('initial state is RealtimeSuccess with system theme', () {
      final bloc = ThemeBloc(mockThemeService);
      expect(bloc.state, isA<RealtimeSuccess<ThemeMode>>());
      expect((bloc.state as RealtimeSuccess<ThemeMode>).data, ThemeMode.system);
    });

    blocTest<ThemeBloc, RealtimeState<ThemeMode>>(
      'emits new theme when stream updates',
      build: () => ThemeBloc(mockThemeService),
      act: (bloc) => themeStreamController.add(ThemeMode.dark),
      expect: () => [
        isA<RealtimeSuccess<ThemeMode>>()
            .having((s) => s.data, 'data', ThemeMode.dark),
      ],
    );

    blocTest<ThemeBloc, RealtimeState<ThemeMode>>(
      'calls setThemeMode on ThemeChanged event',
      build: () {
        when(mockThemeService.setThemeMode(any)).thenAnswer((_) async {});
        return ThemeBloc(mockThemeService);
      },
      act: (bloc) => bloc.add(const ThemeChanged(ThemeMode.light)),
      verify: (_) {
        verify(mockThemeService.setThemeMode(ThemeMode.light)).called(1);
      },
    );

    blocTest<ThemeBloc, RealtimeState<ThemeMode>>(
      'optimistic update works correctly',
      build: () {
        when(mockThemeService.setThemeMode(any)).thenAnswer((_) async {});
        return ThemeBloc(mockThemeService);
      },
      seed: () => RealtimeSuccess(data: ThemeMode.system),
      act: (bloc) => bloc.add(const ThemeChanged(ThemeMode.dark)),
      expect: () => [
        isA<RealtimeOptimistic<ThemeMode>>()
            .having((s) => s.optimisticData, 'optimisticData', ThemeMode.dark),
        isA<RealtimeSuccess<ThemeMode>>()
            .having((s) => s.data, 'data', ThemeMode.dark),
      ],
    );
  });
}
