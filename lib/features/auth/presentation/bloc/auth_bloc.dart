import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';

import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository_interface.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends RealtimeBloc<UserEntity?, AuthEvent> {
  final AuthRepositoryInterface _repository;

  AuthBloc({required AuthRepositoryInterface repository})
      : _repository = repository,
        super(const AuthLoading());

  @override
  Stream<UserEntity?> get dataStream => _repository.watchCurrentUser();

  @override
  void registerEventHandlers() {
    on<AuthCheckRequested>(_onCheckRequested);
    on<AuthLoginRequested>(_onLoginRequested);
    on<AuthLogoutRequested>(_onLogoutRequested);
    on<AuthFirstOwnerCreated>(_onFirstOwnerCreated);
  }

  @override
  RealtimeState<UserEntity?> mapDataToState(UserEntity? data) {
    if (data == null) {
      return const AuthUnauthenticated();
    }
    return AuthAuthenticated(user: data);
  }

  @override
  RealtimeState<UserEntity?> mapErrorToState(
    Object error, {
    StackTrace? stackTrace,
    UserEntity? previousData,
  }) {
    return const AuthError(message: 'Authentication error');
  }

  Future<void> _onCheckRequested(
    AuthCheckRequested event,
    Emitter<RealtimeState<UserEntity?>> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final hasUsers = await _repository.hasAnyUsers();
      if (!hasUsers) {
        emit(const AuthNeedsSetup());
        return;
      }

      final currentUser = await _repository.getCurrentUser();
      if (currentUser != null) {
        emit(AuthAuthenticated(user: currentUser));
      } else {
        emit(const AuthUnauthenticated());
      }
    } catch (e) {
      emit(const AuthError(message: 'Authentication error'));
    }
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<RealtimeState<UserEntity?>> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final user = await _repository.login(event.username, event.password);
      if (user != null) {
        emit(AuthAuthenticated(user: user));
      } else {
        emit(const AuthError(message: 'Invalid username or password'));
      }
    } catch (e) {
      emit(const AuthError(message: 'Invalid username or password'));
    }
  }

  Future<void> _onLogoutRequested(
    AuthLogoutRequested event,
    Emitter<RealtimeState<UserEntity?>> emit,
  ) async {
    emit(const AuthLoading());

    try {
      await _repository.logout();
      emit(const AuthUnauthenticated());
    } catch (e) {
      emit(const AuthError(message: 'Authentication error'));
    }
  }

  Future<void> _onFirstOwnerCreated(
    AuthFirstOwnerCreated event,
    Emitter<RealtimeState<UserEntity?>> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final user = await _repository.createFirstOwner(
        event.username,
        event.password,
      );
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(const AuthError(message: 'Failed to create owner account'));
    }
  }
}
