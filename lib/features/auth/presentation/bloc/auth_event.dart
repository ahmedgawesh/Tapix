part of 'auth_bloc.dart';

abstract class AuthEvent extends RealtimeEvent with EquatableMixin {
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

  const AuthFirstOwnerCreated({
    required this.username,
    required this.password,
  });

  @override
  List<Object?> get props => [username, password];
}
