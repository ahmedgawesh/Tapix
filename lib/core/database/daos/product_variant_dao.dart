import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';

part 'product_variant_dao.g.dart';

@DriftAccessor(tables: [ProductVariants, ProductColors, Sizes])
class ProductVariantDao extends DatabaseAccessor<AppDatabase> with _$ProductVariantDaoMixin {
  ProductVariantDao(super.db);

  Stream<List<ProductVariant>> watchAllVariants() {
    return select(productVariants).watch();
  }

  /// Streams the active variants of [productId]. Soft-deleted variants
  /// (`is_active = 0`) are intentionally excluded so smart-deleted SKUs
  /// disappear from management/POS UIs while still being preserved in
  /// historical sale/purchase items, returns and journal entries.
  Stream<List<ProductVariant>> watchVariantsByProduct(int productId) {
    return (select(productVariants)
          ..where((v) => v.productId.equals(productId))
          ..where((v) => v.isActive.equals(true)))
        .watch();
  }

  Future<List<ProductVariant>> getVariantsByProduct(int productId) {
    return (select(productVariants)..where((v) => v.productId.equals(productId))).get();
  }

  Future<ProductVariant?> getVariantById(int id) {
    return (select(productVariants)..where((v) => v.id.equals(id))).getSingleOrNull();
  }

  /// Returns a map of productId -> (variantCount, totalStock) for all products with variants
  Stream<Map<int, ({int count, int totalStock})>> watchVariantSummaries() {
    return customSelect(
      'SELECT product_id, COUNT(*) as cnt, SUM(stock_quantity) as total_stock '
      'FROM product_variants WHERE is_active = 1 GROUP BY product_id',
      readsFrom: {productVariants},
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

  /// Returns a map of productId -> (sizeName, colorHex) for the first active variant per product.
  /// Used for compact product-card display (SKU (Size ●)).
  Stream<Map<int, ({String? sizeName, String? colorHex})>> watchVariantPreviews() {
    return customSelect(
      'SELECT v.product_id, s.name AS size_name, c.hex_code AS color_hex '
      'FROM product_variants v '
      'LEFT JOIN sizes s ON s.id = v.size_id '
      'LEFT JOIN product_colors c ON c.id = v.color_id '
      'WHERE v.is_active = 1 '
      'AND v.id IN (SELECT MIN(id) FROM product_variants WHERE is_active = 1 GROUP BY product_id)',
      readsFrom: {productVariants, sizes, productColors},
    ).watch().map((rows) {
      final result = <int, ({String? sizeName, String? colorHex})>{};
      for (final row in rows) {
        final productId = row.read<int>('product_id');
        final sizeName = row.readNullable<String>('size_name');
        final colorHex = row.readNullable<String>('color_hex');
        result[productId] = (sizeName: sizeName, colorHex: colorHex);
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

  Future<Map<int, String>> getVariantInfoByVariantIds(List<int> variantIds) async {
    final result = <int, String>{};
    for (final variantId in variantIds) {
      final v = await getVariantById(variantId);
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
        result[variantId] = info;
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
            ..limit(1))
          .get();
      if (strictDefaults.isNotEmpty) return strictDefaults.first;

      final anyVariants = await (select(productVariants)
            ..where((v) => v.productId.equals(productId))
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
        await customUpdate(
          'UPDATE products SET has_variants = 1, updated_at = ? WHERE id = ?',
          variables: [Variable.withDateTime(DateTime.now()), Variable.withInt(productId)],
          updates: {products},
        );
      } else {
        await customUpdate(
          'UPDATE products SET updated_at = ? WHERE id = ?',
          variables: [Variable.withDateTime(DateTime.now()), Variable.withInt(productId)],
          updates: {products},
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
    return transaction(() async {
      final ok = await update(productVariants).replace(variant);

      final row = await customSelect(
        'SELECT COUNT(*) as cnt FROM product_variants WHERE product_id = ? AND is_active = 1',
        variables: [Variable.withInt(variant.productId)],
      ).getSingle();
      final activeCount = row.read<int>('cnt');

      await customUpdate(
        'UPDATE products SET is_active = ?, updated_at = ? WHERE id = ?',
        variables: [
          Variable.withInt(activeCount > 0 ? 1 : 0),
          Variable.withDateTime(DateTime.now()),
          Variable.withInt(variant.productId),
        ],
        updates: {products},
      );

      return ok;
    });
  }

  /// Count active variants that carry an explicit color or size (i.e. true
  /// dimensional variants), excluding the single anonymous default variant
  /// used to back non-variant products. Used when the user toggles
  /// "Has Variants" off — so we can warn them about the exact number that
  /// will be deactivated.
  Future<int> countActiveDimensionalVariants(int productId) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS cnt FROM product_variants '
      'WHERE product_id = ? AND is_active = 1 '
      'AND (color_id IS NOT NULL OR size_id IS NOT NULL)',
      variables: [Variable.withInt(productId)],
    ).getSingle();
    return row.read<int>('cnt');
  }

  /// Deactivate every variant of [productId] that has a color or size
  /// dimension (keeping the anonymous default variant intact so non-variant
  /// sales can continue). Called when "Has Variants" is toggled from
  /// true -> false. We never hard-delete — those variants may appear on
  /// historical invoices/returns and must stay for audit + COGS integrity.
  Future<int> deactivateDimensionalVariants(int productId) async {
    return customUpdate(
      'UPDATE product_variants SET is_active = 0, updated_at = ? '
      'WHERE product_id = ? AND (color_id IS NOT NULL OR size_id IS NOT NULL)',
      variables: [
        Variable.withDateTime(DateTime.now()),
        Variable.withInt(productId),
      ],
      updates: {productVariants},
    );
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
          await customUpdate(
            'UPDATE products SET has_variants = 0, updated_at = ? WHERE id = ?',
            variables: [Variable.withDateTime(DateTime.now()), Variable.withInt(productId)],
            updates: {products},
          );
        } else {
          await customUpdate(
            'UPDATE products SET updated_at = ? WHERE id = ?',
            variables: [Variable.withDateTime(DateTime.now()), Variable.withInt(productId)],
            updates: {products},
          );
        }
      }

      return affected;
    });
  }

  /// Count historical references to [variantId] across all transactional and
  /// audit tables. Mirrors `ProductDao.countProductReferences` but at variant
  /// granularity. A non-zero count means the variant cannot be hard-deleted
  /// without breaking audit trail / accounting integrity (FK restrict on
  /// `sale_items`, `purchase_items`, `inventory_adjustments`, return adjs).
  /// Batches and price-history are technically cascade in the schema, but
  /// they carry COGS / pricing lineage we must preserve, so they count too.
  Future<int> countVariantReferences(int variantId) async {
    final row = await customSelect(
      '''
      SELECT
        (SELECT COUNT(*) FROM sale_items WHERE variant_id = ?1)
        + (SELECT COUNT(*) FROM purchase_items WHERE variant_id = ?1)
        + (SELECT COUNT(*) FROM purchase_return_adjustment_items WHERE variant_id = ?1)
        + (SELECT COUNT(*) FROM sale_return_adjustment_items WHERE variant_id = ?1)
        + (SELECT COUNT(*) FROM inventory_adjustments WHERE variant_id = ?1)
        + (SELECT COUNT(*) FROM product_batches WHERE variant_id = ?1)
        + (SELECT COUNT(*) FROM product_price_histories WHERE variant_id = ?1)
        AS ref_count
      ''',
      variables: [Variable.withInt(variantId)],
    ).getSingle();
    return row.read<int>('ref_count');
  }

  /// Smart delete that mirrors QuickBooks/Xero/Odoo behaviour for variants:
  /// variants with historical references are deactivated (`is_active = 0`)
  /// to preserve audit trail and journal/COGS integrity; variants with no
  /// references are hard-deleted. Always runs in a single transaction so
  /// the parent product's `has_variants` flag stays consistent.
  ///
  /// Returns `(wasDeleted, referenceCount)`.
  ///   - `wasDeleted = true`  -> row removed from product_variants
  ///   - `wasDeleted = false` -> row deactivated (had `referenceCount` refs)
  Future<({bool wasDeleted, int referenceCount})> smartDeleteVariant(int variantId) {
    return transaction(() async {
      final variant = await (select(productVariants)..where((v) => v.id.equals(variantId)))
          .getSingleOrNull();
      if (variant == null) {
        return (wasDeleted: false, referenceCount: 0);
      }

      final refCount = await countVariantReferences(variantId);
      final productId = variant.productId;

      if (refCount > 0) {
        // Soft delete: deactivate the variant. Stock and cost are preserved
        // so reports / cost-of-goods stay reproducible. The user can still
        // run an inventory write-off through the adjustment service if they
        // want to zero on-hand value (this routes through the GL properly).
        await (update(productVariants)..where((v) => v.id.equals(variantId))).write(
          ProductVariantsCompanion(
            isActive: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        await (delete(productVariants)..where((v) => v.id.equals(variantId))).go();
      }

      // Keep products.has_variants in sync with the count of remaining
      // active dimensional variants (color or size != null), matching the
      // semantics used in `deactivateDimensionalVariants`.
      final row = await customSelect(
        'SELECT COUNT(*) as cnt FROM product_variants '
        'WHERE product_id = ? AND is_active = 1 '
        'AND (color_id IS NOT NULL OR size_id IS NOT NULL)',
        variables: [Variable.withInt(productId)],
      ).getSingle();
      final remainingDimensional = row.read<int>('cnt');
      if (remainingDimensional == 0) {
        await customUpdate(
          'UPDATE products SET has_variants = 0, updated_at = ? WHERE id = ?',
          variables: [Variable.withDateTime(DateTime.now()), Variable.withInt(productId)],
          updates: {products},
        );
      } else {
        await customUpdate(
          'UPDATE products SET updated_at = ? WHERE id = ?',
          variables: [Variable.withDateTime(DateTime.now()), Variable.withInt(productId)],
          updates: {products},
        );
      }

      return (wasDeleted: refCount == 0, referenceCount: refCount);
    });
  }
}
