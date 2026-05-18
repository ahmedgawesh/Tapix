import 'package:decimal/decimal.dart';
import '../../../../core/database/app_database.dart';

/// Domain repository interface for customer operations
abstract class CustomerRepository {
  /// Watch all customers with optional active filter
  Stream<List<Customer>> watchAllCustomers({bool? isActive});

  /// Watch a single customer by ID
  Stream<Customer?> watchCustomer(int id);

  /// Get a single customer by ID
  Future<Customer?> getCustomer(int id);

  /// Search customers by name, phone, or email
  Future<List<Customer>> searchCustomers(String query, {bool? isActive});

  /// Create a new customer
  Future<int> createCustomer({
    required String name,
    String? email,
    String? phone,
    String? address,
    required int currencyId,
    Decimal? initialBalance,
    String segment = 'retail',
    bool loyaltyEnabled = true,
  });

  /// Update an existing customer
  Future<bool> updateCustomer(Customer customer);

  /// Delete a customer by ID
  Future<int> deleteCustomer(int id);

  /// Watch customer count
  Stream<int> watchCustomerCount({bool? isActive});

  /// Watch total balance in cents
  Stream<int> watchTotalBalanceCents();

  /// Watch customers with positive balance (receivables)
  Stream<List<Customer>> watchCustomersWithPositiveBalance();

  /// Watch top customers by balance
  Stream<List<Customer>> watchTopCustomersByBalance({int limit = 5});

  /// DEPRECATED: Direct balance updates are DISABLED to prevent GL mismatch.
  ///
  /// Phase 1.3 (May 2026) closes the last absolute-set path to
  /// `customers.balance_cents`. Mirrors the supplier-side guard.
  /// Use [recordTransaction] with `transactionType: 'adjustment'` instead;
  /// that path atomically posts a paired journal entry through
  /// `JournalEntryService` and applies the balance delta via `BalanceService`.
  @Deprecated('Use recordTransaction(transactionType: "adjustment") instead')
  Future<void> updateCustomerBalance(int customerId, int newBalanceCents);

  /// Update customer loyalty enabled status
  Future<void> updateCustomerLoyaltyEnabled(int customerId, bool loyaltyEnabled);

  /// Record a customer transaction (payment, discount, return, etc.).
  ///
  /// Prefer the [CustomerPostingApi] extension helpers
  /// (`recordPayment` / `recordDiscount`) in UI code so the sign-flip
  /// rule (payments reduce AR and therefore persist as negative cents)
  /// lives in exactly one place. Direct calls into this method are
  /// reserved for paths that already know the signed amount (opening
  /// balances, system reversals, returns posted by the unified
  /// `ReturnPostingService`).
  Future<int> recordTransaction({
    required int customerId,
    required String transactionType,
    required int amountCents,
    required int currencyId,
    String? description,
    int? referenceId,
    String? referenceType,
    String? discountType,
    DateTime? transactionDate,
  });

  /// Atomically adjust a customer's balance to [desiredBalanceCents].
  ///
  /// Phase 1.4 (May 2026) — single business-logic entry point for the
  /// "edit opening balance" path that previously lived inline in
  /// `customer_form_bloc.dart`. The presentation layer must not read the
  /// current balance, compute a delta, and post a transaction on its own:
  /// that 3-step recipe is TOCTOU-prone and easy to forget.
  ///
  /// Implementation contract:
  ///   1. Read the current `customers.balance_cents` inside a transaction.
  ///   2. Compute `delta = desiredBalanceCents − current`.
  ///   3. If `delta == 0` → no-op, return `null` (idempotent).
  ///   4. Otherwise call [recordTransaction] with `transactionType:
  ///      'adjustment'` and the signed `delta`, which posts the paired
  ///      journal entry through `JournalEntryService` and writes the
  ///      balance via `BalanceService`.
  ///
  /// Returns the recorded transaction id, or `null` when no change was
  /// needed.
  Future<int?> adjustOpeningBalance({
    required int customerId,
    required int desiredBalanceCents,
    String? description,
  });

  /// Get a single customer transaction by ID
  Future<CustomerTransaction?> getTransaction(int transactionId);

  /// Update a payment or discount transaction amount.
  /// Checks accounting period is open, voids old journal entries,
  /// creates new ones, adjusts balance, and logs audit trail.
  /// Returns the old transaction for audit.
  Future<CustomerTransaction> updateTransaction({
    required int transactionId,
    required int newAmountCents,
    String? newDescription,
  });

  /// Watch customer transactions
  Stream<List<CustomerTransaction>> watchCustomerTransactions(int customerId);

  /// Get customer transactions with optional date range
  Future<List<CustomerTransaction>> getCustomerTransactions(
    int customerId, {
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Get customers by segment
  Stream<List<Customer>> watchCustomersBySegment(String segment);

  /// Get customer count by segment
  Stream<Map<String, int>> watchCustomerCountBySegment();
}

/// Phase 3.5.3 — centralised posting helpers for customer ledger entries.
///
/// Implemented as an extension (rather than as default members on the
/// abstract class) because [CustomerRepository] is consumed via Dart's
/// `implements` clause throughout the codebase, which by design does not
/// inherit method bodies. An extension exposes the same call site
/// (`sl<CustomerRepository>().recordPayment(...)`) without forcing every
/// implementer to re-declare the helper.
///
/// Why these helpers exist:
///
/// * Widgets must never compute `-amountCents` themselves. The sign
///   convention ("a payment shrinks AR and therefore persists negative")
///   is an accounting rule that belongs next to the ledger, not in a
///   `FilledButton.onPressed`.
/// * If the convention is ever inverted (e.g. switching to a
///   contra-sign-on-write strategy), there is exactly one place to
///   change.
/// * Inputs are validated at the boundary: passing `amountCents <= 0`
///   throws [ArgumentError] so a stale form value can never silently
///   post a zero-amount or sign-flipped transaction.
extension CustomerPostingApi on CustomerRepository {
  /// "The customer paid us" — caller passes the positive amount the
  /// operator typed; the repository negates it before persisting.
  Future<int> recordPayment({
    required int customerId,
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
      customerId: customerId,
      transactionType: 'payment',
      amountCents: -amountCents,
      currencyId: currencyId,
      description: description,
      transactionDate: transactionDate,
    );
  }

  /// "We granted the customer a discount" — same contract as
  /// [recordPayment] plus the [discountType] tag (defaults to `cash`).
  Future<int> recordDiscount({
    required int customerId,
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
      customerId: customerId,
      transactionType: 'discount',
      amountCents: -amountCents,
      currencyId: currencyId,
      description: description,
      discountType: discountType,
      transactionDate: transactionDate,
    );
  }
}
