import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/party_ledger_movement_policy.dart';
import 'party_statement_ledger_service.dart';

/// One supplier's balance snapshot plus activity inside the selected period.
class SupplierBalanceLedgerRecord {
  final int supplierId;
  final String supplierName;
  final String? phone;
  final String? email;
  final int openingBalanceCents;

  /// Signed net balance at the report end date.
  /// Positive means payable; negative means supplier receivable.
  final int netBalanceCents;

  /// Signed/net activity totals inside the selected period only.
  final int totalPurchasesCents;
  final int totalPaymentsCents;
  final int totalReturnsCents;
  final int totalDiscountsCents;
  final int transactionCount;
  final DateTime? lastTransactionAt;

  const SupplierBalanceLedgerRecord({
    required this.supplierId,
    required this.supplierName,
    this.phone,
    this.email,
    required this.openingBalanceCents,
    required this.netBalanceCents,
    required this.totalPurchasesCents,
    required this.totalPaymentsCents,
    required this.totalReturnsCents,
    required this.totalDiscountsCents,
    required this.transactionCount,
    this.lastTransactionAt,
  });
}

class _SupplierBalanceAccumulator {
  int ledgerMovementCents = 0;
  int totalPurchasesCents = 0;
  int totalPaymentsCents = 0;
  int totalReturnsCents = 0;
  int totalDiscountsCents = 0;
  int periodTransactionCount = 0;
  DateTime? lastPeriodTransactionAt;

  void add(SupplierTransaction transaction, {required DateTime periodStart}) {
    if (!PartyLedgerMovementPolicy.affectsBalance(
      transaction.transactionType,
    )) {
      return;
    }
    final amount = transaction.amountCents.toBigInt().toInt();
    ledgerMovementCents += amount;

    if (transaction.transactionDate.isBefore(periodStart)) return;

    periodTransactionCount++;
    if (lastPeriodTransactionAt == null ||
        transaction.transactionDate.isAfter(lastPeriodTransactionAt!)) {
      lastPeriodTransactionAt = transaction.transactionDate;
    }

    // Net each normal movement with its reversal. This makes a purchase and
    // its void (or a payment and its reversal) cancel inside the same period.
    switch (transaction.transactionType) {
      case 'purchase':
      case 'purchase_void':
        totalPurchasesCents += amount;
      case 'payment':
      case 'payment_reversal':
        totalPaymentsCents -= amount;
      case 'purchase_return':
      case 'refund':
      case 'credit_note':
      case 'purchase_return_reversal':
      case 'refund_reversal':
      case 'credit_note_reversal':
        totalReturnsCents -= amount;
      case 'discount':
      case 'discount_reversal':
        totalDiscountsCents -= amount;
    }
  }
}

/// Authoritative supplier balance source for all supplier balance reports.
///
/// Snapshot balance equals opening balance plus every signed supplier movement
/// on or before the requested end date. Activity columns remain limited to the
/// requested period.
class SupplierBalanceLedgerService {
  final AppDatabase _db;

  const SupplierBalanceLedgerService(this._db);

  Future<List<SupplierBalanceLedgerRecord>> load({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final endExclusive = PartyLedgerDatePolicy.exclusiveEndOfDay(endDate);
    final suppliers = await (_db.select(
      _db.suppliers,
    )..where((s) => s.createdAt.isSmallerThanValue(endExclusive))).get();
    final transactions =
        await (_db.select(_db.supplierTransactions)
              ..where((t) => t.transactionDate.isSmallerThanValue(endExclusive))
              ..orderBy([
                (t) => OrderingTerm.asc(t.transactionDate),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();

    final bySupplier = <int, _SupplierBalanceAccumulator>{};
    for (final transaction in transactions) {
      bySupplier
          .putIfAbsent(transaction.supplierId, _SupplierBalanceAccumulator.new)
          .add(transaction, periodStart: startDate);
    }

    final records = <SupplierBalanceLedgerRecord>[];
    for (final supplier in suppliers) {
      final opening = supplier.openingBalanceCents.toBigInt().toInt();
      final accumulator =
          bySupplier[supplier.id] ?? _SupplierBalanceAccumulator();
      final netBalance = opening + accumulator.ledgerMovementCents;

      // Keep non-zero inactive suppliers visible for sub-ledger/GL parity.
      // A zero-balance supplier is shown only when it had selected-period
      // activity, matching the report's activity purpose.
      if (!supplier.isActive &&
          netBalance == 0 &&
          accumulator.periodTransactionCount == 0) {
        continue;
      }
      if (netBalance == 0 &&
          opening == 0 &&
          accumulator.periodTransactionCount == 0) {
        continue;
      }

      records.add(
        SupplierBalanceLedgerRecord(
          supplierId: supplier.id,
          supplierName: supplier.name,
          phone: supplier.phone,
          email: supplier.email,
          openingBalanceCents: opening,
          netBalanceCents: netBalance,
          totalPurchasesCents: accumulator.totalPurchasesCents,
          totalPaymentsCents: accumulator.totalPaymentsCents,
          totalReturnsCents: accumulator.totalReturnsCents,
          totalDiscountsCents: accumulator.totalDiscountsCents,
          transactionCount:
              accumulator.periodTransactionCount + (opening != 0 ? 1 : 0),
          lastTransactionAt: accumulator.lastPeriodTransactionAt,
        ),
      );
    }
    return records;
  }
}
