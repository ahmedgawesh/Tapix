import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:mocktail/mocktail.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/products/domain/entities/size_entity.dart';
import 'package:tapix/features/products/presentation/bloc/sizes_bloc.dart';
import 'package:tapix/features/products/presentation/screens/sizes_screen.dart';

class MockSizesBloc extends Mock implements SizesBloc {}

class _FakeRealtimeEvent extends Fake implements RealtimeEvent {}

class _TestAssetLoader extends AssetLoader {
  const _TestAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    return <String, dynamic>{};
  }
}

void main() {
  late MockSizesBloc mockBloc;
  late GoRouter router;

  setUpAll(() {
    registerFallbackValue(_FakeRealtimeEvent());
  });

  setUp(() {
    mockBloc = MockSizesBloc();
    // Provide a default empty stream for watchAllSizes
    when(() => mockBloc.dataStream).thenAnswer((_) => Stream.value([]));
    when(() => mockBloc.add(any())).thenReturn(null);
    when(() => mockBloc.getProductCounts(any())).thenAnswer((_) async => {});
    when(() => mockBloc.state).thenReturn(const RealtimeLoading<List<Size>>());
    when(
      () => mockBloc.stream,
    ).thenAnswer((_) => Stream.value(const RealtimeLoading<List<Size>>()));
    router = GoRouter(
      initialLocation: '/products/sizes',
      routes: [
        GoRoute(
          path: '/products/sizes',
          builder: (context, state) => SizesScreen(bloc: mockBloc),
        ),
        GoRoute(
          path: '/products/sizes/new',
          builder: (context, state) => const SizedBox.shrink(),
        ),
      ],
    );
  });

  Widget createWidget({SizesBloc? bloc}) {
    final effectiveBloc = bloc ?? mockBloc;
    return EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      path: 'assets/translations',
      assetLoader: const _TestAssetLoader(),
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => BlocProvider<SizesBloc>.value(
          value: effectiveBloc,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  group('SizesScreen', () {
    testWidgets('renders loading state', (WidgetTester tester) async {
      when(
        () => mockBloc.state,
      ).thenReturn(const RealtimeLoading<List<Size>>());

      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders empty state when no sizes', (
      WidgetTester tester,
    ) async {
      final successState = RealtimeSuccess<List<Size>>(data: []);
      when(() => mockBloc.state).thenReturn(successState);
      when(() => mockBloc.stream).thenAnswer((_) => Stream.value(successState));

      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.byIcon(LucideIcons.ruler), findsOneWidget);
      expect(find.text('sizes.no_sizes'), findsOneWidget);
      expect(find.text('sizes.add_first_size'), findsOneWidget);
    });

    testWidgets('renders size list when sizes exist', (
      WidgetTester tester,
    ) async {
      // Use a large screen to avoid RenderFlex overflow in the list tile Row
      tester.view.physicalSize = const ui.Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final sizes = [
        const Size(
          id: 1,
          name: 'Small',
          description: 'S',
          sortOrder: 1,
          isActive: true,
        ),
        const Size(
          id: 2,
          name: 'Medium',
          description: 'M',
          sortOrder: 2,
          isActive: true,
        ),
      ];

      final successState = RealtimeSuccess<List<Size>>(data: sizes);
      when(() => mockBloc.state).thenReturn(successState);
      when(() => mockBloc.stream).thenAnswer((_) => Stream.value(successState));

      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.text('Small'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
    });

    testWidgets('shows error message when in error state', (
      WidgetTester tester,
    ) async {
      final errorState = RealtimeError<List<Size>>(error: 'Test error');
      when(() => mockBloc.state).thenReturn(errorState);
      when(() => mockBloc.stream).thenAnswer((_) => Stream.value(errorState));

      await tester.pumpWidget(createWidget());
      await tester.pump();

      // Error should be shown via SnackBar
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Test error'), findsOneWidget);
    });

    testWidgets('has add button in empty state', (WidgetTester tester) async {
      final successState = RealtimeSuccess<List<Size>>(data: []);
      when(() => mockBloc.state).thenReturn(successState);
      when(() => mockBloc.stream).thenAnswer((_) => Stream.value(successState));

      await tester.pumpWidget(createWidget());
      await tester.pump();

      // Verify the "add first size" button is present and tappable
      expect(find.text('sizes.add_first_size'), findsOneWidget);
      // Verify the AppBar plus button is also present
      expect(find.byIcon(LucideIcons.plus), findsWidgets);
    });
  });
}
