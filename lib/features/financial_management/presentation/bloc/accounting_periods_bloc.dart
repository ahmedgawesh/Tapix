import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../accounting/domain/services/accounting_close_service.dart';
import '../../../auth/data/services/session_service.dart';
import '../../../accounting/domain/repositories/journal_repository.dart';

// ── Events ──

abstract class AccountingPeriodsEvent extends RealtimeEvent {
  const AccountingPeriodsEvent();
}

class PeriodCreateRequested extends AccountingPeriodsEvent {
  final String name;
  final DateTime startDate;
  final DateTime endDate;

  const PeriodCreateRequested({
    required this.name,
    required this.startDate,
    required this.endDate,
  });
}

class PeriodCloseRequested extends AccountingPeriodsEvent {
  final int periodId;
  const PeriodCloseRequested({required this.periodId});
}

// ── State Data ──

class AccountingPeriodsData {
  final List<AccountingPeriod> periods;
  const AccountingPeriodsData({required this.periods});
}

// ── Bloc ──

class AccountingPeriodsBloc
    extends RealtimeBloc<AccountingPeriodsData, AccountingPeriodsEvent> {
  final JournalRepository _repository;
  final AppDatabase _db;
  final AuditLogService _audit;
  final AccountingCloseService _closeService;
  final SessionService _sessionService;

  AccountingPeriodsBloc(
    this._repository,
    this._db,
    this._audit,
    this._closeService,
    this._sessionService,
  )
      : super(const RealtimeLoading());

  @override
  Stream<AccountingPeriodsData> get dataStream {
    return _repository.watchAccountingPeriods().map(
          (periods) => AccountingPeriodsData(periods: periods),
        );
  }

  @override
  void registerEventHandlers() {
    on<PeriodCreateRequested>(_onCreateRequested);
    on<PeriodCloseRequested>(_onCloseRequested);
  }

  Future<void> _onCreateRequested(
    PeriodCreateRequested event,
    Emitter<RealtimeState<AccountingPeriodsData>> emit,
  ) async {
    try {
      await (_db.into(_db.accountingPeriods)).insert(
        AccountingPeriodsCompanion.insert(
          periodName: event.name,
          startDate: event.startDate,
          endDate: event.endDate,
        ),
      );
    } catch (e, st) {
      emit(RealtimeError<AccountingPeriodsData>(
        error: e,
        stackTrace: st,
        previousData: currentData,
      ));
    }
  }

  Future<void> _onCloseRequested(
    PeriodCloseRequested event,
    Emitter<RealtimeState<AccountingPeriodsData>> emit,
  ) async {
    try {
      final userId = await _sessionService.getCurrentUserId();
      if (userId == null) {
        throw StateError('Session required to close accounting periods');
      }

      // Get period name before closing for audit
      final periods = await (_db.select(_db.accountingPeriods)
            ..where((p) => p.id.equals(event.periodId)))
          .get();
      final periodName = periods.isNotEmpty ? periods.first.periodName : 'Unknown';

      final result = await _closeService.closePeriod(
        periodId: event.periodId,
        userId: userId,
      );

      if (!result.success) {
        throw StateError(result.errorKey ?? 'Failed to close period');
      }

      // Audit: log period close (CRITICAL)
      _audit.logPeriodClosed(
        periodId: event.periodId,
        periodName: periodName,
        userId: userId,
      );
    } catch (e, st) {
      emit(RealtimeError<AccountingPeriodsData>(
        error: e,
        stackTrace: st,
        previousData: currentData,
      ));
    }
  }
}
