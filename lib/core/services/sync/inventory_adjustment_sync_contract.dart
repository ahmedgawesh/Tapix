import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'offline_sync_event_store.dart';
import 'sync_entity_identity_store.dart';

class InventoryAdjustmentSyncContractBuilder {
  const InventoryAdjustmentSyncContractBuilder(this.db, this.identities);

  final AppDatabase db;
  final SyncEntityIdentityStore identities;

  Future<Map<String, Object?>> buildPosted({
    required InventoryAdjustment adjustment,
  }) async {
    if (adjustment.journalEntryId == null) {
      throw const OfflineSyncException(
        'inventory_adjustment_journal_missing',
        'A synchronized inventory adjustment must have a posted journal.',
      );
    }
    final location = await db
        .customSelect(
          'SELECT document_id,organization_id,branch_id,warehouse_id,'
          'origin_database_id FROM business_document_locations '
          "WHERE source_table='inventory_adjustments' AND source_id=?",
          variables: [Variable.withInt(adjustment.id)],
        )
        .getSingleOrNull();
    if (location == null) {
      throw const OfflineSyncException(
        'inventory_adjustment_location_missing',
        'The inventory adjustment has no immutable business location.',
      );
    }
    final databaseId = await db
        .customSelect('SELECT database_id FROM sync_local_state WHERE id=1')
        .map((row) => row.read<String>('database_id'))
        .getSingle();
    if (location.read<String>('origin_database_id') != databaseId) {
      throw const OfflineSyncException(
        'inventory_adjustment_database_identity_mismatch',
        'The inventory adjustment belongs to another source database.',
      );
    }
    final product = await identities.getOrCreateLocal(
      entityType: 'product',
      localId: adjustment.productId,
    );
    final variant = adjustment.variantId == null
        ? null
        : await identities.getOrCreateLocal(
            entityType: 'product_variant',
            localId: adjustment.variantId!,
          );
    final currency = await (db.select(
      db.currencies,
    )..where((row) => row.id.equals(adjustment.currencyId))).getSingle();
    final batchConsumptions = await db
        .customSelect(
          'SELECT id,batch_id,quantity,unit_cost_cents,direction,'
          'consumption_type FROM batch_consumptions '
          'WHERE inventory_adjustment_id=? ORDER BY id',
          variables: [Variable.withInt(adjustment.id)],
        )
        .get();
    final revaluations = await db
        .customSelect(
          'SELECT old_batch_id,new_batch_id,quantity,old_unit_cost_cents,'
          'new_unit_cost_cents,previous_value_cents,new_value_cents '
          'FROM inventory_revaluation_layers WHERE adjustment_id=? '
          'ORDER BY old_batch_id',
          variables: [Variable.withInt(adjustment.id)],
        )
        .get();

    return {
      'contract': 'inventory_adjustment.posted',
      'contractVersion': 1,
      'documentId': location.read<String>('document_id'),
      'sourceDocumentRef': {
        'databaseId': databaseId,
        'table': 'inventory_adjustments',
        'localId': adjustment.id,
      },
      'organizationId': location.read<String>('organization_id'),
      'branchId': location.read<String>('branch_id'),
      'warehouseId': location.read<String>('warehouse_id'),
      'adjustmentNumber': adjustment.adjustmentNumber,
      'adjustmentType': adjustment.adjustmentType,
      'productGlobalId': product.globalId,
      'variantGlobalId': variant?.globalId,
      'quantityDeltaScaled': adjustment.quantityDelta,
      'unitCostMinor': adjustment.unitCostCents.toBigInt().toInt(),
      'previousUnitCostMinor': adjustment.previousUnitCostCents
          ?.toBigInt()
          .toInt(),
      'totalValueMinor': adjustment.totalValueCents.toBigInt().toInt(),
      'currencyCode': currency.code,
      'costingMethod': adjustment.costingMethod,
      'reason': adjustment.reason,
      'notes': adjustment.notes,
      'actorRef': adjustment.userId == null
          ? null
          : {'databaseId': databaseId, 'localId': adjustment.userId},
      'journalRef': {
        'databaseId': databaseId,
        'localId': adjustment.journalEntryId,
      },
      'postedAt': adjustment.createdAt.toUtc().toIso8601String(),
      'batchMovements': [
        for (final row in batchConsumptions)
          {
            'movementRef': {
              'databaseId': databaseId,
              'localId': row.read<int>('id'),
            },
            'batchGlobalId': (await identities.getOrCreateLocal(
              entityType: 'product_batch',
              localId: row.read<int>('batch_id'),
            )).globalId,
            'quantityScaled': row.read<int>('quantity'),
            'unitCostMinor': row.read<int>('unit_cost_cents'),
            'direction': row.read<String>('direction'),
            'type': row.read<String>('consumption_type'),
          },
      ],
      'revaluationLayers': [
        for (final row in revaluations)
          {
            'oldBatchGlobalId': (await identities.getOrCreateLocal(
              entityType: 'product_batch',
              localId: row.read<int>('old_batch_id'),
            )).globalId,
            'newBatchGlobalId': (await identities.getOrCreateLocal(
              entityType: 'product_batch',
              localId: row.read<int>('new_batch_id'),
            )).globalId,
            'quantityScaled': row.read<int>('quantity'),
            'oldUnitCostMinor': row.read<int>('old_unit_cost_cents'),
            'newUnitCostMinor': row.read<int>('new_unit_cost_cents'),
            'previousValueMinor': row.read<int>('previous_value_cents'),
            'newValueMinor': row.read<int>('new_value_cents'),
            'deltaValueMinor':
                row.read<int>('new_value_cents') -
                row.read<int>('previous_value_cents'),
          },
      ],
    };
  }
}
