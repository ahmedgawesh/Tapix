// ════════════════════════════════════════════════════════════════════════════
// REGRESSION — Linked-return cap must subtract prior adjustment returns.
// ════════════════════════════════════════════════════════════════════════════
//
// Field report (2026-05-17): "إذا قمت بعمل مرتجع غير مرتبط من منتجات ثم قمت
// بعمل مرتجع مرتبط بالفاتورة لنفس المنتجات، البرنامج يسمح باسترجاع كمية أكبر
// من المباعة أو المشتراه ... فهذا سبب أن المخزون زاد عن الذى تم شراءه."
//
// Bug location (root cause)
// -------------------------
//   • `SaleDao.getReturnedQuantity` and `PurchaseDao.getReturnedQuantity`
//     used to count only the linked-return tables (`sale_return_items` /
//     `purchase_return_items`). They ignored
//     `sale_items.qty_returned_adjustment` and
//     `purchase_items.qty_returned_adjustment`, which are the SoT counters
//     bumped by adjustment-return posts via
//     `AdjustmentReturnDao._allocate*ItemsForAdjustment`.
//   • `UnifiedReturnService._getSale/PurchaseReturnableItems` had the same
//     gap in their `already_returned` subquery.
//   • Consequence: an unlinked adjustment return for product X qty N
//     allocated N units against the FIFO-earliest sale_item/purchase_item
//     line. A subsequent linked-return form then re-offered those same
//     units (because the counter wasn't consulted), and posting succeeded
//     even though linked + adjustment > original sold/purchased qty. The
//     surplus units came out of stock that physically didn't exist,
//     inflating GL Inventory above on-hand stock.
//
// The Phase 12 quantity-cap test (adjustment_return_quantity_cap_test.dart)
// covered the OPPOSITE direction (linked first, then adjustment) — that
// direction already worked because the linked-return path correctly bumps
// `qty_returned_linked` and the adjustment cap query consulted both
// counters. The bug was the asymmetric path: adjustment-then-linked.
//
// This test pins BOTH the asymmetric scenario AND that the unified-return
// service / form bloc layer also sees the correct `already_returned`.
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/return_calculation_service.dart';
import 'package:tapix/core/services/unified_return_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late AdjustmentReturnDao adjDao;
  late UnifiedReturnService unifiedService;

  late int currencyId;
  late int customerId;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final accounting = AccountingRepository(db);
    journal = JournalEntryService(accounting);
    adjDao = AdjustmentReturnDao(db);
    unifiedService = UnifiedReturnService(
      db,
      db.purchaseDao,
      db.saleDao,
      adjDao,
      journal,
    );

    await db.customSelect('SELECT 1').get();

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

  // ────────────────────────────────────────────────────────────────────────
  // Test-data builders (mirror those in adjustment_return_quantity_cap_test)
  // ────────────────────────────────────────────────────────────────────────

  Future<({int productId, int variantId})> insertProductWithVariant({
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
            hasVariants: const Value(true),
          ),
        );
    final vid = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: pid,
            stockQuantity: const Value(0),
            costCents: Decimal.fromInt(costCents),
            priceCents: Decimal.fromInt(priceCents),
          ),
        );
    return (productId: pid, variantId: vid);
  }

  Future<int> postPurchase({
    required int productId,
    required int variantId,
    required int quantity,
    int unitCostCents = 1000,
    String poNumber = 'PO-X',
  }) async {
    final pid = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: poNumber,
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(quantity * unitCostCents),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(quantity * unitCostCents),
            currencyId: currencyId,
            status: const Value('draft'),
            paymentMethod: const Value('credit'),
          ),
        );
    await db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            purchaseId: pid,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitCostCents: Decimal.fromInt(unitCostCents),
            subtotalCents: Decimal.fromInt(quantity * unitCostCents),
            totalCents: Decimal.fromInt(quantity * unitCostCents),
          ),
        );
    await db.purchaseDao.postPurchase(pid);
    return pid;
  }

  Future<int> postSale({
    required int productId,
    required int variantId,
    required int quantity,
    int unitPriceCents = 2000,
    String invoiceNumber = 'INV-X',
  }) async {
    final sid = await db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: invoiceNumber,
            customerId: Value(customerId),
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
            saleId: sid,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitPriceCents: Decimal.fromInt(unitPriceCents),
            subtotalCents: Decimal.fromInt(quantity * unitPriceCents),
            totalCents: Decimal.fromInt(quantity * unitPriceCents),
          ),
        );
    await db.saleDao.postSale(sid);
    return sid;
  }

  Future<int> postPurchaseAdjReturn({
    required int productId,
    required int variantId,
    required int quantity,
    int unitPriceCents = 1000,
    String returnNumber = 'PAR-X',
  }) async {
    final retId = await adjDao.createPurchaseAdjReturn(
      PurchaseReturnAdjustmentsCompanion.insert(
        returnNumber: returnNumber,
        supplierId: supplierId,
        currencyId: currencyId,
        totalCents: Decimal.fromInt(quantity * unitPriceCents),
      ),
      [
        PurchaseReturnAdjustmentItemsCompanion.insert(
          returnId: 0,
          productId: productId,
          variantId: Value(variantId),
          quantity: quantity,
          unitPriceCents: Decimal.fromInt(unitPriceCents),
          totalCents: Decimal.fromInt(quantity * unitPriceCents),
        ),
      ],
    );
    await adjDao.postPurchaseAdjReturn(retId, journalEntryService: journal);
    return retId;
  }

  Future<int> postSaleAdjReturn({
    required int productId,
    required int variantId,
    required int quantity,
    int unitPriceCents = 2000,
    String returnNumber = 'SAR-X',
  }) async {
    final retId = await adjDao.createSaleAdjReturn(
      SaleReturnAdjustmentsCompanion.insert(
        returnNumber: returnNumber,
        customerId: Value(customerId),
        currencyId: currencyId,
        totalCents: Decimal.fromInt(quantity * unitPriceCents),
        refundMethod: const Value('cash'),
      ),
      [
        SaleReturnAdjustmentItemsCompanion.insert(
          returnId: 0,
          productId: productId,
          variantId: Value(variantId),
          quantity: quantity,
          unitPriceCents: Decimal.fromInt(unitPriceCents),
          totalCents: Decimal.fromInt(quantity * unitPriceCents),
        ),
      ],
    );
    await adjDao.postSaleAdjReturn(retId, journalEntryService: journal);
    return retId;
  }

  // ════════════════════════════════════════════════════════════════════════
  // PURCHASE SIDE — adjustment first, then linked
  // ════════════════════════════════════════════════════════════════════════

  group('Purchase: linked-return cap AFTER an adjustment return', () {
    test(
        'getReturnedQuantity surfaces adjustment-allocated qty on the '
        'purchase_item line', () async {
      final pv = await insertProductWithVariant(sku: 'BUG-P-1', name: 'Bug P1');
      final purchaseId = await postPurchase(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 10,
          poNumber: 'PO-BUG-P-1');

      // Adjustment return of 4 units. FIFO allocates against this PO line.
      await postPurchaseAdjReturn(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 4,
          returnNumber: 'PAR-BUG-P-1');

      final piRow = await (db.select(db.purchaseItems)
            ..where((i) => i.purchaseId.equals(purchaseId)))
          .getSingle();
      expect(piRow.qtyReturnedAdjustment, equals(4),
          reason: 'allocator must bump the adjustment counter');

      // Now query the cap-helper. Pre-fix this returned 0 (linked-only),
      // post-fix it must return 4.
      final returned = await db.purchaseDao.getReturnedQuantity(piRow.id);
      expect(returned, equals(4),
          reason: 'getReturnedQuantity must include qty_returned_adjustment');
    });

    test(
        'unified-service _getPurchaseReturnableItems exposes correct '
        'remaining qty after an adjustment return', () async {
      final pv = await insertProductWithVariant(sku: 'BUG-P-2', name: 'Bug P2');
      await postPurchase(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 10,
          poNumber: 'PO-BUG-P-2');

      await postPurchaseAdjReturn(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 7,
          returnNumber: 'PAR-BUG-P-2');

      // Ask the service what's still returnable. Pre-fix it would say 10;
      // post-fix it must say 3 (10 - 7).
      final returnable = await unifiedService.getReturnableInvoiceItems(
        productId: pv.productId,
        variantId: pv.variantId,
        side: ReturnSide.purchase,
        partyId: supplierId,
      );
      expect(returnable, hasLength(1));
      expect(returnable.single.remainingQuantity, equals(3),
          reason: 'returnable qty must = original (10) − adjustment (7)');
    });

    test(
        'posting a linked purchase-return after an adjustment cannot exceed '
        'the original purchased qty', () async {
      final pv = await insertProductWithVariant(sku: 'BUG-P-3', name: 'Bug P3');
      final purchaseId = await postPurchase(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 10,
          poNumber: 'PO-BUG-P-3');

      // 1) Adjustment of 7 → 3 units still linkable.
      await postPurchaseAdjReturn(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 7,
          returnNumber: 'PAR-BUG-P-3');

      // 2) Attempt to post a linked return for 5 units (would total 12 > 10).
      final piRow = await (db.select(db.purchaseItems)
            ..where((i) => i.purchaseId.equals(purchaseId)))
          .getSingle();

      final linkedRetId = await db.purchaseDao.createPurchaseReturn(
        PurchaseReturnsCompanion.insert(
          returnNumber: 'PR-BUG-P-3',
          purchaseId: purchaseId,
          subtotalCents: Value(Decimal.fromInt(5000)),
          totalCents: Decimal.fromInt(5000),
          currencyId: currencyId,
        ),
        [
          PurchaseReturnItemsCompanion.insert(
            returnId: 0,
            purchaseItemId: piRow.id,
            quantity: 5,
            subtotalCents: Value(Decimal.fromInt(5000)),
            refundCents: Decimal.fromInt(5000),
          ),
        ],
      );

      expect(
        () => db.purchaseDao.postPurchaseReturn(linkedRetId),
        throwsA(isA<Exception>()),
        reason: 'cap must reject 5 (already 7 adjusted, only 3 available)',
      );
    });

    test('posting a linked purchase-return of EXACTLY the remaining qty works',
        () async {
      final pv = await insertProductWithVariant(sku: 'BUG-P-4', name: 'Bug P4');
      final purchaseId = await postPurchase(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 10,
          poNumber: 'PO-BUG-P-4');

      await postPurchaseAdjReturn(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 7,
          returnNumber: 'PAR-BUG-P-4');

      final piRow = await (db.select(db.purchaseItems)
            ..where((i) => i.purchaseId.equals(purchaseId)))
          .getSingle();

      // 3 units left → linked return of 3 must succeed.
      final linkedRetId = await db.purchaseDao.createPurchaseReturn(
        PurchaseReturnsCompanion.insert(
          returnNumber: 'PR-BUG-P-4',
          purchaseId: purchaseId,
          subtotalCents: Value(Decimal.fromInt(3000)),
          totalCents: Decimal.fromInt(3000),
          currencyId: currencyId,
        ),
        [
          PurchaseReturnItemsCompanion.insert(
            returnId: 0,
            purchaseItemId: piRow.id,
            quantity: 3,
            subtotalCents: Value(Decimal.fromInt(3000)),
            refundCents: Decimal.fromInt(3000),
          ),
        ],
      );

      await db.purchaseDao.postPurchaseReturn(linkedRetId);

      final piAfter = await (db.select(db.purchaseItems)
            ..where((i) => i.id.equals(piRow.id)))
          .getSingle();
      expect(piAfter.qtyReturnedLinked, equals(3));
      expect(piAfter.qtyReturnedAdjustment, equals(7));
      // Invariant: linked + adjustment ≤ original.
      expect(piAfter.qtyReturnedLinked + piAfter.qtyReturnedAdjustment,
          lessThanOrEqualTo(piAfter.quantity));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // SALE SIDE — adjustment first, then linked
  // ════════════════════════════════════════════════════════════════════════

  group('Sale: linked-return cap AFTER an adjustment return', () {
    test(
        'getReturnedQuantity surfaces adjustment-allocated qty on the '
        'sale_item line', () async {
      final pv = await insertProductWithVariant(sku: 'BUG-S-1', name: 'Bug S1');
      // Receive stock so a sale can be posted.
      await postPurchase(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 10,
          poNumber: 'PO-BUG-S-1');

      final saleId = await postSale(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 10,
          invoiceNumber: 'INV-BUG-S-1');

      await postSaleAdjReturn(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 4,
          returnNumber: 'SAR-BUG-S-1');

      final siRow = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(saleId)))
          .getSingle();
      expect(siRow.qtyReturnedAdjustment, equals(4));

      final returned = await db.saleDao.getReturnedQuantity(siRow.id);
      expect(returned, equals(4),
          reason: 'getReturnedQuantity must include qty_returned_adjustment');
    });

    test(
        'unified-service _getSaleReturnableItems exposes correct remaining '
        'qty after an adjustment return', () async {
      final pv = await insertProductWithVariant(sku: 'BUG-S-2', name: 'Bug S2');
      await postPurchase(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 10,
          poNumber: 'PO-BUG-S-2');
      await postSale(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 10,
          invoiceNumber: 'INV-BUG-S-2');

      await postSaleAdjReturn(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 7,
          returnNumber: 'SAR-BUG-S-2');

      final returnable = await unifiedService.getReturnableInvoiceItems(
        productId: pv.productId,
        variantId: pv.variantId,
        side: ReturnSide.sale,
        partyId: customerId,
      );
      expect(returnable, hasLength(1));
      expect(returnable.single.remainingQuantity, equals(3),
          reason: 'returnable qty must = original (10) − adjustment (7)');
    });

    test(
        'posting a linked sale-return after an adjustment cannot exceed '
        'the original sold qty', () async {
      final pv = await insertProductWithVariant(sku: 'BUG-S-3', name: 'Bug S3');
      await postPurchase(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 10,
          poNumber: 'PO-BUG-S-3');
      final saleId = await postSale(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 10,
          invoiceNumber: 'INV-BUG-S-3');

      await postSaleAdjReturn(
          productId: pv.productId,
          variantId: pv.variantId,
          quantity: 7,
          returnNumber: 'SAR-BUG-S-3');

      final siRow = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(saleId)))
          .getSingle();

      // Build a linked sale-return of 5 (would total 12 > 10).
      final calc = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 10,
        returnQuantity: 5,
        originalSubtotalCents: 20000,
        originalDiscountCents: 0,
        originalTaxCents: 0,
      );
      final linkedRetId = await db.saleDao.createSaleReturn(
        SaleReturnsCompanion.insert(
          saleId: saleId,
          returnNumber: 'SR-BUG-S-3',
          totalCents: Decimal.fromInt(calc.refundCents),
          currencyId: currencyId,
          refundMethod: const Value('cash'),
        ),
        [
          SaleReturnItemsCompanion.insert(
            returnId: 0,
            saleItemId: siRow.id,
            quantity: 5,
            refundCents: Decimal.fromInt(calc.refundCents),
            subtotalCents: Value(Decimal.fromInt(calc.subtotalCents)),
            discountCents: Value(Decimal.fromInt(calc.discountCents)),
            taxCents: Value(Decimal.fromInt(calc.taxCents)),
          ),
        ],
      );

      expect(
        () => db.saleDao.postSaleReturn(linkedRetId),
        throwsA(isA<Exception>()),
        reason: 'cap must reject 5 (already 7 adjusted, only 3 available)',
      );
    });
  });
}
