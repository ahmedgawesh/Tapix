import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';

part 'size_dao.g.dart';

@DriftAccessor(tables: [Sizes])
class SizeDao extends DatabaseAccessor<AppDatabase> with _$SizeDaoMixin {
  SizeDao(super.db);

  Stream<List<Size>> watchAllSizes() {
    return (select(sizes)
          ..where((s) => s.isActive.equals(true))
          ..orderBy([
            (s) => OrderingTerm(expression: s.sortOrder),
            (s) => OrderingTerm(expression: s.name),
          ]))
        .watch();
  }

  Future<List<Size>> getAllSizes() {
    return (select(sizes)
          ..where((s) => s.isActive.equals(true))
          ..orderBy([
            (s) => OrderingTerm(expression: s.sortOrder),
            (s) => OrderingTerm(expression: s.name),
          ]))
        .get();
  }

  Future<Size?> getSizeById(int id) {
    return (select(sizes)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  Future<int> createSize(SizesCompanion size) {
    return into(sizes).insert(size);
  }

  Future<bool> updateSize(Size size) {
    return update(sizes).replace(size);
  }

  Future<int> deleteSize(int id) {
    return (delete(sizes)..where((s) => s.id.equals(id))).go();
  }

  Future<int> getProductCountBySize(int sizeId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS cnt FROM product_variants WHERE size_id = ?',
      variables: [Variable.withInt(sizeId)],
    ).getSingle();
    return row.read<int>('cnt');
  }
}
