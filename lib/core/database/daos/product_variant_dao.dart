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

  Future<ProductVariant?> getVariantByBarcode(String barcode) {
    return (select(productVariants)
          ..where((v) => v.barcode.equals(barcode))
          ..where((v) => v.isActive.equals(true)))
        .getSingleOrNull();
  }

  Future<ProductVariant?> getDefaultVariantByProduct(int productId) {
    return (select(productVariants)
          ..where((v) => v.productId.equals(productId))
          ..where((v) => v.colorId.isNull())
          ..where((v) => v.sizeId.isNull())
          ..where((v) => v.isActive.equals(true)))
        .getSingleOrNull();
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
