import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/supplier_dao.dart';

/// Local datasource for supplier operations
abstract class SupplierLocalDatasource {
  Stream<List<Supplier>> watchAllSuppliers({bool? isActive});
  Stream<Supplier?> watchSupplier(int id);
  Future<Supplier?> getSupplier(int id);
  Future<List<Supplier>> searchSuppliers(String query, {bool? isActive});
  Future<int> createSupplier(SuppliersCompanion supplier);
  Future<bool> updateSupplier(Supplier supplier);
  Future<int> deleteSupplier(int id);
  Stream<int> watchSupplierCount({bool? isActive});
  Stream<int> watchTotalBalanceCents();
  Stream<List<Supplier>> watchSuppliersWithPositiveBalance();
  Stream<List<Supplier>> watchTopSuppliersByBalance({int limit = 5});
  Future<void> updateSupplierBalance(int supplierId, int newBalanceCents);
  Future<int> createTransaction(SupplierTransactionsCompanion transaction);
  Future<SupplierTransaction?> getTransaction(int transactionId);
  Stream<List<SupplierTransaction>> watchSupplierTransactions(int supplierId);
  Future<List<SupplierTransaction>> getSupplierTransactions(
    int supplierId, {
    DateTime? startDate,
    DateTime? endDate,
  });
}

/// Implementation of SupplierLocalDatasource using SupplierDao
class SupplierLocalDatasourceImpl implements SupplierLocalDatasource {
  final SupplierDao _supplierDao;

  SupplierLocalDatasourceImpl(this._supplierDao);

  @override
  Stream<List<Supplier>> watchAllSuppliers({bool? isActive}) {
    return _supplierDao.watchAllSuppliers(isActive: isActive);
  }

  @override
  Stream<Supplier?> watchSupplier(int id) {
    return _supplierDao.watchSupplier(id);
  }

  @override
  Future<Supplier?> getSupplier(int id) {
    return _supplierDao.getSupplier(id);
  }

  @override
  Future<List<Supplier>> searchSuppliers(String query, {bool? isActive}) {
    return _supplierDao.searchSuppliers(query, isActive: isActive);
  }

  @override
  Future<int> createSupplier(SuppliersCompanion supplier) {
    return _supplierDao.createSupplier(supplier);
  }

  @override
  Future<bool> updateSupplier(Supplier supplier) {
    return _supplierDao.updateSupplier(supplier);
  }

  @override
  Future<int> deleteSupplier(int id) {
    return _supplierDao.deleteSupplier(id);
  }

  @override
  Stream<int> watchSupplierCount({bool? isActive}) {
    return _supplierDao.watchSupplierCount(isActive: isActive);
  }

  @override
  Stream<int> watchTotalBalanceCents() {
    return _supplierDao.watchTotalBalanceCents();
  }

  @override
  Stream<List<Supplier>> watchSuppliersWithPositiveBalance() {
    return _supplierDao.watchSuppliersWithPositiveBalance();
  }

  @override
  Stream<List<Supplier>> watchTopSuppliersByBalance({int limit = 5}) {
    return _supplierDao.watchTopSuppliersByBalance(limit: limit);
  }

  @override
  Future<void> updateSupplierBalance(int supplierId, int newBalanceCents) {
    return _supplierDao.updateSupplierBalance(supplierId, newBalanceCents);
  }

  @override
  Future<int> createTransaction(SupplierTransactionsCompanion transaction) {
    return _supplierDao.createTransaction(transaction);
  }

  @override
  Future<SupplierTransaction?> getTransaction(int transactionId) {
    return _supplierDao.getTransaction(transactionId);
  }

  @override
  Stream<List<SupplierTransaction>> watchSupplierTransactions(int supplierId) {
    return _supplierDao.watchSupplierTransactions(supplierId);
  }

  @override
  Future<List<SupplierTransaction>> getSupplierTransactions(
    int supplierId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _supplierDao.getSupplierTransactions(
      supplierId,
      startDate: startDate,
      endDate: endDate,
    );
  }
}
