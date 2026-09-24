import 'package:drift/drift.dart';
import '../database/app_database.dart';
import 'logging_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// BALANCE SERVICE
// ══════════════════════════════════════════════════════════════════════════════

/// Static-only service for centralised party-balance adjustments.
///
/// Takes a [DatabaseAccessor] parameter so it works inside DAO transactions.
/// Same pattern as `TaxCalculationService` / `StockService`.
class BalanceService {
  BalanceService._();

  static const String _tag = 'BalanceService';

  /// Adjust customer balance by [deltaCents].
  ///
  /// **Positive** = customer owes more (e.g. new sale on credit).
  /// **Negative** = customer owes less (e.g. credit-note refund).
  ///
  /// No-op when [deltaCents] == 0.
  static Future<void> adjustCustomerBalance(
    DatabaseAccessor<AppDatabase> dao, {
    required int customerId,
    required int deltaCents,
  }) async {
    assert(customerId > 0, 'customerId must be positive');
    if (deltaCents == 0) return;

    LoggingService.debug(
      'adjustCustomerBalance: customer=$customerId delta=$deltaCents',
      tag: _tag,
    );

    final customer = await dao
        .customSelect(
          'SELECT balance_cents FROM customers WHERE id = ?',
          variables: [Variable.withInt(customerId)],
        )
        .getSingleOrNull();

    if (customer != null) {
      final oldBalance = customer.read<int>('balance_cents');
      final newBalance = oldBalance + deltaCents;
      await dao.customUpdate(
        'UPDATE customers SET balance_cents = ?, updated_at = ? WHERE id = ?',
        variables: [
          Variable.withInt(newBalance),
          Variable.withString(DateTime.now().toIso8601String()),
          Variable.withInt(customerId),
        ],
        updates: {dao.attachedDatabase.customers},
        updateKind: UpdateKind.update,
      );

      LoggingService.debug(
        'adjustCustomerBalance: customer=$customerId '
        'old=$oldBalance new=$newBalance',
        tag: _tag,
      );
    }
  }

  /// Adjust supplier balance by [deltaCents].
  ///
  /// **Positive** = we owe more (e.g. new purchase posted).
  /// **Negative** = we owe less (e.g. credit-note from supplier).
  ///
  /// No-op when [deltaCents] == 0.
  static Future<void> adjustSupplierBalance(
    DatabaseAccessor<AppDatabase> dao, {
    required int supplierId,
    required int deltaCents,
  }) async {
    assert(supplierId > 0, 'supplierId must be positive');
    if (deltaCents == 0) return;

    LoggingService.debug(
      'adjustSupplierBalance: supplier=$supplierId delta=$deltaCents',
      tag: _tag,
    );

    final supplier = await dao
        .customSelect(
          'SELECT balance_cents FROM suppliers WHERE id = ?',
          variables: [Variable.withInt(supplierId)],
        )
        .getSingleOrNull();

    if (supplier != null) {
      final oldBalance = supplier.read<int>('balance_cents');
      final newBalance = oldBalance + deltaCents;
      await dao.customUpdate(
        'UPDATE suppliers SET balance_cents = ?, updated_at = ? WHERE id = ?',
        variables: [
          Variable.withInt(newBalance),
          Variable.withString(DateTime.now().toIso8601String()),
          Variable.withInt(supplierId),
        ],
        updates: {dao.attachedDatabase.suppliers},
        updateKind: UpdateKind.update,
      );

      LoggingService.debug(
        'adjustSupplierBalance: supplier=$supplierId '
        'old=$oldBalance new=$newBalance',
        tag: _tag,
      );
    }
  }
}
