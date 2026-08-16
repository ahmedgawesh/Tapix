import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/party_ledger_movement_policy.dart';
import 'party_statement_ledger_service.dart';

/// A signed sub-ledger movement used by the aging calculator.
///
/// Positive amounts create receivables/payables. Negative amounts (payments,
/// returns, discounts, reversals, and negative adjustments) retire the oldest
/// positive amounts first.
class PartyAgingMovement {
  final int id;
  final int amountCents;
  final DateTime transactionDate;

  const PartyAgingMovement({
    required this.id,
    required this.amountCents,
    required this.transactionDate,
  });
}

class PartyAgingBuckets {
  final int currentCents;
  final int days30Cents;
  final int days60Cents;
  final int days90Cents;
  final int over90Cents;

  const PartyAgingBuckets({
    this.currentCents = 0,
    this.days30Cents = 0,
    this.days60Cents = 0,
    this.days90Cents = 0,
    this.over90Cents = 0,
  });

  int get totalCents =>
      currentCents + days30Cents + days60Cents + days90Cents + over90Cents;
}

class PartyAgingRecord {
  final int partyId;
  final String partyName;
  final String? segment;
  final String? phone;
  final String? email;
  final PartyAgingBuckets buckets;

  const PartyAgingRecord({
    required this.partyId,
    required this.partyName,
    this.segment,
    this.phone,
    this.email,
    required this.buckets,
  });
}

class _OutstandingCharge {
  final DateTime? transactionDate;
  int remainingCents;

  _OutstandingCharge({
    required this.transactionDate,
    required this.remainingCents,
  });

  bool get isOpeningBalance => transactionDate == null;
}

/// Pure FIFO aging calculation shared by customer and supplier reports.
class PartyAgingCalculator {
  const PartyAgingCalculator._();

  static PartyAgingBuckets calculate({
    required int openingBalanceCents,
    required Iterable<PartyAgingMovement> movements,
    required DateTime asOf,
  }) {
    final asOfDay = DateTime(asOf.year, asOf.month, asOf.day);
    final ordered =
        movements.where((movement) {
          final movementDay = DateTime(
            movement.transactionDate.year,
            movement.transactionDate.month,
            movement.transactionDate.day,
          );
          return !movementDay.isAfter(asOfDay);
        }).toList()..sort((a, b) {
          final byDate = a.transactionDate.compareTo(b.transactionDate);
          return byDate != 0 ? byDate : a.id.compareTo(b.id);
        });

    final charges = <_OutstandingCharge>[];
    var creditsCents = 0;

    // The actual age of a balance brought into Tapix is unknown, so it is
    // conservatively treated as the oldest balance (>90 days).
    if (openingBalanceCents > 0) {
      charges.add(
        _OutstandingCharge(
          transactionDate: null,
          remainingCents: openingBalanceCents,
        ),
      );
    } else if (openingBalanceCents < 0) {
      creditsCents = -openingBalanceCents;
    }

    for (final movement in ordered) {
      if (movement.amountCents > 0) {
        charges.add(
          _OutstandingCharge(
            transactionDate: movement.transactionDate,
            remainingCents: movement.amountCents,
          ),
        );
      } else if (movement.amountCents < 0) {
        creditsCents += -movement.amountCents;
      }
    }

    // Credits retire the oldest charges first (FIFO), regardless of their
    // transaction type. This also handles voids and reversals correctly.
    for (final charge in charges) {
      if (creditsCents == 0) break;
      final applied = creditsCents < charge.remainingCents
          ? creditsCents
          : charge.remainingCents;
      charge.remainingCents -= applied;
      creditsCents -= applied;
    }

    var current = 0;
    var days30 = 0;
    var days60 = 0;
    var days90 = 0;
    var over90 = 0;

    for (final charge in charges) {
      if (charge.remainingCents <= 0) continue;
      if (charge.isOpeningBalance) {
        over90 += charge.remainingCents;
        continue;
      }

      final date = charge.transactionDate!;
      final movementDay = DateTime(date.year, date.month, date.day);
      final ageDays = asOfDay.difference(movementDay).inDays;
      if (ageDays <= 0) {
        current += charge.remainingCents;
      } else if (ageDays <= 30) {
        days30 += charge.remainingCents;
      } else if (ageDays <= 60) {
        days60 += charge.remainingCents;
      } else if (ageDays <= 90) {
        days90 += charge.remainingCents;
      } else {
        over90 += charge.remainingCents;
      }
    }

    return PartyAgingBuckets(
      currentCents: current,
      days30Cents: days30,
      days60Cents: days60,
      days90Cents: days90,
      over90Cents: over90,
    );
  }
}

/// Loads signed party ledgers and applies the shared FIFO aging algorithm.
class PartyAgingLedgerService {
  final AppDatabase _db;

  const PartyAgingLedgerService(this._db);

  Future<List<PartyAgingRecord>> loadCustomers({required DateTime asOf}) async {
    final endExclusive = PartyLedgerDatePolicy.exclusiveEndOfDay(asOf);
    final customers = await (_db.select(
      _db.customers,
    )..where((c) => c.createdAt.isSmallerThanValue(endExclusive))).get();
    final transactions =
        await (_db.select(_db.customerTransactions)
              ..where((t) => t.transactionDate.isSmallerThanValue(endExclusive))
              ..orderBy([
                (t) => OrderingTerm.asc(t.transactionDate),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();

    final movementsByCustomer = <int, List<PartyAgingMovement>>{};
    for (final transaction in transactions) {
      if (!PartyLedgerMovementPolicy.affectsBalance(
        transaction.transactionType,
      )) {
        continue;
      }
      movementsByCustomer
          .putIfAbsent(transaction.customerId, () => <PartyAgingMovement>[])
          .add(
            PartyAgingMovement(
              id: transaction.id,
              amountCents: transaction.amountCents.toBigInt().toInt(),
              transactionDate: transaction.transactionDate,
            ),
          );
    }

    final records = <PartyAgingRecord>[];
    for (final customer in customers) {
      final buckets = PartyAgingCalculator.calculate(
        openingBalanceCents: customer.openingBalanceCents.toBigInt().toInt(),
        movements: movementsByCustomer[customer.id] ?? const [],
        asOf: asOf,
      );
      if (buckets.totalCents <= 0) continue;
      records.add(
        PartyAgingRecord(
          partyId: customer.id,
          partyName: customer.name,
          segment: customer.segment,
          phone: customer.phone,
          email: customer.email,
          buckets: buckets,
        ),
      );
    }
    return records;
  }

  Future<List<PartyAgingRecord>> loadSuppliers({required DateTime asOf}) async {
    final endExclusive = PartyLedgerDatePolicy.exclusiveEndOfDay(asOf);
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

    final movementsBySupplier = <int, List<PartyAgingMovement>>{};
    for (final transaction in transactions) {
      if (!PartyLedgerMovementPolicy.affectsBalance(
        transaction.transactionType,
      )) {
        continue;
      }
      movementsBySupplier
          .putIfAbsent(transaction.supplierId, () => <PartyAgingMovement>[])
          .add(
            PartyAgingMovement(
              id: transaction.id,
              amountCents: transaction.amountCents.toBigInt().toInt(),
              transactionDate: transaction.transactionDate,
            ),
          );
    }

    final records = <PartyAgingRecord>[];
    for (final supplier in suppliers) {
      final buckets = PartyAgingCalculator.calculate(
        openingBalanceCents: supplier.openingBalanceCents.toBigInt().toInt(),
        movements: movementsBySupplier[supplier.id] ?? const [],
        asOf: asOf,
      );
      if (buckets.totalCents <= 0) continue;
      records.add(
        PartyAgingRecord(
          partyId: supplier.id,
          partyName: supplier.name,
          phone: supplier.phone,
          email: supplier.email,
          buckets: buckets,
        ),
      );
    }
    return records;
  }
}
