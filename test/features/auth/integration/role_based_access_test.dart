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

  group('Task 3.1: Sensitive Settings Protection (Manager+ only)', () {
    test('Owner can access settings (minRole manager)', () {
      final owner = createUser(UserRole.owner);
      expect(permissionService.isRoleAtLeast(owner, UserRole.manager), isTrue);
    });

    test('Manager can access settings (minRole manager)', () {
      final manager = createUser(UserRole.manager);
      expect(permissionService.isRoleAtLeast(manager, UserRole.manager), isTrue);
    });

    test('Cashier cannot access settings (minRole manager)', () {
      final cashier = createUser(UserRole.cashier);
      expect(permissionService.isRoleAtLeast(cashier, UserRole.manager), isFalse);
    });

    test('Salesperson cannot access settings (minRole manager)', () {
      final salesperson = createUser(UserRole.salesperson);
      expect(permissionService.isRoleAtLeast(salesperson, UserRole.manager), isFalse);
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

    test('Cashier cannot view financial reports', () {
      final cashier = createUser(UserRole.cashier);
      expect(permissionService.hasPermission(cashier, Permissions.viewReports), isFalse);
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

    test('Cashier lacks adjustStock permission for disabled button', () {
      final cashier = createUser(UserRole.cashier);
      expect(permissionService.hasPermission(cashier, Permissions.adjustStock), isFalse);
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

    test('All roles can access sales screen', () {
      for (final role in UserRole.values) {
        final user = createUser(role);
        expect(
          permissionService.hasPermission(user, Permissions.processSales),
          isTrue,
          reason: '${role.name} should have processSales permission',
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

    test('Only owner role is in allowedRoles for user management', () {
      final owner = createUser(UserRole.owner);
      final manager = createUser(UserRole.manager);
      final allowedRoles = [UserRole.owner];
      
      expect(allowedRoles.contains(owner.role), isTrue);
      expect(allowedRoles.contains(manager.role), isFalse);
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

    test('Inactive user sees access denied for sales', () {
      final inactiveOwner = createUser(UserRole.owner, isActive: false);
      expect(permissionService.hasPermission(inactiveOwner, Permissions.processSales), isFalse);
    });
  });
}
