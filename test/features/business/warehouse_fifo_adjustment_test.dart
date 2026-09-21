import 'package:tapix/core/services/batch_service.dart';
import 'package:tapix/core/services/stock_service.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/business/warehouse_stock_initialization_service.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late WarehouseOperationScope scope, primary;
  late InventoryAdjustmentService service;
  late int product, variant, currency;
  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    primary = await WarehouseOperationScope.resolve(db);
    currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    product = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Measured FIFO',
            currencyId: Value(currency),
            measurementType: const Value('weight'),
            costingMethod: const Value('fifo'),
            stockQuantity: const Value(5000),
            costCents: Decimal.fromInt(9000),
            priceCents: Decimal.fromInt(10000),
          ),
        );
    variant = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: product,
            stockQuantity: const Value(5000),
            costCents: Decimal.fromInt(9000),
            priceCents: Decimal.fromInt(10000),
          ),
        );
    await db
        .into(db.productBatches)
        .insert(
          ProductBatchesCompanion.insert(
            productId: product,
            variantId: Value(variant),
            batchNumber: 'PRIMARY',
            source: const Value('opening'),
            receivedQuantity: 5000,
            remainingQuantity: 5000,
            unitCostCents: Decimal.fromInt(9000),
          ),
        );
    const id = '33333333-3333-4333-8333-333333333333';
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: id,
            organizationId: primary.organizationId,
            branchId: primary.branchId,
            code: 'FIFO-2',
          ),
        );
    scope = await WarehouseOperationScope.resolve(db, warehouseId: id);
    await WarehouseStockInitializationService(db).initialize(
      scope: scope,
      currencyId: currency,
      seeds: [WarehouseStockSeed(variantId: variant, unitCostCents: 1001)],
    );
    service = InventoryAdjustmentService(
      db: db,
      dao: InventoryAdjustmentDao(db),
      journal: JournalEntryService(AccountingRepository(db)),
    );
  });
  tearDown(() => db.close());
  Future<InventoryAdjustmentResult> adjust(
    InventoryAdjustmentType type,
    int qty, {
    bool simple = false,
  }) => service.adjust(
    productId: product,
    variantId: simple ? null : variant,
    type: type,
    quantityDelta: qty,
    reason: 'Warehouse FIFO acceptance',
    currencyId: currency,
    scope: scope,
  );
  Future<List<Object?>> snapshot() async => [
    for (final table in [
      'products',
      'product_variants',
      'business_warehouse_stocks',
      'product_batches',
      'batch_consumptions',
      'inventory_adjustments',
      'inventory_revaluation_layers',
      'journal_entries',
      'journal_entry_lines',
      'business_document_locations',
    ])
      (await db.customSelect('SELECT * FROM $table').get())
          .map((r) => r.data)
          .toList(),
  ];

  Future<void> verifyJournal(
    InventoryAdjustmentResult result,
    int expected,
  ) async {
    expect(result.totalValueCents, expected);
    final totals = await db
        .customSelect(
          'SELECT SUM(debit_cents) d, SUM(credit_cents) c '
          'FROM journal_entry_lines WHERE journal_entry_id = ?',
          variables: [Variable.withInt(result.journalEntryId)],
        )
        .getSingle();
    expect(totals.read<int>('d'), expected);
    expect(totals.read<int>('c'), expected);
    for (final entry in [
      ('inventory_adjustments', result.adjustmentId),
      ('journal_entries', result.journalEntryId),
    ]) {
      final row = await db
          .customSelect(
            'SELECT warehouse_id FROM business_document_locations '
            'WHERE source_table = ? AND source_id = ?',
            variables: [
              Variable.withString(entry.$1),
              Variable.withInt(entry.$2),
            ],
          )
          .getSingle();
      expect(row.read<String>('warehouse_id'), scope.warehouseId);
    }
    final main =
        await (db.select(db.businessWarehouseStocks)..where(
              (s) =>
                  s.warehouseId.equals(primary.warehouseId) &
                  s.variantId.equals(variant),
            ))
            .getSingle();
    expect(main.quantity, 5000);
    expect(main.unitCostCents, 9000);
    expect(
      (await db.select(db.productVariants).get()).first.stockQuantity,
      5000,
    );
    final batch = await (db.select(
      db.productBatches,
    )..where((b) => b.batchNumber.equals('PRIMARY'))).getSingle();
    expect(batch.remainingQuantity, 5000);
  }

  Future<void> verifyRemainingValue(int expected) async {
    final batches = await db
        .customSelect(
          'SELECT COALESCE(SUM(CAST(ROUND('
          '1.0 * remaining_quantity * unit_cost_cents / 1000) AS INTEGER)), 0) value '
          'FROM product_batches WHERE warehouse_id = ?',
          variables: [Variable.withString(scope.warehouseId)],
        )
        .getSingle();
    final ledger = await db
        .customSelect(
          'SELECT COALESCE(SUM(l.debit_cents - l.credit_cents), 0) value '
          'FROM journal_entry_lines l JOIN journal_entries j ON j.id = l.journal_entry_id '
          'JOIN accounts a ON a.id = l.account_id JOIN business_document_locations d '
          "ON d.source_table = 'journal_entries' AND d.source_id = j.id "
          "WHERE a.account_code = '1200' AND j.status = 'posted' AND d.warehouse_id = ?",
          variables: [Variable.withString(scope.warehouseId)],
        )
        .getSingle();
    expect(batches.read<int>('value'), expected);
    expect(ledger.read<int>('value'), expected);
  }

  for (final simple in [false, true]) {
    test(
      'opening, gain and fractional depletion preserve layer value: simple=$simple',
      () async {
        await verifyJournal(
          await adjust(
            InventoryAdjustmentType.openingBalance,
            1000,
            simple: simple,
          ),
          1001,
        );
        await verifyRemainingValue(1001);
        // New layer: round(1001 * .5) = 501, independent of the existing pool.
        await verifyJournal(
          await adjust(InventoryAdjustmentType.gain, 500, simple: simple),
          501,
        );
        await verifyRemainingValue(1502);
        // First old half removes1001-501=500; second removes501-0=501.
        await verifyJournal(
          await adjust(InventoryAdjustmentType.shrinkage, -500, simple: simple),
          500,
        );
        await verifyRemainingValue(1002);
        await verifyJournal(
          await adjust(InventoryAdjustmentType.shrinkage, -500, simple: simple),
          501,
        );
        await verifyRemainingValue(501);
        await verifyJournal(
          await adjust(InventoryAdjustmentType.shrinkage, -500, simple: simple),
          501,
        );
        await verifyRemainingValue(0);
        final stock = await (db.select(
          db.businessWarehouseStocks,
        )..where((s) => s.warehouseId.equals(scope.warehouseId))).getSingle();
        expect(stock.quantity, 0);
      },
    );
  }

  test(
    'explicit variant does not require other variants initialized in this warehouse',
    () async {
      await (db.update(db.products)..where((p) => p.id.equals(product))).write(
        const ProductsCompanion(hasVariants: Value(true)),
      );
      final size = await db.customInsert(
        "INSERT INTO sizes (name) VALUES ('XL')",
      );
      await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: product,
              sizeId: Value(size),
              costCents: Decimal.fromInt(700),
              priceCents: Decimal.fromInt(900),
            ),
          );
      await verifyJournal(
        await adjust(InventoryAdjustmentType.gain, 1000),
        1001,
      );
    },
  );

  test(
    'journal failure rolls back quantity, FIFO layers and consumption',
    () async {
      await adjust(InventoryAdjustmentType.openingBalance, 1000);
      final before = await snapshot();
      await db.customStatement(
        "CREATE TRIGGER fifo_journal_failure BEFORE INSERT ON journal_entries BEGIN SELECT RAISE(ABORT, 'Injected failure'); END",
      );
      await expectLater(
        adjust(InventoryAdjustmentType.shrinkage, -500),
        throwsA(anything),
      );
      expect(await snapshot(), before);
    },
  );

  test('shortage cannot consume another warehouse layers', () async {
    final before = await snapshot();
    await expectLater(
      adjust(InventoryAdjustmentType.shrinkage, -1000),
      throwsA(isA<InventoryAdjustmentException>()),
    );
    expect(await snapshot(), before);
  });

  for (final method in ['wac', 'fifo']) {
    test(
      '$method expiry adjustments preserve metadata and consume selected batch only',
      () async {
        await db.customStatement(
          "UPDATE products SET inventory_tracking_type = 'batch_expiry', costing_method = ? WHERE id = ?",
          [method, product],
        );
        Future<InventoryAdjustmentResult> receive(
          int quantity,
          DateTime expiry,
          String lot,
        ) => service.adjust(
          productId: product,
          variantId: variant,
          scope: scope,
          type: InventoryAdjustmentType.gain,
          quantityDelta: quantity,
          currencyId: currency,
          reason: 'Counted physical batch',
          expiryDate: expiry,
          manufacturerLotNumber: lot,
        );
        await receive(1000, DateTime(2027, 1, 1), 'EARLY');
        await receive(500, DateTime(2028, 1, 1), 'LATE');
        final batches =
            await (db.select(db.productBatches)
                  ..where((b) => b.warehouseId.equals(scope.warehouseId))
                  ..orderBy([(b) => OrderingTerm.asc(b.id)]))
                .get();
        expect(batches.length, 2);
        expect(batches.last.manufacturerLotNumber, 'LATE');
        expect(batches.last.expiryDate!.year, 2028);
        expect(batches.last.expiryDate!.month, 1);
        expect(batches.last.expiryDate!.day, 1);
        final before = await snapshot();
        final primaryBatch = await (db.select(
          db.productBatches,
        )..where((b) => b.batchNumber.equals('PRIMARY'))).getSingle();
        await expectLater(
          service.adjust(
            productId: product,
            variantId: variant,
            scope: scope,
            type: InventoryAdjustmentType.shrinkage,
            quantityDelta: -500,
            batchId: primaryBatch.id,
            currencyId: currency,
            reason: 'Foreign lot',
          ),
          throwsA(anything),
        );
        expect(await snapshot(), before);
        final result = await service.adjust(
          productId: product,
          variantId: variant,
          scope: scope,
          type: InventoryAdjustmentType.shrinkage,
          quantityDelta: -500,
          batchId: batches.last.id,
          currencyId: currency,
          reason: 'Damaged late lot',
        );
        await verifyJournal(result, 501);
        expect(
          (await (db.select(
                db.productBatches,
              )..where((b) => b.id.equals(batches.first.id))).getSingle())
              .remainingQuantity,
          1000,
        );
        expect(
          (await (db.select(
                db.productBatches,
              )..where((b) => b.id.equals(batches.last.id))).getSingle())
              .remainingQuantity,
          0,
        );
        await verifyRemainingValue(1001);
      },
    );
  }

  test(
    'FIFO revaluation preserves historical restores and exact layer journals',
    () async {
      await adjust(InventoryAdjustmentType.openingBalance, 3000);
      final shortage = await adjust(InventoryAdjustmentType.shrinkage, -1000);
      final result = await service.adjust(
        productId: product,
        variantId: variant,
        scope: scope,
        type: InventoryAdjustmentType.revaluation,
        newUnitCostCents: 2000,
        currencyId: currency,
        reason: 'Layer valuation review',
      );
      await verifyJournal(result, 1998);
      await verifyRemainingValue(4000);
      final audit = await db.select(db.inventoryRevaluationLayers).getSingle();
      expect(audit.quantity, 2000);
      expect(audit.oldUnitCostCents, 1001);
      expect(audit.newUnitCostCents, 2000);
      await expectLater(
        db.customStatement(
          'UPDATE inventory_revaluation_layers SET quantity = 1',
        ),
        throwsA(anything),
      );
      final beforeForbiddenRestore = await snapshot();
      await expectLater(
        BatchService.restoreConsumptions(
          db.inventoryAdjustmentDao,
          scope: scope,
          inventoryAdjustmentId: result.adjustmentId,
          reverseConsumptionType: 'invalid_revaluation_restore',
        ),
        throwsStateError,
      );
      expect(await snapshot(), beforeForbiddenRestore);
      await db.transaction(() async {
        await BatchService.restoreConsumptions(
          db.inventoryAdjustmentDao,
          scope: scope,
          inventoryAdjustmentId: shortage.adjustmentId,
          reverseConsumptionType: 'void_inventory_shrinkage',
        );
        await StockService.adjustStock(
          db.inventoryAdjustmentDao,
          scope: scope,
          productId: product,
          variantId: variant,
          quantity: 1000,
          direction: StockDirection.increase,
        );
        await JournalEntryService(
          AccountingRepository(db),
        ).voidJournalEntriesForSource(
          sourceTable: 'inventory_adjustments',
          sourceId: shortage.adjustmentId,
          reason: 'Restore pre-revaluation shortage',
          userId: null,
        );
      });
      await verifyRemainingValue(5001);
      final old = await (db.select(
        db.productBatches,
      )..where((b) => b.id.equals(audit.oldBatchId))).getSingle();
      expect(old.remainingQuantity, 1000);
      expect(old.unitCostCents.toBigInt().toInt(), 1001);
      await verifyJournal(
        await adjust(InventoryAdjustmentType.shrinkage, -1500),
        2001,
      );
      await verifyRemainingValue(3000);
    },
  );

  test(
    'FIFO revaluation journal failure rolls back layer split and audit',
    () async {
      await adjust(InventoryAdjustmentType.openingBalance, 1500);
      final before = await snapshot();
      await db.customStatement(
        "CREATE TRIGGER reject_revaluation BEFORE INSERT ON journal_entries BEGIN SELECT RAISE(ABORT, 'injected revaluation failure'); END",
      );
      await expectLater(
        service.adjust(
          productId: product,
          variantId: variant,
          scope: scope,
          type: InventoryAdjustmentType.revaluation,
          newUnitCostCents: 2000,
          currencyId: currency,
          reason: 'Failure test',
        ),
        throwsA(anything),
      );
      expect(await snapshot(), before);
    },
  );

  test(
    'missing expiry metadata and FIFO revaluation without stock stay blocked',
    () async {
      final before = await snapshot();
      await expectLater(
        service.adjust(
          productId: product,
          variantId: variant,
          type: InventoryAdjustmentType.revaluation,
          newUnitCostCents: 2000,
          reason: 'Blocked layer revaluation',
          currencyId: currency,
          scope: scope,
        ),
        throwsA(isA<InventoryAdjustmentException>()),
      );
      expect(await snapshot(), before);
      await db.customStatement(
        "UPDATE products SET inventory_tracking_type = 'batch_expiry' WHERE id = ?",
        [product],
      );
      final expiryBefore = await snapshot();
      await expectLater(
        adjust(InventoryAdjustmentType.gain, 1000),
        throwsA(isA<InventoryAdjustmentException>()),
      );
      expect(await snapshot(), expiryBefore);
    },
  );
}
