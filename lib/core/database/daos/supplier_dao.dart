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

  Future<int> createTransaction(SupplierTransactionsCompanion tx) {
    return transaction(() async {
      final txId = await into(supplierTransactions).insert(tx);

      final supplierId = tx.supplierId.value;
      final deltaCents = tx.amountCents.value.toBigInt().toInt();

      final type = tx.transactionType.value;
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
