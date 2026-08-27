import 'package:easy_localization/easy_localization.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/biometric_service.dart';
import '../../../../core/services/crashlytics_service.dart';

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
    on<AuthSecurityQuestionRequested>(_onSecurityQuestionRequested);
    on<AuthPasswordResetRequested>(_onPasswordResetRequested);
    on<AuthBiometricLoginRequested>(_onBiometricLoginRequested);
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
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('AuthCheckRequested error: $e');
      // ignore: avoid_print
      print('Stack trace: $stackTrace');
      emit(AuthError(message: 'Authentication error: $e'));
    }
  }

  Future<void> _onLoginRequested(
    AuthLoginRequested event,
    Emitter<RealtimeState<UserEntity?>> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final user = await _repository.login(
        event.username,
        event.password,
        rememberMe: event.rememberMe,
      );
      if (user != null) {
        CrashlyticsService.instance.setUser(
          userId: user.id,
          role: user.role.name,
        );
        CrashlyticsService.instance.logAction('login', {
          'user_id': user.id.toString(),
          'role': user.role.name,
        });
        emit(AuthAuthenticated(user: user));
      } else {
        emit(const AuthError(message: 'Invalid username or password'));
      }
    } on RemoteAuthenticationRequiredException {
      emit(AuthError(message: 'auth.remote_login_pending'.tr()));
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
      CrashlyticsService.instance.logAction('logout');
      CrashlyticsService.instance.clearUser();
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
        securityQuestion: event.securityQuestion,
        securityAnswer: event.securityAnswer,
      );
      CrashlyticsService.instance.setUser(
        userId: user.id,
        role: user.role.name,
      );
      CrashlyticsService.instance.logAction('first_owner_created', {
        'user_id': user.id.toString(),
      });
      emit(AuthAuthenticated(user: user));
    } catch (e) {
      emit(const AuthError(message: 'Failed to create owner account'));
    }
  }

  Future<void> _onSecurityQuestionRequested(
    AuthSecurityQuestionRequested event,
    Emitter<RealtimeState<UserEntity?>> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final question = await _repository.getSecurityQuestion(event.username);
      if (question != null && question.isNotEmpty) {
        emit(
          AuthSecurityQuestionLoaded(
            username: event.username,
            question: question,
          ),
        );
      } else {
        emit(AuthSecurityQuestionNotSet(username: event.username));
      }
    } catch (e) {
      emit(const AuthError(message: 'Failed to load security question'));
    }
  }

  Future<void> _onBiometricLoginRequested(
    AuthBiometricLoginRequested event,
    Emitter<RealtimeState<UserEntity?>> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final biometricService = sl<BiometricService>();
      final authenticated = await biometricService.authenticate(
        localizedReason: 'auth.biometric_reason'.tr(),
      );

      if (!authenticated) {
        emit(const AuthUnauthenticated());
        return;
      }

      final user = await _repository.loginWithBiometrics();
      if (user != null) {
        CrashlyticsService.instance.setUser(
          userId: user.id,
          role: user.role.name,
        );
        CrashlyticsService.instance.logAction('biometric_login', {
          'user_id': user.id.toString(),
          'role': user.role.name,
        });
        emit(AuthAuthenticated(user: user));
      } else {
        emit(
          const AuthError(
            message: 'Biometric login failed: no previous session',
          ),
        );
      }
    } catch (e) {
      emit(const AuthError(message: 'Biometric authentication failed'));
    }
  }

  Future<void> _onPasswordResetRequested(
    AuthPasswordResetRequested event,
    Emitter<RealtimeState<UserEntity?>> emit,
  ) async {
    emit(const AuthLoading());

    try {
      final success = await _repository.resetPasswordWithSecurityAnswer(
        username: event.username,
        securityAnswer: event.securityAnswer,
        newPassword: event.newPassword,
      );
      if (success) {
        emit(const AuthPasswordResetSuccess());
      } else {
        emit(const AuthPasswordResetFailed(message: 'incorrect_answer'));
      }
    } catch (e) {
      emit(const AuthPasswordResetFailed(message: 'reset_failed'));
    }
  }
}
