import 'package:tapix/core/services/batch_service.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/business/warehouse_stocktake_service.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late WarehouseOperationScope scope;
  late InventoryAdjustmentService adjustments;
  late WarehouseStocktakeService service;
  late int product, variant, currency;
  setUp(() async {
    db = fixtures.memoryDb();
    final primary = await WarehouseOperationScope.resolve(db);
    currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    product = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Counted',
            currencyId: Value(currency),
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(900),
          ),
        );
    variant = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: product,
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(900),
          ),
        );
    const other = '55555555-5555-4555-8555-555555555555';
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: other,
            organizationId: primary.organizationId,
            branchId: primary.branchId,
            code: 'COUNT',
          ),
        );
    await db
        .into(db.businessWarehouseStocks)
        .insert(
          BusinessWarehouseStocksCompanion.insert(
            warehouseId: other,
            variantId: variant,
            unitCostCents: const Value(500),
          ),
        );
    scope = await WarehouseOperationScope.resolve(db, warehouseId: other);
    adjustments = InventoryAdjustmentService(
      db: db,
      dao: InventoryAdjustmentDao(db),
      journal: JournalEntryService(AccountingRepository(db)),
    );
    service = WarehouseStocktakeService(db, adjustments);
    await adjustments.adjust(
      productId: product,
      variantId: variant,
      type: InventoryAdjustmentType.openingBalance,
      quantityDelta: 10,
      reason: 'Opening',
      currencyId: currency,
      scope: scope,
    );
  });
  tearDown(() => db.close());
  Future<Object> snapshot() async => [
    await fixtures.legacySnapshot(db),
    (await db.select(db.businessWarehouseStocks).get())
        .map((r) => r.toJson())
        .toList(),
  ];

  test(
    'FIFO valuation preview uses layer costs and rejects changed layers',
    () async {
      await db.customStatement(
        "UPDATE products SET costing_method='fifo' WHERE id=?",
        [product],
      );
      await BatchService.createOpeningBatch(
        db.inventoryAdjustmentDao,
        scope: scope,
        productId: product,
        variantId: variant,
        quantity: 10,
        unitCostCents: 500,
        source: 'opening',
      );
      final observed = await service.capture(scope: scope, variantId: variant);
      final preview = service.previewRevaluation(
        snapshot: observed,
        newUnitCostCents: 800,
      );
      expect(preview.deltaValueCents, 3000);
      await db.customStatement(
        'UPDATE product_batches SET unit_cost_cents = 600 WHERE warehouse_id = ?',
        [scope.warehouseId],
      );
      final before = await snapshot();
      await expectLater(
        service.postRevaluation(preview: preview, reason: 'Stale layer cost'),
        throwsStateError,
      );
      expect(await snapshot(), before);
    },
  );

  test(
    'count shortage and surplus reconcile selected warehouse and GL',
    () async {
      for (final count in [7, 12]) {
        final observed = await service.capture(
          scope: scope,
          variantId: variant,
        );
        final posted = await service.postCounts(
          counts: [WarehouseCount(snapshot: observed, countedQuantity: count)],
          reason: 'Physical count',
        );
        expect(posted, hasLength(1));
        final value = await db
            .customSelect(
              "SELECT SUM(l.debit_cents-l.credit_cents) AS c FROM journal_entry_lines l JOIN journal_entries j ON j.id=l.journal_entry_id JOIN accounts a ON a.id=l.account_id JOIN business_document_locations d ON d.source_table='journal_entries' AND d.source_id=j.id WHERE j.status='posted' AND a.account_code='1200' AND d.warehouse_id=?",
              variables: [Variable.withString(scope.warehouseId)],
            )
            .getSingle();
        expect(value.read<int>('c'), count * 500);
        expect(
          (await service.capture(scope: scope, variantId: variant)).quantity,
          count,
        );
        expect(
          (await db.select(db.productVariants).getSingle()).stockQuantity,
          0,
        );
        await expectLater(
          service.postCounts(
            counts: [
              WarehouseCount(snapshot: observed, countedQuantity: count),
            ],
            reason: 'Retry',
          ),
          throwsStateError,
        );
      }
    },
  );
  test('changed cost invalidates preview without partial writes', () async {
    final observed = await service.capture(scope: scope, variantId: variant);
    await db.customStatement(
      'UPDATE business_warehouse_stocks SET unit_cost_cents=600 WHERE warehouse_id=?',
      [scope.warehouseId],
    );
    final before = await snapshot();
    await expectLater(
      service.postCounts(
        counts: [WarehouseCount(snapshot: observed, countedQuantity: 7)],
        reason: 'Count',
      ),
      throwsStateError,
    );
    expect(await snapshot(), before);
  });
  test(
    'unchanged count creates no adjustment and duplicate lines reject',
    () async {
      final observed = await service.capture(scope: scope, variantId: variant);
      final request = WarehouseCount(snapshot: observed, countedQuantity: 10);
      final before = await snapshot();
      expect(
        await service.postCounts(counts: [request], reason: 'Count'),
        isEmpty,
      );
      await expectLater(
        service.postCounts(counts: [request, request], reason: 'Count'),
        throwsArgumentError,
      );
      expect(await snapshot(), before);
    },
  );
  test('journal failure rolls back stocktake', () async {
    final observed = await service.capture(scope: scope, variantId: variant);
    await db.customStatement(
      "CREATE TRIGGER reject_count_journal BEFORE INSERT ON journal_entries BEGIN SELECT RAISE(ABORT, 'injected'); END",
    );
    final before = await snapshot();
    await expectLater(
      service.postCounts(
        counts: [WarehouseCount(snapshot: observed, countedQuantity: 7)],
        reason: 'Count',
      ),
      throwsA(anything),
    );
    expect(await snapshot(), before);
  });
  test(
    'changed FIFO layer invalidates a count even with unchanged balance',
    () async {
      await db.customStatement(
        "UPDATE products SET costing_method = 'fifo' WHERE id = ?",
        [product],
      );
      final batch = await BatchService.createOpeningBatch(
        db.saleDao,
        scope: scope,
        productId: product,
        variantId: variant,
        quantity: 10,
        unitCostCents: 500,
        source: 'opening',
      );
      final observed = await service.capture(scope: scope, variantId: variant);
      await db.customStatement(
        'UPDATE product_batches SET unit_cost_cents = 600 WHERE id = ?',
        [batch],
      );
      final before = await snapshot();
      await expectLater(
        service.postCounts(
          counts: [WarehouseCount(snapshot: observed, countedQuantity: 7)],
          reason: 'Count',
        ),
        throwsStateError,
      );
      expect(await snapshot(), before);
    },
  );
}
