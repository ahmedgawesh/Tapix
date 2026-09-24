import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/datasources/journal_local_datasource.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/data/repositories/journal_repository_impl.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late JournalEntryService journal;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((row) => row.code.equals('USD'))).getSingle()).id;
    final accounting = AccountingRepository(db);
    await JournalRepositoryImpl(
      JournalLocalDatasourceImpl(db.accountingDao),
      accounting,
    ).seedDefaultAccounts(currencyId);
    journal = JournalEntryService(accounting);
  });

  tearDown(() => db.close());

  Future<int> balance(String code) async =>
      (await (db.select(
            db.accounts,
          )..where((row) => row.accountCode.equals(code))).getSingle())
          .balanceCents
          .toBigInt()
          .toInt();

  test(
    'inclusive settlement extracts tax from COGS and reverses exactly',
    () async {
      await journal.recordConsignmentObligationJournalEntry(
        obligationEventId: 1001,
        signedAmountCents: 1800,
        currencyId: currencyId,
        description: 'inclusive consignment accrual',
      );
      await journal.recordConsignmentSettlementJournalEntry(
        statementId: 2001,
        obligationSubtotalCents: 1800,
        taxCents: 164,
        totalCents: 1800,
        taxInclusive: true,
        currencyId: currencyId,
        entryDate: DateTime.utc(2026, 9, 23),
      );

      expect(await balance('2050'), 0);
      expect(await balance('2000'), 1800);
      expect(await balance('1300'), 164);
      expect(await balance('5300'), 1636);

      await journal.recordConsignmentSettlementJournalEntry(
        statementId: 2001,
        obligationSubtotalCents: 1800,
        taxCents: 164,
        totalCents: 1800,
        taxInclusive: true,
        currencyId: currencyId,
        entryDate: DateTime.utc(2026, 9, 24),
        reversal: true,
      );
      expect(await balance('2050'), 1800);
      expect(await balance('2000'), 0);
      expect(await balance('1300'), 0);
      expect(await balance('5300'), 1800);
    },
  );

  test(
    'negative settlement creates supplier credit and reverses exactly',
    () async {
      await journal.recordConsignmentObligationJournalEntry(
        obligationEventId: 1002,
        signedAmountCents: -900,
        currencyId: currencyId,
        description: 'consignment return credit',
      );
      await journal.recordConsignmentSettlementJournalEntry(
        statementId: 2002,
        obligationSubtotalCents: -900,
        taxCents: -90,
        totalCents: -990,
        taxInclusive: false,
        currencyId: currencyId,
        entryDate: DateTime.utc(2026, 9, 23),
      );

      expect(await balance('2050'), 0);
      expect(await balance('2000'), -990);
      expect(await balance('1300'), -90);
      expect(await balance('5300'), -900);

      await journal.recordConsignmentSettlementJournalEntry(
        statementId: 2002,
        obligationSubtotalCents: -900,
        taxCents: -90,
        totalCents: -990,
        taxInclusive: false,
        currencyId: currencyId,
        entryDate: DateTime.utc(2026, 9, 24),
        reversal: true,
      );
      expect(await balance('2050'), -900);
      expect(await balance('2000'), 0);
      expect(await balance('1300'), 0);
      expect(await balance('5300'), -900);
    },
  );
}
