import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/batch_audit_dao.dart';
import 'package:tapix/core/services/batch_service.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// Phase H1 — BatchAuditDao read-only contract tests.
///
/// We exercise the DAO against a real in-memory schema (same approach as the
/// FEFO property tests) so the SQL JOINs are validated end-to-end:
///
///   1. `watchBatchesForProduct` honours FEFO ordering and resolves
///      supplier_name + variant label.
///   2. `includeDepleted = false` filters out batches that have been sold
///      down to zero.
///   3. `getConsumptionsForBatch` resolves source labels (sales / sale-return /
///      adjustment) via the LEFT-JOIN chain.
///   4. `getBatchFlowForSale` reconstructs per-line FEFO breakdown and nets
///      partial returns ('in' rows subtract from 'out' rows).
///   5. `getConsumptionsForSaleItem` is the sale-level debug helper.
///   6. WAC / standard-tracked sale lines surface with empty `batches` and the
///      caller falls back to `snapshotCostCents`.
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late BatchAuditDao audit;
  late int currencyId;
  late int supplierId;
  late int productId;
  late int variantId;

  /// Insert the bare-minimum rows needed for the DAO under test.
  Future<void> seedFixture() async {
    // Schema integrity bootstrapping pre-seeds a USD row, so reuse it.
    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingleOrNull();
    currencyId = usd?.id ??
        await db.into(db.currencies).insert(
              CurrenciesCompanion.insert(
                code: 'USD',
                name: 'US Dollar',
                symbol: r'$',
                exchangeRate: Decimal.fromInt(1),
              ),
            );
    supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'Acme Imports',
            currencyId: currencyId,
          ),
        );
    productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            sku: const Value('AUDIT-1'),
            name: 'Audit fixture product',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            stockQuantity: const Value(0),
            inventoryTrackingType: const Value('batch_expiry'),
          ),
        );
    variantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(0),
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
          ),
        );
  }

  /// Insert a batch through the production write path so we exercise the same
  /// row shape `BatchService.consumeFifo` will read. We use `createOpeningBatch`
  /// (source='opening') instead of `createBatchFromPurchase` because the
  /// latter requires a real `purchase_items.id` FK which our minimal fixture
  /// doesn't seed. Both code paths terminate in the same `_insertBatch` so
  /// the resulting row layout is identical for read-side audit purposes.
  Future<int> insertBatch({
    required int qty,
    required int unitCostCents,
    required DateTime received,
    DateTime? expiry,
    int? supplier,
  }) async {
    final id = await BatchService.createOpeningBatch(
      db.purchaseDao,
      productId: productId,
      variantId: variantId,
      quantity: qty,
      unitCostCents: unitCostCents,
      source: 'opening',
      receivedDate: received,
      expiryDate: expiry,
      supplierId: supplier ?? supplierId,
    );
    // Mirror variant stock so the production-path invariant holds.
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = stock_quantity + ? WHERE id = ?',
      [qty, variantId],
    );
    return id;
  }

  /// Create a Sale + SaleItem skeleton and consume FEFO against the seeded
  /// batches. Returns the saleItemId so tests can pivot on it.
  Future<({int saleId, int saleItemId})> createSaleConsuming(int qty) async {
    final saleId = await db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-${DateTime.now().microsecondsSinceEpoch}',
            currencyId: currencyId,
            subtotalCents: Decimal.fromInt(qty * 200),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(qty * 200),
            paymentMethod: 'cash',
            saleDate: Value(DateTime.now()),
          ),
        );
    final saleItemId = await db.into(db.saleItems).insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            variantId: Value(variantId),
            quantity: qty,
            unitPriceCents: Decimal.fromInt(200),
            subtotalCents: Decimal.fromInt(qty * 200),
            totalCents: Decimal.fromInt(qty * 200),
            costCents: Value(Decimal.fromInt(qty * 100)),
          ),
        );
    final consumed = await BatchService.consumeFifo(
      db.purchaseDao,
      productId: productId,
      variantId: variantId,
      quantity: qty,
      consumptionType: 'sale',
      saleItemId: saleItemId,
    );
    // Mirror stock decrement so the variant stock stays honest.
    final consumedTotal = consumed.fold<int>(0, (s, c) => s + c.quantity);
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = stock_quantity - ? WHERE id = ?',
      [consumedTotal, variantId],
    );
    return (saleId: saleId, saleItemId: saleItemId);
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    await seedFixture();
    audit = BatchAuditDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('watchBatchesForProduct', () {
    test('returns batches in FEFO order with supplier name resolved', () async {
      // Use UTC throughout so DateTime equality survives the SQLite text
      // round-trip (Drift stores as ISO-8601 in UTC).
      final laterExpiry = DateTime.utc(2027, 1, 1);
      final earlierExpiry = DateTime.utc(2026, 6, 1);
      // Insert a "later expiry" batch *before* the "earlier expiry" batch in
      // received_date and id. FEFO must still surface the earlier-expiry one
      // first.
      await insertBatch(
        qty: 50,
        unitCostCents: 100,
        received: DateTime.utc(2026, 1, 1),
        expiry: laterExpiry,
      );
      await insertBatch(
        qty: 30,
        unitCostCents: 120,
        received: DateTime.utc(2026, 2, 1),
        expiry: earlierExpiry,
      );

      final batches = await audit.getBatchesForProduct(productId: productId);

      expect(batches, hasLength(2));
      expect(batches.first.expiryDate, earlierExpiry);
      expect(batches.first.remainingQuantity, 30);
      expect(batches.first.supplierName, 'Acme Imports');
      expect(batches.first.consumedQuantity, 0);
      expect(batches.last.expiryDate, laterExpiry);
    });

    test('hides depleted batches by default and exposes them on opt-in',
        () async {
      await insertBatch(
        qty: 10,
        unitCostCents: 100,
        received: DateTime.utc(2026, 1, 1),
        expiry: DateTime.utc(2026, 6, 1),
      );
      await insertBatch(
        qty: 20,
        unitCostCents: 110,
        received: DateTime.utc(2026, 2, 1),
        expiry: DateTime.utc(2026, 7, 1),
      );
      // Sell down the first batch entirely.
      await createSaleConsuming(10);

      final visible = await audit.getBatchesForProduct(productId: productId);
      expect(visible, hasLength(1));
      expect(visible.single.remainingQuantity, 20);

      final all = await audit.getBatchesForProduct(
        productId: productId,
        includeDepleted: true,
      );
      expect(all, hasLength(2));
      // The depleted batch is still surfaced, with consumedQuantity reflecting
      // the sale.
      final depleted = all.firstWhere((b) => b.remainingQuantity == 0);
      expect(depleted.receivedQuantity, 10);
      expect(depleted.consumedQuantity, 10);
      expect(depleted.isDepleted, isTrue);
    });
  });

  group('getConsumptionsForBatch', () {
    test('resolves the sale invoice number on an OUT row', () async {
      final batchId = await insertBatch(
        qty: 10,
        unitCostCents: 100,
        received: DateTime.utc(2026, 1, 1),
        expiry: DateTime.utc(2026, 6, 1),
      );
      await createSaleConsuming(4);

      final rows = await audit.getConsumptionsForBatch(batchId);

      expect(rows, hasLength(1));
      expect(rows.single.direction, 'out');
      expect(rows.single.quantity, 4);
      expect(rows.single.refKind, 'sale');
      expect(rows.single.refLabel, startsWith('INV-'));
      expect(rows.single.unitCostCents, 100);
    });
  });

  group('getBatchFlowForSale', () {
    test('reconstructs per-line FEFO consumption with frozen unit costs',
        () async {
      // Two batches with different unit costs. The earlier-expiry one is
      // cheaper, so FEFO should consume that first.
      await insertBatch(
        qty: 6,
        unitCostCents: 100,
        received: DateTime.utc(2026, 1, 1),
        expiry: DateTime.utc(2026, 6, 1),
      );
      await insertBatch(
        qty: 4,
        unitCostCents: 150,
        received: DateTime.utc(2026, 2, 1),
        expiry: DateTime.utc(2026, 9, 1),
      );

      final ids = await createSaleConsuming(8);
      final flow = await audit.getBatchFlowForSale(ids.saleId);

      expect(flow, hasLength(1));
      final line = flow.single;
      expect(line.saleItemId, ids.saleItemId);
      expect(line.totalQuantity, 8);
      expect(line.batches, hasLength(2));
      // Cheaper / earlier expiry batch consumed in full first.
      expect(line.batches[0].quantity, 6);
      expect(line.batches[0].unitCostCents, 100);
      // Then 2 of the second batch.
      expect(line.batches[1].quantity, 2);
      expect(line.batches[1].unitCostCents, 150);
      // Reconstructed COGS = 6*100 + 2*150 = 900.
      expect(line.reconstructedCogsCents, 900);
      expect(line.isBatchTracked, isTrue);
    });

    test('nets partial returns: a 4-unit return shrinks the OUT slice', () async {
      final batchId = await insertBatch(
        qty: 10,
        unitCostCents: 100,
        received: DateTime.utc(2026, 1, 1),
        expiry: DateTime.utc(2026, 6, 1),
      );
      final ids = await createSaleConsuming(8);

      // Simulate a 4-unit return. Production (`SaleDao.postSaleReturn`)
      // calls `restoreConsumptions` filtered by `saleItemId` only — the
      // resolver matches against the original `'out'` rows whose FK is
      // `sale_item_id`. Passing additional FKs (e.g. `saleReturnItemId`)
      // would AND them into the filter and match nothing, so we mirror
      // the production call here.
      final restored = await BatchService.restoreConsumptions(
        db.purchaseDao,
        reverseConsumptionType: 'sale_return_reverse',
        saleItemId: ids.saleItemId,
        upToQuantity: 4,
      );
      expect(restored, 4);

      final flow = await audit.getBatchFlowForSale(ids.saleId);
      final line = flow.single;
      // Net 'out' = 8 − 4 = 4.
      expect(line.batches, hasLength(1));
      expect(line.batches.single.batchId, batchId);
      expect(line.batches.single.quantity, 4);
      expect(line.batches.single.unitCostCents, 100);
      expect(line.reconstructedCogsCents, 400);
    });
  });

  group('getConsumptionsForSaleItem', () {
    test('returns one row per consumption with frozen unit cost', () async {
      await insertBatch(
        qty: 5,
        unitCostCents: 100,
        received: DateTime.utc(2026, 1, 1),
        expiry: DateTime.utc(2026, 6, 1),
      );
      await insertBatch(
        qty: 5,
        unitCostCents: 150,
        received: DateTime.utc(2026, 2, 1),
        expiry: DateTime.utc(2026, 9, 1),
      );
      final ids = await createSaleConsuming(7);

      final rows = await audit.getConsumptionsForSaleItem(ids.saleItemId);
      expect(rows, hasLength(2));
      expect(rows[0].direction, 'out');
      expect(rows[0].quantity, 5);
      expect(rows[0].unitCostCents, 100);
      expect(rows[0].refKind, 'sale');
      expect(rows[1].quantity, 2);
      expect(rows[1].unitCostCents, 150);
    });
  });

  group('watchAllBatches (Phase H3)', () {
    test('returns all batches FEFO-ordered with productName/productSku enriched',
        () async {
      // Two batches on the seeded product, plus a second product with one batch.
      await insertBatch(
        qty: 5,
        unitCostCents: 100,
        received: DateTime.utc(2026, 1, 1),
        expiry: DateTime.utc(2026, 9, 1),
      );
      await insertBatch(
        qty: 7,
        unitCostCents: 110,
        received: DateTime.utc(2026, 2, 1),
        expiry: DateTime.utc(2026, 6, 1), // earlier expiry → first
      );

      final rows = await audit.watchAllBatches().first;

      expect(rows, hasLength(2));
      // FEFO ordering: earlier expiry first.
      expect(rows.first.expiryDate, DateTime.utc(2026, 6, 1));
      // Cross-product surface populates productName / productSku.
      for (final r in rows) {
        expect(r.productName, 'Audit fixture product');
        expect(r.productSku, 'AUDIT-1');
        expect(r.supplierName, 'Acme Imports');
      }
    });

    test('source filter narrows by exact source string', () async {
      // Insert one 'opening' batch (default fixture path).
      await insertBatch(
        qty: 5,
        unitCostCents: 100,
        received: DateTime.utc(2026, 1, 1),
      );
      // Insert one 'sale_return' batch directly via the same service entry
      // so the test exercises the read filter, not the write API.
      await BatchService.createOpeningBatch(
        db.purchaseDao,
        productId: productId,
        variantId: variantId,
        quantity: 3,
        unitCostCents: 95,
        source: 'sale_return',
        receivedDate: DateTime.utc(2026, 1, 5),
        supplierId: supplierId,
      );
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity = stock_quantity + ? WHERE id = ?',
        [3, variantId],
      );

      final all = await audit.watchAllBatches().first;
      expect(all, hasLength(2));

      final purchaseOnly =
          await audit.watchAllBatches(source: 'opening').first;
      expect(purchaseOnly, hasLength(1));
      expect(purchaseOnly.single.source, 'opening');

      final returnOnly =
          await audit.watchAllBatches(source: 'sale_return').first;
      expect(returnOnly, hasLength(1));
      expect(returnOnly.single.source, 'sale_return');
    });

    test('expiryFilter buckets match ExpiryAlertService cadence', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Bucket fixtures relative to "today" — anchor each batch at a
      // canonical day in its bucket so the test is deterministic.
      // 1) Already expired (yesterday).
      await insertBatch(
        qty: 1,
        unitCostCents: 100,
        received: today.subtract(const Duration(days: 30)),
        expiry: today.subtract(const Duration(days: 1)),
      );
      // 2) Within 30 days (15 days from now).
      await insertBatch(
        qty: 1,
        unitCostCents: 100,
        received: today,
        expiry: today.add(const Duration(days: 15)),
      );
      // 3) Within 60 days (45 days from now).
      await insertBatch(
        qty: 1,
        unitCostCents: 100,
        received: today,
        expiry: today.add(const Duration(days: 45)),
      );
      // 4) No-expiry batch.
      await insertBatch(
        qty: 1,
        unitCostCents: 100,
        received: today,
      );

      final expired = await audit
          .watchAllBatches(expiryFilter: BatchExpiryFilter.expired)
          .first;
      expect(expired, hasLength(1));
      expect(expired.single.expiryDate!.isBefore(today.add(const Duration(days: 1))), isTrue);

      final in30 = await audit
          .watchAllBatches(expiryFilter: BatchExpiryFilter.in30Days)
          .first;
      expect(in30, hasLength(1));

      final in60 = await audit
          .watchAllBatches(expiryFilter: BatchExpiryFilter.in60Days)
          .first;
      expect(in60, hasLength(1));

      final none = await audit
          .watchAllBatches(expiryFilter: BatchExpiryFilter.none)
          .first;
      expect(none, hasLength(1));
      expect(none.single.expiryDate, isNull);
    });

    test('query filter LIKE-matches name, sku and batch number', () async {
      final id1 = await insertBatch(
        qty: 5,
        unitCostCents: 100,
        received: DateTime.utc(2026, 1, 1),
      );

      // Match by SKU.
      final bySku = await audit.watchAllBatches(query: 'AUDIT').first;
      expect(bySku, hasLength(1));
      expect(bySku.single.batchId, id1);

      // Match by product name fragment.
      final byName = await audit.watchAllBatches(query: 'fixture').first;
      expect(byName, hasLength(1));

      // Non-matching string.
      final none = await audit.watchAllBatches(query: 'nonexistent-xyz').first;
      expect(none, isEmpty);
    });

    test('hides depleted by default; surfaces them on opt-in', () async {
      await insertBatch(
        qty: 4,
        unitCostCents: 100,
        received: DateTime.utc(2026, 1, 1),
      );
      await createSaleConsuming(4); // depletes the only batch

      final activeOnly = await audit.watchAllBatches().first;
      expect(activeOnly, isEmpty);

      final all = await audit.watchAllBatches(includeDepleted: true).first;
      expect(all, hasLength(1));
      expect(all.single.remainingQuantity, 0);
      expect(all.single.isDepleted, isTrue);
    });

    test('supplier filter narrows to exact supplier id', () async {
      // Default supplier batch.
      await insertBatch(
        qty: 3,
        unitCostCents: 100,
        received: DateTime.utc(2026, 1, 1),
      );
      // A second supplier with its own batch.
      final supplier2 = await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(
              name: 'Other Co',
              currencyId: currencyId,
            ),
          );
      await insertBatch(
        qty: 2,
        unitCostCents: 110,
        received: DateTime.utc(2026, 1, 5),
        supplier: supplier2,
      );

      final all = await audit.watchAllBatches().first;
      expect(all, hasLength(2));

      final justOther =
          await audit.watchAllBatches(supplierId: supplier2).first;
      expect(justOther, hasLength(1));
      expect(justOther.single.supplierName, 'Other Co');
    });
  });

  group('standard-tracked sales', () {
    test('emit no batch consumptions; flow falls back to snapshotCostCents',
        () async {
      // Flip the product to standard tracking: no batches will be created.
      await db.customStatement(
        "UPDATE products SET inventory_tracking_type = 'standard' WHERE id = ?",
        [productId],
      );
      // Manually create a sale + sale_item with a snapshot cost; do NOT call
      // BatchService.consumeFifo.
      final saleId = await db.into(db.sales).insert(
            SalesCompanion.insert(
              invoiceNumber: 'INV-STD-1',
              currencyId: currencyId,
              subtotalCents: Decimal.fromInt(600),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(600),
              paymentMethod: 'cash',
              saleDate: Value(DateTime.now()),
            ),
          );
      await db.into(db.saleItems).insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: productId,
              variantId: Value(variantId),
              quantity: 3,
              unitPriceCents: Decimal.fromInt(200),
              subtotalCents: Decimal.fromInt(600),
              totalCents: Decimal.fromInt(600),
              costCents: Value(Decimal.fromInt(330)),
            ),
          );

      final flow = await audit.getBatchFlowForSale(saleId);
      expect(flow, hasLength(1));
      expect(flow.single.batches, isEmpty);
      expect(flow.single.isBatchTracked, isFalse);
      expect(flow.single.snapshotCostCents, 330);
      expect(flow.single.reconstructedCogsCents, 0);
    });
  });
}
