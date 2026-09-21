import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'local_branch_scope.dart';
import 'warehouse_read_scope.dart';

/// Internal inventory routing, not a user permission or an add-on entitlement.
/// Callers must authorize a selected warehouse before resolving it. Public
/// entry points remain primary-only until the complete posting pipeline lands.
/// Never change business_contexts to select a warehouse for one operation.
class WarehouseOperationScope {
  WarehouseOperationScope._(this._database, this._local, this.warehouseId);

  final AppDatabase _database;
  final LocalBranchScope _local;
  final String warehouseId;

  String get organizationId => _local.organizationId;
  String get branchId => _local.branchId;
  String get databaseId => _local.databaseId;
  bool get isPrimary => warehouseId == _local.warehouseId;

  static Future<WarehouseOperationScope> resolve(
    AppDatabase db, {
    String? warehouseId,
  }) async {
    final local = await LocalBranchScope.read(db);
    final scope = WarehouseOperationScope._(
      db,
      local,
      warehouseId ?? local.warehouseId,
    );
    await scope.validate(db);
    return scope;
  }

  Future<WarehouseReadScope> forReading(AppDatabase db) async {
    if (!identical(db, _database)) {
      throw StateError('Scope belongs to another connection');
    }
    final selected = await WarehouseReadScope.resolve(
      db,
      warehouseId: warehouseId,
    );
    if (selected.organizationId != organizationId ||
        selected.branchId != branchId ||
        selected.databaseId != databaseId ||
        selected.isPrimary != isPrimary) {
      throw StateError('Warehouse binding changed');
    }
    return selected;
  }

  /// Recheck inside the caller's write transaction: a previously selected
  /// warehouse may have been disabled, removed or rebound in the meantime.
  Future<void> validate(AppDatabase db) async {
    if (!identical(db, _database)) {
      throw StateError(
        'Warehouse scope belongs to another database connection.',
      );
    }
    final current = await LocalBranchScope.read(db);
    if (!_local.matchesBinding(current.toJson())) {
      throw StateError('Local business scope changed during the operation.');
    }
    final rows = await db
        .customSelect(
          '''SELECT id FROM business_warehouses
      WHERE id = ? AND organization_id = ? AND branch_id = ? AND is_active = 1''',
          variables: [
            Variable.withString(warehouseId),
            Variable.withString(organizationId),
            Variable.withString(branchId),
          ],
        )
        .get();
    if (rows.length != 1) {
      throw StateError('Warehouse is not active in the local branch.');
    }
  }
}
