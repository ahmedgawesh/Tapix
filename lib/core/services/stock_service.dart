import 'package:drift/drift.dart';
import '../database/app_database.dart';
import 'logging_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// STOCK DIRECTION
// ══════════════════════════════════════════════════════════════════════════════

/// Direction of stock adjustment.
enum StockDirection { increase, decrease }

// ══════════════════════════════════════════════════════════════════════════════
// STOCK SERVICE
// ══════════════════════════════════════════════════════════════════════════════

/// Static-only service for centralised stock adjustments.
///
/// Takes a [DatabaseAccessor] parameter so it works inside DAO transactions.
/// Same pattern as `TaxCalculationService`.
class StockService {
  StockService._();

  static const String _tag = 'StockService';

  /// Adjust stock for a product/variant by the given [quantity].
  ///
  /// Handles three cases:
  /// 1. **Variant exists** (`variantId != null`): updates `product_variants` row.
  /// 2. **No variant** (`variantId == null`): resolves the single active row
  ///    of a simple product, then updates both that row and `products`.
  /// 3. After adjustment, callers should invoke [syncProductStockFromVariants]
  ///    to keep `products.stock_quantity` in sync.
  ///
  /// Assertions:
  /// - [quantity] must be >= 0
  /// - [productId] must be > 0
  static Future<void> adjustStock(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    int? variantId,
    required int quantity,
    required StockDirection direction,
  }) async {
    assert(quantity >= 0, 'Stock quantity must be non-negative');
    assert(productId > 0, 'productId must be positive');
    assert(
      variantId == null || variantId > 0,
      'variantId must be positive when provided',
    );

    if (quantity == 0) return;

    final sign = direction == StockDirection.increase ? '+' : '-';
    final now = DateTime.now().toIso8601String();

    LoggingService.debug(
      'adjustStock: product=$productId variant=$variantId '
      'qty=$sign$quantity',
      tag: _tag,
    );

    if (variantId != null) {
      await dao.customUpdate(
        'UPDATE product_variants SET stock_quantity = stock_quantity $sign ?, '
        'updated_at = ? WHERE id = ?',
        variables: [
          Variable.withInt(quantity),
          Variable.withString(now),
          Variable.withInt(variantId),
        ],
        updates: {dao.attachedDatabase.productVariants},
        updateKind: UpdateKind.update,
      );
    } else {
      // A simple product's single row may carry an optional colour/size.
      // Resolve by the actual invariant (has_variants=0 + exactly one active
      // row), not by NULL dimensions. Resolve before touching products so a
      // corrupt/multi-row product cannot be half-updated.
      final candidates = await dao
          .customSelect(
            'SELECT v.id FROM product_variants v '
            'JOIN products p ON p.id = v.product_id '
            'WHERE v.product_id = ? AND v.is_active = 1 '
            'AND p.has_variants = 0 ORDER BY v.id LIMIT 2',
            variables: [Variable.withInt(productId)],
          )
          .get();
      if (candidates.length != 1) {
        throw StateError(
          'StockService.adjustStock: simple product=$productId must have '
          'exactly one active operational row; found ${candidates.length}.',
        );
      }
      final canonicalVariantId = candidates.single.read<int>('id');

      // Non-variant product: update the products table directly
      await dao.customUpdate(
        'UPDATE products SET stock_quantity = stock_quantity $sign ?, '
        'updated_at = ? WHERE id = ?',
        variables: [
          Variable.withInt(quantity),
          Variable.withString(now),
          Variable.withInt(productId),
        ],
        updates: {dao.attachedDatabase.products},
        updateKind: UpdateKind.update,
      );
      // Mirror the same movement to the one canonical row. Its optional
      // colour/size must not affect stock identity for a simple product.
      final variantUpdated = await dao.customUpdate(
        'UPDATE product_variants SET stock_quantity = stock_quantity $sign ?, '
        'updated_at = ? WHERE id = ?',
        variables: [
          Variable.withInt(quantity),
          Variable.withString(now),
          Variable.withInt(canonicalVariantId),
        ],
        updates: {dao.attachedDatabase.productVariants},
        updateKind: UpdateKind.update,
      );
      if (variantUpdated == 0) {
        throw StateError(
          'StockService.adjustStock: canonical variant '
          '$canonicalVariantId disappeared for product=$productId.',
        );
      }
    }
  }

  /// Sync `products.stock_quantity` = `SUM(variants.stock_quantity)`.
  ///
  /// Must be called after one or more [adjustStock] calls for the same product.
  static Future<void> syncProductStockFromVariants(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
  }) async {
    assert(productId > 0, 'productId must be positive');

    final now = DateTime.now().toIso8601String();
    final stockRow = await dao
        .customSelect(
          'SELECT COALESCE(SUM(stock_quantity), 0) AS total_stock '
          'FROM product_variants WHERE product_id = ? AND is_active = 1',
          variables: [Variable.withInt(productId)],
        )
        .getSingleOrNull();

    if (stockRow != null) {
      final totalStock = stockRow.read<int>('total_stock');
      await dao.customUpdate(
        'UPDATE products SET stock_quantity = ?, updated_at = ? WHERE id = ?',
        variables: [
          Variable.withInt(totalStock),
          Variable.withString(now),
          Variable.withInt(productId),
        ],
        updates: {dao.attachedDatabase.products},
        updateKind: UpdateKind.update,
      );

      LoggingService.debug(
        'syncProductStock: product=$productId totalStock=$totalStock',
        tag: _tag,
      );
    }
  }
}
