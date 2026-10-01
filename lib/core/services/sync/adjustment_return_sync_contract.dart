import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'offline_sync_event_store.dart';
import 'sync_entity_identity_store.dart';

class AdjustmentReturnSyncContractBuilder {
  const AdjustmentReturnSyncContractBuilder(this.db, this.identities);

  final AppDatabase db;
  final SyncEntityIdentityStore identities;

  Future<Map<String, Object?>> buildPostedSale({
    required SaleReturnAdjustment header,
  }) async {
    if (header.status != 'posted') {
      throw const OfflineSyncException(
        'sale_adjustment_return_not_posted',
        'Only a posted sale adjustment return can be synchronized.',
      );
    }
    final common = await _common(
      table: 'sale_return_adjustments',
      id: header.id,
      contract: 'sale_adjustment_return.posted',
      number: header.returnNumber,
      returnDate: header.returnDate,
      currencyId: header.currencyId,
      subtotalMinor: header.subtotalCents.toBigInt().toInt(),
      discountMinor: header.discountCents.toBigInt().toInt(),
      taxMinor: header.taxCents.toBigInt().toInt(),
      totalMinor: header.totalCents.toBigInt().toInt(),
      refundMethod: header.refundMethod,
      mode: header.returnMode,
      modeReason: header.modeReason,
      notes: header.notes,
      actorUserId: header.postedBy,
    );
    final customer = header.customerId == null
        ? null
        : await identities.getOrCreateLocal(
            entityType: 'customer',
            localId: header.customerId!,
          );
    common['employee'] = await _employeeSnapshot(header.employeeId);
    common['commissions'] = await _adjustmentCommissionSnapshots(header.id);
    final rows =
        await (db.select(db.saleReturnAdjustmentItems)
              ..where((row) => row.returnId.equals(header.id))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    common['customerGlobalId'] = customer?.globalId;
    common['pricing'] = {
      'engineVersion': header.pricingEngineVersion,
      'taxInclusive': header.taxInclusiveAtPost,
      'roundingMode': header.roundingModeAtPost,
    };
    common['items'] = [for (final item in rows) await _saleItem(item)];
    common['itemCount'] = rows.length;
    _assertTotals(
      common,
      rows.fold(0, (sum, item) => sum + item.totalCents.toBigInt().toInt()),
    );
    return common;
  }

  Future<Map<String, Object?>> buildPostedPurchase({
    required PurchaseReturnAdjustment header,
  }) async {
    if (header.status != 'posted') {
      throw const OfflineSyncException(
        'purchase_adjustment_return_not_posted',
        'Only a posted purchase adjustment return can be synchronized.',
      );
    }
    final common = await _common(
      table: 'purchase_return_adjustments',
      id: header.id,
      contract: 'purchase_adjustment_return.posted',
      number: header.returnNumber,
      returnDate: header.returnDate,
      currencyId: header.currencyId,
      subtotalMinor: header.subtotalCents.toBigInt().toInt(),
      discountMinor: header.discountCents.toBigInt().toInt(),
      taxMinor: header.taxCents.toBigInt().toInt(),
      totalMinor: header.totalCents.toBigInt().toInt(),
      refundMethod: header.refundMethod,
      mode: header.returnMode,
      modeReason: header.modeReason,
      notes: header.notes,
      actorUserId: header.postedBy,
    );
    final supplier = await identities.getOrCreateLocal(
      entityType: 'supplier',
      localId: header.supplierId,
    );
    final rows =
        await (db.select(db.purchaseReturnAdjustmentItems)
              ..where((row) => row.returnId.equals(header.id))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    common['supplierGlobalId'] = supplier.globalId;
    common['pricing'] = {
      'engineVersion': header.pricingEngineVersion,
      'taxInclusive': header.taxInclusiveAtPost,
      'roundingMode': header.roundingModeAtPost,
    };
    common['items'] = [for (final item in rows) await _purchaseItem(item)];
    common['itemCount'] = rows.length;
    _assertTotals(
      common,
      rows.fold(0, (sum, item) => sum + item.totalCents.toBigInt().toInt()),
    );
    return common;
  }

  Future<Map<String, Object?>> buildVoidedSale({
    required SaleReturnAdjustment header,
  }) => _voided(
    table: 'sale_return_adjustments',
    id: header.id,
    contract: 'sale_adjustment_return.voided',
    number: header.returnNumber,
    actorUserId: header.voidedBy,
    voidedAt: header.voidedAt,
    reason: header.voidReason,
  );

  Future<Map<String, Object?>> buildVoidedPurchase({
    required PurchaseReturnAdjustment header,
  }) => _voided(
    table: 'purchase_return_adjustments',
    id: header.id,
    contract: 'purchase_adjustment_return.voided',
    number: header.returnNumber,
    actorUserId: header.voidedBy,
    voidedAt: header.voidedAt,
    reason: header.voidReason,
  );

  Future<Map<String, Object?>> _saleItem(SaleReturnAdjustmentItem item) async {
    final base = await _itemBase(
      id: item.id,
      productId: item.productId,
      variantId: item.variantId,
      quantity: item.quantity,
      quantityScale: item.quantityScale,
      measurementType: item.measurementType,
      unitPriceMinor: item.unitPriceCents.toBigInt().toInt(),
      unitCostMinor:
          item.unitCostAtPostCents?.toBigInt().toInt() ??
          item.unitCostCents.toBigInt().toInt(),
      discountMinor: item.discountCents.toBigInt().toInt(),
      taxMinor: item.taxCents.toBigInt().toInt(),
      totalMinor: item.totalCents.toBigInt().toInt(),
      inventoryValueMinor:
          item.inventoryValueAtPostCents?.toBigInt().toInt() ?? 0,
      dispositionType: item.dispositionType,
      reason: item.reason,
    );
    final supplierIdentity = item.supplierIdentityId == null
        ? null
        : await identities.getOrCreateLocal(
            entityType: 'supplier_product_identity',
            localId: item.supplierIdentityId!,
          );
    String? consignmentSupplierGlobalId;
    if (item.consignmentLayerId != null) {
      final layer =
          await (db.select(db.consignmentInventoryLayers)
                ..where((row) => row.id.equals(item.consignmentLayerId!)))
              .getSingleOrNull();
      if (layer != null) {
        consignmentSupplierGlobalId = (await identities.getOrCreateLocal(
          entityType: 'supplier',
          localId: layer.supplierId,
        )).globalId;
      }
    }
    base.addAll({
      'sourceResolution': item.sourceResolution,
      'sourceResolutionReason': item.sourceResolutionReason,
      'sourceResolvedAt': item.sourceResolvedAt?.toUtc().toIso8601String(),
      'supplierIdentityGlobalId': supplierIdentity?.globalId,
      'consignmentLayerId': item.consignmentLayerId,
      'consignmentSupplierGlobalId': consignmentSupplierGlobalId,
      'returnBatchGlobalId': item.returnBatchId == null
          ? null
          : (await identities.getOrCreateLocal(
              entityType: 'product_batch',
              localId: item.returnBatchId!,
            )).globalId,
      'originalInvoiceRef': item.originalInvoiceId == null
          ? null
          : {
              'databaseId': await _databaseId(),
              'table': 'sales',
              'localId': item.originalInvoiceId,
            },
    });
    return base;
  }

  Future<Map<String, Object?>?> _employeeSnapshot(int? employeeId) async {
    if (employeeId == null) return null;
    final employee = await (db.select(
      db.employees,
    )..where((row) => row.id.equals(employeeId))).getSingleOrNull();
    if (employee == null) return null;
    return {
      'localId': employee.id,
      'name': employee.name,
      'position': employee.position,
      'department': employee.department,
      'defaultCommissionRateBps': employee.defaultCommissionRateBps,
    };
  }

  Future<List<Map<String, Object?>>> _adjustmentCommissionSnapshots(
    int returnId,
  ) async {
    final rows =
        await (db.select(db.commissions)
              ..where((row) => row.saleReturnAdjustmentId.equals(returnId))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    return [
      for (final commission in rows)
        {
          'localId': commission.id,
          'employeeId': commission.employeeId,
          // The legacy Drift converter exposes this INTEGER basis-point
          // column as a double. Sync payloads use scaled integers only.
          'rateBps': _integerCommissionRateBps(commission.commissionRateBps),
          'amountMinor': commission.commissionAmountCents.toBigInt().toInt(),
          'status': commission.status,
          'effectiveDate': commission.effectiveDate?.toUtc().toIso8601String(),
        },
    ];
  }

  int _integerCommissionRateBps(double value) {
    if (!value.isFinite || value != value.roundToDouble()) {
      throw const OfflineSyncException(
        'invalid_commission_rate',
        'A commission rate must be stored as a whole number of basis points.',
      );
    }
    return value.toInt();
  }

  Future<Map<String, Object?>> _purchaseItem(
    PurchaseReturnAdjustmentItem item,
  ) async {
    final base = await _itemBase(
      id: item.id,
      productId: item.productId,
      variantId: item.variantId,
      quantity: item.quantity,
      quantityScale: item.quantityScale,
      measurementType: item.measurementType,
      unitPriceMinor: item.unitPriceCents.toBigInt().toInt(),
      unitCostMinor:
          item.unitCostAtPostCents?.toBigInt().toInt() ??
          item.unitCostCents.toBigInt().toInt(),
      discountMinor: item.discountCents.toBigInt().toInt(),
      taxMinor: item.taxCents.toBigInt().toInt(),
      totalMinor: item.totalCents.toBigInt().toInt(),
      inventoryValueMinor:
          item.inventoryValueAtPostCents?.toBigInt().toInt() ?? 0,
      dispositionType: item.dispositionType,
      reason: item.reason,
    );
    base['originalInvoiceRef'] = item.originalInvoiceId == null
        ? null
        : {
            'databaseId': await _databaseId(),
            'table': 'purchases',
            'localId': item.originalInvoiceId,
          };
    return base;
  }

  Future<Map<String, Object?>> _itemBase({
    required int id,
    required int productId,
    required int? variantId,
    required int quantity,
    required int quantityScale,
    required String measurementType,
    required int unitPriceMinor,
    required int unitCostMinor,
    required int discountMinor,
    required int taxMinor,
    required int totalMinor,
    required int inventoryValueMinor,
    required String dispositionType,
    required String? reason,
  }) async {
    final databaseId = await _databaseId();
    final productRow = await (db.select(
      db.products,
    )..where((row) => row.id.equals(productId))).getSingle();
    final product = await identities.getOrCreateLocal(
      entityType: 'product',
      localId: productId,
    );
    final variant = variantId == null
        ? null
        : await identities.getOrCreateLocal(
            entityType: 'product_variant',
            localId: variantId,
          );
    return {
      'lineRef': {'databaseId': databaseId, 'localId': id},
      'productGlobalId': product.globalId,
      'variantGlobalId': variant?.globalId,
      'quantityScaled': quantity,
      'quantityScale': quantityScale,
      'measurementType': measurementType,
      'tracksInventory': productRow.trackInventory,
      'unitPriceMinor': unitPriceMinor,
      'unitCostMinor': unitCostMinor,
      'discountMinor': discountMinor,
      'taxMinor': taxMinor,
      'totalMinor': totalMinor,
      'inventoryValueMinor': inventoryValueMinor,
      'dispositionType': dispositionType,
      'reason': reason,
    };
  }

  Future<Map<String, Object?>> _common({
    required String table,
    required int id,
    required String contract,
    required String number,
    required DateTime returnDate,
    required int currencyId,
    required int subtotalMinor,
    required int discountMinor,
    required int taxMinor,
    required int totalMinor,
    required String refundMethod,
    required String? mode,
    required String? modeReason,
    required String? notes,
    required int? actorUserId,
  }) async {
    final location = await _location(table, id);
    final databaseId = await _databaseId();
    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.id.equals(currencyId))).getSingle();
    return {
      'contract': contract,
      'contractVersion': 1,
      'documentId': location.documentId,
      'sourceDocumentRef': {
        'databaseId': databaseId,
        'table': table,
        'localId': id,
      },
      'organizationId': location.organizationId,
      'branchId': location.branchId,
      'warehouseId': location.warehouseId,
      'returnNumber': number,
      'returnDate': returnDate.toUtc().toIso8601String(),
      'currencyCode': currency.code,
      'refundMethod': refundMethod,
      'returnMode': mode,
      'modeReason': modeReason,
      'notes': notes,
      'subtotalMinor': subtotalMinor,
      'discountMinor': discountMinor,
      'taxMinor': taxMinor,
      'totalMinor': totalMinor,
      'actorRef': actorUserId == null
          ? null
          : {'databaseId': databaseId, 'localId': actorUserId},
    };
  }

  Future<Map<String, Object?>> _voided({
    required String table,
    required int id,
    required String contract,
    required String number,
    required int? actorUserId,
    required DateTime? voidedAt,
    required String? reason,
  }) async {
    if (voidedAt == null) {
      throw const OfflineSyncException(
        'adjustment_return_void_metadata_missing',
        'A voided adjustment return must record its void time.',
      );
    }
    final location = await _location(table, id);
    final databaseId = await _databaseId();
    return {
      'contract': contract,
      'contractVersion': 1,
      'documentId': location.documentId,
      'sourceDocumentRef': {
        'databaseId': databaseId,
        'table': table,
        'localId': id,
      },
      'organizationId': location.organizationId,
      'branchId': location.branchId,
      'warehouseId': location.warehouseId,
      'returnNumber': number,
      'voidedAt': voidedAt.toUtc().toIso8601String(),
      'reason': reason,
      'actorRef': actorUserId == null
          ? null
          : {'databaseId': databaseId, 'localId': actorUserId},
    };
  }

  void _assertTotals(Map<String, Object?> payload, int itemTotal) {
    if (itemTotal != payload['totalMinor']) {
      throw const OfflineSyncException(
        'adjustment_return_money_mismatch',
        'The adjustment-return lines do not match the header total.',
      );
    }
  }

  Future<_AdjustmentReturnLocation> _location(String table, int id) async {
    final row = await db
        .customSelect(
          'SELECT document_id,organization_id,branch_id,warehouse_id,'
          'origin_database_id FROM business_document_locations '
          'WHERE source_table=? AND source_id=?',
          variables: [Variable.withString(table), Variable.withInt(id)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw const OfflineSyncException(
        'adjustment_return_location_missing',
        'The adjustment return has no immutable business location.',
      );
    }
    final databaseId = await _databaseId();
    if (row.read<String>('origin_database_id') != databaseId) {
      throw const OfflineSyncException(
        'adjustment_return_database_identity_mismatch',
        'The adjustment return belongs to another source database.',
      );
    }
    return _AdjustmentReturnLocation(
      documentId: row.read<String>('document_id'),
      organizationId: row.read<String>('organization_id'),
      branchId: row.read<String>('branch_id'),
      warehouseId: row.read<String>('warehouse_id'),
    );
  }

  Future<String> _databaseId() => db
      .customSelect('SELECT database_id FROM sync_local_state WHERE id=1')
      .map((row) => row.read<String>('database_id'))
      .getSingle();
}

class _AdjustmentReturnLocation {
  const _AdjustmentReturnLocation({
    required this.documentId,
    required this.organizationId,
    required this.branchId,
    required this.warehouseId,
  });

  final String documentId;
  final String organizationId;
  final String branchId;
  final String warehouseId;
}
