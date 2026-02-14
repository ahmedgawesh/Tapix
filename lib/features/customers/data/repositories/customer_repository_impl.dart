import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../auth/data/services/session_service.dart';
import '../../domain/repositories/customer_repository.dart';
import '../datasources/customer_local_datasource.dart';

/// Implementation of CustomerRepository
class CustomerRepositoryImpl implements CustomerRepository {
  final CustomerLocalDatasource _datasource;
  final AuditLogService _auditService;
  final SessionService _sessionService;
  final JournalEntryService _journalService;
  final AppDatabase _db;

  CustomerRepositoryImpl(this._datasource, this._auditService, this._sessionService, this._journalService, this._db);

  Future<int?> _currentUserId() => _sessionService.getCurrentUserId();

  @override
  Stream<List<Customer>> watchAllCustomers({bool? isActive}) {
    return _datasource.watchAllCustomers(isActive: isActive);
  }

  @override
  Stream<Customer?> watchCustomer(int id) {
    return _datasource.watchCustomer(id);
  }

  @override
  Future<Customer?> getCustomer(int id) {
    return _datasource.getCustomer(id);
  }

  @override
  Future<List<Customer>> searchCustomers(String query, {bool? isActive}) {
    return _datasource.searchCustomers(query, isActive: isActive);
  }

  @override
  Future<int> createCustomer({
    required String name,
    String? email,
    String? phone,
    String? address,
    required int currencyId,
    Decimal? initialBalance,
    String segment = 'retail',
    bool loyaltyEnabled = true,
  }) {
    final companion = CustomersCompanion(
      name: Value(name),
      email: Value(email),
      phone: Value(phone),
      address: Value(address),
      currencyId: Value(currencyId),
      balanceCents: Value(initialBalance ?? Decimal.zero),
      segment: Value(segment),
      loyaltyEnabled: Value(loyaltyEnabled),
      isActive: const Value(true),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    );
    return _datasource.createCustomer(companion);
  }

  @override
  Future<bool> updateCustomer(Customer customer) {
    return _datasource.updateCustomer(customer);
  }

  @override
  Future<int> deleteCustomer(int id) {
    return _datasource.deleteCustomer(id);
  }

  @override
  Stream<int> watchCustomerCount({bool? isActive}) {
    return _datasource.watchCustomerCount(isActive: isActive);
  }

  @override
  Stream<int> watchTotalBalanceCents() {
    return _datasource.watchTotalBalanceCents();
  }

  @override
  Stream<List<Customer>> watchCustomersWithPositiveBalance() {
    return _datasource.watchCustomersWithPositiveBalance();
  }

  @override
  Stream<List<Customer>> watchTopCustomersByBalance({int limit = 5}) {
    return _datasource.watchTopCustomersByBalance(limit: limit);
  }

  @override
  Future<void> updateCustomerBalance(int customerId, int newBalanceCents) async {
    final existing = await _datasource.getCustomer(customerId);
    final oldBalance = existing?.balanceCents.toBigInt().toInt();

    await _datasource.updateCustomerBalance(customerId, newBalanceCents);

    await _auditService.log(
      entityType: 'customer',
      entityId: customerId,
      action: 'balance_change',
      oldValue: oldBalance == null ? null : {'balanceCents': oldBalance},
      newValue: {
        'balanceCents': newBalanceCents,
        'changeCents': oldBalance == null ? null : (newBalanceCents - oldBalance),
        'reason': 'customer_balance_update',
      },
      userId: await _currentUserId(),
    );
  }

  @override
  Future<void> updateCustomerLoyaltyEnabled(int customerId, bool loyaltyEnabled) {
    return _datasource.updateCustomerLoyaltyEnabled(customerId, loyaltyEnabled);
  }

  @override
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
  }) async {
    final now = DateTime.now();
    final companion = CustomerTransactionsCompanion(
      customerId: Value(customerId),
      transactionType: Value(transactionType),
      amountCents: Value(Decimal.fromInt(amountCents)),
      currencyId: Value(currencyId),
      description: Value(description),
      referenceId: Value(referenceId),
      referenceType: Value(referenceType),
      discountType: Value(discountType),
      transactionDate: Value(transactionDate ?? now),
      createdAt: Value(now),
    );
    // ATOMIC: Wrap customer transaction (which updates balance) and
    // journal entry creation in a single transaction.
    final userId = await _currentUserId();
    final absAmount = amountCents.abs();

    final txId = await _db.transaction(() async {
      final id = await _datasource.createTransaction(companion);

      // Post journal entries for direct party transactions
      if (transactionType == 'payment' && absAmount > 0) {
        await _journalService.recordDirectCustomerPaymentJournalEntry(
          transactionId: id,
          amountCents: absAmount,
          currencyId: currencyId,
          userId: userId,
        );
      } else if (transactionType == 'discount' && absAmount > 0) {
        await _journalService.recordDirectCustomerDiscountJournalEntry(
          transactionId: id,
          amountCents: absAmount,
          currencyId: currencyId,
          userId: userId,
        );
      }

      return id;
    });

    return txId;
  }

  @override
  Future<CustomerTransaction?> getTransaction(int transactionId) {
    return _datasource.getTransaction(transactionId);
  }

  @override
  Stream<List<CustomerTransaction>> watchCustomerTransactions(int customerId) {
    return _datasource.watchCustomerTransactions(customerId);
  }

  @override
  Future<List<CustomerTransaction>> getCustomerTransactions(
    int customerId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _datasource.getCustomerTransactions(
      customerId,
      startDate: startDate,
      endDate: endDate,
    );
  }

  @override
  Stream<List<Customer>> watchCustomersBySegment(String segment) {
    return _datasource.watchAllCustomers(isActive: true).map(
      (customers) => customers.where((c) => c.segment == segment).toList(),
    );
  }

  @override
  Stream<Map<String, int>> watchCustomerCountBySegment() {
    return _datasource.watchAllCustomers(isActive: true).map((customers) {
      final counts = <String, int>{
        'retail': 0,
        'wholesale': 0,
        'premium': 0,
      };
      for (final customer in customers) {
        final segment = customer.segment;
        counts[segment] = (counts[segment] ?? 0) + 1;
      }
      return counts;
    });
  }
}
