import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/employee_dao.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/repositories/employee_repository.dart';
import '../../domain/services/payroll_calculation_service.dart';

// ==================== EVENTS ====================

abstract class EmployeeDetailEvent {
  const EmployeeDetailEvent();
}

class EmployeeDetailInitialized extends EmployeeDetailEvent {
  final int employeeId;

  const EmployeeDetailInitialized(this.employeeId);
}

class EmployeeDetailPeriodChanged extends EmployeeDetailEvent {
  final String period;

  const EmployeeDetailPeriodChanged(this.period);
}

class _EmployeeDataReceived extends EmployeeDetailEvent {
  final Employee employee;

  const _EmployeeDataReceived(this.employee);
}

class _AttendanceDataReceived extends EmployeeDetailEvent {
  final List<Attendance> attendances;

  const _AttendanceDataReceived(this.attendances);
}

class _PayrollDataReceived extends EmployeeDetailEvent {
  final List<Payroll> payrolls;

  const _PayrollDataReceived(this.payrolls);
}

class _LeaveDataReceived extends EmployeeDetailEvent {
  final List<LeaveRequest> leaveRequests;

  const _LeaveDataReceived(this.leaveRequests);
}

class _CommissionDataReceived extends EmployeeDetailEvent {
  final List<Commission> commissions;

  const _CommissionDataReceived(this.commissions);
}

class _SalesStatsReceived extends EmployeeDetailEvent {
  final Map<String, int> stats;

  const _SalesStatsReceived(this.stats);
}

class EmployeeDetailSettleAccount extends EmployeeDetailEvent {
  const EmployeeDetailSettleAccount();
}

class EmployeeDetailDeleteEmployee extends EmployeeDetailEvent {
  const EmployeeDetailDeleteEmployee();
}

// ==================== STATE ====================

class EmployeeDetailState {
  final int employeeId;
  final String period;
  final Employee? employee;
  final Role? role;
  final List<Attendance> attendances;
  final List<Payroll> payrolls;
  final List<LeaveRequest> leaveRequests;
  final List<Commission> commissions;
  final Map<String, int> attendanceCounts;
  // Sales statistics for the period
  final int salesCount;
  final int salesTotalCents;
  final int returnsCount;
  final int returnsTotalCents;
  final bool isLoading;
  final String? error;

  const EmployeeDetailState({
    required this.employeeId,
    required this.period,
    this.employee,
    this.role,
    this.attendances = const [],
    this.payrolls = const [],
    this.leaveRequests = const [],
    this.commissions = const [],
    this.attendanceCounts = const {},
    this.salesCount = 0,
    this.salesTotalCents = 0,
    this.returnsCount = 0,
    this.returnsTotalCents = 0,
    this.isLoading = true,
    this.error,
  });

  int get presentCount => attendanceCounts['present'] ?? 0;
  int get lateCount => attendanceCounts['late'] ?? 0;
  int get absentCount => attendanceCounts['absent'] ?? 0;
  int get leaveCount => attendanceCounts['leave'] ?? 0;
  int get totalAttendanceDays =>
      presentCount + lateCount + absentCount + leaveCount;

  /// Total commission earned (positive entries only)
  int get earnedCommissionCents {
    int total = 0;
    for (final c in commissions) {
      final amt = c.commissionAmountCents.toBigInt().toInt();
      if (amt > 0) total += amt;
    }
    return total;
  }

  /// Total commission deducted from returns (negative entries, returned as positive)
  int get deductedCommissionCents {
    int total = 0;
    for (final c in commissions) {
      final amt = c.commissionAmountCents.toBigInt().toInt();
      if (amt < 0) total += amt.abs();
    }
    return total;
  }

  /// Net commission = earned - deducted
  int get totalCommissionCents => earnedCommissionCents - deductedCommissionCents;

  Payroll? get latestPayroll => payrolls.isNotEmpty ? payrolls.first : null;

  /// Find the payroll record for the current period
  Payroll? get periodPayroll {
    for (final p in payrolls) {
      final pStart = p.periodStart;
      final pPeriod = '${pStart.year}-${pStart.month.toString().padLeft(2, '0')}';
      if (pPeriod == period) return p;
    }
    return null;
  }

  /// Whether the current period already has a paid payroll
  bool get isPeriodSettled {
    final p = periodPayroll;
    return p != null && p.status == 'paid';
  }

  EmployeeDetailState copyWith({
    int? employeeId,
    String? period,
    Employee? employee,
    Role? role,
    List<Attendance>? attendances,
    List<Payroll>? payrolls,
    List<LeaveRequest>? leaveRequests,
    List<Commission>? commissions,
    Map<String, int>? attendanceCounts,
    int? salesCount,
    int? salesTotalCents,
    int? returnsCount,
    int? returnsTotalCents,
    bool? isLoading,
    String? error,
  }) {
    return EmployeeDetailState(
      employeeId: employeeId ?? this.employeeId,
      period: period ?? this.period,
      employee: employee ?? this.employee,
      role: role ?? this.role,
      attendances: attendances ?? this.attendances,
      payrolls: payrolls ?? this.payrolls,
      leaveRequests: leaveRequests ?? this.leaveRequests,
      commissions: commissions ?? this.commissions,
      attendanceCounts: attendanceCounts ?? this.attendanceCounts,
      salesCount: salesCount ?? this.salesCount,
      salesTotalCents: salesTotalCents ?? this.salesTotalCents,
      returnsCount: returnsCount ?? this.returnsCount,
      returnsTotalCents: returnsTotalCents ?? this.returnsTotalCents,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ==================== BLOC ====================

class EmployeeDetailBloc
    extends Bloc<EmployeeDetailEvent, EmployeeDetailState> {
  final EmployeeRepository _repository;
  final EmployeeDao _employeeDao;

  StreamSubscription<Employee?>? _employeeSub;
  StreamSubscription<List<Attendance>>? _attendanceSub;
  StreamSubscription<List<Payroll>>? _payrollSub;
  StreamSubscription<List<LeaveRequest>>? _leaveSub;
  StreamSubscription<List<Commission>>? _commissionSub;

  EmployeeDetailBloc(this._repository, this._employeeDao)
      : super(EmployeeDetailState(
          employeeId: 0,
          period: _currentPeriod(),
        )) {
    on<EmployeeDetailInitialized>(_onInitialized);
    on<EmployeeDetailPeriodChanged>(_onPeriodChanged);
    on<_EmployeeDataReceived>(_onEmployeeDataReceived);
    on<_AttendanceDataReceived>(_onAttendanceDataReceived);
    on<_PayrollDataReceived>(_onPayrollDataReceived);
    on<_LeaveDataReceived>(_onLeaveDataReceived);
    on<_CommissionDataReceived>(_onCommissionDataReceived);
    on<_SalesStatsReceived>(_onSalesStatsReceived);
    on<EmployeeDetailSettleAccount>(_onSettleAccount);
    on<EmployeeDetailDeleteEmployee>(_onDeleteEmployee);
  }

  static String _currentPeriod() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  void _onInitialized(
    EmployeeDetailInitialized event,
    Emitter<EmployeeDetailState> emit,
  ) {
    emit(state.copyWith(
      employeeId: event.employeeId,
      isLoading: true,
    ));
    _subscribeAll(event.employeeId, state.period);
  }

  void _onPeriodChanged(
    EmployeeDetailPeriodChanged event,
    Emitter<EmployeeDetailState> emit,
  ) {
    emit(state.copyWith(period: event.period, isLoading: true));
    _subscribePeriodData(state.employeeId, event.period);
  }

  void _subscribeAll(int employeeId, String period) {
    _cancelAll();

    _employeeSub = _repository.watchEmployee(employeeId).listen(
      (employee) {
        if (employee != null) {
          add(_EmployeeDataReceived(employee));
        }
      },
      onError: (_) {},
    );

    _subscribePeriodData(employeeId, period);
  }

  void _subscribePeriodData(int employeeId, String period) async {
    _attendanceSub?.cancel();
    _payrollSub?.cancel();
    _leaveSub?.cancel();
    _commissionSub?.cancel();

    final parts = period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final periodStart = DateTime(year, month, 1);
    final periodEnd = DateTime(year, month + 1, 0, 23, 59, 59);

    _attendanceSub = _repository
        .watchEmployeeAttendance(
          employeeId,
          startDate: periodStart,
          endDate: periodEnd,
        )
        .listen(
          (data) => add(_AttendanceDataReceived(data)),
          onError: (_) {},
        );

    _payrollSub = _repository.watchEmployeePayrolls(employeeId).listen(
      (data) => add(_PayrollDataReceived(data)),
      onError: (_) {},
    );

    _leaveSub = _repository
        .watchEmployeeLeaveRequests(employeeId)
        .listen(
          (data) => add(_LeaveDataReceived(data)),
          onError: (_) {},
        );

    _commissionSub = _repository
        .watchCommissionsByPeriod(period)
        .listen(
          (data) {
            // Filter to only this employee's commissions
            final filtered = data.where((c) => c.employeeId == employeeId).toList();
            add(_CommissionDataReceived(filtered));
          },
          onError: (_) {},
        );

    // Load sales statistics for this period
    _loadSalesStats(employeeId, period);
  }

  Future<void> _loadSalesStats(int employeeId, String period) async {
    try {
      final parts = period.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final periodStart = DateTime(year, month, 1);
      final periodEnd = DateTime(year, month + 1, 0, 23, 59, 59);

      final stats = await _employeeDao.getEmployeeSalesStats(
        employeeId,
        periodStart,
        periodEnd,
      );
      add(_SalesStatsReceived(stats));
    } catch (_) {
      // Non-critical, don't block UI
    }
  }

  Future<void> _onEmployeeDataReceived(
    _EmployeeDataReceived event,
    Emitter<EmployeeDetailState> emit,
  ) async {
    Role? role;
    if (event.employee.roleId != null) {
      role = await _repository.getRole(event.employee.roleId!);
    }
    emit(state.copyWith(
      employee: event.employee,
      role: role,
      isLoading: false,
    ));
  }

  void _onAttendanceDataReceived(
    _AttendanceDataReceived event,
    Emitter<EmployeeDetailState> emit,
  ) {
    final counts = <String, int>{
      'present': 0,
      'late': 0,
      'absent': 0,
      'leave': 0,
      'early_departure': 0,
    };
    for (final a in event.attendances) {
      counts[a.status] = (counts[a.status] ?? 0) + 1;
    }
    emit(state.copyWith(
      attendances: event.attendances,
      attendanceCounts: counts,
      isLoading: false,
    ));
  }

  void _onPayrollDataReceived(
    _PayrollDataReceived event,
    Emitter<EmployeeDetailState> emit,
  ) {
    emit(state.copyWith(payrolls: event.payrolls, isLoading: false));
  }

  void _onLeaveDataReceived(
    _LeaveDataReceived event,
    Emitter<EmployeeDetailState> emit,
  ) {
    emit(state.copyWith(leaveRequests: event.leaveRequests, isLoading: false));
  }

  void _onCommissionDataReceived(
    _CommissionDataReceived event,
    Emitter<EmployeeDetailState> emit,
  ) {
    emit(state.copyWith(commissions: event.commissions, isLoading: false));
  }

  void _onSalesStatsReceived(
    _SalesStatsReceived event,
    Emitter<EmployeeDetailState> emit,
  ) {
    emit(state.copyWith(
      salesCount: event.stats['salesCount'] ?? 0,
      salesTotalCents: event.stats['salesTotalCents'] ?? 0,
      returnsCount: event.stats['returnsCount'] ?? 0,
      returnsTotalCents: event.stats['returnsTotalCents'] ?? 0,
      isLoading: false,
    ));
  }

  Future<void> _onSettleAccount(
    EmployeeDetailSettleAccount event,
    Emitter<EmployeeDetailState> emit,
  ) async {
    final employee = state.employee;
    if (employee == null) return;

    // Prevent duplicate settlement
    if (state.isPeriodSettled) return;

    try {
      emit(state.copyWith(isLoading: true));

      final parts = state.period.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final periodStart = DateTime(year, month, 1);
      final periodEnd = DateTime(year, month + 1, 0, 23, 59, 59);

      // Calculate payroll
      final netSalesCents = state.salesTotalCents - state.returnsTotalCents;
      final targetBonus = PayrollCalculationService.checkSalesTargetBonus(
        employee: employee,
        actualSalesCents: netSalesCents,
      );
      final payroll = state.latestPayroll;
      final manualBonus = payroll?.bonusCents.toBigInt().toInt() ?? 0;
      final overtime = payroll?.overtimeCents.toBigInt().toInt() ?? 0;
      final totalBonus = manualBonus + targetBonus.targetBonusCents;

      final calc = PayrollCalculationService.calculate(
        employee: employee,
        attendanceCounts: state.attendanceCounts,
        commissionCents: state.totalCommissionCents,
        bonusCents: totalBonus,
        overtimeCents: overtime,
      );

      // Create payroll and mark as paid
      final payrollId = await _repository.createPayroll(
        employeeId: employee.id,
        periodStart: periodStart,
        periodEnd: periodEnd,
        basicSalaryCents: calc.basicSalaryCents,
        commissionCents: calc.commissionCents,
        bonusCents: calc.bonusCents,
        overtimeCents: calc.overtimeCents,
        deductionCents: calc.totalDeductionCents,
        netPayCents: calc.netPayCents,
        currencyId: employee.currencyId,
      );

      await _repository.updatePayrollStatus(
        id: payrollId,
        status: PayrollStatus.paid,
        processedAt: DateTime.now(),
      );

      emit(state.copyWith(isLoading: false, error: null));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onDeleteEmployee(
    EmployeeDetailDeleteEmployee event,
    Emitter<EmployeeDetailState> emit,
  ) async {
    final employee = state.employee;
    if (employee == null) return;

    try {
      emit(state.copyWith(isLoading: true));
      await _repository.deleteEmployee(employee.id);
      // State will be handled by the UI (pop navigation)
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _cancelAll() {
    _employeeSub?.cancel();
    _attendanceSub?.cancel();
    _payrollSub?.cancel();
    _leaveSub?.cancel();
    _commissionSub?.cancel();
  }

  @override
  Future<void> close() async {
    _cancelAll();
    return super.close();
  }
}
