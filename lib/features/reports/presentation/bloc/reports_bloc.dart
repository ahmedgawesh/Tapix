import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/crashlytics_service.dart';
import '../../../accounting/domain/models/trial_balance.dart';
import '../../../accounting/domain/models/reconciliation_result.dart';
import '../../../accounting/domain/repositories/journal_repository.dart';
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
  final TrialBalance trialBalance;
  final ReconciliationResult? reconciliation;
  final ReportDateRange dateRange;

  const ReportsData({
    required this.trialBalance,
    this.reconciliation,
    required this.dateRange,
  });

  bool get isHealthy =>
      trialBalance.isBalanced &&
      (reconciliation == null || reconciliation!.isHealthy);

  int get issueCount => reconciliation?.issues.length ?? 0;

  ReportsData copyWith({
    TrialBalance? trialBalance,
    ReconciliationResult? reconciliation,
    ReportDateRange? dateRange,
  }) {
    return ReportsData(
      trialBalance: trialBalance ?? this.trialBalance,
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
    // Watch the accounts table — any balance change triggers a re-query.
    // This is the ONLY data source for financial reports.
    return _db.select(_db.accounts).watch().asyncMap((_) => _loadFromLedger());
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
        emit(RealtimeSuccess<ReportsData>(
          data: current.copyWith(reconciliation: reconciliation),
        ));
      }
    } catch (e, st) {
      emit(RealtimeError<ReportsData>(
        error: e,
        stackTrace: st,
        previousData: currentData,
      ));
    }
  }

  /// Load trial balance from journal_lines (single source of truth).
  /// It does NOT query sales, purchases, expenses, or inventory tables.
  Future<ReportsData> _loadFromLedger() async {
    final trialBalance = await _repository.getTrialBalance(
      asOfDate: _dateRange.endDate,
    );

    final existingReconciliation = currentData?.reconciliation;

    return ReportsData(
      trialBalance: trialBalance,
      reconciliation: existingReconciliation,
      dateRange: _dateRange,
    );
  }
}
