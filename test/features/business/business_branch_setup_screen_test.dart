import 'dart:convert';
import 'dart:io';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapix/core/database/app_database.dart'
    show BusinessBranch, BusinessWarehouse;
import 'package:tapix/core/services/lan/lan_network_service.dart';
import 'package:tapix/features/business/data/lan_branch_enrollment_service.dart';
import 'package:tapix/features/business/data/warehouse_setup_service.dart';
import 'package:tapix/features/business/presentation/screens/business_branch_setup_screen.dart';

class _Assets extends AssetLoader {
  const _Assets();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Service extends Fake implements WarehouseSetupService {
  _Service() {
    final created = DateTime.utc(2026, 9, 27);
    rows = [
      BusinessBranchOverview(
        branch: BusinessBranch(
          id: '11111111-1111-4111-8111-111111111111',
          organizationId: '00000000-0000-4000-8000-000000000000',
          code: 'MAIN',
          name: 'Main branch',
          isActive: true,
          createdAt: created,
        ),
        defaultWarehouse: BusinessWarehouse(
          id: '22222222-2222-4222-8222-222222222222',
          organizationId: '00000000-0000-4000-8000-000000000000',
          branchId: '11111111-1111-4111-8111-111111111111',
          code: 'MAIN-WH',
          name: 'Main warehouse',
          locationKind: 'branch_store',
          isActive: true,
          createdAt: created,
        ),
        warehouseCount: 2,
        isLocal: true,
        isOnline: true,
      ),
    ];
  }

  late List<BusinessBranchOverview> rows;
  int saves = 0;
  int warehouseSaves = 0;
  int branchRenames = 0;
  int warehouseRenames = 0;
  int catalogueSaves = 0;
  BranchCataloguePolicy savedPolicy = const BranchCataloguePolicy();

  @override
  Future<BusinessBranch> renameBranch({
    required String branchId,
    required String name,
  }) async {
    branchRenames++;
    late BusinessBranch result;
    rows = [
      for (final row in rows)
        if (row.branch.id != branchId)
          row
        else
          BusinessBranchOverview(
            branch: result = BusinessBranch(
              id: row.branch.id,
              organizationId: row.branch.organizationId,
              code: row.branch.code,
              name: name.trim(),
              isActive: row.branch.isActive,
              createdAt: row.branch.createdAt,
            ),
            defaultWarehouse: row.defaultWarehouse,
            warehouseCount: row.warehouseCount,
            isLocal: row.isLocal,
            warehouses: row.warehouses,
            connectionStatus: row.connectionStatus,
            isOnline: row.isOnline,
            lastSeenAt: row.lastSeenAt,
            catalogueMode: row.catalogueMode,
          ),
    ];
    return result;
  }

  @override
  Future<BusinessWarehouse> renameWarehouse({
    required String warehouseId,
    required String name,
  }) async {
    warehouseRenames++;
    late BusinessWarehouse result;
    rows = [
      for (final row in rows)
        BusinessBranchOverview(
          branch: row.branch,
          defaultWarehouse: row.defaultWarehouse.id == warehouseId
              ? result = BusinessWarehouse(
                  id: row.defaultWarehouse.id,
                  organizationId: row.defaultWarehouse.organizationId,
                  branchId: row.defaultWarehouse.branchId,
                  code: row.defaultWarehouse.code,
                  name: name.trim(),
                  locationKind: row.defaultWarehouse.locationKind,
                  isActive: row.defaultWarehouse.isActive,
                  createdAt: row.defaultWarehouse.createdAt,
                )
              : row.defaultWarehouse,
          warehouseCount: row.warehouseCount,
          isLocal: row.isLocal,
          warehouses: [
            for (final warehouse in row.visibleWarehouses)
              if (warehouse.id != warehouseId)
                warehouse
              else
                result = BusinessWarehouse(
                  id: warehouse.id,
                  organizationId: warehouse.organizationId,
                  branchId: warehouse.branchId,
                  code: warehouse.code,
                  name: name.trim(),
                  locationKind: warehouse.locationKind,
                  isActive: warehouse.isActive,
                  createdAt: warehouse.createdAt,
                ),
          ],
          connectionStatus: row.connectionStatus,
          isOnline: row.isOnline,
          lastSeenAt: row.lastSeenAt,
          catalogueMode: row.catalogueMode,
        ),
    ];
    return result;
  }

  @override
  Future<BranchCataloguePolicy> cataloguePolicy(String branchId) async =>
      savedPolicy;

  @override
  Future<BranchCatalogueOptions> catalogueOptions(String branchId) async =>
      const BranchCatalogueOptions(
        categories: [BranchCatalogueOption(id: 1, name: 'Cosmetics')],
        products: [
          BranchCatalogueOption(id: 10, name: 'Lipstick', code: 'COS-10'),
        ],
      );

  @override
  Future<void> saveCataloguePolicy({
    required String branchId,
    required BranchCataloguePolicy policy,
  }) async {
    catalogueSaves++;
    savedPolicy = policy;
    rows = [
      for (final row in rows)
        BusinessBranchOverview(
          branch: row.branch,
          defaultWarehouse: row.defaultWarehouse,
          warehouseCount: row.warehouseCount,
          isLocal: row.isLocal,
          warehouses: row.warehouses,
          connectionStatus: row.connectionStatus,
          isOnline: row.isOnline,
          lastSeenAt: row.lastSeenAt,
          catalogueMode: row.branch.id == branchId
              ? policy.mode
              : row.catalogueMode,
        ),
    ];
  }

  @override
  Future<List<BusinessBranchOverview>> branches() async => rows;

  @override
  Future<bool> canCreateWarehouse() async => true;

  @override
  Future<BusinessWarehouse> createWarehouse({
    required String name,
    required String code,
    String? branchId,
  }) async {
    warehouseSaves++;
    final target = rows.singleWhere((row) => row.branch.id == branchId);
    final warehouse = BusinessWarehouse(
      id: '55555555-5555-4555-8555-555555555555',
      organizationId: target.branch.organizationId,
      branchId: target.branch.id,
      code: code.toUpperCase(),
      name: name,
      locationKind: 'warehouse',
      isActive: true,
      createdAt: DateTime.utc(2026, 9, 27),
    );
    rows = [
      for (final row in rows)
        if (row.branch.id != branchId)
          row
        else
          BusinessBranchOverview(
            branch: row.branch,
            defaultWarehouse: row.defaultWarehouse,
            warehouseCount: row.warehouseCount + 1,
            isLocal: row.isLocal,
            warehouses: [...row.visibleWarehouses, warehouse],
            connectionStatus: row.connectionStatus,
            isOnline: row.isOnline,
            lastSeenAt: row.lastSeenAt,
            catalogueMode: row.catalogueMode,
          ),
    ];
    return warehouse;
  }

  @override
  Future<BusinessBranchOverview> createBranchWithDefaultWarehouse({
    required String branchName,
    required String branchCode,
    required String warehouseName,
    required String warehouseCode,
  }) async {
    saves++;
    final created = DateTime.utc(2026, 9, 27);
    final branch = BusinessBranch(
      id: '33333333-3333-4333-8333-333333333333',
      organizationId: '00000000-0000-4000-8000-000000000000',
      code: branchCode.toUpperCase(),
      name: branchName,
      isActive: true,
      createdAt: created,
    );
    final result = BusinessBranchOverview(
      branch: branch,
      defaultWarehouse: BusinessWarehouse(
        id: '44444444-4444-4444-8444-444444444444',
        organizationId: branch.organizationId,
        branchId: branch.id,
        code: warehouseCode.toUpperCase(),
        name: warehouseName,
        locationKind: 'branch_store',
        isActive: true,
        createdAt: created,
      ),
      warehouseCount: 1,
      isLocal: false,
    );
    rows = [...rows, result];
    return result;
  }
}

class _Enrollment extends Fake implements LanBranchEnrollmentService {
  int calls = 0;

  @override
  Future<LanBranchInvitation> issueInvitation({
    required String branchId,
    required String warehouseId,
    Duration validity = const Duration(minutes: 15),
    DateTime? now,
  }) async {
    calls++;
    return LanBranchInvitation(
      enrollmentId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      organizationId: '00000000-0000-4000-8000-000000000000',
      organizationName: 'Tapix company',
      coordinatorBranchId: '11111111-1111-4111-8111-111111111111',
      branchId: branchId,
      branchName: 'Cairo',
      branchCode: 'CAIRO',
      warehouseId: warehouseId,
      warehouseName: 'Cairo main',
      warehouseCode: 'CAI-MAIN',
      coordinatorDatabaseId: '55555555-5555-4555-8555-555555555555',
      secret: 'test-branch-secret',
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 15)),
    );
  }
}

class _Lan extends Fake implements LanNetworkService {
  int refreshCalls = 0;

  @override
  LanNetworkSnapshot get snapshot => const LanNetworkSnapshot(
    mode: LanMode.master,
    status: LanConnectionStatus.online,
    addresses: ['192.168.1.10'],
    port: 45820,
  );

  @override
  String? get masterTlsFingerprint => List.filled(64, 'a').join();

  @override
  Future<void> refreshMasterNetwork() async {
    refreshCalls++;
  }
}

class _StandaloneLan extends Fake implements LanNetworkService {
  int startCalls = 0;
  LanNetworkSnapshot current = const LanNetworkSnapshot();

  @override
  LanNetworkSnapshot get snapshot => current;

  @override
  String? get masterTlsFingerprint => List.filled(64, 'b').join();

  @override
  Future<void> startMaster({int port = 45820}) async {
    startCalls++;
    current = LanNetworkSnapshot(
      mode: LanMode.master,
      status: LanConnectionStatus.online,
      addresses: const ['192.168.1.20'],
      port: port,
    );
  }

  @override
  Future<void> refreshMasterNetwork() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final language in ['ar', 'en', 'fr']) {
    testWidgets('branch setup fits and explains identity in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _Service();
      final locale = Locale(language);
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          startLocale: locale,
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              theme: ThemeData(brightness: Brightness.dark),
              home: BusinessBranchSetupScreen(service: service),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('MAIN'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('MAIN'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), 'Cairo');
      await tester.enterText(fields.at(1), 'CAIRO');
      await tester.tap(
        find.text('business_locations.branch_setup.create'.tr()),
      );
      await tester.pumpAndSettle();
      expect(service.saves, 1);
      expect(service.rows.last.branch.code, 'CAIRO');
      expect(service.rows.last.defaultWarehouse.code, 'CAIRO');
      expect(service.rows.last.defaultWarehouse.name, 'Cairo');
      expect(service.rows.last.defaultWarehouse.locationKind, 'branch_store');
      await tester.scrollUntilVisible(
        find.text('CAIRO').first,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('CAIRO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('owner renames a branch and preselects its current name', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _Service();
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
        path: 'assets/translations',
        assetLoader: const _Assets(),
        startLocale: const Locale('en'),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: BusinessBranchSetupScreen(service: service),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byTooltip('Rename branch'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Rename branch'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller!.selection.baseOffset, 0);
    expect(field.controller!.selection.extentOffset, 'Main branch'.length);
    await tester.enterText(find.byType(TextFormField), 'Head office');
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();
    expect(service.branchRenames, 1);
    expect(service.rows.single.branch.name, 'Head office');
    expect(find.text('Head office'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('prepared branch creates a responsive one-time QR invitation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final setup = _Service();
    await setup.createBranchWithDefaultWarehouse(
      branchName: 'Cairo',
      branchCode: 'CAIRO',
      warehouseName: 'Cairo main',
      warehouseCode: 'CAI-MAIN',
    );
    final enrollment = _Enrollment();
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
        path: 'assets/translations',
        assetLoader: const _Assets(),
        startLocale: const Locale('en'),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: BusinessBranchSetupScreen(
              service: setup,
              enrollmentService: enrollment,
              lanService: _Lan(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.text(
      'business_locations.branch_setup.prepare_connection'.tr(),
    );
    await tester.scrollUntilVisible(
      action,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(enrollment.calls, 1);
    expect(find.byType(BarcodeWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preparing a branch promotes a standalone coordinator without false warning',
    (tester) async {
      tester.view.physicalSize = const Size(380, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final setup = _Service();
      await setup.createBranchWithDefaultWarehouse(
        branchName: 'Cairo',
        branchCode: 'CAIRO',
        warehouseName: 'Cairo main',
        warehouseCode: 'CAI-MAIN',
      );
      final enrollment = _Enrollment();
      final lan = _StandaloneLan();
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
          path: 'assets/translations',
          assetLoader: const _Assets(),
          startLocale: const Locale('en'),
          saveLocale: false,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: BusinessBranchSetupScreen(
                service: setup,
                enrollmentService: enrollment,
                lanService: lan,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.text('Prepare branch connection');
      await tester.scrollUntilVisible(
        action,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(lan.startCalls, 1);
      expect(enrollment.calls, 1);
      expect(find.byType(BarcodeWidget), findsOneWidget);
      expect(find.textContaining('not configured as the main'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('owner chooses a managed branch product assortment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final setup = _Service();
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
        path: 'assets/translations',
        assetLoader: const _Assets(),
        startLocale: const Locale('en'),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: BusinessBranchSetupScreen(service: setup),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final action = find.text('Product policy');
    await tester.scrollUntilVisible(
      action,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pumpAndSettle();
    expect(find.text('Products for Main branch'), findsOneWidget);
    await tester.tap(find.text('Managed assortment').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Cosmetics'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Cosmetics'));
    await tester.tap(find.text('Save and publish policy'));
    await tester.pumpAndSettle();
    expect(setup.catalogueSaves, 1);
    expect(setup.savedPolicy.mode, BranchCatalogueMode.managedAssortment);
    expect(setup.savedPolicy.categoryIds, {1});
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner adds a zero-balance warehouse to the selected branch', (
    tester,
  ) async {
    final setup = _Service();
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
        path: 'assets/translations',
        assetLoader: const _Assets(),
        startLocale: const Locale('en'),
        saveLocale: false,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: BusinessBranchSetupScreen(service: setup),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final addWarehouse = find
        .text('business_locations.branch_setup.add_warehouse'.tr())
        .first;
    await tester.scrollUntilVisible(
      addWarehouse,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(addWarehouse);
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Main reserve');
    await tester.enterText(fields.at(1), 'MAIN-RESERVE');
    await tester.tap(
      find.text('business_locations.branch_setup.create_warehouse'.tr()),
    );
    await tester.pumpAndSettle();
    expect(setup.warehouseSaves, 1);
    expect(setup.rows.single.warehouseCount, 3);
    expect(
      setup.rows.single.visibleWarehouses.map((row) => row.code),
      contains('MAIN-RESERVE'),
    );
    expect(tester.takeException(), isNull);
  });
}
