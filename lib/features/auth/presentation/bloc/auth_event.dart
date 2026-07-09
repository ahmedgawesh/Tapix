part of 'auth_bloc.dart';

abstract class AuthEvent extends RealtimeEvent with Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

class AuthLoginRequested extends AuthEvent {
  final String username;
  final String password;
  final bool rememberMe;

  const AuthLoginRequested({
    required this.username,
    required this.password,
    this.rememberMe = false,
  });

  @override
  List<Object?> get props => [username, password, rememberMe];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

class AuthFirstOwnerCreated extends AuthEvent {
  final String username;
  final String password;
  final String? securityQuestion;
  final String? securityAnswer;

  const AuthFirstOwnerCreated({
    required this.username,
    required this.password,
    this.securityQuestion,
    this.securityAnswer,
  });

  @override
  List<Object?> get props => [username, password, securityQuestion, securityAnswer];
}

class AuthSecurityQuestionRequested extends AuthEvent {
  final String username;

  const AuthSecurityQuestionRequested({required this.username});

  @override
  List<Object?> get props => [username];
}

class AuthBiometricLoginRequested extends AuthEvent {
  const AuthBiometricLoginRequested();
}

class AuthPasswordResetRequested extends AuthEvent {
  final String username;
  final String securityAnswer;
  final String newPassword;

  const AuthPasswordResetRequested({
    required this.username,
    required this.securityAnswer,
    required this.newPassword,
  });

  @override
  List<Object?> get props => [username, securityAnswer, newPassword];
}
