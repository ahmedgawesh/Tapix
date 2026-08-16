import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/domain/services/accounting_close_service.dart';

Future<Account> _account(AppDatabase db, String code) => (db.select(
  db.accounts,
)..where((account) => account.accountCode.equals(code))).getSingle();

Future<void> _entry(
  AppDatabase db, {
  required String number,
  required DateTime date,
  required String status,
  required int currencyId,
  required int debitAccountId,
  required int creditAccountId,
  required int amount,
}) async {
  final id = await db
      .into(db.journalEntries)
      .insert(
        JournalEntriesCompanion.insert(
          entryNumber: number,
          description: number,
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
          journalEntryId: id,
          accountId: debitAccountId,
          debitCents: Value(Decimal.fromInt(amount)),
          currencyId: currencyId,
          lineNumber: const Value(1),
        ),
      );
  await db
      .into(db.journalEntryLines)
      .insert(
        JournalEntryLinesCompanion.insert(
          journalEntryId: id,
          accountId: creditAccountId,
          creditCents: Value(Decimal.fromInt(amount)),
          currencyId: currencyId,
          lineNumber: const Value(2),
        ),
      );
}

void main() {
  late AppDatabase db;
  late AccountingCloseService service;
  late int currencyId;
  late Account cash;
  late Account revenue;
  late Account expense;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((currency) => currency.code.equals('USD'))).getSingle()).id;
    cash = await _account(db, '1000');
    revenue = await _account(db, '4000');
    expense = await _account(db, '5100');
    service = AccountingCloseService(db, AccountingRepository(db));
  });

  tearDown(() => db.close());

  test(
    'close summary uses period activity and includes the whole final day',
    () async {
      final periodId = await db
          .into(db.accountingPeriods)
          .insert(
            AccountingPeriodsCompanion.insert(
              periodName: 'June 2026',
              startDate: DateTime(2026, 6, 1),
              endDate: DateTime(2026, 6, 30),
            ),
          );
      await _entry(
        db,
        number: 'JE-BEFORE',
        date: DateTime(2026, 5, 31, 12),
        status: 'posted',
        currencyId: currencyId,
        debitAccountId: cash.id,
        creditAccountId: revenue.id,
        amount: 1000,
      );
      await _entry(
        db,
        number: 'JE-REVENUE',
        date: DateTime(2026, 6, 15, 12),
        status: 'posted',
        currencyId: currencyId,
        debitAccountId: cash.id,
        creditAccountId: revenue.id,
        amount: 200,
      );
      await _entry(
        db,
        number: 'JE-EXPENSE-LAST-FRACTION',
        date: DateTime(2026, 6, 30, 23, 59, 59, 500),
        status: 'posted',
        currencyId: currencyId,
        debitAccountId: expense.id,
        creditAccountId: cash.id,
        amount: 50,
      );

      final validation = await service.validatePeriodClose(periodId);

      expect(validation.canClose, isTrue);
      expect(validation.summary!.totalRevenueCents, 200);
      expect(validation.summary!.totalExpensesCents, 50);
      expect(validation.summary!.netIncomeCents, 150);
    },
  );

  test(
    'draft entries and unposted documents on final day block close',
    () async {
      final periodId = await db
          .into(db.accountingPeriods)
          .insert(
            AccountingPeriodsCompanion.insert(
              periodName: 'June 2026',
              startDate: DateTime(2026, 6, 1),
              endDate: DateTime(2026, 6, 30),
            ),
          );
      await _entry(
        db,
        number: 'JE-DRAFT-LAST-FRACTION',
        date: DateTime(2026, 6, 30, 23, 59, 59, 500),
        status: 'draft',
        currencyId: currencyId,
        debitAccountId: cash.id,
        creditAccountId: revenue.id,
        amount: 10,
      );
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'DRAFT-SALE',
              subtotalCents: Decimal.fromInt(100),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(100),
              currencyId: currencyId,
              paymentMethod: 'cash',
              status: const Value('draft'),
              saleDate: Value(DateTime(2026, 6, 30, 23, 59, 59, 500)),
            ),
          );

      final validation = await service.validatePeriodClose(periodId);

      expect(validation.canClose, isFalse);
      expect(
        validation.blockers.map((blocker) => blocker.reasonKey),
        containsAll([
          'reports.close_blocker_draft_entries',
          'reports.close_blocker_unposted_transactions',
        ]),
      );
    },
  );

  test(
    'a period ending today cannot be closed before the day is complete',
    () async {
      final now = DateTime.now();
      final periodId = await db
          .into(db.accountingPeriods)
          .insert(
            AccountingPeriodsCompanion.insert(
              periodName: 'Today',
              startDate: DateTime(now.year, now.month, now.day),
              endDate: DateTime(now.year, now.month, now.day),
            ),
          );

      final validation = await service.validatePeriodClose(periodId);

      expect(
        validation.blockers.map((blocker) => blocker.reasonKey),
        contains('reports.close_blocker_future_period'),
      );
    },
  );
}
