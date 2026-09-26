import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'offline_sync_event_store.dart';
import 'sync_entity_identity_store.dart';

/// Builds the immutable, transport-safe contract for a posted transfer
/// dispatch. Integer SQLite identifiers never cross a database without their
/// source database identity; master data and inventory layers use global IDs.
class WarehouseTransferSyncContractBuilder {
  const WarehouseTransferSyncContractBuilder(this.db, this.identities);

  final AppDatabase db;
  final SyncEntityIdentityStore identities;

  Future<Map<String, Object?>> buildDispatch({
    required WarehouseTransfer transfer,
    required WarehouseTransferDispatch dispatch,
    required List<WarehouseTransferAllocation> allocations,
  }) async {
    if (!dispatch.sealed || dispatch.transferId != transfer.id) {
      throw const OfflineSyncException(
        'unsealed_transfer_dispatch',
        'Only a sealed transfer dispatch can produce a synchronization event.',
      );
    }
    if (allocations.length != dispatch.allocationCount || allocations.isEmpty) {
      throw const OfflineSyncException(
        'transfer_allocation_mismatch',
        'The transfer allocation set does not match the sealed dispatch.',
      );
    }
    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.id.equals(transfer.currencyId))).getSingle();
    final localDatabaseId = await db
        .customSelect('SELECT database_id FROM sync_local_state WHERE id=1')
        .map((row) => row.read<String>('database_id'))
        .getSingle();
    if (localDatabaseId != transfer.databaseId) {
      throw const OfflineSyncException(
        'transfer_database_identity_mismatch',
        'The transfer belongs to a different source database.',
      );
    }
    final lines = <String, WarehouseTransferLine>{
      for (final line in await (db.select(
        db.warehouseTransferLines,
      )..where((row) => row.transferId.equals(transfer.id))).get())
        line.id: line,
    };
    final allocationPayload = <Map<String, Object?>>[];
    var calculatedOwnedValue = 0;
    for (final allocation in [
      ...allocations,
    ]..sort((left, right) => left.sequence.compareTo(right.sequence))) {
      final line = lines[allocation.lineId];
      if (line == null ||
          allocation.quantityScale != line.quantityScale ||
          allocation.measurementType != line.measurementType) {
        throw const OfflineSyncException(
          'transfer_line_identity_mismatch',
          'A transfer allocation no longer matches its sealed line.',
        );
      }
      final product = await identities.getOrCreateLocal(
        entityType: 'product',
        localId: line.productId,
      );
      final variant = await identities.getOrCreateLocal(
        entityType: 'product_variant',
        localId: line.variantId,
      );
      Map<String, Object?>? sourceBatch;
      String? supplierGlobalId;
      if (allocation.sourceBatchId != null) {
        final batch = await identities.getOrCreateLocal(
          entityType: 'product_batch',
          localId: allocation.sourceBatchId!,
        );
        final row =
            await (db.select(db.productBatches)
                  ..where((item) => item.id.equals(allocation.sourceBatchId!)))
                .getSingle();
        if (row.productId != line.productId ||
            row.variantId != line.variantId) {
          throw const OfflineSyncException(
            'transfer_batch_identity_mismatch',
            'The source batch does not belong to the transfer line.',
          );
        }
        if (row.supplierId != null) {
          supplierGlobalId = (await identities.getOrCreateLocal(
            entityType: 'supplier',
            localId: row.supplierId!,
          )).globalId;
        }
        sourceBatch = {
          'globalId': batch.globalId,
          'originDatabaseId': batch.originDatabaseId,
          if (row.purchaseItemId != null)
            'purchaseLineRef': {
              'databaseId': localDatabaseId,
              'localId': row.purchaseItemId,
            },
        };
      }
      if (allocation.supplierId != null) {
        final allocationSupplier = (await identities.getOrCreateLocal(
          entityType: 'supplier',
          localId: allocation.supplierId!,
        )).globalId;
        if (supplierGlobalId != null &&
            supplierGlobalId != allocationSupplier) {
          throw const OfflineSyncException(
            'transfer_supplier_identity_mismatch',
            'The batch and allocation suppliers do not match.',
          );
        }
        supplierGlobalId = allocationSupplier;
      }
      final origins =
          allocation.ownerType == 'owned' && allocation.sourceBatchId == null
          ? await _wacOrigins(
              allocation: allocation,
              sourceWarehouseId: transfer.sourceWarehouseId,
              localDatabaseId: localDatabaseId,
            )
          : const <Map<String, Object?>>[];
      if (allocation.ownerType == 'owned') {
        calculatedOwnedValue += allocation.valueCents;
      }
      allocationPayload.add({
        'allocationId': allocation.id,
        'lineId': allocation.lineId,
        'sequence': allocation.sequence,
        'productGlobalId': product.globalId,
        'variantGlobalId': variant.globalId,
        'ownerType': allocation.ownerType,
        'quantityScaled': allocation.quantity,
        'quantityScale': allocation.quantityScale,
        'measurementType': allocation.measurementType,
        'unitCostMinor': allocation.unitCostCents,
        'valueMinor': allocation.valueCents,
        'supplierGlobalId': ?supplierGlobalId,
        if (allocation.agreementId != null)
          'consignmentAgreementId': allocation.agreementId,
        if (allocation.sourceConsignmentLayerId != null)
          'sourceConsignmentLayerId': allocation.sourceConsignmentLayerId,
        'sourceBatch': ?sourceBatch,
        if (allocation.manufacturerLotNumber != null)
          'manufacturerLotNumber': allocation.manufacturerLotNumber,
        if (allocation.expiryDate != null)
          'expiryDate': allocation.expiryDate!.toUtc().toIso8601String(),
        if (origins.isNotEmpty) 'originSlices': origins,
      });
    }
    if (calculatedOwnedValue != dispatch.ownedValueCents) {
      throw const OfflineSyncException(
        'transfer_owned_value_mismatch',
        'The allocation values do not match the sealed dispatch.',
      );
    }
    return {
      'contract': 'warehouse_transfer.dispatched',
      'contractVersion': 1,
      'transferId': transfer.id,
      'requestKey': dispatch.requestKey,
      'organizationId': transfer.organizationId,
      'branchId': transfer.branchId,
      'sourceDatabaseId': transfer.databaseId,
      'sourceWarehouseId': transfer.sourceWarehouseId,
      'destinationWarehouseId': transfer.destinationWarehouseId,
      'currencyCode': currency.code,
      'dispatchedAt': dispatch.dispatchedAt.toUtc().toIso8601String(),
      'actorRef': {'databaseId': localDatabaseId, 'localId': dispatch.actorId},
      'ownedValueMinor': dispatch.ownedValueCents,
      'allocationCount': dispatch.allocationCount,
      'allocations': allocationPayload,
    };
  }

  Future<Map<String, Object?>> buildReceipt({
    required WarehouseTransfer transfer,
    required WarehouseTransferReceipt receipt,
    required List<WarehouseTransferReceiptItem> items,
  }) async {
    if (!receipt.sealed || receipt.transferId != transfer.id) {
      throw const OfflineSyncException(
        'unsealed_transfer_receipt',
        'Only a sealed transfer receipt can produce a synchronization event.',
      );
    }
    if (items.length != receipt.itemCount || items.isEmpty) {
      throw const OfflineSyncException(
        'transfer_receipt_item_mismatch',
        'The transfer receipt items do not match the sealed receipt.',
      );
    }
    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.id.equals(transfer.currencyId))).getSingle();
    final localDatabaseId = await db
        .customSelect('SELECT database_id FROM sync_local_state WHERE id=1')
        .map((row) => row.read<String>('database_id'))
        .getSingle();
    if (localDatabaseId != transfer.databaseId) {
      throw const OfflineSyncException(
        'transfer_database_identity_mismatch',
        'The transfer belongs to a different source database.',
      );
    }
    final itemPayload = <Map<String, Object?>>[];
    var acceptedValue = 0;
    var varianceValue = 0;
    for (final item in [
      ...items,
    ]..sort((left, right) => left.allocationId.compareTo(right.allocationId))) {
      Map<String, Object?>? destinationBatch;
      if (item.destinationBatchId != null) {
        final identity = await identities.getOrCreateLocal(
          entityType: 'product_batch',
          localId: item.destinationBatchId!,
        );
        destinationBatch = {
          'globalId': identity.globalId,
          'originDatabaseId': identity.originDatabaseId,
        };
      }
      acceptedValue += item.acceptedValueCents;
      varianceValue += item.varianceValueCents;
      itemPayload.add({
        'allocationId': item.allocationId,
        'acceptedQuantityScaled': item.acceptedQuantity,
        'damagedQuantityScaled': item.damagedQuantity,
        'lostQuantityScaled': item.lostQuantity,
        'acceptedValueMinor': item.acceptedValueCents,
        'varianceValueMinor': item.varianceValueCents,
        'destinationBatch': ?destinationBatch,
        'destinationConsignmentLayerId': ?item.destinationConsignmentLayerId,
      });
    }
    if (acceptedValue != receipt.acceptedOwnedValueCents ||
        varianceValue != receipt.varianceOwnedValueCents ||
        receipt.destinationInventoryDeltaCents != acceptedValue) {
      throw const OfflineSyncException(
        'transfer_receipt_value_mismatch',
        'The receipt item values do not match the sealed receipt.',
      );
    }
    final completed =
        await (db.select(db.warehouseTransferEvents)..where(
              (event) =>
                  event.transferId.equals(transfer.id) &
                  event.kind.equals('completed') &
                  event.requestKey.equals(receipt.requestKey),
            ))
            .getSingleOrNull() !=
        null;
    return {
      'contract': 'warehouse_transfer.received',
      'contractVersion': 1,
      'transferId': transfer.id,
      'requestKey': receipt.requestKey,
      'organizationId': transfer.organizationId,
      'branchId': transfer.branchId,
      'sourceDatabaseId': transfer.databaseId,
      'sourceWarehouseId': transfer.sourceWarehouseId,
      'destinationWarehouseId': transfer.destinationWarehouseId,
      'currencyCode': currency.code,
      'receivedAt': receipt.receivedAt.toUtc().toIso8601String(),
      'actorRef': {'databaseId': localDatabaseId, 'localId': receipt.actorId},
      'acceptedOwnedValueMinor': receipt.acceptedOwnedValueCents,
      'varianceOwnedValueMinor': receipt.varianceOwnedValueCents,
      'destinationInventoryDeltaMinor': receipt.destinationInventoryDeltaCents,
      'completedTransfer': completed,
      'notes': receipt.notes,
      'itemCount': receipt.itemCount,
      'items': itemPayload,
    };
  }

  Future<Map<String, Object?>> buildRecall({
    required WarehouseTransfer transfer,
    required WarehouseTransferRecall recall,
    required List<WarehouseTransferRecallItem> items,
  }) async {
    if (!recall.sealed ||
        recall.transferId != transfer.id ||
        transfer.status != 'cancelled') {
      throw const OfflineSyncException(
        'unsealed_transfer_recall',
        'Only a sealed transfer recall can produce a synchronization event.',
      );
    }
    if (items.length != recall.itemCount || items.isEmpty) {
      throw const OfflineSyncException(
        'transfer_recall_item_mismatch',
        'The transfer recall items do not match the sealed recall.',
      );
    }
    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.id.equals(transfer.currencyId))).getSingle();
    final localDatabaseId = await db
        .customSelect('SELECT database_id FROM sync_local_state WHERE id=1')
        .map((row) => row.read<String>('database_id'))
        .getSingle();
    if (localDatabaseId != transfer.databaseId) {
      throw const OfflineSyncException(
        'transfer_database_identity_mismatch',
        'The transfer belongs to a different source database.',
      );
    }
    final sorted = [...items]
      ..sort((left, right) => left.allocationId.compareTo(right.allocationId));
    final calculatedValue = sorted.fold<int>(
      0,
      (total, item) => total + item.valueCents,
    );
    if (calculatedValue != recall.ownedValueCents) {
      throw const OfflineSyncException(
        'transfer_recall_value_mismatch',
        'The recall item values do not match the sealed recall.',
      );
    }
    return {
      'contract': 'warehouse_transfer.recalled',
      'contractVersion': 1,
      'transferId': transfer.id,
      'requestKey': recall.requestKey,
      'organizationId': transfer.organizationId,
      'branchId': transfer.branchId,
      'sourceDatabaseId': transfer.databaseId,
      'sourceWarehouseId': transfer.sourceWarehouseId,
      'destinationWarehouseId': transfer.destinationWarehouseId,
      'currencyCode': currency.code,
      'recalledAt': recall.recalledAt.toUtc().toIso8601String(),
      'actorRef': {'databaseId': localDatabaseId, 'localId': recall.actorId},
      'ownedValueMinor': recall.ownedValueCents,
      'reason': recall.reason,
      'itemCount': recall.itemCount,
      'items': [
        for (final item in sorted)
          {
            'allocationId': item.allocationId,
            'quantityScaled': item.quantity,
            'valueMinor': item.valueCents,
          },
      ],
    };
  }

  Future<List<Map<String, Object?>>> _wacOrigins({
    required WarehouseTransferAllocation allocation,
    required String sourceWarehouseId,
    required String localDatabaseId,
  }) async {
    final event = await db
        .customSelect(
          'SELECT delta,allocations FROM inventory_origin_events '
          'WHERE warehouse_id=? AND event_key=?',
          variables: [
            Variable.withString(sourceWarehouseId),
            Variable.withString('transfer_out:${allocation.id}'),
          ],
        )
        .getSingleOrNull();
    if (event == null || event.read<int>('delta') != -allocation.quantity) {
      throw const OfflineSyncException(
        'transfer_origin_event_missing',
        'The WAC transfer origin event is missing or has a different quantity.',
      );
    }
    final decoded = jsonDecode(event.read<String>('allocations'));
    if (decoded is! List) {
      throw const OfflineSyncException(
        'invalid_transfer_origin',
        'The WAC transfer origin allocation is not a list.',
      );
    }
    final result = <Map<String, Object?>>[];
    var total = 0;
    for (final raw in decoded) {
      if (raw is! Map) {
        throw const OfflineSyncException(
          'invalid_transfer_origin',
          'A WAC transfer origin slice is invalid.',
        );
      }
      final layer = raw.map((key, value) => MapEntry(key.toString(), value));
      final quantity = layer['q'];
      if (quantity is! int || quantity <= 0) {
        throw const OfflineSyncException(
          'invalid_transfer_origin',
          'A WAC transfer origin quantity is invalid.',
        );
      }
      total += quantity;
      final purchaseItemId = layer['p'] is int ? layer['p'] as int : null;
      final supplierIdentityId = layer['i'] is int ? layer['i'] as int : null;
      final supplierId = await _originSupplier(
        purchaseItemId: purchaseItemId,
        supplierIdentityId: supplierIdentityId,
      );
      final supplierGlobalId = supplierId == null
          ? null
          : (await identities.getOrCreateLocal(
              entityType: 'supplier',
              localId: supplierId,
            )).globalId;
      result.add({
        'quantityScaled': quantity,
        'originKind': layer['k']?.toString() ?? 'unknown',
        'supplierGlobalId': ?supplierGlobalId,
        if (purchaseItemId != null)
          'purchaseLineRef': {
            'databaseId': localDatabaseId,
            'localId': purchaseItemId,
          },
        if (layer['r'] != null) 'sourceReference': layer['r'].toString(),
        'sourceQuality': supplierGlobalId == null ? 'unverified' : 'documented',
      });
    }
    if (total != allocation.quantity) {
      throw const OfflineSyncException(
        'transfer_origin_quantity_mismatch',
        'The WAC origin slices do not equal the transferred quantity.',
      );
    }
    return List.unmodifiable(result);
  }

  Future<int?> _originSupplier({
    required int? purchaseItemId,
    required int? supplierIdentityId,
  }) async {
    int? fromIdentity;
    if (supplierIdentityId != null) {
      fromIdentity = await db
          .customSelect(
            'SELECT supplier_id FROM supplier_product_identities WHERE id=?',
            variables: [Variable.withInt(supplierIdentityId)],
          )
          .map((row) => row.read<int>('supplier_id'))
          .getSingleOrNull();
      if (fromIdentity == null) {
        throw const OfflineSyncException(
          'transfer_supplier_identity_missing',
          'A recorded supplier identity no longer exists.',
        );
      }
    }
    int? fromPurchase;
    if (purchaseItemId != null) {
      fromPurchase = await db
          .customSelect(
            'SELECT p.supplier_id FROM purchase_items i '
            'JOIN purchases p ON p.id=i.purchase_id WHERE i.id=?',
            variables: [Variable.withInt(purchaseItemId)],
          )
          .map((row) => row.read<int>('supplier_id'))
          .getSingleOrNull();
      if (fromPurchase == null) {
        throw const OfflineSyncException(
          'transfer_purchase_origin_missing',
          'A recorded purchase origin no longer exists.',
        );
      }
    }
    if (fromIdentity != null &&
        fromPurchase != null &&
        fromIdentity != fromPurchase) {
      throw const OfflineSyncException(
        'transfer_origin_supplier_conflict',
        'The purchase and supplier identity origins disagree.',
      );
    }
    return fromIdentity ?? fromPurchase;
  }
}
