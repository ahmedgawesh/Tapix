import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/repositories/employee_repository.dart';

// ==================== EVENTS ====================

abstract class PayrollEvent extends RealtimeEvent {
  const PayrollEvent();
}

class PayrollInitialized extends PayrollEvent {
  final String period;
  final PayrollStatus? status;

  const PayrollInitialized({
    required this.period,
    this.status,
  });
}

class PayrollPeriodChanged extends PayrollEvent {
  final String period;

  const PayrollPeriodChanged(this.period);
}

class PayrollFilterChanged extends PayrollEvent {
  final PayrollStatus? status;

  const PayrollFilterChanged(this.status);
}

class PayrollCreateRequested extends PayrollEvent {
  final int employeeId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int basicSalaryCents;
  final int commissionCents;
  final int bonusCents;
  final int overtimeCents;
  final int deductionCents;
  final int netPayCents;
  final int currencyId;
  final String? notes;

  const PayrollCreateRequested({
    required this.employeeId,
    required this.periodStart,
    required this.periodEnd,
    required this.basicSalaryCents,
    this.commissionCents = 0,
    this.bonusCents = 0,
    this.overtimeCents = 0,
    this.deductionCents = 0,
    required this.netPayCents,
    required this.currencyId,
    this.notes,
  });
}

class PayrollStatusUpdateRequested extends PayrollEvent {
  final int id;
  final PayrollStatus status;
  final String? bankReference;

  const PayrollStatusUpdateRequested({
    required this.id,
    required this.status,
    this.bankReference,
  });
}

class PayrollDeleteRequested extends PayrollEvent {
  final int id;

  const PayrollDeleteRequested(this.id);
}

// ==================== STATE ====================

class PayrollState {
  final String period;
  final PayrollStatus? statusFilter;
  final List<Payroll> payrolls;
  final PayrollSummary summary;
  final List<String> availablePeriods;
  final bool isLoading;
  final String? error;

  const PayrollState({
    required this.period,
    this.statusFilter,
    this.payrolls = const [],
    this.summary = const PayrollSummary(period: ''),
    this.availablePeriods = const [],
    this.isLoading = true,
    this.error,
  });

  PayrollState copyWith({
    String? period,
    PayrollStatus? statusFilter,
    List<Payroll>? payrolls,
    PayrollSummary? summary,
    List<String>? availablePeriods,
    bool? isLoading,
    String? error,
    bool clearStatusFilter = false,
  }) {
    return PayrollState(
      period: period ?? this.period,
      statusFilter: clearStatusFilter ? null : (statusFilter ?? this.statusFilter),
      payrolls: payrolls ?? this.payrolls,
      summary: summary ?? this.summary,
      availablePeriods: availablePeriods ?? this.availablePeriods,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ==================== BLOC ====================

class PayrollBloc extends Bloc<PayrollEvent, PayrollState> {
  final EmployeeRepository _repository;

  PayrollBloc(this._repository)
      : super(PayrollState(period: _getCurrentPeriod())) {
    on<PayrollInitialized>(_onInitialized);
    on<PayrollPeriodChanged>(_onPeriodChanged);
    on<PayrollFilterChanged>(_onFilterChanged);
    on<PayrollCreateRequested>(_onCreateRequested);
    on<PayrollStatusUpdateRequested>(_onStatusUpdateRequested);
    on<PayrollDeleteRequested>(_onDeleteRequested);
  }

  static String _getCurrentPeriod() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Future<void> _onInitialized(
    PayrollInitialized event,
    Emitter<PayrollState> emit,
  ) async {
    emit(state.copyWith(
      period: event.period,
      statusFilter: event.status,
      isLoading: true,
    ));

    // Load available periods
    final periods = await _repository.getPayrollPeriods();
    emit(state.copyWith(availablePeriods: periods));

    await _subscribeToPayrolls(emit);
  }

  Future<void> _onPeriodChanged(
    PayrollPeriodChanged event,
    Emitter<PayrollState> emit,
  ) async {
    emit(state.copyWith(period: event.period, isLoading: true));
    await _subscribeToPayrolls(emit);
  }

  Future<void> _onFilterChanged(
    PayrollFilterChanged event,
    Emitter<PayrollState> emit,
  ) async {
    emit(state.copyWith(
      statusFilter: event.status,
      clearStatusFilter: event.status == null,
      isLoading: true,
    ));
    await _subscribeToPayrolls(emit);
  }

  Future<void> _subscribeToPayrolls(Emitter<PayrollState> emit) async {
    await emit.forEach(
      _repository.watchPayrollsByPeriod(
        state.period,
        status: state.statusFilter,
      ),
      onData: (payrolls) {
        var totalGross = Decimal.zero;
        var totalDeductions = Decimal.zero;
        var totalNet = Decimal.zero;

        for (final p in payrolls) {
          totalGross += p.basicSalaryCents +
              p.commissionCents +
              p.bonusCents +
              p.overtimeCents;
          totalDeductions += p.deductionCents;
          totalNet += p.netPayCents;
        }

        return state.copyWith(
          payrolls: payrolls,
          summary: PayrollSummary(
            period: state.period,
            totalGrossCents: totalGross.toBigInt().toInt(),
            totalDeductionsCents: totalDeductions.toBigInt().toInt(),
            totalNetCents: totalNet.toBigInt().toInt(),
            employeeCount: payrolls.length,
          ),
          isLoading: false,
          error: null,
        );
      },
      onError: (error, stackTrace) {
        return state.copyWith(
          isLoading: false,
          error: error.toString(),
        );
      },
    );
  }

  Future<void> _onCreateRequested(
    PayrollCreateRequested event,
    Emitter<PayrollState> emit,
  ) async {
    try {
      await _repository.createPayroll(
        employeeId: event.employeeId,
        periodStart: event.periodStart,
        periodEnd: event.periodEnd,
        basicSalaryCents: event.basicSalaryCents,
        commissionCents: event.commissionCents,
        bonusCents: event.bonusCents,
        overtimeCents: event.overtimeCents,
        deductionCents: event.deductionCents,
        netPayCents: event.netPayCents,
        currencyId: event.currencyId,
        notes: event.notes,
      );
      // Stream will automatically update
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onStatusUpdateRequested(
    PayrollStatusUpdateRequested event,
    Emitter<PayrollState> emit,
  ) async {
    try {
      await _repository.updatePayrollStatus(
        id: event.id,
        status: event.status,
        processedAt: event.status == PayrollStatus.processed ||
                event.status == PayrollStatus.paid
            ? DateTime.now()
            : null,
        bankReference: event.bankReference,
      );
      // Stream will automatically update
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onDeleteRequested(
    PayrollDeleteRequested event,
    Emitter<PayrollState> emit,
  ) async {
    try {
      await _repository.deletePayroll(event.id);
      // Stream will automatically update
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }
}
