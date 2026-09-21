import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import '../business/warehouse_operation_scope.dart';

/// Inventory costing method marker — stored on every adjustment row so that
/// a future switch to FIFO for a product class (e.g. pharmacy batches) does
/// not invalidate historical records.
enum CostingMethod {
  weightedAverage,
  fifo;

  String get wireName => switch (this) {
    CostingMethod.weightedAverage => 'weighted_average',
    CostingMethod.fifo => 'fifo',
  };
}

/// Pluggable strategy that resolves the **unit cost** that should be used
/// when valuing an inventory movement (shrinkage / gain / revaluation /
/// COGS).  Keeping this as an interface means adding FIFO later is a drop-in
/// change: only [unitCostCents] differs; all call sites stay the same.
abstract class CostingStrategy {
  CostingMethod get method;

  /// Resolve the unit cost (in cents) of the given stock keeping unit.
  ///
  /// For a variant-bearing product [variantId] MUST be provided; for a
  /// single-variant product callers may pass null and the default variant's
  /// cost will be used (fallback: `products.cost_cents`).
  Future<int> unitCostCents({
    required DatabaseAccessor<AppDatabase> dao,
    required int productId,
    int? variantId,
    WarehouseOperationScope? scope,
  });

  /// Current on-hand quantity used for revaluation delta calculation.
  Future<int> onHandQuantity({
    required DatabaseAccessor<AppDatabase> dao,
    required int productId,
    int? variantId,
    WarehouseOperationScope? scope,
  });
}

/// Reads the selected warehouse's current moving-average cost. Callers capture
/// quantity and cost inside the same posting transaction. Moving-average cost
/// depends on movement order; it is not a conflict-resolution rule for sync.
class WeightedAverageCostingStrategy implements CostingStrategy {
  const WeightedAverageCostingStrategy();

  @override
  CostingMethod get method => CostingMethod.weightedAverage;

  @override
  Future<int> unitCostCents({
    required DatabaseAccessor<AppDatabase> dao,
    required int productId,
    int? variantId,
    WarehouseOperationScope? scope,
  }) async => (await _balance(dao, productId, variantId, scope)).cost;

  @override
  Future<int> onHandQuantity({
    required DatabaseAccessor<AppDatabase> dao,
    required int productId,
    int? variantId,
    WarehouseOperationScope? scope,
  }) async => (await _balance(dao, productId, variantId, scope)).quantity;

  static Future<({int quantity, int cost})> _balance(
    DatabaseAccessor<AppDatabase> dao,
    int productId,
    int? variantId,
    WarehouseOperationScope? scope,
  ) async {
    final operation =
        scope ?? await WarehouseOperationScope.resolve(dao.attachedDatabase);
    await operation.validate(dao.attachedDatabase);
    final product = await (dao.attachedDatabase.select(
      dao.attachedDatabase.products,
    )..where((p) => p.id.equals(productId))).getSingleOrNull();
    if (product == null) {
      throw StateError('Inventory costing product is missing.');
    }
    var resolved = variantId;
    if (resolved == null) {
      if (product.hasVariants) {
        throw StateError('Inventory costing requires an explicit variant.');
      }
      final rows = await dao
          .customSelect(
            'SELECT id FROM product_variants WHERE product_id = ? AND is_active = 1 LIMIT 2',
            variables: [Variable.withInt(productId)],
          )
          .get();
      if (rows.length > 1) {
        throw StateError('Inventory costing variant is ambiguous.');
      }
      if (rows.isEmpty) {
        if (!operation.isPrimary) {
          throw StateError(
            'Selected warehouse requires an operational variant.',
          );
        }
        return (
          quantity: product.stockQuantity,
          cost: product.costCents.toBigInt().toInt(),
        );
      }
      resolved = rows.single.read<int>('id');
    }
    final row = await dao
        .customSelect(
          'SELECT s.quantity, s.unit_cost_cents FROM business_warehouse_stocks s '
          'JOIN product_variants v ON v.id = s.variant_id '
          'WHERE s.warehouse_id = ? AND s.variant_id = ? AND v.product_id = ?',
          variables: [
            Variable.withString(operation.warehouseId),
            Variable.withInt(resolved),
            Variable.withInt(productId),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      throw StateError(
        'Inventory costing balance missing or variant belongs to another product.',
      );
    }
    return (
      quantity: row.read<int>('quantity'),
      cost: row.read<int>('unit_cost_cents'),
    );
  }
}
