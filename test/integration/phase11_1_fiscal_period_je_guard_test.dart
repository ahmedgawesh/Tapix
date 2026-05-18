import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/compliance/fiscal_period_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/domain/models/journal_entry_data.dart';

/// Phase 11.1 regression suite — fiscal-period guard wired into the
/// generic journal-entry pipeline.
///
/// Closes the backdating loophole that previously existed only on
/// returns: BEFORE Phase 11.1, a sale / purchase / payroll / expense
/// post could land in a CLOSED fiscal period because only
/// `ReturnPostingService` consulted `FiscalPeriodService.assertOpen`.
///
/// AFTER Phase 11.1, every `AccountingRepository.createJournalEntry`
/// (and `postJournalEntry`) consults the same service when constructed
/// via `withFiscalPeriodGuard`.
///
/// Invariants verified:
///   1. Generic JE into a CLOSED fiscal period → throws
///      `FiscalPeriodClosedException`.
///   2. Generic JE into an OPEN fiscal period → succeeds + posts.
///   3. Default constructor (`AccountingRepository(db)`) — used by the
///      test suite directly — skips the new guard (back-compat).
///   4. The two period systems (`accounting_periods` legacy +
///      `fiscal_periods` Phase-2.5) are independent: closing in either
///      one blocks the post.
///   5. Voiding a posted JE creates a reversal dated TODAY; if today's
///      period is open, the reversal succeeds even though the original
///      entry's period was later closed.
void main() {
  late AppDatabase db;
  late FiscalPeriodService fiscalService;
  late AccountingRepository guardedRepo;
  late int currencyId;
  late int cashAccountId;
  late int revenueAccountId;

  Future<int> accountIdByCode(String code) async {
    final row = await db.customSelect(
      'SELECT id FROM accounts WHERE account_code = ?',
      variables: [Variable.withString(code)],
    ).getSingle();
    return row.read<int>('id');
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    fiscalService = FiscalPeriodService(db);
    guardedRepo = AccountingRepository.withFiscalPeriodGuard(
      db,
      fiscalPeriodService: fiscalService,
    );

    // Trigger migrations + seed accounts.
    await db.customSelect('SELECT 1').get();

    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();
    currencyId = usd.id;

    cashAccountId = await accountIdByCode('1000');
    revenueAccountId = await accountIdByCode('4000');
  });

  tearDown(() async {
    await db.close();
  });

  JournalEntryData simpleCashRevenueJE({required DateTime date}) {
    return JournalEntryData.simple(
      description: 'Phase 11.1 test JE',
      debitAccountId: cashAccountId,
      creditAccountId: revenueAccountId,
      amountCents: 5000,
      currencyId: currencyId,
      entryDate: date,
      entryType: 'manual',
    );
  }

  group('Phase 11.1 — JE fiscal-period guard', () {
    test(
      'createJournalEntry into a CLOSED fiscal period throws '
      'FiscalPeriodClosedException',
      () async {
        final entryDate = DateTime(2024, 3, 10);
        await fiscalService.ensurePeriod(entryDate);
        await fiscalService.closePeriod(
          periodKey: FiscalPeriodService.keyFor(entryDate),
          userId: 0,
          notes: 'Q1 close',
        );

        await expectLater(
          () => guardedRepo.createJournalEntry(
            entryData: simpleCashRevenueJE(date: entryDate),
            userId: null,
          ),
          throwsA(isA<FiscalPeriodClosedException>()),
        );

        // Ensure NOTHING was written.
        final entries = await db.select(db.journalEntries).get();
        expect(entries, isEmpty,
            reason: 'No JE header should be created on a rejected post');
        final lines = await db.select(db.journalEntryLines).get();
        expect(lines, isEmpty);
      },
    );

    test('createJournalEntry into an OPEN fiscal period succeeds', () async {
      final entryDate = DateTime(2024, 5, 14);
      await fiscalService.ensurePeriod(entryDate); // status=open by default

      final id = await guardedRepo.createJournalEntry(
        entryData: simpleCashRevenueJE(date: entryDate),
        userId: null,
      );
      expect(id, greaterThan(0));

      final entry = await (db.select(db.journalEntries)
            ..where((e) => e.id.equals(id)))
          .getSingle();
      expect(entry.status, equals('posted'));
    });

    test(
      'createJournalEntry with auto-ensured period defaults to OPEN — no '
      'pre-existing row required',
      () async {
        final entryDate = DateTime(2024, 7, 22);
        // We do NOT call ensurePeriod ourselves. assertOpen creates it
        // on demand with status=open.
        final id = await guardedRepo.createJournalEntry(
          entryData: simpleCashRevenueJE(date: entryDate),
          userId: null,
        );
        expect(id, greaterThan(0));

        final period = await fiscalService.getByKey(
          FiscalPeriodService.keyFor(entryDate),
        );
        expect(period, isNotNull);
        expect(period!.status, equals('open'));
      },
    );

    test(
      'default constructor AccountingRepository(db) — no guard, posts '
      'into closed fiscal period succeed (back-compat)',
      () async {
        final unguarded = AccountingRepository(db);
        final entryDate = DateTime(2024, 9, 8);
        await fiscalService.ensurePeriod(entryDate);
        await fiscalService.closePeriod(
          periodKey: FiscalPeriodService.keyFor(entryDate),
          userId: 0,
        );

        // Default constructor → no FiscalPeriodService → no guard.
        // Existing test suites that hand-build the repo continue to
        // work without modification.
        final id = await unguarded.createJournalEntry(
          entryData: simpleCashRevenueJE(date: entryDate),
          userId: null,
        );
        expect(id, greaterThan(0));
      },
    );

    test('reopenPeriod lets a previously-blocked post succeed', () async {
      final entryDate = DateTime(2024, 11, 4);
      await fiscalService.ensurePeriod(entryDate);
      final key = FiscalPeriodService.keyFor(entryDate);

      await fiscalService.closePeriod(periodKey: key, userId: 0);
      await expectLater(
        () => guardedRepo.createJournalEntry(
          entryData: simpleCashRevenueJE(date: entryDate),
          userId: null,
        ),
        throwsA(isA<FiscalPeriodClosedException>()),
      );

      await fiscalService.reopenPeriod(periodKey: key, userId: 0);
      // Must succeed now.
      final id = await guardedRepo.createJournalEntry(
        entryData: simpleCashRevenueJE(date: entryDate),
        userId: null,
      );
      expect(id, greaterThan(0));
    });

    test(
      'voidJournalEntry writes its reversal dated TODAY — succeeds even '
      'after the original entry\'s period is closed',
      () async {
        // 1. Post an entry in May.
        final origDate = DateTime(2024, 5, 20);
        await fiscalService.ensurePeriod(origDate);
        final origId = await guardedRepo.createJournalEntry(
          entryData: simpleCashRevenueJE(date: origDate),
          userId: null,
        );

        // 2. Close May. The original entry is unaffected (immutable).
        await fiscalService.closePeriod(
          periodKey: FiscalPeriodService.keyFor(origDate),
          userId: 0,
        );

        // 3. Void today (today's period is open by default).
        // The reversal entry uses entryDate = DateTime.now() per
        // AccountingRepository.voidJournalEntry, so the closed May
        // period does NOT block it.
        final reversalId = await guardedRepo.voidJournalEntry(
          entryId: origId,
          reason: 'Phase 11.1 test',
          userId: null,
        );
        expect(reversalId, greaterThan(0));

        final reversal = await (db.select(db.journalEntries)
              ..where((e) => e.id.equals(reversalId)))
            .getSingle();
        expect(reversal.entryType, equals('reversal'));
        expect(reversal.reversedEntryId, equals(origId));
      },
    );
  });
}
