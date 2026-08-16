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

  group('PermissionService', () {
    group('hasPermission', () {
      test('owner has all permissions', () {
        final owner = createUser(UserRole.owner);

        expect(permissionService.hasPermission(owner, 'manage_users'), isTrue);
        expect(
          permissionService.hasPermission(owner, 'manage_settings'),
          isTrue,
        );
        expect(
          permissionService.hasPermission(owner, 'view_audit_logs'),
          isTrue,
        );
        expect(
          permissionService.hasPermission(owner, 'backup_restore'),
          isTrue,
        );
      });

      test('manager has limited permissions', () {
        final manager = createUser(UserRole.manager);

        expect(
          permissionService.hasPermission(manager, 'manage_users'),
          isFalse,
        );
        expect(
          permissionService.hasPermission(manager, 'manage_employees'),
          isTrue,
        );
        expect(
          permissionService.hasPermission(manager, 'manage_sales'),
          isTrue,
        );
        expect(
          permissionService.hasPermission(manager, 'view_reports'),
          isTrue,
        );
      });

      test('cashier has sales permissions only', () {
        final cashier = createUser(UserRole.cashier);

        expect(
          permissionService.hasPermission(cashier, 'manage_sales'),
          isTrue,
        );
        expect(
          permissionService.hasPermission(cashier, 'view_customers'),
          isTrue,
        );
        expect(
          permissionService.hasPermission(cashier, 'manage_users'),
          isFalse,
        );
        expect(
          permissionService.hasPermission(cashier, 'manage_settings'),
          isFalse,
        );
        expect(
          permissionService.hasPermission(cashier, Permissions.viewProductCost),
          isFalse,
        );
      });

      test('product cost is limited to trusted financial roles', () {
        expect(
          permissionService.hasPermission(
            createUser(UserRole.owner),
            Permissions.viewProductCost,
          ),
          isTrue,
        );
        expect(
          permissionService.hasPermission(
            createUser(UserRole.manager),
            Permissions.viewProductCost,
          ),
          isTrue,
        );
        expect(
          permissionService.hasPermission(
            createUser(UserRole.accountant),
            Permissions.viewProductCost,
          ),
          isTrue,
        );
        expect(
          permissionService.hasPermission(
            createUser(UserRole.cashier),
            Permissions.viewProductCost,
          ),
          isFalse,
        );
        expect(
          permissionService.hasPermission(
            createUser(UserRole.salesperson),
            Permissions.viewProductCost,
          ),
          isFalse,
        );
      });

      test('salesperson has minimal permissions', () {
        final salesperson = createUser(UserRole.salesperson);

        expect(
          permissionService.hasPermission(salesperson, 'create_sales'),
          isTrue,
        );
        expect(
          permissionService.hasPermission(salesperson, 'view_products'),
          isTrue,
        );
        expect(
          permissionService.hasPermission(salesperson, 'manage_sales'),
          isFalse,
        );
        expect(
          permissionService.hasPermission(salesperson, 'manage_users'),
          isFalse,
        );
      });

      test('inactive user has no permissions', () {
        final inactiveOwner = createUser(UserRole.owner, isActive: false);

        expect(
          permissionService.hasPermission(inactiveOwner, 'manage_users'),
          isFalse,
        );
        expect(
          permissionService.hasPermission(inactiveOwner, 'manage_settings'),
          isFalse,
        );
      });

      test('null user has no permissions', () {
        expect(permissionService.hasPermission(null, 'manage_users'), isFalse);
      });
    });

    group('hasAnyPermission', () {
      test('returns true if user has at least one permission', () {
        final cashier = createUser(UserRole.cashier);

        expect(
          permissionService.hasAnyPermission(cashier, [
            'manage_users',
            'manage_sales',
          ]),
          isTrue,
        );
      });

      test('returns false if user has none of the permissions', () {
        final cashier = createUser(UserRole.cashier);

        expect(
          permissionService.hasAnyPermission(cashier, [
            'manage_users',
            'manage_settings',
          ]),
          isFalse,
        );
      });
    });

    group('hasAllPermissions', () {
      test('returns true if user has all permissions', () {
        final owner = createUser(UserRole.owner);

        expect(
          permissionService.hasAllPermissions(owner, [
            'manage_users',
            'manage_settings',
          ]),
          isTrue,
        );
      });

      test('returns false if user is missing any permission', () {
        final manager = createUser(UserRole.manager);

        expect(
          permissionService.hasAllPermissions(manager, [
            'manage_employees',
            'manage_users',
          ]),
          isFalse,
        );
      });
    });

    group('canAccessRoute', () {
      test('owner can access all routes', () {
        final owner = createUser(UserRole.owner);

        expect(permissionService.canAccessRoute(owner, '/settings'), isTrue);
        expect(permissionService.canAccessRoute(owner, '/users'), isTrue);
        expect(permissionService.canAccessRoute(owner, '/accounting'), isTrue);
      });

      test('manager cannot access owner-only routes', () {
        final manager = createUser(UserRole.manager);

        expect(permissionService.canAccessRoute(manager, '/settings'), isFalse);
        expect(permissionService.canAccessRoute(manager, '/users'), isFalse);
        expect(permissionService.canAccessRoute(manager, '/reports'), isTrue);
      });

      test('cashier has limited route access', () {
        final cashier = createUser(UserRole.cashier);

        expect(permissionService.canAccessRoute(cashier, '/sales'), isTrue);
        expect(permissionService.canAccessRoute(cashier, '/customers'), isTrue);
        expect(
          permissionService.canAccessRoute(cashier, '/suppliers'),
          isFalse,
        );
        expect(permissionService.canAccessRoute(cashier, '/reports'), isFalse);
        expect(
          permissionService.canAccessRoute(cashier, '/products/12/edit'),
          isFalse,
        );
        expect(
          permissionService.canAccessRoute(cashier, '/products/edit-prices'),
          isFalse,
        );
      });

      test('returns true for undefined routes', () {
        final salesperson = createUser(UserRole.salesperson);

        expect(
          permissionService.canAccessRoute(salesperson, '/unknown-route'),
          isTrue,
        );
      });
    });

    group('getPermissionsForRole', () {
      test('returns correct permissions for each role', () {
        expect(
          permissionService.getPermissionsForRole(UserRole.owner),
          contains('manage_users'),
        );
        expect(
          permissionService.getPermissionsForRole(UserRole.manager),
          isNot(contains('manage_users')),
        );
        expect(
          permissionService.getPermissionsForRole(UserRole.cashier),
          contains('manage_sales'),
        );
        expect(
          permissionService.getPermissionsForRole(UserRole.salesperson),
          contains('create_sales'),
        );
      });
    });

    group('Role Hierarchy', () {
      test('owner is at the top of hierarchy', () {
        final owner = createUser(UserRole.owner);
        expect(permissionService.getRoleLevel(UserRole.owner), equals(4));
        expect(permissionService.isRoleAtLeast(owner, UserRole.owner), isTrue);
        expect(
          permissionService.isRoleAtLeast(owner, UserRole.manager),
          isTrue,
        );
        expect(
          permissionService.isRoleAtLeast(owner, UserRole.cashier),
          isTrue,
        );
        expect(
          permissionService.isRoleAtLeast(owner, UserRole.salesperson),
          isTrue,
        );
      });

      test('manager is below owner but above cashier', () {
        final manager = createUser(UserRole.manager);
        expect(permissionService.getRoleLevel(UserRole.manager), equals(3));
        expect(
          permissionService.isRoleAtLeast(manager, UserRole.owner),
          isFalse,
        );
        expect(
          permissionService.isRoleAtLeast(manager, UserRole.manager),
          isTrue,
        );
        expect(
          permissionService.isRoleAtLeast(manager, UserRole.cashier),
          isTrue,
        );
        expect(
          permissionService.isRoleAtLeast(manager, UserRole.salesperson),
          isTrue,
        );
      });

      test('cashier is below manager but above salesperson', () {
        final cashier = createUser(UserRole.cashier);
        expect(permissionService.getRoleLevel(UserRole.cashier), equals(1));
        expect(
          permissionService.isRoleAtLeast(cashier, UserRole.owner),
          isFalse,
        );
        expect(
          permissionService.isRoleAtLeast(cashier, UserRole.manager),
          isFalse,
        );
        expect(
          permissionService.isRoleAtLeast(cashier, UserRole.cashier),
          isTrue,
        );
        expect(
          permissionService.isRoleAtLeast(cashier, UserRole.salesperson),
          isTrue,
        );
      });

      test('salesperson is at the bottom of hierarchy', () {
        final salesperson = createUser(UserRole.salesperson);
        expect(permissionService.getRoleLevel(UserRole.salesperson), equals(0));
        expect(
          permissionService.isRoleAtLeast(salesperson, UserRole.owner),
          isFalse,
        );
        expect(
          permissionService.isRoleAtLeast(salesperson, UserRole.manager),
          isFalse,
        );
        expect(
          permissionService.isRoleAtLeast(salesperson, UserRole.cashier),
          isFalse,
        );
        expect(
          permissionService.isRoleAtLeast(salesperson, UserRole.salesperson),
          isTrue,
        );
      });

      test('inactive user fails role hierarchy check', () {
        final inactiveOwner = createUser(UserRole.owner, isActive: false);
        expect(
          permissionService.isRoleAtLeast(inactiveOwner, UserRole.salesperson),
          isFalse,
        );
      });

      test('null user fails role hierarchy check', () {
        expect(
          permissionService.isRoleAtLeast(null, UserRole.salesperson),
          isFalse,
        );
      });
    });

    group('Role Promotion/Demotion', () {
      test('owner can promote any user', () {
        final owner = createUser(UserRole.owner);
        final salesperson = createUser(UserRole.salesperson);
        expect(
          permissionService.canPromoteUser(
            owner,
            salesperson,
            UserRole.cashier,
          ),
          isTrue,
        );
        expect(
          permissionService.canPromoteUser(
            owner,
            salesperson,
            UserRole.manager,
          ),
          isTrue,
        );
      });

      test('owner cannot promote to owner role', () {
        final owner = createUser(UserRole.owner);
        final manager = createUser(UserRole.manager);
        expect(
          permissionService.canPromoteUser(owner, manager, UserRole.owner),
          isFalse,
        );
      });

      test('non-owner cannot promote users', () {
        final manager = createUser(UserRole.manager);
        final salesperson = createUser(UserRole.salesperson);
        expect(
          permissionService.canPromoteUser(
            manager,
            salesperson,
            UserRole.cashier,
          ),
          isFalse,
        );
      });

      test('owner can demote users below their level', () {
        final owner = createUser(UserRole.owner);
        final manager = createUser(UserRole.manager);
        expect(
          permissionService.canDemoteUser(owner, manager, UserRole.cashier),
          isTrue,
        );
      });

      test('cannot demote to same or higher role', () {
        final owner = createUser(UserRole.owner);
        final manager = createUser(UserRole.manager);
        expect(
          permissionService.canDemoteUser(owner, manager, UserRole.manager),
          isFalse,
        );
        expect(
          permissionService.canDemoteUser(owner, manager, UserRole.owner),
          isFalse,
        );
      });
    });

    group('Permission Constants', () {
      test('Permissions class has user management constants', () {
        expect(Permissions.manageUsers, equals('manage_users'));
        expect(Permissions.promoteUsers, equals('promote_users'));
        expect(Permissions.deactivateUsers, equals('deactivate_users'));
      });

      test('Permissions class has product management constants', () {
        expect(Permissions.editProducts, equals('edit_products'));
        expect(Permissions.deleteProducts, equals('delete_products'));
        expect(Permissions.adjustStock, equals('adjust_stock'));
        expect(Permissions.manageCategories, equals('manage_categories'));
      });

      test('Permissions class has financial operation constants', () {
        expect(Permissions.viewReports, equals('view_reports'));
        expect(Permissions.manageExpenses, equals('manage_expenses'));
        expect(Permissions.accessSettings, equals('access_settings'));
        expect(Permissions.manageTaxes, equals('manage_taxes'));
      });

      test('Permissions class has sales operation constants', () {
        expect(Permissions.processSales, equals('process_sales'));
        expect(Permissions.handleReturns, equals('handle_returns'));
        expect(Permissions.viewDailyReports, equals('view_daily_reports'));
        expect(Permissions.manageDiscounts, equals('manage_discounts'));
      });
    });

    group('Comprehensive Permission Matrix', () {
      test('owner has all system permissions', () {
        final owner = createUser(UserRole.owner);
        expect(
          permissionService.hasPermission(owner, Permissions.manageUsers),
          isTrue,
        );
        expect(
          permissionService.hasPermission(owner, Permissions.promoteUsers),
          isTrue,
        );
        expect(
          permissionService.hasPermission(owner, Permissions.accessSettings),
          isTrue,
        );
        expect(
          permissionService.hasPermission(owner, Permissions.manageTaxes),
          isTrue,
        );
      });

      test('manager has business operations but not user management', () {
        final manager = createUser(UserRole.manager);
        expect(
          permissionService.hasPermission(manager, Permissions.manageUsers),
          isFalse,
        );
        expect(
          permissionService.hasPermission(manager, Permissions.promoteUsers),
          isFalse,
        );
        expect(
          permissionService.hasPermission(manager, Permissions.editProducts),
          isTrue,
        );
        expect(
          permissionService.hasPermission(manager, Permissions.viewReports),
          isTrue,
        );
        expect(
          permissionService.hasPermission(manager, Permissions.manageExpenses),
          isTrue,
        );
      });

      test('cashier has sales operations only', () {
        final cashier = createUser(UserRole.cashier);
        expect(
          permissionService.hasPermission(cashier, Permissions.processSales),
          isTrue,
        );
        expect(
          permissionService.hasPermission(cashier, Permissions.handleReturns),
          isTrue,
        );
        expect(
          permissionService.hasPermission(
            cashier,
            Permissions.viewDailyReports,
          ),
          isTrue,
        );
        expect(
          permissionService.hasPermission(cashier, Permissions.editProducts),
          isFalse,
        );
        expect(
          permissionService.hasPermission(cashier, Permissions.manageExpenses),
          isFalse,
        );
      });

      test('salesperson has limited sales permissions', () {
        final salesperson = createUser(UserRole.salesperson);
        expect(
          permissionService.hasPermission(
            salesperson,
            Permissions.processSales,
          ),
          isTrue,
        );
        expect(
          permissionService.hasPermission(
            salesperson,
            Permissions.viewDailyReports,
          ),
          isTrue,
        );
        expect(
          permissionService.hasPermission(
            salesperson,
            Permissions.handleReturns,
          ),
          isFalse,
        );
        expect(
          permissionService.hasPermission(
            salesperson,
            Permissions.editProducts,
          ),
          isFalse,
        );
      });
    });
  });
}
