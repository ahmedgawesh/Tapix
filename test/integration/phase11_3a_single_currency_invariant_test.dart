import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/accounting/domain/exceptions/accounting_exception.dart';
import 'package:tapix/features/accounting/domain/models/journal_entry_data.dart';

/// Phase 11.3a — single-currency invariant.
///
/// AccountingRepository.createJournalEntry is the canonical writer of
/// `accounts.balance_cents`. It MUST refuse any journal entry whose lines
/// span more than one currency. Cross-currency postings demand explicit
/// FX-conversion entries that the current chart of accounts does not
/// model (no realised / unrealised FX gain-loss accounts seeded), so
/// silently accepting them would produce a mathematically balanced but
/// economically meaningless ledger.
///
/// Invariants verified:
///   1. A balanced two-line JE in a single currency posts successfully.
///   2. A balanced two-line JE that mixes USD + EUR throws
///      AccountingException with a "mixes currencies" message and
///      writes nothing.
///   3. The guard fires BEFORE the double-entry-balance check would have
///      passed — i.e. even mathematically balanced cross-currency
///      attempts are rejected.
///   4. A JE with multiple lines but a single currency (3+ lines, same
///      currencyId everywhere) still succeeds.
void main() {
  late AppDatabase db;
  late AccountingRepository repo;
  late int usdId;
  late int eurId;
  late int cashAccountId;
  late int revenueAccountId;

  Future<int> accountIdByCode(String code) async {
    final row = await db
        .customSelect(
          'SELECT id FROM accounts WHERE account_code = ?',
          variables: [Variable.withString(code)],
        )
        .getSingle();
    return row.read<int>('id');
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    repo = AccountingRepository(db);

    // Trigger migrations + seed accounts + seed default currencies.
    await db.customSelect('SELECT 1').get();

    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    usdId = usd.id;

    final eur = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('EUR'))).getSingle();
    eurId = eur.id;

    cashAccountId = await accountIdByCode('1000');
    revenueAccountId = await accountIdByCode('4000');
  });

  tearDown(() async {
    await db.close();
  });

  group('Phase 11.3a — single-currency invariant', () {
    test('balanced single-currency JE posts successfully', () async {
      final id = await repo.createJournalEntry(
        entryData: JournalEntryData(
          description: 'Single-currency JE',
          entryDate: DateTime.now(),
          autoPost: true,
          lines: [
            JournalEntryLineData(
              accountId: cashAccountId,
              debitCents: 5000,
              creditCents: 0,
              currencyId: usdId,
            ),
            JournalEntryLineData(
              accountId: revenueAccountId,
              debitCents: 0,
              creditCents: 5000,
              currencyId: usdId,
            ),
          ],
        ),
        userId: null,
      );
      expect(id, greaterThan(0));
    });

    test('balanced cross-currency JE is rejected', () async {
      expect(
        () => repo.createJournalEntry(
          entryData: JournalEntryData(
            description: 'Cross-currency JE',
            entryDate: DateTime.now(),
            autoPost: true,
            lines: [
              JournalEntryLineData(
                accountId: cashAccountId,
                debitCents: 5000,
                creditCents: 0,
                currencyId: usdId,
              ),
              JournalEntryLineData(
                accountId: revenueAccountId,
                debitCents: 0,
                creditCents: 5000,
                currencyId: eurId,
              ),
            ],
          ),
          userId: null,
        ),
        throwsA(
          isA<AccountingException>().having(
            (e) => e.toString(),
            'message',
            contains('mixes currencies'),
          ),
        ),
      );

      // Nothing was written.
      final entries = await db.select(db.journalEntries).get();
      expect(entries, isEmpty);
      final lines = await db.select(db.journalEntryLines).get();
      expect(lines, isEmpty);
    });

    test('cross-currency rejection fires even when math is balanced', () async {
      // Same totals on both sides — but currencies differ. The
      // mathematics is fine; the economics is not. Phase 11.3a
      // must reject this BEFORE accepting it.
      expect(
        () => repo.createJournalEntry(
          entryData: JournalEntryData(
            description: 'Balanced cross-currency JE',
            entryDate: DateTime.now(),
            autoPost: false,
            lines: [
              JournalEntryLineData(
                accountId: cashAccountId,
                debitCents: 10000,
                creditCents: 0,
                currencyId: usdId,
              ),
              JournalEntryLineData(
                accountId: revenueAccountId,
                debitCents: 0,
                creditCents: 10000,
                currencyId: eurId,
              ),
            ],
          ),
          userId: null,
        ),
        throwsA(isA<AccountingException>()),
      );
    });

    test('multi-line same-currency JE still succeeds', () async {
      final expenseId = await accountIdByCode('5100');
      final id = await repo.createJournalEntry(
        entryData: JournalEntryData(
          description: '3-line same-currency JE',
          entryDate: DateTime.now(),
          autoPost: true,
          lines: [
            JournalEntryLineData(
              accountId: cashAccountId,
              debitCents: 0,
              creditCents: 7000,
              currencyId: usdId,
            ),
            JournalEntryLineData(
              accountId: expenseId,
              debitCents: 3000,
              creditCents: 0,
              currencyId: usdId,
            ),
            JournalEntryLineData(
              accountId: revenueAccountId,
              debitCents: 4000,
              creditCents: 0,
              currencyId: usdId,
            ),
          ],
        ),
        userId: null,
      );
      expect(id, greaterThan(0));
    });
  });
}
