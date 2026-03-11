import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/auth/auth.dart';

void main() {
  late PermissionService permissionService;

  setUp(() {
    permissionService = PermissionService();
  });

  UserEntity createUser(
    UserRole role, {
    bool isActive = true,
    int id = 1,
  }) {
    return UserEntity(
      id: id,
      username: 'testuser',
      role: role,
      isActive: isActive,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  group('Security: Permission Bypass Prevention', () {
    group('Null User Attacks', () {
      test('null user cannot have any permission', () {
        for (final permission in Permissions.all) {
          expect(
            permissionService.hasPermission(null, permission),
            isFalse,
            reason: 'Null user should not have permission: $permission',
          );
        }
      });

      test('null user fails all role checks', () {
        for (final role in UserRole.values) {
          expect(
            permissionService.isRoleAtLeast(null, role),
            isFalse,
            reason: 'Null user should not pass role check: ${role.name}',
          );
        }
      });

      test('null user cannot access any route', () {
        final routes = [
          '/dashboard',
          '/products',
          '/sales',
          '/customers',
          '/suppliers',
          '/purchases',
          '/expenses',
          '/reports',
          '/settings',
          '/users',
          '/employees',
          '/accounting',
          '/audit',
        ];

        for (final route in routes) {
          expect(
            permissionService.canAccessRoute(null, route),
            isFalse,
            reason: 'Null user should not access route: $route',
          );
        }
      });

      test('null user cannot promote anyone', () {
        final targetUser = createUser(UserRole.salesperson);
        expect(
          permissionService.canPromoteUser(null, targetUser, UserRole.cashier),
          isFalse,
        );
      });

      test('null user cannot demote anyone', () {
        final targetUser = createUser(UserRole.manager);
        expect(
          permissionService.canDemoteUser(null, targetUser, UserRole.cashier),
          isFalse,
        );
      });
    });

    group('Inactive User Attacks', () {
      test('inactive owner has no permissions', () {
        final inactiveOwner = createUser(UserRole.owner, isActive: false);

        for (final permission in Permissions.all) {
          expect(
            permissionService.hasPermission(inactiveOwner, permission),
            isFalse,
            reason: 'Inactive owner should not have permission: $permission',
          );
        }
      });

      test('inactive user cannot access any protected route', () {
        final inactiveManager = createUser(UserRole.manager, isActive: false);

        expect(permissionService.canAccessRoute(inactiveManager, '/reports'), isFalse);
        expect(permissionService.canAccessRoute(inactiveManager, '/products'), isFalse);
        expect(permissionService.canAccessRoute(inactiveManager, '/sales'), isFalse);
      });

      test('inactive owner cannot promote users', () {
        final inactiveOwner = createUser(UserRole.owner, isActive: false);
        final targetUser = createUser(UserRole.salesperson, id: 2);

        expect(
          permissionService.canPromoteUser(inactiveOwner, targetUser, UserRole.cashier),
          isFalse,
        );
      });

      test('cannot promote inactive user', () {
        final owner = createUser(UserRole.owner);
        final inactiveTarget = createUser(UserRole.salesperson, isActive: false, id: 2);

        expect(
          permissionService.canPromoteUser(owner, inactiveTarget, UserRole.cashier),
          isFalse,
        );
      });

      test('cannot demote inactive user', () {
        final owner = createUser(UserRole.owner);
        final inactiveTarget = createUser(UserRole.manager, isActive: false, id: 2);

        expect(
          permissionService.canDemoteUser(owner, inactiveTarget, UserRole.cashier),
          isFalse,
        );
      });
    });

    group('Role Escalation Prevention', () {
      test('manager cannot promote users', () {
        final manager = createUser(UserRole.manager);
        final salesperson = createUser(UserRole.salesperson, id: 2);

        expect(
          permissionService.canPromoteUser(manager, salesperson, UserRole.cashier),
          isFalse,
        );
      });

      test('cashier cannot promote users', () {
        final cashier = createUser(UserRole.cashier);
        final salesperson = createUser(UserRole.salesperson, id: 2);

        expect(
          permissionService.canPromoteUser(cashier, salesperson, UserRole.cashier),
          isFalse,
        );
      });

      test('cannot promote user to owner role', () {
        final owner = createUser(UserRole.owner);
        final manager = createUser(UserRole.manager, id: 2);

        expect(
          permissionService.canPromoteUser(owner, manager, UserRole.owner),
          isFalse,
        );
      });

      test('cannot promote user to same role (no-op)', () {
        final owner = createUser(UserRole.owner);
        final manager = createUser(UserRole.manager, id: 2);

        expect(
          permissionService.canPromoteUser(owner, manager, UserRole.manager),
          isFalse,
        );
      });

      test('cannot promote user to lower role (use demote instead)', () {
        final owner = createUser(UserRole.owner);
        final manager = createUser(UserRole.manager, id: 2);

        expect(
          permissionService.canPromoteUser(owner, manager, UserRole.cashier),
          isFalse,
        );
      });
    });

    group('Permission Injection Prevention', () {
      test('empty permission string returns false', () {
        final owner = createUser(UserRole.owner);
        expect(permissionService.hasPermission(owner, ''), isFalse);
      });

      test('unknown permission string returns false', () {
        final owner = createUser(UserRole.owner);
        expect(permissionService.hasPermission(owner, 'unknown_permission'), isFalse);
        expect(permissionService.hasPermission(owner, 'admin'), isFalse);
        expect(permissionService.hasPermission(owner, 'root'), isFalse);
        expect(permissionService.hasPermission(owner, '*'), isFalse);
      });

      test('SQL injection attempts in permission string fail safely', () {
        final owner = createUser(UserRole.owner);
        expect(
          permissionService.hasPermission(owner, '\'; DROP TABLE users; --'),
          isFalse,
        );
        expect(
          permissionService.hasPermission(owner, '1=1; --'),
          isFalse,
        );
      });

      test('hasAnyPermission with empty list returns false', () {
        final owner = createUser(UserRole.owner);
        expect(permissionService.hasAnyPermission(owner, []), isFalse);
      });

      test('hasAllPermissions with empty list returns true (vacuous truth)', () {
        final owner = createUser(UserRole.owner);
        expect(permissionService.hasAllPermissions(owner, []), isTrue);
      });
    });

    group('Role Hierarchy Integrity', () {
      test('role levels are consistent', () {
        expect(permissionService.getRoleLevel(UserRole.salesperson), equals(0));
        expect(permissionService.getRoleLevel(UserRole.cashier), equals(1));
        expect(permissionService.getRoleLevel(UserRole.accountant), equals(2));
        expect(permissionService.getRoleLevel(UserRole.manager), equals(3));
        expect(permissionService.getRoleLevel(UserRole.owner), equals(4));
      });

      test('higher roles include lower role access', () {
        final owner = createUser(UserRole.owner);
        final manager = createUser(UserRole.manager);
        final cashier = createUser(UserRole.cashier);
        final salesperson = createUser(UserRole.salesperson);

        // Owner >= all roles
        expect(permissionService.isRoleAtLeast(owner, UserRole.owner), isTrue);
        expect(permissionService.isRoleAtLeast(owner, UserRole.manager), isTrue);
        expect(permissionService.isRoleAtLeast(owner, UserRole.cashier), isTrue);
        expect(permissionService.isRoleAtLeast(owner, UserRole.salesperson), isTrue);

        // Manager >= manager, cashier, salesperson but not owner
        expect(permissionService.isRoleAtLeast(manager, UserRole.owner), isFalse);
        expect(permissionService.isRoleAtLeast(manager, UserRole.manager), isTrue);
        expect(permissionService.isRoleAtLeast(manager, UserRole.cashier), isTrue);
        expect(permissionService.isRoleAtLeast(manager, UserRole.salesperson), isTrue);

        // Cashier >= cashier, salesperson but not manager, owner
        expect(permissionService.isRoleAtLeast(cashier, UserRole.owner), isFalse);
        expect(permissionService.isRoleAtLeast(cashier, UserRole.manager), isFalse);
        expect(permissionService.isRoleAtLeast(cashier, UserRole.cashier), isTrue);
        expect(permissionService.isRoleAtLeast(cashier, UserRole.salesperson), isTrue);

        // Salesperson only >= salesperson
        expect(permissionService.isRoleAtLeast(salesperson, UserRole.owner), isFalse);
        expect(permissionService.isRoleAtLeast(salesperson, UserRole.manager), isFalse);
        expect(permissionService.isRoleAtLeast(salesperson, UserRole.cashier), isFalse);
        expect(permissionService.isRoleAtLeast(salesperson, UserRole.salesperson), isTrue);
      });
    });

    group('Demotion Security', () {
      test('non-owner cannot demote users', () {
        final manager = createUser(UserRole.manager);
        final cashier = createUser(UserRole.cashier, id: 2);

        expect(
          permissionService.canDemoteUser(manager, cashier, UserRole.salesperson),
          isFalse,
        );
      });

      test('cannot demote to same role', () {
        final owner = createUser(UserRole.owner);
        final manager = createUser(UserRole.manager, id: 2);

        expect(
          permissionService.canDemoteUser(owner, manager, UserRole.manager),
          isFalse,
        );
      });

      test('cannot demote to higher role', () {
        final owner = createUser(UserRole.owner);
        final cashier = createUser(UserRole.cashier, id: 2);

        expect(
          permissionService.canDemoteUser(owner, cashier, UserRole.manager),
          isFalse,
        );
        expect(
          permissionService.canDemoteUser(owner, cashier, UserRole.owner),
          isFalse,
        );
      });
    });
  });
}
