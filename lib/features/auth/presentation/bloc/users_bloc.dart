import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/user_repository_interface.dart';

// Events
abstract class UsersEvent extends RealtimeEvent with Equatable {
  const UsersEvent();

  @override
  List<Object?> get props => [];
}

class UsersInitialized extends UsersEvent {
  const UsersInitialized();
}

class UserSearchRequested extends UsersEvent {
  final String query;
  const UserSearchRequested(this.query);

  @override
  List<Object?> get props => [query];
}

class UserFilterByRoleRequested extends UsersEvent {
  final UserRole? role;
  const UserFilterByRoleRequested(this.role);

  @override
  List<Object?> get props => [role];
}

class UserToggleActiveRequested extends UsersEvent {
  final int userId;
  final bool isActive;
  const UserToggleActiveRequested(this.userId, this.isActive);

  @override
  List<Object?> get props => [userId, isActive];
}

// Bloc
class UsersBloc extends RealtimeBloc<List<UserEntity>, UsersEvent> {
  final UserRepositoryInterface _repository;
  String _searchQuery = '';
  UserRole? _roleFilter;
  List<UserEntity> _rawData = [];

  UsersBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<List<UserEntity>> get dataStream => _repository.watchAllUsers();

  @override
  void registerEventHandlers() {
    on<UsersInitialized>(_onInitialized);
    on<UserSearchRequested>(_onSearchRequested);
    on<UserFilterByRoleRequested>(_onFilterByRoleRequested);
    on<UserToggleActiveRequested>(_onToggleActiveRequested);
  }

  @override
  RealtimeState<List<UserEntity>> mapDataToState(List<UserEntity> data) {
    _rawData = data;
    return RealtimeSuccess<List<UserEntity>>(data: _applyFilters(data));
  }

  List<UserEntity> _applyFilters(List<UserEntity> users) {
    var filtered = users;

    if (_roleFilter != null) {
      filtered = filtered.where((u) => u.role == _roleFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered
          .where((u) => u.username.toLowerCase().contains(query))
          .toList();
    }

    return filtered;
  }

  void _onInitialized(
    UsersInitialized event,
    Emitter<RealtimeState<List<UserEntity>>> emit,
  ) {
    // Stream subscription handles data loading
  }

  void _onSearchRequested(
    UserSearchRequested event,
    Emitter<RealtimeState<List<UserEntity>>> emit,
  ) {
    _searchQuery = event.query;
    if (_rawData.isNotEmpty) {
      emit(RealtimeSuccess<List<UserEntity>>(data: _applyFilters(_rawData)));
    }
  }

  void _onFilterByRoleRequested(
    UserFilterByRoleRequested event,
    Emitter<RealtimeState<List<UserEntity>>> emit,
  ) {
    _roleFilter = event.role;
    if (_rawData.isNotEmpty) {
      emit(RealtimeSuccess<List<UserEntity>>(data: _applyFilters(_rawData)));
    }
  }

  Future<void> _onToggleActiveRequested(
    UserToggleActiveRequested event,
    Emitter<RealtimeState<List<UserEntity>>> emit,
  ) async {
    await _repository.toggleUserActive(event.userId, event.isActive);
  }
}

// Stats Bloc
class UserStatsBloc extends RealtimeBloc<Map<UserRole, int>, RealtimeEvent> {
  final UserRepositoryInterface _repository;

  UserStatsBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<Map<UserRole, int>> get dataStream => _repository.watchRoleCounts();

  @override
  void registerEventHandlers() {}
}
