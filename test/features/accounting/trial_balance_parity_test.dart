// ════════════════════════════════════════════════════════════════════════════
// TRIAL BALANCE CLASSIFICATION SPEC
// ════════════════════════════════════════════════════════════════════════════
//
// Purpose
// -------
// Pin the classification rules used by `getTrialBalance` in
//   `lib/features/accounting/data/repositories/accounting_repository.dart`.
//
// History
// -------
// Originally Phase 0 of the scattered-calculation migration: two parallel
// implementations of this logic existed (one in `AccountingRepository`,
// one in `JournalRepositoryImpl`). This file pinned their identical
// behaviour so the Phase-1 consolidation could not silently regress.
//
// After Phase 1 (May 2026, see docs/adr/0001-pricing-engines-as-sot.md):
// only `AccountingRepository.getTrialBalance` survives; the
// `JournalRepositoryImpl` copy now delegates to it. The spec is preserved
// here as a contract test against the surviving implementation, driven
// through an in-memory database (the same data path production uses).
//
// Strategy
// --------
// 1. `_classifyRawBalance(raw, type)` is the pure function mirroring the
//    classification block in `accounting_repository.dart`. We test it
//    directly against a curated table of cases.
// 2. Drive `AccountingRepository.getTrialBalance()` against an in-memory
//    `AppDatabase` seeded with custom accounts + posted journal entries,
//    and assert each returned `TrialBalanceItem` agrees with the pure
//    function.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

// ─── Pure classification spec (extracted from both repositories) ─────────────

/// (debit, credit) columns for a given raw journal-line balance and account
/// type. Mirrors the logic in:
///   - accounting_repository.dart:500-519
///   - journal_repository_impl.dart:417-436
///
/// `rawBalance = Σ debit − Σ credit` across the account's posted lines.
(int debit, int credit) _classifyRawBalance(int rawBalance, String type) {
  final t = type.toLowerCase();
  if (t == 'asset' || t == 'expense') {
    // Normal debit balance: positive raw → debit col; negative raw → credit col (abs).
    if (rawBalance >= 0) return (rawBalance, 0);
    return (0, -rawBalance);
  }
  // Liability / Equity / Revenue: normal credit balance.
  // naturalBalance = -rawBalance. Positive → credit col; negative → debit col (abs).
  final natural = -rawBalance;
  if (natural >= 0) return (0, natural);
  return (-natural, 0);
}

// ─── In-memory database helpers ─────────────────────────────────────────

/// Insert a custom account row, returning its assigned ID.
/// Uses an account code outside the auto-seeded chart-of-accounts range
/// (1000-5900) to avoid colliding with `seedDefaultAccounts`.
Future<int> _insertAccount(
  AppDatabase db, {
  required String code,
  required String name,
  required String type,
  required int currencyId,
}) async {
  return db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          accountCode: code,
          accountName: name,
          accountType: type,
          currencyId: currencyId,
        ),
      );
}

/// Insert a posted journal entry header + its lines.
///
/// Bypasses [AccountingRepository.createJournalEntry] on purpose: the
/// purpose of this fixture is to feed the trial-balance query a known set
/// of raw `journal_entry_lines`, not to re-test the JE creation pipeline.
Future<void> _insertPostedEntry(
  AppDatabase db, {
  required String entryNumber,
  required String description,
  required DateTime entryDate,
  required int currencyId,
  required List<({int accountId, int debit, int credit})> lines,
}) async {
  final totalDebits = lines.fold<int>(0, (s, l) => s + l.debit);
  final totalCredits = lines.fold<int>(0, (s, l) => s + l.credit);
  final entryId = await db
      .into(db.journalEntries)
      .insert(
        JournalEntriesCompanion.insert(
          entryNumber: entryNumber,
          description: description,
          entryDate: Value(entryDate),
          status: const Value('posted'),
          entryType: const Value('manual'),
          totalDebitCents: Value(Decimal.fromInt(totalDebits)),
          totalCreditCents: Value(Decimal.fromInt(totalCredits)),
          postedAt: Value(entryDate),
        ),
      );
  var lineNo = 1;
  for (final l in lines) {
    await db
        .into(db.journalEntryLines)
        .insert(
          JournalEntryLinesCompanion.insert(
            journalEntryId: entryId,
            accountId: l.accountId,
            debitCents: Value(Decimal.fromInt(l.debit)),
            creditCents: Value(Decimal.fromInt(l.credit)),
            currencyId: currencyId,
            lineNumber: Value(lineNo++),
          ),
        );
  }
}

void main() {
  group('Pure classification spec', () {
    test(
      'asset/expense: positive raw → debit column, negative → credit (abs)',
      () {
        expect(_classifyRawBalance(500, 'asset'), (500, 0));
        expect(_classifyRawBalance(0, 'asset'), (0, 0));
        expect(_classifyRawBalance(-300, 'asset'), (0, 300));
        expect(_classifyRawBalance(10000, 'expense'), (10000, 0));
        expect(_classifyRawBalance(-250, 'expense'), (0, 250));
        // Case-insensitive
        expect(_classifyRawBalance(100, 'Asset'), (100, 0));
        expect(_classifyRawBalance(100, 'EXPENSE'), (100, 0));
      },
    );

    test(
      'liability/equity/revenue: positive natural → credit, negative → debit',
      () {
        // rawBalance = debit - credit; natural = -raw.
        // A revenue account with 800 credit posts → raw = -800 → natural=800 → credit col.
        expect(_classifyRawBalance(-800, 'revenue'), (0, 800));
        // Abnormal: revenue with net debit → raw=+200 → natural=-200 → debit col (abs=200).
        expect(_classifyRawBalance(200, 'revenue'), (200, 0));
        // Liability normal: raw=-1500 → credit col 1500.
        expect(_classifyRawBalance(-1500, 'liability'), (0, 1500));
        // Equity normal: raw=-5000 → credit col 5000.
        expect(_classifyRawBalance(-5000, 'equity'), (0, 5000));
        // Zero → (0, 0)
        expect(_classifyRawBalance(0, 'revenue'), (0, 0));
      },
    );
  });

  group('AccountingRepository.getTrialBalance honours the spec', () {
    late AppDatabase db;
    late AccountingRepository repo;
    late int currencyId;

    setUp(() async {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
      // Force schema init + default seeds (currencies, default CoA)
      await db.customSelect('SELECT 1').get();
      repo = AccountingRepository(db);
      final usd = await (db.select(
        db.currencies,
      )..where((c) => c.code.equals('USD'))).getSingle();
      currencyId = usd.id;
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'curated ledger → classification matches _classifyRawBalance',
      () async {
        // ──────── Accounts (use 9xxx codes to avoid CoA collision) ────────
        final cashId = await _insertAccount(
          db,
          code: '9101',
          name: 'Test Cash',
          type: 'asset',
          currencyId: currencyId,
        );
        final arId = await _insertAccount(
          db,
          code: '9102',
          name: 'Test AR',
          type: 'asset',
          currencyId: currencyId,
        );
        final apId = await _insertAccount(
          db,
          code: '9200',
          name: 'Test AP',
          type: 'liability',
          currencyId: currencyId,
        );
        final eqId = await _insertAccount(
          db,
          code: '9300',
          name: 'Test Equity',
          type: 'equity',
          currencyId: currencyId,
        );
        final salesId = await _insertAccount(
          db,
          code: '9400',
          name: 'Test Sales',
          type: 'revenue',
          currencyId: currencyId,
        );
        final cogsId = await _insertAccount(
          db,
          code: '9500',
          name: 'Test COGS',
          type: 'expense',
          currencyId: currencyId,
        );

        // ──────── Posted journal entries ────────
        // Sale for $100 with $60 COGS, customer paid cash:
        //   Cash      Dr 100  /  Sales Cr 100
        //   COGS      Dr  60  /  AR    Cr  60   (AR used as Inventory stand-in)
        // Supplier invoice on AP:
        //   COGS      Dr  40  /  AP    Cr  40
        // Capital contribution:
        //   Cash      Dr 500  /  Equity Cr 500
        final date = DateTime(2026, 1, 15);
        await _insertPostedEntry(
          db,
          entryNumber: 'JE-TEST-001',
          description: 'Sale revenue side',
          entryDate: date,
          currencyId: currencyId,
          lines: [
            (accountId: cashId, debit: 100, credit: 0),
            (accountId: salesId, debit: 0, credit: 100),
          ],
        );
        await _insertPostedEntry(
          db,
          entryNumber: 'JE-TEST-002',
          description: 'Sale COGS side',
          entryDate: date,
          currencyId: currencyId,
          lines: [
            (accountId: cogsId, debit: 60, credit: 0),
            (accountId: arId, debit: 0, credit: 60),
          ],
        );
        await _insertPostedEntry(
          db,
          entryNumber: 'JE-TEST-003',
          description: 'Supplier invoice',
          entryDate: date,
          currencyId: currencyId,
          lines: [
            (accountId: cogsId, debit: 40, credit: 0),
            (accountId: apId, debit: 0, credit: 40),
          ],
        );
        await _insertPostedEntry(
          db,
          entryNumber: 'JE-TEST-004',
          description: 'Capital contribution',
          entryDate: date,
          currencyId: currencyId,
          lines: [
            (accountId: cashId, debit: 500, credit: 0),
            (accountId: eqId, debit: 0, credit: 500),
          ],
        );

        final tb = await repo.getTrialBalance();

        // Expected raw balances (Σ debit − Σ credit) per test account:
        //   Cash:   +600  | AR:     -60  | AP: -40
        //   Equity: -500  | Sales: -100  | COGS: +100
        final expectedRaw = {
          cashId: 600,
          arId: -60,
          apId: -40,
          eqId: -500,
          salesId: -100,
          cogsId: 100,
        };
        final typeById = {
          cashId: 'asset',
          arId: 'asset',
          apId: 'liability',
          eqId: 'equity',
          salesId: 'revenue',
          cogsId: 'expense',
        };

        for (final accountId in expectedRaw.keys) {
          final item = tb.items.firstWhere((i) => i.accountId == accountId);
          final raw = expectedRaw[accountId]!;
          final expected = _classifyRawBalance(raw, typeById[accountId]!);
          expect(
            (item.debitCents, item.creditCents),
            expected,
            reason:
                'Account ${item.accountCode} '
                '(${typeById[accountId]}) with raw=$raw',
          );
        }

        // Ledger is balanced by construction across our 6 test accounts:
        //   Σ debits  = Cash 600 + COGS 100 = 700
        //   Σ credits = AR 60 + AP 40 + Equity 500 + Sales 100 = 700
        // The default seeded chart-of-accounts contributes (0,0) to both sides.
        expect(tb.totalDebitCents, 700);
        expect(tb.totalCreditCents, 700);
        expect(tb.isBalanced, isTrue);
      },
    );

    test('empty ledger → empty debits/credits, balanced', () async {
      // Only the seeded chart-of-accounts; no posted journal entries.
      final tb = await repo.getTrialBalance();

      expect(tb.totalDebitCents, 0);
      expect(tb.totalCreditCents, 0);
      expect(tb.isBalanced, isTrue);
      for (final item in tb.items) {
        expect(
          (item.debitCents, item.creditCents),
          (0, 0),
          reason: 'Account ${item.accountCode} should have zero columns',
        );
      }
    });

    test('abnormal balances still classify consistently '
        '(e.g. revenue with net debit)', () async {
      // Contra-revenue-like situation: revenue account with more debits
      // than credits (e.g. due to returns not yet offset). Classification
      // must place the abnormal positive raw into the DEBIT column (abs value).
      final salesId = await _insertAccount(
        db,
        code: '9400',
        name: 'Test Sales',
        type: 'revenue',
        currencyId: currencyId,
      );
      final cashId = await _insertAccount(
        db,
        code: '9101',
        name: 'Test Cash',
        type: 'asset',
        currencyId: currencyId,
      );

      await _insertPostedEntry(
        db,
        entryNumber: 'JE-ABN-001',
        description: 'Abnormal: revenue net debit, asset net credit',
        entryDate: DateTime(2026, 1, 15),
        currencyId: currencyId,
        lines: [
          // Sales raw = +300 (abnormal debit)
          // Cash  raw = -300 (abnormal credit)
          (accountId: salesId, debit: 300, credit: 0),
          (accountId: cashId, debit: 0, credit: 300),
        ],
      );

      final tb = await repo.getTrialBalance();
      final sales = tb.items.firstWhere((i) => i.accountId == salesId);
      final cash = tb.items.firstWhere((i) => i.accountId == cashId);

      expect(
        (sales.debitCents, sales.creditCents),
        (300, 0),
        reason: 'abnormal revenue → debit column (abs)',
      );
      expect(
        (cash.debitCents, cash.creditCents),
        (0, 300),
        reason: 'abnormal asset → credit column (abs)',
      );
      expect(tb.isBalanced, isTrue);
    });
  });
}
