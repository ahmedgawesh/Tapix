// Phase 15.0 — pins the batch-ledger-authoritative inventory-valuation
// formula used by the Reconciliation & Health screen.
//
// Field-reported false-positive (May 2026):
//
//   A FIFO / batch_expiry product was bought twice for the same variant:
//
//     batch 1 → qty 10, unit_cost 9,900¢
//     batch 2 → qty  3, unit_cost 9,801¢  (trade discount on a re-stock)
//
//   GL(1200 Inventory) correctly carries 10×9,900 + 3×9,801 = 128,403¢.
//   But `product_variants.cost_cents` is a DISPLAY value for FIFO/last —
//   it always holds the most-recent paid unit cost (9,801¢). The pre-
//   Phase-15 reconciliation formula `Σ(variant.stock × variant.cost)`
//   therefore reported 13 × 9,801 = 127,413¢ → a 990¢ "drift" that did
//   not exist in the books.
//
// These tests prove the new formula is batch-ledger-authoritative and
// that the WAC happy-path is unchanged.
//
// SoT under test: `JournalLocalDatasourceImpl.getTotalInventoryValueCents`
// (`lib/features/accounting/data/datasources/journal_local_datasource.dart`).
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';

void main() {
  late AppDatabase db;
  late JournalLocalDatasourceImpl ds;
  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    ds = JournalLocalDatasourceImpl(AccountingDao(db));
  });

  tearDown(() async => db.close());

  // ── helpers ──────────────────────────────────────────────────────────

  Future<int> insertProduct({
    required String name,
    required String costingMethod,
    required String inventoryTrackingType,
    required bool hasVariants,
    required int costCents,
    required int stockQty,
  }) {
    return db.into(db.products).insert(
          ProductsCompanion.insert(
            name: name,
            costCents: Decimal.fromInt(costCents),
            priceCents: Decimal.zero,
            costingMethod: Value(costingMethod),
            inventoryTrackingType: Value(inventoryTrackingType),
            hasVariants: Value(hasVariants),
            stockQuantity: Value(stockQty),
          ),
        );
  }

  Future<int> insertVariant({
    required int productId,
    required String sku,
    required int costCents,
    required int stockQty,
  }) {
    return db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            sku: Value(sku),
            costCents: Decimal.fromInt(costCents),
            priceCents: Decimal.zero,
            stockQuantity: Value(stockQty),
          ),
        );
  }

  Future<void> insertBatch({
    required int productId,
    int? variantId,
    required int receivedQty,
    required int remainingQty,
    required int unitCostCents,
    bool active = true,
  }) async {
    await db.into(db.productBatches).insert(
          ProductBatchesCompanion.insert(
            productId: productId,
            variantId: Value(variantId),
            batchNumber:
                'BATCH-${DateTime.now().microsecondsSinceEpoch}-${variantId ?? 0}',
            receivedQuantity: receivedQty,
            remainingQuantity: remainingQty,
            unitCostCents: Decimal.fromInt(unitCostCents),
            isActive: Value(active),
          ),
        );
  }

  // ── 1. FIFO regression — multi-batch with different unit costs ───────

  test(
      'FIFO product with two batches at different unit costs returns batch '
      'ledger total (NOT variant.cost × stock)',
      () async {
    // Mirror the field-reported case exactly:
    //   batch1: 10 × 9900 = 99,000
    //   batch2:  3 × 9801 = 29,403
    //   variant.cost = 9801 (display, latest paid)
    //   variant.stock = 13
    // Pre-Phase-15 wrong formula: 13 × 9801 = 127,413
    // Phase-15 correct formula:    99,000 + 29,403 = 128,403
    final productId = await insertProduct(
      name: 'p1 has v',
      costingMethod: 'fifo',
      inventoryTrackingType: 'batch_expiry',
      hasVariants: true,
      costCents: 9844,
      stockQty: 13,
    );
    final variantId = await insertVariant(
      productId: productId,
      sku: 'tt55-1',
      costCents: 9801,
      stockQty: 13,
    );
    await insertBatch(
      productId: productId,
      variantId: variantId,
      receivedQty: 10,
      remainingQty: 10,
      unitCostCents: 9900,
    );
    await insertBatch(
      productId: productId,
      variantId: variantId,
      receivedQty: 3,
      remainingQty: 3,
      unitCostCents: 9801,
    );

    final value = await ds.getTotalInventoryValueCents();
    expect(value, 128403,
        reason:
            'must use Σ(batch.remaining_qty × batch.unit_cost_cents), not '
            'Σ(variant.stock × variant.cost_cents). The 990¢ "drift" '
            'reported by the pre-Phase-15 formula was a measurement bug.');
  });

  // ── 2. WAC happy-path — non-batched product keeps the variant fallback

  test(
      'WAC product without batches falls back to variant.stock × variant.cost',
      () async {
    final productId = await insertProduct(
      name: 'wac-no-batch',
      costingMethod: 'wac',
      inventoryTrackingType: 'standard',
      hasVariants: true,
      costCents: 100,
      stockQty: 5,
    );
    await insertVariant(
      productId: productId,
      sku: 'wac-v1',
      costCents: 200,
      stockQty: 5,
    );

    final value = await ds.getTotalInventoryValueCents();
    expect(value, 1000,
        reason: '5 × 200 = 1000 — variant fallback kicks in when no '
            'active batch row exists for the variant.');
  });

  // ── 3. Product without variants — third branch of the COALESCE ───────

  test(
      'Product without variants and without batches uses '
      'product.stock × product.cost',
      () async {
    await insertProduct(
      name: 'simple',
      costingMethod: 'wac',
      inventoryTrackingType: 'standard',
      hasVariants: false,
      costCents: 1500,
      stockQty: 4,
    );

    final value = await ds.getTotalInventoryValueCents();
    expect(value, 6000, reason: '4 × 1500 = 6000');
  });

  // ── 4. Inactive batches are excluded ──────────────────────────────────

  test('Inactive (soft-deleted) batches are NOT counted', () async {
    final productId = await insertProduct(
      name: 'with inactive batch',
      costingMethod: 'fifo',
      inventoryTrackingType: 'standard',
      hasVariants: false,
      costCents: 100,
      stockQty: 0,
    );
    await insertBatch(
      productId: productId,
      receivedQty: 5,
      remainingQty: 5,
      unitCostCents: 200,
      active: false,
    );
    await insertBatch(
      productId: productId,
      receivedQty: 3,
      remainingQty: 3,
      unitCostCents: 300,
    );

    final value = await ds.getTotalInventoryValueCents();
    expect(value, 900,
        reason: 'only the active batch (3 × 300) is summed; the inactive '
            'batch is filtered out and the product fallback is suppressed '
            'because an active batch exists for that product.');
  });

  // ── 5. Mixed bag — FIFO + WAC + simple product together ──────────────

  test('Mixed scenario sums all three branches deterministically', () async {
    // Branch A — FIFO product with batch coverage.
    final pA = await insertProduct(
      name: 'A-fifo',
      costingMethod: 'fifo',
      inventoryTrackingType: 'batch_expiry',
      hasVariants: true,
      costCents: 100,
      stockQty: 7,
    );
    final vA = await insertVariant(
      productId: pA,
      sku: 'a-v',
      costCents: 999,
      stockQty: 7,
    );
    await insertBatch(
      productId: pA,
      variantId: vA,
      receivedQty: 7,
      remainingQty: 7,
      unitCostCents: 1000,
    );
    // Σ = 7 × 1000 = 7000

    // Branch B — WAC variant without batches.
    final pB = await insertProduct(
      name: 'B-wac',
      costingMethod: 'wac',
      inventoryTrackingType: 'standard',
      hasVariants: true,
      costCents: 50,
      stockQty: 10,
    );
    await insertVariant(
      productId: pB,
      sku: 'b-v',
      costCents: 50,
      stockQty: 10,
    );
    // Σ = 10 × 50 = 500

    // Branch C — simple product, no variants, no batches.
    await insertProduct(
      name: 'C-simple',
      costingMethod: 'wac',
      inventoryTrackingType: 'standard',
      hasVariants: false,
      costCents: 25,
      stockQty: 4,
    );
    // Σ = 4 × 25 = 100

    final value = await ds.getTotalInventoryValueCents();
    expect(value, 7600, reason: '7000 (FIFO batches) + 500 (WAC variant) '
        '+ 100 (simple product) = 7600');
  });
}
