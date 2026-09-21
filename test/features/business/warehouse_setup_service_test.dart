import 'package:tapix/core/services/business/warehouse_stocktake_service.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
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
}
