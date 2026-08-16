import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';

const _expectedSystemAccounts = <String, String>{
  '1000': 'asset',
  '1010': 'asset',
  '1100': 'asset',
  '1200': 'asset',
  '1290': 'asset',
  '1300': 'asset',
  '1500': 'asset',
  '1510': 'asset',
  '1520': 'asset',
  '1590': 'asset',
  '2000': 'liability',
  '2100': 'liability',
  '2200': 'liability',
  '2300': 'liability',
  '2400': 'liability',
  '3000': 'equity',
  '3100': 'equity',
  '3200': 'equity',
  '4000': 'revenue',
  '4100': 'expense',
  '4200': 'revenue',
  '4900': 'revenue',
  '5100': 'expense',
  '5200': 'expense',
  '5300': 'expense',
  '5500': 'expense',
  '5600': 'expense',
  '5700': 'revenue',
  '5800': 'expense',
  '5900': 'expense',
  '6100': 'expense',
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
