import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/attendance_service.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/repositories/employee_repository.dart';

// ==================== EVENTS ====================

abstract class AttendanceEvent extends RealtimeEvent {
  const AttendanceEvent();
}

class AttendanceInitialized extends AttendanceEvent {
  final DateTime date;

  const AttendanceInitialized(this.date);
}

class AttendanceDateChanged extends AttendanceEvent {
  final DateTime date;

  const AttendanceDateChanged(this.date);
}

class AttendanceCheckInRequested extends AttendanceEvent {
  final int employeeId;
  final String? checkInMethod;
  final String? location;
  final DateTime? checkInTime;

  const AttendanceCheckInRequested({
    required this.employeeId,
    this.checkInMethod,
    this.location,
    this.checkInTime,
  });
}

class AttendanceCheckOutRequested extends AttendanceEvent {
  final int employeeId;
  final int overtimeMinutes;
  final DateTime? checkOutTime;

  const AttendanceCheckOutRequested({
    required this.employeeId,
    this.overtimeMinutes = 0,
    this.checkOutTime,
  });
}

class AttendanceStatusUpdateRequested extends AttendanceEvent {
  final int employeeId;
  final AttendanceStatus status;
  final String? notes;
  final int? approvedBy;

  const AttendanceStatusUpdateRequested({
    required this.employeeId,
    required this.status,
    this.notes,
    this.approvedBy,
  });
}

class AttendanceMarkLateRequested extends AttendanceEvent {
  final int employeeId;
  final String? notes;
  final DateTime? checkInTime;

  const AttendanceMarkLateRequested({
    required this.employeeId,
    this.notes,
    this.checkInTime,
  });
}

class AttendanceMarkAbsentRequested extends AttendanceEvent {
  final int employeeId;
  final String? notes;

  const AttendanceMarkAbsentRequested({required this.employeeId, this.notes});
}

/// Correct an existing attendance record (owner/manager only).
class AttendanceEditRequested extends AttendanceEvent {
  final int employeeId;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final AttendanceStatus status;
  final String? notes;

  const AttendanceEditRequested({
    required this.employeeId,
    required this.checkInTime,
    required this.checkOutTime,
    required this.status,
    this.notes,
  });
}

/// Internal event fired when the attendance stream emits new data.
class _AttendanceDataReceived extends AttendanceEvent {
  final List<Attendance> attendances;

  const _AttendanceDataReceived(this.attendances);
}

/// Internal event fired when the attendance stream emits an error.
class _AttendanceStreamError extends AttendanceEvent {
  final Object error;

  const _AttendanceStreamError(this.error);
}

// ==================== STATE ====================

class AttendanceState {
  final DateTime selectedDate;
  final List<Attendance> attendances;
  final Map<int, String> employeeNames;
  final AttendanceSummary summary;
  final bool isLoading;
  final String? error;

  const AttendanceState({
    required this.selectedDate,
    this.attendances = const [],
    this.employeeNames = const {},
    this.summary = const AttendanceSummary(date: null),
    this.isLoading = true,
    this.error,
  });

  AttendanceState copyWith({
    DateTime? selectedDate,
    List<Attendance>? attendances,
    Map<int, String>? employeeNames,
    AttendanceSummary? summary,
    bool? isLoading,
    String? error,
  }) {
    return AttendanceState(
      selectedDate: selectedDate ?? this.selectedDate,
      attendances: attendances ?? this.attendances,
      employeeNames: employeeNames ?? this.employeeNames,
      summary: summary ?? this.summary,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// Extend AttendanceSummary to allow null date for initial state
extension AttendanceSummaryExtension on AttendanceSummary {
  static AttendanceSummary empty(DateTime date) =>
      AttendanceSummary(date: date);
}

// ==================== BLOC ====================

class AttendanceBloc extends Bloc<AttendanceEvent, AttendanceState> {
  final EmployeeRepository _repository;
  final AttendanceService _attendanceService;
  StreamSubscription<List<Attendance>>? _attendanceSub;

  AttendanceBloc(this._repository, this._attendanceService)
    : super(AttendanceState(selectedDate: DateTime.now())) {
    on<AttendanceInitialized>(_onInitialized);
    on<AttendanceDateChanged>(_onDateChanged);
    on<_AttendanceDataReceived>(_onDataReceived);
    on<_AttendanceStreamError>(_onStreamError);
    on<AttendanceCheckInRequested>(_onCheckInRequested);
    on<AttendanceCheckOutRequested>(_onCheckOutRequested);
    on<AttendanceStatusUpdateRequested>(_onStatusUpdateRequested);
    on<AttendanceMarkLateRequested>(_onMarkLateRequested);
    on<AttendanceMarkAbsentRequested>(_onMarkAbsentRequested);
    on<AttendanceEditRequested>(_onEditRequested);
  }

  void _onInitialized(
    AttendanceInitialized event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(state.copyWith(selectedDate: event.date, isLoading: true));

    // Generate attendance records for all active employees if they don't exist
    try {
      await _attendanceService.generateDailyAttendance(event.date);
    } catch (e) {
      // Don't emit error state, just log it
      // The attendance will still load even if generation fails
    }

    _subscribeToDate(event.date);
  }

  void _onDateChanged(
    AttendanceDateChanged event,
    Emitter<AttendanceState> emit,
  ) async {
    emit(state.copyWith(selectedDate: event.date, isLoading: true));

    // Generate attendance records for the selected date if they don't exist
    try {
      await _attendanceService.generateDailyAttendance(event.date);
    } catch (e) {
      // Don't emit error state, just log it
    }

    _subscribeToDate(event.date);
  }

  void _subscribeToDate(DateTime date) {
    _attendanceSub?.cancel();
    _attendanceSub = _repository
        .watchAttendanceByDate(date)
        .listen(
          (attendances) => add(_AttendanceDataReceived(attendances)),
          onError: (Object error) => add(_AttendanceStreamError(error)),
        );
  }

  Future<void> _onDataReceived(
    _AttendanceDataReceived event,
    Emitter<AttendanceState> emit,
  ) async {
    final attendances = event.attendances;
    int presentCount = 0;
    int lateCount = 0;
    int absentCount = 0;
    int onLeaveCount = 0;

    for (final a in attendances) {
      switch (a.status) {
        case 'present':
          presentCount++;
          break;
        case 'late':
          lateCount++;
          break;
        case 'absent':
          absentCount++;
          break;
        case 'leave':
          onLeaveCount++;
          break;
      }
    }

    // Load employee names for all attendance records
    final names = Map<int, String>.from(state.employeeNames);
    for (final a in attendances) {
      if (!names.containsKey(a.employeeId)) {
        final employee = await _repository.getEmployee(a.employeeId);
        if (employee != null) {
          names[a.employeeId] = employee.name;
        }
      }
    }

    emit(
      state.copyWith(
        attendances: attendances,
        employeeNames: names,
        summary: AttendanceSummary(
          date: state.selectedDate,
          presentCount: presentCount,
          lateCount: lateCount,
          absentCount: absentCount,
          onLeaveCount: onLeaveCount,
        ),
        isLoading: false,
        error: null,
      ),
    );
  }

  void _onStreamError(
    _AttendanceStreamError event,
    Emitter<AttendanceState> emit,
  ) {
    emit(state.copyWith(isLoading: false, error: event.error.toString()));
  }

  Future<void> _onCheckInRequested(
    AttendanceCheckInRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    try {
      final checkInTime = event.checkInTime ?? DateTime.now();
      await _repository.checkIn(
        employeeId: event.employeeId,
        date: state.selectedDate,
        checkInTime: checkInTime,
        checkInMethod: event.checkInMethod ?? 'manual',
        location: event.location,
      );
      // Stream will automatically update
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onCheckOutRequested(
    AttendanceCheckOutRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    try {
      final checkOutTime = event.checkOutTime ?? DateTime.now();
      await _repository.checkOut(
        employeeId: event.employeeId,
        date: state.selectedDate,
        checkOutTime: checkOutTime,
        overtimeMinutes: event.overtimeMinutes,
      );

      // Check for early departure: if left >2hrs before expected end
      final attendance = state.attendances.firstWhere(
        (a) => a.employeeId == event.employeeId,
        orElse: () => state.attendances.first,
      );
      if (attendance.checkInTime != null) {
        final employee = await _repository.getEmployee(event.employeeId);
        if (employee != null) {
          final workingHours = employee.workingHoursPerDay;
          final expectedEnd = attendance.checkInTime!.add(
            Duration(hours: workingHours),
          );
          final earlyBy = expectedEnd.difference(checkOutTime);
          if (earlyBy.inHours >= 2) {
            await _repository.updateAttendanceStatus(
              employeeId: event.employeeId,
              date: state.selectedDate,
              status: AttendanceStatus.early_departure,
              notes:
                  'Left ${earlyBy.inHours}h ${earlyBy.inMinutes % 60}m early',
            );
          }
        }
      }
      // Stream will automatically update
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onStatusUpdateRequested(
    AttendanceStatusUpdateRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    try {
      await _repository.updateAttendanceStatus(
        employeeId: event.employeeId,
        date: state.selectedDate,
        status: event.status,
        notes: event.notes,
        approvedBy: event.approvedBy,
      );
      // Stream will automatically update
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onMarkLateRequested(
    AttendanceMarkLateRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    try {
      final checkInTime = event.checkInTime ?? DateTime.now();
      await _repository.checkIn(
        employeeId: event.employeeId,
        date: state.selectedDate,
        checkInTime: checkInTime,
        checkInMethod: 'manual',
        status: AttendanceStatus.late,
        notes: event.notes,
      );
      // Stream will automatically update
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onMarkAbsentRequested(
    AttendanceMarkAbsentRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    try {
      await _repository.markAbsent(
        employeeId: event.employeeId,
        date: state.selectedDate,
        notes: event.notes,
      );
      // Stream will automatically update
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  Future<void> _onEditRequested(
    AttendanceEditRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    try {
      await _repository.editAttendance(
        employeeId: event.employeeId,
        date: state.selectedDate,
        checkInTime: event.checkInTime,
        checkOutTime: event.checkOutTime,
        status: event.status,
        notes: event.notes,
      );
      // Stream will automatically update
    } catch (e) {
      emit(state.copyWith(error: e.toString()));
    }
  }

  @override
  Future<void> close() async {
    await _attendanceSub?.cancel();
    return super.close();
  }
}
