import 'inventory/inventory_origin_service.dart';
export 'inventory/inventory_origin_service.dart' show InventoryOriginIntent;
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import 'logging_service.dart';
import 'business/warehouse_operation_scope.dart';

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
  /// 1. **Variant exists** (`variantId != null`): updates the selected warehouse.
  /// 2. **No variant** (`variantId == null`): resolves the single active row
  ///    of a simple product, then updates both that row and `products`.
  /// An omitted scope preserves primary-warehouse behavior. Explicit scopes
  /// must be passed through the entire posting pipeline, including costs.
  /// 3. After adjustment, callers should invoke [syncProductStockFromVariants]
  ///    to keep `products.stock_quantity` in sync.
  ///
  /// Runtime preconditions (also enforced in release builds):
  /// - [quantity] must be >= 0
  /// - [productId] must be > 0
  static Future<void> adjustStock(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    int? variantId,
    required int quantity,
    required StockDirection direction,
    WarehouseOperationScope? scope,
    InventoryOriginIntent? origin,
  }) async {
    if (quantity < 0 ||
        productId <= 0 ||
        (variantId != null && variantId <= 0)) {
      throw ArgumentError(
        'Stock requires non-negative quantity and positive IDs.',
      );
    }

    if (quantity == 0) return;

    final sign = direction == StockDirection.increase ? '+' : '-';
    final now = DateTime.now().toIso8601String();

    LoggingService.debug(
      'adjustStock: product=$productId variant=$variantId '
      'qty=$sign$quantity',
      tag: _tag,
    );

    await dao.attachedDatabase.transaction(() async {
      final operationScope =
          scope ?? await WarehouseOperationScope.resolve(dao.attachedDatabase);
      await operationScope.validate(dao.attachedDatabase);
      Future<void> updateWarehouse(int resolvedVariantId) async {
        final originLayers = await InventoryOriginService.capture(
          dao.attachedDatabase,
          operationScope.warehouseId,
          resolvedVariantId,
        );
        final changed = await dao.customUpdate(
          'UPDATE business_warehouse_stocks SET quantity = quantity $sign ?, '
          'updated_at = ? WHERE variant_id = ? '
          'AND warehouse_id = ? '
          'AND EXISTS (SELECT 1 FROM product_variants v WHERE v.id = variant_id AND v.product_id = ?)',
          variables: [
            Variable.withInt(quantity),
            Variable.withString(now),
            Variable.withInt(resolvedVariantId),
            Variable.withString(operationScope.warehouseId),
            Variable.withInt(productId),
          ],
          updates: {
            dao.attachedDatabase.productVariants,
            dao.attachedDatabase.businessWarehouseStocks,
          },
          updateKind: UpdateKind.update,
        );
        if (changed != 1) {
          throw StateError(
            'Missing warehouse balance or variant/product mismatch.',
          );
        }
        if (originLayers != null) {
          await InventoryOriginService.record(
            dao.attachedDatabase,
            warehouse: operationScope.warehouseId,
            variant: resolvedVariantId,
            product: productId,
            delta: direction == StockDirection.increase ? quantity : -quantity,
            layers: originLayers,
            intent: origin,
          );
        }
      }

      if (variantId != null) {
        await updateWarehouse(variantId);
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

        // Only the primary warehouse owns the legacy parent projection.
        if (operationScope.isPrimary) {
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
        }
        // Apply the movement to the one canonical row in this warehouse. Its optional
        // colour/size must not affect stock identity for a simple product.
        await updateWarehouse(canonicalVariantId);
      }
    });
  }

  /// Sync the parent quantity from primary-warehouse balances of active variants.
  ///
  /// Must be called after one or more [adjustStock] calls for the same product.
  static Future<void> syncProductStockFromVariants(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    WarehouseOperationScope? scope,
  }) async {
    if (productId <= 0) throw ArgumentError.value(productId, 'productId');

    await dao.attachedDatabase.transaction(() async {
      final operationScope =
          scope ?? await WarehouseOperationScope.resolve(dao.attachedDatabase);
      await operationScope.validate(dao.attachedDatabase);
      if (!operationScope.isPrimary) return;
      final now = DateTime.now().toIso8601String();
      final stockRow = await dao
          .customSelect(
            'SELECT COALESCE(SUM(ws.quantity), 0) AS total_stock, '
            'COUNT(v.id) AS variant_count, COUNT(ws.variant_id) AS balance_count '
            'FROM product_variants v LEFT JOIN business_warehouse_stocks ws '
            'ON ws.variant_id = v.id AND ws.warehouse_id = ? '
            'WHERE v.product_id = ? AND v.is_active = 1',
            variables: [
              Variable.withString(operationScope.warehouseId),
              Variable.withInt(productId),
            ],
          )
          .getSingleOrNull();

      if (stockRow != null) {
        if (stockRow.read<int>('variant_count') !=
            stockRow.read<int>('balance_count')) {
          throw StateError(
            'Missing warehouse balance during stock aggregation.',
          );
        }
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
    });
  }
}
