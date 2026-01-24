import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tapix/features/auth/auth.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

void main() {
  late MockAuthBloc mockAuthBloc;
  late PermissionService permissionService;

  setUp(() {
    mockAuthBloc = MockAuthBloc();
    permissionService = PermissionService();
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

  Widget buildTestApp({
    required Widget child,
    required AuthState authState,
  }) {
    when(() => mockAuthBloc.state).thenReturn(authState);
    when(() => mockAuthBloc.stream).thenAnswer((_) => Stream.value(authState));

    return MaterialApp(
      home: BlocProvider<AuthBloc>.value(
        value: mockAuthBloc,
        child: child,
      ),
    );
  }

  group('Task 3.1: Sensitive Settings Protection (Manager+ only)', () {
    testWidgets('Owner can access settings screen', (tester) async {
      final owner = createUser(UserRole.owner);

      await tester.pumpWidget(buildTestApp(
        authState: AuthAuthenticated(user: owner),
        child: const Scaffold(
          body: RoleGate(
            minRole: UserRole.manager,
            fallback: AccessDeniedScreen(),
            child: Text('Settings Screen'),
          ),
        ),
      ));

      expect(find.text('Settings Screen'), findsOneWidget);
    });

    testWidgets('Manager can access settings screen', (tester) async {
      final manager = createUser(UserRole.manager);

      await tester.pumpWidget(buildTestApp(
        authState: AuthAuthenticated(user: manager),
        child: const Scaffold(
          body: RoleGate(
            minRole: UserRole.manager,
            fallback: AccessDeniedScreen(),
            child: Text('Settings Screen'),
          ),
        ),
      ));

      expect(find.text('Settings Screen'), findsOneWidget);
    });

    testWidgets('Cashier cannot access settings screen', (tester) async {
      final cashier = createUser(UserRole.cashier);

      await tester.pumpWidget(buildTestApp(
        authState: AuthAuthenticated(user: cashier),
        child: const Scaffold(
          body: RoleGate(
            minRole: UserRole.manager,
            fallback: AccessDeniedScreen(),
            child: Text('Settings Screen'),
          ),
        ),
      ));

      expect(find.text('Settings Screen'), findsNothing);
      expect(find.text('Access Denied'), findsOneWidget);
    });

    testWidgets('Salesperson cannot access settings screen', (tester) async {
      final salesperson = createUser(UserRole.salesperson);

      await tester.pumpWidget(buildTestApp(
        authState: AuthAuthenticated(user: salesperson),
        child: const Scaffold(
          body: RoleGate(
            minRole: UserRole.manager,
            fallback: AccessDeniedScreen(),
            child: Text('Settings Screen'),
          ),
        ),
      ));

      expect(find.text('Settings Screen'), findsNothing);
      expect(find.text('Access Denied'), findsOneWidget);
    });
  });

  group('Task 3.2: Financial Operations (Manager+ only)', () {
    test('Owner has financial operation permissions', () {
      final owner = createUser(UserRole.owner);
      expect(permissionService.hasPermission(owner, Permissions.viewReports), isTrue);
      expect(permissionService.hasPermission(owner, Permissions.manageExpenses), isTrue);
      expect(permissionService.hasPermission(owner, Permissions.manageTaxes), isTrue);
      expect(permissionService.hasPermission(owner, Permissions.manageAccounting), isTrue);
    });

    test('Manager has financial operation permissions', () {
      final manager = createUser(UserRole.manager);
      expect(permissionService.hasPermission(manager, Permissions.viewReports), isTrue);
      expect(permissionService.hasPermission(manager, Permissions.manageExpenses), isTrue);
      expect(permissionService.hasPermission(manager, Permissions.exportData), isTrue);
    });

    test('Cashier lacks financial operation permissions', () {
      final cashier = createUser(UserRole.cashier);
      expect(permissionService.hasPermission(cashier, Permissions.viewReports), isFalse);
      expect(permissionService.hasPermission(cashier, Permissions.manageExpenses), isFalse);
      expect(permissionService.hasPermission(cashier, Permissions.manageTaxes), isFalse);
    });

    test('Salesperson lacks financial operation permissions', () {
      final salesperson = createUser(UserRole.salesperson);
      expect(permissionService.hasPermission(salesperson, Permissions.viewReports), isFalse);
      expect(permissionService.hasPermission(salesperson, Permissions.manageExpenses), isFalse);
    });

    testWidgets('Financial reports protected with PermissionGate', (tester) async {
      final cashier = createUser(UserRole.cashier);

      await tester.pumpWidget(buildTestApp(
        authState: AuthAuthenticated(user: cashier),
        child: const Scaffold(
          body: PermissionGate(
            permission: Permissions.viewReports,
            fallback: Text('No Access to Reports'),
            child: Text('Financial Reports'),
          ),
        ),
      ));

      expect(find.text('Financial Reports'), findsNothing);
      expect(find.text('No Access to Reports'), findsOneWidget);
    });
  });

  group('Task 3.3: Stock Modification (Manager+ only)', () {
    test('Owner can modify stock', () {
      final owner = createUser(UserRole.owner);
      expect(permissionService.hasPermission(owner, Permissions.adjustStock), isTrue);
      expect(permissionService.hasPermission(owner, Permissions.editProducts), isTrue);
      expect(permissionService.hasPermission(owner, Permissions.deleteProducts), isTrue);
    });

    test('Manager can modify stock', () {
      final manager = createUser(UserRole.manager);
      expect(permissionService.hasPermission(manager, Permissions.adjustStock), isTrue);
      expect(permissionService.hasPermission(manager, Permissions.editProducts), isTrue);
      expect(permissionService.hasPermission(manager, Permissions.deleteProducts), isTrue);
    });

    test('Cashier cannot modify stock', () {
      final cashier = createUser(UserRole.cashier);
      expect(permissionService.hasPermission(cashier, Permissions.adjustStock), isFalse);
      expect(permissionService.hasPermission(cashier, Permissions.editProducts), isFalse);
      expect(permissionService.hasPermission(cashier, Permissions.deleteProducts), isFalse);
    });

    test('Salesperson cannot modify stock', () {
      final salesperson = createUser(UserRole.salesperson);
      expect(permissionService.hasPermission(salesperson, Permissions.adjustStock), isFalse);
      expect(permissionService.hasPermission(salesperson, Permissions.editProducts), isFalse);
    });

    testWidgets('Stock adjustment button disabled for cashier', (tester) async {
      final cashier = createUser(UserRole.cashier);

      await tester.pumpWidget(buildTestApp(
        authState: AuthAuthenticated(user: cashier),
        child: Scaffold(
          body: PermissionGate(
            permission: Permissions.adjustStock,
            showDisabled: true,
            disabledTooltip: 'Manager access required',
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('Adjust Stock'),
            ),
          ),
        ),
      ));

      expect(find.byType(Tooltip), findsOneWidget);
      expect(find.byType(Opacity), findsOneWidget);
    });
  });

  group('Task 3.4: Basic Sales Operations (All roles)', () {
    test('Owner can process sales', () {
      final owner = createUser(UserRole.owner);
      expect(permissionService.hasPermission(owner, Permissions.processSales), isTrue);
      expect(permissionService.hasPermission(owner, Permissions.createSales), isTrue);
    });

    test('Manager can process sales', () {
      final manager = createUser(UserRole.manager);
      expect(permissionService.hasPermission(manager, Permissions.processSales), isTrue);
      expect(permissionService.hasPermission(manager, Permissions.createSales), isTrue);
    });

    test('Cashier can process sales', () {
      final cashier = createUser(UserRole.cashier);
      expect(permissionService.hasPermission(cashier, Permissions.processSales), isTrue);
      expect(permissionService.hasPermission(cashier, Permissions.createSales), isTrue);
      expect(permissionService.hasPermission(cashier, Permissions.handleReturns), isTrue);
    });

    test('Salesperson can create sales', () {
      final salesperson = createUser(UserRole.salesperson);
      expect(permissionService.hasPermission(salesperson, Permissions.processSales), isTrue);
      expect(permissionService.hasPermission(salesperson, Permissions.createSales), isTrue);
      expect(permissionService.hasPermission(salesperson, Permissions.viewDailyReports), isTrue);
    });

    testWidgets('Sales screen accessible to all roles', (tester) async {
      for (final role in UserRole.values) {
        final user = createUser(role);

        await tester.pumpWidget(buildTestApp(
          authState: AuthAuthenticated(user: user),
          child: const Scaffold(
            body: PermissionGate(
              permission: Permissions.processSales,
              fallback: Text('No Sales Access'),
              child: Text('Sales Screen'),
            ),
          ),
        ));

        expect(
          find.text('Sales Screen'),
          findsOneWidget,
          reason: '${role.name} should access sales screen',
        );
      }
    });
  });

  group('Task 3.5: User Management (Owner only)', () {
    test('Owner has user management permissions', () {
      final owner = createUser(UserRole.owner);
      expect(permissionService.hasPermission(owner, Permissions.manageUsers), isTrue);
      expect(permissionService.hasPermission(owner, Permissions.promoteUsers), isTrue);
      expect(permissionService.hasPermission(owner, Permissions.deactivateUsers), isTrue);
    });

    test('Manager lacks user management permissions', () {
      final manager = createUser(UserRole.manager);
      expect(permissionService.hasPermission(manager, Permissions.manageUsers), isFalse);
      expect(permissionService.hasPermission(manager, Permissions.promoteUsers), isFalse);
      expect(permissionService.hasPermission(manager, Permissions.deactivateUsers), isFalse);
    });

    test('Cashier lacks user management permissions', () {
      final cashier = createUser(UserRole.cashier);
      expect(permissionService.hasPermission(cashier, Permissions.manageUsers), isFalse);
    });

    test('Salesperson lacks user management permissions', () {
      final salesperson = createUser(UserRole.salesperson);
      expect(permissionService.hasPermission(salesperson, Permissions.manageUsers), isFalse);
    });

    testWidgets('User management screen restricted to owner', (tester) async {
      final manager = createUser(UserRole.manager);

      await tester.pumpWidget(buildTestApp(
        authState: AuthAuthenticated(user: manager),
        child: const Scaffold(
          body: RoleGate(
            allowedRoles: [UserRole.owner],
            fallback: AccessDeniedScreen(
              message: 'Only owners can manage users',
            ),
            child: Text('User Management'),
          ),
        ),
      ));

      expect(find.text('User Management'), findsNothing);
      expect(find.text('Access Denied'), findsOneWidget);
    });

    testWidgets('Owner can access user management', (tester) async {
      final owner = createUser(UserRole.owner);

      await tester.pumpWidget(buildTestApp(
        authState: AuthAuthenticated(user: owner),
        child: const Scaffold(
          body: RoleGate(
            allowedRoles: [UserRole.owner],
            fallback: AccessDeniedScreen(),
            child: Text('User Management'),
          ),
        ),
      ));

      expect(find.text('User Management'), findsOneWidget);
    });
  });

  group('Route-based Access Control', () {
    test('Route permissions match role hierarchy', () {
      final owner = createUser(UserRole.owner);
      final manager = createUser(UserRole.manager);
      final cashier = createUser(UserRole.cashier);
      final salesperson = createUser(UserRole.salesperson);

      // Settings - Owner only
      expect(permissionService.canAccessRoute(owner, '/settings'), isTrue);
      expect(permissionService.canAccessRoute(manager, '/settings'), isFalse);
      expect(permissionService.canAccessRoute(cashier, '/settings'), isFalse);
      expect(permissionService.canAccessRoute(salesperson, '/settings'), isFalse);

      // Reports - Manager+
      expect(permissionService.canAccessRoute(owner, '/reports'), isTrue);
      expect(permissionService.canAccessRoute(manager, '/reports'), isTrue);
      expect(permissionService.canAccessRoute(cashier, '/reports'), isFalse);
      expect(permissionService.canAccessRoute(salesperson, '/reports'), isFalse);

      // Sales - All roles
      expect(permissionService.canAccessRoute(owner, '/sales'), isTrue);
      expect(permissionService.canAccessRoute(manager, '/sales'), isTrue);
      expect(permissionService.canAccessRoute(cashier, '/sales'), isTrue);
      expect(permissionService.canAccessRoute(salesperson, '/sales'), isTrue);
    });
  });

  group('Inactive User Access Control', () {
    test('Inactive user has no permissions regardless of role', () {
      final inactiveOwner = createUser(UserRole.owner, isActive: false);

      expect(permissionService.hasPermission(inactiveOwner, Permissions.manageUsers), isFalse);
      expect(permissionService.hasPermission(inactiveOwner, Permissions.processSales), isFalse);
      expect(permissionService.canAccessRoute(inactiveOwner, '/sales'), isFalse);
      expect(permissionService.isRoleAtLeast(inactiveOwner, UserRole.salesperson), isFalse);
    });

    testWidgets('Inactive user sees access denied', (tester) async {
      final inactiveOwner = createUser(UserRole.owner, isActive: false);

      await tester.pumpWidget(buildTestApp(
        authState: AuthAuthenticated(user: inactiveOwner),
        child: const Scaffold(
          body: PermissionGate(
            permission: Permissions.processSales,
            fallback: Text('Account Inactive'),
            child: Text('Sales'),
          ),
        ),
      ));

      expect(find.text('Sales'), findsNothing);
      expect(find.text('Account Inactive'), findsOneWidget);
    });
  });
}
