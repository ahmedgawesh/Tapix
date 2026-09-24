import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/void_impact_analyzer.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// 2026-05-13 — Reconciliation hardening regression suite.
///
/// This file pins down four root-cause bugs that produced an AR drift of
/// $229.97 and an Inventory drift of $148.50 in a real customer backup
/// (`tapix_backup_20260513_121448.db`):
///
///   ROOT-CAUSE 1 — `getCustomerProductPurchasedQty` /
///                  `getSupplierProductSuppliedQty` count voided / draft
///                  invoices as "invoiced", so adjustment returns can
///                  exceed actual sold/purchased quantity once the source
///                  invoice is voided.
///
///   ROOT-CAUSE 2 — `voidSale` / `voidPurchase` only cascade-void the
///                  *linked* return tables (`sale_returns`,
///                  `purchase_returns`); they ignore the *adjustment*
///                  tables (`sale_return_adjustments`,
///                  `purchase_return_adjustments`), leaving GL entries +
///                  stock movements + sub-ledger entries orphaned.
///
///   ROOT-CAUSE 3 — `sale_dao.voidSaleReturn` (called during cascade) does
///                  NOT call `journalService.voidJournalEntriesForSource`,
///                  so when a sale is voided its cascaded linked return's
///                  JE remains posted. Result: AR / Inventory line items
///                  are credited twice (once by the cascade-voided return,
///                  again by the sale void).
///
///   ROOT-CAUSE 4 — There is no pre-void impact analysis. Users void a
///                  document with adjustment-return allocations attributed
///                  to its lines and silently corrupt the books.
///
/// Each test below FAILS on the pre-fix code and PASSES after the fixes.
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late AdjustmentReturnDao adjDao;
  late AccountingRepository accounting;
  late VoidImpactAnalyzer voidImpactAnalyzer;

  late int currencyId;
  late int customerId;
  late int supplierId;

  Future<int> insertProduct({
    required String sku,
    required String name,
    int costCents = 1000,
    int priceCents = 2000,
    bool hasVariants = true,
  }) async {
    return db
        .into(db.products)
        .insert(
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
  }

  Future<int> insertVariant({
    required int productId,
    int costCents = 1000,
    int priceCents = 2000,
  }) async {
    return db
        .into(db.productVariants)
        .insert(
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
    final purchaseId = await db
        .into(db.purchases)
        .insert(
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
    await db
        .into(db.purchaseItems)
        .insert(
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
    String paymentMethod = 'cash',
  }) async {
    final total = Decimal.fromInt(quantity * unitPriceCents);
    final saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: invoiceNumber,
            customerId: Value(customerIdOverride ?? customerId),
            subtotalCents: total,
            taxCents: Decimal.zero,
            totalCents: total,
            paidAmountCents: Value(
              paymentMethod == 'cash' ? total : Decimal.zero,
            ),
            currencyId: currencyId,
            paymentMethod: paymentMethod,
            status: const Value('draft'),
          ),
        );
    await db
        .into(db.saleItems)
        .insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitPriceCents: Decimal.fromInt(unitPriceCents),
            subtotalCents: total,
            totalCents: total,
          ),
        );
    await db.saleDao.postSale(saleId);
    return saleId;
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    accounting = AccountingRepository(db);
    journal = JournalEntryService(accounting);
    adjDao = AdjustmentReturnDao(db);
    voidImpactAnalyzer = VoidImpactAnalyzer(db);

    await db.customSelect('SELECT 1').get();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, '
      'is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );

    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    currencyId = usd.id;

    customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'Test Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Test Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
  });

  tearDown(() async => db.close());

  // ──────────────────────────────────────────────────────────────────────
  // FIX A — `s.status='completed'` / `pu.status='posted'` filter on the
  // history queries that drive the cap. Without this, voided invoices are
  // counted as invoiced and the cap permits over-returns.
  // ──────────────────────────────────────────────────────────────────────
  group('Fix A — voided/draft invoices excluded from cap history', () {
    test(
      'voided sale: customer cannot return its quantity via adjustment',
      () async {
        final pid = await insertProduct(
          sku: 'A1-S',
          name: 'A1-S',
          hasVariants: true,
        );
        final vid = await insertVariant(productId: pid);

        await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 50,
          poNumber: 'PO-A1',
        );

        // Sell 5, then VOID it.
        final saleId = await postSale(
          productId: pid,
          variantId: vid,
          quantity: 5,
          invoiceNumber: 'INV-A1',
        );
        await db.saleDao.voidSale(saleId);

        // After void: customer has invoiced=0 sold-and-completed, returned=0.
        // Trying to adjust-return any positive qty MUST be capped.
        final retId = await adjDao.createSaleAdjReturn(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SAR-A1',
            customerId: Value(customerId),
            currencyId: currencyId,
            totalCents: Decimal.fromInt(2000),
            refundMethod: const Value('cash'),
          ),
          [
            SaleReturnAdjustmentItemsCompanion.insert(
              sourceResolution: const Value('unverified'),
              sourceResolutionReason: const Value('test fixture'),
              returnId: 0,
              productId: pid,
              variantId: Value(vid),
              quantity: 1,
              unitPriceCents: Decimal.fromInt(2000),
              totalCents: Decimal.fromInt(2000),
            ),
          ],
        );

        expect(
          () => adjDao.postSaleAdjReturn(retId, journalEntryService: journal),
          throwsA(isA<QuantityExceedsHistoryException>()),
          reason:
              'Voided sales must not feed the cap as invoiced — otherwise the '
              'customer can return quantity that was never delivered.',
        );
      },
    );

    test(
      'voided purchase: supplier cannot have its qty adjustment-returned',
      () async {
        final pid = await insertProduct(
          sku: 'A1-P',
          name: 'A1-P',
          hasVariants: true,
        );
        final vid = await insertVariant(productId: pid);

        // Post a purchase, then void it via the DAO.
        final purchaseId = await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 5,
          poNumber: 'PO-A1-P',
        );
        await db.purchaseDao.voidPurchase(purchaseId);

        final retId = await adjDao.createPurchaseAdjReturn(
          PurchaseReturnAdjustmentsCompanion.insert(
            returnNumber: 'PAR-A1',
            supplierId: supplierId,
            currencyId: currencyId,
            totalCents: Decimal.fromInt(1000),
          ),
          [
            PurchaseReturnAdjustmentItemsCompanion.insert(
              returnId: 0,
              productId: pid,
              variantId: Value(vid),
              quantity: 1,
              unitPriceCents: Decimal.fromInt(1000),
              totalCents: Decimal.fromInt(1000),
            ),
          ],
        );

        expect(
          () =>
              adjDao.postPurchaseAdjReturn(retId, journalEntryService: journal),
          throwsA(isA<QuantityExceedsHistoryException>()),
          reason:
              'Voided purchases must not feed the cap as supplied — otherwise '
              'an adjustment return can return goods that were never received.',
        );
      },
    );

    test('draft sale: never delivered, must not count as invoiced', () async {
      final pid = await insertProduct(
        sku: 'A1-D',
        name: 'A1-D',
        hasVariants: true,
      );
      final vid = await insertVariant(productId: pid);

      // Stock it via a posted purchase so the eventual sale could otherwise
      // succeed, but DO NOT post the sale.
      await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 50,
        poNumber: 'PO-A1-D',
      );
      // Insert a draft sale with items but never call postSale.
      final draftId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'INV-A1-D',
              customerId: Value(customerId),
              subtotalCents: Decimal.fromInt(2000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(2000),
              paidAmountCents: Value(Decimal.zero),
              currencyId: currencyId,
              paymentMethod: 'credit',
              status: const Value('draft'),
            ),
          );
      await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              saleId: draftId,
              productId: pid,
              variantId: Value(vid),
              quantity: 5,
              unitPriceCents: Decimal.fromInt(2000),
              subtotalCents: Decimal.fromInt(2000),
              totalCents: Decimal.fromInt(2000),
            ),
          );

      final retId = await adjDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-A1-D',
          customerId: Value(customerId),
          currencyId: currencyId,
          totalCents: Decimal.fromInt(2000),
          refundMethod: const Value('cash'),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            sourceResolution: const Value('unverified'),
            sourceResolutionReason: const Value('test fixture'),
            returnId: 0,
            productId: pid,
            variantId: Value(vid),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(2000),
            totalCents: Decimal.fromInt(2000),
          ),
        ],
      );

      expect(
        () => adjDao.postSaleAdjReturn(retId, journalEntryService: journal),
        throwsA(isA<QuantityExceedsHistoryException>()),
        reason: 'Draft sales must not feed the cap — goods were never sold.',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // FIX B — Cascade-voided returns must reverse their JEs as well.
  // ──────────────────────────────────────────────────────────────────────
  group('Fix B — cascade-void of linked returns reverses their JEs', () {
    test('voiding a sale via repo flow leaves NO orphan posted JEs', () async {
      final pid = await insertProduct(sku: 'B1', name: 'B1', hasVariants: true);
      final vid = await insertVariant(productId: pid);

      await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 20,
        poNumber: 'PO-B1',
      );
      final saleId = await postSale(
        productId: pid,
        variantId: vid,
        quantity: 5,
        invoiceNumber: 'INV-B1',
        paymentMethod: 'credit',
      );

      // Post the sale's JE via the journal service.
      await journal.recordSaleJournalEntry(
        saleId: saleId,
        totalCents: 10000,
        paidAmountCents: 0,
        currencyId: currencyId,
        taxCents: 0,
        paymentMethod: 'credit',
      );

      // Create + post a linked return for 2 units.
      final saleItem = await (db.select(
        db.saleItems,
      )..where((i) => i.saleId.equals(saleId))).getSingle();
      final returnId = await db.saleDao.createSaleReturn(
        SaleReturnsCompanion.insert(
          returnNumber: 'SR-B1',
          saleId: saleId,
          subtotalCents: Value(Decimal.fromInt(4000)),
          totalCents: Decimal.fromInt(4000),
          currencyId: currencyId,
          refundMethod: const Value('credit'),
        ),
        [
          SaleReturnItemsCompanion.insert(
            returnId: 0,
            saleItemId: saleItem.id,
            quantity: 2,
            subtotalCents: Value(Decimal.fromInt(4000)),
            refundCents: Decimal.fromInt(4000),
          ),
        ],
      );
      await db.saleDao.postSaleReturn(returnId);
      await journal.recordSaleReturnJournalEntry(
        returnId: returnId,
        totalCents: 4000,
        currencyId: currencyId,
        taxCents: 0,
        refundMethod: 'credit',
        partyId: customerId,
      );

      // ── REPO-LIKE void path: void JEs for sale, then dao.voidSale (which
      //    cascade-voids the linked return). The repo passes the journal
      //    service so the cascade also reverses the linked-return JE
      //    inside the same transaction (root-cause #3 fix).
      await journal.voidJournalEntriesForSource(
        sourceTable: 'sales',
        sourceId: saleId,
        reason: 'Sale voided',
      );
      await db.saleDao.voidSale(saleId, journalEntryService: journal);

      // After: there must be NO `sale_returns` JE that is still posted +
      // not reversed. If any remains, the cascade left a financial leg
      // orphan (the bug we are fixing).
      final orphanRows = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM journal_entries '
            "WHERE source_table = 'sale_returns' AND source_id = ? "
            "AND status = 'posted' AND is_reversed = 0",
            variables: [Variable.withInt(returnId)],
          )
          .getSingle();
      expect(
        orphanRows.read<int>('c'),
        equals(0),
        reason: 'Cascade-voided sale_return must have its JEs reversed.',
      );
    });

    test(
      'voiding a purchase reverses cascade-voided purchase_return JEs',
      () async {
        final pid = await insertProduct(
          sku: 'B2',
          name: 'B2',
          hasVariants: true,
        );
        final vid = await insertVariant(productId: pid);

        final purchaseId = await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          poNumber: 'PO-B2',
        );
        // Post the purchase's JE.
        await journal.recordPurchaseJournalEntry(
          purchaseId: purchaseId,
          totalCents: 10000,
          paidAmountCents: 0,
          currencyId: currencyId,
          taxCents: 0,
          paymentMethod: 'credit',
        );

        // Linked purchase return for 3 units.
        final pItem = await (db.select(
          db.purchaseItems,
        )..where((i) => i.purchaseId.equals(purchaseId))).getSingle();
        final returnId = await db.purchaseDao.createPurchaseReturn(
          PurchaseReturnsCompanion.insert(
            returnNumber: 'PR-B2',
            purchaseId: purchaseId,
            subtotalCents: Value(Decimal.fromInt(3000)),
            totalCents: Decimal.fromInt(3000),
            currencyId: currencyId,
          ),
          [
            PurchaseReturnItemsCompanion.insert(
              returnId: 0,
              purchaseItemId: pItem.id,
              quantity: 3,
              subtotalCents: Value(Decimal.fromInt(3000)),
              refundCents: Decimal.fromInt(3000),
            ),
          ],
        );
        await db.purchaseDao.postPurchaseReturn(returnId);
        await journal.recordPurchaseReturnJournalEntry(
          returnId: returnId,
          totalCents: 3000,
          currencyId: currencyId,
          taxCents: 0,
          refundMethod: 'credit',
        );

        // Repo-like void: JE void → dao.voidPurchase (cascades). The repo
        // passes the journal service so the cascade also reverses the
        // linked-return JE inside the same transaction.
        await journal.voidJournalEntriesForSource(
          sourceTable: 'purchases',
          sourceId: purchaseId,
          reason: 'Purchase voided',
        );
        await db.purchaseDao.voidPurchase(
          purchaseId,
          journalEntryService: journal,
        );

        final orphanRows = await db
            .customSelect(
              'SELECT COUNT(*) AS c FROM journal_entries '
              "WHERE source_table = 'purchase_returns' AND source_id = ? "
              "AND status = 'posted' AND is_reversed = 0",
              variables: [Variable.withInt(returnId)],
            )
            .getSingle();
        expect(
          orphanRows.read<int>('c'),
          equals(0),
          reason: 'Cascade-voided purchase_return must have its JEs reversed.',
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  // FIX C — VoidImpactAnalyzer + VoidBlocked exception.
  // ──────────────────────────────────────────────────────────────────────
  group('Fix C — VoidImpactAnalyzer detects entanglement', () {
    test('analyzeSaleVoid reports adjustment-return allocations attributed to '
        'this sale and marks them as a BLOCKER', () async {
      final pid = await insertProduct(sku: 'C1', name: 'C1', hasVariants: true);
      final vid = await insertVariant(productId: pid);

      await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 20,
        poNumber: 'PO-C1',
      );
      final saleId = await postSale(
        productId: pid,
        variantId: vid,
        quantity: 10,
        invoiceNumber: 'INV-C1',
      );

      // Post an adjustment return that FIFO-allocates 4 units onto this sale.
      final retId = await adjDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-C1',
          customerId: Value(customerId),
          currencyId: currencyId,
          totalCents: Decimal.fromInt(8000),
          refundMethod: const Value('cash'),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            sourceResolution: const Value('unverified'),
            sourceResolutionReason: const Value('test fixture'),
            returnId: 0,
            productId: pid,
            variantId: Value(vid),
            quantity: 4,
            unitPriceCents: Decimal.fromInt(2000),
            totalCents: Decimal.fromInt(8000),
          ),
        ],
      );
      await adjDao.postSaleAdjReturn(retId, journalEntryService: journal);

      // sale_items.qty_returned_adjustment is now 4 on this sale's line.
      final report = await voidImpactAnalyzer.analyzeSaleVoid(saleId);

      expect(report.adjustmentAllocatedQty, equals(4));
      expect(report.entangledAdjustmentReturns, isNotEmpty);
      expect(report.entangledAdjustmentReturns.first.returnId, equals(retId));
      expect(
        report.hasBlockers,
        isTrue,
        reason:
            'Adjustment-return entanglement is a hard blocker; the user '
            'must void the adjustment return first.',
      );
    });

    test(
      'analyzeSaleVoid with no entanglement returns hasBlockers=false',
      () async {
        final pid = await insertProduct(
          sku: 'C2',
          name: 'C2',
          hasVariants: true,
        );
        final vid = await insertVariant(productId: pid);

        await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 20,
          poNumber: 'PO-C2',
        );
        final saleId = await postSale(
          productId: pid,
          variantId: vid,
          quantity: 5,
          invoiceNumber: 'INV-C2',
        );

        final report = await voidImpactAnalyzer.analyzeSaleVoid(saleId);
        expect(report.hasBlockers, isFalse);
        expect(report.adjustmentAllocatedQty, equals(0));
        expect(report.entangledAdjustmentReturns, isEmpty);
      },
    );

    test(
      'analyzePurchaseVoid reports entangled purchase adjustment returns',
      () async {
        final pid = await insertProduct(
          sku: 'C3',
          name: 'C3',
          hasVariants: true,
        );
        final vid = await insertVariant(productId: pid);

        final purchaseId = await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          poNumber: 'PO-C3',
        );

        final retId = await adjDao.createPurchaseAdjReturn(
          PurchaseReturnAdjustmentsCompanion.insert(
            returnNumber: 'PAR-C3',
            supplierId: supplierId,
            currencyId: currencyId,
            totalCents: Decimal.fromInt(3000),
          ),
          [
            PurchaseReturnAdjustmentItemsCompanion.insert(
              returnId: 0,
              productId: pid,
              variantId: Value(vid),
              quantity: 3,
              unitPriceCents: Decimal.fromInt(1000),
              totalCents: Decimal.fromInt(3000),
            ),
          ],
        );
        await adjDao.postPurchaseAdjReturn(retId, journalEntryService: journal);

        final report = await voidImpactAnalyzer.analyzePurchaseVoid(purchaseId);
        expect(report.adjustmentAllocatedQty, equals(3));
        expect(report.hasBlockers, isTrue);
        expect(report.entangledAdjustmentReturns.first.returnId, equals(retId));
      },
    );
  });
}
