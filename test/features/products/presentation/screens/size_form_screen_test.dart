import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/products/domain/entities/size_entity.dart';
import 'package:tapix/features/products/domain/repositories/size_repository.dart';
import 'package:tapix/features/products/presentation/bloc/sizes_bloc.dart';
import 'package:tapix/features/products/presentation/screens/size_form_screen.dart';

class MockSizeRepository extends Mock implements SizeRepository {}

class MockSizesBloc extends Mock implements SizesBloc {
  final MockSizeRepository mockRepository = MockSizeRepository();

  @override
  SizeRepository get repository => mockRepository;
}

class _FakeRealtimeEvent extends Fake implements RealtimeEvent {}

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
    when(() => mockBloc.state).thenReturn(const RealtimeLoading<List<Size>>());
    when(() => mockBloc.stream).thenAnswer((_) => Stream.value(const RealtimeLoading<List<Size>>()));
  });

  Widget createWidget({SizesBloc? bloc, int? sizeId}) {
    final effectiveBloc = bloc ?? mockBloc;
    final startLocation = sizeId == null ? '/products/sizes/new' : '/products/sizes/1';

    router = GoRouter(
      initialLocation: startLocation,
      routes: [
        GoRoute(
          path: '/products/sizes/new',
          builder: (context, state) => SizeFormScreen(bloc: effectiveBloc),
        ),
        GoRoute(
          path: '/products/sizes/1',
          builder: (context, state) => SizeFormScreen(sizeId: 1, bloc: effectiveBloc),
        ),
      ],
    );

    return EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      path: 'assets/translations',
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

  group('SizeFormScreen', () {
    testWidgets('renders form fields for new size', (WidgetTester tester) async {
      final successState = RealtimeSuccess<List<Size>>(data: []);
      when(() => mockBloc.state).thenReturn(successState);
      when(() => mockBloc.stream).thenAnswer((_) => Stream.value(successState));

      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.byType(Form), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(3)); // name, description, sort order
      // SwitchListTile only shows in edit mode, not new
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('sizes.name'), findsOneWidget);
      expect(find.text('sizes.description'), findsOneWidget);
      expect(find.text('sizes.sort_order'), findsOneWidget);
    });

    testWidgets('renders save and cancel buttons', (WidgetTester tester) async {
      final successState = RealtimeSuccess<List<Size>>(data: []);
      when(() => mockBloc.state).thenReturn(successState);
      when(() => mockBloc.stream).thenAnswer((_) => Stream.value(successState));

      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.text('sizes.save'), findsOneWidget);
      expect(find.text('sizes.cancel'), findsOneWidget);
    });

    testWidgets('populates form when editing existing size', (WidgetTester tester) async {
      const existingSize = Size(
        id: 1,
        name: 'Large',
        description: 'L',
        sortOrder: 4,
        isActive: true,
      );

      final successState = RealtimeSuccess<List<Size>>(data: []);
      when(() => mockBloc.state).thenReturn(successState);
      when(() => mockBloc.stream).thenAnswer((_) => Stream.value(successState));
      when(() => mockBloc.mockRepository.getSizeById(1)).thenAnswer((_) async => existingSize);

      await tester.pumpWidget(createWidget(sizeId: 1));
      await tester.pumpAndSettle();

      expect(find.text('Large'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      // SwitchListTile shows in edit mode
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('validates required fields', (WidgetTester tester) async {
      final successState = RealtimeSuccess<List<Size>>(data: []);
      when(() => mockBloc.state).thenReturn(successState);
      when(() => mockBloc.stream).thenAnswer((_) => Stream.value(successState));

      await tester.pumpWidget(createWidget());
      await tester.pump();

      // Clear the sort order field (default is '0') and name is already empty
      // Tap save to trigger validation
      await tester.tap(find.text('sizes.save'));
      await tester.pump();

      expect(find.text('sizes.name_required'), findsOneWidget);
    });

    testWidgets('cancel button is present and tappable', (WidgetTester tester) async {
      final successState = RealtimeSuccess<List<Size>>(data: []);
      when(() => mockBloc.state).thenReturn(successState);
      when(() => mockBloc.stream).thenAnswer((_) => Stream.value(successState));

      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.text('sizes.cancel'), findsOneWidget);
      // Verify it's an OutlinedButton
      expect(find.widgetWithText(OutlinedButton, 'sizes.cancel'), findsOneWidget);
    });
  });
}
