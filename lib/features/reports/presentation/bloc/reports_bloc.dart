import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/crashlytics_service.dart';
import '../../../accounting/domain/models/trial_balance.dart';
import '../../../accounting/domain/models/reconciliation_result.dart';
import '../../../accounting/domain/repositories/journal_repository.dart';
import '../../../accounting/domain/services/trial_balance_calculation_service.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class ReportsEvent extends RealtimeEvent {
  const ReportsEvent();
}

class ReportsReconciliationRequested extends ReportsEvent {
  const ReportsReconciliationRequested();
}

class ReportsDateRangeChanged extends ReportsEvent {
  final ReportDateRange dateRange;
  const ReportsDateRangeChanged(this.dateRange);
}

// ==================== DATA ====================

class ReportsData {
  /// Cumulative balances from inception through the selected end date.
  final TrialBalance trialBalance;

  /// Activity inside the selected period only (used by Profit & Loss).
  final TrialBalance periodTrialBalance;
  final ReconciliationResult? reconciliation;
  final ReportDateRange dateRange;

  const ReportsData({
    required this.trialBalance,
    required this.periodTrialBalance,
    this.reconciliation,
    required this.dateRange,
  });

  bool get isHealthy =>
      trialBalance.isBalanced &&
      (reconciliation == null || reconciliation!.isHealthy);

  int get issueCount => reconciliation?.issues.length ?? 0;

  ReportsData copyWith({
    TrialBalance? trialBalance,
    TrialBalance? periodTrialBalance,
    ReconciliationResult? reconciliation,
    ReportDateRange? dateRange,
  }) {
    return ReportsData(
      trialBalance: trialBalance ?? this.trialBalance,
      periodTrialBalance: periodTrialBalance ?? this.periodTrialBalance,
      reconciliation: reconciliation ?? this.reconciliation,
      dateRange: dateRange ?? this.dateRange,
    );
  }
}

// ==================== BLOC ====================

/// SINGLE SOURCE OF TRUTH: journal_lines table.
///
/// Trial balance and all financial reports are derived EXCLUSIVELY from
/// posted journal_entry_lines. Never from cached accounts.balance_cents.
///
/// NO direct queries to sales, purchases, expenses, or inventory tables.
class ReportsBloc extends RealtimeBloc<ReportsData, ReportsEvent> {
  final JournalRepository _repository;
  final AppDatabase _db;
  ReportDateRange _dateRange;

  ReportsBloc(this._repository, this._db, {String defaultDateRange = 'month'})
    : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
      super(const RealtimeLoading()) {
    CrashlyticsService.instance.logAction('report_opened', {
      'date_range': defaultDateRange,
    });
  }

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<ReportsData> get dataStream {
    // Reports depend on account metadata, posted entry headers and their lines.
    // Watching all three makes a newly posted/voided journal entry refresh the
    // screen immediately even when the cached account row is unchanged.
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.accounts, _db.journalEntries, _db.journalEntryLines},
        )
        .watch()
        .asyncMap((_) => _loadFromLedger());
  }

  @override
  void registerEventHandlers() {
    on<ReportsReconciliationRequested>(_onReconciliationRequested);
    on<ReportsDateRangeChanged>(_onDateRangeChanged);
  }

  Future<void> _onDateRangeChanged(
    ReportsDateRangeChanged event,
    Emitter<RealtimeState<ReportsData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onReconciliationRequested(
    ReportsReconciliationRequested event,
    Emitter<RealtimeState<ReportsData>> emit,
  ) async {
    try {
      final reconciliation = await _repository.reconcileBalances();
      final current = currentData;
      if (current != null) {
        emit(
          RealtimeSuccess<ReportsData>(
            data: current.copyWith(reconciliation: reconciliation),
          ),
        );
      }
    } catch (e, st) {
      emit(
        RealtimeError<ReportsData>(
          error: e,
          stackTrace: st,
          previousData: currentData,
        ),
      );
    }
  }

  /// Load trial balance from journal_lines (single source of truth).
  /// It does NOT query sales, purchases, expenses, or inventory tables.
  Future<ReportsData> _loadFromLedger() async {
    final start = _dateRange.startDate;
    final end = _dateRange.endDate;
    final endExclusive = DateTime(
      end.year,
      end.month,
      end.day,
    ).add(const Duration(days: 1));
    final endInclusive = endExclusive.subtract(const Duration(microseconds: 1));

    // Trial balance and balance sheet are cumulative "as of" reports.
    final trialBalance = await _repository.getTrialBalance(
      asOfDate: endInclusive,
    );

    // Profit & Loss is a period-activity report, so calculate it from only the
    // posted journal lines inside [start, endExclusive).
    final accounts =
        await (_db.select(_db.accounts)
              ..where((a) => a.isActive.equals(true))
              ..orderBy([(a) => OrderingTerm(expression: a.accountCode)]))
            .get();
    final query = _db.select(_db.journalEntryLines).join([
      innerJoin(
        _db.journalEntries,
        _db.journalEntries.id.equalsExp(_db.journalEntryLines.journalEntryId),
      ),
    ]);
    query.where(
      _db.journalEntries.status.equals('posted') &
          _db.journalEntries.entryDate.isBiggerOrEqualValue(start) &
          _db.journalEntries.entryDate.isSmallerThanValue(endExclusive),
    );
    final rows = await query.get();
    final periodTrialBalance = TrialBalanceCalculationService.calculate(
      accounts: accounts,
      lines: rows.map((row) => row.readTable(_db.journalEntryLines)),
      asOfDate: endInclusive,
    );

    return ReportsData(
      trialBalance: trialBalance,
      periodTrialBalance: periodTrialBalance,
      reconciliation: currentData?.reconciliation,
      dateRange: _dateRange,
    );
  }
}
