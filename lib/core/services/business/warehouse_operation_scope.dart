import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'local_branch_scope.dart';
import 'warehouse_read_scope.dart';

/// Immutable location boundary for one business operation.
///
/// Ordinary in-process operations remain limited to the local branch. The LAN
/// coordinator may resolve a location anywhere inside the same organization
/// and database after authenticating the enrolled device. The global business
/// context is never mutated to switch locations.
class WarehouseOperationScope {
  WarehouseOperationScope._(
    this._database,
    this._local, {
    required this.branchId,
    required this.warehouseId,
    required bool organizationWide,
  }) : _organizationWide = organizationWide;

  final AppDatabase _database;
  final LocalBranchScope _local;
  final bool _organizationWide;
  final String branchId;
  final String warehouseId;

  String get organizationId => _local.organizationId;
  String get databaseId => _local.databaseId;
  bool get isPrimary =>
      branchId == _local.branchId && warehouseId == _local.warehouseId;

  static Future<WarehouseOperationScope> resolve(
    AppDatabase db, {
    String? warehouseId,
  }) => _resolve(db, warehouseId: warehouseId, organizationWide: false);

  /// Used only by the authenticated central LAN coordinator after a device's
  /// organization/location binding has been verified.
  static Future<WarehouseOperationScope> resolveForOrganization(
    AppDatabase db, {
    required String warehouseId,
  }) => _resolve(db, warehouseId: warehouseId, organizationWide: true);

  static Future<WarehouseOperationScope> _resolve(
    AppDatabase db, {
    String? warehouseId,
    required bool organizationWide,
  }) async {
    final local = await LocalBranchScope.read(db);
    final selectedId = warehouseId ?? local.warehouseId;
    final rows = await db
        .customSelect(
          '''SELECT w.branch_id
         FROM business_warehouses w
         JOIN business_branches b ON b.id = w.branch_id
           AND b.organization_id = w.organization_id
         WHERE w.id = ? AND w.organization_id = ?
           AND w.is_active = 1 AND b.is_active = 1
           ${organizationWide ? '' : 'AND w.branch_id = ?'}''',
          variables: [
            Variable.withString(selectedId),
            Variable.withString(local.organizationId),
            if (!organizationWide) Variable.withString(local.branchId),
          ],
        )
        .get();
    if (rows.length != 1) {
      throw StateError(
        organizationWide
            ? 'Warehouse is not active in this organization.'
            : 'Warehouse is not active in the local branch.',
      );
    }
    return WarehouseOperationScope._(
      db,
      local,
      branchId: rows.single.read<String>('branch_id'),
      warehouseId: selectedId,
      organizationWide: organizationWide,
    );
  }

  Future<WarehouseReadScope> forReading(AppDatabase db) async {
    if (!identical(db, _database)) {
      throw StateError('Scope belongs to another connection');
    }
    final selected = await WarehouseReadScope.resolve(
      db,
      warehouseId: warehouseId,
      organizationWide: _organizationWide,
    );
    if (selected.organizationId != organizationId ||
        selected.branchId != branchId ||
        selected.databaseId != databaseId ||
        selected.isPrimary != isPrimary) {
      throw StateError('Warehouse binding changed');
    }
    return selected;
  }

  /// Recheck inside the caller's write transaction. The local database
  /// identity and the selected active location must both remain unchanged.
  Future<void> validate(AppDatabase db) async {
    if (!identical(db, _database)) {
      throw StateError(
        'Warehouse scope belongs to another database connection.',
      );
    }
    final current = await LocalBranchScope.read(db);
    if (current.organizationId != organizationId ||
        current.databaseId != databaseId) {
      throw StateError('Local business identity changed during the operation.');
    }
    if (!_organizationWide && current.branchId != branchId) {
      throw StateError('Local business branch changed during the operation.');
    }
    final rows = await db
        .customSelect(
          '''SELECT 1 AS found
         FROM business_warehouses w
         JOIN business_branches b ON b.id = w.branch_id
           AND b.organization_id = w.organization_id
         WHERE w.id = ? AND w.organization_id = ? AND w.branch_id = ?
           AND w.is_active = 1 AND b.is_active = 1''',
          variables: [
            Variable.withString(warehouseId),
            Variable.withString(organizationId),
            Variable.withString(branchId),
          ],
        )
        .get();
    if (rows.length != 1) {
      throw StateError('Warehouse location is no longer active.');
    }
  }
}
