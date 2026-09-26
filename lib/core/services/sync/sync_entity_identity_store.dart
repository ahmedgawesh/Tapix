import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import 'offline_sync_event_store.dart';

class SyncEntityIdentity {
  const SyncEntityIdentity({
    required this.entityType,
    required this.localId,
    required this.globalId,
    required this.originDatabaseId,
  });

  final String entityType;
  final int localId;
  final String globalId;
  final String originDatabaseId;
}

/// Stable global identities for integer-keyed master data.
///
/// Names, SKU values and barcodes are intentionally not identity keys: they can
/// change or collide. A remote binding is accepted only from an enrolled source
/// and never overwrites an existing local or global mapping.
class SyncEntityIdentityStore {
  SyncEntityIdentityStore(this._db, {Uuid uuid = const Uuid()}) : _uuid = uuid;

  final AppDatabase _db;
  final Uuid _uuid;

  static const supportedTypes = {
    'product',
    'product_variant',
    'product_batch',
    'supplier',
    'customer',
  };

  Future<SyncEntityIdentity> getOrCreateLocal({
    required String entityType,
    required int localId,
  }) => _db.transaction(() async {
    _validateKey(entityType, localId);
    await _requireEntity(entityType, localId);
    if (entityType == 'product_variant') {
      final variant = await (_db.select(
        _db.productVariants,
      )..where((row) => row.id.equals(localId))).getSingle();
      await getOrCreateLocal(entityType: 'product', localId: variant.productId);
    } else if (entityType == 'product_batch') {
      final batch = await (_db.select(
        _db.productBatches,
      )..where((row) => row.id.equals(localId))).getSingle();
      await getOrCreateLocal(entityType: 'product', localId: batch.productId);
      if (batch.variantId != null) {
        await getOrCreateLocal(
          entityType: 'product_variant',
          localId: batch.variantId!,
        );
      }
      if (batch.supplierId != null) {
        await getOrCreateLocal(
          entityType: 'supplier',
          localId: batch.supplierId!,
        );
      }
    }
    final existing = await findByLocal(
      entityType: entityType,
      localId: localId,
    );
    if (existing != null) return existing;
    final localDatabaseId = await _localDatabaseId();
    final globalId = _uuid.v4();
    await _insertIdentity(
      entityType: entityType,
      localId: localId,
      globalId: globalId,
      originDatabaseId: localDatabaseId,
    );
    return SyncEntityIdentity(
      entityType: entityType,
      localId: localId,
      globalId: globalId,
      originDatabaseId: localDatabaseId,
    );
  });

  Future<SyncEntityIdentity> bindRemote({
    required String entityType,
    required int localId,
    required String globalId,
    required String originDatabaseId,
  }) => _db.transaction(() async {
    _validateKey(entityType, localId);
    if (!_isUuid(globalId) || !_isUuid(originDatabaseId)) {
      throw const OfflineSyncException(
        'invalid_global_identity',
        'Global and origin database identities must be UUID values.',
      );
    }
    await _requireEntity(entityType, localId);
    final source = await _db
        .customSelect(
          'SELECT status FROM sync_source_checkpoints WHERE source_database_id=?',
          variables: [Variable.withString(originDatabaseId)],
        )
        .getSingleOrNull();
    if (source == null || source.read<String>('status') != 'active') {
      throw const OfflineSyncException(
        'identity_source_not_enrolled',
        'The identity origin is not an active enrolled source.',
      );
    }
    final byLocal = await findByLocal(entityType: entityType, localId: localId);
    final byGlobal = await findByGlobal(
      entityType: entityType,
      globalId: globalId,
    );
    if (byLocal != null || byGlobal != null) {
      if (byLocal?.globalId == globalId &&
          byLocal?.originDatabaseId == originDatabaseId &&
          byGlobal?.localId == localId) {
        return byLocal!;
      }
      throw const OfflineSyncException(
        'entity_identity_conflict',
        'The local or global entity identity is already bound differently.',
      );
    }
    await _insertIdentity(
      entityType: entityType,
      localId: localId,
      globalId: globalId,
      originDatabaseId: originDatabaseId,
    );
    return SyncEntityIdentity(
      entityType: entityType,
      localId: localId,
      globalId: globalId,
      originDatabaseId: originDatabaseId,
    );
  });

  Future<SyncEntityIdentity?> findByLocal({
    required String entityType,
    required int localId,
  }) async {
    _validateKey(entityType, localId);
    final batch = entityType == 'product_batch';
    final row = await _db
        .customSelect(
          batch
              ? "SELECT 'product_batch' AS entity_type,local_batch_id AS local_id,global_id,origin_database_id FROM sync_inventory_layer_identities WHERE local_batch_id=?"
              : 'SELECT entity_type,local_id,global_id,origin_database_id FROM sync_entity_identities WHERE entity_type=? AND local_id=?',
          variables: batch
              ? [Variable.withInt(localId)]
              : [Variable.withString(entityType), Variable.withInt(localId)],
        )
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<SyncEntityIdentity?> findByGlobal({
    required String entityType,
    required String globalId,
  }) async {
    if (!supportedTypes.contains(entityType) || !_isUuid(globalId)) {
      throw const OfflineSyncException(
        'invalid_entity_identity',
        'The entity type or global identity is invalid.',
      );
    }
    final batch = entityType == 'product_batch';
    final row = await _db
        .customSelect(
          batch
              ? "SELECT 'product_batch' AS entity_type,local_batch_id AS local_id,global_id,origin_database_id FROM sync_inventory_layer_identities WHERE global_id=?"
              : 'SELECT entity_type,local_id,global_id,origin_database_id FROM sync_entity_identities WHERE entity_type=? AND global_id=?',
          variables: batch
              ? [Variable.withString(globalId)]
              : [
                  Variable.withString(entityType),
                  Variable.withString(globalId),
                ],
        )
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<void> _requireEntity(String type, int id) async {
    final table = switch (type) {
      'product' => 'products',
      'product_variant' => 'product_variants',
      'product_batch' => 'product_batches',
      'supplier' => 'suppliers',
      'customer' => 'customers',
      _ => throw const OfflineSyncException(
        'unsupported_entity_type',
        'This entity type is not part of the synchronization contract.',
      ),
    };
    final row = await _db
        .customSelect(
          'SELECT 1 AS found FROM $table WHERE id=?',
          variables: [Variable.withInt(id)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw const OfflineSyncException(
        'sync_entity_not_found',
        'The local entity does not exist.',
      );
    }
  }

  Future<String> _localDatabaseId() async =>
      (await _db
              .customSelect(
                'SELECT database_id FROM sync_local_state WHERE id=1',
              )
              .getSingle())
          .read<String>('database_id');

  Future<void> _insertIdentity({
    required String entityType,
    required int localId,
    required String globalId,
    required String originDatabaseId,
  }) => entityType == 'product_batch'
      ? _db.customStatement(
          'INSERT INTO sync_inventory_layer_identities('
          'local_batch_id,global_id,origin_database_id) VALUES(?,?,?)',
          [localId, globalId, originDatabaseId],
        )
      : _db.customStatement(
          'INSERT INTO sync_entity_identities(entity_type,local_id,global_id,'
          'origin_database_id) VALUES(?,?,?,?)',
          [entityType, localId, globalId, originDatabaseId],
        );

  void _validateKey(String type, int id) {
    if (!supportedTypes.contains(type)) {
      throw const OfflineSyncException(
        'unsupported_entity_type',
        'This entity type is not part of the synchronization contract.',
      );
    }
    if (id <= 0) {
      throw const OfflineSyncException(
        'invalid_local_entity_id',
        'The local entity identifier must be positive.',
      );
    }
  }

  bool _isUuid(String value) => RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);

  SyncEntityIdentity _fromRow(QueryRow row) => SyncEntityIdentity(
    entityType: row.read<String>('entity_type'),
    localId: row.read<int>('local_id'),
    globalId: row.read<String>('global_id'),
    originDatabaseId: row.read<String>('origin_database_id'),
  );
}
