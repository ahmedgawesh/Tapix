import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'warehouse_operation_scope.dart';

/// An explicitly chosen starting cost; quantity always starts at zero.
class WarehouseStockSeed {
  const WarehouseStockSeed({
    required this.variantId,
    required this.unitCostCents,
  });
  final int variantId;
  final int unitCostCents;
}

/// Internal setup, not permission to operate a warehouse. Authorize the scope
/// before calling. Non-zero quantities must use a posted inventory document.
class WarehouseStockInitializationService {
  WarehouseStockInitializationService(this._db);
  final AppDatabase _db;

  /// Atomically insert missing balances only. Existing balances and costs are
  /// never replaced, including on retries after inventory operations.
  Future<int> initialize({
    required WarehouseOperationScope scope,
    required int currencyId,
    required List<WarehouseStockSeed> seeds,
  }) {
    final requested = List<WarehouseStockSeed>.unmodifiable(seeds);
    return _db.transaction(() async {
      await scope.validate(_db);
      if (scope.isPrimary) {
        throw StateError(
          'Primary balances are maintained by the compatibility bridge.',
        );
      }
      if (requested.isEmpty || requested.length > 500) {
        throw ArgumentError('Select between 1 and 500 variants.');
      }
      final ids = <int>{};
      for (final seed in requested) {
        if (seed.variantId <= 0 ||
            !ids.add(seed.variantId) ||
            seed.unitCostCents < 0 ||
            seed.unitCostCents > 9007199254740991) {
          throw ArgumentError('Invalid or duplicate warehouse stock seed.');
        }
      }
      final currency =
          await (_db.select(_db.currencies)..where(
                (c) => c.id.equals(currencyId) & c.isActive.equals(true),
              ))
              .getSingleOrNull();
      if (currency == null) throw StateError('An active currency is required.');
      var created = 0;
      for (final seed in requested) {
        final variant =
            await (_db.select(_db.productVariants)..where(
                  (v) => v.id.equals(seed.variantId) & v.isActive.equals(true),
                ))
                .getSingleOrNull();
        if (variant == null) throw StateError('Variant is unavailable.');
        final product = await (_db.select(
          _db.products,
        )..where((p) => p.id.equals(variant.productId))).getSingle();
        if (!product.isActive ||
            !product.trackInventory ||
            product.currencyId != currencyId) {
          throw StateError(
            'Product must be active, stock-tracked and in the selected currency.',
          );
        }
        final existing =
            await (_db.select(_db.businessWarehouseStocks)..where(
                  (s) =>
                      s.warehouseId.equals(scope.warehouseId) &
                      s.variantId.equals(seed.variantId),
                ))
                .getSingleOrNull();
        if (existing != null) continue;
        // Missing stock with historical inventory evidence is a repair case,
        // never an invitation to recreate an empty balance automatically.
        final history = await _db
            .customSelect(
              '''
          SELECT 1 FROM product_batches b
          JOIN business_document_locations l ON l.source_table = 'product_batches'
            AND l.source_id = b.id
          WHERE l.warehouse_id = ? AND (b.variant_id = ? OR
            (b.variant_id IS NULL AND b.product_id = ?))
          UNION ALL
          SELECT 1 FROM inventory_adjustments a
          WHERE a.warehouse_id = ? AND (a.variant_id = ? OR
            (a.variant_id IS NULL AND a.product_id = ?)) LIMIT 1
        ''',
              variables: [
                Variable.withString(scope.warehouseId),
                Variable.withInt(seed.variantId),
                Variable.withInt(product.id),
                Variable.withString(scope.warehouseId),
                Variable.withInt(seed.variantId),
                Variable.withInt(product.id),
              ],
            )
            .get();
        if (history.isNotEmpty) {
          throw StateError(
            'Missing historical warehouse balance requires repair.',
          );
        }
        await _db
            .into(_db.businessWarehouseStocks)
            .insert(
              BusinessWarehouseStocksCompanion.insert(
                warehouseId: scope.warehouseId,
                variantId: seed.variantId,
                quantity: const Value(0),
                unitCostCents: Value(seed.unitCostCents),
              ),
            );
        created++;
      }
      return created;
    });
  }
}
