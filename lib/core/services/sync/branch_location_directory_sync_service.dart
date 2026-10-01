import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import 'offline_sync_event_store.dart';

class BranchLocationDirectorySyncService {
  BranchLocationDirectorySyncService(
    this._db,
    this._events, {
    Uuid uuid = const Uuid(),
  }) : _uuid = uuid;

  final AppDatabase _db;
  final OfflineSyncEventStore _events;
  final Uuid _uuid;

  static const eventType = 'location.snapshot_page.v1';
  static const _pageSize = 20;
  static const _types = ['branch', 'warehouse'];

  Future<String> publishSnapshot({OfflineSyncTransaction? transaction}) async {
    final local = await _db
        .customSelect(
          'SELECT database_id,organization_id,branch_id FROM sync_local_state WHERE id=1',
        )
        .getSingle();
    final databaseId = local.read<String>('database_id');
    final organizationId = local.read<String>('organization_id');
    final branchId = local.read<String>('branch_id');
    final branches = await _db
        .customSelect(
          '''SELECT b.id,b.code,b.name,b.is_active,
          CASE WHEN b.id=? THEN ? ELSE e.remote_database_id END AS writer_database_id
          FROM business_branches b
          LEFT JOIN lan_branch_enrollments e
            ON e.branch_id=b.id AND e.status='active'
          WHERE b.organization_id=? ORDER BY b.code,b.id''',
          variables: [
            Variable.withString(branchId),
            Variable.withString(databaseId),
            Variable.withString(organizationId),
          ],
        )
        .get();
    final warehouses = await _db
        .customSelect(
          '''SELECT id,branch_id,code,name,location_kind,is_active FROM business_warehouses
          WHERE organization_id=? ORDER BY branch_id,code,id''',
          variables: [Variable.withString(organizationId)],
        )
        .get();
    final entities = <String, List<Map<String, Object?>>>{
      'branch': [
        for (final row in branches)
          {
            'branchId': row.read<String>('id'),
            'organizationId': organizationId,
            'code': row.read<String>('code'),
            'name': _publishedName(
              row.read<String>('name'),
              row.read<String>('code'),
            ),
            'writerDatabaseId': row.readNullable<String>('writer_database_id'),
            'isActive': row.read<int>('is_active') == 1,
          },
      ],
      'warehouse': [
        for (final row in warehouses)
          {
            'warehouseId': row.read<String>('id'),
            'organizationId': organizationId,
            'branchId': row.read<String>('branch_id'),
            'code': row.read<String>('code'),
            'name': _publishedName(
              row.read<String>('name'),
              row.read<String>('code'),
            ),
            'locationKind': row.read<String>('location_kind'),
            'isActive': row.read<int>('is_active') == 1,
          },
      ],
    };
    final digest = sha256
        .convert(
          utf8.encode(
            jsonEncode([for (final type in _types) ...entities[type]!]),
          ),
        )
        .toString();
    final snapshotId = _uuid.v5(
      Namespace.url.value,
      'tapix-location-v1:$databaseId:$digest',
    );
    final occurredAt = DateTime.now().toUtc();
    for (final type in _types) {
      final values = entities[type]!;
      final pageCount = values.isEmpty ? 1 : (values.length / _pageSize).ceil();
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        final start = pageIndex * _pageSize;
        final end = values.isEmpty
            ? 0
            : (start + _pageSize).clamp(0, values.length);
        final page = values.isEmpty
            ? const <Map<String, Object?>>[]
            : values.sublist(start, end);
        Future<void> append(OfflineSyncTransaction sync) async {
          if (!await sync.isWriterRecordingEnabled()) {
            throw const OfflineSyncException(
              'location_writer_not_enrolled',
              'Location publication requires an enrolled branch writer.',
            );
          }
          await sync.appendOnce(
            producerKey: 'location:$snapshotId:$type:$pageIndex',
            eventType: eventType,
            aggregateType: 'location_snapshot',
            aggregateId: snapshotId,
            payload: {
              'contract': 'location.snapshot_page',
              'contractVersion': 1,
              'snapshotId': snapshotId,
              'organizationId': organizationId,
              'sourceDatabaseId': databaseId,
              'sourceBranchId': branchId,
              'entityType': type,
              'pageIndex': pageIndex,
              'pageCount': pageCount,
              'entities': page,
            },
            occurredAt: occurredAt,
          );
        }

        if (transaction case final sync?) {
          await append(sync);
        } else {
          await _events.transaction(append);
        }
      }
    }
    return snapshotId;
  }

  Future<void> applyPage(SyncEventEnvelope event) async {
    final payload = event.payload;
    if (event.eventType != eventType ||
        event.contractVersion != 1 ||
        event.aggregateType != 'location_snapshot' ||
        payload['contract'] != 'location.snapshot_page' ||
        payload['contractVersion'] != 1) {
      throw const OfflineSyncException(
        'invalid_location_contract',
        'The location directory contract is invalid.',
      );
    }
    final authority = await _db
        .customSelect(
          "SELECT value FROM app_settings WHERE key='lan.branch_sync.coordinator_database_id.v1'",
        )
        .getSingleOrNull();
    if (authority == null ||
        authority.read<String>('value') != event.sourceDatabaseId) {
      throw const OfflineSyncException(
        'location_source_not_authoritative',
        'Only the enrolled LAN coordinator can publish locations.',
      );
    }
    final snapshotId = _uuidField(payload, 'snapshotId');
    final organizationId = _uuidField(payload, 'organizationId');
    if (snapshotId != event.aggregateId ||
        organizationId != event.organizationId ||
        _uuidField(payload, 'sourceDatabaseId') != event.sourceDatabaseId ||
        _uuidField(payload, 'sourceBranchId') != event.branchId) {
      throw const OfflineSyncException(
        'location_envelope_mismatch',
        'The location page does not match its event envelope.',
      );
    }
    final localOrganization = await _db
        .customSelect(
          'SELECT organization_id FROM business_contexts WHERE id=1',
        )
        .map((row) => row.read<String>('organization_id'))
        .getSingle();
    if (organizationId != localOrganization) {
      throw const OfflineSyncException(
        'location_organization_mismatch',
        'The location directory belongs to another organization.',
      );
    }
    final type = payload['entityType']?.toString() ?? '';
    final pageIndex = payload['pageIndex'];
    final pageCount = payload['pageCount'];
    final entities = payload['entities'];
    if (!_types.contains(type) ||
        pageIndex is! int ||
        pageIndex < 0 ||
        pageCount is! int ||
        pageCount <= 0 ||
        pageIndex >= pageCount ||
        entities is! List ||
        entities.length > _pageSize) {
      throw const OfflineSyncException(
        'invalid_location_page',
        'The location page metadata is invalid.',
      );
    }
    for (final raw in entities) {
      if (raw is! Map) {
        throw const OfflineSyncException(
          'invalid_location_entity',
          'A location entity has an invalid structure.',
        );
      }
      final entity = Map<String, Object?>.from(raw);
      if (type == 'branch') {
        await _applyBranch(entity, organizationId);
      } else {
        await _applyWarehouse(entity, organizationId);
      }
    }
    await _db.customStatement(
      '''INSERT INTO sync_location_pages(
        event_id,snapshot_id,entity_type,page_index,page_count,source_database_id)
        VALUES(?,?,?,?,?,?)''',
      [
        event.eventId,
        snapshotId,
        type,
        pageIndex,
        pageCount,
        event.sourceDatabaseId,
      ],
    );
  }

  Future<bool> hasCompleteSnapshot() async {
    final rows = await _db
        .customSelect(
          'SELECT snapshot_id,entity_type,page_count,COUNT(*) AS pages '
          'FROM sync_location_pages GROUP BY snapshot_id,entity_type,page_count',
        )
        .get();
    final snapshots = <String, Map<String, bool>>{};
    for (final row in rows) {
      snapshots.putIfAbsent(row.read<String>('snapshot_id'), () => {})[row
              .read<String>('entity_type')] =
          row.read<int>('pages') == row.read<int>('page_count');
    }
    return snapshots.values.any(
      (types) => _types.every((type) => types[type] == true),
    );
  }

  /// Materializes local routing identities that arrived before local physical
  /// warehouse support was installed. This copies identity only; stock stays
  /// empty until a purchase, adjustment, or accepted transfer changes it.
  Future<void> reconcileLocalWarehouses() async {
    final context = await _db
        .customSelect(
          'SELECT organization_id,branch_id FROM business_contexts WHERE id=1',
        )
        .getSingle();
    final organizationId = context.read<String>('organization_id');
    final branchId = context.read<String>('branch_id');
    await _db.customStatement(
      '''INSERT INTO business_warehouses(
        id,organization_id,branch_id,code,name,location_kind,is_active)
        SELECT warehouse_id,organization_id,branch_id,code,name,
               location_kind,is_active
        FROM sync_warehouse_directory
        WHERE organization_id=? AND branch_id=?
        ON CONFLICT(id) DO UPDATE SET code=excluded.code,name=excluded.name,
          location_kind=excluded.location_kind,is_active=excluded.is_active''',
      [organizationId, branchId],
    );
  }

  Future<void> _applyBranch(
    Map<String, Object?> entity,
    String organizationId,
  ) async {
    final branchId = _uuidField(entity, 'branchId');
    if (_uuidField(entity, 'organizationId') != organizationId) {
      throw const OfflineSyncException(
        'location_entity_organization_mismatch',
        'A branch belongs to another organization.',
      );
    }
    final writerRaw = entity['writerDatabaseId'];
    final writer = writerRaw == null
        ? null
        : _uuidField(entity, 'writerDatabaseId');
    final code = _text(entity, 'code', 32);
    await _db.customStatement(
      '''INSERT INTO sync_branch_directory(
        branch_id,organization_id,code,name,writer_database_id,is_active)
        VALUES(?,?,?,?,?,?)
        ON CONFLICT(branch_id) DO UPDATE SET code=excluded.code,name=excluded.name,
          writer_database_id=excluded.writer_database_id,
          is_active=excluded.is_active,updated_at=CURRENT_TIMESTAMP''',
      [
        branchId,
        organizationId,
        code,
        _legacyDisplayName(entity, code),
        writer,
        _bool(entity, 'isActive') ? 1 : 0,
      ],
    );
  }

  Future<void> _applyWarehouse(
    Map<String, Object?> entity,
    String organizationId,
  ) async {
    final warehouseId = _uuidField(entity, 'warehouseId');
    final branchId = _uuidField(entity, 'branchId');
    if (_uuidField(entity, 'organizationId') != organizationId ||
        await _db
                .customSelect(
                  'SELECT 1 AS found FROM sync_branch_directory WHERE branch_id=? AND organization_id=?',
                  variables: [
                    Variable.withString(branchId),
                    Variable.withString(organizationId),
                  ],
                )
                .getSingleOrNull() ==
            null) {
      throw const OfflineSyncException(
        'location_branch_missing',
        'A warehouse branch must arrive before the warehouse.',
      );
    }
    final code = _text(entity, 'code', 32);
    final locationKind = entity['locationKind']?.toString() ?? 'warehouse';
    if (locationKind != 'branch_store' && locationKind != 'warehouse') {
      throw const OfflineSyncException(
        'invalid_location_field',
        'The warehouse location kind is invalid.',
      );
    }
    final name = _legacyDisplayName(entity, code);
    final active = _bool(entity, 'isActive');
    await _db.customStatement(
      '''INSERT INTO sync_warehouse_directory(
        warehouse_id,organization_id,branch_id,code,name,location_kind,is_active)
        VALUES(?,?,?,?,?,?,?)
        ON CONFLICT(warehouse_id) DO UPDATE SET code=excluded.code,
          name=excluded.name,location_kind=excluded.location_kind,
          is_active=excluded.is_active,updated_at=CURRENT_TIMESTAMP''',
      [
        warehouseId,
        organizationId,
        branchId,
        code,
        name,
        locationKind,
        active ? 1 : 0,
      ],
    );

    // Every sellable branch location and every physical warehouse belonging
    // to this branch share this branch writer. Materialize routing identities
    // locally with a zero balance; stock is never copied from the coordinator.
    final localBranch = await _db
        .customSelect('SELECT branch_id FROM business_contexts WHERE id=1')
        .map((row) => row.read<String>('branch_id'))
        .getSingle();
    if (branchId == localBranch) {
      await _db.customStatement(
        '''INSERT INTO business_warehouses(
          id,organization_id,branch_id,code,name,location_kind,is_active)
          VALUES(?,?,?,?,?,?,?)
          ON CONFLICT(id) DO UPDATE SET code=excluded.code,name=excluded.name,
            location_kind=excluded.location_kind,is_active=excluded.is_active''',
        [
          warehouseId,
          organizationId,
          branchId,
          code,
          name,
          locationKind,
          active ? 1 : 0,
        ],
      );
    }
  }

  static String _uuidField(Map<String, Object?> map, String key) {
    final value = map[key]?.toString() ?? '';
    if (!Uuid.isValidUUID(fromString: value)) {
      throw OfflineSyncException(
        'invalid_location_field',
        'The location field $key is invalid.',
      );
    }
    return value.toLowerCase();
  }

  static String _text(Map<String, Object?> map, String key, int max) {
    final value = map[key]?.toString().trim() ?? '';
    if (value.isEmpty || value.length > max) {
      throw OfflineSyncException(
        'invalid_location_field',
        'The location field $key is invalid.',
      );
    }
    return value;
  }

  /// Early multi-location migrations allowed an empty display name for the
  /// automatically provisioned MAIN branch and warehouse. Their immutable
  /// codes remain valid identities, so accepting the code as the display name
  /// keeps old snapshots consumable without inventing or changing identity.
  static String _legacyDisplayName(
    Map<String, Object?> map,
    String fallbackCode,
  ) {
    final value = map['name']?.toString().trim() ?? '';
    if (value.length > 200) {
      throw const OfflineSyncException(
        'invalid_location_field',
        'The location field name is invalid.',
      );
    }
    return value.isEmpty ? fallbackCode : value;
  }

  static String _publishedName(String name, String code) {
    final normalized = name.trim();
    return normalized.isEmpty ? code.trim() : normalized;
  }

  static bool _bool(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! bool) {
      throw OfflineSyncException(
        'invalid_location_field',
        'The location field $key is invalid.',
      );
    }
    return value;
  }
}
