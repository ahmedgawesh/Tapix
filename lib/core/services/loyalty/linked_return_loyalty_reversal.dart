import 'package:drift/drift.dart';
import '../../database/app_database.dart';

/// Restores exactly the recorded deduction, once, in the caller's void
/// transaction. No current rate, tier, or program setting rewrites history.
class LinkedReturnLoyaltyReversal {
  static Future<void> restore(
    AppDatabase db,
    int returnId,
  ) => db.transaction(() async {
    final source = await db
        .customSelect(
          'SELECT s.customer_id FROM sale_returns r JOIN sales s ON s.id=r.sale_id WHERE r.id=?',
          variables: [Variable.withInt(returnId)],
        )
        .getSingle();
    final customerId = source.readNullable<int>('customer_id');
    if (customerId == null) return;
    final rows = await db
        .customSelect(
          "SELECT COALESCE(SUM(points),0) AS net FROM loyalty_point_transactions WHERE customer_id=? AND reference_id=? AND reference_type IN ('sale_return','sale_return_void')",
          variables: [Variable.withInt(customerId), Variable.withInt(returnId)],
        )
        .getSingle();
    final restore = -rows.read<int>('net');
    if (restore <= 0) return;
    final customer = await (db.select(
      db.customers,
    )..where((c) => c.id.equals(customerId))).getSingle();
    final balance = customer.loyaltyPointsBalance + restore;
    await db
        .into(db.loyaltyPointTransactions)
        .insert(
          LoyaltyPointTransactionsCompanion(
            customerId: Value(customerId),
            transactionType: const Value('earn'),
            points: Value(restore),
            balanceAfter: Value(balance),
            source: const Value('sale_return_void'),
            referenceType: const Value('sale_return_void'),
            referenceId: Value(returnId),
            description: Value(
              'Restored recorded points for voided return #$returnId',
            ),
            transactionDate: Value(DateTime.now()),
            createdAt: Value(DateTime.now()),
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
  });
}
