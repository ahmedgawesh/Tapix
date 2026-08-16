import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../measurement/measurement.dart';

/// A frozen carrying-value boundary for one standard-cost inventory SKU.
///
/// Inventory health values each standard/WAC variant as one rounded pool:
/// `round(stock_quantity * cost_cents / quantity_scale)`. Consequently the
/// exact value moved by a fractional quantity is the difference between the
/// rounded pool before and after the mutation, which can differ by one cent
/// from rounding the movement in isolation.
class InventoryValuationSnapshot {
  final int productId;
  final int? variantId;
  final int quantity;
  final int unitCostCents;
  final int quantityScale;

  const InventoryValuationSnapshot({
    required this.productId,
    required this.variantId,
    required this.quantity,
    required this.unitCostCents,
    required this.quantityScale,
  });

  int get valueCents => MeasuredAmount.cents(
    unitCents: unitCostCents,
    quantity: quantity,
    quantityScale: quantityScale,
  );
}

/// Computes the exact signed change in the same rounded inventory pool used
/// by the accounting-health check. FIFO/batch products deliberately return
/// `null`; their exact value comes from batch consumptions instead.
class InventoryValuationDeltaService {
  InventoryValuationDeltaService._();

  static Future<InventoryValuationSnapshot?> capture(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    int? variantId,
  }) async {
    final product = await dao
        .customSelect(
          'SELECT track_inventory, costing_method, inventory_tracking_type, '
          'measurement_type, stock_quantity, cost_cents '
          'FROM products WHERE id = ?',
          variables: [Variable.withInt(productId)],
        )
        .getSingleOrNull();
    if (product == null || (product.read<int?>('track_inventory') ?? 1) == 0) {
      return null;
    }
    final method = product.read<String?>('costing_method') ?? 'wac';
    final tracking = product.read<String?>('inventory_tracking_type');
    if (method == 'fifo' || tracking == 'batch' || tracking == 'batch_expiry') {
      return null;
    }

    final measurementType =
        product.read<String?>('measurement_type') ?? 'piece';
    final quantityScale = measurementType == 'piece' ? 1 : 1000;
    final resolvedVariantId =
        variantId ?? await _defaultVariantId(dao, productId);
    if (resolvedVariantId == null) {
      return InventoryValuationSnapshot(
        productId: productId,
        variantId: null,
        quantity: product.read<int>('stock_quantity'),
        unitCostCents: product.read<int>('cost_cents'),
        quantityScale: quantityScale,
      );
    }

    final variant = await dao
        .customSelect(
          'SELECT stock_quantity, cost_cents FROM product_variants WHERE id = ?',
          variables: [Variable.withInt(resolvedVariantId)],
        )
        .getSingleOrNull();
    if (variant == null) {
      throw StateError(
        'Inventory valuation snapshot: variant=$resolvedVariantId not found.',
      );
    }
    return InventoryValuationSnapshot(
      productId: productId,
      variantId: resolvedVariantId,
      quantity: variant.read<int>('stock_quantity'),
      unitCostCents: variant.read<int>('cost_cents'),
      quantityScale: quantityScale,
    );
  }

  /// Returns `after − before` in cents. Positive means inventory value
  /// increased; negative means it decreased.
  static Future<int> signedDeltaAfter(
    DatabaseAccessor<AppDatabase> dao,
    InventoryValuationSnapshot snapshot,
  ) async {
    final QueryRow? current;
    if (snapshot.variantId != null) {
      current = await dao
          .customSelect(
            'SELECT stock_quantity, cost_cents FROM product_variants WHERE id = ?',
            variables: [Variable.withInt(snapshot.variantId!)],
          )
          .getSingleOrNull();
    } else {
      current = await dao
          .customSelect(
            'SELECT stock_quantity, cost_cents FROM products WHERE id = ?',
            variables: [Variable.withInt(snapshot.productId)],
          )
          .getSingleOrNull();
    }
    if (current == null) {
      throw StateError(
        'Inventory valuation boundary disappeared for product='
        '${snapshot.productId}, variant=${snapshot.variantId}.',
      );
    }
    final afterValue = MeasuredAmount.cents(
      unitCents: current.read<int>('cost_cents'),
      quantity: current.read<int>('stock_quantity'),
      quantityScale: snapshot.quantityScale,
    );
    return afterValue - snapshot.valueCents;
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
