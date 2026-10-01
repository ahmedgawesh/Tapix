import 'package:drift/drift.dart' show Value, Variable;
import 'package:tapix/core/services/business/warehouse_stocktake_service.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/sync/branch_location_directory_sync_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/business/data/warehouse_setup_service.dart';
import 'business_foundation_test.dart' as fixtures;

class _Session extends Fake implements SessionService {
  int? id = 77;
  @override
  Future<int?> getCurrentUserId() async => id;
}

class _License implements WarehouseSetupEntitlement {
  bool allowed = true;
  @override
  Future<bool> permits(WarehouseOperationScope scope) async => allowed;
}

void main() {
  late AppDatabase db;
  late WarehouseSetupService service;
  late _Session session;
  late _License license;
  late String warehouse;
  bool remote = false;
  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    await db.customStatement(
      "INSERT INTO users (id, username, password_hash, role, is_active, created_at, updated_at) VALUES (77, 'setup-owner', 'test', 'owner', 1, 0, 0)",
    );
    final primary = await WarehouseOperationScope.resolve(db);
    warehouse = '22222222-2222-4222-8222-222222222222';
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: warehouse,
            organizationId: primary.organizationId,
            branchId: primary.branchId,
            code: 'SETUP',
          ),
        );
    session = _Session();
    license = _License();
    remote = false;
    service = WarehouseSetupService(
      db,
      session,
      license,
      isRemoteClient: () => remote,
      operatingCurrencyCode: () => 'USD',
      adjustments: InventoryAdjustmentService(
        db: db,
        dao: db.inventoryAdjustmentDao,
        journal: JournalEntryService(AccountingRepository(db)),
      ),
      stocktake: WarehouseStocktakeService(
        db,
        InventoryAdjustmentService(
          db: db,
          dao: db.inventoryAdjustmentDao,
          journal: JournalEntryService(AccountingRepository(db)),
        ),
      ),
    );
  });
  tearDown(() => db.close());

  test(
    'opening setup suggests the selected variant cost without changing stock',
    () async {
      final initial = (await service.items(warehouse, query: 'wac')).single;
      await db.customStatement(
        'UPDATE product_variants SET cost_cents=12345 WHERE id=?',
        [initial.variantId],
      );
      final item = (await service.items(warehouse, query: 'wac')).single;
      expect(item.suggestedUnitCostCents, 12345);
      expect(item.suggestedCostText, '123.45');
      expect(item.parseCost(item.suggestedCostText), 12345);
      final count = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM business_warehouse_stocks WHERE warehouse_id=?',
            variables: [Variable.withString(warehouse)],
          )
          .getSingle();
      expect(count.read<int>('n'), 0);
    },
  );

  test(
    'authorized setup creates zero balance and attributable audit once',
    () async {
      expect((await service.warehouses()).single.id, warehouse);
      final item = (await service.items(warehouse, query: 'wac')).single;
      expect(
        await service.initialize(
          warehouseId: warehouse,
          item: item,
          cost: '2.50',
        ),
        1,
      );
      final balance = await (db.select(
        db.businessWarehouseStocks,
      )..where((s) => s.warehouseId.equals(warehouse))).getSingle();
      expect(balance.quantity, 0);
      expect(balance.unitCostCents, 250);
      final audit =
          await (db.select(db.auditLogs)
                ..where((a) => a.action.equals('initialize_warehouse_stock')))
              .getSingle();
      expect(audit.userId, 77);
      expect(await service.items(warehouse, query: 'wac'), isEmpty);
      expect(
        await service.initialize(
          warehouseId: warehouse,
          item: item,
          cost: '9.99',
        ),
        0,
      );
      expect(
        (await (db.select(db.auditLogs)
                  ..where((a) => a.action.equals('initialize_warehouse_stock')))
                .get())
            .length,
        1,
      );
    },
  );

  test(
    'opening quantity and equity journal are atomic and cannot be repeated',
    () async {
      final item = (await service.items(warehouse, query: 'wac')).single;
      final before = await fixtures.legacySnapshot(db);
      await db.customStatement(
        "CREATE TRIGGER reject_opening BEFORE INSERT ON journal_entries BEGIN SELECT RAISE(ABORT, 'injected opening failure'); END",
      );
      await expectLater(
        service.initializeOpening(
          warehouseId: warehouse,
          item: item,
          cost: '2.50',
          quantity: '1.5',
          reason: 'Initial count',
        ),
        throwsA(anything),
      );
      expect(await fixtures.legacySnapshot(db), before);
      await db.customStatement('DROP TRIGGER reject_opening');
      await service.initializeOpening(
        warehouseId: warehouse,
        item: item,
        cost: '2.50',
        quantity: '1.5',
        reason: 'Initial count',
      );
      final stock = await (db.select(
        db.businessWarehouseStocks,
      )..where((s) => s.warehouseId.equals(warehouse))).getSingle();
      expect(stock.quantity, 1500);
      final value = await db
          .customSelect(
            "SELECT SUM(l.credit_cents-l.debit_cents) value FROM journal_entry_lines l JOIN accounts a ON a.id=l.account_id WHERE a.account_code='3100'",
          )
          .getSingle();
      expect(value.read<int>('value'), 375);
      final posted = await fixtures.legacySnapshot(db);
      await expectLater(
        service.initializeOpening(
          warehouseId: warehouse,
          item: item,
          cost: '2.50',
          quantity: '1.5',
          reason: 'Repeated',
        ),
        throwsStateError,
      );
      expect(await fixtures.legacySnapshot(db), posted);
    },
  );

  test(
    'valuation preview rechecks authorization and stock before posting',
    () async {
      final item = (await service.items(warehouse, query: 'wac')).single;
      await service.initializeOpening(
        warehouseId: warehouse,
        item: item,
        cost: '2.50',
        quantity: '1.5',
        reason: 'Opening',
      );
      final valuation = (await service.valuationItems(warehouse)).single;
      final preview = await service.previewValuation(valuation, '3.00');
      expect(preview.deltaValueCents, 75);
      license.allowed = false;
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        service.postValuation(preview: preview, reason: 'Revalue'),
        throwsA(isA<WarehouseSetupDenied>()),
      );
      expect(await fixtures.legacySnapshot(db), before);
      license.allowed = true;
      await service.postValuation(preview: preview, reason: 'Revalue');
      final stock = await (db.select(
        db.businessWarehouseStocks,
      )..where((s) => s.warehouseId.equals(warehouse))).getSingle();
      expect(stock.quantity, 1500);
      expect(stock.unitCostCents, 300);
      final posted = await fixtures.legacySnapshot(db);
      await expectLater(
        service.postValuation(preview: preview, reason: 'Stale'),
        throwsStateError,
      );
      expect(await fixtures.legacySnapshot(db), posted);
    },
  );

  test(
    'warehouse creation keeps identity and starts without copied balances',
    () async {
      final primary = await WarehouseOperationScope.resolve(db);
      final beforeStock = (await db.select(db.businessWarehouseStocks).get())
          .map((r) => r.toJson())
          .toList();
      expect(await service.canCreateWarehouse(), isTrue);
      final created = await service.createWarehouse(
        name: 'New storage',
        code: ' west_2 ',
      );
      expect(created.code, 'WEST_2');
      expect(created.branchId, primary.branchId);
      expect(created.organizationId, primary.organizationId);
      expect(
        (await db.select(db.businessWarehouseStocks).get())
            .map((r) => r.toJson())
            .toList(),
        beforeStock,
      );
      expect(
        (await WarehouseOperationScope.resolve(db)).warehouseId,
        primary.warehouseId,
      );
      final count = (await db.select(db.businessWarehouses).get()).length;
      await expectLater(
        service.createWarehouse(name: 'Duplicate', code: 'west_2'),
        throwsStateError,
      );
      expect((await db.select(db.businessWarehouses).get()).length, count);
      license.allowed = false;
      expect(await service.canCreateWarehouse(), isFalse);
      await expectLater(
        service.createWarehouse(name: 'Denied', code: 'WEST_3'),
        throwsA(isA<WarehouseSetupDenied>()),
      );
      expect((await db.select(db.businessWarehouses).get()).length, count);
    },
  );

  test(
    'branch creation is atomic, keeps local identity and starts with empty warehouse',
    () async {
      final localBefore = await WarehouseOperationScope.resolve(db);
      final contextBefore = (await db.select(db.businessContexts).get()).single;
      final stockBefore = (await db.select(db.businessWarehouseStocks).get())
          .map((row) => row.toJson())
          .toList();

      final created = await service.createBranchWithDefaultWarehouse(
        branchName: 'Cairo branch',
        branchCode: ' cairo ',
        warehouseName: 'Cairo main warehouse',
        warehouseCode: ' cai-main ',
      );

      expect(created.branch.code, 'CAIRO');
      expect(created.defaultWarehouse.code, 'CAI-MAIN');
      expect(created.defaultWarehouse.locationKind, 'branch_store');
      expect(created.defaultWarehouse.branchId, created.branch.id);
      expect(
        created.defaultWarehouse.organizationId,
        created.branch.organizationId,
      );
      expect(created.warehouseCount, 1);
      expect(created.isLocal, isFalse);
      final remoteWarehouse = await service.createWarehouse(
        branchId: created.branch.id,
        name: 'Cairo reserve warehouse',
        code: 'CAI-RESERVE',
      );
      expect(remoteWarehouse.branchId, created.branch.id);
      expect(remoteWarehouse.locationKind, 'warehouse');
      expect(
        (await db.select(db.businessContexts).get()).single,
        contextBefore,
      );
      expect(
        (await WarehouseOperationScope.resolve(db)).branchId,
        localBefore.branchId,
      );
      expect(
        (await db.select(db.businessWarehouseStocks).get())
            .map((row) => row.toJson())
            .toList(),
        stockBefore,
      );
      final rows = await service.branches();
      expect(rows, hasLength(2));
      expect(rows.singleWhere((row) => row.isLocal).warehouseCount, 2);
      final remoteBranch = rows.singleWhere((row) => !row.isLocal);
      expect(remoteBranch.branch.code, 'CAIRO');
      expect(remoteBranch.warehouseCount, 2);
      expect(
        remoteBranch.visibleWarehouses.map((row) => row.code),
        containsAll(['CAI-MAIN', 'CAI-RESERVE']),
      );
      expect(
        await (db.select(db.auditLogs)..where(
              (row) => row.action.isIn([
                'create_branch_directory',
                'create_branch_default_warehouse',
              ]),
            ))
            .get(),
        hasLength(2),
      );
    },
  );

  test(
    'branch catalogue policy supports full or managed assortments',
    () async {
      final created = await service.createBranchWithDefaultWarehouse(
        branchName: 'Fashion branch',
        branchCode: 'FASHION',
        warehouseName: 'Fashion warehouse',
        warehouseCode: 'FASHION-WH',
      );
      final options = await service.catalogueOptions(created.branch.id);
      expect(options.products, isNotEmpty);
      final selectedProduct = options.products.first.id;
      await service.saveCataloguePolicy(
        branchId: created.branch.id,
        policy: BranchCataloguePolicy(
          mode: BranchCatalogueMode.managedAssortment,
          productIds: {selectedProduct},
        ),
      );

      final saved = await service.cataloguePolicy(created.branch.id);
      expect(saved.mode, BranchCatalogueMode.managedAssortment);
      expect(saved.productIds, {selectedProduct});
      final overview = (await service.branches()).singleWhere(
        (row) => row.branch.id == created.branch.id,
      );
      expect(overview.catalogueMode, BranchCatalogueMode.managedAssortment);
      expect(
        await (db.select(db.auditLogs)..where(
              (row) => row.action.equals('update_branch_catalogue_policy'),
            ))
            .get(),
        hasLength(1),
      );
      await expectLater(
        service.saveCataloguePolicy(
          branchId: created.branch.id,
          policy: const BranchCataloguePolicy(
            mode: BranchCatalogueMode.managedAssortment,
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test('branch presence uses recent authenticated sync activity', () async {
    final created = await service.createBranchWithDefaultWarehouse(
      branchName: 'Presence branch',
      branchCode: 'PRESENCE',
      warehouseName: 'Presence warehouse',
      warehouseCode: 'PRESENCE-WH',
    );
    final primary = await WarehouseOperationScope.resolve(db);
    const enrollmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
    const remoteDatabaseId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
    final now = DateTime.now().toUtc();
    await db.customStatement(
      '''INSERT INTO lan_branch_enrollments(
      enrollment_id,organization_id,branch_id,warehouse_id,
      coordinator_database_id,secret_hash,status,issued_by,expires_at,
      remote_database_id,activated_at)
      VALUES(?,?,?,?,?,?,'active',?,?,?,?)''',
      [
        enrollmentId,
        primary.organizationId,
        created.branch.id,
        created.defaultWarehouse.id,
        primary.databaseId,
        '0' * 64,
        77,
        now.add(const Duration(minutes: 15)).toIso8601String(),
        remoteDatabaseId,
        now.toIso8601String(),
      ],
    );
    await db.customStatement(
      '''INSERT INTO lan_branch_sync_credentials(
      enrollment_id,remote_database_id,token_hash,status,last_seen_at)
      VALUES(?,?,?,'active',?)''',
      [enrollmentId, remoteDatabaseId, '1' * 64, now.toIso8601String()],
    );

    var branch = (await service.branches()).singleWhere(
      (row) => row.branch.id == created.branch.id,
    );
    expect(branch.connectionStatus, 'active');
    expect(branch.isOnline, isTrue);

    await db.customStatement(
      'UPDATE lan_branch_sync_credentials SET last_seen_at=? WHERE enrollment_id=?',
      [
        now.subtract(const Duration(minutes: 5)).toIso8601String(),
        enrollmentId,
      ],
    );
    branch = (await service.branches()).singleWhere(
      (row) => row.branch.id == created.branch.id,
    );
    expect(branch.connectionStatus, 'active');
    expect(branch.isOnline, isFalse);
  });

  test(
    'independent branch cannot fork the coordinator location directory',
    () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'lan.branch_sync.coordinator_database_id.v1',
              value: '99999999-9999-4999-8999-999999999999',
            ),
          );
      final before = (await db.select(db.businessWarehouses).get()).length;
      expect(await service.canCreateWarehouse(), isFalse);
      await expectLater(
        service.createWarehouse(name: 'Local fork', code: 'FORK'),
        throwsA(isA<WarehouseDirectoryAuthorityRequired>()),
      );
      await expectLater(
        service.createBranchWithDefaultWarehouse(
          branchName: 'Local branch fork',
          branchCode: 'FORK-B',
          warehouseName: 'Fork warehouse',
          warehouseCode: 'FORK-W',
        ),
        throwsA(isA<WarehouseDirectoryAuthorityRequired>()),
      );
      expect((await db.select(db.businessWarehouses).get()).length, before);
    },
  );

  test(
    'coordinator publishes a warehouse directory change in the same transaction',
    () async {
      final events = OfflineSyncEventStore(db);
      final locations = BranchLocationDirectorySyncService(db, events);
      await events.activateWriterRecording(
        enrollmentId: '98989898-9898-4989-8989-989898989898',
      );
      final coordinated = WarehouseSetupService(
        db,
        session,
        license,
        isRemoteClient: () => false,
        operatingCurrencyCode: () => 'USD',
        syncEvents: events,
        locationDirectory: locations,
      );
      final target = await coordinated.createBranchWithDefaultWarehouse(
        branchName: 'Alex branch',
        branchCode: 'ALEX',
        warehouseName: 'Alex main',
        warehouseCode: 'ALEX-MAIN',
      );
      final published = await db
          .customSelect(
            "SELECT payload_json FROM sync_outbox_events WHERE event_type='location.snapshot_page.v1'",
          )
          .map((row) => row.read<String>('payload_json'))
          .get();
      expect(published, hasLength(2));
      expect(published.join(), contains(target.branch.id));
      expect(published.join(), contains(target.defaultWarehouse.id));
    },
  );

  test('duplicate branch or warehouse code leaves no partial branch', () async {
    final beforeBranches = (await db.select(db.businessBranches).get()).length;
    final beforeWarehouses =
        (await db.select(db.businessWarehouses).get()).length;
    final existingBranch = (await db.select(db.businessBranches).get()).single;
    await expectLater(
      service.createBranchWithDefaultWarehouse(
        branchName: 'Duplicate branch',
        branchCode: existingBranch.code.toLowerCase(),
        warehouseName: 'Unused warehouse',
        warehouseCode: 'UNUSED',
      ),
      throwsStateError,
    );
    await expectLater(
      service.createBranchWithDefaultWarehouse(
        branchName: 'Should roll back',
        branchCode: 'ROLLBACK',
        warehouseName: 'Duplicate warehouse',
        warehouseCode: 'setup',
      ),
      throwsStateError,
    );
    expect(
      (await db.select(db.businessBranches).get()),
      hasLength(beforeBranches),
    );
    expect(
      (await db.select(db.businessWarehouses).get()),
      hasLength(beforeWarehouses),
    );
  });

  test(
    'branch directory rechecks owner, Pro and remote-client boundaries',
    () async {
      for (final revoke in ['role', 'license', 'remote']) {
        switch (revoke) {
          case 'role':
            await db.customStatement(
              "UPDATE users SET role='manager' WHERE id=77",
            );
          case 'license':
            license.allowed = false;
          case 'remote':
            remote = true;
        }
        final before = (await db.select(db.businessBranches).get()).length;
        await expectLater(
          service.createBranchWithDefaultWarehouse(
            branchName: 'Denied',
            branchCode: 'DENIED_$revoke',
            warehouseName: 'Denied warehouse',
            warehouseCode: 'DENIED_W_$revoke',
          ),
          throwsA(isA<WarehouseSetupDenied>()),
        );
        expect((await db.select(db.businessBranches).get()), hasLength(before));
        await db.customStatement("UPDATE users SET role='owner' WHERE id=77");
        license.allowed = true;
        remote = false;
      }
    },
  );

  test(
    'central reports list primary and locations from every active branch',
    () async {
      final primary = await WarehouseOperationScope.resolve(db);
      const branchId = '33333333-3333-4333-8333-333333333333';
      const remoteStore = '44444444-4444-4444-8444-444444444444';
      await db
          .into(db.businessBranches)
          .insert(
            BusinessBranchesCompanion.insert(
              id: branchId,
              organizationId: primary.organizationId,
              code: 'REMOTE',
              name: const Value('Remote branch'),
            ),
          );
      await db
          .into(db.businessWarehouses)
          .insert(
            BusinessWarehousesCompanion.insert(
              id: remoteStore,
              organizationId: primary.organizationId,
              branchId: branchId,
              code: 'REMOTE-STORE',
              name: const Value('Remote branch balance'),
              locationKind: const Value('branch_store'),
            ),
          );

      final locations = await service.reportLocations();
      expect(
        locations.map((location) => location.warehouse.id),
        containsAll([primary.warehouseId, warehouse, remoteStore]),
      );
      final remote = locations.singleWhere(
        (location) => location.warehouse.id == remoteStore,
      );
      expect(remote.branchName, 'Remote branch');
      expect(remote.isBranchLocation, isTrue);
      expect((await service.reportScope(remoteStore)).warehouseId, remoteStore);
    },
  );

  test(
    'report scope checks current access and preserves disabled warehouse history',
    () async {
      final scope = await service.reportScope(warehouse);
      await scope.checkAccess();
      license.allowed = false;
      await expectLater(
        scope.checkAccess(),
        throwsA(isA<WarehouseSetupDenied>()),
      );
      license.allowed = true;
      await db.customStatement(
        'UPDATE business_warehouses SET is_active = 0 WHERE id = ?',
        [warehouse],
      );
      await scope.checkAccess();
      session.id = null;
      await expectLater(
        scope.checkAccess(),
        throwsA(isA<WarehouseSetupDenied>()),
      );
    },
  );

  for (final revoke in ['role', 'inactive', 'session', 'license', 'remote']) {
    test('authorization revoked after reading blocks save: $revoke', () async {
      final item = (await service.items(warehouse)).first;
      switch (revoke) {
        case 'role':
          await db.customStatement(
            "UPDATE users SET role = 'manager' WHERE id = 77",
          );
        case 'inactive':
          await db.customStatement(
            'UPDATE users SET is_active = 0 WHERE id = 77',
          );
        case 'session':
          session.id = null;
        case 'license':
          license.allowed = false;
        case 'remote':
          remote = true;
      }
      await expectLater(
        service.initialize(warehouseId: warehouse, item: item, cost: '1'),
        throwsA(isA<WarehouseSetupDenied>()),
      );
      await expectLater(
        service.items(warehouse),
        throwsA(isA<WarehouseSetupDenied>()),
      );
      expect(
        await (db.select(
          db.businessWarehouseStocks,
        )..where((s) => s.warehouseId.equals(warehouse))).get(),
        isEmpty,
      );
    });
  }

  test(
    'unreleased entitlement never inherits ordinary subscription access',
    () async {
      final denied = WarehouseSetupService(
        db,
        session,
        const UnreleasedWarehouseSetupEntitlement(),
        isRemoteClient: () => false,
      );
      expect(await denied.warehouses(), isEmpty);
      await expectLater(
        denied.items(warehouse),
        throwsA(isA<WarehouseSetupDenied>()),
      );
    },
  );

  test('audit failure rolls back balance creation', () async {
    final item = (await service.items(warehouse)).first;
    await db.customStatement(
      "CREATE TRIGGER reject_setup_audit BEFORE INSERT ON audit_logs BEGIN SELECT RAISE(ABORT, 'Injected audit failure'); END",
    );
    await expectLater(
      service.initialize(warehouseId: warehouse, item: item, cost: '1.23'),
      throwsA(anything),
    );
    expect(
      await (db.select(
        db.businessWarehouseStocks,
      )..where((s) => s.warehouseId.equals(warehouse))).get(),
      isEmpty,
    );
  });

  test(
    'cost parsing respects 0, 2, 3 decimals without floating point rounding',
    () {
      WarehouseSetupItem item(int digits) => WarehouseSetupItem(
        variantId: 1,
        name: 'p',
        label: '',
        currencyId: 1,
        currencyCode: 'XXX',
        decimalDigits: digits,
      );
      expect(item(0).parseCost('١٢٣'), 123);
      expect(item(2).parseCost('12,34'), 1234);
      expect(item(3).parseCost('۱۲٫۳۴۵'), 12345);
      expect(() => item(0).parseCost('1.2'), throwsFormatException);
      expect(() => item(2).parseCost('1.234'), throwsFormatException);
      expect(() => item(2).parseCost('-1'), throwsFormatException);
      expect(() => item(2).parseCost('1e3'), throwsFormatException);
    },
  );
  test(
    'authorized stocktake posts inventory and audit; stale count is rejected',
    () async {
      final item = (await service.items(warehouse, query: 'wac')).single;
      await service.initialize(
        warehouseId: warehouse,
        item: item,
        cost: '2.50',
      );
      final count = (await service.countItems(warehouse)).single;
      await service.postCount(
        item: count,
        countedQuantity: '5',
        reason: 'Physical count',
      );
      final row = (await db
          .customSelect(
            "SELECT quantity FROM business_warehouse_stocks WHERE warehouse_id = '$warehouse'",
          )
          .getSingle());
      expect(row.read<int>('quantity'), 5000);
      expect(count.displayQuantity(-500), '-0.500');
      expect(
        (await db
                .customSelect(
                  "SELECT user_id FROM audit_logs WHERE action = 'warehouse_stocktake'",
                )
                .getSingle())
            .read<int>('user_id'),
        77,
      );
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        service.postCount(item: count, countedQuantity: '8', reason: 'Stale'),
        throwsStateError,
      );
      expect(await fixtures.legacySnapshot(db), before);
    },
  );

  for (final revoke in ['role', 'license', 'remote']) {
    test('stocktake rechecks $revoke after preview', () async {
      final item = (await service.items(warehouse, query: 'wac')).single;
      await service.initialize(
        warehouseId: warehouse,
        item: item,
        cost: '2.50',
      );
      final count = (await service.countItems(warehouse)).single;
      if (revoke == 'role') {
        await db.customStatement(
          "UPDATE users SET role = 'manager' WHERE id = 77",
        );
      }
      if (revoke == 'license') license.allowed = false;
      if (revoke == 'remote') remote = true;
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        service.postCount(item: count, countedQuantity: '5', reason: 'Count'),
        throwsA(isA<WarehouseSetupDenied>()),
      );
      expect(await fixtures.legacySnapshot(db), before);
    });
  }
  test(
    'renames branch and warehouse without changing stable identities',
    () async {
      final before = await WarehouseOperationScope.resolve(db);
      final branchBefore = await (db.select(
        db.businessBranches,
      )..where((row) => row.id.equals(before.branchId))).getSingle();
      final warehouseBefore = await (db.select(
        db.businessWarehouses,
      )..where((row) => row.id.equals(before.warehouseId))).getSingle();

      final branch = await service.renameBranch(
        branchId: branchBefore.id,
        name: 'Head office',
      );
      final renamedWarehouse = await service.renameWarehouse(
        warehouseId: warehouseBefore.id,
        name: 'Central stock',
      );

      expect(branch.id, branchBefore.id);
      expect(branch.code, branchBefore.code);
      expect(branch.name, 'Head office');
      expect(renamedWarehouse.id, warehouseBefore.id);
      expect(renamedWarehouse.code, warehouseBefore.code);
      expect(renamedWarehouse.name, 'Central stock');
      expect(
        (await WarehouseOperationScope.resolve(db)).databaseId,
        before.databaseId,
      );
      final audits =
          await (db.select(db.auditLogs)..where(
                (row) => row.action.isIn(['rename_branch', 'rename_warehouse']),
              ))
              .get();
      expect(audits, hasLength(2));
    },
  );

  test('independent branch cannot rename coordinator locations', () async {
    final primary = await WarehouseOperationScope.resolve(db);
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'lan.branch_sync.coordinator_database_id.v1',
            value: '99999999-9999-4999-8999-999999999999',
          ),
        );
    await expectLater(
      service.renameBranch(branchId: primary.branchId, name: 'Forbidden'),
      throwsA(isA<WarehouseDirectoryAuthorityRequired>()),
    );
    await expectLater(
      service.renameWarehouse(
        warehouseId: primary.warehouseId,
        name: 'Forbidden',
      ),
      throwsA(isA<WarehouseDirectoryAuthorityRequired>()),
    );
  });
}
