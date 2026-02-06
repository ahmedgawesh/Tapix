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

  Future<int> createTransaction(SupplierTransactionsCompanion transaction) {
    return into(supplierTransactions).insert(transaction);
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
}
