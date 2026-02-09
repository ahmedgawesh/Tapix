import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
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

class ReportsBloc extends RealtimeBloc<ReportsData, ReportsEvent> {
  final JournalRepository _repository;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();

  /// Cached account list for computing trial balance from lines
  List<Account> _accountsCache = [];
  StreamSubscription<List<Account>>? _accountsCacheSub;

  ReportsBloc(this._repository) : super(const RealtimeLoading()) {
    // Keep a live cache of accounts for name/type lookups
    _accountsCacheSub = _repository.watchAllAccounts().listen((accounts) {
      _accountsCache = accounts;
    });
  }

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<ReportsData> get dataStream {
    // Watch posted journal entry lines within the selected date range
    return _repository
        .watchPostedLinesByDateRange(_dateRange.startDate, _dateRange.endDate)
        .map((lines) => _computeFromLines(lines));
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
    // Re-subscribe to the new date range stream
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

  /// Compute trial balance from journal entry lines (date-range filtered).
  /// Aggregates debit/credit per account from the lines.
  ReportsData _computeFromLines(List<JournalEntryLine> lines) {
    // Build a map: accountId -> {totalDebit, totalCredit}
    final accountTotals = <int, _AccountTotal>{};

    for (final line in lines) {
      final debit = line.debitCents.toBigInt().toInt();
      final credit = line.creditCents.toBigInt().toInt();
      final existing = accountTotals[line.accountId];
      if (existing != null) {
        existing.totalDebit += debit;
        existing.totalCredit += credit;
      } else {
        accountTotals[line.accountId] = _AccountTotal(
          totalDebit: debit,
          totalCredit: credit,
        );
      }
    }

    // Build account lookup from cache
    final accountMap = <int, Account>{};
    for (final a in _accountsCache) {
      accountMap[a.id] = a;
    }

    int totalDebits = 0;
    int totalCredits = 0;
    final items = <TrialBalanceItem>[];

    for (final entry in accountTotals.entries) {
      final accountId = entry.key;
      final totals = entry.value;
      final account = accountMap[accountId];

      final accountCode = account?.accountCode ?? '???';
      final accountName = account?.accountName ?? 'Unknown';
      final accountType = account?.accountType ?? 'asset';

      // Compute net balance and assign to debit/credit column
      final net = totals.totalDebit - totals.totalCredit;
      int debit = 0;
      int credit = 0;

      final type = accountType.toLowerCase();
      if (type == 'asset' || type == 'expense') {
        if (net >= 0) {
          debit = net;
        } else {
          credit = -net;
        }
      } else {
        if (net <= 0) {
          credit = -net;
        } else {
          debit = net;
        }
      }

      totalDebits += debit;
      totalCredits += credit;

      items.add(TrialBalanceItem(
        accountId: accountId,
        accountCode: accountCode,
        accountName: accountName,
        accountType: accountType,
        debitCents: debit,
        creditCents: credit,
      ));
    }

    // Sort by account code
    items.sort((a, b) => a.accountCode.compareTo(b.accountCode));

    final trialBalance = TrialBalance(
      asOfDate: _dateRange.endDate,
      items: items,
      totalDebitCents: totalDebits,
      totalCreditCents: totalCredits,
      isBalanced: totalDebits == totalCredits,
    );

    final existingReconciliation = currentData?.reconciliation;

    return ReportsData(
      trialBalance: trialBalance,
      reconciliation: existingReconciliation,
      dateRange: _dateRange,
    );
  }

  @override
  Future<void> close() {
    _accountsCacheSub?.cancel();
    return super.close();
  }
}

class _AccountTotal {
  int totalDebit;
  int totalCredit;

  _AccountTotal({required this.totalDebit, required this.totalCredit});
}
