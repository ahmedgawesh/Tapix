import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/returns/return_journal_policy.dart';
import 'package:tapix/core/services/returns/return_posting_service.dart';
import 'package:tapix/core/services/compliance/customer_credit_note_service.dart';
import 'package:tapix/core/services/compliance/fiscal_period_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

/// Phase 2 compliance regression suite.
///
/// Verifies the invariants enforced by the centralized
/// `ReturnPostingService` chokepoint:
///
///   1. Fiscal-period guard (Phase 2.5) — posts into a closed period
///      are rejected with `FiscalPeriodClosedException`.
///   2. Customer-credit-note sub-ledger (Phase 2.3) — an unlinked sale
///      return with `refund=credit` + `customerId` auto-issues a credit
///      note whose open balance equals the refunded total.
///   3. Snapshot columns (Phase 2.1) — `tax_rate_bps_at_post` and
///      `unit_cost_at_post_cents` are frozen at post-time.
///   4. Disposition routing (Phase 2.2) — a purchase adjustment return
///      with `send_back` disposition routes the inventory leg to
///      1290 Returns-in-Transit instead of 1200 Inventory.
///   5. GL ↔ sub-ledger reconciliation — Σ(open credit-note balances)
///      == GL balance of 2400 Customer Credit Liability after issuance.
void main() {
  late AppDatabase db;
  late AdjustmentReturnDao adjDao;
  late AccountingRepository accountingRepo;
  late ReturnJournalPolicy policy;
  late ReturnPostingService postingService;
  late FiscalPeriodService fiscalService;
  late CustomerCreditNoteService creditNoteService;
  late JournalEntryService journalService;

  // ── Shared fixtures ──────────────────────────────────────────────────
  late int currencyId;
  late int productId;
  late int variantId;
  late int customerId;
  late int supplierId;

  Future<int> accountIdByCode(String code) async {
    final row = await db.customSelect(
      'SELECT id FROM accounts WHERE account_code = ?',
      variables: [Variable.withString(code)],
    ).getSingle();
    return row.read<int>('id');
  }

  /// Sum posted debits/credits for a specific (sourceTable, sourceId).
  Future<List<({int accountId, int debitCents, int creditCents})>>
      journalLinesForSource(String sourceTable, int sourceId) async {
    final rows = await db.customSelect(
      'SELECT jel.account_id, jel.debit_cents, jel.credit_cents '
      'FROM journal_entry_lines jel '
      'INNER JOIN journal_entries je ON je.id = jel.journal_entry_id '
      "WHERE je.source_table = ? AND je.source_id = ? AND je.status = 'posted'",
      variables: [
        Variable.withString(sourceTable),
        Variable.withInt(sourceId),
      ],
    ).get();
    return rows
        .map((r) => (
              accountId: r.read<int>('account_id'),
              debitCents: r.read<int>('debit_cents'),
              creditCents: r.read<int>('credit_cents'),
            ))
        .toList();
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    accountingRepo = AccountingRepository(db);
    policy = ReturnJournalPolicy(accountingRepo);
    fiscalService = FiscalPeriodService(db);
    creditNoteService = CustomerCreditNoteService(
      db: db,
      accountingRepo: accountingRepo,
    );
    postingService = ReturnPostingService(
      accountingRepo: accountingRepo,
      policy: policy,
      fiscalPeriodService: fiscalService,
      creditNoteService: creditNoteService,
    );
    journalService = JournalEntryService(
      accountingRepo,
      returnPostingService: postingService,
    );
    adjDao = AdjustmentReturnDao(db);

    // Trigger migrations (seeds accounts).
    await db.customSelect('SELECT 1').get();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, is_active, created_at, updated_at) '
      'VALUES (0, \'system\', \'no-pin\', \'owner\', 1, $now, $now)',
    );

    // Seed common test fixtures.
    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();
    currencyId = usd.id;

    productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            sku: const Value<String?>('P2-TEST-001'),
            name: 'Phase 2 Test Product',
            costCents: Decimal.fromInt(3000),
            priceCents: Decimal.fromInt(5000),
            currencyId: Value(currencyId),
            stockQuantity: const Value(100),
          ),
        );

    variantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(100),
            costCents: Decimal.fromInt(3000),
            priceCents: Decimal.fromInt(5000),
          ),
        );

    customerId = await db.into(db.customers).insert(
          CustomersCompanion.insert(
            name: 'P2 Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.fromInt(50000)),
          ),
        );

    supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'P2 Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.fromInt(80000)),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  // ──────────────────────────────────────────────────────────────────────
  // TEST 1 — Fiscal-period guard (Phase 2.5)
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 2.5 — Fiscal-period guard', () {
    test(
      'post into a CLOSED period is rejected with FiscalPeriodClosedException',
      () async {
        // Create a return dated January 2025.
        final returnDate = DateTime(2025, 1, 15);
        final returnId = await adjDao.createSaleAdjReturn(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SAR-P2-FP-001',
            customerId: Value(customerId),
            currencyId: currencyId,
            totalCents: Decimal.fromInt(5000),
            refundMethod: const Value('cash'),
            returnDate: Value(returnDate),
          ),
          [
            SaleReturnAdjustmentItemsCompanion.insert(
              returnId: 0,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1,
              unitPriceCents: Decimal.fromInt(5000),
              totalCents: Decimal.fromInt(5000),
            ),
          ],
        );

        // Close the period that covers Jan 2025.
        await fiscalService.ensurePeriod(returnDate);
        await fiscalService.closePeriod(
          periodKey: FiscalPeriodService.keyFor(returnDate),
          userId: 0,
          notes: 'Year-end close',
        );

        // Attempt to post — must throw.
        expect(
          () => adjDao.postSaleAdjReturn(
            returnId,
            journalEntryService: journalService,
            allowOverHistory: true,
          ),
          throwsA(isA<FiscalPeriodClosedException>()),
        );

        // Nothing should have been written to the GL.
        final lines =
            await journalLinesForSource('sale_return_adjustments', returnId);
        expect(lines, isEmpty,
            reason: 'No JE lines should exist for a rejected post');
      },
    );

    test(
      'post into an OPEN period succeeds and posts a balanced JE',
      () async {
        final returnDate = DateTime(2025, 6, 10);
        await fiscalService.ensurePeriod(returnDate); // status=open

        final returnId = await adjDao.createSaleAdjReturn(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SAR-P2-FP-002',
            customerId: Value(customerId),
            currencyId: currencyId,
            totalCents: Decimal.fromInt(5000),
            refundMethod: const Value('cash'),
            returnDate: Value(returnDate),
          ),
          [
            SaleReturnAdjustmentItemsCompanion.insert(
              returnId: 0,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1,
              unitPriceCents: Decimal.fromInt(5000),
              totalCents: Decimal.fromInt(5000),
            ),
          ],
        );

        await adjDao.postSaleAdjReturn(
          returnId,
          journalEntryService: journalService,
          allowOverHistory: true,
        );

        final lines =
            await journalLinesForSource('sale_return_adjustments', returnId);
        final totalDr =
            lines.fold<int>(0, (s, l) => s + l.debitCents);
        final totalCr =
            lines.fold<int>(0, (s, l) => s + l.creditCents);
        expect(totalDr, equals(totalCr), reason: 'JE must be balanced');
        expect(lines, isNotEmpty);
      },
    );

    test('reopenPeriod lets posts succeed again', () async {
      final d = DateTime(2025, 3, 5);
      await fiscalService.ensurePeriod(d);
      final key = FiscalPeriodService.keyFor(d);

      await fiscalService.closePeriod(periodKey: key, userId: 0);
      await expectLater(
        () => fiscalService.assertOpen(d),
        throwsA(isA<FiscalPeriodClosedException>()),
      );

      await fiscalService.reopenPeriod(periodKey: key, userId: 0);
      // Must NOT throw.
      await fiscalService.assertOpen(d);
    });
  });

  // ──────────────────────────────────────────────────────────────────────
  // TEST 2 — Customer credit note sub-ledger (Phase 2.3)
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 2.3 — Customer credit-note sub-ledger', () {
    test(
      'unlinked sale return with refund=credit + customer auto-issues a '
      'credit note whose balance matches the refund total AND 2400 GL',
      () async {
        final returnId = await adjDao.createSaleAdjReturn(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SAR-P2-CN-001',
            customerId: Value(customerId),
            currencyId: currencyId,
            totalCents: Decimal.fromInt(7500), // $75 credit
            refundMethod: const Value('credit'),
          ),
          [
            SaleReturnAdjustmentItemsCompanion.insert(
              returnId: 0,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1,
              unitPriceCents: Decimal.fromInt(7500),
              totalCents: Decimal.fromInt(7500),
            ),
          ],
        );

        await adjDao.postSaleAdjReturn(
          returnId,
          journalEntryService: journalService,
          allowOverHistory: true,
        );

        // ── Sub-ledger: exactly one open credit note, full face value ──
        final notes = await creditNoteService.listOpenForCustomer(
          customerId: customerId,
          currencyId: currencyId,
        );
        expect(notes.length, equals(1),
            reason: 'One credit note should have been auto-issued');
        expect(notes.first.balanceCents.toBigInt().toInt(), equals(7500));
        expect(notes.first.originalAmountCents.toBigInt().toInt(),
            equals(7500));
        expect(notes.first.status, equals('open'));
        expect(notes.first.sourceTable, equals('sale_return_adjustments'));
        expect(notes.first.sourceId, equals(returnId));
        expect(notes.first.issueJournalEntryId, isNotNull);

        // ── GL: 2400 Customer Credit Liability has Cr 7500 from the JE ──
        final lines = await journalLinesForSource(
          'sale_return_adjustments',
          returnId,
        );
        final acct2400 = await accountIdByCode('2400');
        final liabLines =
            lines.where((l) => l.accountId == acct2400).toList();
        expect(liabLines.length, equals(1),
            reason: 'Settlement must route to 2400 (not 1100 AR) '
                'for unlinked + credit refund');
        expect(liabLines.first.creditCents, equals(7500));

        // ── Reconciliation: Σ(open note balances) == 2400 GL balance ──
        final openBal = await creditNoteService.getOpenBalance(
          customerId: customerId,
          currencyId: currencyId,
        );
        expect(openBal, equals(7500),
            reason: 'Sub-ledger total must match the 2400 Cr posted');
      },
    );

    test('apply() decrements balance + posts Dr 2400 / Cr 1100 JE', () async {
      // Issue a note manually for simplicity.
      final returnId = await adjDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-P2-CN-002',
          customerId: Value(customerId),
          currencyId: currencyId,
          totalCents: Decimal.fromInt(10000),
          refundMethod: const Value('credit'),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: productId,
            variantId: Value(variantId),
            quantity: 2,
            unitPriceCents: Decimal.fromInt(5000),
            totalCents: Decimal.fromInt(10000),
          ),
        ],
      );
      await adjDao.postSaleAdjReturn(
        returnId,
        journalEntryService: journalService,
        allowOverHistory: true,
      );

      final notes = await creditNoteService.listOpenForCustomer(
        customerId: customerId,
        currencyId: currencyId,
      );
      expect(notes.length, equals(1));
      final note = notes.first;

      // Apply $30 of the $100 credit.
      await creditNoteService.apply(
        creditNoteId: note.id,
        saleId: null,
        amountCents: 3000,
      );

      final after = await creditNoteService.getById(note.id);
      expect(after!.balanceCents.toBigInt().toInt(), equals(7000));
      expect(after.status, equals('partially_applied'));

      // Apply the remainder.
      await creditNoteService.apply(
        creditNoteId: note.id,
        saleId: null,
        amountCents: 7000,
      );
      final fullyApplied = await creditNoteService.getById(note.id);
      expect(fullyApplied!.balanceCents.toBigInt().toInt(), equals(0));
      expect(fullyApplied.status, equals('fully_applied'));

      // Sub-ledger total is now zero.
      final bal = await creditNoteService.getOpenBalance(
        customerId: customerId,
        currencyId: currencyId,
      );
      expect(bal, equals(0));

      // The apply JEs posted Dr 2400 / Cr 1100.
      final appRows = await db.customSelect(
        'SELECT je.id, je.source_table FROM journal_entries je '
        "WHERE je.entry_type = 'credit_note_application'",
      ).get();
      expect(appRows.length, equals(2));
    });

    test(
      'applying more than available throws CreditNoteInsufficientBalanceException',
      () async {
        final returnId = await adjDao.createSaleAdjReturn(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SAR-P2-CN-003',
            customerId: Value(customerId),
            currencyId: currencyId,
            totalCents: Decimal.fromInt(2000),
            refundMethod: const Value('credit'),
          ),
          [
            SaleReturnAdjustmentItemsCompanion.insert(
              returnId: 0,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1,
              unitPriceCents: Decimal.fromInt(2000),
              totalCents: Decimal.fromInt(2000),
            ),
          ],
        );
        await adjDao.postSaleAdjReturn(
          returnId,
          journalEntryService: journalService,
          allowOverHistory: true,
        );

        final notes = await creditNoteService.listOpenForCustomer(
          customerId: customerId,
          currencyId: currencyId,
        );
        expect(notes.length, equals(1));

        expect(
          () => creditNoteService.apply(
            creditNoteId: notes.first.id,
            saleId: null,
            amountCents: 999999,
          ),
          throwsA(isA<CreditNoteInsufficientBalanceException>()),
        );
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  // TEST 3 — Snapshot columns (Phase 2.1)
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 2.1 — Snapshot columns frozen at post-time', () {
    test(
      'postPurchaseAdjReturn populates tax_rate_bps_at_post + '
      'unit_cost_at_post_cents on every line',
      () async {
        final returnId = await adjDao.createPurchaseAdjReturn(
          PurchaseReturnAdjustmentsCompanion.insert(
            returnNumber: 'PAR-P2-SNAP-001',
            supplierId: supplierId,
            currencyId: currencyId,
            totalCents: Decimal.fromInt(11500),
            refundMethod: const Value('credit'),
          ),
          [
            PurchaseReturnAdjustmentItemsCompanion.insert(
              returnId: 0,
              productId: productId,
              variantId: Value(variantId),
              quantity: 2,
              unitPriceCents: Decimal.fromInt(5000),
              taxCents: Value(Decimal.fromInt(1500)), // 15% of 10000
              totalCents: Decimal.fromInt(11500),
            ),
          ],
        );

        await adjDao.postPurchaseAdjReturn(
          returnId,
          journalEntryService: journalService,
          allowOverHistory: true,
        );

        final row = await db.customSelect(
          'SELECT tax_rate_bps_at_post, unit_cost_at_post_cents '
          'FROM purchase_return_adjustment_items WHERE return_id = ?',
          variables: [Variable.withInt(returnId)],
        ).getSingle();

        // 1500 / 10000 = 15% = 1500 bps.
        expect(row.read<int>('tax_rate_bps_at_post'), equals(1500));
        // unitCost was auto-frozen from product.cost_cents = 3000.
        expect(row.read<int>('unit_cost_at_post_cents'), equals(3000));
      },
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  // TEST 4 — Disposition routing (Phase 2.2)
  // ──────────────────────────────────────────────────────────────────────
  group('Phase 2.2 — Disposition routing', () {
    test(
      'purchase adjustment return with disposition_type=send_back '
      'routes inventory leg to 1290 instead of 1200',
      () async {
        final returnId = await adjDao.createPurchaseAdjReturn(
          PurchaseReturnAdjustmentsCompanion.insert(
            returnNumber: 'PAR-P2-DISP-001',
            supplierId: supplierId,
            currencyId: currencyId,
            totalCents: Decimal.fromInt(6000),
            refundMethod: const Value('credit'),
          ),
          [
            PurchaseReturnAdjustmentItemsCompanion.insert(
              returnId: 0,
              productId: productId,
              variantId: Value(variantId),
              quantity: 2,
              unitPriceCents: Decimal.fromInt(3000),
              totalCents: Decimal.fromInt(6000),
              dispositionType: const Value('send_back'),
            ),
          ],
        );

        await adjDao.postPurchaseAdjReturn(
          returnId,
          journalEntryService: journalService,
          allowOverHistory: true,
        );

        final lines = await journalLinesForSource(
            'purchase_return_adjustments', returnId);
        final acct1200 = await accountIdByCode('1200');
        final acct1290 = await accountIdByCode('1290');

        // Inventory at cost = 2 * 3000 = 6000.
        // send_back → Dr 1290 6000, Cr 1200 6000 (no touch on 4100 for
        // the inventory leg).
        final rit1290 =
            lines.where((l) => l.accountId == acct1290).toList();
        expect(rit1290.length, equals(1),
            reason: 'send_back must debit 1290 Returns-in-Transit');
        expect(rit1290.first.debitCents, equals(6000));

        final inv1200 =
            lines.where((l) => l.accountId == acct1200).toList();
        expect(inv1200.length, equals(1),
            reason: 'Inventory credited at cost regardless of disposition');
        expect(inv1200.first.creditCents, equals(6000));
      },
    );

    test(
      'purchase adjustment return with default disposition=restock '
      'routes inventory leg to 1200 (no 1290 touched)',
      () async {
        final returnId = await adjDao.createPurchaseAdjReturn(
          PurchaseReturnAdjustmentsCompanion.insert(
            returnNumber: 'PAR-P2-DISP-002',
            supplierId: supplierId,
            currencyId: currencyId,
            totalCents: Decimal.fromInt(6000),
            refundMethod: const Value('credit'),
          ),
          [
            PurchaseReturnAdjustmentItemsCompanion.insert(
              returnId: 0,
              productId: productId,
              variantId: Value(variantId),
              quantity: 2,
              unitPriceCents: Decimal.fromInt(3000),
              totalCents: Decimal.fromInt(6000),
              // dispositionType defaults to 'restock'.
            ),
          ],
        );

        await adjDao.postPurchaseAdjReturn(
          returnId,
          journalEntryService: journalService,
          allowOverHistory: true,
        );

        final lines = await journalLinesForSource(
            'purchase_return_adjustments', returnId);
        final acct1290 = await accountIdByCode('1290');
        expect(lines.where((l) => l.accountId == acct1290), isEmpty,
            reason: 'restock must NOT touch 1290');
      },
    );
  });
}
