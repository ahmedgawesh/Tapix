import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'document_posting_scope.dart';
import 'warehouse_read_scope.dart';

/// Read-only document boundary. Disabled locations retain their history.
class WarehouseDocumentScope {
  WarehouseDocumentScope._();

  static String primaryDocuments(InventoryPostingDocument kind) =>
      '''(
    SELECT d.* FROM ${kind.table} d
    WHERE EXISTS (
      SELECT 1 FROM business_document_locations l
      JOIN business_contexts c ON c.organization_id = l.organization_id
        AND c.branch_id = l.branch_id AND c.warehouse_id = l.warehouse_id
      JOIN business_warehouses w ON w.id = c.warehouse_id
        AND w.branch_id = c.branch_id AND w.organization_id = c.organization_id
      JOIN business_branches b ON b.id = c.branch_id
        AND b.organization_id = c.organization_id
      WHERE c.id = 1 AND l.source_table = '${kind.table}' AND l.source_id = d.id
    )
  )''';

  static Future<bool> contains(
    AppDatabase db,
    InventoryPostingDocument kind,
    int id, {
    WarehouseReadScope? scope,
  }) async {
    await scope?.validate(db);
    return (await db
            .customSelect(
              'SELECT id FROM ${scope?.documents(kind) ?? primaryDocuments(kind)} WHERE id = ?',
              variables: [Variable.withInt(id)],
              readsFrom: dependencies(db),
            )
            .getSingleOrNull()) !=
        null;
  }

  static Set<TableInfo<Table, dynamic>> dependencies(AppDatabase db) => {
    db.businessDocumentLocations,
    db.businessContexts,
    db.businessWarehouses,
    db.businessBranches,
  };

  /// Old simple-product lines may omit variant_id, even with an optional size.
  /// Resolve only an unambiguous active operational row, never guess a variant.
  static String operationalVariant(String alias) {
    if (!const {'pi', 'si', 'srai', 'prai', 'pb'}.contains(alias)) {
      throw ArgumentError.value(alias, 'alias');
    }
    return '''COALESCE($alias.variant_id, (
      SELECT MIN(v0.id) FROM product_variants v0
      JOIN products p0 ON p0.id = v0.product_id AND p0.has_variants = 0
      WHERE v0.product_id = $alias.product_id AND v0.is_active = 1
      HAVING COUNT(*) = 1
    ))''';
  }
}
