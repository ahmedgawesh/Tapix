import 'package:tapbix_sync_contracts/tapbix_sync_contracts.dart'
    show SyncWireContract;
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import 'offline_sync_event_store.dart';

/// Applies one remote envelope exactly once and keeps the canonical payload for
/// consolidated reports and deterministic recovery.
///
/// This projection is deliberately read-only. Financial and inventory events
/// remain owned by their source branch; special operational projectors (such
/// as an inter-branch transfer arriving at its destination) are invoked inside
/// the same inbox transaction through the optional operational projector.
class SyncInboundProjectionService {
  SyncInboundProjectionService(
    this._db,
    this._events, {
    Future<void> Function(SyncEventEnvelope event)? operationalProjector,
    Future<void> Function(SyncEventEnvelope event)? appliedObserver,
  }) : _operationalProjector = operationalProjector,
       _appliedObserver = appliedObserver;

  final AppDatabase _db;
  final OfflineSyncEventStore _events;
  final Future<void> Function(SyncEventEnvelope event)? _operationalProjector;
  final Future<void> Function(SyncEventEnvelope event)? _appliedObserver;

  static const supportedContracts = SyncWireContract.supportedContracts;

  Future<InboundSyncResult> apply(SyncEventEnvelope event) async {
    final result = await _events.applyInbound(
      event: event,
      apply: (envelope) async {
        if (!supportedContracts.contains(envelope.eventType)) {
          throw OfflineSyncException(
            'unsupported_event_contract',
            'Unsupported synchronization contract: '
                '${envelope.eventType}.',
          );
        }
        await _validateDocumentLocation(envelope);
        await _db.customStatement(
          '''INSERT INTO sync_remote_event_projections(
              event_id,source_database_id,organization_id,branch_id,
              source_sequence,event_type,aggregate_type,aggregate_id,
              contract_version,payload_json,event_hash,occurred_at)
              VALUES(?,?,?,?,?,?,?,?,?,?,?,?)''',
          [
            envelope.eventId,
            envelope.sourceDatabaseId,
            envelope.organizationId,
            envelope.branchId,
            envelope.sequence,
            envelope.eventType,
            envelope.aggregateType,
            envelope.aggregateId,
            envelope.contractVersion,
            jsonEncode(_canonical(envelope.payload)),
            envelope.eventHash,
            envelope.occurredAt.toUtc().toIso8601String(),
          ],
        );
        await _operationalProjector?.call(envelope);
      },
    );
    if (result == InboundSyncResult.applied && _appliedObserver != null) {
      try {
        await _appliedObserver(event);
      } catch (_) {
        // A system notification is a convenience side effect. The immutable
        // event and operational projection are already committed and must not
        // be retried merely because the OS notification API was unavailable.
      }
    }
    return result;
  }

  Future<void> _validateDocumentLocation(SyncEventEnvelope event) async {
    final payloadBranch = event.payload['branchId']?.toString();
    if (payloadBranch != null &&
        payloadBranch.isNotEmpty &&
        payloadBranch != event.branchId) {
      throw const OfflineSyncException(
        'payload_branch_mismatch',
        'The document branch does not match the enrolled source branch.',
      );
    }
    final warehouseId = event.payload['warehouseId']?.toString();
    if (warehouseId == null || warehouseId.isEmpty) return;
    final count = await _db
        .customSelect(
          '''SELECT COUNT(*) AS n FROM business_warehouses
          WHERE id=? AND organization_id=? AND branch_id=?''',
          variables: [
            Variable.withString(warehouseId),
            Variable.withString(event.organizationId),
            Variable.withString(event.branchId),
          ],
        )
        .map((row) => row.read<int>('n'))
        .getSingle();
    if (count != 1) {
      throw const OfflineSyncException(
        'payload_warehouse_mismatch',
        'The document warehouse does not belong to its enrolled branch.',
      );
    }
  }

  Future<int> nextSequenceFor(String sourceDatabaseId) async {
    final row = await _db
        .customSelect(
          'SELECT next_sequence FROM sync_source_checkpoints '
          'WHERE source_database_id=?',
          variables: [Variable.withString(sourceDatabaseId)],
        )
        .getSingleOrNull();
    if (row == null) {
      throw const OfflineSyncException(
        'source_not_enrolled',
        'The source database is not enrolled.',
      );
    }
    return row.read<int>('next_sequence');
  }

  static Object? _canonical(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList()
        ..sort(
          (left, right) => left.key.toString().compareTo(right.key.toString()),
        );
      return <String, Object?>{
        for (final entry in entries)
          entry.key.toString(): _canonical(entry.value),
      };
    }
    if (value is List) {
      return value.map(_canonical).toList(growable: false);
    }
    return value;
  }
}
