import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../../features/accounting/data/repositories/accounting_repository.dart';
import '../../features/accounting/domain/models/journal_entry_data.dart';

enum OwnerFinanceTransactionType {
  contribution,
  withdrawal,
  loanReceived,
  loanRepayment;

  String get wireName => switch (this) {
    contribution => 'contribution',
    withdrawal => 'withdrawal',
    loanReceived => 'loan_received',
    loanRepayment => 'loan_repayment',
  };

  String get journalEntryType => switch (this) {
    contribution => 'owner_contribution',
    withdrawal => 'owner_withdrawal',
    loanReceived => 'owner_loan_received',
    loanRepayment => 'owner_loan_repayment',
  };

  String get controlAccountCode => switch (this) {
    contribution => '3000',
    withdrawal => '3200',
    loanReceived || loanRepayment => '2200',
  };

  bool get debitOffsetAccount => this == contribution || this == loanReceived;
}

class OwnerFinanceResult {
  final int transactionId;
  final String transactionNumber;
  final int journalEntryId;

  const OwnerFinanceResult({
    required this.transactionId,
    required this.transactionNumber,
    required this.journalEntryId,
  });
}

class OwnerFinanceException implements Exception {
  final String message;
  const OwnerFinanceException(this.message);

  @override
  String toString() => 'OwnerFinanceException: $message';
}

class OwnerFinanceService {
  static const allowedOffsetAccountCodes = {'1000', '1010'};

  final AppDatabase _db;
  final AccountingRepository _accounting;

  OwnerFinanceService({
    required AppDatabase db,
    required AccountingRepository accounting,
  }) : _db = db,
       _accounting = accounting;

  Stream<List<OwnerFinanceTransaction>> watchTransactions() {
    return (_db.select(_db.ownerFinanceTransactions)..orderBy([
          (t) => OrderingTerm.desc(t.transactionDate),
          (t) => OrderingTerm.desc(t.id),
        ]))
        .watch();
  }

  Future<List<Account>> getMoneyAccounts() {
    return (_db.select(_db.accounts)
          ..where(
            (a) =>
                a.isActive.equals(true) &
                a.accountCode.isIn(allowedOffsetAccountCodes),
          )
          ..orderBy([(a) => OrderingTerm.asc(a.accountCode)]))
        .get();
  }

  Future<int> getDefaultCurrencyId() async {
    final currency =
        await (_db.select(_db.currencies)
              ..where((c) => c.isBase.equals(true))
              ..limit(1))
            .getSingleOrNull() ??
        await (_db.select(_db.currencies)..limit(1)).getSingle();
    return currency.id;
  }

  Future<OwnerFinanceResult> record({
    required OwnerFinanceTransactionType type,
    required int offsetAccountId,
    required int amountCents,
    required int currencyId,
    required DateTime transactionDate,
    required String description,
    String? notes,
    int? userId,
  }) async {
    final trimmedDescription = description.trim();
    if (amountCents <= 0) {
      throw const OwnerFinanceException('Amount must be greater than zero');
    }
    if (trimmedDescription.isEmpty) {
      throw const OwnerFinanceException('Description is required');
    }

    return _db.transaction(() async {
      final offset = await (_db.select(
        _db.accounts,
      )..where((a) => a.id.equals(offsetAccountId))).getSingleOrNull();
      if (offset == null ||
          !allowedOffsetAccountCodes.contains(offset.accountCode)) {
        throw const OwnerFinanceException(
          'Owner finance offset must be Cash (1000) or Bank (1010)',
        );
      }
      if (offset.currencyId != currencyId) {
        throw const OwnerFinanceException(
          'The selected money account uses a different currency',
        );
      }

      final control = await _accounting.getAccountByCode(
        type.controlAccountCode,
      );
      if (control == null || !control.isActive) {
        throw OwnerFinanceException(
          'Required account ${type.controlAccountCode} is unavailable',
        );
      }
      if (control.currencyId != currencyId) {
        throw const OwnerFinanceException(
          'Owner control account uses a different currency',
        );
      }

      final number = await _generateNumber(transactionDate);
      final transactionId = await _db
          .into(_db.ownerFinanceTransactions)
          .insert(
            OwnerFinanceTransactionsCompanion.insert(
              transactionNumber: number,
              transactionType: type.wireName,
              amountCents: Decimal.fromInt(amountCents),
              currencyId: currencyId,
              offsetAccountId: offsetAccountId,
              transactionDate: transactionDate,
              description: trimmedDescription,
              notes: Value(_trimToNull(notes)),
              createdBy: Value(userId),
            ),
          );

      final debitAccountId = type.debitOffsetAccount ? offset.id : control.id;
      final creditAccountId = type.debitOffsetAccount ? control.id : offset.id;

      final journalEntryId = await _accounting.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: '$number — $trimmedDescription',
          debitAccountId: debitAccountId,
          creditAccountId: creditAccountId,
          amountCents: amountCents,
          currencyId: currencyId,
          entryDate: transactionDate,
          entryType: type.journalEntryType,
          sourceTable: 'owner_finance_transactions',
          sourceId: transactionId,
          autoPost: true,
        ),
        userId: userId,
      );

      await (_db.update(
        _db.ownerFinanceTransactions,
      )..where((t) => t.id.equals(transactionId))).write(
        OwnerFinanceTransactionsCompanion(
          journalEntryId: Value(journalEntryId),
          updatedAt: Value(DateTime.now()),
        ),
      );

      return OwnerFinanceResult(
        transactionId: transactionId,
        transactionNumber: number,
        journalEntryId: journalEntryId,
      );
    });
  }

  Future<int> voidTransaction({
    required int transactionId,
    required String reason,
    int? userId,
  }) {
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const OwnerFinanceException('Void reason is required');
    }

    return _db.transaction(() async {
      final row = await (_db.select(
        _db.ownerFinanceTransactions,
      )..where((t) => t.id.equals(transactionId))).getSingleOrNull();
      if (row == null) {
        throw const OwnerFinanceException('Owner transaction not found');
      }
      if (row.status != 'posted' || row.journalEntryId == null) {
        throw const OwnerFinanceException(
          'Only a posted owner transaction can be voided',
        );
      }

      final reversalId = await _accounting.voidJournalEntry(
        entryId: row.journalEntryId!,
        reason: trimmedReason,
        userId: userId,
      );
      await (_db.update(
        _db.ownerFinanceTransactions,
      )..where((t) => t.id.equals(transactionId))).write(
        OwnerFinanceTransactionsCompanion(
          status: const Value('voided'),
          reversalJournalEntryId: Value(reversalId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return reversalId;
    });
  }

  Future<String> _generateNumber(DateTime date) async {
    final prefix = 'OWN-${date.year}${date.month.toString().padLeft(2, '0')}';
    final last =
        await (_db.select(_db.ownerFinanceTransactions)
              ..where((t) => t.transactionNumber.like('$prefix-%'))
              ..orderBy([(t) => OrderingTerm.desc(t.transactionNumber)])
              ..limit(1))
            .getSingleOrNull();
    final lastSequence =
        int.tryParse(last?.transactionNumber.split('-').last ?? '') ?? 0;
    return '$prefix-${(lastSequence + 1).toString().padLeft(4, '0')}';
  }

  static String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
