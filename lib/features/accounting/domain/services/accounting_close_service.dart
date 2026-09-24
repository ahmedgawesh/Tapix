import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../data/repositories/accounting_repository.dart';
import '../services/trial_balance_calculation_service.dart';

/// Result of pre-close validation
class PeriodCloseValidation {
  final bool canClose;
  final List<PeriodCloseBlocker> blockers;
  final List<PeriodCloseWarning> warnings;
  final PeriodCloseSummary? summary;

  const PeriodCloseValidation({
    required this.canClose,
    required this.blockers,
    required this.warnings,
    this.summary,
  });
}

class PeriodCloseBlocker {
  /// Translation key for the blocker reason
  final String reasonKey;

  /// Optional args for the translation
  final List<String> args;

  const PeriodCloseBlocker({required this.reasonKey, this.args = const []});
}

class PeriodCloseWarning {
  /// Translation key for the warning
  final String warningKey;

  /// Optional args for the translation
  final List<String> args;

  const PeriodCloseWarning({required this.warningKey, this.args = const []});
}

class PeriodCloseSummary {
  final int totalRevenueCents;
  final int totalExpensesCents;
  final int netIncomeCents;
  final int retainedEarningsTransferCents;
  final String periodName;
  final DateTime startDate;
  final DateTime endDate;

  const PeriodCloseSummary({
    required this.totalRevenueCents,
    required this.totalExpensesCents,
    required this.netIncomeCents,
    required this.retainedEarningsTransferCents,
    required this.periodName,
    required this.startDate,
    required this.endDate,
  });
}

/// Result of period close execution
class PeriodCloseResult {
  final bool success;
  final int? closingJournalEntryId;
  final String? errorKey;

  const PeriodCloseResult({
    required this.success,
    this.closingJournalEntryId,
    this.errorKey,
  });
}

/// Accounting Close Service
///
/// Implements strict rules for when a period can be closed:
///
/// BLOCKING CONDITIONS (must all pass):
/// 1. Period must exist and be open
/// 2. Trial balance must be balanced (debits = credits)
/// 3. No draft journal entries in the period
/// 4. No unposted transactions in the period
/// 5. Period end date must be in the past (can't close future periods)
///
/// WARNINGS (non-blocking):
/// 1. Negative equity after close
/// 2. Zero revenue (empty period)
/// 3. Net loss for the period
///
/// CLOSE ACTIONS:
/// 1. Mark period as closed with timestamp and user
/// No closing journal entries. No retained earnings transfer.
class AccountingCloseService {
  final AppDatabase _db;
  final AccountingRepository _accountingRepo;

  AccountingCloseService(this._db, this._accountingRepo);

  /// Validate whether a period can be closed
  /// Returns blockers (hard stops) and warnings (informational)
  Future<PeriodCloseValidation> validatePeriodClose(int periodId) async {
    final blockers = <PeriodCloseBlocker>[];
    final warnings = <PeriodCloseWarning>[];

    // ── Check 1: Period exists and is open ──
    final period = await (_db.select(
      _db.accountingPeriods,
    )..where((p) => p.id.equals(periodId))).getSingleOrNull();

    if (period == null) {
      blockers.add(
        const PeriodCloseBlocker(
          reasonKey: 'reports.close_blocker_period_not_found',
        ),
      );
      return PeriodCloseValidation(
        canClose: false,
        blockers: blockers,
        warnings: warnings,
      );
    }

    if (period.isClosed) {
      blockers.add(
        const PeriodCloseBlocker(
          reasonKey: 'reports.close_blocker_already_closed',
        ),
      );
      return PeriodCloseValidation(
        canClose: false,
        blockers: blockers,
        warnings: warnings,
      );
    }

    final periodStart = DateTime(
      period.startDate.year,
      period.startDate.month,
      period.startDate.day,
    );
    final endExclusive = DateTime(
      period.endDate.year,
      period.endDate.month,
      period.endDate.day,
    ).add(const Duration(days: 1));
    final endInclusive = endExclusive.subtract(const Duration(microseconds: 1));

    // ── Check 2: The complete final day must have elapsed ──
    if (DateTime.now().isBefore(endExclusive)) {
      blockers.add(
        const PeriodCloseBlocker(
          reasonKey: 'reports.close_blocker_future_period',
        ),
      );
    }

    // ── Check 3: Cumulative trial balance at period end must balance ──
    final trialBalance = await _accountingRepo.getTrialBalance(
      asOfDate: endInclusive,
    );
    if (!trialBalance.isBalanced) {
      blockers.add(
        const PeriodCloseBlocker(
          reasonKey: 'reports.close_blocker_trial_unbalanced',
        ),
      );
    }

    // ── Check 4: No draft journal entries in the period ──
    final draftRows = await _db
        .customSelect(
          '''SELECT COUNT(*) AS cnt FROM journal_entries
         WHERE status = 'draft'
           AND entry_date >= ? AND entry_date < ?''',
          variables: [
            Variable.withDateTime(periodStart),
            Variable.withDateTime(endExclusive),
          ],
          readsFrom: {_db.journalEntries},
        )
        .getSingle();
    final draftCount = draftRows.read<int>('cnt');

    if (draftCount > 0) {
      blockers.add(
        PeriodCloseBlocker(
          reasonKey: 'reports.close_blocker_draft_entries',
          args: [draftCount.toString()],
        ),
      );
    }

    // ── Check 5: No unposted operational documents in the period ──
    final unpostedRow = await _db
        .customSelect(
          '''SELECT COALESCE(SUM(cnt), 0) AS cnt FROM (
           SELECT COUNT(*) AS cnt FROM sales
             WHERE status IN ('draft', 'pending')
               AND sale_date >= ? AND sale_date < ?
           UNION ALL
           SELECT COUNT(*) AS cnt FROM purchases
             WHERE status IN ('draft', 'pending')
               AND purchase_date >= ? AND purchase_date < ?
           UNION ALL
           SELECT COUNT(*) AS cnt FROM sale_returns
             WHERE status = 'draft' AND return_date >= ? AND return_date < ?
           UNION ALL
           SELECT COUNT(*) AS cnt FROM purchase_returns
             WHERE status = 'draft' AND return_date >= ? AND return_date < ?
           UNION ALL
           SELECT COUNT(*) AS cnt FROM sale_return_adjustments
             WHERE status = 'draft' AND return_date >= ? AND return_date < ?
           UNION ALL
           SELECT COUNT(*) AS cnt FROM purchase_return_adjustments
             WHERE status = 'draft' AND return_date >= ? AND return_date < ?
         )''',
          variables: List.generate(
            6,
            (_) => [
              Variable.withDateTime(periodStart),
              Variable.withDateTime(endExclusive),
            ],
          ).expand((pair) => pair).toList(),
          readsFrom: {
            _db.sales,
            _db.purchases,
            _db.saleReturns,
            _db.purchaseReturns,
            _db.saleReturnAdjustments,
            _db.purchaseReturnAdjustments,
          },
        )
        .getSingle();
    final unpostedCount = unpostedRow.read<int>('cnt');
    if (unpostedCount > 0) {
      blockers.add(
        PeriodCloseBlocker(
          reasonKey: 'reports.close_blocker_unposted_transactions',
          args: [unpostedCount.toString()],
        ),
      );
    }

    // ── Compute activity only inside this accounting period ──
    final accounts = await (_db.select(
      _db.accounts,
    )..where((account) => account.isActive.equals(true))).get();
    final periodQuery = _db.select(_db.journalEntryLines).join([
      innerJoin(
        _db.journalEntries,
        _db.journalEntries.id.equalsExp(_db.journalEntryLines.journalEntryId),
      ),
    ]);
    periodQuery.where(
      _db.journalEntries.status.equals('posted') &
          _db.journalEntries.entryDate.isBiggerOrEqualValue(periodStart) &
          _db.journalEntries.entryDate.isSmallerThanValue(endExclusive),
    );
    final periodRows = await periodQuery.get();
    final periodTrialBalance = TrialBalanceCalculationService.calculate(
      accounts: accounts,
      lines: periodRows.map((row) => row.readTable(_db.journalEntryLines)),
      asOfDate: endInclusive,
    );
    final totalRevenue = periodTrialBalance.totalForType('revenue');
    final totalExpenses = periodTrialBalance.totalForType('expense');
    final netIncome = totalRevenue - totalExpenses;
    final ownerCapital = trialBalance.totalForType('equity');

    // ── Warning 1: Negative equity after close ──
    if (ownerCapital + netIncome < 0) {
      warnings.add(
        const PeriodCloseWarning(
          warningKey: 'reports.close_warning_negative_equity',
        ),
      );
    }

    // ── Warning 2: Zero revenue ──
    if (totalRevenue == 0) {
      warnings.add(
        const PeriodCloseWarning(
          warningKey: 'reports.close_warning_zero_revenue',
        ),
      );
    }

    // ── Warning 3: Net loss ──
    if (netIncome < 0) {
      warnings.add(
        const PeriodCloseWarning(warningKey: 'reports.close_warning_net_loss'),
      );
    }

    final summary = PeriodCloseSummary(
      totalRevenueCents: totalRevenue,
      totalExpensesCents: totalExpenses,
      netIncomeCents: netIncome,
      retainedEarningsTransferCents: netIncome,
      periodName: period.periodName,
      startDate: period.startDate,
      endDate: period.endDate,
    );

    return PeriodCloseValidation(
      canClose: blockers.isEmpty,
      blockers: blockers,
      warnings: warnings,
      summary: summary,
    );
  }

  /// Execute period close
  ///
  /// Simply marks the period as closed. No closing journal entries.
  /// No retained earnings transfer. Revenue and expense accounts
  /// are NOT zeroed out — they accumulate continuously.
  Future<PeriodCloseResult> closePeriod({
    required int periodId,
    required int userId,
  }) async {
    // Re-validate
    final validation = await validatePeriodClose(periodId);
    if (!validation.canClose) {
      return const PeriodCloseResult(
        success: false,
        errorKey: 'reports.close_error_validation_failed',
      );
    }

    // Mark period as closed — no closing journal entries
    await _accountingRepo.closeAccountingPeriod(
      periodId: periodId,
      userId: userId,
    );

    return const PeriodCloseResult(success: true);
  }
}
