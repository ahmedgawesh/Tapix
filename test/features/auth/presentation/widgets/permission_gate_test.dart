import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/auth/auth.dart';

void main() {
  late PermissionService permissionService;

  setUp(() {
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

  group('PermissionGate Logic', () {
    test('owner has manageUsers permission', () {
      final user = createUser(UserRole.owner);
      expect(
        permissionService.hasPermission(user, Permissions.manageUsers),
        isTrue,
      );
    });

    test('cashier lacks manageUsers permission', () {
      final user = createUser(UserRole.cashier);
      expect(
        permissionService.hasPermission(user, Permissions.manageUsers),
        isFalse,
      );
    });

    test('salesperson lacks manageUsers permission', () {
      final user = createUser(UserRole.salesperson);
      expect(
        permissionService.hasPermission(user, Permissions.manageUsers),
        isFalse,
      );
    });

    test('inactive user has no permissions', () {
      final user = createUser(UserRole.owner, isActive: false);
      expect(
        permissionService.hasPermission(user, Permissions.manageUsers),
        isFalse,
      );
    });
  });

  group('RoleGate Logic', () {
    test('manager meets minRole of manager', () {
      final user = createUser(UserRole.manager);
      expect(permissionService.isRoleAtLeast(user, UserRole.manager), isTrue);
    });

    test('owner meets minRole of manager', () {
      final user = createUser(UserRole.owner);
      expect(permissionService.isRoleAtLeast(user, UserRole.manager), isTrue);
    });

    test('cashier does not meet minRole of manager', () {
      final user = createUser(UserRole.cashier);
      expect(permissionService.isRoleAtLeast(user, UserRole.manager), isFalse);
    });

    test('salesperson does not meet minRole of manager', () {
      final user = createUser(UserRole.salesperson);
      expect(permissionService.isRoleAtLeast(user, UserRole.manager), isFalse);
    });

    test('inactive user does not meet any minRole', () {
      final user = createUser(UserRole.owner, isActive: false);
      expect(
        permissionService.isRoleAtLeast(user, UserRole.salesperson),
        isFalse,
      );
    });
  });

  group('MultiPermissionGate Logic', () {
    test('owner has all required permissions', () {
      final user = createUser(UserRole.owner);
      expect(
        permissionService.hasAllPermissions(user, [
          Permissions.manageUsers,
          Permissions.viewReports,
        ]),
        isTrue,
      );
    });

    test('manager has viewReports but not manageUsers', () {
      final user = createUser(UserRole.manager);
      expect(
        permissionService.hasPermission(user, Permissions.viewReports),
        isTrue,
      );
      expect(
        permissionService.hasPermission(user, Permissions.manageUsers),
        isFalse,
      );
      expect(
        permissionService.hasAnyPermission(user, [
          Permissions.manageUsers,
          Permissions.viewReports,
        ]),
        isTrue,
      );
    });

    test('salesperson lacks all admin permissions', () {
      final user = createUser(UserRole.salesperson);
      expect(
        permissionService.hasAnyPermission(user, [
          Permissions.manageUsers,
          Permissions.viewReports,
        ]),
        isFalse,
      );
    });
  });
}
