import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'document_posting_scope.dart';

/// Internal read boundary. Callers authorize access separately. Unlike an
/// operation scope, this preserves stock and history for disabled locations.
class WarehouseReadScope {
  WarehouseReadScope._(
    this._database,
    this.organizationId,
    this.branchId,
    this.warehouseId,
    this.databaseId,
    this.isPrimary, [
    this._accessCheck,
  ]);

  final AppDatabase _database;
  final String organizationId;
  final String branchId;
  final String warehouseId;
  final String databaseId;
  final bool isPrimary;
  final Future<void> Function()? _accessCheck;

  WarehouseReadScope withAccessCheck(Future<void> Function() check) =>
      WarehouseReadScope._(
        _database,
        organizationId,
        branchId,
        warehouseId,
        databaseId,
        isPrimary,
        check,
      );

  Future<void> checkAccess() => validate(_database);

  static Future<WarehouseReadScope> resolve(
    AppDatabase db, {
    String? warehouseId,
  }) async {
    final rows = await db
        .customSelect(
          '''
      SELECT c.organization_id, c.branch_id, c.database_id,
        c.warehouse_id AS primary_id, w.id AS selected_id
      FROM business_contexts c
      JOIN business_warehouses w ON w.id = COALESCE(?, c.warehouse_id)
        AND w.organization_id = c.organization_id AND w.branch_id = c.branch_id
      JOIN business_branches b ON b.id = c.branch_id
        AND b.organization_id = c.organization_id
      WHERE c.id = 1
    ''',
          variables: [Variable<String>(warehouseId)],
        )
        .get();
    if (rows.length != 1) {
      throw StateError('Warehouse does not belong to the local branch.');
    }
    final r = rows.single;
    return WarehouseReadScope._(
      db,
      r.read<String>('organization_id'),
      r.read<String>('branch_id'),
      r.read<String>('selected_id'),
      r.read<String>('database_id'),
      r.read<String>('selected_id') == r.read<String>('primary_id'),
    );
  }

  static Future<T> snapshot<T>(
    AppDatabase db,
    WarehouseReadScope? scope,
    Future<T> Function() action,
  ) => db.transaction(() async {
    await scope?.validate(db);
    return action();
  });

  Future<void> validate(AppDatabase db) async {
    if (!identical(_database, db)) {
      throw StateError('Read scope belongs to another database connection.');
    }
    await _accessCheck?.call();
    final current = await resolve(db, warehouseId: warehouseId);
    if (current.organizationId != organizationId ||
        current.branchId != branchId ||
        current.databaseId != databaseId ||
        current.isPrimary != isPrimary) {
      throw StateError('Read scope binding changed.');
    }
  }

  // SQL fragments are composed only from immutable, database-resolved values;
  // quote every literal, including legacy identifiers containing apostrophes.
  static String _literal(String value) => "'${value.replaceAll("'", "''")}'";
  String get _binding =>
      '''EXISTS (
    SELECT 1 FROM business_contexts c
    JOIN business_warehouses w ON w.id = ${_literal(warehouseId)}
      AND w.organization_id = c.organization_id AND w.branch_id = c.branch_id
    JOIN business_branches b ON b.id = c.branch_id
      AND b.organization_id = c.organization_id
    WHERE c.id = 1 AND c.database_id = ${_literal(databaseId)}
      AND c.organization_id = ${_literal(organizationId)}
      AND c.branch_id = ${_literal(branchId)})''';

  String get warehouses =>
      '(SELECT w.* FROM business_warehouses w '
      'WHERE w.id = ${_literal(warehouseId)} AND $_binding)';

  String get stocks => '''(SELECT s.* FROM business_warehouse_stocks s
    WHERE s.warehouse_id = ${_literal(warehouseId)} AND $_binding)''';

  String _located(String table) =>
      '''(SELECT d.* FROM $table d
    WHERE $_binding AND EXISTS (SELECT 1 FROM business_document_locations l
      WHERE l.source_table = '$table' AND l.source_id = d.id
        AND l.organization_id = ${_literal(organizationId)}
        AND l.branch_id = ${_literal(branchId)}
        AND l.warehouse_id = ${_literal(warehouseId)}))''';

  String documents(InventoryPostingDocument kind) => _located(kind.table);
  String get batches => _located('product_batches');
  String get adjustments => _located('inventory_adjustments');
  String get journals => _located('journal_entries');
}
