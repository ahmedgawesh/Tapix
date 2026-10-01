import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart' hide Size;
import 'package:tapix/core/di/injection_container.dart';
import 'package:tapix/core/services/business/warehouse_read_scope.dart';
import 'package:tapix/core/services/currency_service.dart';
import 'package:tapix/features/business/data/company_branch_monitor_service.dart';
import 'package:tapix/features/business/data/synced_location_report_service.dart';
import 'package:tapix/features/business/data/warehouse_setup_service.dart';
import 'package:tapix/features/business/presentation/screens/company_branch_monitor_screen.dart';
import 'package:tapix/features/business/presentation/screens/company_document_detail_screen.dart';
import 'package:tapix/features/business/presentation/screens/synced_location_report_screen.dart';
import 'package:tapix/features/business/presentation/screens/warehouse_reports_screen.dart';
import 'package:tapix/features/reports/presentation/bloc/inventory_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/screens/inventory_reports_screen.dart';
import 'package:tapix/features/reports/presentation/widgets/warehouse_report_context.dart';
import 'package:tapix/features/settings/domain/entities/company_profile.dart';
import 'business_foundation_test.dart' as fixtures;

class _Assets extends AssetLoader {
  const _Assets();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Service extends Fake implements WarehouseSetupService {
  _Service(this.db, this.warehouse, {this.additionalLocations = const []});
  final AppDatabase db;
  final BusinessWarehouse warehouse;
  final List<WarehouseReportLocation> additionalLocations;
  @override
  Future<List<WarehouseReportLocation>> reportLocations() async => [
    WarehouseReportLocation(
      warehouse: warehouse,
      branchName: 'Main branch',
      branchCode: 'MAIN',
      isLocalBranch: true,
    ),
    ...additionalLocations,
  ];
  @override
  Future<WarehouseReadScope> reportScope(String id) =>
      WarehouseReadScope.resolve(db, warehouseId: id, organizationWide: true);
}

class _Monitor extends CompanyBranchMonitorService {
  _Monitor(super.db, {this.snapshot});

  final CompanyBranchMonitorSnapshot? snapshot;

  @override
  Future<CompanyBranchMonitorSnapshot> load({DateTime? now}) async =>
      snapshot ??
      CompanyBranchMonitorSnapshot(
        locations: const [],
        documents: const [],
        generatedAt: DateTime.utc(2026, 9, 30),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  for (final language in ['ar', 'en', 'fr']) {
    for (final dark in [false, true]) {
      testWidgets(
        'warehouse report $language dark=$dark keeps scope and export label',
        (tester) async {
          await sl.reset();
          addTearDown(sl.reset);
          tester.view.physicalSize = dark
              ? const Size(1200, 900)
              : const Size(360, 740);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final db = fixtures.memoryDb();
          addTearDown(db.close);
          final scope = await WarehouseReadScope.resolve(db);
          final warehouse =
              (await db.select(db.businessWarehouses).get()).single;
          sl.registerSingleton<CurrencyService>(
            CurrencyService(await SharedPreferences.getInstance()),
          );
          WarehouseReadScope? passedScope;
          sl.registerFactoryParam<
            InventoryReportsBloc,
            WarehouseReadScope?,
            void
          >((selected, _) {
            passedScope = selected;
            return InventoryReportsBloc(db, warehouseScope: selected);
          });
          await tester.pumpWidget(
            EasyLocalization(
              supportedLocales: const [
                Locale('ar'),
                Locale('en'),
                Locale('fr'),
              ],
              path: 'assets/translations',
              assetLoader: const _Assets(),
              startLocale: Locale(language),
              saveLocale: false,
              child: Builder(
                builder: (context) => MaterialApp(
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: context.localizationDelegates,
                  theme: ThemeData(
                    brightness: dark ? Brightness.dark : Brightness.light,
                  ),
                  home: WarehouseReportsScreen(
                    service: _Service(db, warehouse),
                    warehouseId: scope.warehouseId,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.enterText(
            find.byType(TextField),
            'reports.inventory_reports'.tr(),
          );
          await tester.pumpAndSettle();
          tester.testTextInput.hide();
          await tester.tap(find.text('reports.inventory_reports'.tr()).last);
          await tester.pumpAndSettle();
          expect(passedScope?.warehouseId, warehouse.id);
          final location = WarehouseReportContext.maybeOf(
            tester.element(find.byType(InventoryReportsScreen)),
          )!;
          const company = CompanyProfile(name: 'Company');
          expect(
            location.decorateCompany(company).name,
            contains(warehouse.code),
          );
          expect(company.name, 'Company');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        },
      );
    }
  }
  testWidgets(
    'remote location keeps the report catalogue instead of opening monitor',
    (tester) async {
      await sl.reset();
      addTearDown(sl.reset);
      tester.view.physicalSize = const Size(420, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = fixtures.memoryDb();
      addTearDown(db.close);
      final localWarehouse =
          (await db.select(db.businessWarehouses).get()).single;
      final organizationId = localWarehouse.organizationId;
      const branchId = '22222222-2222-4222-8222-222222222222';
      const warehouseId = '33333333-3333-4333-8333-333333333333';
      await db.customStatement(
        '''INSERT INTO business_branches(
          id,organization_id,code,name,is_active)
          VALUES(?,?,?,?,1)''',
        [branchId, organizationId, 'CAIRO', 'Cairo branch'],
      );
      await db.customStatement(
        '''INSERT INTO business_warehouses(
          id,organization_id,branch_id,code,name,location_kind,is_active)
          VALUES(?,?,?,?,?,'warehouse',1)''',
        [warehouseId, organizationId, branchId, 'CAIRO-WH', 'Cairo warehouse'],
      );
      final remoteWarehouse = await (db.select(
        db.businessWarehouses,
      )..where((row) => row.id.equals(warehouseId))).getSingle();
      sl.registerSingleton<CurrencyService>(
        CurrencyService(await SharedPreferences.getInstance()),
      );
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          startLocale: const Locale('en'),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: WarehouseReportsScreen(
                service: _Service(
                  db,
                  localWarehouse,
                  additionalLocations: [
                    WarehouseReportLocation(
                      warehouse: remoteWarehouse,
                      branchName: 'Cairo branch',
                      branchCode: 'CAIRO',
                      isLocalBranch: false,
                    ),
                  ],
                ),
                warehouseId: localWarehouse.id,
                syncedReportService: SyncedLocationReportService(_Monitor(db)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Cairo branch · Cairo warehouse · CAIRO-WH').last,
      );
      await tester.pumpAndSettle();

      expect(find.byType(CompanyBranchMonitorScreen), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Sales by supplier'), findsOneWidget);

      await tester.tap(find.text('Sales by supplier'));
      await tester.pumpAndSettle();

      expect(find.byType(SyncedLocationReportScreen), findsOneWidget);
      expect(find.byType(CompanyBranchMonitorScreen), findsNothing);
      expect(find.text('Cairo branch · Cairo warehouse'), findsOneWidget);
      expect(
        tester
            .widget<SyncedLocationReportScreen>(
              find.byType(SyncedLocationReportScreen),
            )
            .scope
            ?.kind,
        SyncedReportScopeKind.location,
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Whole branch'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sales by supplier'));
      await tester.pumpAndSettle();

      final aggregated = tester.widget<SyncedLocationReportScreen>(
        find.byType(SyncedLocationReportScreen),
      );
      expect(aggregated.scope?.kind, SyncedReportScopeKind.branch);
      expect(aggregated.scope?.branchId, branchId);
      expect(find.text('Consolidated report: Cairo branch'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'supplier purchase result opens only scoped invoices and their product lines',
    (tester) async {
      await sl.reset();
      addTearDown(sl.reset);
      tester.view.physicalSize = const Size(420, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = fixtures.memoryDb();
      addTearDown(db.close);
      sl.registerSingleton<CurrencyService>(
        CurrencyService(await SharedPreferences.getInstance()),
      );
      final at = DateTime.now();
      CompanyDocumentSnapshot purchase({
        required String id,
        required String branch,
        required String warehouse,
        required String product,
        required int total,
      }) => CompanyDocumentSnapshot(
        documentId: id,
        sourceDatabaseId: 'db-$branch',
        branchId: branch,
        branchName: branch == 'cairo' ? 'Cairo branch' : 'Main branch',
        warehouseId: warehouse,
        warehouseName: warehouse == 'floor'
            ? 'Cairo sales floor'
            : 'Main stock',
        kind: CompanyDocumentKind.purchase,
        number: id,
        documentDate: at,
        currencyCode: 'USD',
        totalMinor: total,
        subtotalMinor: total,
        itemCount: 1,
        isRemote: true,
        isVoided: false,
        occurredAt: at,
        partyName: 'Hope Supplies',
        lines: [
          CompanyDocumentLineSnapshot(
            productName: product,
            variantName: null,
            quantityScaled: 1,
            quantityScale: 1,
            measurementType: 'piece',
            unitMinor: total,
            subtotalMinor: total,
            discountMinor: 0,
            taxMinor: 0,
            totalMinor: total,
          ),
        ],
      );
      final snapshot = CompanyBranchMonitorSnapshot(
        locations: const [],
        generatedAt: at,
        documents: [
          purchase(
            id: 'PI-CAIRO-1',
            branch: 'cairo',
            warehouse: 'floor',
            product: 'Cairo product one',
            total: 24500,
          ),
          purchase(
            id: 'PI-CAIRO-2',
            branch: 'cairo',
            warehouse: 'floor',
            product: 'Cairo product two',
            total: 170000,
          ),
          purchase(
            id: 'PI-MAIN-1',
            branch: 'main',
            warehouse: 'main-floor',
            product: 'Main product',
            total: 999900,
          ),
        ],
      );

      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          startLocale: const Locale('en'),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: SyncedLocationReportScreen(
                reportKey: 'reports.purchases_by_supplier',
                scope: const SyncedReportScope.location(
                  branchId: 'cairo',
                  warehouseId: 'floor',
                ),
                locationLabel: 'Cairo branch · Sales floor',
                service: SyncedLocationReportService(
                  _Monitor(db, snapshot: snapshot),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final supplier = find.text('Hope Supplies');
      await tester.scrollUntilVisible(
        supplier,
        320,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(supplier);
      await tester.pumpAndSettle();
      await tester.tap(supplier);
      await tester.pumpAndSettle();
      expect(find.text('PI-CAIRO-1'), findsOneWidget);
      expect(find.text('PI-CAIRO-2'), findsOneWidget);
      expect(find.text('PI-MAIN-1'), findsNothing);

      await tester.tap(find.text('PI-CAIRO-2'));
      await tester.pumpAndSettle();
      expect(find.byType(CompanyDocumentDetailScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Cairo product two'),
        260,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Cairo product two'), findsOneWidget);
      expect(find.byIcon(Icons.print_outlined), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(360, 740), const Size(1200, 900)]) {
    testWidgets('synced report is responsive at ${size.width.toInt()}px', (
      tester,
    ) async {
      await sl.reset();
      addTearDown(sl.reset);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = fixtures.memoryDb();
      addTearDown(db.close);
      sl.registerSingleton<CurrencyService>(
        CurrencyService(await SharedPreferences.getInstance()),
      );
      final at = DateTime.now();
      final snapshot = CompanyBranchMonitorSnapshot(
        locations: const [],
        generatedAt: at,
        documents: [
          CompanyDocumentSnapshot(
            documentId: 'sale-1',
            sourceDatabaseId: 'remote-db',
            branchId: 'cairo',
            branchName: 'فرع القاهرة',
            warehouseId: 'floor',
            warehouseName: 'صالة الفرع',
            kind: CompanyDocumentKind.sale,
            number: 'SI-1',
            documentDate: at,
            currencyCode: 'USD',
            totalMinor: 125000,
            itemCount: 1,
            isRemote: true,
            isVoided: false,
            occurredAt: at,
            lines: const [
              CompanyDocumentLineSnapshot(
                productName: 'منتج تجريبي ذو اسم طويل لاختبار الشاشة',
                variantName: null,
                quantityScaled: 2,
                quantityScale: 1,
                measurementType: 'piece',
                unitMinor: 62500,
                subtotalMinor: 125000,
                discountMinor: 0,
                taxMinor: 0,
                totalMinor: 125000,
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('ar')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          startLocale: const Locale('ar'),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: SyncedLocationReportScreen(
                reportKey: 'reports.sales_by_product',
                branchId: 'cairo',
                warehouseId: 'floor',
                locationLabel: 'فرع القاهرة · صالة الفرع',
                service: SyncedLocationReportService(
                  _Monitor(db, snapshot: snapshot),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('فرع القاهرة · صالة الفرع'), findsOneWidget);
      final productFinder = find.text('منتج تجريبي ذو اسم طويل لاختبار الشاشة');
      await tester.scrollUntilVisible(
        productFinder,
        240,
        scrollable: find.byType(Scrollable).last,
      );
      expect(productFinder, findsOneWidget);
      await tester.tap(productFinder);
      await tester.pumpAndSettle();
      expect(find.byType(CompanyDocumentDetailScreen), findsOneWidget);
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(
        find.text('منتج تجريبي ذو اسم طويل لاختبار الشاشة'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
