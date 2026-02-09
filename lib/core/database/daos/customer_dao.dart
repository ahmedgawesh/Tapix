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

  Future<int> createTransaction(CustomerTransactionsCompanion tx) {
    return transaction(() async {
      final txId = await into(customerTransactions).insert(tx);

      final customerId = tx.customerId.value;
      final deltaCents = tx.amountCents.value.toBigInt().toInt();

      final type = tx.transactionType.value;
      final affectsBalance = type == 'payment' ||
          type == 'payment_reversal' ||
          type == 'discount' ||
          type == 'adjustment' ||
          type == 'sale' ||
          type == 'sale_return' ||
          type == 'credit_note' ||
          type == 'credit_note_reversal';

      if (!affectsBalance) {
        return txId;
      }

      final customer = await (select(customers)..where((c) => c.id.equals(customerId)))
          .getSingleOrNull();
      if (customer != null) {
        final oldBalance = customer.balanceCents.toBigInt().toInt();
        final newBalance = oldBalance + deltaCents;
        await (update(customers)..where((c) => c.id.equals(customerId))).write(
          CustomersCompanion(
            balanceCents: Value(Decimal.fromInt(newBalance)),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      return txId;
    });
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

  /// Recalculate customer balance from the transaction ledger (single source of truth).
  /// This derives the balance from SUM(customer_transactions.amount_cents) and
  /// overwrites the cached customers.balance_cents field.
  /// Use this for reconciliation or to fix any balance drift.
  Future<int> recalculateBalance(int customerId) async {
    return transaction(() async {
      final result = await customSelect(
        'SELECT COALESCE(SUM(amount_cents), 0) AS derived_balance '
        'FROM customer_transactions WHERE customer_id = ?',
        variables: [Variable.withInt(customerId)],
      ).getSingle();

      final derivedBalance = result.read<int>('derived_balance');

      await (update(customers)..where((c) => c.id.equals(customerId))).write(
        CustomersCompanion(
          balanceCents: Value(Decimal.fromInt(derivedBalance)),
          updatedAt: Value(DateTime.now()),
        ),
      );

      return derivedBalance;
    });
  }

  /// Recalculate balances for ALL customers from their transaction ledgers.
  Future<void> recalculateAllBalances() async {
    final allCustomers = await select(customers).get();
    for (final c in allCustomers) {
      await recalculateBalance(c.id);
    }
  }
}
