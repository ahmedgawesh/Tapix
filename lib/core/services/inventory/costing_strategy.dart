import 'package:drift/drift.dart';
import '../../database/app_database.dart';

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
  });

  /// Current on-hand quantity used for revaluation delta calculation.
  Future<int> onHandQuantity({
    required DatabaseAccessor<AppDatabase> dao,
    required int productId,
    int? variantId,
  });
}

/// Moving-Weighted-Average implementation — the default used by QuickBooks,
/// Xero, Odoo (default), Zoho Inventory and every mainstream SME ERP.
/// Deterministic, conflict-free under offline-first multi-branch sync
/// (the arithmetic average of purchases converges regardless of ordering).
class WeightedAverageCostingStrategy implements CostingStrategy {
  const WeightedAverageCostingStrategy();

  @override
  CostingMethod get method => CostingMethod.weightedAverage;

  @override
  Future<int> unitCostCents({
    required DatabaseAccessor<AppDatabase> dao,
    required int productId,
    int? variantId,
  }) async {
    if (variantId != null) {
      final row = await dao.customSelect(
        'SELECT cost_cents FROM product_variants WHERE id = ?',
        variables: [Variable.withInt(variantId)],
      ).getSingleOrNull();
      if (row != null) return row.read<int>('cost_cents');
    }
    // Fallback: single-variant product — read from products table.
    final row = await dao.customSelect(
      'SELECT cost_cents FROM products WHERE id = ?',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();
    return row?.read<int>('cost_cents') ?? 0;
  }

  @override
  Future<int> onHandQuantity({
    required DatabaseAccessor<AppDatabase> dao,
    required int productId,
    int? variantId,
  }) async {
    if (variantId != null) {
      final row = await dao.customSelect(
        'SELECT stock_quantity FROM product_variants WHERE id = ?',
        variables: [Variable.withInt(variantId)],
      ).getSingleOrNull();
      return row?.read<int>('stock_quantity') ?? 0;
    }
    final row = await dao.customSelect(
      'SELECT stock_quantity FROM products WHERE id = ?',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();
    return row?.read<int>('stock_quantity') ?? 0;
  }
}
