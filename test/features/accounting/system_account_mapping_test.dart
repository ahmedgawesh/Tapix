import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/accounting/system_accounts.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/accounting_dao.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';

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
  test(
    'binding a non-USD branch aligns and repairs every system account',
    () async {
      final eur = await (db.select(
        db.currencies,
      )..where((currency) => currency.code.equals('EUR'))).getSingle();

      await BranchCurrencyPolicyStore(db).bind('EUR');

      final accounts = await db.select(db.accounts).get();
      final canonical = accounts
          .where(
            (account) =>
                _expectedSystemAccounts.containsKey(account.accountCode),
          )
          .toList();
      expect(canonical, hasLength(_expectedSystemAccounts.length));
      expect(canonical.map((account) => account.currencyId).toSet(), <int>{
        eur.id,
      });

      await (db.delete(
        db.accounts,
      )..where((account) => account.accountCode.equals('2050'))).go();
      await db.seedDefaultAccountsForTest();

      final restored = await (db.select(
        db.accounts,
      )..where((account) => account.accountCode.equals('2050'))).getSingle();
      expect(restored.currencyId, eur.id);
      expect(restored.isSystemAccount, isTrue);
    },
  );

  test(
    'currency binding refuses to relabel unexplained non-zero balances',
    () async {
      final accrued = await (db.select(
        db.accounts,
      )..where((account) => account.accountCode.equals('2050'))).getSingle();
      await (db.update(db.accounts)
            ..where((account) => account.id.equals(accrued.id)))
          .write(AccountsCompanion(balanceCents: Value(Decimal.fromInt(1))));

      await expectLater(
        BranchCurrencyPolicyStore(db).bind('EUR'),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'message',
            contains('refusing to reinterpret'),
          ),
        ),
      );

      final bindingCount = await db.customSelect('''
              SELECT COUNT(*) AS n FROM app_settings
              WHERE key LIKE 'business.currency.v1.%'
            ''').getSingle();
      expect(bindingCount.read<int>('n'), 0);

      final currencies = await db.customSelect('''
              SELECT DISTINCT currency_id
              FROM accounts
              WHERE account_code IN ('1000', '2050', '4000')
            ''').get();
      expect(
        currencies.map((row) => row.read<int>('currency_id')).toSet(),
        hasLength(1),
        reason: 'failed binding must roll back earlier account repairs',
      );
    },
  );
  test(
    'legacy non-USD ledger deterministically repairs the system chart currency',
    () async {
      final eur = await (db.select(
        db.currencies,
      )..where((currency) => currency.code.equals('EUR'))).getSingle();
      final cash = await (db.select(
        db.accounts,
      )..where((account) => account.accountCode.equals('1000'))).getSingle();
      final revenue = await (db.select(
        db.accounts,
      )..where((account) => account.accountCode.equals('4000'))).getSingle();

      final entryId = await db
          .into(db.journalEntries)
          .insert(
            JournalEntriesCompanion.insert(
              entryNumber: 'JE-LEGACY-EUR',
              description: 'Legacy EUR evidence',
              status: const Value('posted'),
              totalDebitCents: Value(Decimal.fromInt(100)),
              totalCreditCents: Value(Decimal.fromInt(100)),
            ),
          );
      await db
          .into(db.journalEntryLines)
          .insert(
            JournalEntryLinesCompanion.insert(
              journalEntryId: entryId,
              accountId: cash.id,
              debitCents: Value(Decimal.fromInt(100)),
              currencyId: eur.id,
            ),
          );
      await db
          .into(db.journalEntryLines)
          .insert(
            JournalEntryLinesCompanion.insert(
              journalEntryId: entryId,
              accountId: revenue.id,
              creditCents: Value(Decimal.fromInt(100)),
              currencyId: eur.id,
              lineNumber: const Value(2),
            ),
          );

      await db.seedDefaultAccountsForTest();

      final canonical = (await db.select(db.accounts).get())
          .where(
            (account) =>
                _expectedSystemAccounts.containsKey(account.accountCode),
          )
          .toList();
      expect(canonical.map((account) => account.currencyId).toSet(), <int>{
        eur.id,
      });
    },
  );
}
