import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../measurement/measurement.dart';
import '../business/warehouse_operation_scope.dart';

/// A frozen carrying-value boundary for one standard-cost inventory SKU.
///
/// Inventory health values each standard/WAC variant as one rounded pool:
/// `round(stock_quantity * cost_cents / quantity_scale)`. Consequently the
/// exact value moved by a fractional quantity is the difference between the
/// rounded pool before and after the mutation, which can differ by one cent
/// from rounding the movement in isolation.
class InventoryValuationSnapshot {
  final WarehouseOperationScope? scope;
  final String warehouseId;
  final int productId;
  final int? variantId;
  final int quantity;
  final int unitCostCents;
  final int quantityScale;

  const InventoryValuationSnapshot({
    this.scope,
    required this.warehouseId,
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
    WarehouseOperationScope? scope,
  }) async {
    final product = await dao
        .customSelect(
          'SELECT track_inventory, costing_method, inventory_tracking_type, '
          'measurement_type, has_variants, stock_quantity, cost_cents '
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

    final operationScope =
        scope ?? await WarehouseOperationScope.resolve(dao.attachedDatabase);
    await operationScope.validate(dao.attachedDatabase);
    if (variantId == null && product.read<bool>('has_variants')) {
      throw StateError(
        'Inventory valuation requires an explicit variant for product=$productId.',
      );
    }
    final measurementType =
        product.read<String?>('measurement_type') ?? 'piece';
    final quantityScale = measurementType == 'piece' ? 1 : 1000;
    final resolvedVariantId =
        variantId ?? await _defaultVariantId(dao, productId);
    if (resolvedVariantId == null) {
      if (!operationScope.isPrimary) {
        throw StateError(
          'Secondary warehouse valuation requires an operational variant.',
        );
      }
      return InventoryValuationSnapshot(
        scope: operationScope,
        warehouseId: operationScope.warehouseId,
        productId: productId,
        variantId: null,
        quantity: product.read<int>('stock_quantity'),
        unitCostCents: product.read<int>('cost_cents'),
        quantityScale: quantityScale,
      );
    }

    final variant = await _warehouseBalance(
      dao,
      warehouseId: operationScope.warehouseId,
      productId: productId,
      variantId: resolvedVariantId,
    );
    return InventoryValuationSnapshot(
      scope: operationScope,
      warehouseId: operationScope.warehouseId,
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
    final scope =
        snapshot.scope ??
        await WarehouseOperationScope.resolve(dao.attachedDatabase);
    await scope.validate(dao.attachedDatabase);
    if (scope.warehouseId != snapshot.warehouseId) {
      throw StateError(
        'Inventory valuation warehouse changed during movement.',
      );
    }
    final QueryRow? current;
    if (snapshot.variantId != null) {
      current = await _warehouseBalance(
        dao,
        warehouseId: snapshot.warehouseId,
        productId: snapshot.productId,
        variantId: snapshot.variantId!,
      );
    } else {
      if (!scope.isPrimary) {
        throw StateError(
          'Secondary warehouse valuation cannot read legacy product stock.',
        );
      }
      current = await dao
          .customSelect(
            'SELECT stock_quantity, cost_cents FROM products p WHERE id = ? '
            'AND has_variants = 0 AND NOT EXISTS (SELECT 1 FROM product_variants v '
            'WHERE v.product_id = p.id AND v.is_active = 1)',
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

  static Future<QueryRow> _warehouseBalance(
    DatabaseAccessor<AppDatabase> dao, {
    required String warehouseId,
    required int productId,
    required int variantId,
  }) async {
    final row = await dao
        .customSelect(
          'SELECT s.quantity AS stock_quantity, s.unit_cost_cents AS cost_cents '
          'FROM business_warehouse_stocks s '
          'JOIN product_variants v ON v.id = s.variant_id '
          'WHERE s.warehouse_id = ? AND s.variant_id = ? AND v.product_id = ?',
          variables: [
            Variable.withString(warehouseId),
            Variable.withInt(variantId),
            Variable.withInt(productId),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      throw StateError(
        'Inventory valuation balance missing or variant does not belong to product=$productId, variant=$variantId.',
      );
    }
    return row;
  }

  static Future<int?> _defaultVariantId(
    DatabaseAccessor<AppDatabase> dao,
    int productId,
  ) async {
    // A simple product can have optional dimensions, but must not select an
    // arbitrary pool when its active operational row is ambiguous.
    final rows = await dao
        .customSelect(
          'SELECT id FROM product_variants WHERE product_id = ? AND is_active = 1 LIMIT 2',
          variables: [Variable.withInt(productId)],
        )
        .get();
    if (rows.length > 1) {
      throw StateError(
        'Inventory valuation has multiple active variants for simple product=$productId.',
      );
    }
    return rows.isEmpty ? null : rows.single.read<int>('id');
  }
}
