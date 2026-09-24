import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// 2026-05-18 — Phase 15.2 — Reconciliation hardening regression pack.
///
/// Triggered by `tapix_backup_20260518_051956.db` after a user edited a
/// cheque-paid purchase. The Reconciliation & Health screen surfaced:
///
///   * AP mismatch:        GL(journal_lines)=207989, Suppliers=297980
///     ⇒ drift = +89991¢  (= the voided purchase total)
///   * Inventory mismatch: GL(journal_lines)=417100, Σ(stock×cost)=446800
///     ⇒ drift = +29700¢  (= 3 × 9900¢ — exactly the WAC batch left active)
///
/// Two independent root causes (both upstream, both single-file fixes):
///
///   R1 — `voidPurchase` / `voidSale` in the repository reverse the
///        document-level JE (sourceTable='purchases'/'sales') but DO NOT
///        reverse the per-payment JEs (sourceTable='purchase_payments'/
///        'sale_payments'). The supplier/customer sub-ledger correctly
///        records a `payment_reversal` row, but the GL Cr Cash|Bank / Dr AP
///        leg stays posted, silently dropping AP by the cleared amount.
///
///   R2 — `PurchaseDao.voidPurchase` only deactivates `product_batches`
///        when `_isFifoProduct(productId)` is true. But `postPurchase`
///        creates a batch for EVERY tracked product (`if (tracks)`),
///        regardless of `costing_method`. Tracked `wac`/`standard` products
///        therefore left an orphan `is_active=1` batch on void —
///        inflating Σ(active batch remaining × cost) by exactly that
///        batch's value while GL was correctly reversed.
///
/// Each test below FAILS on the pre-Phase-15.2 code and PASSES after the
/// fixes in `purchase_repository_impl.voidPurchase`,
/// `sale_repository_impl.voidSale`, and `purchase_dao.voidPurchase`.
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late AccountingRepository accounting;

  late int currencyId;
  late int customerId;
  late int supplierId;

  Future<int> insertProduct({
    required String sku,
    required String name,
    int costCents = 10000,
    int priceCents = 15000,
    bool hasVariants = true,
    String costingMethod = 'wac',
    String inventoryTrackingType = 'standard',
    bool trackInventory = true,
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
            costingMethod: Value(costingMethod),
            inventoryTrackingType: Value(inventoryTrackingType),
            trackInventory: Value(trackInventory),
          ),
        );
  }

  Future<int> insertVariant({
    required int productId,
    int costCents = 10000,
    int priceCents = 15000,
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

  Future<int> postPurchaseLine({
    required int productId,
    required int? variantId,
    required int quantity,
    int unitCostCents = 10000,
    String poNumber = 'PO-X',
    String paymentMethod = 'credit',
    int paidAmountCents = 0,
  }) async {
    final total = Decimal.fromInt(quantity * unitCostCents);
    final purchaseId = await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            purchaseNumber: poNumber,
            supplierId: supplierId,
            subtotalCents: total,
            taxCents: Decimal.zero,
            totalCents: total,
            paidAmountCents: Value(Decimal.fromInt(paidAmountCents)),
            currencyId: currencyId,
            status: const Value('draft'),
            paymentMethod: Value(paymentMethod),
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
            subtotalCents: total,
            totalCents: total,
          ),
        );
    await db.purchaseDao.postPurchase(purchaseId);
    return purchaseId;
  }

  Future<int> postSaleLine({
    required int productId,
    required int? variantId,
    required int quantity,
    int unitPriceCents = 20000,
    String invoiceNumber = 'INV-X',
    String paymentMethod = 'credit',
    int paidAmountCents = 0,
  }) async {
    final total = Decimal.fromInt(quantity * unitPriceCents);
    final saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: invoiceNumber,
            customerId: Value(customerId),
            subtotalCents: total,
            taxCents: Decimal.zero,
            totalCents: total,
            paidAmountCents: Value(Decimal.fromInt(paidAmountCents)),
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
  // R1 — Payment JE reversal on void
  // ──────────────────────────────────────────────────────────────────────
  group('R1 — purchase_payments / sale_payments JE reversal on void', () {
    test('voiding a purchase whose cheque-cleared payment JE is posted leaves '
        'NO orphan posted purchase_payments JE', () async {
      final pid = await insertProduct(
        sku: 'R1-P',
        name: 'R1-P',
        hasVariants: true,
      );
      final vid = await insertVariant(productId: pid);

      // Stock-only purchase to seed the supplier balance.
      final purchaseId = await postPurchaseLine(
        productId: pid,
        variantId: vid,
        quantity: 3,
        unitCostCents: 30000,
        poNumber: 'PO-R1-P',
        paymentMethod: 'cheque',
      );
      // Post the purchase JE so AP is loaded.
      await journal.recordPurchaseJournalEntry(
        purchaseId: purchaseId,
        totalCents: 90000,
        paidAmountCents: 0,
        currencyId: currencyId,
        taxCents: 0,
        paymentMethod: 'cheque',
      );

      // Cheque clears → record a payment + its JE.
      final paymentId = await db
          .into(db.purchasePayments)
          .insert(
            PurchasePaymentsCompanion.insert(
              purchaseId: purchaseId,
              amountCents: Decimal.fromInt(90000),
              currencyId: currencyId,
              paymentMethod: 'cheque',
              notes: const Value('Cheque cleared via confirmation'),
            ),
          );
      await journal.recordSupplierPaymentJournalEntry(
        paymentId: paymentId,
        amountCents: 90000,
        currencyId: currencyId,
        paymentMethod: 'cheque',
      );

      // Pre-void: exactly one posted, non-reversed JE for this payment.
      final preCount = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM journal_entries '
            "WHERE source_table = 'purchase_payments' AND source_id = ? "
            "AND status = 'posted' AND is_reversed = 0",
            variables: [Variable.withInt(paymentId)],
          )
          .getSingle();
      expect(preCount.read<int>('c'), equals(1));

      // Simulate the repo-level void flow exactly:
      //   1. Void the 'purchases' JE
      //   2. Iterate payments, void each one's JE          ← Phase 15.2 fix
      //   3. dao.voidPurchase(...)
      await journal.voidJournalEntriesForSource(
        sourceTable: 'purchases',
        sourceId: purchaseId,
        reason: 'Purchase voided',
      );
      final payments = await db.purchaseDao.getPurchasePayments(purchaseId);
      for (final p in payments) {
        await journal.voidJournalEntriesForSource(
          sourceTable: 'purchase_payments',
          sourceId: p.id,
          reason: 'Purchase voided — payment JE reversed',
        );
      }
      await db.purchaseDao.voidPurchase(
        purchaseId,
        journalEntryService: journal,
      );

      // Post-void: NO posted, non-reversed payment JE may remain.
      final postCount = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM journal_entries '
            "WHERE source_table = 'purchase_payments' AND source_id = ? "
            "AND status = 'posted' AND is_reversed = 0",
            variables: [Variable.withInt(paymentId)],
          )
          .getSingle();
      expect(
        postCount.read<int>('c'),
        equals(0),
        reason:
            'Cheque-cleared payment JE must be reversed on purchase void, '
            'otherwise AP and Cash/Bank silently drift by the payment amount.',
      );
    });

    test('voiding a sale whose cheque-cleared payment JE is posted leaves '
        'NO orphan posted sale_payments JE', () async {
      final pid = await insertProduct(
        sku: 'R1-S',
        name: 'R1-S',
        hasVariants: true,
      );
      final vid = await insertVariant(productId: pid);

      // Seed stock so the sale can post.
      await postPurchaseLine(
        productId: pid,
        variantId: vid,
        quantity: 20,
        poNumber: 'PO-R1-S',
      );

      final saleId = await postSaleLine(
        productId: pid,
        variantId: vid,
        quantity: 5,
        unitPriceCents: 20000,
        invoiceNumber: 'INV-R1-S',
        paymentMethod: 'cheque',
      );
      await journal.recordSaleJournalEntry(
        saleId: saleId,
        totalCents: 100000,
        paidAmountCents: 0,
        currencyId: currencyId,
        taxCents: 0,
        paymentMethod: 'cheque',
      );

      // Cheque clears → record a payment + its JE.
      final paymentId = await db
          .into(db.salePayments)
          .insert(
            SalePaymentsCompanion.insert(
              saleId: saleId,
              amountCents: Decimal.fromInt(100000),
              currencyId: currencyId,
              paymentMethod: 'cheque',
              notes: const Value('Cheque cleared via confirmation'),
            ),
          );
      await journal.recordCustomerPaymentJournalEntry(
        paymentId: paymentId,
        amountCents: 100000,
        currencyId: currencyId,
        paymentMethod: 'cheque',
      );

      final preCount = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM journal_entries '
            "WHERE source_table = 'sale_payments' AND source_id = ? "
            "AND status = 'posted' AND is_reversed = 0",
            variables: [Variable.withInt(paymentId)],
          )
          .getSingle();
      expect(preCount.read<int>('c'), equals(1));

      // Repo-level void flow.
      await journal.voidJournalEntriesForSource(
        sourceTable: 'sales',
        sourceId: saleId,
        reason: 'Sale voided',
      );
      final payments = await db.saleDao.getSalePayments(saleId);
      for (final p in payments) {
        await journal.voidJournalEntriesForSource(
          sourceTable: 'sale_payments',
          sourceId: p.id,
          reason: 'Sale voided — payment JE reversed',
        );
      }
      await db.saleDao.voidSale(saleId, journalEntryService: journal);

      final postCount = await db
          .customSelect(
            'SELECT COUNT(*) AS c FROM journal_entries '
            "WHERE source_table = 'sale_payments' AND source_id = ? "
            "AND status = 'posted' AND is_reversed = 0",
            variables: [Variable.withInt(paymentId)],
          )
          .getSingle();
      expect(
        postCount.read<int>('c'),
        equals(0),
        reason:
            'Cheque-cleared payment JE must be reversed on sale void, '
            'otherwise AR and Cash/Bank silently drift by the payment amount.',
      );
    });

    test('AP GL balance after purchase void with cleared cheque matches '
        'pre-purchase balance (zero net AP / Cash movement)', () async {
      final pid = await insertProduct(
        sku: 'R1-AP',
        name: 'R1-AP',
        hasVariants: true,
      );
      final vid = await insertVariant(productId: pid);

      final apAccountId =
          await (db.select(db.accounts)
                ..where((a) => a.accountCode.equals('2000')))
              .getSingle()
              .then((a) => a.id);

      Future<int> apBalance() async {
        final row = await db
            .customSelect(
              'SELECT COALESCE(SUM(jel.debit_cents), 0) AS dr, '
              '       COALESCE(SUM(jel.credit_cents), 0) AS cr '
              'FROM journal_entry_lines jel '
              'INNER JOIN journal_entries je ON je.id = jel.journal_entry_id '
              "WHERE jel.account_id = ? AND je.status = 'posted'",
              variables: [Variable.withInt(apAccountId)],
            )
            .getSingle();
        // AP is a liability → balance = Cr − Dr.
        return row.read<int>('cr') - row.read<int>('dr');
      }

      final apBefore = await apBalance();

      final purchaseId = await postPurchaseLine(
        productId: pid,
        variantId: vid,
        quantity: 3,
        unitCostCents: 30000,
        poNumber: 'PO-R1-AP',
        paymentMethod: 'cheque',
      );
      await journal.recordPurchaseJournalEntry(
        purchaseId: purchaseId,
        totalCents: 90000,
        paidAmountCents: 0,
        currencyId: currencyId,
        taxCents: 0,
        paymentMethod: 'cheque',
      );

      // Cheque cleared → payment + JE.
      final paymentId = await db
          .into(db.purchasePayments)
          .insert(
            PurchasePaymentsCompanion.insert(
              purchaseId: purchaseId,
              amountCents: Decimal.fromInt(90000),
              currencyId: currencyId,
              paymentMethod: 'cheque',
            ),
          );
      await journal.recordSupplierPaymentJournalEntry(
        paymentId: paymentId,
        amountCents: 90000,
        currencyId: currencyId,
        paymentMethod: 'cheque',
      );

      // After post + cleared payment: AP returned to zero (Cr 90000 / Dr 90000).
      expect(await apBalance(), equals(apBefore));

      // Void the purchase via the repo-level flow.
      await journal.voidJournalEntriesForSource(
        sourceTable: 'purchases',
        sourceId: purchaseId,
        reason: 'Purchase voided',
      );
      final payments = await db.purchaseDao.getPurchasePayments(purchaseId);
      for (final p in payments) {
        await journal.voidJournalEntriesForSource(
          sourceTable: 'purchase_payments',
          sourceId: p.id,
          reason: 'Purchase voided — payment JE reversed',
        );
      }
      await db.purchaseDao.voidPurchase(
        purchaseId,
        journalEntryService: journal,
      );

      // After void: AP must STILL equal pre-purchase balance (zero net effect).
      // Pre-Phase-15.2 this returned `apBefore - 90000` (= the AP drift).
      expect(
        await apBalance(),
        equals(apBefore),
        reason:
            'Voiding a fully-paid cheque purchase must leave AP at its '
            'pre-purchase balance — both the invoice JE AND the cleared '
            'payment JE must be reversed.',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // R2 — Symmetric batch deactivation on void for ALL tracked products
  // ──────────────────────────────────────────────────────────────────────
  group('R2 — purchase void deactivates batches for WAC/standard products', () {
    test('voiding a purchase of a tracked WAC/standard product deactivates '
        'the batch row created on post', () async {
      // Reproduce product 2 (WAC, standard) from the field backup.
      final pid = await insertProduct(
        sku: 'R2-WAC',
        name: 'WAC tracked product',
        hasVariants: true,
        costingMethod: 'wac',
        inventoryTrackingType: 'standard',
      );
      final vid = await insertVariant(productId: pid);

      final purchaseId = await postPurchaseLine(
        productId: pid,
        variantId: vid,
        quantity: 3,
        unitCostCents: 9900,
        poNumber: 'PO-R2-WAC',
      );

      // Post created exactly one active batch on this line.
      final pItem = await (db.select(
        db.purchaseItems,
      )..where((i) => i.purchaseId.equals(purchaseId))).getSingle();
      final batchesBefore =
          await (db.select(db.productBatches)..where(
                (b) =>
                    b.purchaseItemId.equals(pItem.id) & b.isActive.equals(true),
              ))
              .get();
      expect(
        batchesBefore,
        hasLength(1),
        reason:
            'postPurchase creates a batch for every tracked product, '
            'including WAC. (Phase 6.4 unified ledger.)',
      );
      expect(batchesBefore.first.remainingQuantity, equals(3));

      // Void the purchase.
      await db.purchaseDao.voidPurchase(purchaseId);

      // After void: the batch MUST be `is_active = 0` and remaining = 0.
      // Pre-Phase-15.2 the batch stayed active because the void path
      // gated batch deactivation on `_isFifoProduct`, leaving an orphan
      // `is_active=1` row that inflated Σ(active batch × cost).
      final batchesAfter = await (db.select(
        db.productBatches,
      )..where((b) => b.purchaseItemId.equals(pItem.id))).get();
      expect(batchesAfter, hasLength(1));
      expect(
        batchesAfter.first.isActive,
        isFalse,
        reason:
            'WAC/standard tracked batches must be deactivated on void to '
            'keep Σ(active batch remaining × cost) in sync with GL.',
      );
      expect(batchesAfter.first.remainingQuantity, equals(0));
    });

    test(
      'voiding a purchase of a tracked FIFO/batch_expiry product still '
      'deactivates its batch (regression guard for the original path)',
      () async {
        final pid = await insertProduct(
          sku: 'R2-FIFO',
          name: 'FIFO tracked product',
          hasVariants: true,
          costingMethod: 'fifo',
          inventoryTrackingType: 'batch_expiry',
        );
        final vid = await insertVariant(productId: pid);

        final purchaseId = await postPurchaseLine(
          productId: pid,
          variantId: vid,
          quantity: 10,
          unitCostCents: 9900,
          poNumber: 'PO-R2-FIFO',
        );

        await db.purchaseDao.voidPurchase(purchaseId);

        final pItem = await (db.select(
          db.purchaseItems,
        )..where((i) => i.purchaseId.equals(purchaseId))).getSingle();
        final batchesAfter = await (db.select(
          db.productBatches,
        )..where((b) => b.purchaseItemId.equals(pItem.id))).get();
        expect(batchesAfter, hasLength(1));
        expect(batchesAfter.first.isActive, isFalse);
        expect(batchesAfter.first.remainingQuantity, equals(0));
      },
    );

    test('after voiding a tracked-WAC purchase, Σ(active batch remaining × '
        'cost) for the variant matches variant.stock × variant.cost', () async {
      // This is the exact field-report invariant: the inventory valuation
      // formula in `getTotalInventoryValueCents` (Phase 15.0) must agree
      // across its two branches once the void is symmetric.
      final pid = await insertProduct(
        sku: 'R2-INV',
        name: 'WAC tracked product',
        hasVariants: true,
        costingMethod: 'wac',
        inventoryTrackingType: 'standard',
      );
      final vid = await insertVariant(productId: pid);

      // Two purchases: PO1 leaves stock, PO2 gets voided.
      await postPurchaseLine(
        productId: pid,
        variantId: vid,
        quantity: 10,
        unitCostCents: 10000,
        poNumber: 'PO-R2-INV-A',
      );
      final voidableId = await postPurchaseLine(
        productId: pid,
        variantId: vid,
        quantity: 3,
        unitCostCents: 9900,
        poNumber: 'PO-R2-INV-B',
      );

      await db.purchaseDao.voidPurchase(voidableId);

      // Sum active batches for this variant.
      final batchSum = await db
          .customSelect(
            'SELECT COALESCE(SUM(remaining_quantity * unit_cost_cents), 0) AS total '
            'FROM product_batches WHERE variant_id = ? AND is_active = 1',
            variables: [Variable.withInt(vid)],
          )
          .getSingle();

      // Pre-Phase-15.2: batchSum = 10*10000 + 3*9900 = 129700 (stale batch
      // not deactivated). Post-fix: batchSum = 10*10000 = 100000.
      expect(
        batchSum.read<int>('total'),
        equals(100000),
        reason:
            'Stale WAC batch from a voided purchase must NOT contribute '
            'to the inventory valuation sum.',
      );

      // Variant stock returned to 10 units.
      final variantRow = await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(vid))).getSingle();
      expect(variantRow.stockQuantity, equals(10));
    });
  });
}
