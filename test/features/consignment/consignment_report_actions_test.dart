import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/features/consignment/data/consignment_reporting_service.dart';
import 'package:tapix/features/consignment/presentation/screens/consignment_hub_screen.dart';
import 'package:tapix/features/settings/data/services/company_profile_service.dart';
import 'package:tapix/features/settings/domain/entities/company_profile.dart';

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Reports implements ConsignmentReportingService {
  @override
  Future<ConsignmentDashboardSnapshot> load() async =>
      const ConsignmentDashboardSnapshot(
        agreements: [],
        receipts: [],
        custodyDocuments: [],
        ownershipConversions: [],
        statements: [],
        payments: [],
        suppliers: {},
        currencyCodes: {},
        operationsEnabled: true,
        historicalManagementEnabled: true,
        reportRows: [],
      );
  @override
  Future<List<ConsignmentSupplierReportRow>> loadReport({
    required ConsignmentReportRange range,
    int? supplierId,
  }) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnavailableProfile implements CompanyProfileService {
  int calls = 0;
  @override
  Future<CompanyProfile> getProfile() async {
    calls++;
    throw StateError('Test export dependency failure');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  testWidgets(
    'sales details navigates and every empty-report export runs with visible failures',
    (tester) async {
      await sl.reset();
      addTearDown(sl.reset);
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      sl.registerSingleton<ConsignmentReportingService>(_Reports());
      final profile = _UnavailableProfile();
      sl.registerSingleton<CompanyProfileService>(profile);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const ConsignmentHubScreen()),
          GoRoute(
            path: '/reports/sales/by-supplier',
            builder: (_, _) =>
                const Scaffold(body: Text('supplier-sales-destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          startLocale: const Locale('en'),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp.router(
              routerConfig: router,
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('common.refresh'.tr()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('consignment.report'.tr()).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('consignment.report'.tr()).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('consignment.apply_filters'.tr()));
      await tester.tap(find.text('consignment.apply_filters'.tr()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('consignment.sales_detail'.tr()));
      await tester.pumpAndSettle();
      expect(find.text('supplier-sales-destination'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      for (final action in ['print', 'share', 'excel']) {
        await tester.tap(find.byType(PopupMenuButton<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('consignment.$action'.tr()));
        await tester.pumpAndSettle();
        expect(find.text('consignment.export_failed'.tr()), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }
      expect(profile.calls, 3);
      expect(tester.takeException(), isNull);
    },
  );
}
