import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/ledger/ledger_running_balance.dart';
import '../../../core/services/party_ledger_movement_policy.dart';

class PartyStatementOptionRecord {
  final int id;
  final String name;
  final String? phone;
  final int balanceCents;

  const PartyStatementOptionRecord({
    required this.id,
    required this.name,
    this.phone,
    required this.balanceCents,
  });
}

class PartyStatementPartyRecord {
  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? segment;

  const PartyStatementPartyRecord({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.segment,
  });
}

class PartyStatementTransactionRecord {
  final int id;
  final DateTime date;
  final String type;
  final String? transactionNumber;
  final String? discountType;
  final String? description;
  final int amountCents;
  final int runningBalanceCents;
  final int? referenceId;
  final String? referenceType;

  /// When true, this transaction is shown for audit trail visibility only.
  /// It does not affect the running balance, opening/closing balance, or
  /// debit/credit totals (e.g. cash refunds that were settled outside AP).
  final bool isDisplayOnly;

  const PartyStatementTransactionRecord({
    required this.id,
    required this.date,
    required this.type,
    this.transactionNumber,
    this.discountType,
    this.description,
    required this.amountCents,
    required this.runningBalanceCents,
    this.referenceId,
    this.referenceType,
    this.isDisplayOnly = false,
  });
}

class PartyStatementLedgerSnapshot {
  final PartyStatementPartyRecord? party;
  final List<PartyStatementOptionRecord> options;
  final int openingBalanceCents;
  final int closingBalanceCents;
  final int totalDebitsCents;
  final int totalCreditsCents;
  final List<PartyStatementTransactionRecord> transactions;

  const PartyStatementLedgerSnapshot({
    this.party,
    this.options = const [],
    this.openingBalanceCents = 0,
    this.closingBalanceCents = 0,
    this.totalDebitsCents = 0,
    this.totalCreditsCents = 0,
    this.transactions = const [],
  });
}

/// Normalizes report end dates so the complete selected day is included.
class PartyLedgerDatePolicy {
  const PartyLedgerDatePolicy._();

  static DateTime exclusiveEndOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day).add(const Duration(days: 1));
}

/// Authoritative period snapshot for customer and supplier sub-ledgers.
///
/// Opening balance is the immutable party opening balance plus every signed
/// movement before the selected period. Closing balance adds only movements
/// inside the period. The cached `balance_cents` column is deliberately not
/// used because it can be stale and also represents a different point in time.
class PartyStatementLedgerService {
  final AppDatabase _db;

  const PartyStatementLedgerService(this._db);

  Future<PartyStatementLedgerSnapshot> loadCustomer({
    required int? customerId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final endExclusive = PartyLedgerDatePolicy.exclusiveEndOfDay(endDate);
    final customers =
        await (_db.select(_db.customers)
              ..where((c) => c.createdAt.isSmallerThanValue(endExclusive))
              ..orderBy([(c) => OrderingTerm.asc(c.name)]))
            .get();
    final transactions =
        await (_db.select(_db.customerTransactions)
              ..where(
                (transaction) => transaction.transactionDate.isSmallerThanValue(
                  endExclusive,
                ),
              )
              ..orderBy([
                (transaction) => OrderingTerm.asc(transaction.transactionDate),
                (transaction) => OrderingTerm.asc(transaction.id),
              ]))
            .get();

    // Balance-affecting transactions only (for dropdown balance calculation)
    final byCustomerBalance = <int, List<CustomerTransaction>>{};
    // ALL transactions including display-only (for the statement table)
    final byCustomerAll = <int, List<CustomerTransaction>>{};
    for (final transaction in transactions) {
      byCustomerAll
          .putIfAbsent(transaction.customerId, () => <CustomerTransaction>[])
          .add(transaction);
      if (PartyLedgerMovementPolicy.affectsBalance(
        transaction.transactionType,
      )) {
        byCustomerBalance
            .putIfAbsent(transaction.customerId, () => <CustomerTransaction>[])
            .add(transaction);
      }
    }

    final options = customers
        .where((customer) => customer.isActive)
        .map(
          (customer) => PartyStatementOptionRecord(
            id: customer.id,
            name: customer.name,
            phone: customer.phone,
            balanceCents:
                customer.openingBalanceCents.toBigInt().toInt() +
                _customerMovementTotal(
                  byCustomerBalance[customer.id] ?? const [],
                ),
          ),
        )
        .toList();

    if (customerId == null) {
      return PartyStatementLedgerSnapshot(options: options);
    }
    final selected = customers.where((customer) => customer.id == customerId);
    if (selected.isEmpty) {
      return PartyStatementLedgerSnapshot(options: options);
    }

    final customer = selected.first;
    final movements =
        byCustomerAll[customer.id] ?? const <CustomerTransaction>[];
    return _buildSnapshot(
      party: PartyStatementPartyRecord(
        id: customer.id,
        name: customer.name,
        phone: customer.phone,
        email: customer.email,
        address: customer.address,
        segment: customer.segment,
      ),
      options: options,
      immutableOpeningBalanceCents: customer.openingBalanceCents
          .toBigInt()
          .toInt(),
      startDate: startDate,
      movements: movements.map(
        (transaction) => _Movement(
          id: transaction.id,
          date: transaction.transactionDate,
          type: transaction.transactionType,
          transactionNumber: transaction.transactionNumber,
          discountType: transaction.discountType,
          description: transaction.description,
          amountCents: transaction.amountCents.toBigInt().toInt(),
          referenceId: transaction.referenceId,
          referenceType: transaction.referenceType,
          isDisplayOnly: !PartyLedgerMovementPolicy.affectsBalance(
            transaction.transactionType,
          ),
        ),
      ),
    );
  }

  Future<PartyStatementLedgerSnapshot> loadSupplier({
    required int? supplierId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final endExclusive = PartyLedgerDatePolicy.exclusiveEndOfDay(endDate);
    final suppliers =
        await (_db.select(_db.suppliers)
              ..where((s) => s.createdAt.isSmallerThanValue(endExclusive))
              ..orderBy([(s) => OrderingTerm.asc(s.name)]))
            .get();
    final transactions =
        await (_db.select(_db.supplierTransactions)
              ..where(
                (transaction) => transaction.transactionDate.isSmallerThanValue(
                  endExclusive,
                ),
              )
              ..orderBy([
                (transaction) => OrderingTerm.asc(transaction.transactionDate),
                (transaction) => OrderingTerm.asc(transaction.id),
              ]))
            .get();

    // Balance-affecting transactions only (for dropdown balance calculation)
    final bySupplierBalance = <int, List<SupplierTransaction>>{};
    // ALL transactions including display-only (for the statement table)
    final bySupplierAll = <int, List<SupplierTransaction>>{};
    for (final transaction in transactions) {
      bySupplierAll
          .putIfAbsent(transaction.supplierId, () => <SupplierTransaction>[])
          .add(transaction);
      if (PartyLedgerMovementPolicy.affectsBalance(
        transaction.transactionType,
      )) {
        bySupplierBalance
            .putIfAbsent(transaction.supplierId, () => <SupplierTransaction>[])
            .add(transaction);
      }
    }

    final options = suppliers
        .where((supplier) => supplier.isActive)
        .map(
          (supplier) => PartyStatementOptionRecord(
            id: supplier.id,
            name: supplier.name,
            phone: supplier.phone,
            balanceCents:
                supplier.openingBalanceCents.toBigInt().toInt() +
                _supplierMovementTotal(
                  bySupplierBalance[supplier.id] ?? const [],
                ),
          ),
        )
        .toList();

    if (supplierId == null) {
      return PartyStatementLedgerSnapshot(options: options);
    }
    final selected = suppliers.where((supplier) => supplier.id == supplierId);
    if (selected.isEmpty) {
      return PartyStatementLedgerSnapshot(options: options);
    }

    final supplier = selected.first;
    final movements =
        bySupplierAll[supplier.id] ?? const <SupplierTransaction>[];
    return _buildSnapshot(
      party: PartyStatementPartyRecord(
        id: supplier.id,
        name: supplier.name,
        phone: supplier.phone,
        email: supplier.email,
        address: supplier.address,
      ),
      options: options,
      immutableOpeningBalanceCents: supplier.openingBalanceCents
          .toBigInt()
          .toInt(),
      startDate: startDate,
      movements: movements.map(
        (transaction) => _Movement(
          id: transaction.id,
          date: transaction.transactionDate,
          type: transaction.transactionType,
          transactionNumber: transaction.transactionNumber,
          discountType: transaction.discountType,
          description: transaction.description,
          amountCents: transaction.amountCents.toBigInt().toInt(),
          referenceId: transaction.referenceId,
          referenceType: transaction.referenceType,
          isDisplayOnly: !PartyLedgerMovementPolicy.affectsBalance(
            transaction.transactionType,
          ),
        ),
      ),
    );
  }

  static PartyStatementLedgerSnapshot _buildSnapshot({
    required PartyStatementPartyRecord party,
    required List<PartyStatementOptionRecord> options,
    required int immutableOpeningBalanceCents,
    required DateTime startDate,
    required Iterable<_Movement> movements,
  }) {
    var openingBalance = immutableOpeningBalanceCents;
    final periodMovements = <_Movement>[];
    for (final movement in movements) {
      if (movement.date.isBefore(startDate)) {
        // Only balance-affecting transactions contribute to opening balance.
        // Display-only transactions before the period are skipped entirely.
        if (!movement.isDisplayOnly) {
          openingBalance += movement.amountCents;
        }
      } else {
        periodMovements.add(movement);
      }
    }

    final runningBalance = LedgerRunningBalance(openingBalance);
    var totalDebits = 0;
    var totalCredits = 0;
    final transactions = <PartyStatementTransactionRecord>[];
    for (final movement in periodMovements) {
      if (movement.isDisplayOnly) {
        // Display-only: show in the list but don't touch running balance
        // or debit/credit totals.
        transactions.add(
          PartyStatementTransactionRecord(
            id: movement.id,
            date: movement.date,
            type: movement.type,
            transactionNumber: movement.transactionNumber,
            discountType: movement.discountType,
            description: movement.description,
            amountCents: movement.amountCents,
            runningBalanceCents: runningBalance.current,
            referenceId: movement.referenceId,
            referenceType: movement.referenceType,
            isDisplayOnly: true,
          ),
        );
        continue;
      }
      final balanceAfterMovement = runningBalance.apply(movement.amountCents);
      if (movement.amountCents > 0) {
        totalDebits += movement.amountCents;
      } else if (movement.amountCents < 0) {
        totalCredits += -movement.amountCents;
      }
      transactions.add(
        PartyStatementTransactionRecord(
          id: movement.id,
          date: movement.date,
          type: movement.type,
          transactionNumber: movement.transactionNumber,
          discountType: movement.discountType,
          description: movement.description,
          amountCents: movement.amountCents,
          runningBalanceCents: balanceAfterMovement,
          referenceId: movement.referenceId,
          referenceType: movement.referenceType,
        ),
      );
    }

    return PartyStatementLedgerSnapshot(
      party: party,
      options: options,
      openingBalanceCents: openingBalance,
      closingBalanceCents: runningBalance.current,
      totalDebitsCents: totalDebits,
      totalCreditsCents: totalCredits,
      transactions: transactions,
    );
  }

  static int _customerMovementTotal(
    Iterable<CustomerTransaction> transactions,
  ) => transactions.fold(
    0,
    (total, transaction) => total + transaction.amountCents.toBigInt().toInt(),
  );

  static int _supplierMovementTotal(
    Iterable<SupplierTransaction> transactions,
  ) => transactions.fold(
    0,
    (total, transaction) => total + transaction.amountCents.toBigInt().toInt(),
  );
}

class _Movement {
  final int id;
  final DateTime date;
  final String type;
  final String? transactionNumber;
  final String? discountType;
  final String? description;
  final int amountCents;
  final int? referenceId;
  final String? referenceType;
  final bool isDisplayOnly;

  const _Movement({
    required this.id,
    required this.date,
    required this.type,
    this.transactionNumber,
    this.discountType,
    this.description,
    required this.amountCents,
    this.referenceId,
    this.referenceType,
    this.isDisplayOnly = false,
  });
}
