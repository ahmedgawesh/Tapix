import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'offline_sync_event_store.dart';
import 'sync_entity_identity_store.dart';

/// Immutable synchronization contracts for supplier purchases and their linked
/// returns. Monetary snapshots and inventory identities are copied at posting
/// time so another branch never depends on mutable product or supplier cards.
class PurchaseSyncContractBuilder {
  const PurchaseSyncContractBuilder(this.db, this.identities);

  final AppDatabase db;
  final SyncEntityIdentityStore identities;

  Future<Map<String, Object?>> buildPostedPurchase({
    required Purchase purchase,
    required int? actorUserId,
  }) async {
    if (purchase.status != 'posted') {
      throw const OfflineSyncException(
        'purchase_not_posted',
        'Only a posted purchase can produce a synchronization event.',
      );
    }
    final location = await _location('purchases', purchase.id);
    final databaseId = await _localDatabaseId();
    _assertLocal(location, databaseId);

    final supplier = await identities.getOrCreateLocal(
      entityType: 'supplier',
      localId: purchase.supplierId,
    );
    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.id.equals(purchase.currencyId))).getSingle();
    final rows =
        await (db.select(db.purchaseItems)
              ..where((row) => row.purchaseId.equals(purchase.id))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    if (rows.isEmpty) {
      throw const OfflineSyncException(
        'purchase_items_missing',
        'A posted purchase must contain at least one item.',
      );
    }

    final items = <Map<String, Object?>>[];
    var subtotal = 0;
    var discount = 0;
    var tax = 0;
    var total = 0;
    var inventoryValue = 0;
    for (final item in rows) {
      subtotal += item.subtotalCents.toBigInt().toInt();
      discount += item.discountCents.toBigInt().toInt();
      tax += item.taxCents.toBigInt().toInt();
      total += item.totalCents.toBigInt().toInt();
      inventoryValue += item.inventoryValueAtPostCents?.toBigInt().toInt() ?? 0;
      final productRow = await (db.select(
        db.products,
      )..where((row) => row.id.equals(item.productId))).getSingle();
      final variantRow = item.variantId == null
          ? null
          : await (db.select(
              db.productVariants,
            )..where((row) => row.id.equals(item.variantId!))).getSingle();
      final product = await identities.getOrCreateLocal(
        entityType: 'product',
        localId: item.productId,
      );
      final variant = item.variantId == null
          ? null
          : await identities.getOrCreateLocal(
              entityType: 'product_variant',
              localId: item.variantId!,
            );
      final supplierIdentity = item.supplierIdentityId == null
          ? null
          : await identities.getOrCreateLocal(
              entityType: 'supplier_product_identity',
              localId: item.supplierIdentityId!,
            );
      final batches =
          await (db.select(db.productBatches)
                ..where((row) => row.purchaseItemId.equals(item.id))
                ..orderBy([(row) => OrderingTerm.asc(row.id)]))
              .get();
      final batchPayload = <Map<String, Object?>>[];
      for (final batch in batches) {
        final identity = await identities.getOrCreateLocal(
          entityType: 'product_batch',
          localId: batch.id,
        );
        batchPayload.add({
          'batchGlobalId': identity.globalId,
          'batchNumber': batch.batchNumber,
          'quantityScaled': batch.receivedQuantity,
          'unitCostMinor': batch.unitCostCents.toBigInt().toInt(),
          'manufacturerLotNumber': batch.manufacturerLotNumber,
          'expiryDate': batch.expiryDate?.toUtc().toIso8601String(),
        });
      }
      items.add({
        'lineRef': {'databaseId': databaseId, 'localId': item.id},
        'productGlobalId': product.globalId,
        'productName': productRow.name,
        'productSku': productRow.sku,
        'variantGlobalId': variant?.globalId,
        'variantName': variantRow?.sku,
        'variantSku': variantRow?.sku,
        'supplierIdentityGlobalId': supplierIdentity?.globalId,
        'quantityScaled': item.quantity,
        'quantityScale': item.quantityScale,
        'measurementType': item.measurementType,
        'tracksInventory': productRow.trackInventory,
        'unitCostMinor': item.unitCostCents.toBigInt().toInt(),
        'subtotalMinor': item.subtotalCents.toBigInt().toInt(),
        'discountMinor': item.discountCents.toBigInt().toInt(),
        'taxMinor': item.taxCents.toBigInt().toInt(),
        'totalMinor': item.totalCents.toBigInt().toInt(),
        'inventoryValueMinor':
            item.inventoryValueAtPostCents?.toBigInt().toInt() ?? 0,
        'manufacturerLotNumber': item.manufacturerLotNumber,
        'expiryDate': item.expiryDate?.toUtc().toIso8601String(),
        'batches': batchPayload,
      });
    }
    if (subtotal != purchase.subtotalCents.toBigInt().toInt() ||
        discount != purchase.discountCents.toBigInt().toInt() ||
        tax != purchase.taxCents.toBigInt().toInt() ||
        total != purchase.totalCents.toBigInt().toInt()) {
      throw const OfflineSyncException(
        'purchase_money_mismatch',
        'The purchase line amounts do not match the posted purchase.',
      );
    }

    final payments =
        await (db.select(db.purchasePayments)
              ..where((row) => row.purchaseId.equals(purchase.id))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    return {
      'contract': 'purchase.posted',
      'contractVersion': 1,
      'documentId': location.documentId,
      'sourceDocumentRef': {
        'databaseId': databaseId,
        'table': 'purchases',
        'localId': purchase.id,
      },
      'organizationId': location.organizationId,
      'branchId': location.branchId,
      'warehouseId': location.warehouseId,
      'purchaseNumber': purchase.purchaseNumber,
      'supplierInvoiceRef': purchase.supplierInvoiceRef,
      'purchaseDate': purchase.purchaseDate.toUtc().toIso8601String(),
      'dueDate': purchase.dueDate?.toUtc().toIso8601String(),
      'supplierGlobalId': supplier.globalId,
      'currencyCode': currency.code,
      'paymentMethod': purchase.paymentMethod,
      'subtotalMinor': purchase.subtotalCents.toBigInt().toInt(),
      'discountMinor': purchase.discountCents.toBigInt().toInt(),
      'taxMinor': purchase.taxCents.toBigInt().toInt(),
      'totalMinor': purchase.totalCents.toBigInt().toInt(),
      'paidMinor': purchase.paidAmountCents.toBigInt().toInt(),
      'inventoryValueMinor': inventoryValue,
      'pricing': {
        'engineVersion': purchase.pricingEngineVersion,
        'taxInclusive': purchase.taxInclusiveAtPost,
        'roundingMode': purchase.roundingModeAtPost,
      },
      'notes': purchase.notes,
      'actorRef': _actor(databaseId, actorUserId),
      'payments': [
        for (final payment in payments)
          {
            'paymentRef': {'databaseId': databaseId, 'localId': payment.id},
            'amountMinor': payment.amountCents.toBigInt().toInt(),
            'method': payment.paymentMethod,
            'reference': payment.reference,
            'paymentDate': payment.paymentDate.toUtc().toIso8601String(),
          },
      ],
      'itemCount': items.length,
      'items': items,
    };
  }

  Future<Map<String, Object?>> buildPostedLinkedReturn({
    required PurchaseReturn purchaseReturn,
    required int? actorUserId,
  }) async {
    if (purchaseReturn.status != 'posted') {
      throw const OfflineSyncException(
        'purchase_return_not_posted',
        'Only a posted purchase return can produce a synchronization event.',
      );
    }
    final location = await _location('purchase_returns', purchaseReturn.id);
    final sourceLocation = await _location(
      'purchases',
      purchaseReturn.purchaseId,
    );
    final databaseId = await _localDatabaseId();
    _assertLocal(location, databaseId);
    _assertLocal(sourceLocation, databaseId);
    final purchase = await (db.select(
      db.purchases,
    )..where((row) => row.id.equals(purchaseReturn.purchaseId))).getSingle();
    final supplier = await identities.getOrCreateLocal(
      entityType: 'supplier',
      localId: purchase.supplierId,
    );
    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.id.equals(purchaseReturn.currencyId))).getSingle();
    final rows =
        await (db.select(db.purchaseReturnItems)
              ..where((row) => row.returnId.equals(purchaseReturn.id))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    if (rows.isEmpty) {
      throw const OfflineSyncException(
        'purchase_return_items_missing',
        'A posted purchase return must contain at least one item.',
      );
    }

    final items = <Map<String, Object?>>[];
    var subtotal = 0;
    var discount = 0;
    var tax = 0;
    var total = 0;
    var inventoryValue = 0;
    for (final item in rows) {
      final purchaseItem = await (db.select(
        db.purchaseItems,
      )..where((row) => row.id.equals(item.purchaseItemId))).getSingle();
      final productRow = await (db.select(
        db.products,
      )..where((row) => row.id.equals(purchaseItem.productId))).getSingle();
      final product = await identities.getOrCreateLocal(
        entityType: 'product',
        localId: purchaseItem.productId,
      );
      final variant = purchaseItem.variantId == null
          ? null
          : await identities.getOrCreateLocal(
              entityType: 'product_variant',
              localId: purchaseItem.variantId!,
            );
      subtotal += item.subtotalCents.toBigInt().toInt();
      discount += item.discountCents.toBigInt().toInt();
      tax += item.taxCents.toBigInt().toInt();
      total += item.refundCents.toBigInt().toInt();
      inventoryValue += item.inventoryValueAtPostCents?.toBigInt().toInt() ?? 0;
      items.add({
        'lineRef': {'databaseId': databaseId, 'localId': item.id},
        'sourcePurchaseLineRef': {
          'databaseId': databaseId,
          'localId': item.purchaseItemId,
        },
        'productGlobalId': product.globalId,
        'variantGlobalId': variant?.globalId,
        'quantityScaled': item.quantity,
        'quantityScale': item.quantityScale,
        'measurementType': item.measurementType,
        'tracksInventory': productRow.trackInventory,
        'subtotalMinor': item.subtotalCents.toBigInt().toInt(),
        'discountMinor': item.discountCents.toBigInt().toInt(),
        'taxMinor': item.taxCents.toBigInt().toInt(),
        'refundMinor': item.refundCents.toBigInt().toInt(),
        'unitCostMinor': item.unitCostAtPostCents?.toBigInt().toInt(),
        'inventoryValueMinor':
            item.inventoryValueAtPostCents?.toBigInt().toInt() ?? 0,
        'reason': item.reason,
      });
    }
    if (subtotal != purchaseReturn.subtotalCents.toBigInt().toInt() ||
        discount != purchaseReturn.discountCents.toBigInt().toInt() ||
        tax != purchaseReturn.taxCents.toBigInt().toInt() ||
        total != purchaseReturn.totalCents.toBigInt().toInt()) {
      throw const OfflineSyncException(
        'purchase_return_money_mismatch',
        'The purchase-return lines do not match the posted return.',
      );
    }
    return {
      'contract': 'purchase_return.posted',
      'contractVersion': 1,
      'documentId': location.documentId,
      'sourceDocumentRef': {
        'databaseId': databaseId,
        'table': 'purchase_returns',
        'localId': purchaseReturn.id,
      },
      'originalPurchaseDocumentId': sourceLocation.documentId,
      'originalPurchaseRef': {
        'databaseId': databaseId,
        'table': 'purchases',
        'localId': purchaseReturn.purchaseId,
      },
      'organizationId': location.organizationId,
      'branchId': location.branchId,
      'warehouseId': location.warehouseId,
      'returnNumber': purchaseReturn.returnNumber,
      'returnDate': purchaseReturn.returnDate.toUtc().toIso8601String(),
      'dueDate': purchaseReturn.dueDate?.toUtc().toIso8601String(),
      'supplierGlobalId': supplier.globalId,
      'currencyCode': currency.code,
      'refundMethod': purchaseReturn.refundMethod,
      'dispositionType': purchaseReturn.dispositionType,
      'subtotalMinor': purchaseReturn.subtotalCents.toBigInt().toInt(),
      'discountMinor': purchaseReturn.discountCents.toBigInt().toInt(),
      'taxMinor': purchaseReturn.taxCents.toBigInt().toInt(),
      'totalMinor': purchaseReturn.totalCents.toBigInt().toInt(),
      'inventoryValueMinor': inventoryValue,
      'pricing': {
        'engineVersion': purchaseReturn.pricingEngineVersion,
        'taxInclusive': purchaseReturn.taxInclusiveAtPost,
        'roundingMode': purchaseReturn.roundingModeAtPost,
      },
      'reason': purchaseReturn.reason,
      'actorRef': _actor(databaseId, actorUserId),
      'itemCount': items.length,
      'items': items,
    };
  }

  Future<Map<String, Object?>> buildVoidedPurchase({
    required Purchase purchase,
    required int? actorUserId,
    required DateTime voidedAt,
    String reason = 'voided',
  }) {
    if (purchase.status != 'voided') {
      throw const OfflineSyncException(
        'purchase_not_voided',
        'Only a voided purchase can produce a void event.',
      );
    }
    return _voidPayload(
      sourceTable: 'purchases',
      localId: purchase.id,
      numberKey: 'purchaseNumber',
      number: purchase.purchaseNumber,
      contract: 'purchase.voided',
      actorUserId: actorUserId,
      voidedAt: voidedAt,
      reason: reason,
    );
  }

  Future<Map<String, Object?>> buildVoidedLinkedReturn({
    required PurchaseReturn purchaseReturn,
    required int? actorUserId,
    required DateTime voidedAt,
    String reason = 'voided',
  }) async {
    if (purchaseReturn.status != 'voided') {
      throw const OfflineSyncException(
        'purchase_return_not_voided',
        'Only a voided purchase return can produce a void event.',
      );
    }
    final payload = await _voidPayload(
      sourceTable: 'purchase_returns',
      localId: purchaseReturn.id,
      numberKey: 'returnNumber',
      number: purchaseReturn.returnNumber,
      contract: 'purchase_return.voided',
      actorUserId: actorUserId,
      voidedAt: voidedAt,
      reason: reason,
    );
    final source = await _location('purchases', purchaseReturn.purchaseId);
    payload['originalPurchaseDocumentId'] = source.documentId;
    payload['originalPurchaseRef'] = {
      'databaseId': await _localDatabaseId(),
      'table': 'purchases',
      'localId': purchaseReturn.purchaseId,
    };
    return payload;
  }

  Future<Map<String, Object?>> _voidPayload({
    required String sourceTable,
    required int localId,
    required String numberKey,
    required String number,
    required String contract,
    required int? actorUserId,
    required DateTime voidedAt,
    required String reason,
  }) async {
    final location = await _location(sourceTable, localId);
    final databaseId = await _localDatabaseId();
    _assertLocal(location, databaseId);
    return {
      'contract': contract,
      'contractVersion': 1,
      'documentId': location.documentId,
      'sourceDocumentRef': {
        'databaseId': databaseId,
        'table': sourceTable,
        'localId': localId,
      },
      'organizationId': location.organizationId,
      'branchId': location.branchId,
      'warehouseId': location.warehouseId,
      numberKey: number,
      'voidedAt': voidedAt.toUtc().toIso8601String(),
      'reason': reason,
      'actorRef': _actor(databaseId, actorUserId),
    };
  }

  Map<String, Object?>? _actor(String databaseId, int? actorUserId) =>
      actorUserId == null
      ? null
      : {'databaseId': databaseId, 'localId': actorUserId};

  void _assertLocal(_PurchaseLocation location, String databaseId) {
    if (location.originDatabaseId != databaseId) {
      throw const OfflineSyncException(
        'purchase_database_identity_mismatch',
        'The purchase document belongs to another source database.',
      );
    }
  }

  Future<_PurchaseLocation> _location(String table, int id) async {
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
        'purchase_location_missing',
        'The posted purchase document has no immutable business location.',
      );
    }
    return _PurchaseLocation(
      documentId: row.read<String>('document_id'),
      organizationId: row.read<String>('organization_id'),
      branchId: row.read<String>('branch_id'),
      warehouseId: row.read<String>('warehouse_id'),
      originDatabaseId: row.read<String>('origin_database_id'),
    );
  }

  Future<String> _localDatabaseId() => db
      .customSelect('SELECT database_id FROM sync_local_state WHERE id=1')
      .map((row) => row.read<String>('database_id'))
      .getSingle();
}

class _PurchaseLocation {
  const _PurchaseLocation({
    required this.documentId,
    required this.organizationId,
    required this.branchId,
    required this.warehouseId,
    required this.originDatabaseId,
  });

  final String documentId;
  final String organizationId;
  final String branchId;
  final String warehouseId;
  final String originDatabaseId;
}
