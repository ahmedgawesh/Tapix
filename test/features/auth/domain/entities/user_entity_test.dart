import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/auth/auth.dart';

void main() {
  group('UserRole', () {
    test('fromString parses valid roles', () {
      expect(UserRole.fromString('owner'), UserRole.owner);
      expect(UserRole.fromString('manager'), UserRole.manager);
      expect(UserRole.fromString('cashier'), UserRole.cashier);
      expect(UserRole.fromString('salesperson'), UserRole.salesperson);
    });

    test('fromString is case-insensitive', () {
      expect(UserRole.fromString('OWNER'), UserRole.owner);
      expect(UserRole.fromString('Manager'), UserRole.manager);
      expect(UserRole.fromString('CASHIER'), UserRole.cashier);
    });

    test('fromString returns salesperson for invalid value', () {
      expect(UserRole.fromString('invalid'), UserRole.salesperson);
      expect(UserRole.fromString(''), UserRole.salesperson);
    });
  });

  group('UserEntity', () {
    late UserEntity user;

    setUp(() {
      user = UserEntity(
        id: 1,
        username: 'testuser',
        role: UserRole.manager,
        employeeId: 10,
        isActive: true,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 2),
        lastLoginAt: DateTime(2024, 1, 3),
      );
    });

    test('role check getters work correctly', () {
      expect(user.isOwner, isFalse);
      expect(user.isManager, isTrue);
      expect(user.isCashier, isFalse);
      expect(user.isSalesperson, isFalse);

      final owner = user.copyWith(role: UserRole.owner);
      expect(owner.isOwner, isTrue);
      expect(owner.isManager, isFalse);
    });

    test('hasPermission checks role hierarchy', () {
      final owner = user.copyWith(role: UserRole.owner);
      final manager = user.copyWith(role: UserRole.manager);
      final cashier = user.copyWith(role: UserRole.cashier);
      final salesperson = user.copyWith(role: UserRole.salesperson);

      expect(owner.hasPermission(UserRole.owner), isTrue);
      expect(owner.hasPermission(UserRole.manager), isTrue);
      expect(owner.hasPermission(UserRole.cashier), isTrue);
      expect(owner.hasPermission(UserRole.salesperson), isTrue);

      expect(manager.hasPermission(UserRole.owner), isFalse);
      expect(manager.hasPermission(UserRole.manager), isTrue);
      expect(manager.hasPermission(UserRole.cashier), isTrue);

      expect(cashier.hasPermission(UserRole.manager), isFalse);
      expect(cashier.hasPermission(UserRole.cashier), isTrue);

      expect(salesperson.hasPermission(UserRole.cashier), isFalse);
      expect(salesperson.hasPermission(UserRole.salesperson), isTrue);
    });

    test('copyWith creates new instance with updated values', () {
      final updated = user.copyWith(
        username: 'newuser',
        role: UserRole.owner,
        isActive: false,
      );

      expect(updated.id, user.id);
      expect(updated.username, 'newuser');
      expect(updated.role, UserRole.owner);
      expect(updated.isActive, isFalse);
      expect(updated.employeeId, user.employeeId);
    });

    test('equality works correctly', () {
      final user1 = UserEntity(
        id: 1,
        username: 'test',
        role: UserRole.owner,
        isActive: true,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

      final user2 = UserEntity(
        id: 1,
        username: 'test',
        role: UserRole.owner,
        isActive: true,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

      final user3 = UserEntity(
        id: 2,
        username: 'test',
        role: UserRole.owner,
        isActive: true,
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      );

      expect(user1, equals(user2));
      expect(user1, isNot(equals(user3)));
    });
  });
}
