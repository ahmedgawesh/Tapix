import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';

part 'product_variant_dao.g.dart';

@DriftAccessor(tables: [ProductVariants, ProductColors, Sizes])
class ProductVariantDao extends DatabaseAccessor<AppDatabase> with _$ProductVariantDaoMixin {
  ProductVariantDao(super.db);

  Stream<List<ProductVariant>> watchAllVariants() {
    return (select(productVariants)..where((v) => v.isActive.equals(true))).watch();
  }

  Stream<List<ProductVariant>> watchVariantsByProduct(int productId) {
    return (select(productVariants)
          ..where((v) => v.productId.equals(productId))
          ..where((v) => v.isActive.equals(true)))
        .watch();
  }

  Future<List<ProductVariant>> getVariantsByProduct(int productId) {
    return (select(productVariants)
          ..where((v) => v.productId.equals(productId))
          ..where((v) => v.isActive.equals(true)))
        .get();
  }

  Future<ProductVariant?> getVariantById(int id) {
    return (select(productVariants)..where((v) => v.id.equals(id))).getSingleOrNull();
  }

  /// Returns a map of productId -> (variantCount, totalStock) for all products with variants
  Stream<Map<int, ({int count, int totalStock})>> watchVariantSummaries() {
    return customSelect(
      'SELECT product_id, COUNT(*) as cnt, SUM(stock_quantity) as total_stock '
      'FROM product_variants WHERE is_active = 1 GROUP BY product_id',
    ).watch().map((rows) {
      final result = <int, ({int count, int totalStock})>{};
      for (final row in rows) {
        final productId = row.read<int>('product_id');
        final count = row.read<int>('cnt');
        final totalStock = row.read<int>('total_stock');
        result[productId] = (count: count, totalStock: totalStock);
      }
      return result;
    });
  }

  Future<Map<int, String>> getVariantInfoByProductIds(List<int> productIds) async {
    final result = <int, String>{};
    for (final productId in productIds) {
      final v = await getDefaultVariantByProduct(productId);
      if (v == null) continue;

      String? colorName;
      if (v.colorId != null) {
        final color = await (select(productColors)..where((c) => c.id.equals(v.colorId!)))
            .getSingleOrNull();
        colorName = color?.name;
      }

      String? sizeName;
      if (v.sizeId != null) {
        final size = await (select(sizes)..where((s) => s.id.equals(v.sizeId!)))
            .getSingleOrNull();
        sizeName = size?.name;
      }

      final info = [sizeName, colorName]
          .whereType<String>()
          .where((x) => x.trim().isNotEmpty)
          .join(' / ');
      if (info.isNotEmpty) {
        result[productId] = info;
      }
    }
    return result;
  }

  /// Returns variant summary for a single product
  Future<({int count, int totalStock})?> getVariantSummaryByProduct(int productId) async {
    final row = await customSelect(
      'SELECT COUNT(*) as cnt, SUM(stock_quantity) as total_stock '
      'FROM product_variants WHERE product_id = ? AND is_active = 1',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();
    if (row == null) return null;
    final count = row.read<int>('cnt');
    if (count == 0) return null;
    final totalStock = row.read<int>('total_stock');
    return (count: count, totalStock: totalStock);
  }

  Future<ProductVariant?> getVariantByBarcode(String barcode) {
    return (select(productVariants)
          ..where((v) => v.barcode.equals(barcode))
          ..where((v) => v.isActive.equals(true)))
        .getSingleOrNull();
  }

  Future<ProductVariant?> getVariantBySku(String sku) {
    return (select(productVariants)
          ..where((v) => v.sku.equals(sku))
          ..where((v) => v.isActive.equals(true)))
        .getSingleOrNull();
  }

  Future<ProductVariant?> getDefaultVariantByProduct(int productId) {
    return transaction(() async {
      final strictDefaults = await (select(productVariants)
            ..where((v) => v.productId.equals(productId))
            ..where((v) => v.colorId.isNull())
            ..where((v) => v.sizeId.isNull())
            ..where((v) => v.isActive.equals(true))
            ..limit(1))
          .get();
      if (strictDefaults.isNotEmpty) return strictDefaults.first;

      final anyVariants = await (select(productVariants)
            ..where((v) => v.productId.equals(productId))
            ..where((v) => v.isActive.equals(true))
            ..orderBy([(v) => OrderingTerm(expression: v.id)])
            ..limit(1))
          .get();
      if (anyVariants.isNotEmpty) return anyVariants.first;
      return null;
    });
  }

  Future<int> createVariant(ProductVariantsCompanion variant) {
    return transaction(() async {
      final id = await into(productVariants).insert(variant);
      final productId = variant.productId.value;

      final hasDimensions =
          variant.colorId.present && variant.colorId.value != null ||
              variant.sizeId.present && variant.sizeId.value != null;
      if (hasDimensions) {
        await customStatement(
          'UPDATE products SET has_variants = 1 WHERE id = ?',
          [productId],
        );
      }
      return id;
    });
  }

  Future<void> updateVariantBarcode({required int variantId, required String barcode}) {
    return (update(productVariants)..where((v) => v.id.equals(variantId))).write(
      ProductVariantsCompanion(
        barcode: Value(barcode),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<bool> updateVariant(ProductVariant variant) {
    return update(productVariants).replace(variant);
  }

  Future<int> deleteVariant(int id) {
    return transaction(() async {
      final variant = await (select(productVariants)..where((v) => v.id.equals(id)))
          .getSingleOrNull();
      final affected = await (delete(productVariants)..where((v) => v.id.equals(id))).go();

      final productId = variant?.productId;
      if (productId != null) {
        final row = await customSelect(
          'SELECT COUNT(*) as cnt FROM product_variants WHERE product_id = ? AND is_active = 1',
          variables: [Variable.withInt(productId)],
        ).getSingle();
        final remaining = row.read<int>('cnt');
        if (remaining == 0) {
          await customStatement(
            'UPDATE products SET has_variants = 0 WHERE id = ?',
            [productId],
          );
        }
      }

      return affected;
    });
  }
}
