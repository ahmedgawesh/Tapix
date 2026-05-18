// ════════════════════════════════════════════════════════════════════════════
// Phase 1.5 — SINGLE-WRITER GUARD on `accounts.balance_cents`
// ════════════════════════════════════════════════════════════════════════════
//
// Static-analysis test that pins the invariant from
// `docs/adr/0001-pricing-engines-as-sot.md` §B:
//
//   "AccountingRepository._updateAccountBalance is the SOLE writer of
//    accounts.balance_cents. No other call site — including migrations —
//    may issue `UPDATE accounts SET balance_cents = …`."
//
// Before Phase 1.5, `_repairSupplierOpeningBalanceJournals` in
// app_database.dart hand-rolled two raw SQL statements:
//
//   UPDATE accounts SET balance_cents = balance_cents - $absBalance …
//   UPDATE accounts SET balance_cents = balance_cents + $absBalance …
//
// bypassing the single-writer invariant. The migration now delegates to
// JournalEntryService.recordSupplierOpeningBalanceJournalEntry, which routes
// through AccountingRepository.createJournalEntry — the only sanctioned
// writer of `accounts.balance_cents`.
//
// This grep-style test fails the build the moment anyone re-introduces a
// raw `UPDATE accounts SET balance_cents = …` outside of
// AccountingRepository, regardless of formatting / whitespace / case.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Remove `// line` and `/* block */` comments from a Dart source string so
/// that the guard only inspects *executable* code — otherwise the very
/// commentary that documents the removed bypass would trip the regex.
String _stripDartComments(String src) {
  // Block comments first (non-greedy, multi-line).
  var out = src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  // Then single-line // comments (to end-of-line).
  out = out.replaceAll(RegExp(r'//[^\n]*'), '');
  return out;
}

final _forbidden = RegExp(
  r'update\s+accounts\s+set\s+balance_cents',
  caseSensitive: false,
);

void main() {
  group('Single-writer guard on accounts.balance_cents', () {
    test(
      'app_database.dart contains NO raw "UPDATE accounts SET balance_cents" '
      'statements (Phase 1.5 invariant)',
      () {
        final raw = File('lib/core/database/app_database.dart')
            .readAsStringSync();
        final code = _stripDartComments(raw);
        final flat = code.replaceAll(RegExp(r'\s+'), ' ');

        expect(
          _forbidden.hasMatch(flat),
          isFalse,
          reason:
              'Raw "UPDATE accounts SET balance_cents = ..." re-introduced in '
              'app_database.dart. The accounts.balance_cents column has ONE '
              'sanctioned writer: AccountingRepository._updateAccountBalance '
              '(via createJournalEntry). Migrations that need to seed '
              'balances must call '
              'JournalEntryService.record*OpeningBalanceJournalEntry instead. '
              'See docs/adr/0001-pricing-engines-as-sot.md section B.',
        );
      },
    );

    test(
      'no .dart file under lib/ writes accounts.balance_cents via raw SQL',
      () {
        // The sole permitted writer lives in accounting_repository.dart and
        // uses the Drift query builder (update(_db.accounts) …), not raw
        // SQL. Verify no executable code anywhere under lib/ uses the
        // raw-SQL form.
        final libDir = Directory('lib');
        final offenders = <String>[];

        for (final entity in libDir.listSync(recursive: true)) {
          if (entity is! File) continue;
          if (!entity.path.endsWith('.dart')) continue;

          final raw = entity.readAsStringSync();
          final code = _stripDartComments(raw);
          final flat = code.replaceAll(RegExp(r'\s+'), ' ');
          if (_forbidden.hasMatch(flat)) {
            offenders.add(entity.path);
          }
        }

        expect(
          offenders,
          isEmpty,
          reason:
              'Files containing raw "UPDATE accounts SET balance_cents": '
              '$offenders. Route through '
              'AccountingRepository.createJournalEntry (the sole sanctioned '
              'writer). See docs/adr/0001-pricing-engines-as-sot.md section B.',
        );
      },
    );
  });
}
