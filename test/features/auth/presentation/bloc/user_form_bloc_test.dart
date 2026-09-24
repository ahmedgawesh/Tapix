import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/features/auth/domain/entities/user_entity.dart';
import 'package:tapix/features/auth/domain/repositories/user_repository_interface.dart';
import 'package:tapix/features/auth/presentation/bloc/user_form_bloc.dart';

class MockUserRepository extends Mock implements UserRepositoryInterface {}

void main() {
  late MockUserRepository mockRepository;

  final testUser = UserEntity(
    id: 1,
    username: 'testuser',
    role: UserRole.cashier,
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    mockRepository = MockUserRepository();
  });

  group('UserFormBloc', () {
    group('UserFormLoadRequested', () {
      blocTest<UserFormBloc, UserFormState>(
        'emits [Loading, Loaded] for new user (no userId)',
        build: () => UserFormBloc(mockRepository),
        act: (bloc) => bloc.add(const UserFormLoadRequested()),
        expect: () => [
          isA<UserFormLoading>(),
          isA<UserFormLoaded>().having(
            (s) => s.existingUser,
            'existingUser',
            isNull,
          ),
        ],
      );

      blocTest<UserFormBloc, UserFormState>(
        'emits [Loading, Loaded(user)] for existing user',
        setUp: () {
          when(
            () => mockRepository.getUserById(1),
          ).thenAnswer((_) async => testUser);
        },
        build: () => UserFormBloc(mockRepository),
        act: (bloc) => bloc.add(const UserFormLoadRequested(userId: 1)),
        expect: () => [
          isA<UserFormLoading>(),
          isA<UserFormLoaded>().having(
            (s) => s.existingUser?.username,
            'username',
            'testuser',
          ),
        ],
      );
    });

    group('UserFormSubmitRequested - Create', () {
      blocTest<UserFormBloc, UserFormState>(
        'emits error when username is empty',
        build: () => UserFormBloc(mockRepository),
        act: (bloc) => bloc.add(
          const UserFormSubmitRequested(
            username: '',
            password: 'password123',
            confirmPassword: 'password123',
            role: UserRole.cashier,
            employeeId: 7,
          ),
        ),
        expect: () => [
          isA<UserFormSubmitting>(),
          isA<UserFormError>().having(
            (s) => s.message,
            'message',
            'username_required',
          ),
        ],
      );

      blocTest<UserFormBloc, UserFormState>(
        'emits error when username is too short',
        build: () => UserFormBloc(mockRepository),
        act: (bloc) => bloc.add(
          const UserFormSubmitRequested(
            username: 'ab',
            password: 'password123',
            confirmPassword: 'password123',
            role: UserRole.cashier,
            employeeId: 7,
          ),
        ),
        expect: () => [
          isA<UserFormSubmitting>(),
          isA<UserFormError>().having(
            (s) => s.message,
            'message',
            'username_min_length',
          ),
        ],
      );

      blocTest<UserFormBloc, UserFormState>(
        'emits error when username is taken',
        setUp: () {
          when(
            () => mockRepository.isUsernameTaken('taken', excludeUserId: null),
          ).thenAnswer((_) async => true);
        },
        build: () => UserFormBloc(mockRepository),
        act: (bloc) => bloc.add(
          const UserFormSubmitRequested(
            username: 'taken',
            password: 'password123',
            confirmPassword: 'password123',
            role: UserRole.cashier,
            employeeId: 7,
          ),
        ),
        expect: () => [
          isA<UserFormSubmitting>(),
          isA<UserFormError>().having(
            (s) => s.message,
            'message',
            'username_taken',
          ),
        ],
      );

      blocTest<UserFormBloc, UserFormState>(
        'emits error when password is empty for new user',
        setUp: () {
          when(
            () =>
                mockRepository.isUsernameTaken('newuser', excludeUserId: null),
          ).thenAnswer((_) async => false);
        },
        build: () => UserFormBloc(mockRepository),
        act: (bloc) => bloc.add(
          const UserFormSubmitRequested(
            username: 'newuser',
            password: '',
            confirmPassword: '',
            role: UserRole.cashier,
            employeeId: 7,
          ),
        ),
        expect: () => [
          isA<UserFormSubmitting>(),
          isA<UserFormError>().having(
            (s) => s.message,
            'message',
            'password_required',
          ),
        ],
      );

      blocTest<UserFormBloc, UserFormState>(
        'emits error when password is too short',
        setUp: () {
          when(
            () =>
                mockRepository.isUsernameTaken('newuser', excludeUserId: null),
          ).thenAnswer((_) async => false);
        },
        build: () => UserFormBloc(mockRepository),
        act: (bloc) => bloc.add(
          const UserFormSubmitRequested(
            username: 'newuser',
            password: '12345',
            confirmPassword: '12345',
            role: UserRole.cashier,
            employeeId: 7,
          ),
        ),
        expect: () => [
          isA<UserFormSubmitting>(),
          isA<UserFormError>().having(
            (s) => s.message,
            'message',
            'password_min_length',
          ),
        ],
      );

      blocTest<UserFormBloc, UserFormState>(
        'emits error when passwords do not match',
        setUp: () {
          when(
            () =>
                mockRepository.isUsernameTaken('newuser', excludeUserId: null),
          ).thenAnswer((_) async => false);
        },
        build: () => UserFormBloc(mockRepository),
        act: (bloc) => bloc.add(
          const UserFormSubmitRequested(
            username: 'newuser',
            password: 'password123',
            confirmPassword: 'different',
            role: UserRole.cashier,
            employeeId: 7,
          ),
        ),
        expect: () => [
          isA<UserFormSubmitting>(),
          isA<UserFormError>().having(
            (s) => s.message,
            'message',
            'passwords_not_match',
          ),
        ],
      );

      blocTest<UserFormBloc, UserFormState>(
        'emits success when user is created successfully',
        setUp: () {
          when(
            () =>
                mockRepository.isUsernameTaken('newuser', excludeUserId: null),
          ).thenAnswer((_) async => false);
          when(
            () => mockRepository.createUser(
              username: 'newuser',
              password: 'password123',
              role: UserRole.cashier,
              employeeId: 7,
            ),
          ).thenAnswer((_) async => testUser);
        },
        build: () => UserFormBloc(mockRepository),
        act: (bloc) => bloc.add(
          const UserFormSubmitRequested(
            username: 'newuser',
            password: 'password123',
            confirmPassword: 'password123',
            role: UserRole.cashier,
            employeeId: 7,
          ),
        ),
        expect: () => [
          isA<UserFormSubmitting>(),
          isA<UserFormSuccess>().having(
            (s) => s.message,
            'message',
            'created_success',
          ),
        ],
      );
    });

    group('UserFormSubmitRequested - Update', () {
      blocTest<UserFormBloc, UserFormState>(
        'emits success when user is updated without password change',
        setUp: () {
          when(
            () => mockRepository.isUsernameTaken('updated', excludeUserId: 1),
          ).thenAnswer((_) async => false);
          when(
            () => mockRepository.updateUser(
              id: 1,
              username: 'updated',
              password: null,
              role: UserRole.manager,
              employeeId: null,
              clearEmployeeLink: false,
            ),
          ).thenAnswer((_) async {});
        },
        build: () => UserFormBloc(mockRepository),
        act: (bloc) => bloc.add(
          const UserFormSubmitRequested(
            userId: 1,
            username: 'updated',
            password: '',
            confirmPassword: '',
            role: UserRole.manager,
          ),
        ),
        expect: () => [
          isA<UserFormSubmitting>(),
          isA<UserFormSuccess>().having(
            (s) => s.message,
            'message',
            'updated_success',
          ),
        ],
      );

      blocTest<UserFormBloc, UserFormState>(
        'emits success when user is updated with new password',
        setUp: () {
          when(
            () => mockRepository.isUsernameTaken('updated', excludeUserId: 1),
          ).thenAnswer((_) async => false);
          when(
            () => mockRepository.updateUser(
              id: 1,
              username: 'updated',
              password: 'newpass123',
              role: UserRole.manager,
              employeeId: null,
              clearEmployeeLink: false,
            ),
          ).thenAnswer((_) async {});
        },
        build: () => UserFormBloc(mockRepository),
        act: (bloc) => bloc.add(
          const UserFormSubmitRequested(
            userId: 1,
            username: 'updated',
            password: 'newpass123',
            confirmPassword: 'newpass123',
            role: UserRole.manager,
          ),
        ),
        expect: () => [
          isA<UserFormSubmitting>(),
          isA<UserFormSuccess>().having(
            (s) => s.message,
            'message',
            'updated_success',
          ),
        ],
      );
    });
  });
}
