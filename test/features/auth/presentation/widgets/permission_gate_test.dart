import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/features/auth/auth.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

void main() {
  late MockAuthBloc mockAuthBloc;

  setUp(() {
    mockAuthBloc = MockAuthBloc();
  });

  UserEntity createUser(UserRole role, {bool isActive = true}) {
    return UserEntity(
      id: 1,
      username: 'testuser',
      role: role,
      isActive: isActive,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      home: BlocProvider<AuthBloc>.value(
        value: mockAuthBloc,
        child: Scaffold(body: child),
      ),
    );
  }

  group('PermissionGate', () {
    testWidgets('shows child when user has permission', (tester) async {
      final user = createUser(UserRole.owner);
      when(() => mockAuthBloc.state).thenReturn(AuthAuthenticated(user: user));
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(AuthAuthenticated(user: user)),
      );

      await tester.pumpWidget(buildTestWidget(
        const PermissionGate(
          permission: Permissions.manageUsers,
          child: Text('Protected Content'),
        ),
      ));

      expect(find.text('Protected Content'), findsOneWidget);
    });

    testWidgets('shows fallback when user lacks permission', (tester) async {
      final user = createUser(UserRole.cashier);
      when(() => mockAuthBloc.state).thenReturn(AuthAuthenticated(user: user));
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(AuthAuthenticated(user: user)),
      );

      await tester.pumpWidget(buildTestWidget(
        const PermissionGate(
          permission: Permissions.manageUsers,
          fallback: Text('Access Denied'),
          child: Text('Protected Content'),
        ),
      ));

      expect(find.text('Protected Content'), findsNothing);
      expect(find.text('Access Denied'), findsOneWidget);
    });

    testWidgets('shows nothing when no fallback and no permission',
        (tester) async {
      final user = createUser(UserRole.salesperson);
      when(() => mockAuthBloc.state).thenReturn(AuthAuthenticated(user: user));
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(AuthAuthenticated(user: user)),
      );

      await tester.pumpWidget(buildTestWidget(
        const PermissionGate(
          permission: Permissions.manageUsers,
          child: Text('Protected Content'),
        ),
      ));

      expect(find.text('Protected Content'), findsNothing);
      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('shows fallback when user is not authenticated',
        (tester) async {
      when(() => mockAuthBloc.state).thenReturn(const AuthUnauthenticated());
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(const AuthUnauthenticated()),
      );

      await tester.pumpWidget(buildTestWidget(
        const PermissionGate(
          permission: Permissions.manageUsers,
          fallback: Text('Not Logged In'),
          child: Text('Protected Content'),
        ),
      ));

      expect(find.text('Protected Content'), findsNothing);
      expect(find.text('Not Logged In'), findsOneWidget);
    });

    testWidgets('shows disabled state with tooltip when showDisabled is true',
        (tester) async {
      final user = createUser(UserRole.cashier);
      when(() => mockAuthBloc.state).thenReturn(AuthAuthenticated(user: user));
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(AuthAuthenticated(user: user)),
      );

      await tester.pumpWidget(buildTestWidget(
        PermissionGate(
          permission: Permissions.manageUsers,
          showDisabled: true,
          disabledTooltip: 'Manager access required',
          child: ElevatedButton(
            onPressed: () {},
            child: const Text('Manage Users'),
          ),
        ),
      ));

      expect(find.byType(Tooltip), findsOneWidget);
      expect(find.byType(Opacity), findsOneWidget);
    });
  });

  group('RoleGate', () {
    testWidgets('shows child when user has allowed role', (tester) async {
      final user = createUser(UserRole.manager);
      when(() => mockAuthBloc.state).thenReturn(AuthAuthenticated(user: user));
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(AuthAuthenticated(user: user)),
      );

      await tester.pumpWidget(buildTestWidget(
        const RoleGate(
          allowedRoles: [UserRole.owner, UserRole.manager],
          child: Text('Manager Content'),
        ),
      ));

      expect(find.text('Manager Content'), findsOneWidget);
    });

    testWidgets('shows fallback when user role is not allowed', (tester) async {
      final user = createUser(UserRole.cashier);
      when(() => mockAuthBloc.state).thenReturn(AuthAuthenticated(user: user));
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(AuthAuthenticated(user: user)),
      );

      await tester.pumpWidget(buildTestWidget(
        const RoleGate(
          allowedRoles: [UserRole.owner, UserRole.manager],
          fallback: Text('Managers Only'),
          child: Text('Manager Content'),
        ),
      ));

      expect(find.text('Manager Content'), findsNothing);
      expect(find.text('Managers Only'), findsOneWidget);
    });

    testWidgets('minRole allows roles at or above minimum', (tester) async {
      final manager = createUser(UserRole.manager);
      when(() => mockAuthBloc.state)
          .thenReturn(AuthAuthenticated(user: manager));
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(AuthAuthenticated(user: manager)),
      );

      await tester.pumpWidget(buildTestWidget(
        const RoleGate(
          minRole: UserRole.manager,
          child: Text('Manager+ Content'),
        ),
      ));

      expect(find.text('Manager+ Content'), findsOneWidget);
    });

    testWidgets('minRole blocks roles below minimum', (tester) async {
      final cashier = createUser(UserRole.cashier);
      when(() => mockAuthBloc.state)
          .thenReturn(AuthAuthenticated(user: cashier));
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(AuthAuthenticated(user: cashier)),
      );

      await tester.pumpWidget(buildTestWidget(
        const RoleGate(
          minRole: UserRole.manager,
          fallback: Text('Insufficient Role'),
          child: Text('Manager+ Content'),
        ),
      ));

      expect(find.text('Manager+ Content'), findsNothing);
      expect(find.text('Insufficient Role'), findsOneWidget);
    });
  });

  group('MultiPermissionGate', () {
    testWidgets('shows child when user has all required permissions',
        (tester) async {
      final user = createUser(UserRole.owner);
      when(() => mockAuthBloc.state).thenReturn(AuthAuthenticated(user: user));
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(AuthAuthenticated(user: user)),
      );

      await tester.pumpWidget(buildTestWidget(
        const MultiPermissionGate(
          permissions: [Permissions.manageUsers, Permissions.viewReports],
          requireAll: true,
          child: Text('Admin Content'),
        ),
      ));

      expect(find.text('Admin Content'), findsOneWidget);
    });

    testWidgets('shows child when user has any of the permissions',
        (tester) async {
      final user = createUser(UserRole.manager);
      when(() => mockAuthBloc.state).thenReturn(AuthAuthenticated(user: user));
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(AuthAuthenticated(user: user)),
      );

      await tester.pumpWidget(buildTestWidget(
        const MultiPermissionGate(
          permissions: [Permissions.manageUsers, Permissions.viewReports],
          requireAll: false,
          child: Text('Reports Content'),
        ),
      ));

      expect(find.text('Reports Content'), findsOneWidget);
    });

    testWidgets('shows fallback when user lacks all permissions',
        (tester) async {
      final user = createUser(UserRole.salesperson);
      when(() => mockAuthBloc.state).thenReturn(AuthAuthenticated(user: user));
      when(() => mockAuthBloc.stream).thenAnswer(
        (_) => Stream.value(AuthAuthenticated(user: user)),
      );

      await tester.pumpWidget(buildTestWidget(
        const MultiPermissionGate(
          permissions: [Permissions.manageUsers, Permissions.viewReports],
          requireAll: false,
          fallback: Text('No Access'),
          child: Text('Protected Content'),
        ),
      ));

      expect(find.text('Protected Content'), findsNothing);
      expect(find.text('No Access'), findsOneWidget);
    });
  });
}
