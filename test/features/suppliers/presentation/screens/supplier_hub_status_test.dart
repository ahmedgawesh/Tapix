import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/core/services/parties/party_balance_classifier.dart';
import 'package:tapix/features/suppliers/domain/repositories/supplier_repository.dart';
import 'package:tapix/features/suppliers/presentation/screens/supplier_hub_screen.dart';
import '../../support/supplier_lifecycle_repository.dart';

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Currency extends Mock implements CurrencyService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final language in ['ar', 'en', 'fr']) {
    testWidgets('inactive suppliers reachable in actual hub ($language)', (
      tester,
    ) async {
      await sl.reset();
      addTearDown(sl.reset);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = SupplierLifecycleRepository([
        sampleSupplier(1, 'TEST9', active: false),
      ]);
      addTearDown(repository.close);
      final currency = _Currency();
      when(() => currency.format(any())).thenReturn('0.00');
      sl.registerSingleton<SupplierRepository>(repository);
      sl.registerSingleton<CurrencyService>(currency);
      sl.registerSingleton<PartyBalanceClassifier>(
        const PartyBalanceClassifier(),
      );
      final router = GoRouter(
        initialLocation: '/suppliers',
        routes: [
          GoRoute(
            path: '/suppliers',
            builder: (_, _) => const SupplierHubScreen(),
          ),
          GoRoute(
            path: '/suppliers/:id',
            builder: (_, state) => Scaffold(
              body: Text('opened-supplier-${state.pathParameters['id']}'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          startLocale: Locale(language),
          saveLocale: false,
          child: Builder(
            builder: (ctx) => MaterialApp.router(
              locale: ctx.locale,
              supportedLocales: ctx.supportedLocales,
              localizationsDelegates: ctx.localizationDelegates,
              routerConfig: router,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final inactiveChip = find.byKey(
        const ValueKey('supplier_status_inactive'),
      );
      expect(inactiveChip, findsOneWidget);
      await tester.tap(inactiveChip);
      await tester.pumpAndSettle();
      final supplierName = find.text('Supplier TEST9');
      await tester.scrollUntilVisible(
        supplierName,
        150,
        scrollable: find.byType(Scrollable).first,
      );
      // Scrolling can schedule a layout without drawing it immediately. Wait
      // before inspecting the target or sending a pointer event.
      await tester.pumpAndSettle();
      // Visibility in a scrollable does not imply that an overlay (the add
      // supplier FAB) leaves the target's center reachable. Position the name
      // away from the bottom overlay, then verify the actual hit-test result.
      await Scrollable.ensureVisible(
        tester.element(supplierName),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      expect(supplierName, findsOneWidget);
      expect(find.text('TEST9'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        supplierName.hitTestable(),
        findsOneWidget,
        reason: 'The supplier name must receive a real tap after scrolling.',
      );
      await tester.tap(supplierName);
      await tester.pumpAndSettle();
      expect(find.text('opened-supplier-1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  }
}
