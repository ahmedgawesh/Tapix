import 'package:drift/drift.dart';
import 'package:decimal/decimal.dart';
import '../app_database.dart';
import '../tables/parties.dart';

part 'customer_dao.g.dart';

@DriftAccessor(tables: [Customers, CustomerTransactions])
class CustomerDao extends DatabaseAccessor<AppDatabase> with _$CustomerDaoMixin {
  CustomerDao(super.db);

  Stream<List<Customer>> watchAllCustomers({bool? isActive}) {
    final query = select(customers);
    if (isActive != null) {
      query.where((c) => c.isActive.equals(isActive));
    }
    query.orderBy([(c) => OrderingTerm(expression: c.name)]);
    return query.watch();
  }

  Stream<Customer?> watchCustomer(int id) {
    return (select(customers)..where((c) => c.id.equals(id))).watchSingleOrNull();
  }

  Future<Customer?> getCustomer(int id) {
    return (select(customers)..where((c) => c.id.equals(id))).getSingleOrNull();
  }

  Future<List<Customer>> searchCustomers(String query, {bool? isActive}) {
    final q = select(customers)
      ..where((c) => c.name.like('%$query%') | c.phone.like('%$query%') | c.email.like('%$query%'));
    if (isActive != null) {
      q.where((c) => c.isActive.equals(isActive));
    }
    return q.get();
  }

  Future<int> createCustomer(CustomersCompanion customer) {
    return into(customers).insert(customer);
  }

  Future<bool> updateCustomer(Customer customer) {
    return update(customers).replace(customer);
  }

  Future<int> deleteCustomer(int id) {
    return (delete(customers)..where((c) => c.id.equals(id))).go();
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

  Future<List<CustomerTransaction>> getCustomerTransactions(
    int customerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final query = select(customerTransactions)..where((t) => t.customerId.equals(customerId));
    if (startDate != null) {
      query.where((t) => t.transactionDate.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.transactionDate.isSmallerOrEqualValue(endDate));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.transactionDate, mode: OrderingMode.desc)]);
    return query.get();
  }

  Stream<int> watchCustomerCount({bool? isActive}) {
    final query = selectOnly(customers)..addColumns([customers.id.count()]);
    if (isActive != null) {
      query.where(customers.isActive.equals(isActive));
    }
    return query.map((row) => row.read(customers.id.count()) ?? 0).watchSingle();
  }

  Stream<int> watchTotalBalanceCents() {
    final query = selectOnly(customers)
      ..addColumns([customers.balanceCents.sum()])
      ..where(customers.isActive.equals(true));
    return query.map((row) => row.read(customers.balanceCents.sum()) ?? 0).watchSingle();
  }

  Stream<List<Customer>> watchCustomersWithPositiveBalance() {
    return (select(customers)
          ..where((c) => c.balanceCents.isBiggerThanValue(0) & c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm(expression: c.balanceCents, mode: OrderingMode.desc)]))
        .watch();
  }

  Stream<List<Customer>> watchTopCustomersByBalance({int limit = 5}) {
    return (select(customers)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm(expression: c.balanceCents, mode: OrderingMode.desc)])
          ..limit(limit))
        .watch();
  }

  Future<void> updateCustomerBalance(int customerId, int newBalanceCents) async {
    await (update(customers)..where((c) => c.id.equals(customerId))).write(
      CustomersCompanion(
        balanceCents: Value(Decimal.fromInt(newBalanceCents)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateCustomerLoyaltyEnabled(int customerId, bool loyaltyEnabled) async {
    await (update(customers)..where((c) => c.id.equals(customerId))).write(
      CustomersCompanion(
        loyaltyEnabled: Value(loyaltyEnabled),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
