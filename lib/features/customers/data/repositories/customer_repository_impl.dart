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

  CustomerRepositoryImpl(
    this._datasource,
    this._auditService,
    this._sessionService,
    this._journalService,
    this._db,
  );

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
  }) async {
    final balanceCents = initialBalance ?? Decimal.zero;
    final companion = CustomersCompanion(
      name: Value(name),
      email: Value(email),
      phone: Value(phone),
      address: Value(address),
      currencyId: Value(currencyId),
      balanceCents: Value(balanceCents),
      openingBalanceCents: Value(
        balanceCents,
      ), // Store opening balance separately
      segment: Value(segment),
      loyaltyEnabled: Value(loyaltyEnabled),
      isActive: const Value(true),
      createdAt: Value(DateTime.now()),
      updatedAt: Value(DateTime.now()),
    );

    final balanceInt = balanceCents.toBigInt().toInt();

    // ATOMIC: create customer + post opening balance journal entry together
    final customerId = await _db.transaction(() async {
      final id = await _datasource.createCustomer(companion);

      if (balanceInt != 0) {
        final userId = await _currentUserId();
        await _journalService.recordCustomerOpeningBalanceJournalEntry(
          customerId: id,
          amountCents: balanceInt,
          currencyId: currencyId,
          userId: userId,
        );
      }

      return id;
    });

    return customerId;
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

  /// DISABLED: Direct balance updates WITHOUT journal entries are forbidden.
  ///
  /// Phase 1.3 (scattered-calculation migration, May 2026) closes the last
  /// rogue writer of `customers.balance_cents`. Mirrors the equivalent
  /// guard already in place on `SupplierRepositoryImpl.updateSupplierBalance`
  /// (see `FULL_SYSTEM_AUDIT_REPORT.md` finding H1).
  ///
  /// Customer balance must ONLY change through ledger-backed operations:
  ///   - `createCustomer()` with `initialBalance` → seeds via opening-balance JE
  ///   - `recordTransaction(transactionType: 'adjustment')` → records a
  ///      `customer_transactions` row, posts a paired GL entry via
  ///      `JournalEntryService`, and applies the matching balance delta
  ///      through `BalanceService` in a single atomic transaction.
  ///   - DAO-level sale / payment / return flows → already routed through
  ///     `BalanceService` under their respective transactions.
  ///
  /// Allowing the absolute-set path back into production would break the
  /// GL ↔ Customer sub-ledger reconciliation invariant
  /// (see `reconcileBalances()`).
  @override
  Future<void> updateCustomerBalance(
    int customerId,
    int newBalanceCents,
  ) async {
    throw StateError(
      'Direct customer balance updates are DISABLED. '
      'Use recordTransaction(transactionType: "adjustment") instead, '
      'which atomically updates both the customer balance and the General Ledger.',
    );
  }

  @override
  Future<void> updateCustomerLoyaltyEnabled(
    int customerId,
    bool loyaltyEnabled,
  ) {
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
      } else if (transactionType == 'adjustment' && amountCents != 0) {
        // Balance adjustment uses the opening balance equity account.
        // amountCents carries the sign: positive = customer owes more,
        // negative = customer owes less.
        await _journalService.recordCustomerOpeningBalanceJournalEntry(
          customerId: customerId,
          amountCents: amountCents,
          currencyId: currencyId,
          userId: userId,
        );
      }

      return id;
    });

    return txId;
  }

  @override
  Future<int?> adjustOpeningBalance({
    required int customerId,
    required int desiredBalanceCents,
    String? description,
  }) async {
    // Wrap read + delta + post in a single DB transaction so a concurrent
    // writer (e.g. a sale finishing while the form is being saved) cannot
    // race the read of `balance_cents` and leave us with a stale delta.
    return _db.transaction(() async {
      final existing = await _datasource.getCustomer(customerId);
      if (existing == null) {
        throw StateError('Customer $customerId not found');
      }
      final currentCents = existing.balanceCents.toBigInt().toInt();
      final deltaCents = desiredBalanceCents - currentCents;
      if (deltaCents == 0) return null;

      // recordTransaction handles the journal entry + balance write
      // atomically (it opens its own _db.transaction() block; nested
      // transactions on Drift coalesce into the outer one, so this stays
      // a single SQLite commit).
      return await recordTransaction(
        customerId: customerId,
        transactionType: 'adjustment',
        amountCents: deltaCents,
        currencyId: existing.currencyId,
        description: description,
      );
    });
  }

  @override
  Future<CustomerTransaction?> getTransaction(int transactionId) {
    return _datasource.getTransaction(transactionId);
  }

  @override
  Future<CustomerTransaction> updateTransaction({
    required int transactionId,
    required int newAmountCents,
    String? newDescription,
  }) async {
    // 1. Fetch existing transaction to validate and get date
    final existing = await _datasource.getTransaction(transactionId);
    if (existing == null) {
      throw StateError('Transaction #$transactionId not found');
    }

    // 2. Check accounting period is open for the transaction date
    final txDate = existing.transactionDate;
    final periodRows = await _db
        .customSelect(
          '''SELECT id, is_closed FROM accounting_periods
         WHERE start_date <= ? AND end_date >= ?
         ORDER BY start_date DESC LIMIT 1''',
          variables: [
            Variable.withDateTime(txDate),
            Variable.withDateTime(txDate),
          ],
          readsFrom: {_db.accountingPeriods},
        )
        .get();
    if (periodRows.isNotEmpty && periodRows.first.read<bool>('is_closed')) {
      throw StateError(
        'Cannot edit transaction: the accounting period containing this '
        'transaction has been closed.',
      );
    }

    final userId = await _currentUserId();
    final oldAmountCents = existing.amountCents.toBigInt().toInt().abs();
    final absNewAmount = newAmountCents.abs();

    // 3. ATOMIC: update transaction + void old journal + create new journal
    final oldTx = await _db.transaction(() async {
      final old = await _datasource.updateTransactionAmount(
        transactionId,
        newAmountCents: absNewAmount,
        newDescription: newDescription,
      );

      // Void old journal entries for this transaction
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'customer_transactions',
        sourceId: transactionId,
        reason:
            'Transaction amount edited from $oldAmountCents to $absNewAmount cents',
        userId: userId,
      );

      // Create new journal entries with updated amount
      if (existing.transactionType == 'payment' && absNewAmount > 0) {
        await _journalService.recordDirectCustomerPaymentJournalEntry(
          transactionId: transactionId,
          amountCents: absNewAmount,
          currencyId: existing.currencyId,
          userId: userId,
        );
      } else if (existing.transactionType == 'discount' && absNewAmount > 0) {
        await _journalService.recordDirectCustomerDiscountJournalEntry(
          transactionId: transactionId,
          amountCents: absNewAmount,
          currencyId: existing.currencyId,
          userId: userId,
        );
      }

      return old;
    });

    // 4. Audit log
    await _auditService.log(
      entityType: 'customer_transaction',
      entityId: transactionId,
      action: 'edit_transaction',
      oldValue: {
        'amountCents': oldAmountCents,
        'type': existing.transactionType,
        'customerId': existing.customerId,
      },
      newValue: {'amountCents': absNewAmount, 'description': newDescription},
      userId: userId,
    );

    return oldTx;
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
    return _datasource
        .watchAllCustomers(isActive: true)
        .map(
          (customers) => customers.where((c) => c.segment == segment).toList(),
        );
  }

  @override
  Stream<Map<String, int>> watchCustomerCountBySegment() {
    return _datasource.watchAllCustomers(isActive: true).map((customers) {
      final counts = <String, int>{'retail': 0, 'wholesale': 0, 'premium': 0};
      for (final customer in customers) {
        final segment = customer.segment;
        counts[segment] = (counts[segment] ?? 0) + 1;
      }
      return counts;
    });
  }
}
