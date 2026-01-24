import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/parties.dart';

part 'customer_dao.g.dart';

@DriftAccessor(tables: [Customers, CustomerTransactions])
class CustomerDao extends DatabaseAccessor<AppDatabase> with _$CustomerDaoMixin {
  CustomerDao(super.db);

  Stream<List<Customer>> watchAllCustomers() {
    return (select(customers)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm(expression: c.name)]))
        .watch();
  }

  Stream<Customer?> watchCustomer(int id) {
    return (select(customers)..where((c) => c.id.equals(id))).watchSingleOrNull();
  }

  Future<List<Customer>> searchCustomers(String query) {
    return (select(customers)
          ..where((c) => c.name.like('%$query%') | c.phone.like('%$query%') | c.email.like('%$query%'))
          ..where((c) => c.isActive.equals(true)))
        .get();
  }

  Future<int> createCustomer(CustomersCompanion customer) {
    return into(customers).insert(customer);
  }

  Future<bool> updateCustomer(Customer customer) {
    return update(customers).replace(customer);
  }

  Future<int> createTransaction(CustomerTransactionsCompanion transaction) {
    return into(customerTransactions).insert(transaction);
  }

  Stream<List<CustomerTransaction>> watchCustomerTransactions(int customerId) {
    return (select(customerTransactions)
          ..where((t) => t.customerId.equals(customerId))
          ..orderBy([(t) => OrderingTerm(expression: t.transactionDate, mode: OrderingMode.desc)]))
        .watch();
  }
}
