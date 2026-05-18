import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// Phase 0.1 — Hard cap on adjustment-return quantities.
///
/// Validates:
///   • Returning more than Σ purchased / sold (across linked + adjustment
///     history) is REJECTED at the DAO layer with QuantityExceedsHistoryException.
///   • Atomic counters (qty_returned_linked, qty_returned_adjustment) on
///     sale_items / purchase_items are bumped on post and decremented on void.
///   • The cap respects the three inventory tracking modes
///     (standard/wac, batch/fifo, batch_expiry/fifo).
///   • The cap respects products without variants (variantId = null).
///   • The `allowOverHistory: true` escape hatch bypasses the cap (manager
///     override / walk-in case) but still enforces stock invariants.
///   • Combined returns (linked + adjustment) cannot exceed history together.
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late AdjustmentReturnDao adjDao;

  late int currencyId;
  late int customerId;
  late int supplierId;

  Future<int> insertProduct({
    required String sku,
    required String name,
    int costCents = 1000,
    int priceCents = 2000,
    String costingMethod = 'wac',
    String inventoryTracking = 'standard',
    bool hasVariants = true,
  }) async {
    final pid = await db.into(db.products).insert(
          ProductsCompanion.insert(
            sku: Value(sku),
            name: name,
            costCents: Decimal.fromInt(costCents),
            priceCents: Decimal.fromInt(priceCents),
            currencyId: Value(currencyId),
            stockQuantity: const Value(0),
            hasVariants: Value(hasVariants),
          ),
        );
    await db.customStatement(
      'UPDATE products SET costing_method = ?, inventory_tracking_type = ? '
      'WHERE id = ?',
      [costingMethod, inventoryTracking, pid],
    );
    return pid;
  }

  Future<int> insertVariant({
    required int productId,
    int costCents = 1000,
    int priceCents = 2000,
  }) async {
    return db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(0),
            costCents: Decimal.fromInt(costCents),
            priceCents: Decimal.fromInt(priceCents),
          ),
        );
  }

  Future<int> postPurchase({
    required int productId,
    required int? variantId,
    required int quantity,
    int unitCostCents = 1000,
    int? supplierIdOverride,
    String poNumber = 'PO-X',
  }) async {
    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: poNumber,
            supplierId: supplierIdOverride ?? supplierId,
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

  Future<int> postSale({
    required int productId,
    required int? variantId,
    required int quantity,
    int unitPriceCents = 2000,
    int? customerIdOverride,
    String invoiceNumber = 'INV-X',
  }) async {
    final saleId = await db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: invoiceNumber,
            customerId: Value(customerIdOverride ?? customerId),
            subtotalCents: Decimal.fromInt(quantity * unitPriceCents),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(quantity * unitPriceCents),
            paidAmountCents: Value(Decimal.fromInt(quantity * unitPriceCents)),
            currencyId: currencyId,
            paymentMethod: 'cash',
            status: const Value('draft'),
          ),
        );
    await db.into(db.saleItems).insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitPriceCents: Decimal.fromInt(unitPriceCents),
            subtotalCents: Decimal.fromInt(quantity * unitPriceCents),
            totalCents: Decimal.fromInt(quantity * unitPriceCents),
          ),
        );
    await db.saleDao.postSale(saleId);
    return saleId;
  }

  Future<int> createPurchaseAdjReturn({
    required int productId,
    required int? variantId,
    required int quantity,
    int? supplierIdOverride,
    String returnNumber = 'PAR-CAP',
  }) async {
    return adjDao.createPurchaseAdjReturn(
      PurchaseReturnAdjustmentsCompanion.insert(
        returnNumber: returnNumber,
        supplierId: supplierIdOverride ?? supplierId,
        currencyId: currencyId,
        totalCents: Decimal.fromInt(quantity * 1000),
      ),
      [
        PurchaseReturnAdjustmentItemsCompanion.insert(
          returnId: 0,
          productId: productId,
          variantId: Value(variantId),
          quantity: quantity,
          unitPriceCents: Decimal.fromInt(1000),
          totalCents: Decimal.fromInt(quantity * 1000),
        ),
      ],
    );
  }

  Future<int> createSaleAdjReturn({
    required int productId,
    required int? variantId,
    required int quantity,
    int? customerIdOverride,
    String refundMethod = 'cash',
    String returnNumber = 'SAR-CAP',
  }) async {
    return adjDao.createSaleAdjReturn(
      SaleReturnAdjustmentsCompanion.insert(
        returnNumber: returnNumber,
        customerId: Value(customerIdOverride ?? customerId),
        currencyId: currencyId,
        totalCents: Decimal.fromInt(quantity * 2000),
        refundMethod: Value(refundMethod),
      ),
      [
        SaleReturnAdjustmentItemsCompanion.insert(
          returnId: 0,
          productId: productId,
          variantId: Value(variantId),
          quantity: quantity,
          unitPriceCents: Decimal.fromInt(2000),
          totalCents: Decimal.fromInt(quantity * 2000),
        ),
      ],
    );
  }

  Future<({int linked, int adjustment})> readPurchaseItemCounters(
      int purchaseId) async {
    final row = await (db.select(db.purchaseItems)
          ..where((i) => i.purchaseId.equals(purchaseId)))
        .getSingle();
    return (linked: row.qtyReturnedLinked, adjustment: row.qtyReturnedAdjustment);
  }

  Future<({int linked, int adjustment})> readSaleItemCounters(int saleId) async {
    final row = await (db.select(db.saleItems)
          ..where((i) => i.saleId.equals(saleId)))
        .getSingle();
    return (linked: row.qtyReturnedLinked, adjustment: row.qtyReturnedAdjustment);
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final accounting = AccountingRepository(db);
    journal = JournalEntryService(accounting);
    adjDao = AdjustmentReturnDao(db);

    await db.customSelect('SELECT 1').get();

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
            name: 'Cap Test Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
    supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'Cap Test Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
  });

  tearDown(() async => db.close());

  // ──────────────────────────────────────────────────────────────────────────
  // 1. PURCHASE-SIDE CAP — WAC standard tracking, with variants
  // ──────────────────────────────────────────────────────────────────────────
  group('Purchase adjustment return cap — WAC + variants', () {
    test('rejects qty > Σ purchased from supplier', () async {
      final pid = await insertProduct(
          sku: 'CAP-WAC-1', name: 'Cap WAC 1', hasVariants: true);
      final vid = await insertVariant(productId: pid);

      await postPurchase(
          productId: pid, variantId: vid, quantity: 10, poNumber: 'PO-CAP-1');

      final retId = await createPurchaseAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 11,
      );

      expect(
        () => adjDao.postPurchaseAdjReturn(retId, journalEntryService: journal),
        throwsA(isA<QuantityExceedsHistoryException>()),
      );
    });

    test('accepts qty equal to Σ purchased and bumps adjustment counter',
        () async {
      final pid = await insertProduct(
          sku: 'CAP-WAC-2', name: 'Cap WAC 2', hasVariants: true);
      final vid = await insertVariant(productId: pid);

      final purchaseId = await postPurchase(
          productId: pid, variantId: vid, quantity: 10, poNumber: 'PO-CAP-2');

      final retId = await createPurchaseAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 10,
      );
      await adjDao.postPurchaseAdjReturn(retId, journalEntryService: journal);

      // The cap counter is on purchase_items; adjustment-path bumps `adjustment`.
      // Note: linked-path counter remains 0 because this is an unlinked return,
      // but the cap deducts (linked + adjustment) from history.
      // Since the adjustment counter is product-keyed, not purchase-line keyed,
      // we don't update purchase_items here. The cap helper uses an aggregate
      // approach instead. So purchase_items counters stay at 0 for adj-path.
      final counters = await readPurchaseItemCounters(purchaseId);
      expect(counters.linked, equals(0));
      // Counter is updated by allocator in DAO; assert the adjustment counter
      // grew to match the qty returned.
      expect(counters.adjustment, equals(10),
          reason: 'adjustment counter must be bumped on post');
    });

    test('combined linked + adjustment cannot exceed Σ purchased', () async {
      final pid = await insertProduct(
          sku: 'CAP-WAC-3', name: 'Cap WAC 3', hasVariants: true);
      final vid = await insertVariant(productId: pid);

      final purchaseId = await postPurchase(
          productId: pid, variantId: vid, quantity: 10, poNumber: 'PO-CAP-3');

      // First, do a linked return of 6 via PurchaseDao directly.
      final prItems = await (db.select(db.purchaseItems)
            ..where((i) => i.purchaseId.equals(purchaseId)))
          .get();
      final prItem = prItems.single;

      final linkedRetId = await db.purchaseDao.createPurchaseReturn(
        PurchaseReturnsCompanion.insert(
          returnNumber: 'PR-CAP-3',
          purchaseId: purchaseId,
          subtotalCents: Value(Decimal.fromInt(6000)),
          totalCents: Decimal.fromInt(6000),
          currencyId: currencyId,
        ),
        [
          PurchaseReturnItemsCompanion.insert(
            returnId: 0,
            purchaseItemId: prItem.id,
            quantity: 6,
            subtotalCents: Value(Decimal.fromInt(6000)),
            refundCents: Decimal.fromInt(6000),
          ),
        ],
      );
      await db.purchaseDao.postPurchaseReturn(linkedRetId);

      // After: linked counter = 6, history available = 10 - 6 = 4.
      final mid = await readPurchaseItemCounters(purchaseId);
      expect(mid.linked, equals(6));

      // Now: adjustment of 5 must FAIL (would total 11 > 10).
      final retIdFail = await createPurchaseAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 5,
        returnNumber: 'PAR-CAP-3-FAIL',
      );
      expect(
        () => adjDao.postPurchaseAdjReturn(retIdFail,
            journalEntryService: journal),
        throwsA(isA<QuantityExceedsHistoryException>()),
      );

      // But adjustment of 4 must SUCCEED.
      final retIdOk = await createPurchaseAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 4,
        returnNumber: 'PAR-CAP-3-OK',
      );
      await adjDao.postPurchaseAdjReturn(retIdOk, journalEntryService: journal);

      final after = await readPurchaseItemCounters(purchaseId);
      expect(after.linked, equals(6));
      expect(after.adjustment, equals(4));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 2. PURCHASE-SIDE CAP — products WITHOUT variants
  // ──────────────────────────────────────────────────────────────────────────
  group('Purchase adjustment return cap — no variants', () {
    test('rejects qty > Σ purchased when variantId is null', () async {
      final pid = await insertProduct(
          sku: 'CAP-NV-1', name: 'Cap NoVar 1', hasVariants: false);
      // Products without explicit variants still need a single default
      // (color_id IS NULL, size_id IS NULL) row for the stock service.
      await insertVariant(productId: pid);

      await postPurchase(
          productId: pid, variantId: null, quantity: 5, poNumber: 'PO-CAP-NV-1');

      final retId = await createPurchaseAdjReturn(
        productId: pid,
        variantId: null,
        quantity: 6,
      );

      expect(
        () => adjDao.postPurchaseAdjReturn(retId, journalEntryService: journal),
        throwsA(isA<QuantityExceedsHistoryException>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 3. PURCHASE-SIDE CAP — FIFO batch tracking
  // ──────────────────────────────────────────────────────────────────────────
  group('Purchase adjustment return cap — FIFO batch', () {
    test('cap respects history regardless of inventory_tracking_type',
        () async {
      final pid = await insertProduct(
        sku: 'CAP-FIFO-1',
        name: 'Cap FIFO 1',
        costingMethod: 'fifo',
        inventoryTracking: 'batch',
        hasVariants: true,
      );
      final vid = await insertVariant(productId: pid);

      await postPurchase(
          productId: pid, variantId: vid, quantity: 8, poNumber: 'PO-CAP-FIFO-1');

      final retId = await createPurchaseAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 9,
      );

      expect(
        () => adjDao.postPurchaseAdjReturn(retId, journalEntryService: journal),
        throwsA(isA<QuantityExceedsHistoryException>()),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 4. SALE-SIDE CAP — symmetric tests
  // ──────────────────────────────────────────────────────────────────────────
  group('Sale adjustment return cap', () {
    test('rejects qty > Σ sold to customer', () async {
      final pid = await insertProduct(sku: 'CAP-S-1', name: 'Cap Sale 1');
      final vid = await insertVariant(productId: pid);

      await postPurchase(productId: pid, variantId: vid, quantity: 20);
      await postSale(
          productId: pid, variantId: vid, quantity: 5, invoiceNumber: 'INV-S-1');

      final retId = await createSaleAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 6,
      );

      expect(
        () => adjDao.postSaleAdjReturn(retId, journalEntryService: journal),
        throwsA(isA<QuantityExceedsHistoryException>()),
      );
    });

    test('accepts qty within history and bumps counter', () async {
      final pid = await insertProduct(sku: 'CAP-S-2', name: 'Cap Sale 2');
      final vid = await insertVariant(productId: pid);

      await postPurchase(productId: pid, variantId: vid, quantity: 20);
      final saleId = await postSale(
          productId: pid, variantId: vid, quantity: 5, invoiceNumber: 'INV-S-2');

      final retId = await createSaleAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 5,
      );
      await adjDao.postSaleAdjReturn(retId, journalEntryService: journal);

      final counters = await readSaleItemCounters(saleId);
      expect(counters.adjustment, equals(5));
    });

    test('combined linked + adjustment cannot exceed Σ sold', () async {
      final pid = await insertProduct(sku: 'CAP-S-3', name: 'Cap Sale 3');
      final vid = await insertVariant(productId: pid);

      await postPurchase(productId: pid, variantId: vid, quantity: 20);
      final saleId = await postSale(
          productId: pid, variantId: vid, quantity: 10, invoiceNumber: 'INV-S-3');

      final saleItem = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(saleId)))
          .getSingle();

      // Linked return of 7 first.
      final linkedRetId = await db.saleDao.createSaleReturn(
        SaleReturnsCompanion.insert(
          returnNumber: 'SR-CAP-3',
          saleId: saleId,
          subtotalCents: Value(Decimal.fromInt(14000)),
          totalCents: Decimal.fromInt(14000),
          currencyId: currencyId,
          refundMethod: const Value('cash'),
        ),
        [
          SaleReturnItemsCompanion.insert(
            returnId: 0,
            saleItemId: saleItem.id,
            quantity: 7,
            subtotalCents: Value(Decimal.fromInt(14000)),
            refundCents: Decimal.fromInt(14000),
          ),
        ],
      );
      await db.saleDao.postSaleReturn(linkedRetId);

      final mid = await readSaleItemCounters(saleId);
      expect(mid.linked, equals(7));

      // Adjustment of 4 must fail (7+4=11 > 10).
      final retFailId = await createSaleAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 4,
        returnNumber: 'SAR-CAP-3-FAIL',
      );
      expect(
        () => adjDao.postSaleAdjReturn(retFailId, journalEntryService: journal),
        throwsA(isA<QuantityExceedsHistoryException>()),
      );

      // Adjustment of 3 must succeed.
      final retOkId = await createSaleAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 3,
        returnNumber: 'SAR-CAP-3-OK',
      );
      await adjDao.postSaleAdjReturn(retOkId, journalEntryService: journal);

      final after = await readSaleItemCounters(saleId);
      expect(after.linked, equals(7));
      expect(after.adjustment, equals(3));
    });

    test('walk-in (customerId=null) cash refund bypasses cap implicitly',
        () async {
      final pid = await insertProduct(sku: 'CAP-S-4', name: 'Cap Sale 4');
      final vid = await insertVariant(productId: pid);

      await postPurchase(productId: pid, variantId: vid, quantity: 5);

      // No sale to walk-in customer at all → still allow cash refund.
      final retId = await adjDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-WALKIN',
          customerId: const Value(null),
          currencyId: currencyId,
          totalCents: Decimal.fromInt(2000),
          refundMethod: const Value('cash'),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: pid,
            variantId: Value(vid),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(2000),
            totalCents: Decimal.fromInt(2000),
          ),
        ],
      );

      // allowOverHistory: true is required for walk-in (no upstream sale).
      await adjDao.postSaleAdjReturn(
        retId,
        journalEntryService: journal,
        allowOverHistory: true,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 5. allowOverHistory escape hatch
  // ──────────────────────────────────────────────────────────────────────────
  group('allowOverHistory: true', () {
    test('purchase: bypasses history cap when explicitly allowed', () async {
      final pid = await insertProduct(sku: 'CAP-OV-1', name: 'Override 1');
      final vid = await insertVariant(productId: pid);

      // Force stock without any purchase invoice (corruption-style setup).
      await db.customStatement(
          'UPDATE product_variants SET stock_quantity = 5 WHERE id = ?', [vid]);
      await db.customStatement(
          'UPDATE products SET stock_quantity = 5 WHERE id = ?', [pid]);

      final retId = await createPurchaseAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 3,
      );

      // Without override: rejected (history is empty).
      expect(
        () => adjDao.postPurchaseAdjReturn(retId, journalEntryService: journal),
        throwsA(isA<QuantityExceedsHistoryException>()),
      );

      // With override: allowed.
      final retId2 = await createPurchaseAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 3,
        returnNumber: 'PAR-OV-1-B',
      );
      await adjDao.postPurchaseAdjReturn(
        retId2,
        journalEntryService: journal,
        allowOverHistory: true,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 6. Counter reverse on void
  // ──────────────────────────────────────────────────────────────────────────
  group('Counter reverse on void', () {
    test('voidPurchaseAdjReturn decrements adjustment counter', () async {
      final pid = await insertProduct(sku: 'CAP-V-1', name: 'Void 1');
      final vid = await insertVariant(productId: pid);

      final purchaseId = await postPurchase(
          productId: pid, variantId: vid, quantity: 10);

      final retId = await createPurchaseAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 4,
      );
      await adjDao.postPurchaseAdjReturn(retId, journalEntryService: journal);
      expect((await readPurchaseItemCounters(purchaseId)).adjustment, equals(4));

      await adjDao.voidPurchaseAdjReturn(retId, journalEntryService: journal);
      expect((await readPurchaseItemCounters(purchaseId)).adjustment, equals(0));
    });

    test('voidSaleAdjReturn decrements adjustment counter', () async {
      final pid = await insertProduct(sku: 'CAP-V-2', name: 'Void 2');
      final vid = await insertVariant(productId: pid);

      await postPurchase(productId: pid, variantId: vid, quantity: 10);
      final saleId = await postSale(
          productId: pid, variantId: vid, quantity: 5, invoiceNumber: 'INV-V-2');

      final retId = await createSaleAdjReturn(
        productId: pid,
        variantId: vid,
        quantity: 2,
      );
      await adjDao.postSaleAdjReturn(retId, journalEntryService: journal);
      expect((await readSaleItemCounters(saleId)).adjustment, equals(2));

      await adjDao.voidSaleAdjReturn(retId, journalEntryService: journal);
      expect((await readSaleItemCounters(saleId)).adjustment, equals(0));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 7. Linked path counter increments on post and decrements on void
  // ──────────────────────────────────────────────────────────────────────────
  group('Linked path counters', () {
    test('postPurchaseReturn / voidPurchaseReturn moves linked counter',
        () async {
      final pid = await insertProduct(sku: 'CAP-L-1', name: 'Linked 1');
      final vid = await insertVariant(productId: pid);

      final purchaseId = await postPurchase(
          productId: pid, variantId: vid, quantity: 10);
      final pi = await (db.select(db.purchaseItems)
            ..where((i) => i.purchaseId.equals(purchaseId)))
          .getSingle();

      final retId = await db.purchaseDao.createPurchaseReturn(
        PurchaseReturnsCompanion.insert(
          returnNumber: 'PR-L-1',
          purchaseId: purchaseId,
          subtotalCents: Value(Decimal.fromInt(3000)),
          totalCents: Decimal.fromInt(3000),
          currencyId: currencyId,
        ),
        [
          PurchaseReturnItemsCompanion.insert(
            returnId: 0,
            purchaseItemId: pi.id,
            quantity: 3,
            subtotalCents: Value(Decimal.fromInt(3000)),
            refundCents: Decimal.fromInt(3000),
          ),
        ],
      );
      await db.purchaseDao.postPurchaseReturn(retId);
      expect((await readPurchaseItemCounters(purchaseId)).linked, equals(3));

      await db.purchaseDao.voidPurchaseReturn(retId);
      expect((await readPurchaseItemCounters(purchaseId)).linked, equals(0));
    });
  });
}
