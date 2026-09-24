import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:tapix/features/auth/auth.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';

@GenerateMocks([AuthRepositoryInterface])
import 'auth_bloc_test.mocks.dart';

void main() {
  late MockAuthRepositoryInterface mockRepository;

  setUp(() {
    mockRepository = MockAuthRepositoryInterface();
    when(
      mockRepository.watchCurrentUser(),
    ).thenAnswer((_) => const Stream.empty());
  });

  group('AuthBloc', () {
    final testUser = UserEntity(
      id: 1,
      username: 'testuser',
      role: UserRole.owner,
      isActive: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    group('AuthCheckRequested', () {
      blocTest<AuthBloc, RealtimeState<UserEntity?>>(
        'emits [AuthLoading, AuthNeedsSetup] when no users exist',
        build: () {
          when(mockRepository.hasAnyUsers()).thenAnswer((_) async => false);
          return AuthBloc(repository: mockRepository);
        },
        act: (bloc) => bloc.add(const AuthCheckRequested()),
        expect: () => [const AuthLoading(), const AuthNeedsSetup()],
        verify: (_) {
          verify(mockRepository.hasAnyUsers()).called(1);
        },
      );

      blocTest<AuthBloc, RealtimeState<UserEntity?>>(
        'emits [AuthLoading, AuthUnauthenticated] when users exist but no session',
        build: () {
          when(mockRepository.hasAnyUsers()).thenAnswer((_) async => true);
          when(mockRepository.getCurrentUser()).thenAnswer((_) async => null);
          return AuthBloc(repository: mockRepository);
        },
        act: (bloc) => bloc.add(const AuthCheckRequested()),
        expect: () => [const AuthLoading(), const AuthUnauthenticated()],
      );

      blocTest<AuthBloc, RealtimeState<UserEntity?>>(
        'emits [AuthLoading, AuthAuthenticated] when session exists',
        build: () {
          when(mockRepository.hasAnyUsers()).thenAnswer((_) async => true);
          when(
            mockRepository.getCurrentUser(),
          ).thenAnswer((_) async => testUser);
          return AuthBloc(repository: mockRepository);
        },
        act: (bloc) => bloc.add(const AuthCheckRequested()),
        expect: () => [const AuthLoading(), AuthAuthenticated(user: testUser)],
      );
    });

    group('AuthLoginRequested', () {
      blocTest<AuthBloc, RealtimeState<UserEntity?>>(
        'emits [AuthLoading, AuthAuthenticated] on successful login',
        build: () {
          when(
            mockRepository.login('testuser', 'password123'),
          ).thenAnswer((_) async => testUser);
          return AuthBloc(repository: mockRepository);
        },
        act: (bloc) => bloc.add(
          const AuthLoginRequested(
            username: 'testuser',
            password: 'password123',
          ),
        ),
        expect: () => [const AuthLoading(), AuthAuthenticated(user: testUser)],
      );

      blocTest<AuthBloc, RealtimeState<UserEntity?>>(
        'emits [AuthLoading, AuthError] on invalid credentials',
        build: () {
          when(
            mockRepository.login('wronguser', 'wrongpass'),
          ).thenAnswer((_) async => null);
          return AuthBloc(repository: mockRepository);
        },
        act: (bloc) => bloc.add(
          const AuthLoginRequested(
            username: 'wronguser',
            password: 'wrongpass',
          ),
        ),
        expect: () => [
          const AuthLoading(),
          const AuthError(message: 'Invalid username or password'),
        ],
      );
    });

    group('AuthLogoutRequested', () {
      blocTest<AuthBloc, RealtimeState<UserEntity?>>(
        'emits [AuthLoading, AuthUnauthenticated] on logout',
        build: () {
          when(mockRepository.logout()).thenAnswer((_) async {});
          return AuthBloc(repository: mockRepository);
        },
        act: (bloc) => bloc.add(const AuthLogoutRequested()),
        expect: () => [const AuthLoading(), const AuthUnauthenticated()],
        verify: (_) {
          verify(mockRepository.logout()).called(1);
        },
      );
    });

    group('AuthFirstOwnerCreated', () {
      blocTest<AuthBloc, RealtimeState<UserEntity?>>(
        'emits [AuthLoading, AuthAuthenticated] on successful owner creation',
        build: () {
          when(
            mockRepository.createFirstOwner('admin', 'password123'),
          ).thenAnswer((_) async => testUser);
          return AuthBloc(repository: mockRepository);
        },
        act: (bloc) => bloc.add(
          const AuthFirstOwnerCreated(
            username: 'admin',
            password: 'password123',
          ),
        ),
        expect: () => [const AuthLoading(), AuthAuthenticated(user: testUser)],
      );

      blocTest<AuthBloc, RealtimeState<UserEntity?>>(
        'emits [AuthLoading, AuthError] when owner already exists',
        build: () {
          when(
            mockRepository.createFirstOwner('admin', 'password123'),
          ).thenThrow(
            Exception('Cannot create first owner: users already exist'),
          );
          return AuthBloc(repository: mockRepository);
        },
        act: (bloc) => bloc.add(
          const AuthFirstOwnerCreated(
            username: 'admin',
            password: 'password123',
          ),
        ),
        expect: () => [const AuthLoading(), isA<AuthError>()],
      );
    });
  });
}
