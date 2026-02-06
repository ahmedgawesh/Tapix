import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/employee_repository.dart';

// ==================== EVENTS ====================

abstract class RolesEvent extends RealtimeEvent {
  const RolesEvent();
}

class RolesInitialized extends RolesEvent {
  final bool? isActive;

  const RolesInitialized({this.isActive = true});
}

class RoleCreateRequested extends RolesEvent {
  final String name;
  final String? nameAr;
  final String? nameFr;
  final String? description;
  final List<String> permissions;
  final bool isSystemRole;

  const RoleCreateRequested({
    required this.name,
    this.nameAr,
    this.nameFr,
    this.description,
    this.permissions = const [],
    this.isSystemRole = false,
  });
}

class RoleUpdateRequested extends RolesEvent {
  final Role role;

  const RoleUpdateRequested(this.role);
}

class RoleDeleteRequested extends RolesEvent {
  final int id;

  const RoleDeleteRequested(this.id);
}

// ==================== BLOC ====================

class RolesBloc extends RealtimeBloc<List<Role>, RolesEvent> {
  final EmployeeRepository _repository;

  bool? _isActiveFilter = true;

  RolesBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<List<Role>> get dataStream =>
      _repository.watchAllRoles(isActive: _isActiveFilter);

  @override
  void registerEventHandlers() {
    on<RolesInitialized>(_onInitialized);
    on<RoleCreateRequested>(_onCreateRequested);
    on<RoleUpdateRequested>(_onUpdateRequested);
    on<RoleDeleteRequested>(_onDeleteRequested);
  }

  Future<void> _onInitialized(
    RolesInitialized event,
    Emitter<RealtimeState<List<Role>>> emit,
  ) async {
    _isActiveFilter = event.isActive;
    refresh();
  }

  Future<void> _onCreateRequested(
    RoleCreateRequested event,
    Emitter<RealtimeState<List<Role>>> emit,
  ) async {
    try {
      await _repository.createRole(
        name: event.name,
        nameAr: event.nameAr,
        nameFr: event.nameFr,
        description: event.description,
        permissions: event.permissions,
        isSystemRole: event.isSystemRole,
      );
      // Stream will automatically update
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  Future<void> _onUpdateRequested(
    RoleUpdateRequested event,
    Emitter<RealtimeState<List<Role>>> emit,
  ) async {
    try {
      await _repository.updateRole(event.role);
      // Stream will automatically update
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }

  Future<void> _onDeleteRequested(
    RoleDeleteRequested event,
    Emitter<RealtimeState<List<Role>>> emit,
  ) async {
    try {
      await _repository.deleteRole(event.id);
      // Stream will automatically update
    } catch (e) {
      emit(RealtimeError(error: e, previousData: currentData));
    }
  }
}
