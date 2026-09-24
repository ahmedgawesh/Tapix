import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'product_cost_service.dart';
import '../business/warehouse_operation_scope.dart';

/// Frozen pre-movement state for one concrete inventory variant.
class WacMovementSnapshot {
  final WarehouseOperationScope scope;
  final int productId;
  final int variantId;
  final int quantity;
  final int unitCostCents;

  const WacMovementSnapshot({
    required this.scope,
    required this.productId,
    required this.variantId,
    required this.quantity,
    required this.unitCostCents,
  });
}

/// Central WAC mutation policy for return movements.
///
/// FIFO/batch products return null from [capture] and remain governed by
/// BatchService. Non-inventory and last-cost products are also excluded.
class WacMovementService {
  WacMovementService._();

  /// Capture the quantity and WAC immediately BEFORE a stock movement.
  static Future<WacMovementSnapshot?> capture(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    int? variantId,
    WarehouseOperationScope? scope,
  }) async {
    final product = await dao
        .customSelect(
          'SELECT track_inventory, costing_method, inventory_tracking_type '
          'FROM products WHERE id = ?',
          variables: [Variable.withInt(productId)],
        )
        .getSingleOrNull();
    if (product == null) return null;
    if ((product.read<int?>('track_inventory') ?? 1) == 0) return null;

    final method = product.read<String?>('costing_method') ?? 'wac';
    final tracking = product.read<String?>('inventory_tracking_type');
    if (method != ProductCostService.methodWac ||
        tracking == 'batch' ||
        tracking == 'batch_expiry') {
      return null;
    }

    final resolvedVariantId =
        variantId ?? await _defaultVariantId(dao, productId);
    if (resolvedVariantId == null) {
      throw StateError(
        'WacMovementService: product=$productId has no active/default '
        'variant, so its WAC cannot be updated safely.',
      );
    }

    final operationScope =
        scope ?? await WarehouseOperationScope.resolve(dao.attachedDatabase);
    await operationScope.validate(dao.attachedDatabase);
    final row = await dao
        .customSelect(
          'SELECT (s.quantity - s.supplier_owned_quantity) AS stock_quantity, s.unit_cost_cents AS cost_cents '
          'FROM business_warehouse_stocks s JOIN product_variants v ON v.id = s.variant_id '
          'WHERE s.variant_id = ? AND s.warehouse_id = ? AND v.product_id = ?',
          variables: [
            Variable.withInt(resolvedVariantId),
            Variable.withString(operationScope.warehouseId),
            Variable.withInt(productId),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      throw StateError(
        'WacMovementService: variant=$resolvedVariantId not found.',
      );
    }

    return WacMovementSnapshot(
      scope: operationScope,
      productId: productId,
      variantId: resolvedVariantId,
      quantity: row.read<int>('stock_quantity'),
      unitCostCents: row.read<int>('cost_cents'),
    );
  }

  /// Blend an inbound return into the current WAC after stock was increased.
  static Future<void> applyInbound(
    DatabaseAccessor<AppDatabase> dao, {
    required WacMovementSnapshot snapshot,
    required int addedQty,
    required int inboundUnitCostCents,
  }) async {
    await ProductCostService.applyPurchaseCostToVariant(
      dao,
      variantId: snapshot.variantId,
      beforeQty: snapshot.quantity,
      beforeCostCents: snapshot.unitCostCents,
      addedQty: addedQty,
      newPaidCostCents: inboundUnitCostCents,
      costingMethod: ProductCostService.methodWac,
      scope: snapshot.scope,
    );
    await _syncParent(dao, snapshot.productId, snapshot.scope);
  }

  /// Remove the frozen value of a previously posted inbound return after
  /// stock was decreased (return void).
  static Future<void> reverseInbound(
    DatabaseAccessor<AppDatabase> dao, {
    required WacMovementSnapshot snapshot,
    required int removedQty,
    required int removedUnitCostCents,
  }) async {
    await ProductCostService.applyRemovalCostToVariant(
      dao,
      variantId: snapshot.variantId,
      beforeQty: snapshot.quantity,
      beforeCostCents: snapshot.unitCostCents,
      removedQty: removedQty,
      removedUnitCostCents: removedUnitCostCents,
      costingMethod: ProductCostService.methodWac,
      scope: snapshot.scope,
    );
    await _syncParent(dao, snapshot.productId, snapshot.scope);
  }

  static Future<void> _syncParent(
    DatabaseAccessor<AppDatabase> dao,
    int productId,
    WarehouseOperationScope scope,
  ) {
    return ProductCostService.syncProductFromVariants(
      dao,
      productId: productId,
      syncPrice: false,
      scope: scope,
    );
  }

  static Future<int?> _defaultVariantId(
    DatabaseAccessor<AppDatabase> dao,
    int productId,
  ) async {
    final rows = await dao
        .customSelect(
          'SELECT v.id FROM product_variants v JOIN products p ON p.id = v.product_id '
          'WHERE p.id = ? AND p.has_variants = 0 AND v.is_active = 1 LIMIT 2',
          variables: [Variable.withInt(productId)],
        )
        .get();
    if (rows.length != 1) {
      throw StateError(
        'WAC requires exactly one active simple-product variant or an explicit variant.',
      );
    }
    return rows.single.read<int>('id');
  }
}
