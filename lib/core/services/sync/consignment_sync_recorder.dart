import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import 'offline_sync_event_store.dart';
import 'sync_entity_identity_store.dart';

/// Records finalized consignment documents in the immutable branch stream.
/// Receivers keep these envelopes as read-only company evidence; they never
/// repost stock, supplier balances or journals owned by the source branch.
class ConsignmentSyncRecorder {
  ConsignmentSyncRecorder(this._db, {Uuid uuid = const Uuid()}) : _uuid = uuid;

  final AppDatabase _db;
  final Uuid _uuid;

  Future<void> record({
    required String eventType,
    required String contract,
    required String documentType,
    required Object localDocumentId,
    required String action,
    required DateTime occurredAt,
    required int supplierId,
    required int currencyId,
    String? warehouseId,
    String? agreementId,
    required Map<String, Object?> values,
    List<Map<String, Object?>> lines = const [],
  }) async {
    final events = OfflineSyncEventStore(_db);
    // Most installations still run as a single local database. Avoid opening
    // a nested write transaction for them; the consignment document remains
    // fully local until this database is explicitly enrolled as a LAN writer.
    if (!await events.isWriterRecordingEnabled()) return;
    await events.transaction((sync) async {
      final local = await _db
          .customSelect(
            'SELECT database_id,organization_id,branch_id '
            'FROM sync_local_state WHERE id=1',
          )
          .getSingle();
      final databaseId = local.read<String>('database_id');
      final supplier = await SyncEntityIdentityStore(
        _db,
      ).getOrCreateLocal(entityType: 'supplier', localId: supplierId);
      final currencyCode = await _db
          .customSelect(
            'SELECT code FROM currencies WHERE id=?',
            variables: [Variable.withInt(currencyId)],
          )
          .map((row) => row.read<String>('code'))
          .getSingle();
      final normalizedLines = <Map<String, Object?>>[];
      for (final line in lines) {
        final productId = line['productId'];
        final variantId = line['variantId'];
        normalizedLines.add({
          ...line,
          if (productId is int)
            'productGlobalId':
                (await SyncEntityIdentityStore(_db).getOrCreateLocal(
                  entityType: 'product',
                  localId: productId,
                )).globalId,
          if (variantId is int)
            'variantGlobalId':
                (await SyncEntityIdentityStore(_db).getOrCreateLocal(
                  entityType: 'product_variant',
                  localId: variantId,
                )).globalId,
        });
      }
      final documentId = _uuid.v5(
        Namespace.url.value,
        'tapix-consignment:$databaseId:$documentType:$localDocumentId',
      );
      await sync.appendOnce(
        producerKey: 'consignment:$documentType:$localDocumentId:$action',
        eventType: eventType,
        aggregateType: documentType,
        aggregateId: documentId,
        occurredAt: occurredAt,
        payload: {
          'contract': contract,
          'contractVersion': 1,
          'documentId': documentId,
          'documentType': documentType,
          'action': action,
          'sourceDocumentRef': {
            'databaseId': databaseId,
            'localId': localDocumentId,
          },
          'organizationId': local.read<String>('organization_id'),
          'sourceDatabaseId': databaseId,
          'sourceBranchId': local.read<String>('branch_id'),
          'warehouseId': warehouseId,
          'supplierGlobalId': supplier.globalId,
          'agreementRef': agreementId == null
              ? null
              : {'databaseId': databaseId, 'localId': agreementId},
          'currencyCode': currencyCode,
          'occurredAt': occurredAt.toUtc().toIso8601String(),
          ...values,
          'lineCount': normalizedLines.length,
          'lines': normalizedLines,
        },
      );
    });
  }
}
