import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import '../../payments/checkout_settlement.dart';

/// Validates against the issuing branch. Call inside the sale transaction.
/// Point value is captured in sale_payments; later rate changes cannot rewrite it.
class SaleLoyaltySettlement {
  static Future<int> validate(
    AppDatabase db, {
    required int? customerId,
    required int currencyId,
    required int points,
    required int expectedValueCents,
    required int totalCents,
  }) async {
    if (points == 0 && expectedValueCents == 0) return 0;
    if (points <= 0 || customerId == null) {
      throw StateError('loyalty_invalid_redemption');
    }
    final settings = await db.select(db.loyaltySettingsTable).getSingleOrNull();
    final customer = await db.customerDao.getCustomer(customerId);
    if (settings == null ||
        !settings.isEnabled ||
        !settings.allowPointsRedemption ||
        settings.pointValueCents <= 0 ||
        customer == null ||
        !customer.isActive ||
        !customer.loyaltyEnabled ||
        customer.currencyId != currencyId) {
      throw StateError('loyalty_unavailable');
    }
    final value = points * settings.pointValueCents;
    if (points < settings.minRedemptionPoints ||
        points > customer.loyaltyPointsBalance ||
        value != expectedValueCents ||
        value > totalCents ||
        value * 10000 > totalCents * settings.maxRedemptionPercentBps) {
      throw StateError('loyalty_balance_or_policy_changed');
    }
    return value;
  }

  static Future<void> changePoints(
    AppDatabase db, {
    required int customerId,
    required int points,
    required int referenceId,
    required String referenceType,
  }) async {
    if (points == 0) return;
    final customer = await db.customerDao.getCustomer(customerId);
    if (customer == null || customer.loyaltyPointsBalance + points < 0) {
      throw StateError('loyalty_insufficient_points');
    }
    final balance = customer.loyaltyPointsBalance + points;
    await db
        .into(db.loyaltyPointTransactions)
        .insert(
          LoyaltyPointTransactionsCompanion(
            customerId: Value(customerId),
            transactionType: Value(points > 0 ? 'earn' : 'redeem'),
            points: Value(points),
            balanceAfter: Value(balance),
            source: Value(referenceType),
            referenceId: Value(referenceId),
            referenceType: Value(referenceType),
            description: Value('$referenceType #$referenceId'),
          ),
        );
    await (db.update(
      db.customers,
    )..where((c) => c.id.equals(customerId))).write(
      CustomersCompanion(
        loyaltyPointsBalance: Value(balance),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Cumulative proration avoids losing a point across multiple partial returns.
  static Future<({int points, int cents})> returnShare(
    AppDatabase db,
    int saleId,
    int returnTotal,
  ) async {
    final sale = await (db.select(
      db.sales,
    )..where((s) => s.id.equals(saleId))).getSingle();
    final payments =
        await (db.select(db.salePayments)..where(
              (p) =>
                  p.saleId.equals(saleId) & p.paymentMethod.equals('loyalty'),
            ))
            .get();
    if (payments.isEmpty) return (points: 0, cents: 0);
    final points = payments.fold<int>(
      0,
      (s, p) => s + int.parse(p.reference!.split(':').last),
    );
    final value = payments.fold<int>(
      0,
      (s, p) => s + p.amountCents.toBigInt().toInt(),
    );
    final returns = await (db.select(
      db.saleReturns,
    )..where((r) => r.saleId.equals(saleId) & r.status.equals('posted'))).get();
    final priorTotal = returns.fold<int>(
      0,
      (s, r) => s + r.totalCents.toBigInt().toInt(),
    );
    var restored = 0;
    for (final r in returns) {
      final rows =
          await (db.select(db.loyaltyPointTransactions)..where(
                (t) =>
                    t.referenceId.equals(r.id) &
                    t.referenceType.equals('sale_return_redemption'),
              ))
              .get();
      restored += rows.fold<int>(0, (s, t) => s + t.points);
    }
    final total = sale.totalCents.toBigInt().toInt();
    var priorCents = 0;
    for (final r in returns) {
      final row = await db
          .customSelect(
            "SELECT COALESCE(SUM(amount_cents),0) amount FROM customer_transactions WHERE reference_type='sale_return' AND reference_id=? AND transaction_type='return_settlement_loyalty'",
            variables: [Variable.withInt(r.id)],
          )
          .getSingle();
      priorCents += row.read<int>('amount');
    }
    final targetCents = (value * (priorTotal + returnTotal) ~/ total).clamp(
      0,
      value,
    );
    final cents = (targetCents - priorCents).clamp(0, returnTotal);
    final targetPoints = targetCents ~/ (value ~/ points);
    return (
      points: (targetPoints - restored).clamp(0, points - restored),
      cents: cents,
    );
  }

  /// Keep the requested cash/card/cheque split, reducing its refundable value
  /// by the portion returned as points. Unallocated credit stays on account.
  static List<CheckoutPaymentAllocation> returnAllocations({
    required int totalCents,
    required int loyaltyCents,
    required String method,
    required List<CheckoutPaymentAllocation> requested,
    DateTime? dueDate,
  }) {
    var remaining = totalCents - loyaltyCents;
    final legs = requested.isNotEmpty
        ? requested
        : [
            if (method != 'credit' && remaining > 0)
              CheckoutPaymentAllocation(
                method: method,
                amountCents: remaining,
                dueDate: dueDate,
                reference: 'sale-return',
              ),
          ];
    return [
      for (final leg in legs)
        if (remaining > 0)
          (() {
            final amount = leg.amountCents.clamp(0, remaining);
            remaining -= amount;
            return CheckoutPaymentAllocation(
              method: leg.method,
              amountCents: amount,
              reference: leg.reference,
              bankName: leg.bankName,
              issueDate: leg.issueDate,
              dueDate: leg.dueDate,
              note: leg.note,
            );
          })(),
      CheckoutPaymentAllocation(method: 'loyalty', amountCents: loyaltyCents),
    ];
  }
}
