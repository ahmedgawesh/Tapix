import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../datasources/supplier_local_datasource.dart';

/// Implementation of SupplierRepository
class SupplierRepositoryImpl implements SupplierRepository {
  final SupplierLocalDatasource _datasource;

  SupplierRepositoryImpl(this._datasource);

  @override
  Stream<List<Supplier>> watchAllSuppliers({bool? isActive}) {
    return _datasource.watchAllSuppliers(isActive: isActive);
  }

  @override
  Stream<Supplier?> watchSupplier(int id) {
    return _datasource.watchSupplier(id);
  }

  @override
  Future<Supplier?> getSupplier(int id) {
    return _datasource.getSupplier(id);
  }

  @override
  Future<List<Supplier>> searchSuppliers(String query, {bool? isActive}) {
    return _datasource.searchSuppliers(query, isActive: isActive);
  }

  @override
  Future<int> createSupplier({
    required String name,
    String? email,
    String? phone,
    String? address,
    required int currencyId,
    Decimal? initialBalance,
  }) {
    final companion = SuppliersCompanion(
      name: Value(name),
      email: Value(email),
      phone: Value(phone),
      address: Value(address),
      currencyId: Value(currencyId),
      balanceCents: Value(initialBalance ?? Decimal.zero),
      isActive: const Value(true),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    );
    return _datasource.createSupplier(companion);
  }

  @override
  Future<bool> updateSupplier(Supplier supplier) {
    return _datasource.updateSupplier(supplier);
  }

  @override
  Future<int> deleteSupplier(int id) {
    return _datasource.deleteSupplier(id);
  }

  @override
  Stream<int> watchSupplierCount({bool? isActive}) {
    return _datasource.watchSupplierCount(isActive: isActive);
  }

  @override
  Stream<int> watchTotalBalanceCents() {
    return _datasource.watchTotalBalanceCents();
  }

  @override
  Stream<List<Supplier>> watchSuppliersWithPositiveBalance() {
    return _datasource.watchSuppliersWithPositiveBalance();
  }

  @override
  Stream<List<Supplier>> watchTopSuppliersByBalance({int limit = 5}) {
    return _datasource.watchTopSuppliersByBalance(limit: limit);
  }

  @override
  Future<void> updateSupplierBalance(int supplierId, int newBalanceCents) {
    return _datasource.updateSupplierBalance(supplierId, newBalanceCents);
  }

  @override
  Future<int> recordTransaction({
    required int supplierId,
    required String transactionType,
    required int amountCents,
    required int currencyId,
    String? description,
    int? referenceId,
    String? referenceType,
  }) {
    final companion = SupplierTransactionsCompanion(
      supplierId: Value(supplierId),
      transactionType: Value(transactionType),
      amountCents: Value(Decimal.fromInt(amountCents)),
      currencyId: Value(currencyId),
      description: Value(description),
      referenceId: Value(referenceId),
      referenceType: Value(referenceType),
      transactionDate: Value(DateTime.now()),
      createdAt: Value(DateTime.now()),
    );
    return _datasource.createTransaction(companion);
  }

  @override
  Stream<List<SupplierTransaction>> watchSupplierTransactions(int supplierId) {
    return _datasource.watchSupplierTransactions(supplierId);
  }

  @override
  Future<List<SupplierTransaction>> getSupplierTransactions(
    int supplierId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _datasource.getSupplierTransactions(
      supplierId,
      startDate: startDate,
      endDate: endDate,
    );
  }
}
