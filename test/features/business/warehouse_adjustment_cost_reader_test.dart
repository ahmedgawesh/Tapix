import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/database/migrations/business_warehouse_stock.dart';
import 'package:tapix/core/services/business/document_posting_scope.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/inventory/costing_strategy.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:uuid/uuid.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int product, variant;
  late WarehouseOperationScope selected;
  const strategy = WeightedAverageCostingStrategy();
  setUp(() async {
    db = fixtures.memoryDb();
    await fixtures.seedLegacyData(db);
    final row = await db
        .customSelect(
          'SELECT id, product_id FROM product_variants ORDER BY id LIMIT 1',
        )
        .getSingle();
    product = row.read<int>('product_id');
    variant = row.read<int>('id');
    final primary = await WarehouseOperationScope.resolve(db);
    final other = const Uuid().v4();
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: other,
            organizationId: primary.organizationId,
            branchId: primary.branchId,
            code: 'READER',
          ),
        );
    selected = await WarehouseOperationScope.resolve(db, warehouseId: other);
    await db
        .into(db.businessWarehouseStocks)
        .insert(
          BusinessWarehouseStocksCompanion.insert(
            warehouseId: other,
            variantId: variant,
            quantity: const Value(55),
            unitCostCents: const Value(999),
          ),
        );
  });
  tearDown(() => db.close());
  Future<void> corruptMirrors() async {
    await removeBusinessWarehouseStockTriggers(db);
    await db.customStatement(
      'UPDATE products SET stock_quantity = 9999, cost_cents = 99999 WHERE id = ?',
      [product],
    );
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = 8888, cost_cents = 88888 WHERE id = ?',
      [variant],
    );
  }

  for (final explicit in [false, true]) {
    test(
      'cost reader uses warehouse values despite stale mirrors explicit=$explicit',
      () async {
        await corruptMirrors();
        expect(
          await strategy.unitCostCents(
            dao: db.productDao,
            productId: product,
            variantId: explicit ? variant : null,
          ),
          701,
        );
        expect(
          await strategy.onHandQuantity(
            dao: db.productDao,
            productId: product,
            variantId: explicit ? variant : null,
          ),
          1234,
        );
        expect(
          await strategy.unitCostCents(
            dao: db.productDao,
            productId: product,
            variantId: explicit ? variant : null,
            scope: selected,
          ),
          999,
        );
        expect(
          await strategy.onHandQuantity(
            dao: db.productDao,
            productId: product,
            variantId: explicit ? variant : null,
            scope: selected,
          ),
          55,
        );
      },
    );
  }

  test(
    'wrong variant ownership and unknown variant do not fall back to parent cost',
    () async {
      final other = (await db.select(db.products).get()).firstWhere(
        (p) => p.id != product,
      );
      await expectLater(
        strategy.unitCostCents(
          dao: db.productDao,
          productId: other.id,
          variantId: variant,
        ),
        throwsStateError,
      );
      await expectLater(
        strategy.onHandQuantity(
          dao: db.productDao,
          productId: product,
          variantId: 999999,
        ),
        throwsStateError,
      );
    },
  );

  test('multiple variants require explicit selection', () async {
    await (db.update(db.products)..where((p) => p.id.equals(product))).write(
      const ProductsCompanion(hasVariants: Value(true)),
    );
    await expectLater(
      strategy.unitCostCents(dao: db.productDao, productId: product),
      throwsStateError,
    );
    expect(
      await strategy.unitCostCents(
        dao: db.productDao,
        productId: product,
        variantId: variant,
      ),
      701,
    );
  });

  test('legacy no-variant fallback is primary only', () async {
    final legacy = await db.customInsert(
      "INSERT INTO products (name,cost_cents,price_cents,stock_quantity) VALUES ('Legacy',123,500,7)",
    );
    expect(
      await strategy.unitCostCents(dao: db.productDao, productId: legacy),
      123,
    );
    await expectLater(
      strategy.unitCostCents(
        dao: db.productDao,
        productId: legacy,
        scope: selected,
      ),
      throwsStateError,
    );
  });

  test(
    'real shrinkage posts the warehouse value despite stale cost mirrors',
    () async {
      await corruptMirrors();
      final currency = (await (db.select(
        db.products,
      )..where((p) => p.id.equals(product))).getSingle()).currencyId!;
      final service = InventoryAdjustmentService(
        db: db,
        dao: InventoryAdjustmentDao(db),
        journal: JournalEntryService(AccountingRepository(db)),
      );
      final result = await service.adjust(
        productId: product,
        variantId: variant,
        type: InventoryAdjustmentType.shrinkage,
        quantityDelta: -234,
        reason: 'Warehouse cost regression',
        currencyId: currency,
      );
      expect(result.totalValueCents, 164);
      final totals = await db
          .customSelect(
            'SELECT SUM(debit_cents) d, SUM(credit_cents) c FROM journal_entry_lines WHERE journal_entry_id = ?',
            variables: [Variable.withInt(result.journalEntryId)],
          )
          .getSingle();
      expect(totals.read<int>('d'), 164);
      expect(totals.read<int>('c'), 164);
    },
  );

  test(
    'document resolver uses recorded warehouse while default validation stays primary',
    () async {
      final sale = (await db.select(db.sales).get()).single;
      final primary = await DocumentPostingScope.resolveForDocument(
        db,
        InventoryPostingDocument.sale,
        sale.id,
      );
      expect(primary.isPrimary, isTrue);
      // Future scoped document fixture only: production still forbids moving it.
      await db.customStatement('DROP TRIGGER business_location_immutable');
      await db.customStatement(
        "UPDATE business_document_locations SET warehouse_id = ? WHERE source_table = 'sales' AND source_id = ?",
        [selected.warehouseId, sale.id],
      );
      await expectLater(
        DocumentPostingScope.validate(
          db,
          InventoryPostingDocument.sale,
          sale.id,
        ),
        throwsStateError,
      );
      final resolved = await DocumentPostingScope.resolveForDocument(
        db,
        InventoryPostingDocument.sale,
        sale.id,
      );
      expect(resolved.warehouseId, selected.warehouseId);
      await (db.update(db.businessWarehouses)
            ..where((w) => w.id.equals(selected.warehouseId)))
          .write(const BusinessWarehousesCompanion(isActive: Value(false)));
      await expectLater(
        DocumentPostingScope.resolveForDocument(
          db,
          InventoryPostingDocument.sale,
          sale.id,
        ),
        throwsStateError,
      );
    },
  );

  Future<InventoryAdjustmentResult> adjustSelected(
    InventoryAdjustmentType type, {
    int quantity = 0,
    int? cost,
  }) async {
    final currency = (await (db.select(
      db.products,
    )..where((p) => p.id.equals(product))).getSingle()).currencyId!;
    return InventoryAdjustmentService(
      db: db,
      dao: InventoryAdjustmentDao(db),
      journal: JournalEntryService(AccountingRepository(db)),
    ).adjust(
      productId: product,
      variantId: variant,
      type: type,
      quantityDelta: quantity,
      newUnitCostCents: cost,
      reason: 'Selected warehouse acceptance',
      currencyId: currency,
      scope: selected,
    );
  }

  for (final type in [
    InventoryAdjustmentType.gain,
    InventoryAdjustmentType.shrinkage,
    InventoryAdjustmentType.revaluation,
    InventoryAdjustmentType.openingBalance,
  ]) {
    test(
      'selected warehouse adjustment and journal are atomic: ${type.name}',
      () async {
        final before = await db
            .customSelect(
              'SELECT stock_quantity, cost_cents FROM product_variants WHERE id = ?',
              variables: [Variable.withInt(variant)],
            )
            .getSingle();
        final delta = type == InventoryAdjustmentType.shrinkage
            ? -10
            : type == InventoryAdjustmentType.revaluation
            ? 0
            : 10;
        final result = await adjustSelected(
          type,
          quantity: delta,
          cost: type == InventoryAdjustmentType.revaluation ? 1999 : null,
        );
        expect(
          result.totalValueCents,
          type == InventoryAdjustmentType.revaluation ? 55 : 10,
        );
        for (final source in ['inventory_adjustments', 'journal_entries']) {
          final location = await db
              .customSelect(
                'SELECT warehouse_id FROM business_document_locations WHERE source_table = ? AND source_id = ?',
                variables: [
                  Variable.withString(source),
                  Variable.withInt(
                    source == 'inventory_adjustments'
                        ? result.adjustmentId
                        : result.journalEntryId,
                  ),
                ],
              )
              .getSingle();
          expect(location.read<String>('warehouse_id'), selected.warehouseId);
        }
        expect(
          await strategy.onHandQuantity(
            dao: db.productDao,
            productId: product,
            variantId: variant,
            scope: selected,
          ),
          55 + delta,
        );
        expect(
          await strategy.unitCostCents(
            dao: db.productDao,
            productId: product,
            variantId: variant,
            scope: selected,
          ),
          type == InventoryAdjustmentType.revaluation ? 1999 : 999,
        );
        final after = await db
            .customSelect(
              'SELECT stock_quantity, cost_cents FROM product_variants WHERE id = ?',
              variables: [Variable.withInt(variant)],
            )
            .getSingle();
        expect(after.data, before.data);
        final totals = await db
            .customSelect(
              'SELECT SUM(debit_cents) d, SUM(credit_cents) c FROM journal_entry_lines WHERE journal_entry_id = ?',
              variables: [Variable.withInt(result.journalEntryId)],
            )
            .getSingle();
        expect(totals.read<int>('d'), result.totalValueCents);
        expect(totals.read<int>('c'), result.totalValueCents);
      },
    );
  }

  test('failed journal rolls back selected warehouse and adjustment', () async {
    final before = await fixtures.legacySnapshot(db);
    await db.customStatement("""
      CREATE TRIGGER fail_adjustment_journal BEFORE INSERT ON journal_entries
      WHEN NEW.source_table = 'inventory_adjustments'
      BEGIN SELECT RAISE(ABORT, 'injected journal failure'); END
    """);
    await expectLater(
      adjustSelected(InventoryAdjustmentType.gain, quantity: 10),
      throwsA(anything),
    );
    expect(await fixtures.legacySnapshot(db), before);
    expect(
      await strategy.onHandQuantity(
        dao: db.productDao,
        productId: product,
        variantId: variant,
        scope: selected,
      ),
      55,
    );
  });

  test('selected revaluation uses rounded pool difference', () async {
    await db.customStatement(
      'UPDATE business_warehouse_stocks SET quantity = 1, unit_cost_cents = 499 WHERE warehouse_id = ? AND variant_id = ?',
      [selected.warehouseId, variant],
    );
    final result = await adjustSelected(
      InventoryAdjustmentType.revaluation,
      cost: 501,
    );
    expect(result.totalValueCents, 1);
  });

  test(
    'adjustment route, currency and journal ownership cannot be changed',
    () async {
      final first = await adjustSelected(
        InventoryAdjustmentType.gain,
        quantity: 10,
      );
      final second = await adjustSelected(
        InventoryAdjustmentType.gain,
        quantity: 10,
      );
      await expectLater(
        db.customStatement(
          'UPDATE inventory_adjustments SET warehouse_id = NULL WHERE id = ?',
          [first.adjustmentId],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'UPDATE inventory_adjustments SET currency_id = currency_id + 1 WHERE id = ?',
          [first.adjustmentId],
        ),
        throwsA(anything),
      );
      await expectLater(
        InventoryAdjustmentDao(db).linkJournalEntry(
          adjustmentId: first.adjustmentId,
          journalEntryId: second.journalEntryId,
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'UPDATE journal_entries SET source_id = ? WHERE id = ?',
          [second.adjustmentId, first.journalEntryId],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'UPDATE journal_entry_lines SET currency_id = currency_id + 1 WHERE journal_entry_id = ?',
          [first.journalEntryId],
        ),
        throwsA(anything),
      );
    },
  );

  test(
    'unbalanced FIFO and inactive warehouses reject adjustment without writes',
    () async {
      await db.customStatement(
        "UPDATE products SET costing_method = 'fifo' WHERE id = ?",
        [product],
      );
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        adjustSelected(InventoryAdjustmentType.gain, quantity: 10),
        throwsStateError,
      );
      expect(await fixtures.legacySnapshot(db), before);
      await db.customStatement(
        "UPDATE products SET costing_method = 'wac' WHERE id = ?",
        [product],
      );
      await db.customStatement(
        'UPDATE business_warehouses SET is_active = 0 WHERE id = ?',
        [selected.warehouseId],
      );
      await expectLater(
        adjustSelected(InventoryAdjustmentType.gain, quantity: 10),
        throwsStateError,
      );
    },
  );

  test('selected explicit variant supports multi-variant product', () async {
    await (db.update(db.products)..where((p) => p.id.equals(product))).write(
      const ProductsCompanion(hasVariants: Value(true)),
    );
    final gain = await adjustSelected(
      InventoryAdjustmentType.gain,
      quantity: 10,
    );
    expect(gain.totalValueCents, 10);
    await adjustSelected(InventoryAdjustmentType.revaluation, cost: 1999);
    expect(
      await strategy.unitCostCents(
        dao: db.productDao,
        productId: product,
        variantId: variant,
        scope: selected,
      ),
      1999,
    );
    expect(
      await strategy.unitCostCents(
        dao: db.productDao,
        productId: product,
        variantId: variant,
      ),
      701,
    );
  });

  test('selected adjustment rejects a different active currency', () async {
    final productCurrency = (await (db.select(
      db.products,
    )..where((p) => p.id.equals(product))).getSingle()).currencyId!;
    final otherCurrency = (await db.select(db.currencies).get()).firstWhere(
      (c) => c.id != productCurrency && c.isActive,
    );
    final before = await fixtures.legacySnapshot(db);
    await expectLater(
      InventoryAdjustmentService(
        db: db,
        dao: InventoryAdjustmentDao(db),
        journal: JournalEntryService(AccountingRepository(db)),
      ).adjust(
        productId: product,
        variantId: variant,
        type: InventoryAdjustmentType.gain,
        quantityDelta: 10,
        reason: 'Wrong currency',
        currencyId: otherCurrency.id,
        scope: selected,
      ),
      throwsA(isA<InventoryAdjustmentException>()),
    );
    expect(await fixtures.legacySnapshot(db), before);
  });

  test('missing document cannot resolve an operation scope', () async {
    await expectLater(
      DocumentPostingScope.resolveForDocument(
        db,
        InventoryPostingDocument.sale,
        999999,
      ),
      throwsStateError,
    );
  });
}
