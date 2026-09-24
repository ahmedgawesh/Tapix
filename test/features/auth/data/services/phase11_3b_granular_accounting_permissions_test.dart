import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/auth/data/services/permission_service.dart';
import 'package:tapix/features/auth/domain/entities/permission_constants.dart';
import 'package:tapix/features/auth/domain/entities/user_entity.dart';

/// Phase 11.3b — granular accounting permissions.
///
/// Three new permissions isolate the highest-blast-radius accounting
/// operations from the coarse `voidTransactions` and `manageAccounting`
/// permissions:
///
///   • [Permissions.voidJournalEntry]
///   • [Permissions.closeFiscalPeriod]
///   • [Permissions.reopenFiscalPeriod]
///
/// Default assignment: owner-only. Tests verify that:
///   1. The three constants exist and are registered in `Permissions.all`.
///   2. The constants are distinct from the legacy coarse permissions.
///   3. The owner role is granted all three by default.
///   4. NO other role (manager, accountant, cashier, salesperson) holds
///      any of the three by default — even roles that already have
///      `voidTransactions` or `manageAccounting`.
///   5. Inactive owners cannot exercise the permissions either (active
///      check upstream still applies).
void main() {
  final svc = PermissionService();

  UserEntity user(UserRole role, {bool isActive = true}) => UserEntity(
    id: 1,
    username: 'u-${role.name}',
    role: role,
    isActive: isActive,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  group('Phase 11.3b — granular accounting permissions', () {
    test('three constants exist and are unique strings', () {
      expect(Permissions.voidJournalEntry, equals('void_journal_entry'));
      expect(Permissions.closeFiscalPeriod, equals('close_fiscal_period'));
      expect(Permissions.reopenFiscalPeriod, equals('reopen_fiscal_period'));

      // They MUST be distinct from the legacy coarse permissions.
      final granular = {
        Permissions.voidJournalEntry,
        Permissions.closeFiscalPeriod,
        Permissions.reopenFiscalPeriod,
      };
      expect(granular, hasLength(3));
      expect(granular.contains(Permissions.voidTransactions), isFalse);
      expect(granular.contains(Permissions.manageAccounting), isFalse);
    });

    test('all three permissions are registered in Permissions.all', () {
      expect(Permissions.all, contains(Permissions.voidJournalEntry));
      expect(Permissions.all, contains(Permissions.closeFiscalPeriod));
      expect(Permissions.all, contains(Permissions.reopenFiscalPeriod));
    });

    test('owner role has all three granular permissions', () {
      final owner = user(UserRole.owner);
      expect(svc.hasPermission(owner, Permissions.voidJournalEntry), isTrue);
      expect(svc.hasPermission(owner, Permissions.closeFiscalPeriod), isTrue);
      expect(svc.hasPermission(owner, Permissions.reopenFiscalPeriod), isTrue);
    });

    test(
      'manager role does NOT hold any of the three (despite holding voidTransactions)',
      () {
        final manager = user(UserRole.manager);
        // Sanity: manager DOES hold the coarse void permission.
        expect(
          svc.hasPermission(manager, Permissions.voidTransactions),
          isTrue,
        );
        // But NOT any of the granular accounting ones.
        expect(
          svc.hasPermission(manager, Permissions.voidJournalEntry),
          isFalse,
        );
        expect(
          svc.hasPermission(manager, Permissions.closeFiscalPeriod),
          isFalse,
        );
        expect(
          svc.hasPermission(manager, Permissions.reopenFiscalPeriod),
          isFalse,
        );
      },
    );

    test(
      'accountant role does NOT hold any of the three (despite holding manageAccounting)',
      () {
        final accountant = user(UserRole.accountant);
        // Sanity: accountant DOES hold the coarse accounting permission.
        expect(
          svc.hasPermission(accountant, Permissions.manageAccounting),
          isTrue,
        );
        // But NOT any of the granular ones — closing a period is a
        // separate approval gate.
        expect(
          svc.hasPermission(accountant, Permissions.voidJournalEntry),
          isFalse,
        );
        expect(
          svc.hasPermission(accountant, Permissions.closeFiscalPeriod),
          isFalse,
        );
        expect(
          svc.hasPermission(accountant, Permissions.reopenFiscalPeriod),
          isFalse,
        );
      },
    );

    test('cashier and salesperson hold none of the three', () {
      for (final role in [UserRole.cashier, UserRole.salesperson]) {
        final u = user(role);
        expect(
          svc.hasPermission(u, Permissions.voidJournalEntry),
          isFalse,
          reason: '${role.name} must not void JEs',
        );
        expect(
          svc.hasPermission(u, Permissions.closeFiscalPeriod),
          isFalse,
          reason: '${role.name} must not close periods',
        );
        expect(
          svc.hasPermission(u, Permissions.reopenFiscalPeriod),
          isFalse,
          reason: '${role.name} must not reopen periods',
        );
      }
    });

    test('inactive owner cannot exercise the permissions', () {
      final inactive = user(UserRole.owner, isActive: false);
      expect(
        svc.hasPermission(inactive, Permissions.voidJournalEntry),
        isFalse,
      );
      expect(
        svc.hasPermission(inactive, Permissions.closeFiscalPeriod),
        isFalse,
      );
      expect(
        svc.hasPermission(inactive, Permissions.reopenFiscalPeriod),
        isFalse,
      );
    });
  });
}
