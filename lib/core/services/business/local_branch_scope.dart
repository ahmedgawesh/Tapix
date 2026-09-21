import '../../database/app_database.dart';

/// Server-owned data boundary, independent of user roles and paid add-ons.
/// A paired cashier operates the master's database, never its own local scope.
class LocalBranchScope {
  const LocalBranchScope({
    required this.organizationId,
    required this.branchId,
    required this.warehouseId,
    required this.databaseId,
  });

  final String organizationId;
  final String branchId;
  final String warehouseId;
  final String databaseId;

  Map<String, String> toJson() => {
    'organizationId': organizationId,
    'branchId': branchId,
    'warehouseId': warehouseId,
    'databaseId': databaseId,
  };

  bool matchesBinding(Object? binding) {
    if (binding is! Map) return false;
    return toJson().entries.every((e) => binding[e.key] == e.value);
  }

  /// Optional assertions, not routing instructions. Missing fields preserve
  /// compatibility with existing single-branch clients. Explicit null, lists,
  /// foreign IDs and unknown aliases cannot select another site's data.
  bool acceptsSelectors(Map<String, dynamic> selectors) {
    for (final entry in toJson().entries) {
      final snake = entry.key.replaceAll('Id', '_id');
      for (final key in [entry.key, snake]) {
        if (selectors.containsKey(key) && selectors[key] != entry.value) {
          return false;
        }
      }
    }
    return true;
  }

  static Future<LocalBranchScope> read(AppDatabase db) async {
    final rows = await db.customSelect('''
      SELECT c.organization_id, c.branch_id, c.warehouse_id, c.database_id
      FROM business_contexts c
      JOIN business_organizations o ON o.id = c.organization_id
      JOIN business_branches b ON b.id = c.branch_id AND b.organization_id = o.id
      JOIN business_warehouses w ON w.id = c.warehouse_id
        AND w.branch_id = b.id AND w.organization_id = o.id
      WHERE c.id = 1 AND b.is_active = 1 AND w.is_active = 1
    ''').get();
    if (rows.length != 1) throw StateError('No active local business scope.');
    final row = rows.single;
    return LocalBranchScope(
      organizationId: row.read<String>('organization_id'),
      branchId: row.read<String>('branch_id'),
      warehouseId: row.read<String>('warehouse_id'),
      databaseId: row.read<String>('database_id'),
    );
  }
}
