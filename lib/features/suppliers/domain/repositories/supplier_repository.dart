import 'package:decimal/decimal.dart';
import '../../../../core/database/app_database.dart';

/// Domain repository interface for supplier operations
abstract class SupplierRepository {
  /// Watch all suppliers with optional active filter
  Stream<List<Supplier>> watchAllSuppliers({bool? isActive});

  /// Watch a single supplier by ID
  Stream<Supplier?> watchSupplier(int id);

  /// Get a single supplier by ID
  Future<Supplier?> getSupplier(int id);

  /// Search suppliers by name, phone, or email
  Future<List<Supplier>> searchSuppliers(String query, {bool? isActive});

  /// Checks all suppliers, including inactive ones. This is an early UX check;
  /// the database unique index is the final authority.
  Future<bool> isProductCodeAvailable(String? code, {int? excludingSupplierId});

  /// A saved document/history or issued source identity locks the prefix.
  Future<bool> isProductCodeLocked(int supplierId);

  /// Create a new supplier
  Future<int> createSupplier({
    required String name,
    String? email,
    String? phone,
    String? address,
    String? productCode,
    required int currencyId,
    Decimal? initialBalance,
  });

  /// Update an existing supplier
  Future<bool> updateSupplier(Supplier supplier);

  /// Update the active flag only; retain the code, balance and history.
  Future<void> setSupplierActive(int supplierId, bool isActive);

  /// Delete a supplier by ID
  Future<int> deleteSupplier(int id);

  /// Watch supplier count
  Stream<int> watchSupplierCount({bool? isActive});

  /// Watch total balance in cents
  Stream<int> watchTotalBalanceCents();

  /// Watch suppliers with positive balance (payables)
  Stream<List<Supplier>> watchSuppliersWithPositiveBalance();

  /// Watch top suppliers by balance
  Stream<List<Supplier>> watchTopSuppliersByBalance({int limit = 5});

  /// DEPRECATED: Direct balance updates are DISABLED to prevent GL mismatch.
  /// Use [recordTransaction] with transactionType 'adjustment' instead.
  @Deprecated('Use recordTransaction(transactionType: "adjustment") instead')
  Future<void> updateSupplierBalance(int supplierId, int newBalanceCents);

  /// Record a supplier transaction (payment, purchase, return, etc.).
  ///
  /// Prefer the [SupplierPostingApi] extension helpers
  /// (`recordPayment` / `recordDiscount`) in UI code. The sign-flip rule
  /// (a payment we issue reduces what we owe the supplier and therefore
  /// persists as negative cents) is owned by the repository, never by
  /// widgets. Direct calls remain available for system flows (opening
  /// balances, reversals, returns posted by the unified
  /// `ReturnPostingService`) that already carry a pre-signed amount.
  Future<int> recordTransaction({
    required int supplierId,
    required String transactionType,
    required int amountCents,
    required int currencyId,
    String? description,
    int? referenceId,
    String? referenceType,
    String? discountType,
    DateTime? transactionDate,
  });

  /// Atomically adjust a supplier's balance to [desiredBalanceCents].
  ///
  /// Phase 1.4 (May 2026) — mirror of `CustomerRepository.adjustOpeningBalance`.
  /// Replaces the scattered (read → delta → recordTransaction) recipe that
  /// previously lived in `supplier_form_bloc.dart`. The repository owns the
  /// atomicity guarantee (read + post in the same DB transaction) and the
  /// "no-op when delta is zero" rule, so the bloc only has to provide the
  /// user-entered target balance.
  ///
  /// Returns the recorded `supplier_transactions` row id, or `null` when
  /// the balance is already at the desired value.
  Future<int?> adjustOpeningBalance({
    required int supplierId,
    required int desiredBalanceCents,
    String? description,
  });

  /// Get a single supplier transaction by ID
  Future<SupplierTransaction?> getTransaction(int transactionId);

  /// Update a payment or discount transaction amount.
  /// Checks accounting period is open, voids old journal entries,
  /// creates new ones, adjusts balance, and logs audit trail.
  /// Returns the old transaction for audit.
  Future<SupplierTransaction> updateTransaction({
    required int transactionId,
    required int newAmountCents,
    String? newDescription,
  });

  /// Watch supplier transactions
  Stream<List<SupplierTransaction>> watchSupplierTransactions(int supplierId);

  /// Get supplier transactions with optional date range
  Future<List<SupplierTransaction>> getSupplierTransactions(
    int supplierId, {
    DateTime? startDate,
    DateTime? endDate,
  });
}

/// Phase 3.5.3 — centralised posting helpers for the supplier ledger.
///
/// Mirrors `CustomerPostingApi` in shape and rationale. Implemented as
/// an extension because [SupplierRepository] is consumed via Dart's
/// `implements` clause, which does not inherit method bodies.
extension SupplierPostingApi on SupplierRepository {
  /// "We paid the supplier" — caller passes the positive amount; the
  /// repository negates it before persisting because the supplier ledger
  /// represents "what we still owe": a payment shrinks that figure.
  Future<int> recordPayment({
    required int supplierId,
    required int amountCents,
    required int currencyId,
    String? description,
    DateTime? transactionDate,
  }) {
    if (amountCents <= 0) {
      throw ArgumentError.value(
        amountCents,
        'amountCents',
        'recordPayment requires a strictly positive amount; the sign flip '
            'is performed inside the repository.',
      );
    }
    return recordTransaction(
      supplierId: supplierId,
      transactionType: 'payment',
      amountCents: -amountCents,
      currencyId: currencyId,
      description: description,
      transactionDate: transactionDate,
    );
  }

  /// "The supplier granted us a discount" — same convention as
  /// [recordPayment], with an optional [discountType] tag.
  Future<int> recordDiscount({
    required int supplierId,
    required int amountCents,
    required int currencyId,
    String discountType = 'cash',
    String? description,
    DateTime? transactionDate,
  }) {
    if (amountCents <= 0) {
      throw ArgumentError.value(
        amountCents,
        'amountCents',
        'recordDiscount requires a strictly positive amount.',
      );
    }
    return recordTransaction(
      supplierId: supplierId,
      transactionType: 'discount',
      amountCents: -amountCents,
      currencyId: currencyId,
      description: description,
      discountType: discountType,
      transactionDate: transactionDate,
    );
  }
}
