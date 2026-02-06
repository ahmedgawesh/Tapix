import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/customer_dao.dart';

/// Local datasource for customer operations
abstract class CustomerLocalDatasource {
  Stream<List<Customer>> watchAllCustomers({bool? isActive});
  Stream<Customer?> watchCustomer(int id);
  Future<Customer?> getCustomer(int id);
  Future<List<Customer>> searchCustomers(String query, {bool? isActive});
  Future<int> createCustomer(CustomersCompanion customer);
  Future<bool> updateCustomer(Customer customer);
  Future<int> deleteCustomer(int id);
  Stream<int> watchCustomerCount({bool? isActive});
  Stream<int> watchTotalBalanceCents();
  Stream<List<Customer>> watchCustomersWithPositiveBalance();
  Stream<List<Customer>> watchTopCustomersByBalance({int limit = 5});
  Future<void> updateCustomerBalance(int customerId, int newBalanceCents);
  Future<void> updateCustomerLoyaltyEnabled(int customerId, bool loyaltyEnabled);
  Future<int> createTransaction(CustomerTransactionsCompanion transaction);
  Stream<List<CustomerTransaction>> watchCustomerTransactions(int customerId);
  Future<List<CustomerTransaction>> getCustomerTransactions(
    int customerId, {
    DateTime? startDate,
    DateTime? endDate,
  });
}

/// Implementation of CustomerLocalDatasource using CustomerDao
class CustomerLocalDatasourceImpl implements CustomerLocalDatasource {
  final CustomerDao _customerDao;

  CustomerLocalDatasourceImpl(this._customerDao);

  @override
  Stream<List<Customer>> watchAllCustomers({bool? isActive}) {
    return _customerDao.watchAllCustomers(isActive: isActive);
  }

  @override
  Stream<Customer?> watchCustomer(int id) {
    return _customerDao.watchCustomer(id);
  }

  @override
  Future<Customer?> getCustomer(int id) {
    return _customerDao.getCustomer(id);
  }

  @override
  Future<List<Customer>> searchCustomers(String query, {bool? isActive}) {
    return _customerDao.searchCustomers(query, isActive: isActive);
  }

  @override
  Future<int> createCustomer(CustomersCompanion customer) {
    return _customerDao.createCustomer(customer);
  }

  @override
  Future<bool> updateCustomer(Customer customer) {
    return _customerDao.updateCustomer(customer);
  }

  @override
  Future<int> deleteCustomer(int id) {
    return _customerDao.deleteCustomer(id);
  }

  @override
  Stream<int> watchCustomerCount({bool? isActive}) {
    return _customerDao.watchCustomerCount(isActive: isActive);
  }

  @override
  Stream<int> watchTotalBalanceCents() {
    return _customerDao.watchTotalBalanceCents();
  }

  @override
  Stream<List<Customer>> watchCustomersWithPositiveBalance() {
    return _customerDao.watchCustomersWithPositiveBalance();
  }

  @override
  Stream<List<Customer>> watchTopCustomersByBalance({int limit = 5}) {
    return _customerDao.watchTopCustomersByBalance(limit: limit);
  }

  @override
  Future<void> updateCustomerBalance(int customerId, int newBalanceCents) {
    return _customerDao.updateCustomerBalance(customerId, newBalanceCents);
  }

  @override
  Future<void> updateCustomerLoyaltyEnabled(int customerId, bool loyaltyEnabled) {
    return _customerDao.updateCustomerLoyaltyEnabled(customerId, loyaltyEnabled);
  }

  @override
  Future<int> createTransaction(CustomerTransactionsCompanion transaction) {
    return _customerDao.createTransaction(transaction);
  }

  @override
  Stream<List<CustomerTransaction>> watchCustomerTransactions(int customerId) {
    return _customerDao.watchCustomerTransactions(customerId);
  }

  @override
  Future<List<CustomerTransaction>> getCustomerTransactions(
    int customerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _customerDao.getCustomerTransactions(
      customerId,
      startDate: startDate,
      endDate: endDate,
    );
  }
}
