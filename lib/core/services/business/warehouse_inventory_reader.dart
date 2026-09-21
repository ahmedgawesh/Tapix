import 'package:drift/drift.dart';
import '../../database/app_database.dart';
import '../batch_service.dart';
import 'warehouse_operation_scope.dart';

class WarehouseInventoryReader {
  WarehouseInventoryReader._();

  /// Read the operational balance, never the product's compatibility mirror.
  /// The caller owns the posting transaction and its validated document scope.
  static Future<({int variantId, int quantity, int unitCostCents})> read(
    DatabaseAccessor<AppDatabase> dao,
    WarehouseOperationScope scope,
    int productId,
    int? variantId,
  ) async {
    await scope.validate(dao.attachedDatabase);
    final candidates = await dao
        .customSelect(
          'SELECT v.id FROM product_variants v JOIN products p ON p.id = v.product_id '
          'WHERE v.product_id = ? AND '
          '(? IS NOT NULL AND v.id = ? OR ? IS NULL AND p.has_variants = 0 AND v.is_active = 1) '
          'LIMIT 2',
          variables: [
            Variable.withInt(productId),
            Variable<int>(variantId),
            Variable<int>(variantId),
            Variable<int>(variantId),
          ],
        )
        .get();
    if (candidates.length != 1) {
      throw StateError('Document requires one matching operational variant');
    }
    final row = await dao
        .customSelect(
          'SELECT quantity, unit_cost_cents FROM business_warehouse_stocks '
          'WHERE warehouse_id = ? AND variant_id = ?',
          variables: [
            Variable.withString(scope.warehouseId),
            Variable.withInt(candidates.single.read<int>('id')),
          ],
        )
        .getSingleOrNull();
    if (row == null) throw StateError('Document warehouse balance is missing');
    return (
      variantId: candidates.single.read<int>('id'),
      quantity: row.read<int>('quantity'),
      unitCostCents: row.read<int>('unit_cost_cents'),
    );
  }

  static Future<void> assertBatches(
    DatabaseAccessor<AppDatabase> dao, {
    required WarehouseOperationScope scope,
    required int productId,
  }) async {
    await scope.validate(dao.attachedDatabase);
    if (scope.isPrimary) {
      await BatchService.assertInvariantForProduct(
        dao,
        scope: scope,
        productId: productId,
      );
      return;
    }
    final variants = await dao
        .customSelect(
          'SELECT v.id FROM product_variants v JOIN business_warehouse_stocks s ON s.variant_id = v.id '
          'WHERE v.product_id = ? AND s.warehouse_id = ?',
          variables: [
            Variable.withInt(productId),
            Variable.withString(scope.warehouseId),
          ],
        )
        .get();
    for (final variant in variants) {
      await BatchService.assertInvariant(
        dao,
        scope: scope,
        productId: productId,
        variantId: variant.read<int>('id'),
      );
    }
  }
}
