import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/employee_repository.dart';

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
    this.isLoading = true,
    this.error,
  });

  int get presentCount => attendanceCounts['present'] ?? 0;
  int get lateCount => attendanceCounts['late'] ?? 0;
  int get absentCount => attendanceCounts['absent'] ?? 0;
  int get leaveCount => attendanceCounts['leave'] ?? 0;
  int get totalAttendanceDays =>
      presentCount + lateCount + absentCount + leaveCount;

  int get totalCommissionCents {
    int total = 0;
    for (final c in commissions) {
      total += c.commissionAmountCents.toBigInt().toInt();
    }
    return total;
  }

  Payroll? get latestPayroll => payrolls.isNotEmpty ? payrolls.first : null;

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
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// ==================== BLOC ====================

class EmployeeDetailBloc
    extends Bloc<EmployeeDetailEvent, EmployeeDetailState> {
  final EmployeeRepository _repository;

  StreamSubscription<Employee?>? _employeeSub;
  StreamSubscription<List<Attendance>>? _attendanceSub;
  StreamSubscription<List<Payroll>>? _payrollSub;
  StreamSubscription<List<LeaveRequest>>? _leaveSub;
  StreamSubscription<List<Commission>>? _commissionSub;

  EmployeeDetailBloc(this._repository)
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

  void _subscribePeriodData(int employeeId, String period) {
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
        .watchEmployeeCommissions(employeeId)
        .listen(
          (data) => add(_CommissionDataReceived(data)),
          onError: (_) {},
        );
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
