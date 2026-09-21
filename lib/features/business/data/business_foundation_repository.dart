import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/measurement/measurement.dart';
import '../domain/business_scope.dart';

/// Read-only compatibility boundary. Multi-warehouse stock writers must be
/// implemented and released before additional warehouses can be operated.
class BusinessFoundationRepository {
  BusinessFoundationRepository(this._db);
  final AppDatabase _db;

  Selectable<QueryRow> _scopeQuery() => _db.customSelect(
    '''
    SELECT c.organization_id, c.branch_id, c.warehouse_id, c.database_id,
           o.name AS organization_name, b.name AS branch_name,
           w.name AS warehouse_name
    FROM business_contexts c
    JOIN business_organizations o ON o.id = c.organization_id
    JOIN business_branches b ON b.id = c.branch_id AND b.organization_id = o.id
    JOIN business_warehouses w ON w.id = c.warehouse_id
      AND w.branch_id = b.id AND w.organization_id = o.id
    WHERE c.id = 1 AND b.is_active = 1 AND w.is_active = 1
  ''',
    readsFrom: {
      _db.businessContexts,
      _db.businessOrganizations,
      _db.businessBranches,
      _db.businessWarehouses,
    },
  );

  BusinessScope _scope(List<QueryRow> rows) {
    if (rows.length != 1) {
      throw StateError('Missing or inconsistent primary business scope.');
    }
    final row = rows.single;
    return BusinessScope(
      organizationId: row.read<String>('organization_id'),
      branchId: row.read<String>('branch_id'),
      warehouseId: row.read<String>('warehouse_id'),
      databaseId: row.read<String>('database_id'),
      organizationName: row.read<String>('organization_name'),
      branchName: row.read<String>('branch_name'),
      warehouseName: row.read<String>('warehouse_name'),
    );
  }

  Future<BusinessScope> getScope() async => _scope(await _scopeQuery().get());
  Stream<BusinessScope> watchScope() => _scopeQuery().watch().map(_scope);

  /// Reads warehouse stock. Legacy quantity/cost fields remain an atomic
  /// compatibility projection; FIFO valuation still uses its batch layers.
  Future<List<PrimaryWarehouseStock>> getPrimaryWarehouseStock(
    String warehouseId,
  ) async {
    final scope = await getScope();
    if (warehouseId != scope.warehouseId) {
      throw StateError('This database can only operate its primary warehouse.');
    }
    final rows = await _db
        .customSelect(
          '''
      SELECT v.id, v.product_id, s.quantity AS stock_quantity,
             s.unit_cost_cents AS cost_cents, v.is_active,
             p.measurement_type
      FROM product_variants v JOIN products p ON p.id = v.product_id
      JOIN business_warehouse_stocks s ON s.variant_id = v.id
      WHERE s.warehouse_id = ?
      ORDER BY v.id
    ''',
          variables: [Variable.withString(warehouseId)],
          readsFrom: {
            _db.businessWarehouseStocks,
            _db.productVariants,
            _db.products,
          },
        )
        .get();
    return rows
        .map(
          (row) => PrimaryWarehouseStock(
            warehouseId: scope.warehouseId,
            productId: row.read<int>('product_id'),
            variantId: row.read<int>('id'),
            quantity: row.read<int>('stock_quantity'),
            quantityScale: MeasurementType.fromDb(
              row.read<String>('measurement_type'),
            ).quantityScale,
            unitCostCents: row.read<int>('cost_cents'),
            isActive: row.read<bool>('is_active'),
          ),
        )
        .toList(growable: false);
  }
}
