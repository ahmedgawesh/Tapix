import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/business/warehouse_stock_initialization_service.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late WarehouseOperationScope scope;
  late WarehouseStockInitializationService initializer;
  late int variant, product, currency;

  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    final primary = await WarehouseOperationScope.resolve(db);
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: '11111111-1111-4111-8111-111111111111',
            organizationId: primary.organizationId,
            branchId: primary.branchId,
            code: 'INIT',
          ),
        );
    scope = await WarehouseOperationScope.resolve(
      db,
      warehouseId: '11111111-1111-4111-8111-111111111111',
    );
    final row = await db
        .customSelect(
          'SELECT v.id, v.product_id, p.currency_id '
          "FROM product_variants v JOIN products p ON p.id = v.product_id WHERE p.costing_method = 'wac' LIMIT 1",
        )
        .getSingle();
    variant = row.read<int>('id');
    product = row.read<int>('product_id');
    currency = row.read<int>('currency_id');
    initializer = WarehouseStockInitializationService(db);
  });
  tearDown(() => db.close());

  Future<int> initialize({int cost = 200}) => initializer.initialize(
    scope: scope,
    currencyId: currency,
    seeds: [WarehouseStockSeed(variantId: variant, unitCostCents: cost)],
  );
  Future<BusinessWarehouseStock> balance() =>
      (db.select(db.businessWarehouseStocks)..where(
            (s) =>
                s.warehouseId.equals(scope.warehouseId) &
                s.variantId.equals(variant),
          ))
          .getSingle();

  test(
    'zero quantity and explicit cost; legacy financial data untouched',
    () async {
      final before = await fixtures.legacySnapshot(db);
      expect(await initialize(), 1);
      expect((await balance()).quantity, 0);
      expect((await balance()).unitCostCents, 200);
      expect(await fixtures.legacySnapshot(db), before);
      expect(await initialize(cost: 999), 0);
      expect((await balance()).unitCostCents, 200);
    },
  );

  test(
    'initialization feeds a scoped WAC opening document and balanced journal',
    () async {
      final primary = await WarehouseOperationScope.resolve(db);
      final original =
          await (db.select(db.businessWarehouseStocks)..where(
                (s) =>
                    s.warehouseId.equals(primary.warehouseId) &
                    s.variantId.equals(variant),
              ))
              .getSingle();
      await initialize();
      final service = InventoryAdjustmentService(
        db: db,
        dao: InventoryAdjustmentDao(db),
        journal: JournalEntryService(AccountingRepository(db)),
      );
      await service.adjust(
        productId: product,
        variantId: variant,
        type: InventoryAdjustmentType.openingBalance,
        quantityDelta: 1000,
        reason: 'Documented warehouse opening',
        currencyId: currency,
        scope: scope,
      );
      expect((await balance()).quantity, 1000);
      final row = await db
          .customSelect(
            "SELECT id, total_value_cents FROM inventory_adjustments WHERE warehouse_id = '11111111-1111-4111-8111-111111111111'",
          )
          .getSingle();
      expect(row.read<int>('total_value_cents'), 200);
      final journal = await db
          .customSelect(
            'SELECT SUM(l.debit_cents) d, SUM(l.credit_cents) c '
            'FROM journal_entry_lines l JOIN journal_entries j ON j.id = l.journal_entry_id '
            "WHERE j.source_table = 'inventory_adjustments' AND j.source_id = ?",
            variables: [Variable.withInt(row.read<int>('id'))],
          )
          .getSingle();
      expect(journal.read<int>('d'), 200);
      expect(journal.read<int>('c'), 200);
      expect(await initialize(cost: 999), 0);
      expect((await balance()).quantity, 1000);
      expect((await balance()).unitCostCents, 200);
      expect(
        await (db.select(db.businessWarehouseStocks)..where(
              (s) =>
                  s.warehouseId.equals(primary.warehouseId) &
                  s.variantId.equals(variant),
            ))
            .getSingle(),
        original,
      );
      await service.adjust(
        productId: product,
        variantId: variant,
        type: InventoryAdjustmentType.shrinkage,
        quantityDelta: -1000,
        reason: 'Counted stock depletion',
        currencyId: currency,
        scope: scope,
      );
      await (db.delete(db.businessWarehouseStocks)..where(
            (s) =>
                s.warehouseId.equals(scope.warehouseId) &
                s.variantId.equals(variant),
          ))
          .go();
      await expectLater(initialize(), throwsStateError);
    },
  );

  test('a later invalid seed rolls back every earlier insertion', () async {
    await expectLater(
      initializer.initialize(
        scope: scope,
        currencyId: currency,
        seeds: [
          WarehouseStockSeed(variantId: variant, unitCostCents: 200),
          const WarehouseStockSeed(variantId: 999999, unitCostCents: 200),
        ],
      ),
      throwsStateError,
    );
    expect(
      await (db.select(
        db.businessWarehouseStocks,
      )..where((s) => s.warehouseId.equals(scope.warehouseId))).get(),
      isEmpty,
    );
  });

  test('concurrent retries insert once without resetting the cost', () async {
    final results = await Future.wait([initialize(), initialize()]);
    expect(results.reduce((a, b) => a + b), 1);
    expect((await balance()).quantity, 0);
  });

  test('reject primary and disabled warehouse scopes', () async {
    await expectLater(
      initializer.initialize(
        scope: await WarehouseOperationScope.resolve(db),
        currencyId: currency,
        seeds: [WarehouseStockSeed(variantId: variant, unitCostCents: 0)],
      ),
      throwsStateError,
    );
    await db.customStatement(
      "UPDATE business_warehouses SET is_active = 0 WHERE id = '11111111-1111-4111-8111-111111111111'",
    );
    await expectLater(initialize(), throwsStateError);
  });

  test('scope from another connection is refused', () async {
    final other = fixtures.memoryDb();
    try {
      final foreign = await WarehouseOperationScope.resolve(other);
      await expectLater(
        initializer.initialize(
          scope: foreign,
          currencyId: currency,
          seeds: [WarehouseStockSeed(variantId: variant, unitCostCents: 0)],
        ),
        throwsStateError,
      );
    } finally {
      await other.close();
    }
  });

  for (final explicitVariant in [false, true]) {
    test(
      'batch history blocks empty reconstruction: variant=$explicitVariant',
      () async {
        await db
            .into(db.productBatches)
            .insert(
              ProductBatchesCompanion.insert(
                productId: product,
                variantId: Value(explicitVariant ? variant : null),
                warehouseId: Value(scope.warehouseId),
                batchNumber: 'HISTORY',
                source: const Value('opening'),
                receivedQuantity: 1000,
                remainingQuantity: 0,
                unitCostCents: Decimal.fromInt(200),
              ),
            );
        await expectLater(initialize(), throwsStateError);
        expect(
          await (db.select(
            db.businessWarehouseStocks,
          )..where((s) => s.warehouseId.equals(scope.warehouseId))).get(),
          isEmpty,
        );
      },
    );
  }

  test('reject duplicates and negative costs', () async {
    await expectLater(initialize(cost: -1), throwsArgumentError);
    final seed = WarehouseStockSeed(variantId: variant, unitCostCents: 0);
    await expectLater(
      initializer.initialize(
        scope: scope,
        currencyId: currency,
        seeds: [seed, seed],
      ),
      throwsArgumentError,
    );
  });

  test(
    'reject disabled variants, untracked products and wrong currency',
    () async {
      await db.customStatement(
        'UPDATE product_variants SET is_active = 0 WHERE id = ?',
        [variant],
      );
      await expectLater(initialize(), throwsStateError);
      await db.customStatement(
        'UPDATE product_variants SET is_active = 1 WHERE id = ?',
        [variant],
      );
      await db.customStatement(
        'UPDATE products SET track_inventory = 0 WHERE id = ?',
        [product],
      );
      await expectLater(initialize(), throwsStateError);
      await db.customStatement(
        'UPDATE products SET track_inventory = 1 WHERE id = ?',
        [product],
      );
      final other = await db
          .into(db.currencies)
          .insert(
            CurrenciesCompanion.insert(
              code: 'XYZ',
              name: 'Other',
              symbol: 'X',
              exchangeRate: Decimal.one,
            ),
          );
      await expectLater(
        initializer.initialize(
          scope: scope,
          currencyId: other,
          seeds: [WarehouseStockSeed(variantId: variant, unitCostCents: 200)],
        ),
        throwsStateError,
      );
    },
  );
}
