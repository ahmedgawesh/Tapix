import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// Phase I4 — cross-table invariant enforcement (Invariant I1).
///
/// Verifies that `BatchService.assertInvariantForProduct(...)` is wired into
/// every batch-mutating production path so that any silent desync between
/// `Σ(product_batches.remaining_quantity)` and `product_variants.stock_quantity`
/// causes the enclosing transaction to roll back with a `StateError` carrying
/// the documented message prefix.
///
/// Each test follows the same shape:
///   1. Build a clean state where the invariant holds.
///   2. Inject a desync via raw SQL on `product_variants.stock_quantity`
///      (simulating a future write path that bypasses `BatchService`).
///   3. Trigger a batch-mutating DAO/service call.
///   4. Expect `StateError` whose message starts with
///      `'BatchService.assertInvariant'`.
///
/// One test per insertion site category — proves the wiring exists in:
///   • SaleDao.postSale
///   • PurchaseDao.postPurchase
///   • AdjustmentReturnDao.postPurchaseAdjReturn
///   • InventoryAdjustmentService.adjust (shrinkage)
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late InventoryAdjustmentService invAdjService;
  late AdjustmentReturnDao adjReturnDao;

  late int currencyId;
  late int customerId;
  late int supplierId;

  Future<int> insertProduct({
    required String sku,
    required String name,
    int costCents = 1000,
    int priceCents = 2000,
  }) async {
    final pid = await db.into(db.products).insert(
          ProductsCompanion.insert(
            sku: Value(sku),
            name: name,
            costCents: Decimal.fromInt(costCents),
            priceCents: Decimal.fromInt(priceCents),
            currencyId: Value(currencyId),
            stockQuantity: const Value(0),
            inventoryTrackingType: const Value('batch'),
          ),
        );
    // Also flip costing_method to 'fifo' so both gate signals agree.
    await db.customStatement(
      "UPDATE products SET costing_method = 'fifo' WHERE id = ?",
      [pid],
    );
    return pid;
  }

  Future<int> insertVariant({
    required int productId,
    int costCents = 1000,
    int priceCents = 2000,
  }) =>
      db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              stockQuantity: const Value(0),
              costCents: Decimal.fromInt(costCents),
              priceCents: Decimal.fromInt(priceCents),
            ),
          );

  Future<int> postPurchase({
    required int productId,
    required int variantId,
    required int quantity,
    required int unitCostCents,
    required String poNumber,
  }) async {
    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: poNumber,
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(quantity * unitCostCents),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(quantity * unitCostCents),
            paidAmountCents: Value(Decimal.zero),
            currencyId: currencyId,
            status: const Value('draft'),
            paymentMethod: const Value('credit'),
          ),
        );
    await db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitCostCents: Decimal.fromInt(unitCostCents),
            subtotalCents: Decimal.fromInt(quantity * unitCostCents),
            totalCents: Decimal.fromInt(quantity * unitCostCents),
          ),
        );
    await db.purchaseDao.postPurchase(purchaseId);
    return purchaseId;
  }

  /// Inject a desync by tweaking `product_variants.stock_quantity` directly.
  /// This simulates a future write path that bypasses `BatchService`.
  Future<void> corruptVariantStock({
    required int variantId,
    required int delta,
  }) async {
    await db.customStatement(
      'UPDATE product_variants '
      '   SET stock_quantity = stock_quantity + ? WHERE id = ?',
      [delta, variantId],
    );
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final accounting = AccountingRepository(db);
    journal = JournalEntryService(accounting);
    invAdjService = InventoryAdjustmentService(
      db: db,
      dao: db.inventoryAdjustmentDao,
      journal: journal,
    );
    adjReturnDao = AdjustmentReturnDao(db);

    // Force DB init (seeds accounts + currencies)
    await db.customSelect('SELECT 1').get();

    // Seed system user (FK target for created_by / posted_by)
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, '
      'is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );

    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();
    currencyId = usd.id;

    customerId = await db.into(db.customers).insert(
          CustomersCompanion.insert(
            name: 'I4 Test Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
    supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'I4 Test Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
  });

  tearDown(() async => db.close());

  // ──────────────────────────────────────────────────────────────────────────
  // Common matcher
  // ──────────────────────────────────────────────────────────────────────────
  Matcher isInvariantStateError() => isA<StateError>().having(
        (e) => e.message,
        'message',
        startsWith('BatchService.assertInvariant'),
      );

  // ──────────────────────────────────────────────────────────────────────────
  // 1. SaleDao.postSale
  // ──────────────────────────────────────────────────────────────────────────
  test('SaleDao.postSale throws StateError when ledger is desynced', () async {
    final pid = await insertProduct(sku: 'I4-SALE', name: 'I4 sale product');
    final vid = await insertVariant(productId: pid);

    // Build a clean batch + variant pair: stock=10, Σ(remaining)=10.
    await postPurchase(
      productId: pid,
      variantId: vid,
      quantity: 10,
      unitCostCents: 100,
      poNumber: 'PO-I4-SALE',
    );

    // Inject desync: variant.stock = 12 but Σ(remaining) = 10.
    await corruptVariantStock(variantId: vid, delta: 2);

    // Now try to post a sale of 3 units. The cost-snapshot loop will call
    // BatchService.consumeFifo (which mutates the ledger to remaining=7),
    // then sync product, then I4's assertInvariantForProduct fires.
    // After consume: variant.stock = 12 - 3 = 9, Σ(remaining) = 7 → 9 ≠ 7.
    final saleId = await db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-I4-SALE',
            customerId: Value(customerId),
            subtotalCents: Decimal.fromInt(600),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(600),
            paidAmountCents: Value(Decimal.fromInt(600)),
            currencyId: currencyId,
            paymentMethod: 'cash',
            status: const Value('draft'),
          ),
        );
    await db.into(db.saleItems).insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: pid,
            variantId: Value(vid),
            quantity: 3,
            unitPriceCents: Decimal.fromInt(200),
            subtotalCents: Decimal.fromInt(600),
            totalCents: Decimal.fromInt(600),
          ),
        );

    expect(
      () => db.saleDao.postSale(saleId),
      throwsA(isInvariantStateError()),
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 2. PurchaseDao.postPurchase
  // ──────────────────────────────────────────────────────────────────────────
  test('PurchaseDao.postPurchase throws StateError when ledger is desynced',
      () async {
    final pid = await insertProduct(sku: 'I4-PURCH', name: 'I4 purchase prod');
    final vid = await insertVariant(productId: pid);

    // Pre-corrupt: variant.stock = 5 but Σ(remaining) = 0 (no batches yet).
    await corruptVariantStock(variantId: vid, delta: 5);

    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-I4-PURCH',
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(700),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(700),
            paidAmountCents: Value(Decimal.zero),
            currencyId: currencyId,
            status: const Value('draft'),
            paymentMethod: const Value('credit'),
          ),
        );
    await db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: pid,
            variantId: Value(vid),
            quantity: 7,
            unitCostCents: Decimal.fromInt(100),
            subtotalCents: Decimal.fromInt(700),
            totalCents: Decimal.fromInt(700),
          ),
        );

    // After post: stock = 5+7 = 12, Σ(remaining) = 7 → 12 ≠ 7.
    expect(
      () => db.purchaseDao.postPurchase(purchaseId),
      throwsA(isInvariantStateError()),
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 3. AdjustmentReturnDao.postPurchaseAdjReturn
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'AdjustmentReturnDao.postPurchaseAdjReturn throws StateError on desync',
      () async {
    final pid = await insertProduct(sku: 'I4-PAR', name: 'I4 adj return prod');
    final vid = await insertVariant(productId: pid);

    await postPurchase(
      productId: pid,
      variantId: vid,
      quantity: 10,
      unitCostCents: 100,
      poNumber: 'PO-I4-PAR',
    );

    // Inject desync: variant.stock = 13, Σ(remaining) = 10.
    await corruptVariantStock(variantId: vid, delta: 3);

    final returnId = await adjReturnDao.createPurchaseAdjReturn(
      PurchaseReturnAdjustmentsCompanion.insert(
        returnNumber: 'PAR-I4-1',
        supplierId: supplierId,
        currencyId: currencyId,
        totalCents: Decimal.fromInt(400),
      ),
      [
        PurchaseReturnAdjustmentItemsCompanion.insert(
          returnId: 0, // overwritten by DAO
          productId: pid,
          variantId: Value(vid),
          quantity: 4,
          unitPriceCents: Decimal.fromInt(100),
          totalCents: Decimal.fromInt(400),
        ),
      ],
    );

    // After post: stock = 13 - 4 = 9, Σ(remaining) = 10 - 4 = 6 → 9 ≠ 6.
    expect(
      () => adjReturnDao.postPurchaseAdjReturn(
        returnId,
        journalEntryService: journal,
      ),
      throwsA(isInvariantStateError()),
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 4. InventoryAdjustmentService.adjust (shrinkage)
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'InventoryAdjustmentService.adjust throws StateError on desync (shrinkage)',
      () async {
    final pid = await insertProduct(sku: 'I4-INV', name: 'I4 inv adj prod');
    final vid = await insertVariant(productId: pid);

    await postPurchase(
      productId: pid,
      variantId: vid,
      quantity: 10,
      unitCostCents: 100,
      poNumber: 'PO-I4-INV',
    );

    // Inject desync: variant.stock = 14, Σ(remaining) = 10.
    await corruptVariantStock(variantId: vid, delta: 4);

    // Shrinkage of 2 → consumeFifo deducts 2 from batches (Σ=8) AND
    // StockService decreases variant.stock by 2 (=12). 12 ≠ 8 → assertion
    // fires inside the service's I4 hook.
    expect(
      () => invAdjService.adjust(
        productId: pid,
        variantId: vid,
        type: InventoryAdjustmentType.shrinkage,
        quantityDelta: -2,
        reason: 'I4 desync test',
        currencyId: currencyId,
        userId: 0,
      ),
      throwsA(isInvariantStateError()),
    );
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 5. Sanity: when ledger is in sync, the same paths succeed
  // ──────────────────────────────────────────────────────────────────────────
  test('clean ledger: postSale+voidSale round-trip passes the I4 assertion',
      () async {
    final pid = await insertProduct(sku: 'I4-OK', name: 'I4 clean path');
    final vid = await insertVariant(productId: pid);

    await postPurchase(
      productId: pid,
      variantId: vid,
      quantity: 10,
      unitCostCents: 100,
      poNumber: 'PO-I4-OK',
    );

    final saleId = await db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-I4-OK',
            customerId: Value(customerId),
            subtotalCents: Decimal.fromInt(600),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(600),
            paidAmountCents: Value(Decimal.fromInt(600)),
            currencyId: currencyId,
            paymentMethod: 'cash',
            status: const Value('draft'),
          ),
        );
    await db.into(db.saleItems).insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: pid,
            variantId: Value(vid),
            quantity: 3,
            unitPriceCents: Decimal.fromInt(200),
            subtotalCents: Decimal.fromInt(600),
            totalCents: Decimal.fromInt(600),
          ),
        );

    // No desync injected — both calls must complete without throwing.
    await db.saleDao.postSale(saleId);
    await db.saleDao.voidSale(saleId);

    // Final state: variant.stock = 10, Σ(remaining) = 10.
    final stockRow = await db.customSelect(
      'SELECT stock_quantity FROM product_variants WHERE id = ?',
      variables: [Variable.withInt(vid)],
    ).getSingle();
    final batchRow = await db.customSelect(
      'SELECT COALESCE(SUM(remaining_quantity), 0) AS s '
      '  FROM product_batches WHERE variant_id = ? AND is_active = 1',
      variables: [Variable.withInt(vid)],
    ).getSingle();
    expect(stockRow.read<int>('stock_quantity'), equals(10));
    expect(batchRow.read<int>('s'), equals(10));
  });
}
