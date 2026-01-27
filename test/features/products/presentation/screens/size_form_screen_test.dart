import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/products/domain/entities/size_entity.dart';
import 'package:tapix/features/products/presentation/bloc/sizes_bloc.dart';
import 'package:tapix/features/products/presentation/screens/size_form_screen.dart';

class MockSizesBloc extends Mock implements SizesBloc {}

void main() {
  late MockSizesBloc mockBloc;
  late GoRouter router;

  setUp(() {
    mockBloc = MockSizesBloc();
    // Provide a default empty stream for watchAllSizes
    when(() => mockBloc.dataStream).thenAnswer((_) => Stream.value([]));
    when(() => mockBloc.state).thenReturn(const RealtimeLoading<List<Size>>());
    when(() => mockBloc.stream).thenAnswer((_) => Stream.value(const RealtimeLoading<List<Size>>()));
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/products/sizes/new',
          builder: (context, state) => SizeFormScreen(bloc: mockBloc),
        ),
        GoRoute(
          path: '/products/sizes/1',
          builder: (context, state) => SizeFormScreen(sizeId: 1, bloc: mockBloc),
        ),
      ],
    );
  });

  Widget createWidget({SizesBloc? bloc, int? sizeId}) {
    final effectiveBloc = bloc ?? mockBloc;
    final startLocation = sizeId == null ? '/products/sizes/new' : '/products/sizes/1';

    return EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('ar'), Locale('fr')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      child: MaterialApp.router(
        routerConfig: router,
        routeInformationProvider: PlatformRouteInformationProvider(
          initialRouteInformation: RouteInformation(uri: Uri.parse(startLocation)),
        ),
        builder: (context, child) => BlocProvider<SizesBloc>.value(
          value: effectiveBloc,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }

  group('SizeFormScreen', () {
    testWidgets('renders form fields for new size', (WidgetTester tester) async {
      when(() => mockBloc.state).thenReturn(RealtimeSuccess<List<Size>>(data: []));

      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.byType(Form), findsOneWidget);
      expect(find.byType(TextFormField), findsNWidgets(3)); // name, description, sort order
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(find.text('sizes.name'), findsOneWidget);
      expect(find.text('sizes.description'), findsOneWidget);
      expect(find.text('sizes.sort_order'), findsOneWidget);
      expect(find.text('sizes.is_active'), findsOneWidget);
    });

    testWidgets('renders save button', (WidgetTester tester) async {
      when(() => mockBloc.state).thenReturn(RealtimeSuccess<List<Size>>(data: []));

      await tester.pumpWidget(createWidget());
      await tester.pump();

      expect(find.text('common.save'), findsOneWidget);
      expect(find.text('common.cancel'), findsOneWidget);
    });

    testWidgets('populates form when editing existing size', (WidgetTester tester) async {
      const existingSize = Size(
        id: 1,
        name: 'Large',
        description: 'L',
        sortOrder: 4,
        isActive: true,
      );

      when(() => mockBloc.state).thenReturn(RealtimeSuccess<List<Size>>(data: []));
      when(() => mockBloc.repository.getSizeById(1)).thenAnswer((_) async => existingSize);

      await tester.pumpWidget(createWidget(sizeId: 1));
      await tester.pump();

      expect(find.text('Large'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('validates required fields', (WidgetTester tester) async {
      when(() => mockBloc.state).thenReturn(RealtimeSuccess<List<Size>>(data: []));

      await tester.pumpWidget(createWidget());
      await tester.pump();

      // Try to save without filling required fields
      await tester.tap(find.text('common.save'));
      await tester.pump();

      expect(find.text('sizes.name_required'), findsOneWidget);
    });

    testWidgets('navigates back when cancel pressed', (WidgetTester tester) async {
      when(() => mockBloc.state).thenReturn(RealtimeSuccess<List<Size>>(data: []));

      await tester.pumpWidget(createWidget());
      await tester.pump();

      await tester.tap(find.text('common.cancel'));
      await tester.pumpAndSettle();

      expect(router.routeInformationProvider.value.uri.path, '/');
    });
  });
}
