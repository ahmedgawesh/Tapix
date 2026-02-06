import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/auth/domain/entities/user_entity.dart';
import 'package:tapix/features/auth/domain/repositories/user_repository_interface.dart';
import 'package:tapix/features/auth/presentation/bloc/users_bloc.dart';

class MockUserRepository extends Mock implements UserRepositoryInterface {}

void main() {
  late MockUserRepository mockRepository;

  final testUsers = [
    UserEntity(
      id: 1,
      username: 'owner1',
      role: UserRole.owner,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      lastLoginAt: DateTime(2026, 1, 15),
    ),
    UserEntity(
      id: 2,
      username: 'cashier1',
      role: UserRole.cashier,
      isActive: true,
      createdAt: DateTime(2026, 1, 2),
      updatedAt: DateTime(2026, 1, 2),
    ),
    UserEntity(
      id: 3,
      username: 'manager1',
      role: UserRole.manager,
      isActive: false,
      createdAt: DateTime(2026, 1, 3),
      updatedAt: DateTime(2026, 1, 3),
    ),
  ];

  setUp(() {
    mockRepository = MockUserRepository();
  });

  group('UsersBloc', () {
    blocTest<UsersBloc, RealtimeState<List<UserEntity>>>(
      'emits RealtimeSuccess when stream emits users',
      setUp: () {
        when(() => mockRepository.watchAllUsers())
            .thenAnswer((_) => Stream.value(testUsers));
      },
      build: () => UsersBloc(mockRepository),
      expect: () => [
        isA<RealtimeSuccess<List<UserEntity>>>()
            .having((s) => s.data.length, 'data.length', 3),
      ],
    );

    blocTest<UsersBloc, RealtimeState<List<UserEntity>>>(
      'filters users by role when UserFilterByRoleRequested is added',
      setUp: () {
        when(() => mockRepository.watchAllUsers())
            .thenAnswer((_) => Stream.value(testUsers));
      },
      build: () => UsersBloc(mockRepository),
      act: (bloc) async {
        // Wait for initial data to load
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const UserFilterByRoleRequested(UserRole.owner));
      },
      skip: 1, // skip initial data load
      expect: () => [
        isA<RealtimeSuccess<List<UserEntity>>>()
            .having((s) => s.data.length, 'data.length', 1)
            .having((s) => s.data.first.role, 'role', UserRole.owner),
      ],
    );

    blocTest<UsersBloc, RealtimeState<List<UserEntity>>>(
      'filters users by search query when UserSearchRequested is added',
      setUp: () {
        when(() => mockRepository.watchAllUsers())
            .thenAnswer((_) => Stream.value(testUsers));
      },
      build: () => UsersBloc(mockRepository),
      act: (bloc) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const UserSearchRequested('cashier'));
      },
      skip: 1,
      expect: () => [
        isA<RealtimeSuccess<List<UserEntity>>>()
            .having((s) => s.data.length, 'data.length', 1)
            .having((s) => s.data.first.username, 'username', 'cashier1'),
      ],
    );

    late StreamController<List<UserEntity>> filterController;

    blocTest<UsersBloc, RealtimeState<List<UserEntity>>>(
      'clears filter when null role is requested',
      setUp: () {
        filterController = StreamController<List<UserEntity>>.broadcast();
        when(() => mockRepository.watchAllUsers())
            .thenAnswer((_) => filterController.stream);
        // Emit data once after a short delay
        Future<void>.delayed(const Duration(milliseconds: 10), () {
          filterController.add(testUsers);
        });
      },
      tearDown: () => filterController.close(),
      build: () => UsersBloc(mockRepository),
      act: (bloc) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const UserFilterByRoleRequested(UserRole.owner));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const UserFilterByRoleRequested(null));
      },
      skip: 1, // skip initial data load
      expect: () => [
        // First: filtered to owner only
        isA<RealtimeSuccess<List<UserEntity>>>()
            .having((s) => s.data.length, 'data.length', 1),
        // Then: cleared filter, all users
        isA<RealtimeSuccess<List<UserEntity>>>()
            .having((s) => s.data.length, 'data.length', 3),
      ],
    );

    blocTest<UsersBloc, RealtimeState<List<UserEntity>>>(
      'calls toggleUserActive on repository when UserToggleActiveRequested',
      setUp: () {
        when(() => mockRepository.watchAllUsers())
            .thenAnswer((_) => Stream.value(testUsers));
        when(() => mockRepository.toggleUserActive(1, false))
            .thenAnswer((_) async {});
      },
      build: () => UsersBloc(mockRepository),
      act: (bloc) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const UserToggleActiveRequested(1, false));
      },
      verify: (_) {
        verify(() => mockRepository.toggleUserActive(1, false)).called(1);
      },
    );
  });

  group('UserStatsBloc', () {
    blocTest<UserStatsBloc, RealtimeState<Map<UserRole, int>>>(
      'emits role counts from stream',
      setUp: () {
        when(() => mockRepository.watchRoleCounts()).thenAnswer(
          (_) => Stream.value({
            UserRole.owner: 1,
            UserRole.manager: 2,
            UserRole.cashier: 3,
            UserRole.salesperson: 0,
          }),
        );
      },
      build: () => UserStatsBloc(mockRepository),
      expect: () => [
        isA<RealtimeSuccess<Map<UserRole, int>>>()
            .having((s) => s.data[UserRole.owner], 'owners', 1)
            .having((s) => s.data[UserRole.manager], 'managers', 2)
            .having((s) => s.data[UserRole.cashier], 'cashiers', 3),
      ],
    );
  });
}
