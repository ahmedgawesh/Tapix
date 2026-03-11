import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/user_repository_interface.dart';

// States
abstract class UserFormState extends Equatable {
  const UserFormState();

  @override
  List<Object?> get props => [];
}

class UserFormInitial extends UserFormState {
  const UserFormInitial();
}

class UserFormLoading extends UserFormState {
  const UserFormLoading();
}

class UserFormLoaded extends UserFormState {
  final UserEntity? existingUser;

  const UserFormLoaded({this.existingUser});

  @override
  List<Object?> get props => [existingUser];
}

class UserFormSubmitting extends UserFormState {
  const UserFormSubmitting();
}

class UserFormSuccess extends UserFormState {
  final String message;

  const UserFormSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

class UserFormError extends UserFormState {
  final String message;

  const UserFormError(this.message);

  @override
  List<Object?> get props => [message];
}

// Events
abstract class UserFormEvent extends Equatable {
  const UserFormEvent();

  @override
  List<Object?> get props => [];
}

class UserFormLoadRequested extends UserFormEvent {
  final int? userId;

  const UserFormLoadRequested({this.userId});

  @override
  List<Object?> get props => [userId];
}

class UserFormSubmitRequested extends UserFormEvent {
  final int? userId;
  final String username;
  final String password;
  final String confirmPassword;
  final UserRole role;
  final int? employeeId;
  final bool clearEmployeeLink;
  final String? securityQuestion;
  final String? securityAnswer;

  const UserFormSubmitRequested({
    this.userId,
    required this.username,
    required this.password,
    required this.confirmPassword,
    required this.role,
    this.employeeId,
    this.clearEmployeeLink = false,
    this.securityQuestion,
    this.securityAnswer,
  });

  @override
  List<Object?> get props => [
        userId,
        username,
        password,
        confirmPassword,
        role,
        employeeId,
        clearEmployeeLink,
        securityQuestion,
        securityAnswer,
      ];
}

class UserFormUsernameCheckRequested extends UserFormEvent {
  final String username;
  final int? excludeUserId;

  const UserFormUsernameCheckRequested(this.username, {this.excludeUserId});

  @override
  List<Object?> get props => [username, excludeUserId];
}

// Bloc
class UserFormBloc extends Bloc<UserFormEvent, UserFormState> {
  final UserRepositoryInterface _repository;

  UserFormBloc(this._repository) : super(const UserFormInitial()) {
    on<UserFormLoadRequested>(_onLoadRequested);
    on<UserFormSubmitRequested>(_onSubmitRequested);
  }

  Future<void> _onLoadRequested(
    UserFormLoadRequested event,
    Emitter<UserFormState> emit,
  ) async {
    emit(const UserFormLoading());
    try {
      if (event.userId != null) {
        final user = await _repository.getUserById(event.userId!);
        emit(UserFormLoaded(existingUser: user));
      } else {
        emit(const UserFormLoaded());
      }
    } catch (e) {
      emit(UserFormError(e.toString()));
    }
  }

  Future<void> _onSubmitRequested(
    UserFormSubmitRequested event,
    Emitter<UserFormState> emit,
  ) async {
    emit(const UserFormSubmitting());

    try {
      // Validate username
      if (event.username.trim().isEmpty) {
        emit(const UserFormError('username_required'));
        return;
      }
      if (event.username.trim().length < 3) {
        emit(const UserFormError('username_min_length'));
        return;
      }

      // Check username uniqueness
      final isTaken = await _repository.isUsernameTaken(
        event.username.trim(),
        excludeUserId: event.userId,
      );
      if (isTaken) {
        emit(const UserFormError('username_taken'));
        return;
      }

      // For new users, validate password
      if (event.userId == null) {
        if (event.password.isEmpty) {
          emit(const UserFormError('password_required'));
          return;
        }
        if (event.password.length < 6) {
          emit(const UserFormError('password_min_length'));
          return;
        }
        if (event.password != event.confirmPassword) {
          emit(const UserFormError('passwords_not_match'));
          return;
        }
      } else {
        // For edit, validate password only if provided
        if (event.password.isNotEmpty) {
          if (event.password.length < 6) {
            emit(const UserFormError('password_min_length'));
            return;
          }
          if (event.password != event.confirmPassword) {
            emit(const UserFormError('passwords_not_match'));
            return;
          }
        }
      }

      if (event.userId == null) {
        // Create new user
        await _repository.createUser(
          username: event.username.trim(),
          password: event.password,
          role: event.role,
          employeeId: event.employeeId,
          securityQuestion: event.securityQuestion,
          securityAnswer: event.securityAnswer,
        );
        emit(const UserFormSuccess('created_success'));
      } else {
        // Update existing user
        await _repository.updateUser(
          id: event.userId!,
          username: event.username.trim(),
          password: event.password.isNotEmpty ? event.password : null,
          role: event.role,
          employeeId: event.employeeId,
          clearEmployeeLink: event.clearEmployeeLink,
          securityQuestion: event.securityQuestion,
          securityAnswer: event.securityAnswer,
        );
        emit(const UserFormSuccess('updated_success'));
      }
    } catch (e) {
      emit(UserFormError(e.toString()));
    }
  }
}
