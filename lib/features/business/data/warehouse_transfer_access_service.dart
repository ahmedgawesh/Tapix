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

  Future<int> _activeOwner() async {
    if (_isRemoteClient()) throw const WarehouseTransferAccessDenied();
    final id = await _session.getCurrentUserId();
    if (id == null) throw const WarehouseTransferAccessDenied();
    final user = await (_db.select(
      _db.users,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    if (user == null || user.isActive != 1 || user.role != 'owner') {
      throw const WarehouseTransferAccessDenied();
    }
    return id;
  }

  Future<WarehouseOperationScope> _allowedScope(String warehouseId) async {
    final primary = await WarehouseOperationScope.resolve(_db);
    final scope = await WarehouseOperationScope.resolve(
      _db,
      warehouseId: warehouseId,
    );
    await scope.validate(_db);
    if (scope.organizationId != primary.organizationId ||
        scope.branchId != primary.branchId ||
        scope.databaseId != primary.databaseId ||
        !await _entitlement.permits(scope)) {
      throw const WarehouseTransferAccessDenied();
    }
    return scope;
  }

  Future<void> authorizeWarehouse(String warehouseId) async {
    await _activeOwner();
    await _allowedScope(warehouseId);
  }

  Future<int> authorize(
    TransferDraftAction action,
    String sourceWarehouseId,
    String destinationWarehouseId,
  ) async {
    final actor = await _activeOwner();
    final source = await _allowedScope(sourceWarehouseId);
    final destination = await _allowedScope(destinationWarehouseId);
    if (source.warehouseId == destination.warehouseId ||
        source.organizationId != destination.organizationId ||
        source.branchId != destination.branchId ||
        source.databaseId != destination.databaseId) {
      throw const WarehouseTransferAccessDenied();
    }
    return actor;
  }

  Future<List<WarehouseTransferCatalogItem>> catalog(
    String warehouseId, {
    String query = '',
    int offset = 0,
  }) => _db.transaction(() async {
    await _activeOwner();
    await _allowedScope(warehouseId);
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

  Future<List<BusinessWarehouse>> warehouses() => _db.transaction(() async {
    await _activeOwner();
    final primary = await WarehouseOperationScope.resolve(_db);
    final rows =
        await (_db.select(_db.businessWarehouses)
              ..where(
                (row) =>
                    row.organizationId.equals(primary.organizationId) &
                    row.branchId.equals(primary.branchId) &
                    row.isActive.equals(true),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.code)]))
            .get();
    final allowed = <BusinessWarehouse>[];
    for (final row in rows) {
      try {
        await _allowedScope(row.id);
        allowed.add(row);
      } on WarehouseTransferAccessDenied {
        // Do not reveal a warehouse outside the active entitlement/scope.
      }
    }
    return List.unmodifiable(allowed);
  });
}
