import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/inventory.dart';
import '../tables/products.dart';

part 'inventory_adjustment_dao.g.dart';

@DriftAccessor(tables: [InventoryAdjustments, Products, ProductVariants])
class InventoryAdjustmentDao extends DatabaseAccessor<AppDatabase>
    with _$InventoryAdjustmentDaoMixin {
  InventoryAdjustmentDao(super.db);

  /// Generate the next sequential adjustment number in the form
  /// `ADJ-YYYYMM-NNNN`. Numbering resets per calendar month to mirror the
  /// convention used by `PAR-` / `SAR-` / invoice numbering elsewhere.
  Future<String> generateAdjustmentNumber() async {
    final now = DateTime.now();
    final prefix = 'ADJ-${now.year}${now.month.toString().padLeft(2, '0')}';
    final last =
        await (select(inventoryAdjustments)
              ..where((a) => a.adjustmentNumber.like('$prefix%'))
              ..orderBy([(a) => OrderingTerm.desc(a.adjustmentNumber)])
              ..limit(1))
            .getSingleOrNull();

    int nextNum = 1;
    if (last != null) {
      final parts = last.adjustmentNumber.split('-');
      nextNum = (int.tryParse(parts.last) ?? 0) + 1;
    }
    return '$prefix-${nextNum.toString().padLeft(4, '0')}';
  }

  Future<int> insertAdjustment(InventoryAdjustmentsCompanion companion) {
    return into(inventoryAdjustments).insert(companion);
  }

  Future<int> linkJournalEntry({
    required int adjustmentId,
    required int journalEntryId,
  }) {
    return (update(
      inventoryAdjustments,
    )..where((a) => a.id.equals(adjustmentId))).write(
      InventoryAdjustmentsCompanion(
        journalEntryId: Value(journalEntryId),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<InventoryAdjustment?> getById(int id) {
    return (select(
      inventoryAdjustments,
    )..where((a) => a.id.equals(id))).getSingleOrNull();
  }

  Stream<List<InventoryAdjustment>> watchAll() {
    return (select(
      inventoryAdjustments,
    )..orderBy([(a) => OrderingTerm.desc(a.createdAt)])).watch();
  }

  Stream<List<InventoryAdjustment>> watchByProduct(int productId) {
    return (select(inventoryAdjustments)
          ..where((a) => a.productId.equals(productId))
          ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
        .watch();
  }

  Stream<List<InventoryAdjustment>> watchByVariant(int variantId) {
    return (select(inventoryAdjustments)
          ..where((a) => a.variantId.equals(variantId))
          ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
        .watch();
  }

  Future<List<InventoryAdjustment>> getByDateRange(
    DateTime start,
    DateTime end,
  ) {
    return (select(inventoryAdjustments)
          ..where(
            (a) =>
                a.createdAt.isBiggerOrEqualValue(start) &
                a.createdAt.isSmallerThanValue(end),
          )
          ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
        .get();
  }

  Future<T> runInTransaction<T>(Future<T> Function() action) {
    return transaction(action);
  }
}
