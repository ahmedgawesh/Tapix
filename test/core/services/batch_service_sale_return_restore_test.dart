import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/batch_service.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// Regression test pinning the **May 2026 sale-return restoration bug**.
///
/// Field report: posting a linked sale return on a batch-tracked product
/// aborted with
///   `BatchService.assertInvariant: product=P variant=V
///    Σ(batch.remaining)=N but product_variants.stock_quantity=N+returnQty.
///    Refuse to leave the transaction in a desynchronised state.`
///
/// Root cause: `BatchService.restoreConsumptions` ANDed `sale_return_item_id`
/// into the WHERE clause whenever the caller passed it. The source `out`
/// rows from the original sale always carry `sale_return_item_id IS NULL`
/// (it is never tagged by `consumeFifo`), so the filter matched **zero**
/// rows. Meanwhile `StockService.adjustStock` had already incremented the
/// variant's `stock_quantity`, leaving Σ(batch.remaining) one short.
///
/// Fix: classify `saleReturnItemId` as a *reversal-context* tag, used only
/// to stamp the new `in` row, never to filter the source `out` rows.
///
/// The tests below also pin the contract that:
///   * single-source-FK callers (void sale, void purchase return, void
///     purchase-adj return) keep their previous behaviour;
///   * passing `saleReturnItemId` alone is rejected with `ArgumentError`
///     so a future regression of "use it as the only filter" fails loudly.
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late int productId;
  late int variantId;
  late int saleId;
  late int saleItemId;
  late int returnId;
  late int returnItemId;

  Future<void> seedProductVariant() async {
    productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            sku: const Value('SR-RESTORE-REGRESSION'),
            name: 'Sale-return restoration regression product',
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            stockQuantity: const Value(0),
            inventoryTrackingType: const Value('batch'),
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

  Future<int> insertOpeningBatch({
    required int qty,
    required int unitCostCents,
  }) async {
    final id = await BatchService.createOpeningBatch(
      db.purchaseDao,
      productId: productId,
      variantId: variantId,
      quantity: qty,
      unitCostCents: unitCostCents,
      source: 'opening',
      receivedDate: DateTime.utc(2026, 1, 1),
    );
    // Mirror the variant stock so `assertInvariant` holds — this mirrors the
    // production path where StockService handles the row-level mutation.
    await db.customStatement(
      'UPDATE product_variants SET stock_quantity = stock_quantity + ? '
      'WHERE id = ?',
      [qty, variantId],
    );
    return id;
  }

  late int currencyId;

  Future<void> seedSaleAndReturnHeaders({required int qty}) async {
    currencyId = (await db.select(db.currencies).get()).first.id;
    saleId = await db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-SR-RESTORE',
            subtotalCents: Decimal.fromInt(200 * qty),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(200 * qty),
            currencyId: currencyId,
            paymentMethod: 'cash',
          ),
        );
    saleItemId = await db.into(db.saleItems).insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            variantId: Value(variantId),
            quantity: qty,
            unitPriceCents: Decimal.fromInt(200),
            subtotalCents: Decimal.fromInt(200 * qty),
            totalCents: Decimal.fromInt(200 * qty),
          ),
        );
  }

  Future<void> seedReturnHeaders({required int returnQty}) async {
    returnId = await db.into(db.saleReturns).insert(
          SaleReturnsCompanion.insert(
            returnNumber: 'SR-RESTORE-0001',
            saleId: saleId,
            currencyId: currencyId,
            refundMethod: const Value('cash'),
            subtotalCents: Value(Decimal.fromInt(200 * returnQty)),
            taxCents: Value(Decimal.zero),
            totalCents: Decimal.fromInt(200 * returnQty),
          ),
        );
    returnItemId = await db.into(db.saleReturnItems).insert(
          SaleReturnItemsCompanion.insert(
            returnId: returnId,
            saleItemId: saleItemId,
            quantity: returnQty,
            subtotalCents: Value(Decimal.fromInt(200 * returnQty)),
            refundCents: Decimal.fromInt(200 * returnQty),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    await seedProductVariant();
  });

  tearDown(() async => db.close());

  // ──────────────────────────────────────────────────────────────────────────
  // 1. The exact production scenario that triggered the bug.
  // ──────────────────────────────────────────────────────────────────────────
  group('Sale-return restoration — dual-FK regression', () {
    test('restoreConsumptions with saleItemId + saleReturnItemId restores the '
        'matching `out` row (no longer over-filtered into 0 matches)', () async {
      // Arrange: one batch of 10 units, one sale of 3 units consumed FIFO.
      final batchId =
          await insertOpeningBatch(qty: 10, unitCostCents: 100);
      await seedSaleAndReturnHeaders(qty: 3);

      // Mirror `SaleDao.postSale`: FIFO consume + adjustStock decrement.
      final consumed = await BatchService.consumeFifo(
        db.purchaseDao,
        productId: productId,
        variantId: variantId,
        quantity: 3,
        consumptionType: 'sale',
        saleItemId: saleItemId,
      );
      expect(consumed.fold<int>(0, (s, c) => s + c.quantity), equals(3));
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity = stock_quantity - 3 '
        'WHERE id = ?',
        [variantId],
      );
      await BatchService.assertInvariant(db.purchaseDao,
          productId: productId, variantId: variantId);

      // The source `out` row carries sale_item_id but NOT sale_return_item_id.
      final outBefore = await db.customSelect(
        'SELECT sale_item_id, sale_return_item_id, direction '
        '  FROM batch_consumptions '
        ' WHERE batch_id = ? AND direction = ?',
        variables: [Variable.withInt(batchId), Variable.withString('out')],
      ).getSingle();
      expect(outBefore.read<int>('sale_item_id'), equals(saleItemId));
      expect(outBefore.read<int?>('sale_return_item_id'), isNull,
          reason: 'consumeFifo must NOT stamp sale_return_item_id on `out` rows');

      // Act: post a partial sale-return of 1 unit. Mirror `SaleDao.postSaleReturn`:
      // adjustStock then restoreConsumptions with BOTH FKs.
      await seedReturnHeaders(returnQty: 1);
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity = stock_quantity + 1 '
        'WHERE id = ?',
        [variantId],
      );
      final restored = await BatchService.restoreConsumptions(
        db.purchaseDao,
        reverseConsumptionType: 'sale_return_reverse',
        saleItemId: saleItemId,
        saleReturnItemId: returnItemId,
        upToQuantity: 1,
      );

      // Assert: 1 unit was restored to the batch ledger, the invariant holds,
      // and the new `in` row is tagged with BOTH FKs.
      expect(restored, equals(1),
          reason: 'restoreConsumptions must find the source `out` row even '
              'when saleReturnItemId is also passed (regression: was 0)');

      final batchAfter = await db.customSelect(
        'SELECT remaining_quantity FROM product_batches WHERE id = ?',
        variables: [Variable.withInt(batchId)],
      ).getSingle();
      expect(batchAfter.read<int>('remaining_quantity'), equals(8),
          reason: '10 received − 3 sold + 1 restored = 8');

      // The cross-table invariant is what production aborted on. It must hold.
      await BatchService.assertInvariant(db.purchaseDao,
          productId: productId, variantId: variantId);

      // The reversal `in` row carries BOTH FKs so a later void of the return
      // can find it via `_reverseRestoredFifo`.
      final inRow = await db.customSelect(
        'SELECT sale_item_id, sale_return_item_id, direction, quantity, '
        '       consumption_type '
        '  FROM batch_consumptions '
        ' WHERE batch_id = ? AND direction = ?',
        variables: [Variable.withInt(batchId), Variable.withString('in')],
      ).getSingle();
      expect(inRow.read<int>('sale_item_id'), equals(saleItemId));
      expect(inRow.read<int>('sale_return_item_id'), equals(returnItemId));
      expect(inRow.read<int>('quantity'), equals(1));
      expect(inRow.read<String>('consumption_type'),
          equals('sale_return_reverse'));
    });

    test('partial then full restoration matches the original `out` quantity '
        '(no over-restore)', () async {
      await insertOpeningBatch(qty: 5, unitCostCents: 100);
      await seedSaleAndReturnHeaders(qty: 5);

      await BatchService.consumeFifo(
        db.purchaseDao,
        productId: productId,
        variantId: variantId,
        quantity: 5,
        consumptionType: 'sale',
        saleItemId: saleItemId,
      );
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity = stock_quantity - 5 '
        'WHERE id = ?',
        [variantId],
      );

      // First partial return: 2 units.
      await seedReturnHeaders(returnQty: 2);
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity = stock_quantity + 2 '
        'WHERE id = ?',
        [variantId],
      );
      final restoredA = await BatchService.restoreConsumptions(
        db.purchaseDao,
        reverseConsumptionType: 'sale_return_reverse',
        saleItemId: saleItemId,
        saleReturnItemId: returnItemId,
        upToQuantity: 2,
      );
      expect(restoredA, equals(2));
      await BatchService.assertInvariant(db.purchaseDao,
          productId: productId, variantId: variantId);

      // Second partial return: 3 units (different return row).
      final secondReturnId = await db.into(db.saleReturns).insert(
            SaleReturnsCompanion.insert(
              returnNumber: 'SR-RESTORE-0002',
              saleId: saleId,
              currencyId: currencyId,
              refundMethod: const Value('cash'),
              subtotalCents: Value(Decimal.fromInt(600)),
              taxCents: Value(Decimal.zero),
              totalCents: Decimal.fromInt(600),
            ),
          );
      final secondReturnItemId = await db.into(db.saleReturnItems).insert(
            SaleReturnItemsCompanion.insert(
              returnId: secondReturnId,
              saleItemId: saleItemId,
              quantity: 3,
              subtotalCents: Value(Decimal.fromInt(600)),
              refundCents: Decimal.fromInt(600),
            ),
          );
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity = stock_quantity + 3 '
        'WHERE id = ?',
        [variantId],
      );
      final restoredB = await BatchService.restoreConsumptions(
        db.purchaseDao,
        reverseConsumptionType: 'sale_return_reverse',
        saleItemId: saleItemId,
        saleReturnItemId: secondReturnItemId,
        upToQuantity: 3,
      );
      expect(restoredB, equals(3));
      await BatchService.assertInvariant(db.purchaseDao,
          productId: productId, variantId: variantId);

      // Final state: full sale reversed, batch back to 5.
      final batchRow = await db.customSelect(
        'SELECT SUM(remaining_quantity) AS s FROM product_batches '
        ' WHERE product_id = ? AND variant_id = ? AND is_active = 1',
        variables: [Variable.withInt(productId), Variable.withInt(variantId)],
      ).getSingle();
      expect(batchRow.read<int>('s'), equals(5));
    });

    test('WAC-era sale (no `out` rows) restores 0 — silent no-op as documented',
        () async {
      // No prior consumption — simulates a sale posted before the product
      // was migrated to batch tracking.
      await insertOpeningBatch(qty: 4, unitCostCents: 100);
      await seedSaleAndReturnHeaders(qty: 1);
      await seedReturnHeaders(returnQty: 1);

      final restored = await BatchService.restoreConsumptions(
        db.purchaseDao,
        reverseConsumptionType: 'sale_return_reverse',
        saleItemId: saleItemId,
        saleReturnItemId: returnItemId,
        upToQuantity: 1,
      );
      expect(restored, equals(0),
          reason: 'No source `out` rows ⇒ silent no-op (legacy-WAC contract)');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 2. Single-FK callers are unaffected.
  // ──────────────────────────────────────────────────────────────────────────
  group('Single-source-FK callers unchanged', () {
    test('void-sale path (saleItemId only) still restores symmetrically',
        () async {
      final batchId = await insertOpeningBatch(qty: 6, unitCostCents: 100);
      await seedSaleAndReturnHeaders(qty: 4);

      await BatchService.consumeFifo(
        db.purchaseDao,
        productId: productId,
        variantId: variantId,
        quantity: 4,
        consumptionType: 'sale',
        saleItemId: saleItemId,
      );
      final restored = await BatchService.restoreConsumptions(
        db.purchaseDao,
        reverseConsumptionType: 'void_sale_reverse',
        saleItemId: saleItemId,
      );
      expect(restored, equals(4));
      final after = await db.customSelect(
        'SELECT remaining_quantity FROM product_batches WHERE id = ?',
        variables: [Variable.withInt(batchId)],
      ).getSingle();
      expect(after.read<int>('remaining_quantity'), equals(6));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 3. `saleReturnItemId` alone is rejected — it is not a source FK.
  // ──────────────────────────────────────────────────────────────────────────
  group('Reversal-context FK guard', () {
    test('passing only saleReturnItemId throws ArgumentError', () async {
      await insertOpeningBatch(qty: 1, unitCostCents: 100);
      await seedSaleAndReturnHeaders(qty: 1);
      await seedReturnHeaders(returnQty: 1);

      await expectLater(
        BatchService.restoreConsumptions(
          db.purchaseDao,
          reverseConsumptionType: 'sale_return_reverse',
          saleReturnItemId: returnItemId,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
