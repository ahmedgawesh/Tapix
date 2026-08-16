import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/reports/services/general_ledger_service.dart';

Future<Account> _account(AppDatabase db, String code) => (db.select(
  db.accounts,
)..where((account) => account.accountCode.equals(code))).getSingle();

Future<void> _insertEntry(
  AppDatabase db, {
  required String number,
  required String status,
  required DateTime date,
  required int currencyId,
  required int cashAccountId,
  required int taxAccountId,
  required int debitTax,
  required int creditTax,
}) async {
  final amount = debitTax + creditTax;
  final entryId = await db
      .into(db.journalEntries)
      .insert(
        JournalEntriesCompanion.insert(
          entryNumber: number,
          description: 'Header $number',
          entryDate: Value(date),
          status: Value(status),
          entryType: const Value('manual'),
          totalDebitCents: Value(Decimal.fromInt(amount)),
          totalCreditCents: Value(Decimal.fromInt(amount)),
          postedAt: status == 'posted' ? Value(date) : const Value.absent(),
        ),
      );

  await db
      .into(db.journalEntryLines)
      .insert(
        JournalEntryLinesCompanion.insert(
          journalEntryId: entryId,
          accountId: taxAccountId,
          debitCents: Value(Decimal.fromInt(debitTax)),
          creditCents: Value(Decimal.fromInt(creditTax)),
          currencyId: currencyId,
          lineNumber: const Value(1),
          description: Value('Tax $number'),
        ),
      );
  await db
      .into(db.journalEntryLines)
      .insert(
        JournalEntryLinesCompanion.insert(
          journalEntryId: entryId,
          accountId: cashAccountId,
          debitCents: Value(Decimal.fromInt(creditTax)),
          creditCents: Value(Decimal.fromInt(debitTax)),
          currencyId: currencyId,
          lineNumber: const Value(2),
        ),
      );
}

void main() {
  late AppDatabase db;
  late GeneralLedgerService service;
  late int currencyId;
  late Account cash;
  late Account taxPayable;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((currency) => currency.code.equals('USD'))).getSingle()).id;
    cash = await _account(db, '1000');
    taxPayable = await _account(db, '2100');
    service = GeneralLedgerService(db);
  });

  tearDown(() => db.close());

  test(
    'uses posted journal lines with opening and natural running balance',
    () async {
      await _insertEntry(
        db,
        number: 'JE-BEFORE',
        status: 'posted',
        date: DateTime(2026, 7, 31, 12),
        currencyId: currencyId,
        cashAccountId: cash.id,
        taxAccountId: taxPayable.id,
        debitTax: 0,
        creditTax: 100,
      );
      await _insertEntry(
        db,
        number: 'JE-CREDIT',
        status: 'posted',
        date: DateTime(2026, 8, 10, 9),
        currencyId: currencyId,
        cashAccountId: cash.id,
        taxAccountId: taxPayable.id,
        debitTax: 0,
        creditTax: 300,
      );
      await _insertEntry(
        db,
        number: 'JE-DEBIT',
        status: 'posted',
        date: DateTime(2026, 8, 15, 10),
        currencyId: currencyId,
        cashAccountId: cash.id,
        taxAccountId: taxPayable.id,
        debitTax: 80,
        creditTax: 0,
      );
      await _insertEntry(
        db,
        number: 'JE-LAST-FRACTION',
        status: 'posted',
        date: DateTime(2026, 8, 31, 23, 59, 59, 999, 999),
        currencyId: currencyId,
        cashAccountId: cash.id,
        taxAccountId: taxPayable.id,
        debitTax: 0,
        creditTax: 40,
      );
      await _insertEntry(
        db,
        number: 'JE-DRAFT',
        status: 'draft',
        date: DateTime(2026, 8, 20),
        currencyId: currencyId,
        cashAccountId: cash.id,
        taxAccountId: taxPayable.id,
        debitTax: 0,
        creditTax: 700,
      );
      await _insertEntry(
        db,
        number: 'JE-NEXT-DAY',
        status: 'posted',
        date: DateTime(2026, 9, 1),
        currencyId: currencyId,
        cashAccountId: cash.id,
        taxAccountId: taxPayable.id,
        debitTax: 0,
        creditTax: 900,
      );

      final ledger = await service.load(
        accountId: taxPayable.id,
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 31),
      );

      expect(ledger.openingBalanceCents, 100);
      expect(ledger.totalDebitCents, 80);
      expect(ledger.totalCreditCents, 340);
      expect(ledger.closingBalanceCents, 360);
      expect(ledger.rows.map((row) => row.entryNumber), [
        'JE-CREDIT',
        'JE-DEBIT',
        'JE-LAST-FRACTION',
      ]);
      expect(ledger.rows.map((row) => row.runningBalanceCents), [
        400,
        320,
        360,
      ]);
      expect(ledger.rows.first.description, 'Tax JE-CREDIT');

      final cashLedger = await service.load(
        accountId: cash.id,
        startDate: DateTime(2026, 8, 1),
        endDate: DateTime(2026, 8, 31),
      );
      expect(
        cashLedger.rows
            .firstWhere((row) => row.entryNumber == 'JE-CREDIT')
            .description,
        'Header JE-CREDIT',
      );
    },
  );

  test('inventory gain 4200 displays posted surplus credits', () async {
    final gain = await _account(db, '4200');
    await _insertEntry(
      db,
      number: 'JE-INVENTORY-GAIN',
      status: 'posted',
      date: DateTime(2026, 8, 9, 12),
      currencyId: currencyId,
      cashAccountId: cash.id,
      taxAccountId: gain.id,
      debitTax: 0,
      creditTax: 12500,
    );

    final ledger = await service.load(
      accountId: gain.id,
      startDate: DateTime(2026, 8, 1),
      endDate: DateTime(2026, 8, 31),
    );

    expect(ledger.rows.single.entryNumber, 'JE-INVENTORY-GAIN');
    expect(ledger.totalCreditCents, 12500);
    expect(ledger.closingBalanceCents, 12500);
  });

  test(
    'active-account selector comes from the real chart of accounts',
    () async {
      final accounts = await service.watchActiveAccounts().first;
      expect(accounts.any((account) => account.accountCode == '2100'), isTrue);

      final customId = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              accountCode: '5999',
              accountName: 'Custom expense',
              accountType: 'expense',
              currencyId: currencyId,
            ),
          );
      final refreshed = await service.watchActiveAccounts().first;
      expect(refreshed.any((account) => account.id == customId), isTrue);
    },
  );
}
