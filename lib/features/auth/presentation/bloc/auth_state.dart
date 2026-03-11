part of 'auth_bloc.dart';

abstract class AuthState extends RealtimeState<UserEntity?> with EquatableMixin {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthNeedsSetup extends AuthState {
  const AuthNeedsSetup();
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthAuthenticated extends AuthState {
  final UserEntity user;

  const AuthAuthenticated({required this.user});

  @override
  List<Object?> get props => [user];
}

class AuthError extends AuthState {
  final String message;

  const AuthError({required this.message});

  @override
  List<Object?> get props => [message];
}

class AuthSecurityQuestionLoaded extends AuthState {
  final String username;
  final String question;

  const AuthSecurityQuestionLoaded({required this.username, required this.question});

  @override
  List<Object?> get props => [username, question];
}

class AuthSecurityQuestionNotSet extends AuthState {
  final String username;

  const AuthSecurityQuestionNotSet({required this.username});

  @override
  List<Object?> get props => [username];
}

class AuthPasswordResetSuccess extends AuthState {
  const AuthPasswordResetSuccess();
}

class AuthPasswordResetFailed extends AuthState {
  final String message;

  const AuthPasswordResetFailed({required this.message});

  @override
  List<Object?> get props => [message];
}
