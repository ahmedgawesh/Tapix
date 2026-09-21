import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'local_branch_scope.dart';
import 'warehouse_operation_scope.dart';

/// Primary-warehouse historical reads and explicit internal operation routing.
/// Batch location is the immutable document location, not a product attribute.
class WarehouseBatchScope {
  WarehouseBatchScope._();

  static String get primaryBatches =>
      '(SELECT * FROM product_batches WHERE ${predicate('product_batches')})';

  static Set<TableInfo<Table, dynamic>> dependencies(AppDatabase db) => {
    db.businessDocumentLocations,
    db.businessContexts,
    db.businessBranches,
    db.businessWarehouses,
  };

  /// Ownership is independent of activation: disabling operations must not
  /// remove physical inventory from historical audit or financial valuation.
  static String predicate(String alias) {
    if (!const {'product_batches', 'pb', 'pb0'}.contains(alias)) {
      throw ArgumentError.value(alias, 'alias');
    }
    return '''EXISTS (
      SELECT 1 FROM business_document_locations bl
      JOIN business_contexts c ON c.organization_id = bl.organization_id
        AND c.branch_id = bl.branch_id AND c.warehouse_id = bl.warehouse_id
      JOIN business_branches b ON b.id = c.branch_id
        AND b.organization_id = c.organization_id
      JOIN business_warehouses w ON w.id = c.warehouse_id
        AND w.branch_id = c.branch_id AND w.organization_id = c.organization_id
      WHERE c.id = 1 AND bl.source_table = 'product_batches'
        AND bl.source_id = $alias.id)''';
  }

  /// Bound parameters are supplied by operationVariables, never SQL IDs from
  /// a client. The caller validates this operation scope inside its transaction.
  static String operationPredicate(String alias) {
    if (!const {'product_batches', 'pb', 'pb0'}.contains(alias)) {
      throw ArgumentError.value(alias, 'alias');
    }
    return 'EXISTS (SELECT 1 FROM business_document_locations bl '
        "WHERE bl.source_table = 'product_batches' AND bl.source_id = $alias.id "
        'AND bl.organization_id = ? AND bl.branch_id = ? AND bl.warehouse_id = ?)';
  }

  static List<Variable> operationVariables(WarehouseOperationScope scope) => [
    Variable.withString(scope.organizationId),
    Variable.withString(scope.branchId),
    Variable.withString(scope.warehouseId),
  ];

  static Future<String> primaryWarehouse(AppDatabase db) async =>
      (await LocalBranchScope.read(db)).warehouseId;

  static Future<void> requireBatch(
    AppDatabase db,
    int batchId, {
    WarehouseOperationScope? scope,
  }) async {
    final operationScope = scope ?? await WarehouseOperationScope.resolve(db);
    await operationScope.validate(db);
    final row = await db
        .customSelect(
          'SELECT id FROM product_batches WHERE id = ? AND ${operationPredicate('product_batches')}',
          variables: [
            Variable.withInt(batchId),
            ...operationVariables(operationScope),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      throw StateError(
        'Batch $batchId does not belong to the selected active warehouse.',
      );
    }
  }
}
