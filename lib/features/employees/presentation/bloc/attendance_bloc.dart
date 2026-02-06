import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
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

  const AttendanceCheckInRequested({
    required this.employeeId,
    this.checkInMethod,
    this.location,
  });
}

class AttendanceCheckOutRequested extends AttendanceEvent {
  final int employeeId;
  final int overtimeMinutes;

  const AttendanceCheckOutRequested({
    required this.employeeId,
    this.overtimeMinutes = 0,
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

  const AttendanceMarkLateRequested({
    required this.employeeId,
    this.notes,
  });
}

class AttendanceMarkAbsentRequested extends AttendanceEvent {
  final int employeeId;
  final String? notes;

  const AttendanceMarkAbsentRequested({
    required this.employeeId,
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
  final AttendanceSummary summary;
  final bool isLoading;
  final String? error;

  const AttendanceState({
    required this.selectedDate,
    this.attendances = const [],
    this.summary = const AttendanceSummary(date: null),
    this.isLoading = true,
    this.error,
  });

  AttendanceState copyWith({
    DateTime? selectedDate,
    List<Attendance>? attendances,
    AttendanceSummary? summary,
    bool? isLoading,
    String? error,
  }) {
    return AttendanceState(
      selectedDate: selectedDate ?? this.selectedDate,
      attendances: attendances ?? this.attendances,
      summary: summary ?? this.summary,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// Extend AttendanceSummary to allow null date for initial state
extension AttendanceSummaryExtension on AttendanceSummary {
  static AttendanceSummary empty(DateTime date) => AttendanceSummary(date: date);
}

// ==================== BLOC ====================

class AttendanceBloc extends Bloc<AttendanceEvent, AttendanceState> {
  final EmployeeRepository _repository;
  StreamSubscription<List<Attendance>>? _attendanceSub;

  AttendanceBloc(this._repository)
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
  }

  void _onInitialized(
    AttendanceInitialized event,
    Emitter<AttendanceState> emit,
  ) {
    emit(state.copyWith(selectedDate: event.date, isLoading: true));
    _subscribeToDate(event.date);
  }

  void _onDateChanged(
    AttendanceDateChanged event,
    Emitter<AttendanceState> emit,
  ) {
    emit(state.copyWith(selectedDate: event.date, isLoading: true));
    _subscribeToDate(event.date);
  }

  void _subscribeToDate(DateTime date) {
    _attendanceSub?.cancel();
    _attendanceSub = _repository.watchAttendanceByDate(date).listen(
      (attendances) => add(_AttendanceDataReceived(attendances)),
      onError: (Object error) => add(_AttendanceStreamError(error)),
    );
  }

  void _onDataReceived(
    _AttendanceDataReceived event,
    Emitter<AttendanceState> emit,
  ) {
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

    emit(state.copyWith(
      attendances: attendances,
      summary: AttendanceSummary(
        date: state.selectedDate,
        presentCount: presentCount,
        lateCount: lateCount,
        absentCount: absentCount,
        onLeaveCount: onLeaveCount,
      ),
      isLoading: false,
      error: null,
    ));
  }

  void _onStreamError(
    _AttendanceStreamError event,
    Emitter<AttendanceState> emit,
  ) {
    emit(state.copyWith(
      isLoading: false,
      error: event.error.toString(),
    ));
  }

  Future<void> _onCheckInRequested(
    AttendanceCheckInRequested event,
    Emitter<AttendanceState> emit,
  ) async {
    try {
      final now = DateTime.now();
      await _repository.checkIn(
        employeeId: event.employeeId,
        date: state.selectedDate,
        checkInTime: now,
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
      final now = DateTime.now();
      await _repository.checkOut(
        employeeId: event.employeeId,
        date: state.selectedDate,
        checkOutTime: now,
        overtimeMinutes: event.overtimeMinutes,
      );
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
      final now = DateTime.now();
      await _repository.checkIn(
        employeeId: event.employeeId,
        date: state.selectedDate,
        checkInTime: now,
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

  @override
  Future<void> close() async {
    await _attendanceSub?.cancel();
    return super.close();
  }
}
