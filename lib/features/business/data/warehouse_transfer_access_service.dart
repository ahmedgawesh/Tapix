import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../auth/data/services/session_service.dart';
import 'warehouse_setup_service.dart';
import 'warehouse_transfer_repository.dart';

class WarehouseTransferCatalogItem {
  const WarehouseTransferCatalogItem({
    required this.productId,
    required this.variantId,
    required this.name,
    required this.code,
    required this.quantity,
    required this.supplierOwnedQuantity,
    required this.quantityScale,
    required this.measurementType,
  });

  final int productId;
  final int variantId;
  final String name;
  final String code;
  final int quantity;
  final int supplierOwnedQuantity;
  final int quantityScale;
  final String measurementType;

  int get ownedQuantity => quantity - supplierOwnedQuantity;

  int parseQuantity(String input) {
    var text = input.trim().replaceAll('٫', '.').replaceAll(',', '.');
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    const persian = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < 10; i++) {
      text = text.replaceAll(arabic[i], '$i').replaceAll(persian[i], '$i');
    }
    if (text.length > 40 || !RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) {
      throw const FormatException('Invalid transfer quantity');
    }
    final parts = text.split('.');
    final fraction = parts.length == 2 ? parts[1] : '';
    final digits = quantityScale == 1 ? 0 : 3;
    if (fraction.length > digits) {
      throw const FormatException('Transfer quantity precision');
    }
    final amount = BigInt.parse(parts[0] + fraction.padRight(digits, '0'));
    if (amount <= BigInt.zero || amount > BigInt.from(quantity)) {
      throw const FormatException('Transfer quantity is unavailable');
    }
    return amount.toInt();
  }
}

class WarehouseTransferAccessLocation {
  const WarehouseTransferAccessLocation({
    required this.warehouse,
    required this.branchName,
  });

  final BusinessWarehouse warehouse;
  final String branchName;
}

class WarehouseTransferAccessDenied implements Exception {
  const WarehouseTransferAccessDenied();
}

/// One production authorization boundary for every local transfer operation.
///
/// Local multi-warehouse transfers are part of the existing Pro entitlement.
/// A LAN replica must call its host API instead of writing the replicated
/// database directly. Online branch transfers use a separate entitlement and
/// are intentionally outside this local-branch service.
class WarehouseTransferAccessService {
  const WarehouseTransferAccessService(
    this._db,
    this._session,
    this._entitlement, {
    required bool Function() isRemoteClient,
  }) : _isRemoteClient = isRemoteClient;

  final AppDatabase _db;
  final SessionService _session;
  final WarehouseSetupEntitlement _entitlement;
  final bool Function() _isRemoteClient;

  Future<User> _activeOperator() async {
    if (_isRemoteClient()) throw const WarehouseTransferAccessDenied();
    final id = await _session.getCurrentUserId();
    if (id == null) throw const WarehouseTransferAccessDenied();
    final user = await (_db.select(
      _db.users,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (user == null ||
        user.isActive != 1 ||
        !const {'owner', 'manager', 'warehouseClerk'}.contains(user.role)) {
      throw const WarehouseTransferAccessDenied();
    }
    return user;
  }

  void _requireUserScope(User user, WarehouseOperationScope scope) {
    final legacyOwner =
        user.role == 'owner' &&
        user.branchId == null &&
        user.warehouseId == null;
    if (user.globalLocationAccess || legacyOwner) return;
    if (user.branchId != scope.branchId) {
      throw const WarehouseTransferAccessDenied();
    }
    if (user.role == 'warehouseClerk' &&
        user.warehouseId != scope.warehouseId) {
      throw const WarehouseTransferAccessDenied();
    }
    if (user.warehouseId != null && user.warehouseId != scope.warehouseId) {
      throw const WarehouseTransferAccessDenied();
    }
  }

  Future<WarehouseOperationScope> _allowedScope(String warehouseId) async {
    final primary = await WarehouseOperationScope.resolve(_db);
    final scope = await WarehouseOperationScope.resolveForOrganization(
      _db,
      warehouseId: warehouseId,
    );
    await scope.validate(_db);
    if (scope.organizationId != primary.organizationId ||
        scope.databaseId != primary.databaseId ||
        !await _entitlement.permits(scope)) {
      throw const WarehouseTransferAccessDenied();
    }
    return scope;
  }

  Future<void> authorizeWarehouse(String warehouseId) async {
    final user = await _activeOperator();
    final scope = await _allowedScope(warehouseId);
    _requireUserScope(user, scope);
  }

  /// Authorizes a document owned by one local warehouse and returns the
  /// immutable actor id that must be recorded on that document.
  Future<int> authorizeInboundWarehouse(String warehouseId) async {
    final user = await _activeOperator();
    final scope = await _allowedScope(warehouseId);
    _requireUserScope(user, scope);
    return user.id;
  }

  /// Authorizes an outbound document whose source stock is local while the
  /// destination is a routing identity owned by another enrolled branch.
  Future<int> authorizeDistributedOutbound(
    String sourceWarehouseId,
    String destinationWarehouseId,
  ) async {
    final user = await _activeOperator();
    final source = await _allowedScope(sourceWarehouseId);
    _requireUserScope(user, source);
    final target = await _db
        .customSelect(
          '''SELECT w.organization_id,w.branch_id,b.writer_database_id
          FROM sync_warehouse_directory w
          JOIN sync_branch_directory b ON b.branch_id=w.branch_id
          WHERE w.warehouse_id=? AND w.is_active=1 AND b.is_active=1''',
          variables: [Variable.withString(destinationWarehouseId)],
        )
        .getSingleOrNull();
    if (target == null ||
        target.read<String>('organization_id') != source.organizationId ||
        target.read<String>('branch_id') == source.branchId ||
        target.readNullable<String>('writer_database_id') == null ||
        target.read<String>('writer_database_id') == source.databaseId) {
      throw const WarehouseTransferAccessDenied();
    }
    return user.id;
  }

  Future<int> authorize(
    TransferDraftAction action,
    String sourceWarehouseId,
    String destinationWarehouseId,
  ) async {
    final user = await _activeOperator();
    final source = await _allowedScope(sourceWarehouseId);
    final destination = await _allowedScope(destinationWarehouseId);
    if (source.warehouseId == destination.warehouseId ||
        source.organizationId != destination.organizationId ||
        source.databaseId != destination.databaseId) {
      throw const WarehouseTransferAccessDenied();
    }
    if (action == TransferDraftAction.read) {
      try {
        _requireUserScope(user, source);
      } on WarehouseTransferAccessDenied {
        _requireUserScope(user, destination);
      }
    } else {
      _requireUserScope(
        user,
        action == TransferDraftAction.receive ? destination : source,
      );
    }
    return user.id;
  }

  Future<List<WarehouseTransferCatalogItem>> catalog(
    String warehouseId, {
    String query = '',
    int offset = 0,
  }) => _db.transaction(() async {
    final user = await _activeOperator();
    final scope = await _allowedScope(warehouseId);
    _requireUserScope(user, scope);
    if (offset < 0) throw ArgumentError.value(offset, 'offset');
    final search = query.trim();
    final rows = await _db
        .customSelect(
          '''SELECT p.id AS product_id, v.id AS variant_id, p.name,
        COALESCE(v.sku, v.barcode, p.sku, p.barcode, '') AS code,
        s.quantity, s.supplier_owned_quantity, p.measurement_type
      FROM business_warehouse_stocks s
      JOIN product_variants v ON v.id=s.variant_id
      JOIN products p ON p.id=v.product_id
      WHERE s.warehouse_id=? AND s.quantity>0
        AND v.is_active=1 AND p.is_active=1 AND p.track_inventory=1
        AND (instr(lower(p.name),lower(?))>0
          OR instr(lower(COALESCE(v.sku,'')),lower(?))>0
          OR instr(lower(COALESCE(v.barcode,'')),lower(?))>0
          OR instr(lower(COALESCE(p.sku,'')),lower(?))>0
          OR instr(lower(COALESCE(p.barcode,'')),lower(?))>0)
      ORDER BY p.name,v.id LIMIT 50 OFFSET ?''',
          variables: [
            Variable.withString(warehouseId),
            for (var i = 0; i < 5; i++) Variable.withString(search),
            Variable.withInt(offset),
          ],
        )
        .get();
    return List.unmodifiable(
      rows.map(
        (row) => WarehouseTransferCatalogItem(
          productId: row.read<int>('product_id'),
          variantId: row.read<int>('variant_id'),
          name: row.read<String>('name'),
          code: row.read<String>('code'),
          quantity: row.read<int>('quantity'),
          supplierOwnedQuantity: row.read<int>('supplier_owned_quantity'),
          quantityScale: row.read<String>('measurement_type') == 'piece'
              ? 1
              : 1000,
          measurementType: row.read<String>('measurement_type'),
        ),
      ),
    );
  });

  Future<List<WarehouseTransferAccessLocation>> warehouses() =>
      _db.transaction(() async {
        await _activeOperator();
        final primary = await WarehouseOperationScope.resolve(_db);
        final rows = await _db
            .customSelect(
              '''SELECT w.*, b.name AS branch_name, b.code AS branch_code
              FROM business_warehouses w
              JOIN business_branches b ON b.id=w.branch_id
                AND b.organization_id=w.organization_id
              WHERE w.organization_id=? AND w.is_active=1 AND b.is_active=1
              ORDER BY b.created_at,b.code,
                CASE WHEN w.location_kind='branch_store' THEN 0 ELSE 1 END,
                w.created_at,w.code''',
              variables: [Variable.withString(primary.organizationId)],
              readsFrom: {_db.businessWarehouses, _db.businessBranches},
            )
            .get();
        final allowed = <WarehouseTransferAccessLocation>[];
        for (final row in rows) {
          final warehouse = _db.businessWarehouses.map(row.data);
          try {
            await _allowedScope(warehouse.id);
            final branchName = row.read<String>('branch_name').trim();
            allowed.add(
              WarehouseTransferAccessLocation(
                warehouse: warehouse,
                branchName: branchName.isEmpty
                    ? row.read<String>('branch_code')
                    : branchName,
              ),
            );
          } on WarehouseTransferAccessDenied {
            // Do not reveal a location outside the active entitlement/scope.
          }
        }
        return List.unmodifiable(allowed);
      });
}
