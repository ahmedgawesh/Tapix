import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'product_cost_service.dart';

/// Frozen pre-movement state for one concrete inventory variant.
class WacMovementSnapshot {
  final int productId;
  final int variantId;
  final int quantity;
  final int unitCostCents;

  const WacMovementSnapshot({
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

    final row = await dao
        .customSelect(
          'SELECT stock_quantity, cost_cents FROM product_variants WHERE id = ?',
          variables: [Variable.withInt(resolvedVariantId)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw StateError(
        'WacMovementService: variant=$resolvedVariantId not found.',
      );
    }

    return WacMovementSnapshot(
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
    );
    await _syncParent(dao, snapshot.productId);
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
    );
    await _syncParent(dao, snapshot.productId);
  }

  static Future<void> _syncParent(
    DatabaseAccessor<AppDatabase> dao,
    int productId,
  ) {
    return ProductCostService.syncProductFromVariants(
      dao,
      productId: productId,
      syncPrice: false,
    );
  }

  static Future<int?> _defaultVariantId(
    DatabaseAccessor<AppDatabase> dao,
    int productId,
  ) async {
    final strict = await dao
        .customSelect(
          'SELECT id FROM product_variants '
          'WHERE product_id = ? AND color_id IS NULL AND size_id IS NULL '
          'AND is_active = 1 ORDER BY id LIMIT 1',
          variables: [Variable.withInt(productId)],
        )
        .getSingleOrNull();
    if (strict != null) return strict.read<int>('id');

    final any = await dao
        .customSelect(
          'SELECT id FROM product_variants '
          'WHERE product_id = ? AND is_active = 1 ORDER BY id LIMIT 1',
          variables: [Variable.withInt(productId)],
        )
        .getSingleOrNull();
    return any?.read<int>('id');
  }
}
