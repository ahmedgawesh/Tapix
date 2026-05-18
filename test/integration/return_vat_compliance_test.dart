import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// Phase 0.2 — VAT reversal compliance for *linked* purchase returns.
///
/// Regression for the Phase 0 audit finding:
///   recordPurchaseReturnJournalEntry historically posted a 2-line entry
///   (Dr AP/Cash, Cr Inventory) but never debited 1300 VAT Receivable, so any
///   tax that was originally claimed on the matching purchase invoice stayed
///   in the input-VAT bucket forever. That is a tax-law violation in every
///   VAT regime (KSA / EG / EU).
///
/// This test now verifies:
///   • When a linked purchase return carries `taxCents > 0`, the JE includes a
///     credit to 1300 VAT Receivable equal to that amount.
///   • The credit to 1200 Inventory equals `total - tax` (net only).
///   • Total debits == total credits (balanced).
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late AccountingRepository accounting;

  Future<int> accountIdByCode(String code) async {
    final row = await db.customSelect(
      'SELECT id FROM accounts WHERE account_code = ?',
      variables: [Variable.withString(code)],
    ).getSingle();
    return row.read<int>('id');
  }

  Future<List<({int accountId, int debit, int credit})>> linesFor(
      int journalEntryId) async {
    final rows = await db.customSelect(
      'SELECT account_id, debit_cents, credit_cents '
      'FROM journal_entry_lines WHERE journal_entry_id = ? '
      'ORDER BY id ASC',
      variables: [Variable.withInt(journalEntryId)],
    ).get();
    return rows
        .map((r) => (
              accountId: r.read<int>('account_id'),
              debit: r.read<int>('debit_cents'),
              credit: r.read<int>('credit_cents'),
            ))
        .toList();
  }

  Future<int> latestPurchaseReturnJournalId(int returnId) async {
    final row = await db.customSelect(
      'SELECT id FROM journal_entries '
      "WHERE source_table = 'purchase_returns' AND source_id = ? "
      "  AND status = 'posted' "
      'ORDER BY id DESC LIMIT 1',
      variables: [Variable.withInt(returnId)],
    ).getSingle();
    return row.read<int>('id');
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    accounting = AccountingRepository(db);
    journal = JournalEntryService(accounting);
    await db.customSelect('SELECT 1').get();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, '
      'is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );
  });

  tearDown(() async => db.close());

  test('linked purchase return JE credits 1300 VAT Receivable for taxCents',
      () async {
    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();

    final apId = await accountIdByCode('2000');
    final inventoryId = await accountIdByCode('1200');
    final vatReceivableId = await accountIdByCode('1300');

    // Simulate a posted purchase return totaling 1150 with 150 VAT.
    const total = 1150;
    const tax = 150;
    const netInventory = total - tax; // 1000

    await journal.recordPurchaseReturnJournalEntry(
      returnId: 999,
      totalCents: total,
      taxCents: tax,
      currencyId: usd.id,
      refundMethod: 'credit',
    );

    final jeId = await latestPurchaseReturnJournalId(999);
    final lines = await linesFor(jeId);

    // Sum credits for inventory and VAT.
    final invCredit = lines
        .where((l) => l.accountId == inventoryId)
        .fold<int>(0, (s, l) => s + l.credit);
    final vatCredit = lines
        .where((l) => l.accountId == vatReceivableId)
        .fold<int>(0, (s, l) => s + l.credit);
    final apDebit = lines
        .where((l) => l.accountId == apId)
        .fold<int>(0, (s, l) => s + l.debit);

    expect(vatCredit, equals(tax),
        reason: 'VAT Receivable must be reversed by exactly the tax amount');
    expect(invCredit, equals(netInventory),
        reason: 'Inventory credit must equal net of tax (total - tax)');
    expect(apDebit, equals(total),
        reason: 'AP must be debited by the gross total');

    final totalDebits = lines.fold<int>(0, (s, l) => s + l.debit);
    final totalCredits = lines.fold<int>(0, (s, l) => s + l.credit);
    expect(totalDebits, equals(totalCredits), reason: 'JE must balance');
  });

  test('zero-tax linked purchase return JE has no VAT line', () async {
    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();

    final vatReceivableId = await accountIdByCode('1300');

    const total = 800;
    const tax = 0;

    await journal.recordPurchaseReturnJournalEntry(
      returnId: 1000,
      totalCents: total,
      taxCents: tax,
      currencyId: usd.id,
      refundMethod: 'credit',
    );

    final jeId = await latestPurchaseReturnJournalId(1000);
    final lines = await linesFor(jeId);

    final hasVatLine = lines.any((l) => l.accountId == vatReceivableId);
    expect(hasVatLine, isFalse,
        reason: 'No VAT line when taxCents = 0 (avoids zero-amount noise)');

    final totalDebits = lines.fold<int>(0, (s, l) => s + l.debit);
    final totalCredits = lines.fold<int>(0, (s, l) => s + l.credit);
    expect(totalDebits, equals(totalCredits));
  });
}
