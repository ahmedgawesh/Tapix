import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../measurement/measurement.dart';
import '../../features/accounting/data/repositories/accounting_repository.dart';
import '../../features/accounting/domain/models/journal_entry_data.dart';
import 'journal_entry_service.dart';
import 'returns/posted_return.dart';

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
  }) : _db = db,
       _accountingRepo = accountingRepo,
       _journalService = journalService;

  /// Rebuild the entire ledger from historical transactions.
  /// Returns a report of what was done.
  ///
  /// [confirmationToken] must be set to `true` to proceed.
  /// This prevents accidental invocation — the caller (UI) must
  /// explicitly confirm the destructive operation.
  Future<LedgerRebuildReport> rebuild({bool confirmationToken = false}) async {
    if (!confirmationToken) {
      throw StateError(
        'LedgerRebuildService.rebuild() requires confirmationToken=true. '
        'This is a destructive operation that deletes all journal entries.',
      );
    }

    final report = LedgerRebuildReport();
    final stopwatch = Stopwatch()..start();

    developer.log('=== LEDGER REBUILD STARTED ===', name: 'LedgerRebuild');

    try {
      await _db.transaction(() async {
        // Phase 0: Temporarily reopen all closed periods so replayed entries
        // are not blocked by the closed-period lock.
        final reopenedPeriodIds = await _reopenAllClosedPeriods(report);

        // Capture manual/adjustment entries before deleting the ledger.
        final preservedEntries = await _capturePreservedEntries(report);

        // Phase 1: Reset all account balances to zero.
        await _resetAccountBalances(report);

        // Phase 2: Delete reconstructable journal entries.
        await _deleteAllJournalEntries(report);

        // Phase 3: Replay all historical transactions.
        await _replaySales(report);
        await _replayPurchases(report);
        await _replayExpenses(report);
        await _replaySaleReturns(report);
        await _replayPurchaseReturns(report);
        await _replayPurchaseAdjustmentReturns(report);
        await _replaySaleAdjustmentReturns(report);
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

        // Consignment sub-ledger journals are immutable audit records and stay
        // in place. Recalculate the cache from the complete posted ledger so
        // their retained lines are included exactly once.
        await _accountingRepo.rebuildCachedAccountBalancesFromPostedLedger();

        // Phase 4: Restore periods, then verify before committing anything.
        await _restoreClosedPeriods(reopenedPeriodIds, report);
        await _verify(report);
        if (report.errors.isNotEmpty || !report.trialBalanceBalanced) {
          throw const _LedgerRebuildRollback();
        }
      });
    } on _LedgerRebuildRollback {
      report.rolledBack = true;
      developer.log(
        'Ledger rebuild failed verification; every database change was rolled back.',
        name: 'LedgerRebuild',
      );
    }

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
      final existing =
          await (_db.select(_db.journalEntries)..where(
                (j) =>
                    j.sourceTable.equals('customers') &
                    j.sourceId.equals(customer.id) &
                    j.entryType.equals('opening_balance'),
              ))
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
        developer.log(
          'Error repairing customer #${customer.id}: $e',
          name: 'OpeningBalanceRepair',
        );
      }
    }

    // Repair suppliers
    final suppliers = await _db.select(_db.suppliers).get();
    for (final supplier in suppliers) {
      final balanceCents = supplier.balanceCents.toBigInt().toInt();
      if (balanceCents == 0) continue;

      final existing =
          await (_db.select(_db.journalEntries)..where(
                (j) =>
                    j.sourceTable.equals('suppliers') &
                    j.sourceId.equals(supplier.id) &
                    j.entryType.equals('opening_balance'),
              ))
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
        developer.log(
          'Error repairing supplier #${supplier.id}: $e',
          name: 'OpeningBalanceRepair',
        );
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
    final closedPeriods = await (_db.select(
      _db.accountingPeriods,
    )..where((p) => p.isClosed.equals(true))).get();

    final ids = <int>[];
    for (final period in closedPeriods) {
      await (_db.update(_db.accountingPeriods)
            ..where((p) => p.id.equals(period.id)))
          .write(const AccountingPeriodsCompanion(isClosed: Value(false)));
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
      await (_db.update(
        _db.accountingPeriods,
      )..where((p) => p.id.equals(id))).write(
        AccountingPeriodsCompanion(
          isClosed: const Value(true),
          updatedAt: Value(DateTime.now()),
        ),
      );
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
    final accounts = await (_db.select(
      _db.accounts,
    )..where((a) => a.isActive.equals(true))).get();

    for (final account in accounts) {
      await (_db.update(
        _db.accounts,
      )..where((a) => a.id.equals(account.id))).write(
        AccountsCompanion(
          balanceCents: Value(Decimal.zero),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }

    report.accountsReset = accounts.length;
    developer.log(
      'Reset ${accounts.length} account balances to zero',
      name: 'LedgerRebuild',
    );
  }

  /// Phase 2: Delete reconstructable journal entries and lines.
  ///
  /// Journals referenced by the immutable consignment sub-ledger must retain
  /// their original IDs. Deleting and recreating them would either violate
  /// the RESTRICT foreign keys or break the frozen audit trail.
  Future<void> _deleteAllJournalEntries(LedgerRebuildReport report) async {
    const protectedJournal = '''
      EXISTS(
        SELECT 1 FROM consignment_obligation_events e
        WHERE e.journal_entry_id=journal_entries.id
      )
      OR EXISTS(
        SELECT 1 FROM consignment_adjustment_return_events e
        WHERE e.journal_entry_id=journal_entries.id
      )
      OR EXISTS(
        SELECT 1 FROM consignment_settlement_statements s
        WHERE s.journal_entry_id=journal_entries.id
           OR s.void_journal_entry_id=journal_entries.id
      )
      OR EXISTS(
        SELECT 1 FROM consignment_settlement_payments p
        WHERE p.journal_entry_id=journal_entries.id
           OR p.reversal_journal_entry_id=journal_entries.id
      )
    ''';

    final protectedCounts = await _db.customSelect('''
      SELECT COUNT(DISTINCT journal_entries.id) AS entry_count,
             COUNT(journal_entry_lines.id) AS line_count
      FROM journal_entries
      LEFT JOIN journal_entry_lines
        ON journal_entry_lines.journal_entry_id=journal_entries.id
      WHERE $protectedJournal
    ''').getSingle();
    report.consignmentJournalEntriesRetained = protectedCounts.read<int>(
      'entry_count',
    );
    report.consignmentJournalLinesRetained = protectedCounts.read<int>(
      'line_count',
    );

    // Delete child rows first, excluding every journal referenced by the
    // consignment sub-ledger. The correlated alias keeps the protection rule
    // independent of the number of historical entries (no SQLite bind limit).
    final linesDeleted = await _db.customUpdate('''
      DELETE FROM journal_entry_lines
      WHERE journal_entry_id IN (
        SELECT journal_entries.id FROM journal_entries
        WHERE NOT ($protectedJournal)
      )
    ''');
    final entriesDeleted = await _db.customUpdate('''
      DELETE FROM journal_entries
      WHERE NOT ($protectedJournal)
    ''');

    report.journalEntriesDeleted = entriesDeleted;
    report.journalLinesDeleted = linesDeleted;
    developer.log(
      'Deleted $entriesDeleted reconstructable journal entries and '
      '$linesDeleted lines; retained '
      '${report.consignmentJournalEntriesRetained} consignment entries',
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
      // Inventory adjustments are not reconstructed from invoices/returns.
      // They must survive a ledger rebuild or 1200 loses opening stock and
      // physical-count adjustments while the quantities remain unchanged.
      'inventory_opening_balance',
      'inventory_shrinkage',
      'inventory_gain',
      'inventory_revaluation',
    };

    final entries =
        await (_db.select(_db.journalEntries)
              ..where((e) => e.status.equals('posted'))
              ..where((e) => e.entryType.isIn(preservedTypes.toList())))
            .get();

    final preserved = <_PreservedJournalEntry>[];
    for (final entry in entries) {
      final lines =
          await (_db.select(_db.journalEntryLines)
                ..where((l) => l.journalEntryId.equals(entry.id))
                ..orderBy([(l) => OrderingTerm(expression: l.lineNumber)]))
              .get();

      preserved.add(
        _PreservedJournalEntry(
          description: entry.description,
          entryDate: entry.entryDate,
          entryType: entry.entryType,
          accountingPeriodId: entry.accountingPeriodId,
          sourceTable: entry.sourceTable,
          sourceId: entry.sourceId,
          createdBy: entry.createdBy,
          lines: lines
              .map(
                (line) => JournalEntryLineData(
                  accountId: line.accountId,
                  debitCents: line.debitCents.toBigInt().toInt(),
                  creditCents: line.creditCents.toBigInt().toInt(),
                  currencyId: line.currencyId,
                  description: line.description,
                ),
              )
              .toList(),
        ),
      );
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
    final sales = await (_db.select(
      _db.sales,
    )..where((s) => s.status.equals('completed'))).get();

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

        // Rebuild the perpetual-inventory leg as well. The old rebuild only
        // recreated revenue / cash / receivable and silently dropped every
        // sale COGS entry after deleting the ledger. SaleDao is the shared
        // source of truth: exact batch-consumption totals for FIFO, frozen
        // sale-item cost for WAC.
        final costCents = await _db.saleDao.computeSaleCostCents(sale.id);
        if (costCents > 0) {
          await _journalService.recordSaleCOGSJournalEntry(
            saleId: sale.id,
            costCents: costCents,
            currencyId: sale.currencyId,
          );
        }
        report.salesReplayed++;
      } catch (e) {
        report.errors.add('Sale #${sale.id}: $e');
        developer.log(
          'Error replaying sale #${sale.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.salesReplayed} sales',
      name: 'LedgerRebuild',
    );
  }

  /// Phase 3b: Replay all posted (non-voided) purchases
  Future<void> _replayPurchases(LedgerRebuildReport report) async {
    final purchases = await (_db.select(
      _db.purchases,
    )..where((p) => p.status.equals('posted'))).get();

    for (final purchase in purchases) {
      try {
        final totalCents = purchase.totalCents.toBigInt().toInt();
        final paidCents = purchase.paidAmountCents.toBigInt().toInt();
        final taxCents = purchase.taxCents.toBigInt().toInt();
        final inventoryNetCents = await _db.purchaseDao
            .computePurchaseInventoryNetCents(purchase.id);

        await _journalService.recordPurchaseJournalEntry(
          purchaseId: purchase.id,
          totalCents: totalCents,
          paidAmountCents: paidCents,
          currencyId: purchase.currencyId,
          taxCents: taxCents,
          inventoryNetCents: inventoryNetCents,
          paymentMethod: purchase.paymentMethod,
        );
        final actualInventoryValue = await _db.purchaseDao
            .computePurchaseInventoryValueAtPostCents(purchase.id);
        final roundingDelta = actualInventoryValue - inventoryNetCents;
        if (roundingDelta != 0) {
          await _journalService.recordInventoryRoundingJournalEntry(
            sourceTable: 'purchases',
            sourceId: purchase.id,
            deltaValueCents: roundingDelta,
            currencyId: purchase.currencyId,
            reason: 'Purchase ${purchase.purchaseNumber} rebuild',
          );
        }
        report.purchasesReplayed++;
      } catch (e) {
        report.errors.add('Purchase #${purchase.id}: $e');
        developer.log(
          'Error replaying purchase #${purchase.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.purchasesReplayed} purchases',
      name: 'LedgerRebuild',
    );
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
        developer.log(
          'Error replaying expense #${expense.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.expensesReplayed} expenses',
      name: 'LedgerRebuild',
    );
  }

  /// Phase 3d: Replay all posted sale returns
  Future<void> _replaySaleReturns(LedgerRebuildReport report) async {
    final returns = await (_db.select(
      _db.saleReturns,
    )..where((r) => r.status.equals('posted'))).get();

    for (final ret in returns) {
      try {
        final totalCents = ret.totalCents.toBigInt().toInt();
        final taxCents = ret.taxCents.toBigInt().toInt();

        // Resolve partyId (customer_id) from the parent sale so the policy
        // can satisfy the credit-refund defense-in-depth check.
        final saleRow = await (_db.select(
          _db.sales,
        )..where((s) => s.id.equals(ret.saleId))).getSingleOrNull();
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
        // Use the same source as live posting. For FIFO this is the exact
        // value of the batch layers restored by this return; for WAC it is
        // the frozen return / original-sale cost. Besides preventing blended
        // unit-cost rounding drift, this removes the stale SQL reference to
        // the non-existent legacy `sale_return_items.unit_cost_cents` column.
        final returnCostCents = await _db.saleDao.computeSaleReturnCostCents(
          ret.id,
        );
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
        developer.log(
          'Error replaying sale return #${ret.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.saleReturnsReplayed} sale returns',
      name: 'LedgerRebuild',
    );
  }

  /// Phase 3e: Replay all posted purchase returns
  Future<void> _replayPurchaseReturns(LedgerRebuildReport report) async {
    final returns = await (_db.select(
      _db.purchaseReturns,
    )..where((r) => r.status.equals('posted'))).get();

    for (final ret in returns) {
      try {
        final totalCents = ret.totalCents.toBigInt().toInt();
        final taxCents = ret.taxCents.toBigInt().toInt();

        // Inventory leg = ACTUAL valuation removed by the stock ledger
        // (FIFO batch consumption / WAC current cost), the same single
        // source of truth used at post time. Replaying with the refund net
        // (the old default) would re-introduce the 1200 vs Σ(stock×cost)
        // drift on every rebuild for FIFO/price-variance lines.
        final inventoryCostCents = await _db.purchaseDao
            .computePurchaseReturnInventoryCostCents(ret.id);

        await _journalService.recordPurchaseReturnJournalEntry(
          returnId: ret.id,
          totalCents: totalCents,
          taxCents: taxCents,
          inventoryCostCents: inventoryCostCents,
          currencyId: ret.currencyId,
          refundMethod: ret.refundMethod,
        );
        report.purchaseReturnsReplayed++;
      } catch (e) {
        report.errors.add('Purchase Return #${ret.id}: $e');
        developer.log(
          'Error replaying purchase return #${ret.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.purchaseReturnsReplayed} purchase returns',
      name: 'LedgerRebuild',
    );
  }

  /// Per-product costing info needed to value a replayed return line the same
  /// way the post path does. Mirrors `PurchaseDao._isFifoProduct` and the
  /// `track_inventory` gate.
  Future<({bool tracks, bool fifo})> _costingInfo(int productId) async {
    final row = await _db
        .customSelect(
          'SELECT track_inventory, inventory_tracking_type, costing_method '
          'FROM products WHERE id = ?',
          variables: [Variable.withInt(productId)],
        )
        .getSingleOrNull();
    if (row == null) return (tracks: true, fifo: false);
    final tracks = (row.read<int?>('track_inventory') ?? 1) == 1;
    final tracking = row.read<String?>('inventory_tracking_type');
    final fifo =
        tracking == 'batch' ||
        tracking == 'batch_expiry' ||
        (row.read<String?>('costing_method') ?? 'wac') == 'fifo';
    return (tracks: tracks, fifo: fifo);
  }

  /// Phase 3e2: Replay posted PURCHASE ADJUSTMENT (unlinked) returns.
  ///
  /// These live in `purchase_return_adjustments` and were previously NEVER
  /// replayed — `_deleteAllJournalEntries` wiped their JE and nothing
  /// recreated it, so every rebuild silently dropped the entire return from
  /// the ledger (inventory + AP/cash + VAT all drifting). We rebuild the JE
  /// from the persisted items, valuing the inventory leg from the SAME single
  /// source of truth used at post time:
  ///   • FIFO → Σ(batch_consumptions.quantity × unit_cost_cents) of the
  ///     'out' rows this return produced (the batch ledger is untouched by a
  ///     rebuild, so those rows still exist).
  ///   • WAC  → frozen unit_cost_cents × qty.
  Future<void> _replayPurchaseAdjustmentReturns(
    LedgerRebuildReport report,
  ) async {
    final returns = await (_db.select(
      _db.purchaseReturnAdjustments,
    )..where((r) => r.status.equals('posted'))).get();

    for (final ret in returns) {
      try {
        final items = await (_db.select(
          _db.purchaseReturnAdjustmentItems,
        )..where((i) => i.returnId.equals(ret.id))).get();

        int totalTax = 0;
        int totalInvCost = 0;
        final explicitLines = <PostedReturnLine>[];
        for (final item in items) {
          final qty = item.quantity;
          final tax = item.taxCents.toBigInt().toInt();
          totalTax += tax;

          final info = await _costingInfo(item.productId);
          int lineInv;
          if (!info.tracks) {
            lineInv = 0;
          } else if (item.inventoryValueAtPostCents != null) {
            lineInv = item.inventoryValueAtPostCents!.toBigInt().toInt();
          } else if (info.fifo) {
            final r = await _db
                .customSelect(
                  'SELECT CAST((COALESCE(SUM(quantity * unit_cost_cents), 0) + ?) / ? AS INTEGER) AS c '
                  'FROM batch_consumptions '
                  'WHERE purchase_return_adjustment_item_id = ? '
                  "AND direction = 'out'",
                  variables: [
                    Variable.withInt(item.quantityScale ~/ 2),
                    Variable.withInt(item.quantityScale),
                    Variable.withInt(item.id),
                  ],
                )
                .getSingle();
            lineInv = r.read<int>('c');
          } else {
            lineInv = MeasuredAmount.cents(
              unitCents: item.unitCostCents.toBigInt().toInt(),
              quantity: qty,
              quantityScale: item.quantityScale,
            );
          }
          totalInvCost += lineInv;

          explicitLines.add(
            PostedReturnLine(
              totalCents: item.totalCents.toBigInt().toInt(),
              taxCents: tax,
              inventoryCostCents: lineInv,
              disposition: ReturnDispositionX.fromWire(item.dispositionType),
              productId: item.productId,
              variantId: item.variantId,
              qty: qty,
            ),
          );
        }

        await _journalService.recordPurchaseAdjustmentReturnJournalEntry(
          returnId: ret.id,
          totalCents: ret.totalCents.toBigInt().toInt(),
          taxCents: totalTax,
          inventoryCostCents: totalInvCost,
          currencyId: ret.currencyId,
          refundMethod: ret.refundMethod,
          supplierId: ret.supplierId,
          explicitLines: explicitLines,
          approvalStatus: ret.approvalStatus,
          approvalReason: ret.approvalReason,
          postingDate: ret.returnDate,
        );
        report.purchaseReturnsReplayed++;
      } catch (e) {
        report.errors.add('Purchase Adj Return #${ret.id}: $e');
        developer.log(
          'Error replaying purchase adj return #${ret.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed posted purchase adjustment returns',
      name: 'LedgerRebuild',
    );
  }

  /// Phase 3d2: Replay posted SALE ADJUSTMENT (unlinked) returns.
  ///
  /// Same rebuild gap as purchase adjustment returns. The inventory leg here
  /// is the value of goods coming BACK into stock — for FIFO a fresh batch is
  /// created at the frozen `unit_cost_cents`, so qty × that frozen cost is the
  /// exact valuation added for BOTH FIFO and WAC (no batch consumption rows
  /// are produced on the way in). Credit-note issuance inside
  /// `ReturnPostingService.post` is idempotent on (source_table, source_id),
  /// so a rebuild never double-issues.
  Future<void> _replaySaleAdjustmentReturns(LedgerRebuildReport report) async {
    final returns = await (_db.select(
      _db.saleReturnAdjustments,
    )..where((r) => r.status.equals('posted'))).get();

    for (final ret in returns) {
      try {
        final items = await (_db.select(
          _db.saleReturnAdjustmentItems,
        )..where((i) => i.returnId.equals(ret.id))).get();

        int totalTax = 0;
        int totalInvCost = 0;
        final explicitLines = <PostedReturnLine>[];
        for (final item in items) {
          final qty = item.quantity;
          final tax = item.taxCents.toBigInt().toInt();
          totalTax += tax;

          final info = await _costingInfo(item.productId);
          final lineInv = !info.tracks
              ? 0
              : item.inventoryValueAtPostCents != null
              ? item.inventoryValueAtPostCents!.toBigInt().toInt()
              : MeasuredAmount.cents(
                  unitCents: item.unitCostCents.toBigInt().toInt(),
                  quantity: qty,
                  quantityScale: item.quantityScale,
                );
          totalInvCost += lineInv;

          explicitLines.add(
            PostedReturnLine(
              totalCents: item.totalCents.toBigInt().toInt(),
              taxCents: tax,
              inventoryCostCents: lineInv,
              disposition: ReturnDispositionX.fromWire(item.dispositionType),
              productId: item.productId,
              variantId: item.variantId,
              qty: qty,
            ),
          );
        }

        await _journalService.recordSaleAdjustmentReturnJournalEntry(
          returnId: ret.id,
          totalCents: ret.totalCents.toBigInt().toInt(),
          taxCents: totalTax,
          inventoryCostCents: totalInvCost,
          currencyId: ret.currencyId,
          refundMethod: ret.refundMethod,
          partyId: ret.customerId,
          explicitLines: explicitLines,
          approvalStatus: ret.approvalStatus,
          approvalReason: ret.approvalReason,
          postingDate: ret.returnDate,
        );
        report.saleReturnsReplayed++;
      } catch (e) {
        report.errors.add('Sale Adj Return #${ret.id}: $e');
        developer.log(
          'Error replaying sale adj return #${ret.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed posted sale adjustment returns',
      name: 'LedgerRebuild',
    );
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
        developer.log(
          'Error replaying sale payment #${payment.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.salePaymentsReplayed} sale payments',
      name: 'LedgerRebuild',
    );
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
        developer.log(
          'Error replaying purchase payment #${payment.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.purchasePaymentsReplayed} purchase payments',
      name: 'LedgerRebuild',
    );
  }

  /// Phase 3h: Replay direct customer transactions (payments & discounts from profile)
  Future<void> _replayDirectCustomerTransactions(
    LedgerRebuildReport report,
  ) async {
    final transactions = await (_db.select(
      _db.customerTransactions,
    )..where((t) => t.transactionType.isIn(['payment', 'discount']))).get();

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
        developer.log(
          'Error replaying customer transaction #${tx.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.directCustomerTransactionsReplayed} direct customer transactions',
      name: 'LedgerRebuild',
    );
  }

  /// Phase 3i: Replay direct supplier transactions (payments & discounts from profile)
  Future<void> _replayDirectSupplierTransactions(
    LedgerRebuildReport report,
  ) async {
    final transactions = await (_db.select(
      _db.supplierTransactions,
    )..where((t) => t.transactionType.isIn(['payment', 'discount']))).get();

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
        developer.log(
          'Error replaying supplier transaction #${tx.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.directSupplierTransactionsReplayed} direct supplier transactions',
      name: 'LedgerRebuild',
    );
  }

  /// Phase 3j: Replay opening balances for customers that have a non-zero
  /// balance_cents but whose opening_balance journal entry was NOT preserved
  /// (i.e. it never existed in the first place).
  Future<void> _replayCustomerOpeningBalances(
    LedgerRebuildReport report,
  ) async {
    final customers = await _db.select(_db.customers).get();

    for (final customer in customers) {
      try {
        final balanceCents = customer.balanceCents.toBigInt().toInt();
        if (balanceCents == 0) continue;

        // Check if an opening_balance journal entry already exists for this customer
        // (it would have been replayed via _replayPreservedEntries)
        final existing =
            await (_db.select(_db.journalEntries)..where(
                  (j) =>
                      j.sourceTable.equals('customers') &
                      j.sourceId.equals(customer.id) &
                      j.entryType.equals('opening_balance'),
                ))
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
        developer.log(
          'Error replaying customer opening balance #${customer.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.customerOpeningBalancesReplayed} customer opening balances',
      name: 'LedgerRebuild',
    );
  }

  /// Phase 3k: Replay opening balances for suppliers that have a non-zero
  /// balance_cents but whose opening_balance journal entry was NOT preserved.
  Future<void> _replaySupplierOpeningBalances(
    LedgerRebuildReport report,
  ) async {
    final suppliers = await _db.select(_db.suppliers).get();

    for (final supplier in suppliers) {
      try {
        final balanceCents = supplier.balanceCents.toBigInt().toInt();
        if (balanceCents == 0) continue;

        // Check if an opening_balance journal entry already exists for this supplier
        final existing =
            await (_db.select(_db.journalEntries)..where(
                  (j) =>
                      j.sourceTable.equals('suppliers') &
                      j.sourceId.equals(supplier.id) &
                      j.entryType.equals('opening_balance'),
                ))
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
        developer.log(
          'Error replaying supplier opening balance #${supplier.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.supplierOpeningBalancesReplayed} supplier opening balances',
      name: 'LedgerRebuild',
    );
  }

  /// Phase 3l: Replay all PAID payrolls as direct expense.
  /// No accrual. No Salaries Payable. Direct: Dr Salaries Expense, Cr Cash/Bank.
  Future<void> _replayPayrolls(LedgerRebuildReport report) async {
    final paidPayrolls = await (_db.select(
      _db.payrolls,
    )..where((p) => p.status.equals('paid'))).get();

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
        developer.log(
          'Error replaying payroll #${payroll.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.payrollsReplayed} payrolls',
      name: 'LedgerRebuild',
    );
  }

  /// Phase 3k: Replay all loyalty point earns.
  /// When points are earned: Dr Discounts Given (5500), Cr Loyalty Points Liability (2300)
  Future<void> _replayLoyaltyEarns(LedgerRebuildReport report) async {
    final earns = await (_db.select(
      _db.loyaltyPointTransactions,
    )..where((t) => t.transactionType.equals('earn'))).get();

    for (final earn in earns) {
      try {
        if (earn.points <= 0) continue;

        // Look up loyalty settings to get point value in cents
        final settings = await (_db.select(
          _db.loyaltySettingsTable,
        )).getSingleOrNull();
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
        developer.log(
          'Error replaying loyalty earn #${earn.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.loyaltyEarnsReplayed} loyalty earns',
      name: 'LedgerRebuild',
    );
  }

  /// Phase 3l: Replay all loyalty reward redemptions
  Future<void> _replayLoyaltyRedemptions(LedgerRebuildReport report) async {
    final redemptions = await _db.select(_db.customerRewardRedemptions).get();

    for (final redemption in redemptions) {
      try {
        // Look up the reward to get its monetary value
        final reward = await (_db.select(
          _db.loyaltyRewards,
        )..where((r) => r.id.equals(redemption.rewardId))).getSingleOrNull();
        if (reward == null ||
            reward.valueCents == null ||
            reward.valueCents! <= 0) {
          continue;
        }

        // Get customer currency
        final customer = await _db.customerDao.getCustomer(
          redemption.customerId,
        );
        final currencyId = customer?.currencyId ?? 1;

        await _journalService.recordLoyaltyRedemptionJournalEntry(
          redemptionId: redemption.id,
          valueCents: reward.valueCents!,
          currencyId: currencyId,
        );
        report.loyaltyRedemptionsReplayed++;
      } catch (e) {
        report.errors.add('Loyalty Redemption #${redemption.id}: $e');
        developer.log(
          'Error replaying loyalty redemption #${redemption.id}: $e',
          name: 'LedgerRebuild',
        );
      }
    }

    developer.log(
      'Replayed ${report.loyaltyRedemptionsReplayed} loyalty redemptions',
      name: 'LedgerRebuild',
    );
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
        developer.log(
          'Error replaying manual entry: $e',
          name: 'LedgerRebuild',
        );
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
  int consignmentJournalEntriesRetained = 0;
  int consignmentJournalLinesRetained = 0;
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
  bool rolledBack = false;
  int totalDebits = 0;
  int totalCredits = 0;
  int durationMs = 0;
  List<String> errors = [];

  bool get isSuccess => !rolledBack && trialBalanceBalanced && errors.isEmpty;

  String get summary =>
      '''
LEDGER REBUILD REPORT
=====================
Duration: ${durationMs}ms
Closed periods temporarily reopened: $periodsReopened
Accounts reset: $accountsReset
Journal entries deleted: $journalEntriesDeleted
Journal lines deleted: $journalLinesDeleted
Consignment journal entries retained: $consignmentJournalEntriesRetained
Consignment journal lines retained: $consignmentJournalLinesRetained
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
  Rolled back: $rolledBack
  Total Debits: $totalDebits
  Total Credits: $totalCredits

Errors: ${errors.isEmpty ? 'NONE' : '\n  ${errors.join('\n  ')}'}

Result: ${isSuccess ? 'SUCCESS ✓' : 'FAILED ✗'}
''';
}

class _LedgerRebuildRollback implements Exception {
  const _LedgerRebuildRollback();
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

  String get summary =>
      '''
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
