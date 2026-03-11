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

  /// Update customer balance
  Future<void> updateCustomerBalance(int customerId, int newBalanceCents);

  /// Update customer loyalty enabled status
  Future<void> updateCustomerLoyaltyEnabled(int customerId, bool loyaltyEnabled);

  /// Record a customer transaction (payment, discount, return, etc.)
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
