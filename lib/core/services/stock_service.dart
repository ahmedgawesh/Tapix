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
  /// 2. **No variant** (`variantId == null`): updates both `products` row AND
  ///    the default variant (`color_id IS NULL AND size_id IS NULL`).
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
      // Also update the default variant. Guard against the silent-desync
      // case where the product has NO strict-default variant
      // (color_id IS NULL AND size_id IS NULL) — updating zero rows and then
      // letting `syncProductStockFromVariants` overwrite
      // `products.stock_quantity` with SUM(variants.stock_quantity) would
      // erase this adjustment while its journal entry stays posted. Require
      // the caller to pass a real `variantId` in that scenario.
      final variantUpdated = await dao.customUpdate(
        'UPDATE product_variants SET stock_quantity = stock_quantity $sign ?, '
        'updated_at = ? '
        'WHERE product_id = ? AND color_id IS NULL AND size_id IS NULL',
        variables: [
          Variable.withInt(quantity),
          Variable.withString(now),
          Variable.withInt(productId),
        ],
        updates: {dao.attachedDatabase.productVariants},
        updateKind: UpdateKind.update,
      );
      if (variantUpdated == 0) {
        throw StateError(
          'StockService.adjustStock: product=$productId has no default '
          '(color_id IS NULL AND size_id IS NULL) variant. Pass a concrete '
          'variantId instead of null — otherwise syncProductStockFromVariants '
          'would silently revert this adjustment and desync the ledger.',
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
    final stockRow = await dao.customSelect(
      'SELECT COALESCE(SUM(stock_quantity), 0) AS total_stock '
      'FROM product_variants WHERE product_id = ? AND is_active = 1',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();

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
