import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/ledger/ledger_running_balance.dart';

/// One immutable, posted line in an account's general ledger.
class GeneralLedgerRow {
  final int journalEntryId;
  final int journalLineId;
  final String entryNumber;
  final DateTime entryDate;
  final String entryType;
  final String description;
  final int debitCents;
  final int creditCents;
  final int runningBalanceCents;

  const GeneralLedgerRow({
    required this.journalEntryId,
    required this.journalLineId,
    required this.entryNumber,
    required this.entryDate,
    required this.entryType,
    required this.description,
    required this.debitCents,
    required this.creditCents,
    required this.runningBalanceCents,
  });
}

/// A complete account ledger for a selected reporting period.
class GeneralLedgerSnapshot {
  final Account account;
  final DateTime startDate;
  final DateTime endDate;
  final int openingBalanceCents;
  final List<GeneralLedgerRow> rows;
  final int totalDebitCents;
  final int totalCreditCents;
  final int closingBalanceCents;

  const GeneralLedgerSnapshot({
    required this.account,
    required this.startDate,
    required this.endDate,
    required this.openingBalanceCents,
    required this.rows,
    required this.totalDebitCents,
    required this.totalCreditCents,
    required this.closingBalanceCents,
  });
}

/// General-ledger read model backed exclusively by posted journal entries.
///
/// Business documents are deliberately not reconstructed here. Journal entry
/// lines are the accounting source of truth and already contain payments,
/// taxes, returns, adjustments, reversals and the exact inventory cost used at
/// posting time.
class GeneralLedgerService {
  final AppDatabase _db;

  GeneralLedgerService(this._db);

  Stream<List<Account>> watchActiveAccounts() {
    return (_db.select(_db.accounts)
          ..where((account) => account.isActive.equals(true))
          ..orderBy([
            (account) => OrderingTerm(expression: account.accountCode),
          ]))
        .watch();
  }

  Stream<GeneralLedgerSnapshot> watch({
    required int accountId,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.accounts, _db.journalEntries, _db.journalEntryLines},
        )
        .watch()
        .asyncMap(
          (_) => load(
            accountId: accountId,
            startDate: startDate,
            endDate: endDate,
          ),
        );
  }

  Future<GeneralLedgerSnapshot> load({
    required int accountId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final periodStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final endExclusive = DateTime(
      endDate.year,
      endDate.month,
      endDate.day,
    ).add(const Duration(days: 1));
    if (!periodStart.isBefore(endExclusive)) {
      throw ArgumentError('The general-ledger date range is invalid.');
    }

    final account = await (_db.select(
      _db.accounts,
    )..where((row) => row.id.equals(accountId))).getSingleOrNull();
    if (account == null) {
      throw StateError('Account $accountId does not exist.');
    }

    final openingLines = await _loadLines(
      accountId: accountId,
      before: periodStart,
    );
    final openingBalance = openingLines.fold<int>(
      0,
      (sum, record) => sum + _naturalDelta(account, record.line),
    );
    final runningBalance = LedgerRunningBalance(openingBalance);

    final periodLines = await _loadLines(
      accountId: accountId,
      onOrAfter: periodStart,
      before: endExclusive,
    );
    var totalDebit = 0;
    var totalCredit = 0;
    final rows = <GeneralLedgerRow>[];
    for (final record in periodLines) {
      final debit = record.line.debitCents.toBigInt().toInt();
      final credit = record.line.creditCents.toBigInt().toInt();
      totalDebit += debit;
      totalCredit += credit;
      final rowBalance = runningBalance.apply(
        _naturalDelta(account, record.line),
      );

      final lineDescription = record.line.description?.trim();
      rows.add(
        GeneralLedgerRow(
          journalEntryId: record.entry.id,
          journalLineId: record.line.id,
          entryNumber: record.entry.entryNumber,
          entryDate: record.entry.entryDate,
          entryType: record.entry.entryType,
          description: lineDescription == null || lineDescription.isEmpty
              ? record.entry.description
              : lineDescription,
          debitCents: debit,
          creditCents: credit,
          runningBalanceCents: rowBalance,
        ),
      );
    }

    return GeneralLedgerSnapshot(
      account: account,
      startDate: periodStart,
      endDate: endExclusive.subtract(const Duration(microseconds: 1)),
      openingBalanceCents: openingBalance,
      rows: List.unmodifiable(rows),
      totalDebitCents: totalDebit,
      totalCreditCents: totalCredit,
      closingBalanceCents: runningBalance.current,
    );
  }

  Future<List<_PostedLedgerLine>> _loadLines({
    required int accountId,
    DateTime? onOrAfter,
    required DateTime before,
  }) async {
    final query = _db.select(_db.journalEntryLines).join([
      innerJoin(
        _db.journalEntries,
        _db.journalEntries.id.equalsExp(_db.journalEntryLines.journalEntryId),
      ),
    ]);

    var predicate =
        _db.journalEntryLines.accountId.equals(accountId) &
        _db.journalEntries.status.equals('posted') &
        _db.journalEntries.entryDate.isSmallerThanValue(before);
    if (onOrAfter != null) {
      predicate =
          predicate &
          _db.journalEntries.entryDate.isBiggerOrEqualValue(onOrAfter);
    }
    query.where(predicate);
    query.orderBy([
      OrderingTerm(expression: _db.journalEntries.entryDate),
      OrderingTerm(expression: _db.journalEntries.id),
      OrderingTerm(expression: _db.journalEntryLines.lineNumber),
      OrderingTerm(expression: _db.journalEntryLines.id),
    ]);

    final result = await query.get();
    return result
        .map(
          (row) => _PostedLedgerLine(
            entry: row.readTable(_db.journalEntries),
            line: row.readTable(_db.journalEntryLines),
          ),
        )
        .toList(growable: false);
  }

  int _naturalDelta(Account account, JournalEntryLine line) {
    final debit = line.debitCents.toBigInt().toInt();
    final credit = line.creditCents.toBigInt().toInt();
    switch (account.accountType.toLowerCase()) {
      case 'liability':
      case 'equity':
      case 'revenue':
        return credit - debit;
      case 'asset':
      case 'expense':
      default:
        return debit - credit;
    }
  }
}

class _PostedLedgerLine {
  final JournalEntry entry;
  final JournalEntryLine line;

  const _PostedLedgerLine({required this.entry, required this.line});
}
