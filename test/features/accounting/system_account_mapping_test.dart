import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/accounting/system_accounts.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';

final _expectedSystemAccounts = <String, String>{
  for (final account in systemAccountDefinitions)
    account['code']! as String: account['type']! as String,
};

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  test(
    'every required posting account exists with the correct type and lock',
    () async {
      final accounts = await db.select(db.accounts).get();
      final byCode = {
        for (final account in accounts) account.accountCode: account,
      };

      expect(
        byCode.keys.where(_expectedSystemAccounts.containsKey).toSet(),
        _expectedSystemAccounts.keys.toSet(),
      );
      for (final entry in _expectedSystemAccounts.entries) {
        final account = byCode[entry.key]!;
        expect(
          account.accountType,
          entry.value,
          reason: 'account ${entry.key}',
        );
        expect(account.isSystemAccount, isTrue, reason: 'account ${entry.key}');
        expect(account.isActive, isTrue, reason: 'account ${entry.key}');
      }
    },
  );

  test(
    'opening repair restores a missing consignment accrued account',
    () async {
      await (db.delete(
        db.accounts,
      )..where((account) => account.accountCode.equals('2050'))).go();

      expect(
        await (db.select(db.accounts)
              ..where((account) => account.accountCode.equals('2050')))
            .getSingleOrNull(),
        isNull,
      );

      await db.seedDefaultAccountsForTest();

      final restored = await (db.select(
        db.accounts,
      )..where((account) => account.accountCode.equals('2050'))).getSingle();
      expect(restored.accountName, 'Accrued Consignment Payable');
      expect(restored.accountType, 'liability');
      expect(restored.isSystemAccount, isTrue);
      expect(restored.isActive, isTrue);
      expect(restored.balanceCents, Decimal.zero);
    },
  );

  test('opening the database repairs legacy system-account metadata', () async {
    final cash = await (db.select(
      db.accounts,
    )..where((account) => account.accountCode.equals('1000'))).getSingle();
    await (db.update(
      db.accounts,
    )..where((account) => account.id.equals(cash.id))).write(
      const AccountsCompanion(
        accountType: Value('expense'),
        isSystemAccount: Value(false),
        isActive: Value(false),
        displayOrder: Value(999),
      ),
    );

    await db.seedDefaultAccountsForTest();

    final repaired = await (db.select(
      db.accounts,
    )..where((account) => account.id.equals(cash.id))).getSingle();
    expect(repaired.accountType, 'asset');
    expect(repaired.isSystemAccount, isTrue);
    expect(repaired.isActive, isTrue);
    expect(repaired.displayOrder, 1);
  });

  test(
    'system posting accounts cannot be edited or deleted through CRUD',
    () async {
      final cash = await (db.select(
        db.accounts,
      )..where((account) => account.accountCode.equals('1000'))).getSingle();
      final dao = AccountingDao(db);

      await expectLater(
        dao.updateAccount(cash.copyWith(accountName: 'Unsafe rename')),
        throwsA(isA<StateError>()),
      );
      await expectLater(dao.deleteAccount(cash.id), throwsA(isA<StateError>()));

      expect(
        await (db.select(
          db.accounts,
        )..where((account) => account.id.equals(cash.id))).getSingleOrNull(),
        isNotNull,
      );
    },
  );
}
