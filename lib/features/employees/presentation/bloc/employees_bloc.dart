import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/employee_repository.dart';

// ==================== EVENTS ====================

abstract class EmployeesEvent extends RealtimeEvent {
  const EmployeesEvent();
}

class EmployeesInitialized extends EmployeesEvent {
  final bool? isActive;
  final String? department;
  final int? roleId;

  const EmployeesInitialized({
    this.isActive = true,
    this.department,
    this.roleId,
  });
}

class EmployeeSearchRequested extends EmployeesEvent {
  final String query;

  const EmployeeSearchRequested(this.query);
}

class EmployeeFilterByRoleRequested extends EmployeesEvent {
  final int? roleId;

  const EmployeeFilterByRoleRequested(this.roleId);
}

class EmployeeFilterByDepartmentRequested extends EmployeesEvent {
  final String? department;

  const EmployeeFilterByDepartmentRequested(this.department);
}

class EmployeeCreateRequested extends EmployeesEvent {
  final String name;
  final String? nameAr;
  final String? nameFr;
  final String? employeeCode;
  final int? userId;
  final String? email;
  final String? phone;
  final String? position;
  final String? department;
  final int? roleId;
  final int? managerId;
  final int? salaryCents;
  final int defaultCommissionRateBps;
  final int currencyId;
  final DateTime? hireDate;
  final String? notes;

  const EmployeeCreateRequested({
    required this.name,
    this.nameAr,
    this.nameFr,
    this.employeeCode,
    this.userId,
    this.email,
    this.phone,
    this.position,
    this.department,
    this.roleId,
    this.managerId,
    this.salaryCents,
    this.defaultCommissionRateBps = 0,
    required this.currencyId,
    this.hireDate,
    this.notes,
  });
}

class EmployeeUpdateRequested extends EmployeesEvent {
  final Employee employee;

  const EmployeeUpdateRequested(this.employee);
}

class EmployeeDeleteRequested extends EmployeesEvent {
  final int id;

  const EmployeeDeleteRequested(this.id);
}

// ==================== BLOC ====================

class EmployeesBloc extends RealtimeBloc<List<Employee>, EmployeesEvent> {
  final EmployeeRepository _repository;

  bool? _isActiveFilter = true;
  String? _departmentFilter;
  int? _roleIdFilter;
  String _searchQuery = '';

  EmployeesBloc(this._repository) : super(const RealtimeLoading()) {
    // Stream will be initialized by parent class
  }

  @override
  Stream<List<Employee>> get dataStream => _repository.watchAllEmployees(
        isActive: _isActiveFilter,
        department: _departmentFilter,
        roleId: _roleIdFilter,
      );

  @override
  void registerEventHandlers() {
    on<EmployeesInitialized>(_onInitialized);
    on<EmployeeSearchRequested>(_onSearchRequested);
    on<EmployeeFilterByRoleRequested>(_onFilterByRole);
    on<EmployeeFilterByDepartmentRequested>(_onFilterByDepartment);
    on<EmployeeCreateRequested>(_onCreateRequested);
    on<EmployeeUpdateRequested>(_onUpdateRequested);
    on<EmployeeDeleteRequested>(_onDeleteRequested);
  }

  Future<void> _onInitialized(
    EmployeesInitialized event,
    Emitter<RealtimeState<List<Employee>>> emit,
  ) async {
    _isActiveFilter = event.isActive;
    _departmentFilter = event.department;
    _roleIdFilter = event.roleId;
    refresh();
  }

  Future<void> _onSearchRequested(
    EmployeeSearchRequested event,
    Emitter<RealtimeState<List<Employee>>> emit,
  ) async {
    _searchQuery = event.query;
    if (_searchQuery.isEmpty) {
      refresh();
      return;
    }

    try {
      emit(const RealtimeLoading());
      final results = await _repository.searchEmployees(
        _searchQuery,
        isActive: _isActiveFilter,
      );
      emit(RealtimeSuccess(data: results));
    } catch (e) {
      emit(RealtimeError(error: e));
    }
  }

  Future<void> _onFilterByRole(
    EmployeeFilterByRoleRequested event,
    Emitter<RealtimeState<List<Employee>>> emit,
  ) async {
    _roleIdFilter = event.roleId;
    refresh();
  }

  Future<void> _onFilterByDepartment(
    EmployeeFilterByDepartmentRequested event,
    Emitter<RealtimeState<List<Employee>>> emit,
  ) async {
    _departmentFilter = event.department;
    refresh();
  }

  Future<void> _onCreateRequested(
    EmployeeCreateRequested event,
    Emitter<RealtimeState<List<Employee>>> emit,
  ) async {
    try {
      await _repository.createEmployee(
        name: event.name,
        nameAr: event.nameAr,
        nameFr: event.nameFr,
        employeeCode: event.employeeCode,
        userId: event.userId,
        email: event.email,
        phone: event.phone,
        position: event.position,
        department: event.department,
        roleId: event.roleId,
        managerId: event.managerId,
        salaryCents: event.salaryCents,
        defaultCommissionRateBps: event.defaultCommissionRateBps,
        currencyId: event.currencyId,
        hireDate: event.hireDate,
        notes: event.notes,
      );
      // Stream will automatically update
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  Future<void> _onUpdateRequested(
    EmployeeUpdateRequested event,
    Emitter<RealtimeState<List<Employee>>> emit,
  ) async {
    try {
      await _repository.updateEmployee(event.employee);
      // Stream will automatically update
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  Future<void> _onDeleteRequested(
    EmployeeDeleteRequested event,
    Emitter<RealtimeState<List<Employee>>> emit,
  ) async {
    try {
      await _repository.deleteEmployee(event.id);
      // Stream will automatically update
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  /// Generate next employee code
  Future<String> generateEmployeeCode() {
    return _repository.generateEmployeeCode();
  }
}

// ==================== EMPLOYEE STATS BLOC ====================

class EmployeeStatsState {
  final int activeCount;
  final int totalCount;
  final List<String> departments;
  final bool isLoading;

  const EmployeeStatsState({
    this.activeCount = 0,
    this.totalCount = 0,
    this.departments = const [],
    this.isLoading = true,
  });

  EmployeeStatsState copyWith({
    int? activeCount,
    int? totalCount,
    List<String>? departments,
    bool? isLoading,
  }) {
    return EmployeeStatsState(
      activeCount: activeCount ?? this.activeCount,
      totalCount: totalCount ?? this.totalCount,
      departments: departments ?? this.departments,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class EmployeeStatsBloc extends Cubit<EmployeeStatsState> {
  final EmployeeRepository _repository;

  EmployeeStatsBloc(this._repository) : super(const EmployeeStatsState()) {
    _loadStats();
  }

  void _loadStats() {
    _repository.watchEmployeeCount(isActive: true).listen((count) {
      emit(state.copyWith(activeCount: count, isLoading: false));
    });

    _repository.watchEmployeeCount().listen((count) {
      emit(state.copyWith(totalCount: count, isLoading: false));
    });

    _repository.watchDepartments().listen((departments) {
      emit(state.copyWith(departments: departments, isLoading: false));
    });
  }
}
