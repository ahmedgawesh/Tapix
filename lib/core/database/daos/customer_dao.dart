import 'package:drift/drift.dart';
import 'package:decimal/decimal.dart';
import '../app_database.dart';
import '../tables/parties.dart';
import '../../services/balance_service.dart';

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

  /// Generate the next sequential transaction number for a given prefix.
  /// e.g. PAY-0001, DSC-0001, SAL-0001, RET-0001
  Future<String> _nextTransactionNumber(String prefix) async {
    final result = await customSelect(
      'SELECT COUNT(*) AS cnt FROM customer_transactions WHERE transaction_number LIKE ?',
      variables: [Variable<String>('$prefix-%')],
    ).getSingle();
    final count = result.read<int>('cnt');
    return '$prefix-${(count + 1).toString().padLeft(4, '0')}';
  }

  /// Transaction types that are managed by SaleDao and must NOT be routed
  /// through this method. SaleDao updates customer balance directly, so
  /// routing these here would cause double balance updates.
  static const _saleOwnedTypes = {
    'sale',
    'sale_void',
    'sale_return',
    'refund',
    'refund_reversal',
  };

  Future<int> createTransaction(CustomerTransactionsCompanion tx) {
    return transaction(() async {
      // Guard: reject types owned by SaleDao to prevent double balance updates
      final type = tx.transactionType.value;
      if (_saleOwnedTypes.contains(type)) {
        throw StateError(
          'CustomerDao.createTransaction() must not be used for "$type" transactions. '
          'These are managed by SaleDao which updates balance directly.',
        );
      }

      // Auto-generate transaction number if not provided
      var companion = tx;
      if (!tx.transactionNumber.present || tx.transactionNumber.value == null) {
        String prefix;
        switch (type) {
          case 'payment':
            prefix = 'CPAY';
            break;
          case 'discount':
            prefix = 'CDSC';
            break;
          case 'sale':
            prefix = 'SAL';
            break;
          case 'sale_return':
            prefix = 'SRET';
            break;
          case 'payment_reversal':
            prefix = 'CPRV';
            break;
          case 'credit_note':
            prefix = 'CCRN';
            break;
          case 'credit_note_reversal':
            prefix = 'CCRV';
            break;
          case 'adjustment':
            prefix = 'CADJ';
            break;
          default:
            prefix = 'CTXN';
        }
        final txNumber = await _nextTransactionNumber(prefix);
        companion = companion.copyWith(transactionNumber: Value(txNumber));
      }

      final txId = await into(customerTransactions).insert(companion);

      final customerId = tx.customerId.value;
      final deltaCents = tx.amountCents.value.toBigInt().toInt();

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

      await BalanceService.adjustCustomerBalance(this,
        customerId: customerId,
        deltaCents: deltaCents,
      );

      return txId;
    });
  }

  /// Only 'payment' and 'discount' transactions may be edited.
  static const _editableTypes = {'payment', 'discount'};

  /// Update a payment or discount transaction amount.
  /// Returns the old transaction for audit purposes.
  /// Adjusts the customer balance by the delta (newAmount - oldAmount).
  Future<CustomerTransaction> updateTransactionAmount(
    int transactionId, {
    required int newAmountCents,
    String? newDescription,
  }) {
    return transaction(() async {
      final existing = await (select(customerTransactions)
            ..where((t) => t.id.equals(transactionId)))
          .getSingleOrNull();
      if (existing == null) {
        throw StateError('Transaction #$transactionId not found');
      }
      if (!_editableTypes.contains(existing.transactionType)) {
        throw StateError(
          'Only payment and discount transactions can be edited. '
          'Got: "${existing.transactionType}"',
        );
      }

      final oldCents = existing.amountCents.toBigInt().toInt();
      // For payments/discounts the stored amount is negative (reduces balance).
      // The caller passes the absolute new amount; we preserve the sign.
      final signedNewAmount = oldCents < 0 ? -newAmountCents.abs() : newAmountCents.abs();
      final deltaCents = signedNewAmount - oldCents;

      // Update the transaction row
      await (update(customerTransactions)
            ..where((t) => t.id.equals(transactionId)))
          .write(CustomerTransactionsCompanion(
        amountCents: Value(Decimal.fromInt(signedNewAmount)),
        description: newDescription != null ? Value(newDescription) : const Value.absent(),
      ));

      // Adjust customer balance by the delta
      if (deltaCents != 0) {
        await BalanceService.adjustCustomerBalance(this,
          customerId: existing.customerId,
          deltaCents: deltaCents,
        );
      }

      return existing;
    });
  }

  Future<CustomerTransaction?> getTransaction(int transactionId) {
    return (select(customerTransactions)..where((t) => t.id.equals(transactionId)))
        .getSingleOrNull();
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

  /// INTERNAL — absolute-set writer for `customers.balance_cents`.
  ///
  /// **DO NOT CALL THIS FROM PRODUCTION CODE.** It bypasses both
  /// `BalanceService` (the per-delta path) and `JournalEntryService` (the GL
  /// posting path), so any caller will silently desynchronise the customer
  /// sub-ledger from the General Ledger and break
  /// `AccountingRepository.reconcileBalances()`.
  ///
  /// As of Phase 1.3 (May 2026) every production path was migrated to:
  ///   - `BalanceService.adjustCustomerBalance` for delta mutations
  ///     (already used by `sale_dao`, `adjustment_return_dao`, etc.)
  ///   - `recalculateBalance` below, for idempotent rebuild from
  ///     `customer_transactions` (the legitimate authoritative source)
  ///
  /// This method is retained ONLY for legacy migration / repair scripts
  /// that need to seed a balance before any transactions exist.
  ///
  /// See `docs/adr/0001-pricing-engines-as-sot.md` § Phase 1.
  @Deprecated('Use BalanceService.adjustCustomerBalance or recalculateBalance')
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
