import 'package:drift/drift.dart';

import '../../database/app_database.dart';

/// Read boundary for primary-warehouse reports during the compatibility phase.
/// Inactive locations retain their physical stock and financial valuation.
class WarehouseStockScope {
  WarehouseStockScope._();

  static const primaryStocks = '''(
    SELECT s.* FROM business_warehouse_stocks s
    JOIN business_contexts c ON c.warehouse_id = s.warehouse_id
    JOIN business_warehouses w ON w.id = c.warehouse_id
      AND w.organization_id = c.organization_id AND w.branch_id = c.branch_id
    JOIN business_branches b ON b.id = c.branch_id
      AND b.organization_id = c.organization_id
    WHERE c.id = 1
  )''';

  static Set<TableInfo<Table, dynamic>> dependencies(AppDatabase db) => {
    db.businessWarehouseStocks,
    db.businessContexts,
    db.businessWarehouses,
    db.businessBranches,
  };
}
