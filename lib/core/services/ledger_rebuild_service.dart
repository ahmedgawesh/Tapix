import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../../features/accounting/data/repositories/accounting_repository.dart';
import '../../features/accounting/domain/models/journal_entry_data.dart';
import 'journal_entry_service.dart';

/// STEP 8: Ledger Rebuild Service
///
/// Rebuilds the General Ledger from raw historical transactions.
/// This is a destructive operation that:
/// 1. Resets ALL account balances to zero
/// 2. Deletes ALL existing journal entries and lines
/// 3. Re-creates journal entries from sales, purchases, expenses, returns
/// 4. Verifies the trial balance is balanced after rebuild
///
/// This should ONLY be run as part of the accounting fix process.
class LedgerRebuildService {
  final AppDatabase _db;
  final AccountingRepository _accountingRepo;
  final JournalEntryService _journalService;

  LedgerRebuildService({
    required AppDatabase db,
    required AccountingRepository accountingRepo,
    required JournalEntryService journalService,
  })  : _db = db,
        _accountingRepo = accountingRepo,
        _journalService = journalService;

  /// Rebuild the entire ledger from historical transactions.
  /// Returns a report of what was done.
  ///
  /// [confirmationToken] must be set to `true` to proceed.
  /// This prevents accidental invocation — the caller (UI) must
  /// explicitly confirm the destructive operation.
  Future<LedgerRebuildReport> rebuild({
    bool confirmationToken = false,
  }) async {
    if (!confirmationToken) {
      throw StateError(
        'LedgerRebuildService.rebuild() requires confirmationToken=true. '
        'This is a destructive operation that deletes all journal entries.',
      );
    }

    final report = LedgerRebuildReport();
    final stopwatch = Stopwatch()..start();

    developer.log('=== LEDGER REBUILD STARTED ===', name: 'LedgerRebuild');

    // Phase 0: Temporarily reopen all closed periods so replayed entries
    //          are not blocked by the closed-period lock in
    //          AccountingRepository.createJournalEntry().
    final reopenedPeriodIds = await _reopenAllClosedPeriods(report);

    // Capture manual/adjustment entries before deleting the ledger.
    final preservedEntries = await _capturePreservedEntries(report);

    // Phase 1: Reset all account balances to zero
    await _resetAccountBalances(report);

    // Phase 2: Delete all existing journal entries
    await _deleteAllJournalEntries(report);

    // Phase 3: Replay all historical transactions
    await _replaySales(report);
    await _replayPurchases(report);
    await _replayExpenses(report);
    await _replaySaleReturns(report);
    await _replayPurchaseReturns(report);
    await _replaySalePayments(report);
    await _replayPurchasePayments(report);
    await _replayDirectCustomerTransactions(report);
    await _replayDirectSupplierTransactions(report);
    await _replayCustomerOpeningBalances(report);
    await _replaySupplierOpeningBalances(report);
    await _replayPayrolls(report);
    await _replayLoyaltyEarns(report);
    await _replayLoyaltyRedemptions(report);
    await _replayPreservedEntries(preservedEntries, report);

    // Phase 4: Restore closed periods that were temporarily reopened
    await _restoreClosedPeriods(reopenedPeriodIds, report);

    // Phase 5: Verify
    await _verify(report);

    stopwatch.stop();
    report.durationMs = stopwatch.elapsedMilliseconds;

    developer.log(
      '=== LEDGER REBUILD COMPLETE in ${report.durationMs}ms ===\n${report.summary}',
      name: 'LedgerRebuild',
    );

    return report;
  }

  /// Repair ONLY missing opening balance journal entries for customers and
  /// suppliers that have a non-zero balance_cents but no corresponding
  /// 'opening_balance' journal entry.
  ///
  /// This is a SAFE, IDEMPOTENT operation — it will NOT:
  /// - Delete any existing journal entries
  /// - Reset any account balances
  /// - Affect sales, purchases, payments, or any other transactions
  ///
  /// It ONLY creates missing opening balance entries.
  /// Safe to run multiple times — skips customers/suppliers that already
  /// have an opening_balance journal entry.
  Future<OpeningBalanceRepairReport> repairOpeningBalances() async {
    final report = OpeningBalanceRepairReport();

    // Repair customers
    final customers = await _db.select(_db.customers).get();
    for (final customer in customers) {
      final balanceCents = customer.balanceCents.toBigInt().toInt();
      if (balanceCents == 0) continue;

      // Check if an opening_balance journal entry already exists
      final existing = await (_db.select(_db.journalEntries)
            ..where((j) =>
                j.sourceTable.equals('customers') &
                j.sourceId.equals(customer.id) &
                j.entryType.equals('opening_balance')))
          .getSingleOrNull();
      if (existing != null) {
        report.customersSkipped++;
        continue;
      }

      try {
        await _journalService.recordCustomerOpeningBalanceJournalEntry(
          customerId: customer.id,
          amountCents: balanceCents,
          currencyId: customer.currencyId,
        );
        report.customersRepaired++;
        developer.log(
          'Created opening balance JE for Customer #${customer.id}: $balanceCents cents',
          name: 'OpeningBalanceRepair',
        );
      } catch (e) {
        report.errors.add('Customer #${customer.id}: $e');
        developer.log('Error repairing customer #${customer.id}: $e', name: 'OpeningBalanceRepair');
      }
    }

    // Repair suppliers
    final suppliers = await _db.select(_db.suppliers).get();
    for (final supplier in suppliers) {
      final balanceCents = supplier.balanceCents.toBigInt().toInt();
      if (balanceCents == 0) continue;

      final existing = await (_db.select(_db.journalEntries)
            ..where((j) =>
                j.sourceTable.equals('suppliers') &
                j.sourceId.equals(supplier.id) &
                j.entryType.equals('opening_balance')))
          .getSingleOrNull();
      if (existing != null) {
        report.suppliersSkipped++;
        continue;
      }

      try {
        await _journalService.recordSupplierOpeningBalanceJournalEntry(
          supplierId: supplier.id,
          amountCents: balanceCents,
          currencyId: supplier.currencyId,
        );
        report.suppliersRepaired++;
        developer.log(
          'Created opening balance JE for Supplier #${supplier.id}: $balanceCents cents',
          name: 'OpeningBalanceRepair',
        );
      } catch (e) {
        report.errors.add('Supplier #${supplier.id}: $e');
        developer.log('Error repairing supplier #${supplier.id}: $e', name: 'OpeningBalanceRepair');
      }
    }

    developer.log(
      'Opening balance repair complete: '
      '${report.customersRepaired} customers, ${report.suppliersRepaired} suppliers repaired. '
      '${report.customersSkipped} customers, ${report.suppliersSkipped} suppliers skipped.',
      name: 'OpeningBalanceRepair',
    );

    return report;
  }

  /// Phase 0: Temporarily reopen all closed periods so the replay can
  /// create journal entries for dates that fall within those periods.
  /// Returns the list of period IDs that were reopened.
  Future<List<int>> _reopenAllClosedPeriods(LedgerRebuildReport report) async {
    final closedPeriods = await (_db.select(_db.accountingPeriods)
          ..where((p) => p.isClosed.equals(true)))
        .get();

    final ids = <int>[];
    for (final period in closedPeriods) {
      await (_db.update(_db.accountingPeriods)
            ..where((p) => p.id.equals(period.id)))
          .write(const AccountingPeriodsCompanion(
            isClosed: Value(false),
          ));
      ids.add(period.id);
    }

    report.periodsReopened = ids.length;
    if (ids.isNotEmpty) {
      developer.log(
        'Temporarily reopened ${ids.length} closed periods for rebuild',
        name: 'LedgerRebuild',
      );
    }
    return ids;
  }

  /// Phase 4: Restore previously closed periods back to closed state.
  Future<void> _restoreClosedPeriods(
    List<int> periodIds,
    LedgerRebuildReport report,
  ) async {
    for (final id in periodIds) {
      await (_db.update(_db.accountingPeriods)
            ..where((p) => p.id.equals(id)))
          .write(AccountingPeriodsCompanion(
            isClosed: const Value(true),
            updatedAt: Value(DateTime.now()),
          ));
    }

    if (periodIds.isNotEmpty) {
      developer.log(
        'Restored ${periodIds.length} closed periods after rebuild',
        name: 'LedgerRebuild',
      );
    }
  }

  /// Phase 1: Reset all account balances to zero
  Future<void> _resetAccountBalances(LedgerRebuildReport report) async {
    final accounts = await (_db.select(_db.accounts)
          ..where((a) => a.isActive.equals(true)))
        .get();

    for (final account in accounts) {
      await (_db.update(_db.accounts)..where((a) => a.id.equals(account.id)))
          .write(AccountsCompanion(
            balanceCents: Value(Decimal.zero),
            updatedAt: Value(DateTime.now()),
          ));
    }

    report.accountsReset = accounts.length;
    developer.log('Reset ${accounts.length} account balances to zero', name: 'LedgerRebuild');
  }

  /// Phase 2: Delete all existing journal entries and lines
  Future<void> _deleteAllJournalEntries(LedgerRebuildReport report) async {
    // Delete lines first (FK constraint)
    final linesDeleted = await _db.delete(_db.journalEntryLines).go();
    final entriesDeleted = await _db.delete(_db.journalEntries).go();

    report.journalEntriesDeleted = entriesDeleted;
    report.journalLinesDeleted = linesDeleted;
    developer.log(
      'Deleted $entriesDeleted journal entries and $linesDeleted lines',
      name: 'LedgerRebuild',
    );
  }

  Future<List<_PreservedJournalEntry>> _capturePreservedEntries(
    LedgerRebuildReport report,
  ) async {
    const preservedTypes = {
      'manual',
      'adjustment',
      'opening',
      'opening_balance',
    };

    final entries = await (_db.select(_db.journalEntries)
          ..where((e) => e.status.equals('posted'))
          ..where((e) => e.entryType.isIn(preservedTypes.toList())))
        .get();

    final preserved = <_PreservedJournalEntry>[];
    for (final entry in entries) {
      final lines = await (_db.select(_db.journalEntryLines)
            ..where((l) => l.journalEntryId.equals(entry.id))
            ..orderBy([(l) => OrderingTerm(expression: l.lineNumber)]))
          .get();

      preserved.add(_PreservedJournalEntry(
        description: entry.description,
        entryDate: entry.entryDate,
        entryType: entry.entryType,
        accountingPeriodId: entry.accountingPeriodId,
        sourceTable: entry.sourceTable,
        sourceId: entry.sourceId,
        createdBy: entry.createdBy,
        lines: lines
            .map((line) => JournalEntryLineData(
                  accountId: line.accountId,
                  debitCents: line.debitCents.toBigInt().toInt(),
                  creditCents: line.creditCents.toBigInt().toInt(),
                  currencyId: line.currencyId,
                  description: line.description,
                ))
            .toList(),
      ));
    }

    report.manualEntriesPreserved = preserved.length;
    if (preserved.isNotEmpty) {
      developer.log(
        'Preserved ${preserved.length} manual/adjustment entries for rebuild',
        name: 'LedgerRebuild',
      );
    }
    return preserved;
  }

  /// Phase 3a: Replay all completed (non-voided) sales
  Future<void> _replaySales(LedgerRebuildReport report) async {
    final sales = await (_db.select(_db.sales)
          ..where((s) => s.status.equals('completed')))
        .get();

    for (final sale in sales) {
      try {
        final totalCents = sale.totalCents.toBigInt().toInt();
        final paidCents = sale.paidAmountCents.toBigInt().toInt();

        await _journalService.recordSaleJournalEntry(
          saleId: sale.id,
          totalCents: totalCents,
          paidAmountCents: paidCents,
          currencyId: sale.currencyId,
          taxCents: sale.taxCents.toBigInt().toInt(),
        );
        report.salesReplayed++;
      } catch (e) {
        report.errors.add('Sale #${sale.id}: $e');
        developer.log('Error replaying sale #${sale.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.salesReplayed} sales', name: 'LedgerRebuild');
  }

  /// Phase 3b: Replay all posted (non-voided) purchases
  Future<void> _replayPurchases(LedgerRebuildReport report) async {
    final purchases = await (_db.select(_db.purchases)
          ..where((p) => p.status.equals('posted')))
        .get();

    for (final purchase in purchases) {
      try {
        final totalCents = purchase.totalCents.toBigInt().toInt();
        final paidCents = purchase.paidAmountCents.toBigInt().toInt();
        final taxCents = purchase.taxCents.toBigInt().toInt();

        await _journalService.recordPurchaseJournalEntry(
          purchaseId: purchase.id,
          totalCents: totalCents,
          paidAmountCents: paidCents,
          currencyId: purchase.currencyId,
          taxCents: taxCents,
          paymentMethod: purchase.paymentMethod,
        );
        report.purchasesReplayed++;
      } catch (e) {
        report.errors.add('Purchase #${purchase.id}: $e');
        developer.log('Error replaying purchase #${purchase.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.purchasesReplayed} purchases', name: 'LedgerRebuild');
  }

  /// Phase 3c: Replay all expenses
  Future<void> _replayExpenses(LedgerRebuildReport report) async {
    final expenses = await _db.select(_db.expenses).get();

    for (final expense in expenses) {
      try {
        final amountCents = expense.amountCents.toBigInt().toInt();

        await _journalService.recordExpenseJournalEntry(
          expenseId: expense.id,
          amountCents: amountCents,
          currencyId: expense.currencyId,
        );
        report.expensesReplayed++;
      } catch (e) {
        report.errors.add('Expense #${expense.id}: $e');
        developer.log('Error replaying expense #${expense.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.expensesReplayed} expenses', name: 'LedgerRebuild');
  }

  /// Phase 3d: Replay all posted sale returns
  Future<void> _replaySaleReturns(LedgerRebuildReport report) async {
    final returns = await (_db.select(_db.saleReturns)
          ..where((r) => r.status.equals('posted')))
        .get();

    for (final ret in returns) {
      try {
        final totalCents = ret.totalCents.toBigInt().toInt();
        final taxCents = ret.taxCents.toBigInt().toInt();

        // Resolve partyId (customer_id) from the parent sale so the policy
        // can satisfy the credit-refund defense-in-depth check.
        final saleRow = await (_db.select(_db.sales)
              ..where((s) => s.id.equals(ret.saleId)))
            .getSingleOrNull();
        final partyId = saleRow?.customerId;

        await _journalService.recordSaleReturnJournalEntry(
          returnId: ret.id,
          totalCents: totalCents,
          currencyId: ret.currencyId,
          taxCents: taxCents,
          refundMethod: ret.refundMethod,
          partyId: partyId,
        );

        // ── COGS reversal leg (Dr 1200 Inventory, Cr 5300 COGS) ──
        // Pre-existing gap in rebuild: the inventory side of linked sale
        // returns used to be omitted, leaving a net positive impact on
        // COGS after a rebuild. We restore it here using the frozen cost
        // snapshot on `sale_return_items.unit_cost_cents` (falls back to
        // the parent sale item's unit_cost_cents when NULL).
        final costRow = await _db.customSelect(
          '''
          SELECT COALESCE(SUM(
                   COALESCE(sri.unit_cost_cents, si.unit_cost_cents, 0)
                   * sri.quantity
                 ), 0) AS cost_cents
          FROM sale_return_items sri
          INNER JOIN sale_items si ON si.id = sri.sale_item_id
          WHERE sri.sale_return_id = ?
          ''',
          variables: [Variable.withInt(ret.id)],
          readsFrom: {_db.saleReturnItems, _db.saleItems},
        ).getSingleOrNull();
        final returnCostCents = costRow?.read<int>('cost_cents') ?? 0;
        if (returnCostCents > 0) {
          await _journalService.recordSaleReturnCOGSReversalJournalEntry(
            returnId: ret.id,
            costCents: returnCostCents,
            currencyId: ret.currencyId,
          );
        }

        report.saleReturnsReplayed++;
      } catch (e) {
        report.errors.add('Sale Return #${ret.id}: $e');
        developer.log('Error replaying sale return #${ret.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.saleReturnsReplayed} sale returns', name: 'LedgerRebuild');
  }

  /// Phase 3e: Replay all posted purchase returns
  Future<void> _replayPurchaseReturns(LedgerRebuildReport report) async {
    final returns = await (_db.select(_db.purchaseReturns)
          ..where((r) => r.status.equals('posted')))
        .get();

    for (final ret in returns) {
      try {
        final totalCents = ret.totalCents.toBigInt().toInt();
        final taxCents = ret.taxCents.toBigInt().toInt();

        await _journalService.recordPurchaseReturnJournalEntry(
          returnId: ret.id,
          totalCents: totalCents,
          taxCents: taxCents,
          currencyId: ret.currencyId,
          refundMethod: ret.refundMethod,
        );
        report.purchaseReturnsReplayed++;
      } catch (e) {
        report.errors.add('Purchase Return #${ret.id}: $e');
        developer.log('Error replaying purchase return #${ret.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.purchaseReturnsReplayed} purchase returns', name: 'LedgerRebuild');
  }

  /// Phase 3f: Replay all customer (sale) payments
  Future<void> _replaySalePayments(LedgerRebuildReport report) async {
    final payments = await _db.select(_db.salePayments).get();

    for (final payment in payments) {
      try {
        final amountCents = payment.amountCents.toBigInt().toInt();
        if (amountCents <= 0) continue;

        await _journalService.recordCustomerPaymentJournalEntry(
          paymentId: payment.id,
          amountCents: amountCents,
          currencyId: payment.currencyId,
          paymentMethod: payment.paymentMethod,
        );
        report.salePaymentsReplayed++;
      } catch (e) {
        report.errors.add('Sale Payment #${payment.id}: $e');
        developer.log('Error replaying sale payment #${payment.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.salePaymentsReplayed} sale payments', name: 'LedgerRebuild');
  }

  /// Phase 3g: Replay all supplier (purchase) payments
  Future<void> _replayPurchasePayments(LedgerRebuildReport report) async {
    final payments = await _db.select(_db.purchasePayments).get();

    for (final payment in payments) {
      try {
        final amountCents = payment.amountCents.toBigInt().toInt();
        if (amountCents <= 0) continue;

        await _journalService.recordSupplierPaymentJournalEntry(
          paymentId: payment.id,
          amountCents: amountCents,
          currencyId: payment.currencyId,
          paymentMethod: payment.paymentMethod,
        );
        report.purchasePaymentsReplayed++;
      } catch (e) {
        report.errors.add('Purchase Payment #${payment.id}: $e');
        developer.log('Error replaying purchase payment #${payment.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.purchasePaymentsReplayed} purchase payments', name: 'LedgerRebuild');
  }

  /// Phase 3h: Replay direct customer transactions (payments & discounts from profile)
  Future<void> _replayDirectCustomerTransactions(LedgerRebuildReport report) async {
    final transactions = await (_db.select(_db.customerTransactions)
          ..where((t) => t.transactionType.isIn(['payment', 'discount'])))
        .get();

    for (final tx in transactions) {
      try {
        final amountCents = tx.amountCents.toBigInt().toInt().abs();
        if (amountCents <= 0) continue;

        if (tx.transactionType == 'payment') {
          await _journalService.recordDirectCustomerPaymentJournalEntry(
            transactionId: tx.id,
            amountCents: amountCents,
            currencyId: tx.currencyId,
          );
        } else if (tx.transactionType == 'discount') {
          await _journalService.recordDirectCustomerDiscountJournalEntry(
            transactionId: tx.id,
            amountCents: amountCents,
            currencyId: tx.currencyId,
          );
        }
        report.directCustomerTransactionsReplayed++;
      } catch (e) {
        report.errors.add('Customer Transaction #${tx.id}: $e');
        developer.log('Error replaying customer transaction #${tx.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.directCustomerTransactionsReplayed} direct customer transactions', name: 'LedgerRebuild');
  }

  /// Phase 3i: Replay direct supplier transactions (payments & discounts from profile)
  Future<void> _replayDirectSupplierTransactions(LedgerRebuildReport report) async {
    final transactions = await (_db.select(_db.supplierTransactions)
          ..where((t) => t.transactionType.isIn(['payment', 'discount'])))
        .get();

    for (final tx in transactions) {
      try {
        final amountCents = tx.amountCents.toBigInt().toInt().abs();
        if (amountCents <= 0) continue;

        if (tx.transactionType == 'payment') {
          await _journalService.recordDirectSupplierPaymentJournalEntry(
            transactionId: tx.id,
            amountCents: amountCents,
            currencyId: tx.currencyId,
          );
        } else if (tx.transactionType == 'discount') {
          await _journalService.recordDirectSupplierDiscountJournalEntry(
            transactionId: tx.id,
            amountCents: amountCents,
            currencyId: tx.currencyId,
          );
        }
        report.directSupplierTransactionsReplayed++;
      } catch (e) {
        report.errors.add('Supplier Transaction #${tx.id}: $e');
        developer.log('Error replaying supplier transaction #${tx.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.directSupplierTransactionsReplayed} direct supplier transactions', name: 'LedgerRebuild');
  }

  /// Phase 3j: Replay opening balances for customers that have a non-zero
  /// balance_cents but whose opening_balance journal entry was NOT preserved
  /// (i.e. it never existed in the first place).
  Future<void> _replayCustomerOpeningBalances(LedgerRebuildReport report) async {
    final customers = await _db.select(_db.customers).get();

    for (final customer in customers) {
      try {
        final balanceCents = customer.balanceCents.toBigInt().toInt();
        if (balanceCents == 0) continue;

        // Check if an opening_balance journal entry already exists for this customer
        // (it would have been replayed via _replayPreservedEntries)
        final existing = await (_db.select(_db.journalEntries)
              ..where((j) =>
                  j.sourceTable.equals('customers') &
                  j.sourceId.equals(customer.id) &
                  j.entryType.equals('opening_balance')))
            .getSingleOrNull();
        if (existing != null) continue;

        await _journalService.recordCustomerOpeningBalanceJournalEntry(
          customerId: customer.id,
          amountCents: balanceCents,
          currencyId: customer.currencyId,
        );
        report.customerOpeningBalancesReplayed++;
      } catch (e) {
        report.errors.add('Customer Opening Balance #${customer.id}: $e');
        developer.log('Error replaying customer opening balance #${customer.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.customerOpeningBalancesReplayed} customer opening balances', name: 'LedgerRebuild');
  }

  /// Phase 3k: Replay opening balances for suppliers that have a non-zero
  /// balance_cents but whose opening_balance journal entry was NOT preserved.
  Future<void> _replaySupplierOpeningBalances(LedgerRebuildReport report) async {
    final suppliers = await _db.select(_db.suppliers).get();

    for (final supplier in suppliers) {
      try {
        final balanceCents = supplier.balanceCents.toBigInt().toInt();
        if (balanceCents == 0) continue;

        // Check if an opening_balance journal entry already exists for this supplier
        final existing = await (_db.select(_db.journalEntries)
              ..where((j) =>
                  j.sourceTable.equals('suppliers') &
                  j.sourceId.equals(supplier.id) &
                  j.entryType.equals('opening_balance')))
            .getSingleOrNull();
        if (existing != null) continue;

        await _journalService.recordSupplierOpeningBalanceJournalEntry(
          supplierId: supplier.id,
          amountCents: balanceCents,
          currencyId: supplier.currencyId,
        );
        report.supplierOpeningBalancesReplayed++;
      } catch (e) {
        report.errors.add('Supplier Opening Balance #${supplier.id}: $e');
        developer.log('Error replaying supplier opening balance #${supplier.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.supplierOpeningBalancesReplayed} supplier opening balances', name: 'LedgerRebuild');
  }

  /// Phase 3l: Replay all PAID payrolls as direct expense.
  /// No accrual. No Salaries Payable. Direct: Dr Salaries Expense, Cr Cash/Bank.
  Future<void> _replayPayrolls(LedgerRebuildReport report) async {
    final paidPayrolls = await (_db.select(_db.payrolls)
          ..where((p) => p.status.equals('paid')))
        .get();

    for (final payroll in paidPayrolls) {
      try {
        final netPayCents = payroll.netPayCents.toBigInt().toInt();
        if (netPayCents <= 0) continue;

        await _journalService.recordPayrollJournalEntry(
          payrollId: payroll.id,
          netPayCents: netPayCents,
          currencyId: payroll.currencyId,
        );

        report.payrollsReplayed++;
      } catch (e) {
        report.errors.add('Payroll #${payroll.id}: $e');
        developer.log('Error replaying payroll #${payroll.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.payrollsReplayed} payrolls', name: 'LedgerRebuild');
  }

  /// Phase 3k: Replay all loyalty point earns.
  /// When points are earned: Dr Discounts Given (5500), Cr Loyalty Points Liability (2300)
  Future<void> _replayLoyaltyEarns(LedgerRebuildReport report) async {
    final earns = await (_db.select(_db.loyaltyPointTransactions)
          ..where((t) => t.transactionType.equals('earn')))
        .get();

    for (final earn in earns) {
      try {
        if (earn.points <= 0) continue;

        // Look up loyalty settings to get point value in cents
        final settings = await (_db.select(_db.loyaltySettingsTable)).getSingleOrNull();
        final pointValueCents = settings?.pointValueCents ?? 1;
        final valueCents = earn.points * pointValueCents;
        if (valueCents <= 0) continue;

        // Get customer currency
        final customer = await _db.customerDao.getCustomer(earn.customerId);
        final currencyId = customer?.currencyId ?? 1;

        // The referenceId on earn transactions typically points to the sale
        final saleId = earn.referenceId ?? earn.id;

        await _journalService.recordLoyaltyEarnJournalEntry(
          saleId: saleId,
          valueCents: valueCents,
          currencyId: currencyId,
        );
        report.loyaltyEarnsReplayed++;
      } catch (e) {
        report.errors.add('Loyalty Earn #${earn.id}: $e');
        developer.log('Error replaying loyalty earn #${earn.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.loyaltyEarnsReplayed} loyalty earns', name: 'LedgerRebuild');
  }

  /// Phase 3l: Replay all loyalty reward redemptions
  Future<void> _replayLoyaltyRedemptions(LedgerRebuildReport report) async {
    final redemptions = await _db.select(_db.customerRewardRedemptions).get();

    for (final redemption in redemptions) {
      try {
        // Look up the reward to get its monetary value
        final reward = await (_db.select(_db.loyaltyRewards)
              ..where((r) => r.id.equals(redemption.rewardId)))
            .getSingleOrNull();
        if (reward == null || reward.valueCents == null || reward.valueCents! <= 0) continue;

        // Get customer currency
        final customer = await _db.customerDao.getCustomer(redemption.customerId);
        final currencyId = customer?.currencyId ?? 1;

        await _journalService.recordLoyaltyRedemptionJournalEntry(
          redemptionId: redemption.id,
          valueCents: reward.valueCents!,
          currencyId: currencyId,
        );
        report.loyaltyRedemptionsReplayed++;
      } catch (e) {
        report.errors.add('Loyalty Redemption #${redemption.id}: $e');
        developer.log('Error replaying loyalty redemption #${redemption.id}: $e', name: 'LedgerRebuild');
      }
    }

    developer.log('Replayed ${report.loyaltyRedemptionsReplayed} loyalty redemptions', name: 'LedgerRebuild');
  }

  Future<void> _replayPreservedEntries(
    List<_PreservedJournalEntry> entries,
    LedgerRebuildReport report,
  ) async {
    for (final entry in entries) {
      try {
        await _accountingRepo.createJournalEntry(
          entryData: JournalEntryData(
            description: entry.description,
            entryDate: entry.entryDate,
            accountingPeriodId: entry.accountingPeriodId,
            entryType: entry.entryType,
            sourceTable: entry.sourceTable,
            sourceId: entry.sourceId,
            lines: entry.lines,
            autoPost: true,
          ),
          userId: entry.createdBy,
        );
        report.manualEntriesReplayed++;
      } catch (e) {
        report.errors.add('Manual Entry "${entry.description}": $e');
        developer.log('Error replaying manual entry: $e', name: 'LedgerRebuild');
      }
    }

    if (entries.isNotEmpty) {
      developer.log(
        'Replayed ${report.manualEntriesReplayed} manual/adjustment entries',
        name: 'LedgerRebuild',
      );
    }
  }

  /// Phase 4: Verify the rebuilt ledger
  Future<void> _verify(LedgerRebuildReport report) async {
    final trialBalance = await _accountingRepo.getTrialBalance();
    report.trialBalanceBalanced = trialBalance.isBalanced;
    report.totalDebits = trialBalance.totalDebitCents;
    report.totalCredits = trialBalance.totalCreditCents;

    if (!trialBalance.isBalanced) {
      report.errors.add(
        'VERIFICATION FAILED: Trial balance not balanced after rebuild. '
        'Debits=${trialBalance.totalDebitCents}, Credits=${trialBalance.totalCreditCents}',
      );
    }

    developer.log(
      'Verification: balanced=${trialBalance.isBalanced}, '
      'debits=${trialBalance.totalDebitCents}, credits=${trialBalance.totalCreditCents}',
      name: 'LedgerRebuild',
    );
  }
}

/// Report of what the ledger rebuild did
class LedgerRebuildReport {
  int periodsReopened = 0;
  int accountsReset = 0;
  int journalEntriesDeleted = 0;
  int journalLinesDeleted = 0;
  int manualEntriesPreserved = 0;
  int manualEntriesReplayed = 0;
  int salesReplayed = 0;
  int purchasesReplayed = 0;
  int expensesReplayed = 0;
  int saleReturnsReplayed = 0;
  int purchaseReturnsReplayed = 0;
  int salePaymentsReplayed = 0;
  int purchasePaymentsReplayed = 0;
  int directCustomerTransactionsReplayed = 0;
  int directSupplierTransactionsReplayed = 0;
  int customerOpeningBalancesReplayed = 0;
  int supplierOpeningBalancesReplayed = 0;
  int payrollsReplayed = 0;
  int loyaltyEarnsReplayed = 0;
  int loyaltyRedemptionsReplayed = 0;
  bool trialBalanceBalanced = false;
  int totalDebits = 0;
  int totalCredits = 0;
  int durationMs = 0;
  List<String> errors = [];

  bool get isSuccess => trialBalanceBalanced && errors.isEmpty;

  String get summary => '''
LEDGER REBUILD REPORT
=====================
Duration: ${durationMs}ms
Closed periods temporarily reopened: $periodsReopened
Accounts reset: $accountsReset
Journal entries deleted: $journalEntriesDeleted
Journal lines deleted: $journalLinesDeleted
Manual entries preserved: $manualEntriesPreserved

Transactions replayed:
  Manual/Adjustments: $manualEntriesReplayed
  Sales: $salesReplayed
  Purchases: $purchasesReplayed
  Expenses: $expensesReplayed
  Sale Returns: $saleReturnsReplayed
  Purchase Returns: $purchaseReturnsReplayed
  Sale Payments: $salePaymentsReplayed
  Purchase Payments: $purchasePaymentsReplayed
  Direct Customer Transactions: $directCustomerTransactionsReplayed
  Direct Supplier Transactions: $directSupplierTransactionsReplayed
  Customer Opening Balances: $customerOpeningBalancesReplayed
  Supplier Opening Balances: $supplierOpeningBalancesReplayed
  Payrolls: $payrollsReplayed
  Loyalty Earns: $loyaltyEarnsReplayed
  Loyalty Redemptions: $loyaltyRedemptionsReplayed

Verification:
  Trial Balance Balanced: $trialBalanceBalanced
  Total Debits: $totalDebits
  Total Credits: $totalCredits

Errors: ${errors.isEmpty ? 'NONE' : '\n  ${errors.join('\n  ')}'}

Result: ${isSuccess ? 'SUCCESS ✓' : 'FAILED ✗'}
''';
}

class _PreservedJournalEntry {
  final String description;
  final DateTime entryDate;
  final String entryType;
  final int? accountingPeriodId;
  final String? sourceTable;
  final int? sourceId;
  final int? createdBy;
  final List<JournalEntryLineData> lines;

  const _PreservedJournalEntry({
    required this.description,
    required this.entryDate,
    required this.entryType,
    required this.accountingPeriodId,
    required this.sourceTable,
    required this.sourceId,
    required this.createdBy,
    required this.lines,
  });
}

/// Report from the lightweight opening balance repair routine.
class OpeningBalanceRepairReport {
  int customersRepaired = 0;
  int customersSkipped = 0;
  int suppliersRepaired = 0;
  int suppliersSkipped = 0;
  List<String> errors = [];

  bool get isSuccess => errors.isEmpty;
  int get totalRepaired => customersRepaired + suppliersRepaired;

  String get summary => '''
OPENING BALANCE REPAIR REPORT
==============================
Customers repaired: $customersRepaired
Customers skipped (already had JE): $customersSkipped
Suppliers repaired: $suppliersRepaired
Suppliers skipped (already had JE): $suppliersSkipped
Errors: ${errors.isEmpty ? 'NONE' : '\n  ${errors.join('\n  ')}'}
Result: ${isSuccess ? 'SUCCESS ✓' : 'FAILED ✗'}
''';
}
