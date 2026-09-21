import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/inventory_adjustment_dao.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

/// Integration tests for the new `InventoryAdjustmentService`.
///
/// Invariants under test:
///   - Shrinkage  → balanced JE: Dr 5800 / Cr 1200, value = |qty| × cost
///   - Gain       → balanced JE: Dr 1200 / Cr 4200, value = |qty| × cost
///   - Revalue ↑  → balanced JE: Dr 1200 / Cr 5900
///   - Revalue ↓  → balanced JE: Dr 5900 / Cr 1200
///   - Stock ledger mutates only for shrinkage / gain (not revaluation)
///   - Adjustment row is linked to the posted JE
///   - Empty/blank reason is rejected BEFORE any DB write
///   - Shrinkage below zero is rejected
///   - Sign mismatches (negative gain, positive shrinkage) are rejected
void main() {
  late AppDatabase db;
  late InventoryAdjustmentDao adjDao;
  late JournalEntryService journal;
  late InventoryAdjustmentService service;

  late int currencyId;
  late int productId;
  late int variantId;

  Future<int> accountIdByCode(String code) async {
    final row = await db
        .customSelect(
          'SELECT id FROM accounts WHERE account_code = ?',
          variables: [Variable.withString(code)],
        )
        .getSingle();
    return row.read<int>('id');
  }

  Future<List<({int accountId, int debitCents, int creditCents})>>
  linesForAdjustment(int adjustmentId) async {
    final rows = await db
        .customSelect(
          'SELECT jel.account_id, jel.debit_cents, jel.credit_cents '
          'FROM journal_entry_lines jel '
          'INNER JOIN journal_entries je ON je.id = jel.journal_entry_id '
          'WHERE je.source_table = ? AND je.source_id = ? AND je.status = ?',
          variables: [
            Variable.withString('inventory_adjustments'),
            Variable.withInt(adjustmentId),
            Variable.withString('posted'),
          ],
        )
        .get();
    return rows
        .map(
          (r) => (
            accountId: r.read<int>('account_id'),
            debitCents: r.read<int>('debit_cents'),
            creditCents: r.read<int>('credit_cents'),
          ),
        )
        .toList();
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    adjDao = InventoryAdjustmentDao(db);
    final accountingRepo = AccountingRepository(db);
    journal = JournalEntryService(accountingRepo);
    service = InventoryAdjustmentService(db: db, dao: adjDao, journal: journal);

    // Force DB init (seeds accounts, currencies)
    await db.customSelect('SELECT 1').get();

    // Seed a system user so FK constraints on posted_by / created_by pass
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );

    // Seed product + variant (cost = $30, stock = 100 units)
    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    currencyId = usd.id;

    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: const Value<String?>('INV-ADJ-001'),
            name: 'Inventory Adj Test Product',
            costCents: Decimal.fromInt(3000),
            priceCents: Decimal.fromInt(5000),
            currencyId: Value(currencyId),
            stockQuantity: const Value(100),
          ),
        );

    variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(100),
            costCents: Decimal.fromInt(3000),
            priceCents: Decimal.fromInt(5000),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> seedFifoLayers() async {
    await db.customStatement(
      "UPDATE products SET costing_method = 'fifo' WHERE id = ?",
      [productId],
    );
    for (final layer in [(2, 100), (98, 300)]) {
      await db
          .into(db.productBatches)
          .insert(
            ProductBatchesCompanion.insert(
              productId: productId,
              variantId: Value(variantId),
              batchNumber: 'LAYER-${layer.$2}',
              source: const Value('opening'),
              receivedQuantity: layer.$1,
              remainingQuantity: layer.$1,
              unitCostCents: Decimal.fromInt(layer.$2),
              receivedDate: Value(DateTime(2026, 1, layer.$2 == 100 ? 1 : 2)),
            ),
          );
    }
  }

  for (final explicitVariant in [false, true]) {
    test(
      'FIFO shrinkage posts consumed layer costs: variant=$explicitVariant',
      () async {
        await seedFifoLayers();
        if (explicitVariant) {
          await db.customStatement(
            'UPDATE product_variants SET cost_cents = 0 WHERE id = ?',
            [variantId],
          );
        }
        final result = await service.adjust(
          productId: productId,
          variantId: explicitVariant ? variantId : null,
          type: InventoryAdjustmentType.shrinkage,
          quantityDelta: -3,
          reason: 'Counted damaged stock',
          currencyId: currencyId,
          userId: 0,
        );
        // Two from the oldest layer at100, then one at300; display cost is3000.
        expect(result.totalValueCents, 500);
        final lines = await linesForAdjustment(result.adjustmentId);
        expect(lines.fold<int>(0, (s, l) => s + l.debitCents), 500);
        expect(lines.fold<int>(0, (s, l) => s + l.creditCents), 500);
        final row = (await adjDao.getById(result.adjustmentId))!;
        expect(row.totalValueCents, Decimal.fromInt(500));
        expect(row.costingMethod, 'fifo');
        expect(row.unitCostCents, Decimal.fromInt(167));
        expect(
          (await db.select(db.productVariants).getSingle()).stockQuantity,
          97,
        );
        final layers = await (db.select(
          db.productBatches,
        )..orderBy([(b) => OrderingTerm.asc(b.id)])).get();
        expect(layers.map((l) => l.remainingQuantity), [0, 97]);
      },
    );
  }

  test('FIFO journal failure rolls back stock, layers and adjustment', () async {
    await seedFifoLayers();
    await db.customStatement(
      "CREATE TRIGGER reject_fifo_journal BEFORE INSERT ON journal_entries BEGIN SELECT RAISE(ABORT, 'Injected failure'); END",
    );
    await expectLater(
      service.adjust(
        productId: productId,
        variantId: variantId,
        type: InventoryAdjustmentType.shrinkage,
        quantityDelta: -3,
        reason: 'Rollback test',
        currencyId: currencyId,
        userId: 0,
      ),
      throwsA(anything),
    );
    expect(
      (await db.select(db.productVariants).getSingle()).stockQuantity,
      100,
    );
    expect(await db.select(db.inventoryAdjustments).get(), isEmpty);
    expect(await db.select(db.batchConsumptions).get(), isEmpty);
    final layers = await (db.select(
      db.productBatches,
    )..orderBy([(b) => OrderingTerm.asc(b.id)])).get();
    expect(layers.map((l) => l.remainingQuantity), [2, 98]);
  });

  test(
    'FIFO revaluation uses real layers and preserves their historical costs',
    () async {
      await seedFifoLayers();
      final result = await service.adjust(
        productId: productId,
        variantId: variantId,
        type: InventoryAdjustmentType.revaluation,
        newUnitCostCents: 4000,
        reason: 'Revalue remaining layers',
        currencyId: currencyId,
        userId: 0,
      );
      expect(result.totalValueCents, 370400); // 400000 - (2*100 + 98*300)
      final original =
          await (db.select(db.productBatches)
                ..where((b) => b.source.equals('opening'))
                ..orderBy([(b) => OrderingTerm.asc(b.id)]))
              .get();
      expect(original.map((b) => b.unitCostCents.toBigInt().toInt()), [
        100,
        300,
      ]);
      expect(original.map((b) => b.remainingQuantity), [0, 0]);
      final layers = await db.select(db.inventoryRevaluationLayers).get();
      expect(layers.length, 2);
      expect(
        layers.fold<int>(
          0,
          (sum, r) => sum + r.newValueCents - r.previousValueCents,
        ),
        370400,
      );
      expect(
        (await db.select(db.productVariants).getSingle()).stockQuantity,
        100,
      );
    },
  );
  group('Chart of Accounts', () {
    test('seeds 4200, 5800, 5900 on init', () async {
      final gain = await accountIdByCode('4200');
      final shrinkage = await accountIdByCode('5800');
      final revaluation = await accountIdByCode('5900');
      expect(gain, greaterThan(0));
      expect(shrinkage, greaterThan(0));
      expect(revaluation, greaterThan(0));
    });
  });

  group('Shrinkage', () {
    test(
      'balanced JE Dr 5800 / Cr 1200, stock decreased, row linked',
      () async {
        final result = await service.adjust(
          productId: productId,
          variantId: variantId,
          type: InventoryAdjustmentType.shrinkage,
          quantityDelta: -5,
          reason: 'Damaged during shelving',
          currencyId: currencyId,
          userId: 0,
        );

        // Value = 5 × $30 = $150
        expect(result.totalValueCents, equals(15000));

        final lines = await linesForAdjustment(result.adjustmentId);
        expect(lines.length, equals(2));
        final totalD = lines.fold<int>(0, (s, l) => s + l.debitCents);
        final totalC = lines.fold<int>(0, (s, l) => s + l.creditCents);
        expect(totalD, equals(totalC), reason: 'must balance');
        expect(totalD, equals(15000));

        final shrinkageId = await accountIdByCode('5800');
        final inventoryId = await accountIdByCode('1200');
        final debit = lines.firstWhere((l) => l.debitCents > 0);
        final credit = lines.firstWhere((l) => l.creditCents > 0);
        expect(debit.accountId, equals(shrinkageId));
        expect(credit.accountId, equals(inventoryId));

        // Stock decreased from 100 → 95 on the variant
        final v = await (db.select(
          db.productVariants,
        )..where((x) => x.id.equals(variantId))).getSingle();
        expect(v.stockQuantity, equals(95));

        // Adjustment row links back to the JE
        final row = await adjDao.getById(result.adjustmentId);
        expect(row, isNotNull);
        expect(row!.journalEntryId, equals(result.journalEntryId));
        expect(row.costingMethod, equals('weighted_average'));
        expect(row.adjustmentType, equals('shrinkage'));
      },
    );

    test('rejects empty / whitespace reason without touching DB', () async {
      expect(
        () => service.adjust(
          productId: productId,
          variantId: variantId,
          type: InventoryAdjustmentType.shrinkage,
          quantityDelta: -1,
          reason: '   ',
          currencyId: currencyId,
        ),
        throwsA(isA<InventoryAdjustmentException>()),
      );

      // No row written
      final count = await db
          .customSelect('SELECT COUNT(*) AS cnt FROM inventory_adjustments')
          .getSingle();
      expect(count.read<int>('cnt'), equals(0));
    });

    test('rejects positive delta (sign mismatch)', () async {
      expect(
        () => service.adjust(
          productId: productId,
          variantId: variantId,
          type: InventoryAdjustmentType.shrinkage,
          quantityDelta: 3, // WRONG: must be negative
          reason: 'oops',
          currencyId: currencyId,
        ),
        throwsA(isA<InventoryAdjustmentException>()),
      );
    });

    test('rejects shrink-below-zero', () async {
      expect(
        () => service.adjust(
          productId: productId,
          variantId: variantId,
          type: InventoryAdjustmentType.shrinkage,
          quantityDelta: -500, // stock is only 100
          reason: 'over-shrink',
          currencyId: currencyId,
        ),
        throwsA(isA<InventoryAdjustmentException>()),
      );
    });
  });

  group('Gain', () {
    test('balanced JE Dr 1200 / Cr 4200, stock increased', () async {
      final result = await service.adjust(
        productId: productId,
        variantId: variantId,
        type: InventoryAdjustmentType.gain,
        quantityDelta: 7,
        reason: 'Count surplus after audit',
        currencyId: currencyId,
        userId: 0,
      );

      // 7 × $30 = $210
      expect(result.totalValueCents, equals(21000));

      final lines = await linesForAdjustment(result.adjustmentId);
      expect(lines.length, equals(2));
      final inventoryId = await accountIdByCode('1200');
      final gainId = await accountIdByCode('4200');
      final debit = lines.firstWhere((l) => l.debitCents > 0);
      final credit = lines.firstWhere((l) => l.creditCents > 0);
      expect(debit.accountId, equals(inventoryId));
      expect(credit.accountId, equals(gainId));

      final v = await (db.select(
        db.productVariants,
      )..where((x) => x.id.equals(variantId))).getSingle();
      expect(v.stockQuantity, equals(107));
    });

    test('rejects negative delta', () async {
      expect(
        () => service.adjust(
          productId: productId,
          variantId: variantId,
          type: InventoryAdjustmentType.gain,
          quantityDelta: -3,
          reason: 'bad',
          currencyId: currencyId,
        ),
        throwsA(isA<InventoryAdjustmentException>()),
      );
    });
  });

  group('Revaluation', () {
    test(
      'write-up: Dr 1200 / Cr 5900, cost updated, stock unchanged',
      () async {
        // Cost $30 → $40; on-hand 100 ⇒ delta = +$10 × 100 = +$1000
        final result = await service.adjust(
          productId: productId,
          variantId: variantId,
          type: InventoryAdjustmentType.revaluation,
          quantityDelta: 0,
          newUnitCostCents: 4000,
          reason: 'Supplier price correction (upward)',
          currencyId: currencyId,
          userId: 0,
        );

        expect(result.totalValueCents, equals(100000));

        final lines = await linesForAdjustment(result.adjustmentId);
        expect(lines.length, equals(2));
        final inventoryId = await accountIdByCode('1200');
        final revalId = await accountIdByCode('5900');
        final debit = lines.firstWhere((l) => l.debitCents > 0);
        final credit = lines.firstWhere((l) => l.creditCents > 0);
        expect(debit.accountId, equals(inventoryId));
        expect(credit.accountId, equals(revalId));
        expect(debit.debitCents, equals(100000));

        // Variant cost updated, stock unchanged
        final v = await (db.select(
          db.productVariants,
        )..where((x) => x.id.equals(variantId))).getSingle();
        expect(v.stockQuantity, equals(100));
        expect(v.costCents, equals(Decimal.fromInt(4000)));
        expect(v.previousCostCents, equals(Decimal.fromInt(3000)));
      },
    );

    test('write-down: Dr 5900 / Cr 1200', () async {
      // $30 → $20 on 100 units ⇒ delta = -$10 × 100 = -$1000 → |1000|
      final result = await service.adjust(
        productId: productId,
        variantId: variantId,
        type: InventoryAdjustmentType.revaluation,
        quantityDelta: 0,
        newUnitCostCents: 2000,
        reason: 'NRV write-down (IAS 2)',
        currencyId: currencyId,
      );

      expect(result.totalValueCents, equals(-100000));

      final lines = await linesForAdjustment(result.adjustmentId);
      final inventoryId = await accountIdByCode('1200');
      final revalId = await accountIdByCode('5900');
      final debit = lines.firstWhere((l) => l.debitCents > 0);
      final credit = lines.firstWhere((l) => l.creditCents > 0);
      expect(debit.accountId, equals(revalId));
      expect(credit.accountId, equals(inventoryId));
      expect(debit.debitCents, equals(100000));
    });

    test('rejects non-zero quantityDelta', () async {
      expect(
        () => service.adjust(
          productId: productId,
          variantId: variantId,
          type: InventoryAdjustmentType.revaluation,
          quantityDelta: 3,
          newUnitCostCents: 4000,
          reason: 'x',
          currencyId: currencyId,
        ),
        throwsA(isA<InventoryAdjustmentException>()),
      );
    });

    test('rejects same-cost revaluation (zero delta)', () async {
      expect(
        () => service.adjust(
          productId: productId,
          variantId: variantId,
          type: InventoryAdjustmentType.revaluation,
          quantityDelta: 0,
          newUnitCostCents: 3000, // same as current
          reason: 'noop',
          currencyId: currencyId,
        ),
        throwsA(isA<InventoryAdjustmentException>()),
      );
    });
  });

  // ── Regression: silent stock desync when passing variantId=null on a
  // product whose only variant has a non-null color/size (e.g. "Small") ──
  //
  // Repro of the field bug reported from the product-list screen:
  //   1. Product has ONE variant with size_id set → no "strict-default"
  //      (color_id IS NULL AND size_id IS NULL) variant exists.
  //   2. UI mistakenly passed variantId=null to the adjustment service.
  //   3. StockService.adjustStock updated zero variant rows, then
  //      syncProductStockFromVariants rewrote products.stock_quantity back
  //      to SUM(variants.stock_quantity) — erasing the adjustment while
  //      the journal entry stayed posted (Inventory account credited with
  //      no matching stock movement → assets drift toward negative).
  //
  // After the fix, the service/StockService refuses to proceed in this
  // configuration; the whole transaction rolls back, and NO journal entry
  // is posted, NO stock row is touched. The only safe path is to pass a
  // concrete variantId.
  group('Stock/GL desync guard (dimensional default variant)', () {
    late int dimProductId;
    late int sizeId;
    late int smallVariantId;

    setUp(() async {
      // Product with a single Small-size variant (no strict-default variant
      // i.e. color_id IS NULL AND size_id IS NULL does NOT exist).
      dimProductId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              sku: const Value<String?>('INV-DIM-001'),
              name: 'Skirt (Small only)',
              costCents: Decimal.fromInt(3000),
              priceCents: Decimal.fromInt(5000),
              currencyId: Value(currencyId),
              stockQuantity: const Value(100),
              hasVariants: const Value(true),
            ),
          );
      sizeId = await db
          .into(db.sizes)
          .insert(SizesCompanion.insert(name: 'Small'));
      smallVariantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: dimProductId,
              sizeId: Value(sizeId),
              stockQuantity: const Value(100),
              costCents: Decimal.fromInt(3000),
              priceCents: Decimal.fromInt(5000),
            ),
          );
    });

    test('variantId=null + no strict-default variant → rollback, NO stock '
        'change, NO journal entry (prevents -150 silent loss)', () async {
      expect(
        () => service.adjust(
          productId: dimProductId,
          // BUG input: should have been smallVariantId
          type: InventoryAdjustmentType.shrinkage,
          quantityDelta: -5,
          reason: 'Damaged during shelving',
          currencyId: currencyId,
          userId: 0,
        ),
        throwsA(isA<StateError>()),
      );

      // Stock on the variant is untouched: still 100 (was NOT decremented).
      final v = await (db.select(
        db.productVariants,
      )..where((x) => x.id.equals(smallVariantId))).getSingle();
      expect(
        v.stockQuantity,
        equals(100),
        reason: 'variant row must be untouched after rollback',
      );

      // Stock on the product is untouched: still 100.
      final p = await (db.select(
        db.products,
      )..where((x) => x.id.equals(dimProductId))).getSingle();
      expect(
        p.stockQuantity,
        equals(100),
        reason: 'products.stock_quantity must be untouched after rollback',
      );

      // No inventory_adjustments row was committed.
      final adjCount = await db
          .customSelect(
            'SELECT COUNT(*) AS cnt FROM inventory_adjustments '
            'WHERE product_id = ?',
            variables: [Variable.withInt(dimProductId)],
          )
          .getSingle();
      expect(adjCount.read<int>('cnt'), equals(0));

      // No posted journal entry for this adjustment type was created.
      final jeCount = await db
          .customSelect(
            'SELECT COUNT(*) AS cnt FROM journal_entries '
            'WHERE source_table = ? AND status = ?',
            variables: [
              Variable.withString('inventory_adjustments'),
              Variable.withString('posted'),
            ],
          )
          .getSingle();
      expect(
        jeCount.read<int>('cnt'),
        equals(0),
        reason: 'no orphan posted JE (would drift assets negative)',
      );
    });

    test(
      'variantId=smallVariantId (correct call) → balanced, stock 100→95',
      () async {
        final result = await service.adjust(
          productId: dimProductId,
          variantId: smallVariantId,
          type: InventoryAdjustmentType.shrinkage,
          quantityDelta: -5,
          reason: 'Damaged during shelving',
          currencyId: currencyId,
          userId: 0,
        );

        final v = await (db.select(
          db.productVariants,
        )..where((x) => x.id.equals(smallVariantId))).getSingle();
        expect(v.stockQuantity, equals(95));

        final p = await (db.select(
          db.products,
        )..where((x) => x.id.equals(dimProductId))).getSingle();
        // syncProductStockFromVariants must mirror SUM(variants).
        expect(p.stockQuantity, equals(95));

        final lines = await linesForAdjustment(result.adjustmentId);
        final totalD = lines.fold<int>(0, (s, l) => s + l.debitCents);
        final totalC = lines.fold<int>(0, (s, l) => s + l.creditCents);
        expect(totalD, equals(totalC));
        expect(totalD, equals(15000));
      },
    );
  });
}
