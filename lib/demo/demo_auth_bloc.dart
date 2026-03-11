import 'dart:async';

import '../core/bloc/realtime_bloc.dart';
import '../features/auth/auth.dart';
import 'demo_config.dart';

/// A fake AuthBloc that immediately emits [AuthAuthenticated] with a Manager user.
/// All login/logout/setup events are ignored.
class DemoAuthBloc extends AuthBloc {
  DemoAuthBloc({required super.repository});

  static final UserEntity demoUser = UserEntity(
    id: 1,
    username: DemoConfig.demoUsername,
    role: UserRole.manager,
    isActive: true,
    createdAt: DateTime(2025, 1, 1),
    updatedAt: DateTime.now(),
    lastLoginAt: DateTime.now(),
  );

  @override
  void registerEventHandlers() {
    on<AuthCheckRequested>((event, emit) {
      emit(AuthAuthenticated(user: demoUser));
    });
    on<AuthLoginRequested>((event, emit) {
      emit(AuthAuthenticated(user: demoUser));
    });
    on<AuthLogoutRequested>((event, emit) {
      // Block logout in demo mode — always stay authenticated
      emit(AuthAuthenticated(user: demoUser));
    });
    on<AuthFirstOwnerCreated>((event, emit) {
      emit(AuthAuthenticated(user: demoUser));
    });
    on<AuthSecurityQuestionRequested>((event, emit) {
      emit(AuthAuthenticated(user: demoUser));
    });
    on<AuthPasswordResetRequested>((event, emit) {
      emit(AuthAuthenticated(user: demoUser));
    });
  }

  @override
  Stream<UserEntity?> get dataStream => Stream.value(demoUser);

  @override
  RealtimeState<UserEntity?> mapDataToState(UserEntity? data) {
    return AuthAuthenticated(user: demoUser);
  }
}
