import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/repositories/employee_repository.dart';

// ==================== EVENTS ====================

abstract class LeaveRequestsEvent extends RealtimeEvent {
  const LeaveRequestsEvent();
}

class LeaveRequestsInitialized extends LeaveRequestsEvent {
  final LeaveRequestStatus? status;

  const LeaveRequestsInitialized({this.status});
}

class LeaveRequestsFilterChanged extends LeaveRequestsEvent {
  final LeaveRequestStatus? status;

  const LeaveRequestsFilterChanged(this.status);
}

class LeaveRequestCreateRequested extends LeaveRequestsEvent {
  final int employeeId;
  final LeaveType leaveType;
  final DateTime startDate;
  final DateTime endDate;
  final int daysCount;
  final String? reason;

  const LeaveRequestCreateRequested({
    required this.employeeId,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.daysCount,
    this.reason,
  });
}

class LeaveRequestApproveRequested extends LeaveRequestsEvent {
  final int id;
  final int approvedBy;

  const LeaveRequestApproveRequested({
    required this.id,
    required this.approvedBy,
  });
}

class LeaveRequestRejectRequested extends LeaveRequestsEvent {
  final int id;
  final int rejectedBy;
  final String? rejectionReason;

  const LeaveRequestRejectRequested({
    required this.id,
    required this.rejectedBy,
    this.rejectionReason,
  });
}

class LeaveRequestCancelRequested extends LeaveRequestsEvent {
  final int id;

  const LeaveRequestCancelRequested(this.id);
}

// ==================== BLOC ====================

class LeaveRequestsBloc
    extends RealtimeBloc<List<LeaveRequest>, LeaveRequestsEvent> {
  final EmployeeRepository _repository;

  LeaveRequestStatus? _statusFilter;

  LeaveRequestsBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<List<LeaveRequest>> get dataStream =>
      _repository.watchAllLeaveRequests(status: _statusFilter);

  @override
  void registerEventHandlers() {
    on<LeaveRequestsInitialized>(_onInitialized);
    on<LeaveRequestsFilterChanged>(_onFilterChanged);
    on<LeaveRequestCreateRequested>(_onCreateRequested);
    on<LeaveRequestApproveRequested>(_onApproveRequested);
    on<LeaveRequestRejectRequested>(_onRejectRequested);
    on<LeaveRequestCancelRequested>(_onCancelRequested);
  }

  Future<void> _onInitialized(
    LeaveRequestsInitialized event,
    Emitter<RealtimeState<List<LeaveRequest>>> emit,
  ) async {
    _statusFilter = event.status;
    refresh();
  }

  Future<void> _onFilterChanged(
    LeaveRequestsFilterChanged event,
    Emitter<RealtimeState<List<LeaveRequest>>> emit,
  ) async {
    _statusFilter = event.status;
    refresh();
  }

  Future<void> _onCreateRequested(
    LeaveRequestCreateRequested event,
    Emitter<RealtimeState<List<LeaveRequest>>> emit,
  ) async {
    try {
      await _repository.createLeaveRequest(
        employeeId: event.employeeId,
        leaveType: event.leaveType,
        startDate: event.startDate,
        endDate: event.endDate,
        daysCount: event.daysCount,
        reason: event.reason,
      );
      // Stream will automatically update
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  Future<void> _onApproveRequested(
    LeaveRequestApproveRequested event,
    Emitter<RealtimeState<List<LeaveRequest>>> emit,
  ) async {
    try {
      await _repository.approveLeaveRequest(
        id: event.id,
        approvedBy: event.approvedBy,
      );
      // Stream will automatically update
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  Future<void> _onRejectRequested(
    LeaveRequestRejectRequested event,
    Emitter<RealtimeState<List<LeaveRequest>>> emit,
  ) async {
    try {
      await _repository.rejectLeaveRequest(
        id: event.id,
        rejectedBy: event.rejectedBy,
        rejectionReason: event.rejectionReason,
      );
      // Stream will automatically update
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  Future<void> _onCancelRequested(
    LeaveRequestCancelRequested event,
    Emitter<RealtimeState<List<LeaveRequest>>> emit,
  ) async {
    try {
      await _repository.cancelLeaveRequest(event.id);
      // Stream will automatically update
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }
}
