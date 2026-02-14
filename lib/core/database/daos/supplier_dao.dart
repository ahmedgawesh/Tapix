import 'package:drift/drift.dart';
import 'package:decimal/decimal.dart';
import '../app_database.dart';
import '../tables/parties.dart';

part 'supplier_dao.g.dart';

@DriftAccessor(tables: [Suppliers, SupplierTransactions])
class SupplierDao extends DatabaseAccessor<AppDatabase> with _$SupplierDaoMixin {
  SupplierDao(super.db);

  Stream<List<Supplier>> watchAllSuppliers({bool? isActive}) {
    final query = select(suppliers);
    if (isActive != null) {
      query.where((s) => s.isActive.equals(isActive));
    }
    query.orderBy([(s) => OrderingTerm(expression: s.name)]);
    return query.watch();
  }

  Stream<Supplier?> watchSupplier(int id) {
    return (select(suppliers)..where((s) => s.id.equals(id))).watchSingleOrNull();
  }

  Future<Supplier?> getSupplier(int id) {
    return (select(suppliers)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  Future<List<Supplier>> searchSuppliers(String query, {bool? isActive}) {
    final q = select(suppliers)
      ..where((s) => s.name.like('%$query%') | s.phone.like('%$query%') | s.email.like('%$query%'));
    if (isActive != null) {
      q.where((s) => s.isActive.equals(isActive));
    }
    return q.get();
  }

  Future<int> createSupplier(SuppliersCompanion supplier) {
    return into(suppliers).insert(supplier);
  }

  Future<bool> updateSupplier(Supplier supplier) {
    return update(suppliers).replace(supplier);
  }

  Future<int> deleteSupplier(int id) {
    return (delete(suppliers)..where((s) => s.id.equals(id))).go();
  }

  /// Generate the next sequential transaction number for a given prefix.
  /// e.g. PAY-0001, DSC-0001, PUR-0001, RET-0001
  Future<String> _nextTransactionNumber(String prefix) async {
    final result = await customSelect(
'SELECT COUNT(*) AS cnt FROM supplier_transactions WHERE transaction_number LIKE ?',
      variables: [Variable<String>('$prefix-%')],
    ).getSingle();
    final count = result.read<int>('cnt');
    return '$prefix-${(count + 1).toString().padLeft(4, '0')}';
  }

  /// Transaction types that are managed by PurchaseDao and must NOT be routed
  /// through this method. PurchaseDao updates supplier balance directly, so
  /// routing these here would cause double balance updates.
  static const _purchaseOwnedTypes = {
    'purchase',
    'purchase_void',
    'purchase_return',
    'refund',
    'refund_reversal',
  };

  Future<int> createTransaction(SupplierTransactionsCompanion tx) {
    return transaction(() async {
      // Guard: reject types owned by PurchaseDao to prevent double balance updates
      final type = tx.transactionType.value;
      if (_purchaseOwnedTypes.contains(type)) {
        throw StateError(
          'SupplierDao.createTransaction() must not be used for "$type" transactions. '
          'These are managed by PurchaseDao which updates balance directly.',
        );
      }

      // Auto-generate transaction number if not provided
      var companion = tx;
      if (!tx.transactionNumber.present || tx.transactionNumber.value == null) {
        String prefix;
        switch (type) {
          case 'payment':
            prefix = 'SPAY';
            break;
          case 'discount':
            prefix = 'SDSC';
            break;
          case 'purchase':
            prefix = 'PUR';
            break;
          case 'return':
            prefix = 'PRET';
            break;
          case 'payment_reversal':
            prefix = 'SPRV';
            break;
          case 'credit_note':
            prefix = 'SCRN';
            break;
          case 'adjustment':
            prefix = 'SADJ';
            break;
          default:
            prefix = 'STXN';
        }
        final txNumber = await _nextTransactionNumber(prefix);
        companion = companion.copyWith(transactionNumber: Value(txNumber));
      }

      final txId = await into(supplierTransactions).insert(companion);

      final supplierId = tx.supplierId.value;
      final deltaCents = tx.amountCents.value.toBigInt().toInt();

      final affectsBalance = type == 'purchase' ||
          type == 'payment' ||
          type == 'payment_reversal' ||
          type == 'discount' ||
          type == 'adjustment' ||
          type == 'credit_note' ||
          type == 'credit_note_reversal';

      if (!affectsBalance) {
        return txId;
      }

      final supplier = await (select(suppliers)..where((s) => s.id.equals(supplierId)))
          .getSingleOrNull();
      if (supplier != null) {
        final oldBalance = supplier.balanceCents.toBigInt().toInt();
        final newBalance = oldBalance + deltaCents;
        await (update(suppliers)..where((s) => s.id.equals(supplierId))).write(
          SuppliersCompanion(
            balanceCents: Value(Decimal.fromInt(newBalance)),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      return txId;
    });
  }

  Future<SupplierTransaction?> getTransaction(int transactionId) {
    return (select(supplierTransactions)..where((t) => t.id.equals(transactionId)))
        .getSingleOrNull();
  }

  Stream<List<SupplierTransaction>> watchSupplierTransactions(int supplierId) {
    return (select(supplierTransactions)
          ..where((t) => t.supplierId.equals(supplierId))
          ..orderBy([(t) => OrderingTerm(expression: t.transactionDate, mode: OrderingMode.desc)]))
        .watch();
  }

  Future<List<SupplierTransaction>> getSupplierTransactions(
    int supplierId, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final query = select(supplierTransactions)..where((t) => t.supplierId.equals(supplierId));
    if (startDate != null) {
      query.where((t) => t.transactionDate.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      query.where((t) => t.transactionDate.isSmallerOrEqualValue(endDate));
    }
    query.orderBy([(t) => OrderingTerm(expression: t.transactionDate, mode: OrderingMode.desc)]);
    return query.get();
  }

  Stream<int> watchSupplierCount({bool? isActive}) {
    final query = selectOnly(suppliers)..addColumns([suppliers.id.count()]);
    if (isActive != null) {
      query.where(suppliers.isActive.equals(isActive));
    }
    return query.map((row) => row.read(suppliers.id.count()) ?? 0).watchSingle();
  }

  Stream<int> watchTotalBalanceCents() {
    final query = selectOnly(suppliers)
      ..addColumns([suppliers.balanceCents.sum()])
      ..where(suppliers.isActive.equals(true));
    return query.map((row) => row.read(suppliers.balanceCents.sum()) ?? 0).watchSingle();
  }

  Stream<List<Supplier>> watchSuppliersWithPositiveBalance() {
    return (select(suppliers)
          ..where((s) => s.balanceCents.isBiggerThanValue(0) & s.isActive.equals(true))
          ..orderBy([(s) => OrderingTerm(expression: s.balanceCents, mode: OrderingMode.desc)]))
        .watch();
  }

  Stream<List<Supplier>> watchTopSuppliersByBalance({int limit = 5}) {
    return (select(suppliers)
          ..where((s) => s.isActive.equals(true))
          ..orderBy([(s) => OrderingTerm(expression: s.balanceCents, mode: OrderingMode.desc)])
          ..limit(limit))
        .watch();
  }

  Future<void> updateSupplierBalance(int supplierId, int newBalanceCents) async {
    await (update(suppliers)..where((s) => s.id.equals(supplierId))).write(
      SuppliersCompanion(
        balanceCents: Value(Decimal.fromInt(newBalanceCents)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Recalculate supplier balance from the transaction ledger (single source of truth).
  /// This derives the balance from SUM(supplier_transactions.amount_cents) and
  /// overwrites the cached suppliers.balance_cents field.
  /// Use this for reconciliation or to fix any balance drift.
  Future<int> recalculateBalance(int supplierId) async {
    return transaction(() async {
      final result = await customSelect(
        'SELECT COALESCE(SUM(amount_cents), 0) AS derived_balance '
        'FROM supplier_transactions WHERE supplier_id = ?',
        variables: [Variable.withInt(supplierId)],
      ).getSingle();

      final derivedBalance = result.read<int>('derived_balance');

      await (update(suppliers)..where((s) => s.id.equals(supplierId))).write(
        SuppliersCompanion(
          balanceCents: Value(Decimal.fromInt(derivedBalance)),
          updatedAt: Value(DateTime.now()),
        ),
      );

      return derivedBalance;
    });
  }

  /// Recalculate balances for ALL suppliers from their transaction ledgers.
  Future<void> recalculateAllBalances() async {
    final allSuppliers = await select(suppliers).get();
    for (final s in allSuppliers) {
      await recalculateBalance(s.id);
    }
  }
}
