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

  /// Create a new supplier
  Future<int> createSupplier({
    required String name,
    String? email,
    String? phone,
    String? address,
    required int currencyId,
    Decimal? initialBalance,
  });

  /// Update an existing supplier
  Future<bool> updateSupplier(Supplier supplier);

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

  /// Update supplier balance
  Future<void> updateSupplierBalance(int supplierId, int newBalanceCents);

  /// Record a supplier transaction (payment, purchase, return, etc.)
  Future<int> recordTransaction({
    required int supplierId,
    required String transactionType,
    required int amountCents,
    required int currencyId,
    String? description,
    int? referenceId,
    String? referenceType,
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
