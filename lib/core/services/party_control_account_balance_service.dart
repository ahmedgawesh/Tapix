import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'party_ledger_movement_policy.dart';

/// Immutable customer/supplier sub-ledger totals at one accounting instant.
class PartyControlAccountBalances {
  final int customerBalanceCents;
  final int supplierBalanceCents;

  const PartyControlAccountBalances({
    required this.customerBalanceCents,
    required this.supplierBalanceCents,
  });
}

/// Rebuilds AR/AP sub-ledger totals from immutable openings and movements.
///
/// Cached `customers.balance_cents` / `suppliers.balance_cents` are deliberately
/// excluded: they are operational caches and may drift or represent a later
/// instant than the GL trial balance being reconciled.
class PartyControlAccountBalanceService {
  final AppDatabase _db;

  const PartyControlAccountBalanceService(this._db);

  Future<PartyControlAccountBalances> load({required DateTime asOf}) async {
    final customers = await (_db.select(
      _db.customers,
    )..where((c) => c.createdAt.isSmallerOrEqualValue(asOf))).get();
    final suppliers = await (_db.select(
      _db.suppliers,
    )..where((s) => s.createdAt.isSmallerOrEqualValue(asOf))).get();

    var customerTotal = customers.fold<int>(
      0,
      (sum, customer) => sum + customer.openingBalanceCents.toBigInt().toInt(),
    );
    var supplierTotal = suppliers.fold<int>(
      0,
      (sum, supplier) => sum + supplier.openingBalanceCents.toBigInt().toInt(),
    );

    final customerTransactions = await (_db.select(
      _db.customerTransactions,
    )..where((t) => t.transactionDate.isSmallerOrEqualValue(asOf))).get();
    for (final transaction in customerTransactions) {
      if (PartyLedgerMovementPolicy.affectsBalance(
        transaction.transactionType,
      )) {
        customerTotal += transaction.amountCents.toBigInt().toInt();
      }
    }

    final supplierTransactions = await (_db.select(
      _db.supplierTransactions,
    )..where((t) => t.transactionDate.isSmallerOrEqualValue(asOf))).get();
    for (final transaction in supplierTransactions) {
      if (PartyLedgerMovementPolicy.affectsBalance(
        transaction.transactionType,
      )) {
        supplierTotal += transaction.amountCents.toBigInt().toInt();
      }
    }

    return PartyControlAccountBalances(
      customerBalanceCents: customerTotal,
      supplierBalanceCents: supplierTotal,
    );
  }
}
