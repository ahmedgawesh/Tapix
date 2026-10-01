import 'dart:convert';

import 'package:tapbix_sync_contracts/tapbix_sync_contracts.dart';

export 'package:tapbix_sync_contracts/tapbix_sync_contracts.dart'
    show OfflineSyncException, SyncEventEnvelope;
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';

enum InboundSyncResult { applied, duplicate }

/// Local transactional event ledger. Business writers use [transaction] so
/// their mutation and the outbox append commit or roll back together.
class OfflineSyncEventStore {
  OfflineSyncEventStore(this._db, {Uuid uuid = const Uuid()}) : _uuid = uuid;
  final AppDatabase _db;
  final Uuid _uuid;

  Future<T> transaction<T>(
    Future<T> Function(OfflineSyncTransaction transaction) action,
  ) => _db.transaction(() => action(OfflineSyncTransaction._(_db, _uuid)));

  /// Records the coordinator provisioning decision that enables local outbox
  /// capture. The record is immutable and is intentionally absent for normal
  /// single-branch installations. Independent LAN branches use the local Pro
  /// coordinator; internet branches use the separately entitled coordinator.
  Future<void> activateWriterRecording({required String enrollmentId}) async {
    final normalized = enrollmentId.trim().toLowerCase();
    if (!Uuid.isValidUUID(fromString: normalized)) {
      throw const OfflineSyncException(
        'invalid_writer_enrollment',
        'The writer enrollment identifier must be a UUID.',
      );
    }
    final local = await _localIdentity();
    await _db.transaction(() async {
      final existing = await _db
          .customSelect(
            'SELECT enrollment_id,database_id,organization_id,branch_id '
            'FROM sync_writer_enrollment WHERE id=1',
          )
          .getSingleOrNull();
      if (existing != null) {
        if (existing.read<String>('enrollment_id') == normalized &&
            existing.read<String>('database_id') == local.databaseId &&
            existing.read<String>('organization_id') == local.organizationId &&
            existing.read<String>('branch_id') == local.branchId) {
          return;
        }
        throw const OfflineSyncException(
          'writer_enrollment_conflict',
          'This database is already bound to another writer enrollment.',
        );
      }
      await _db.customStatement(
        'INSERT INTO sync_writer_enrollment(id,enrollment_id,database_id,'
        'organization_id,branch_id) VALUES(1,?,?,?,?)',
        [normalized, local.databaseId, local.organizationId, local.branchId],
      );
    });
  }

  Future<bool> isWriterRecordingEnabled() async =>
      await _db
          .customSelect(
            'SELECT 1 AS enabled FROM sync_writer_enrollment WHERE id=1',
          )
          .getSingleOrNull() !=
      null;

  /// Registers one durable destination for this database's local stream.
  ///
  /// Every destination owns an independent cursor and retry state. Existing
  /// events are backfilled from [firstSequence], which lets a newly enrolled
  /// branch initialize from the immutable company stream without changing the
  /// event or marking it delivered for another branch.
  Future<void> registerDeliveryPeer({
    required String targetDatabaseId,
    required String organizationId,
    required String branchId,
    int firstSequence = 1,
    bool relayRemoteEvents = true,
  }) async {
    final target = targetDatabaseId.trim().toLowerCase();
    final organization = organizationId.trim().toLowerCase();
    final branch = branchId.trim().toLowerCase();
    if (!Uuid.isValidUUID(fromString: target) ||
        !Uuid.isValidUUID(fromString: organization) ||
        !Uuid.isValidUUID(fromString: branch) ||
        firstSequence <= 0) {
      throw const OfflineSyncException(
        'invalid_delivery_peer',
        'The delivery peer identity or first sequence is invalid.',
      );
    }
    final local = await _localIdentity();
    if (target == local.databaseId) {
      throw const OfflineSyncException(
        'local_database_cannot_be_target',
        'A database cannot deliver its stream to itself.',
      );
    }
    if (organization != local.organizationId) {
      throw const OfflineSyncException(
        'organization_mismatch',
        'The delivery peer belongs to another organization.',
      );
    }
    await _db.transaction(() async {
      final existing = await _db
          .customSelect(
            'SELECT organization_id,branch_id,first_sequence,status,relay_remote_events '
            'FROM sync_delivery_peers WHERE target_database_id=?',
            variables: [Variable.withString(target)],
          )
          .getSingleOrNull();
      if (existing != null) {
        if (existing.read<String>('organization_id') != organization ||
            existing.read<String>('branch_id') != branch ||
            existing.read<int>('first_sequence') != firstSequence ||
            existing.read<int>('relay_remote_events') !=
                (relayRemoteEvents ? 1 : 0) ||
            existing.read<String>('status') == 'revoked') {
          throw const OfflineSyncException(
            'delivery_peer_conflict',
            'The target database is already registered differently.',
          );
        }
        if (existing.read<String>('status') == 'quarantined') {
          await _db.customStatement(
            "UPDATE sync_delivery_peers SET status='active',updated_at=? "
            'WHERE target_database_id=?',
            [DateTime.now().toUtc().toIso8601String(), target],
          );
        }
      } else {
        await _db.customStatement(
          'INSERT INTO sync_delivery_peers(target_database_id,'
          'organization_id,branch_id,first_sequence,relay_remote_events) VALUES(?,?,?,?,?)',
          [
            target,
            organization,
            branch,
            firstSequence,
            relayRemoteEvents ? 1 : 0,
          ],
        );
      }
      await _db.customStatement(
        '''INSERT OR IGNORE INTO sync_outbox_deliveries(
          target_database_id,event_id,source_sequence,next_attempt_at)
          SELECT ?,event_id,local_sequence,next_attempt_at
          FROM sync_outbox_events WHERE local_sequence>=?''',
        [target, firstSequence],
      );
      if (relayRemoteEvents) {
        await _db.customStatement(
          '''INSERT OR IGNORE INTO sync_relay_deliveries(
          target_database_id,event_id,source_database_id,source_sequence,
          next_attempt_at)
          SELECT ?,event_id,source_database_id,source_sequence,
            CASE WHEN datetime(occurred_at)<=datetime(projected_at)
              THEN occurred_at ELSE projected_at END
          FROM sync_remote_event_projections
          WHERE organization_id=? AND source_database_id<>?''',
          [target, organization, target],
        );
      }
    });
  }

  /// Stages an accepted remote event for every other active branch database.
  ///
  /// The original envelope is relayed unchanged, so the receiving database
  /// advances the original source checkpoint and can detect gaps correctly.
  /// Calling this after a duplicate push is safe and repairs a coordinator
  /// interruption that happened after projection but before fan-out.
  Future<void> stageRelayDeliveries(SyncEventEnvelope event) async {
    _validate(event);
    final local = await _localIdentity();
    if (event.organizationId != local.organizationId ||
        event.sourceDatabaseId == local.databaseId) {
      throw const OfflineSyncException(
        'invalid_relay_source',
        'Only a projected remote event from this organization can be relayed.',
      );
    }
    await _db.transaction(() async {
      final projection = await _db
          .customSelect(
            'SELECT source_database_id,source_sequence,event_hash FROM '
            'sync_remote_event_projections WHERE event_id=?',
            variables: [Variable.withString(event.eventId)],
          )
          .getSingleOrNull();
      if (projection == null ||
          projection.read<String>('source_database_id') !=
              event.sourceDatabaseId ||
          projection.read<int>('source_sequence') != event.sequence ||
          projection.read<String>('event_hash') != event.eventHash) {
        throw const OfflineSyncException(
          'relay_projection_mismatch',
          'The relay event does not match its durable projection.',
        );
      }
      await _db.customStatement(
        '''INSERT OR IGNORE INTO sync_relay_deliveries(
          target_database_id,event_id,source_database_id,source_sequence,
          next_attempt_at)
          SELECT target_database_id,?,?,?,?
          FROM sync_delivery_peers
          WHERE status='active' AND relay_remote_events=1 AND organization_id=?
            AND target_database_id<>?''',
        [
          event.eventId,
          event.sourceDatabaseId,
          event.sequence,
          (event.occurredAt.isBefore(DateTime.now().toUtc())
                  ? event.occurredAt
                  : DateTime.now().toUtc())
              .toIso8601String(),
          event.organizationId,
          event.sourceDatabaseId,
        ],
      );
    });
  }

  /// Claims the contiguous head for one peer without affecting any other
  /// destination. A failed or leased head blocks later events for that peer.
  Future<List<SyncEventEnvelope>> claimDispatchBatchForPeer({
    required String targetDatabaseId,
    required String leaseToken,
    int limit = 50,
    Duration leaseDuration = const Duration(minutes: 2),
    DateTime? now,
  }) async {
    final target = targetDatabaseId.trim().toLowerCase();
    if (!Uuid.isValidUUID(fromString: target) ||
        leaseToken.trim().isEmpty ||
        limit <= 0 ||
        leaseDuration <= Duration.zero) {
      throw const OfflineSyncException(
        'invalid_peer_lease',
        'Invalid peer outbox lease.',
      );
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final until = clock.add(leaseDuration).toIso8601String();
    return _db.transaction(() async {
      final peer = await _db
          .customSelect(
            'SELECT status FROM sync_delivery_peers WHERE target_database_id=?',
            variables: [Variable.withString(target)],
          )
          .getSingleOrNull();
      if (peer == null || peer.read<String>('status') != 'active') {
        throw const OfflineSyncException(
          'delivery_peer_inactive',
          'The delivery peer is missing or inactive.',
        );
      }
      final rows = await _db
          .customSelect(
            '''SELECT e.*,
          d.state AS delivery_state,d.next_attempt_at AS delivery_next_attempt_at,
          d.lease_until AS delivery_lease_until
          FROM sync_outbox_deliveries d
          JOIN sync_outbox_events e ON e.event_id=d.event_id
          WHERE d.target_database_id=? AND d.state<>'delivered'
          ORDER BY d.source_sequence''',
            variables: [Variable.withString(target)],
          )
          .get();
      final claimed = <QueryRow>[];
      for (final row in rows) {
        if (claimed.length == limit) break;
        final state = row.read<String>('delivery_state');
        if (state == 'dead_letter') break;
        final eligible = state == 'pending'
            ? !DateTime.parse(
                row.read<String>('delivery_next_attempt_at'),
              ).toUtc().isAfter(clock)
            : state == 'leased' &&
                  !DateTime.parse(
                    row.read<String>('delivery_lease_until'),
                  ).toUtc().isAfter(clock);
        if (!eligible) break;
        claimed.add(row);
      }
      for (final row in claimed) {
        await _db.customStatement(
          "UPDATE sync_outbox_deliveries SET state='leased',"
          'attempt_count=attempt_count+1,lease_token=?,lease_until=?,'
          'last_error=NULL WHERE target_database_id=? AND event_id=?',
          [leaseToken, until, target, row.read<String>('event_id')],
        );
      }
      return claimed.map(_fromRow).toList(growable: false);
    });
  }

  /// Claims relay work independently per original source stream. A blocked
  /// source never blocks another source, but later events from the same source
  /// cannot overtake its pending, leased, or dead-letter head.
  Future<List<SyncEventEnvelope>> claimRelayBatchForPeer({
    required String targetDatabaseId,
    required String leaseToken,
    int limit = 50,
    Duration leaseDuration = const Duration(minutes: 2),
    DateTime? now,
  }) async {
    final target = targetDatabaseId.trim().toLowerCase();
    if (!Uuid.isValidUUID(fromString: target) ||
        leaseToken.trim().isEmpty ||
        limit <= 0 ||
        leaseDuration <= Duration.zero) {
      throw const OfflineSyncException(
        'invalid_peer_lease',
        'Invalid peer relay lease.',
      );
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final until = clock.add(leaseDuration).toIso8601String();
    return _db.transaction(() async {
      final peer = await _db
          .customSelect(
            'SELECT status FROM sync_delivery_peers WHERE target_database_id=?',
            variables: [Variable.withString(target)],
          )
          .getSingleOrNull();
      if (peer == null || peer.read<String>('status') != 'active') {
        throw const OfflineSyncException(
          'delivery_peer_inactive',
          'The delivery peer is missing or inactive.',
        );
      }
      final rows = await _db
          .customSelect(
            '''SELECT p.*,
          d.state AS delivery_state,d.next_attempt_at AS delivery_next_attempt_at,
          d.lease_until AS delivery_lease_until
          FROM sync_relay_deliveries d
          JOIN sync_remote_event_projections p ON p.event_id=d.event_id
          WHERE d.target_database_id=? AND d.state<>'delivered'
          ORDER BY d.source_database_id,d.source_sequence''',
            variables: [Variable.withString(target)],
          )
          .get();
      final claimed = <QueryRow>[];
      final blockedSources = <String>{};
      for (final row in rows) {
        if (claimed.length == limit) break;
        final source = row.read<String>('source_database_id');
        if (blockedSources.contains(source)) continue;
        final state = row.read<String>('delivery_state');
        if (state == 'dead_letter') {
          blockedSources.add(source);
          continue;
        }
        final eligible = state == 'pending'
            ? !DateTime.parse(
                row.read<String>('delivery_next_attempt_at'),
              ).toUtc().isAfter(clock)
            : state == 'leased' &&
                  !DateTime.parse(
                    row.read<String>('delivery_lease_until'),
                  ).toUtc().isAfter(clock);
        if (!eligible) {
          blockedSources.add(source);
          continue;
        }
        claimed.add(row);
      }
      for (final row in claimed) {
        await _db.customStatement(
          "UPDATE sync_relay_deliveries SET state='leased',"
          'attempt_count=attempt_count+1,lease_token=?,lease_until=?,'
          'last_error=NULL WHERE target_database_id=? AND event_id=?',
          [leaseToken, until, target, row.read<String>('event_id')],
        );
      }
      return claimed.map(_fromProjectionRow).toList(growable: false);
    });
  }

  Future<void> acknowledgeForPeer({
    required String targetDatabaseId,
    required String eventId,
    required String leaseToken,
    DateTime? deliveredAt,
  }) async {
    final target = targetDatabaseId.trim().toLowerCase();
    var changed = await _db.customUpdate(
      "UPDATE sync_outbox_deliveries SET state='delivered',lease_token=NULL,"
      'lease_until=NULL,delivered_at=?,last_error=NULL '
      "WHERE target_database_id=? AND event_id=? AND state='leased' AND lease_token=?",
      variables: [
        Variable.withString(
          (deliveredAt ?? DateTime.now()).toUtc().toIso8601String(),
        ),
        Variable.withString(target),
        Variable.withString(eventId),
        Variable.withString(leaseToken),
      ],
      updates: const {},
    );
    if (changed == 1) return;
    changed = await _db.customUpdate(
      "UPDATE sync_relay_deliveries SET state='delivered',lease_token=NULL,"
      'lease_until=NULL,delivered_at=?,last_error=NULL '
      "WHERE target_database_id=? AND event_id=? AND state='leased' AND lease_token=?",
      variables: [
        Variable.withString(
          (deliveredAt ?? DateTime.now()).toUtc().toIso8601String(),
        ),
        Variable.withString(target),
        Variable.withString(eventId),
        Variable.withString(leaseToken),
      ],
      updates: const {},
    );
    if (changed == 1) return;
    final alreadyDelivered = await _db
        .customSelect(
          '''SELECT 1 AS found FROM sync_outbox_deliveries
          WHERE target_database_id=? AND event_id=? AND state='delivered'
          UNION ALL
          SELECT 1 AS found FROM sync_relay_deliveries
          WHERE target_database_id=? AND event_id=? AND state='delivered'
          LIMIT 1''',
          variables: [
            Variable.withString(target),
            Variable.withString(eventId),
            Variable.withString(target),
            Variable.withString(eventId),
          ],
        )
        .getSingleOrNull();
    if (alreadyDelivered == null) throw _peerLeaseLost;
  }

  Future<void> recordPeerFailure({
    required String targetDatabaseId,
    required String eventId,
    required String leaseToken,
    required String error,
    required DateTime retryAt,
    int maxAttempts = 8,
  }) => _db.transaction(() async {
    if (maxAttempts <= 0) {
      throw const OfflineSyncException(
        'invalid_max_attempts',
        'The maximum attempt count must be positive.',
      );
    }
    final target = targetDatabaseId.trim().toLowerCase();
    final row = await _db
        .customSelect(
          'SELECT attempt_count FROM sync_outbox_deliveries '
          "WHERE target_database_id=? AND event_id=? AND state='leased' "
          'AND lease_token=?',
          variables: [
            Variable.withString(target),
            Variable.withString(eventId),
            Variable.withString(leaseToken),
          ],
        )
        .getSingleOrNull();
    if (row == null) throw _peerLeaseLost;
    final dead = row.read<int>('attempt_count') >= maxAttempts;
    final changed = await _db.customUpdate(
      'UPDATE sync_outbox_deliveries SET state=?,lease_token=NULL,'
      'lease_until=NULL,next_attempt_at=?,last_error=? '
      "WHERE target_database_id=? AND event_id=? AND state='leased' AND lease_token=?",
      variables: [
        Variable.withString(dead ? 'dead_letter' : 'pending'),
        Variable.withString(retryAt.toUtc().toIso8601String()),
        Variable.withString(
          error.trim().isEmpty ? 'unknown_sync_error' : error.trim(),
        ),
        Variable.withString(target),
        Variable.withString(eventId),
        Variable.withString(leaseToken),
      ],
      updates: const {},
    );
    if (changed != 1) throw _peerLeaseLost;
  });

  Future<void> enrollSource({
    required String sourceDatabaseId,
    required String organizationId,
    required String branchId,
    int startingSequence = 1,
  }) async {
    if (startingSequence <= 0) {
      throw const OfflineSyncException(
        'invalid_starting_sequence',
        'The starting sequence must be positive.',
      );
    }
    final local = await _localIdentity();
    if (sourceDatabaseId == local.databaseId) {
      throw const OfflineSyncException(
        'local_database_cannot_be_source',
        'A database cannot enroll itself as a remote source.',
      );
    }
    if (organizationId != local.organizationId) {
      throw const OfflineSyncException(
        'organization_mismatch',
        'The remote database belongs to a different organization.',
      );
    }
    await _db.transaction(() async {
      final row = await _db
          .customSelect(
            'SELECT organization_id,branch_id,next_sequence FROM '
            'sync_source_checkpoints WHERE source_database_id=?',
            variables: [Variable.withString(sourceDatabaseId)],
          )
          .getSingleOrNull();
      if (row != null) {
        if (row.read<String>('organization_id') != organizationId ||
            row.read<String>('branch_id') != branchId) {
          throw const OfflineSyncException(
            'source_enrollment_conflict',
            'The source is already enrolled with a different identity.',
          );
        }
        // Reconnecting an enrolled source must never rewind its checkpoint.
        return;
      }
      await _db.customStatement(
        'INSERT INTO sync_source_checkpoints(source_database_id,'
        'organization_id,branch_id,next_sequence) VALUES(?,?,?,?)',
        [sourceDatabaseId, organizationId, branchId, startingSequence],
      );
    });
  }

  /// Claims only the contiguous head of the stream. An unready, leased, or
  /// dead-letter event blocks later events and prevents out-of-order delivery.
  Future<List<SyncEventEnvelope>> claimDispatchBatch({
    required String leaseToken,
    int limit = 50,
    Duration leaseDuration = const Duration(minutes: 2),
    DateTime? now,
  }) async {
    if (leaseToken.trim().isEmpty ||
        limit <= 0 ||
        leaseDuration <= Duration.zero) {
      throw const OfflineSyncException(
        'invalid_lease',
        'Invalid outbox lease.',
      );
    }
    final clock = (now ?? DateTime.now()).toUtc();
    final until = clock.add(leaseDuration).toIso8601String();
    return _db.transaction(() async {
      final rows = await _db
          .customSelect(
            "SELECT * FROM sync_outbox_events WHERE state<>'delivered' "
            'ORDER BY local_sequence',
          )
          .get();
      final claimed = <QueryRow>[];
      for (final row in rows) {
        if (claimed.length == limit) break;
        final state = row.read<String>('state');
        if (state == 'dead_letter') break;
        final eligible = state == 'pending'
            ? !DateTime.parse(
                row.read<String>('next_attempt_at'),
              ).toUtc().isAfter(clock)
            : state == 'leased' &&
                  !DateTime.parse(
                    row.read<String>('lease_until'),
                  ).toUtc().isAfter(clock);
        if (!eligible) break;
        claimed.add(row);
      }
      for (final row in claimed) {
        await _db.customStatement(
          "UPDATE sync_outbox_events SET state='leased',"
          'attempt_count=attempt_count+1,lease_token=?,lease_until=?,'
          'last_error=NULL WHERE event_id=?',
          [leaseToken, until, row.read<String>('event_id')],
        );
      }
      return claimed.map(_fromRow).toList(growable: false);
    });
  }

  Future<void> acknowledge({
    required String eventId,
    required String leaseToken,
    DateTime? deliveredAt,
  }) async {
    final changed = await _db.customUpdate(
      "UPDATE sync_outbox_events SET state='delivered',lease_token=NULL,"
      'lease_until=NULL,delivered_at=?,last_error=NULL '
      "WHERE event_id=? AND state='leased' AND lease_token=?",
      variables: [
        Variable.withString(
          (deliveredAt ?? DateTime.now()).toUtc().toIso8601String(),
        ),
        Variable.withString(eventId),
        Variable.withString(leaseToken),
      ],
      updates: const {},
    );
    if (changed != 1) throw _leaseLost;
  }

  Future<void> recordFailure({
    required String eventId,
    required String leaseToken,
    required String error,
    required DateTime retryAt,
    int maxAttempts = 8,
  }) => _db.transaction(() async {
    if (maxAttempts <= 0) {
      throw const OfflineSyncException(
        'invalid_max_attempts',
        'The maximum attempt count must be positive.',
      );
    }
    final row = await _db
        .customSelect(
          'SELECT attempt_count FROM sync_outbox_events WHERE event_id=? '
          "AND state='leased' AND lease_token=?",
          variables: [
            Variable.withString(eventId),
            Variable.withString(leaseToken),
          ],
        )
        .getSingleOrNull();
    if (row == null) throw _leaseLost;
    final dead = row.read<int>('attempt_count') >= maxAttempts;
    final changed = await _db.customUpdate(
      'UPDATE sync_outbox_events SET state=?,lease_token=NULL,'
      'lease_until=NULL,next_attempt_at=?,last_error=? '
      "WHERE event_id=? AND state='leased' AND lease_token=?",
      variables: [
        Variable.withString(dead ? 'dead_letter' : 'pending'),
        Variable.withString(retryAt.toUtc().toIso8601String()),
        Variable.withString(
          error.trim().isEmpty ? 'unknown_sync_error' : error,
        ),
        Variable.withString(eventId),
        Variable.withString(leaseToken),
      ],
      updates: const {},
    );
    if (changed != 1) throw _leaseLost;
  });

  Future<InboundSyncResult> applyInbound({
    required SyncEventEnvelope event,
    required Future<void> Function(SyncEventEnvelope event) apply,
  }) async {
    _validate(event);
    final local = await _localIdentity();
    if (event.sourceDatabaseId == local.databaseId) {
      throw const OfflineSyncException(
        'looped_back_event',
        'A local event cannot be applied as remote.',
      );
    }
    if (event.organizationId != local.organizationId) {
      throw const OfflineSyncException(
        'organization_mismatch',
        'The event belongs to another organization.',
      );
    }
    return _db.transaction(() async {
      final prior = await _db
          .customSelect(
            'SELECT source_database_id,event_hash,state FROM '
            'sync_inbox_receipts WHERE event_id=?',
            variables: [Variable.withString(event.eventId)],
          )
          .getSingleOrNull();
      if (prior != null) {
        if (prior.read<String>('source_database_id') ==
                event.sourceDatabaseId &&
            prior.read<String>('event_hash') == event.eventHash &&
            prior.read<String>('state') == 'applied') {
          return InboundSyncResult.duplicate;
        }
        throw const OfflineSyncException(
          'event_identity_conflict',
          'The event identifier has different content.',
        );
      }
      final checkpoint = await _db
          .customSelect(
            'SELECT organization_id,branch_id,next_sequence,status FROM '
            'sync_source_checkpoints WHERE source_database_id=?',
            variables: [Variable.withString(event.sourceDatabaseId)],
          )
          .getSingleOrNull();
      if (checkpoint == null) {
        throw const OfflineSyncException(
          'source_not_enrolled',
          'The source database is not enrolled.',
        );
      }
      if (checkpoint.read<String>('status') != 'active') {
        throw const OfflineSyncException(
          'source_quarantined',
          'Source quarantined.',
        );
      }
      if (checkpoint.read<String>('organization_id') != event.organizationId ||
          checkpoint.read<String>('branch_id') != event.branchId) {
        throw const OfflineSyncException(
          'source_identity_conflict',
          'The event source does not match its enrollment.',
        );
      }
      final expected = checkpoint.read<int>('next_sequence');
      if (event.sequence != expected) {
        throw OfflineSyncException(
          event.sequence < expected
              ? 'stale_event_without_receipt'
              : 'event_gap',
          'Expected $expected but received ${event.sequence}.',
        );
      }
      await _db.customStatement(
        'INSERT INTO sync_inbox_receipts(event_id,source_database_id,'
        'organization_id,branch_id,source_sequence,event_type,aggregate_type,'
        "aggregate_id,contract_version,event_hash,state) VALUES(?,?,?,?,?,?,?,?,?,?,'applying')",
        [
          event.eventId,
          event.sourceDatabaseId,
          event.organizationId,
          event.branchId,
          event.sequence,
          event.eventType,
          event.aggregateType,
          event.aggregateId,
          event.contractVersion,
          event.eventHash,
        ],
      );
      await apply(event);
      final stamp = DateTime.now().toUtc().toIso8601String();
      await _db.customStatement(
        "UPDATE sync_inbox_receipts SET state='applied',applied_at=? WHERE event_id=?",
        [stamp, event.eventId],
      );
      await _db.customStatement(
        'UPDATE sync_source_checkpoints SET next_sequence=next_sequence+1,'
        'updated_at=? WHERE source_database_id=?',
        [stamp, event.sourceDatabaseId],
      );
      return InboundSyncResult.applied;
    });
  }

  Future<_LocalIdentity> _localIdentity() async {
    final row = await _db
        .customSelect(
          'SELECT database_id,organization_id,branch_id FROM sync_local_state WHERE id=1',
        )
        .getSingleOrNull();
    if (row == null) {
      throw const OfflineSyncException(
        'missing_local_identity',
        'The local synchronization identity is missing.',
      );
    }
    return _LocalIdentity(
      row.read<String>('database_id'),
      row.read<String>('organization_id'),
      row.read<String>('branch_id'),
    );
  }

  void _validate(SyncEventEnvelope event) {
    if (event.eventId.length != 36 ||
        event.sourceDatabaseId.length != 36 ||
        event.organizationId.length != 36 ||
        event.branchId.length != 36 ||
        event.sequence <= 0 ||
        event.contractVersion <= 0 ||
        event.eventType.trim().isEmpty ||
        event.aggregateType.trim().isEmpty ||
        event.aggregateId.trim().isEmpty) {
      throw const OfflineSyncException(
        'invalid_event_envelope',
        'Invalid event.',
      );
    }
    if (event.eventHash != OfflineSyncTransaction.eventHashFor(event)) {
      throw const OfflineSyncException(
        'event_hash_mismatch',
        'The event fingerprint is invalid.',
      );
    }
  }

  SyncEventEnvelope _fromRow(QueryRow row) => SyncEventEnvelope(
    eventId: row.read<String>('event_id'),
    sourceDatabaseId: row.read<String>('source_database_id'),
    organizationId: row.read<String>('organization_id'),
    branchId: row.read<String>('branch_id'),
    sequence: row.read<int>('local_sequence'),
    eventType: row.read<String>('event_type'),
    aggregateType: row.read<String>('aggregate_type'),
    aggregateId: row.read<String>('aggregate_id'),
    contractVersion: row.read<int>('contract_version'),
    payload: (jsonDecode(row.read<String>('payload_json')) as Map).map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    ),
    occurredAt: DateTime.parse(row.read<String>('occurred_at')).toUtc(),
    eventHash: row.read<String>('event_hash'),
  );

  SyncEventEnvelope _fromProjectionRow(QueryRow row) => SyncEventEnvelope(
    eventId: row.read<String>('event_id'),
    sourceDatabaseId: row.read<String>('source_database_id'),
    organizationId: row.read<String>('organization_id'),
    branchId: row.read<String>('branch_id'),
    sequence: row.read<int>('source_sequence'),
    eventType: row.read<String>('event_type'),
    aggregateType: row.read<String>('aggregate_type'),
    aggregateId: row.read<String>('aggregate_id'),
    contractVersion: row.read<int>('contract_version'),
    payload: (jsonDecode(row.read<String>('payload_json')) as Map).map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    ),
    occurredAt: DateTime.parse(row.read<String>('occurred_at')).toUtc(),
    eventHash: row.read<String>('event_hash'),
  );

  static const _leaseLost = OfflineSyncException(
    'lease_lost',
    'The event is no longer owned by this worker.',
  );
  static const _peerLeaseLost = OfflineSyncException(
    'peer_lease_lost',
    'The event is no longer leased to this peer worker.',
  );
}

class OfflineSyncTransaction {
  OfflineSyncTransaction._(this._db, this._uuid);
  final AppDatabase _db;
  final Uuid _uuid;

  Future<bool> isWriterRecordingEnabled() async =>
      await _db
          .customSelect(
            'SELECT 1 AS enabled FROM sync_writer_enrollment WHERE id=1',
          )
          .getSingleOrNull() !=
      null;

  Future<SyncEventEnvelope> append({
    required String eventType,
    required String aggregateType,
    required String aggregateId,
    required Map<String, Object?> payload,
    int contractVersion = 1,
    DateTime? occurredAt,
  }) => _append(
    eventType: eventType,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
    payload: payload,
    contractVersion: contractVersion,
    occurredAt: occurredAt,
  );

  /// Appends one immutable event for a business transition.
  ///
  /// Retrying the same [producerKey] returns the original event without
  /// consuming a sequence. Reusing it with different semantic content is a
  /// conflict, which protects callers from silently hiding a second posting.
  Future<SyncEventEnvelope> appendOnce({
    required String producerKey,
    required String eventType,
    required String aggregateType,
    required String aggregateId,
    required Map<String, Object?> payload,
    int contractVersion = 1,
    DateTime? occurredAt,
  }) => _append(
    producerKey: producerKey,
    eventType: eventType,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
    payload: payload,
    contractVersion: contractVersion,
    occurredAt: occurredAt,
  );

  Future<SyncEventEnvelope> _append({
    String? producerKey,
    required String eventType,
    required String aggregateType,
    required String aggregateId,
    required Map<String, Object?> payload,
    required int contractVersion,
    DateTime? occurredAt,
  }) async {
    if (eventType.trim().isEmpty ||
        aggregateType.trim().isEmpty ||
        aggregateId.trim().isEmpty ||
        contractVersion <= 0) {
      throw const OfflineSyncException(
        'invalid_local_event',
        'Invalid local event.',
      );
    }
    _validateJson(payload);
    final normalizedProducerKey = producerKey?.trim();
    if (producerKey != null &&
        (normalizedProducerKey!.isEmpty ||
            normalizedProducerKey.length > 256)) {
      throw const OfflineSyncException(
        'invalid_producer_key',
        'The producer key must contain between 1 and 256 characters.',
      );
    }
    final state = await _db
        .customSelect(
          'SELECT database_id,organization_id,branch_id,next_sequence '
          'FROM sync_local_state WHERE id=1',
        )
        .getSingle();
    final eventId = normalizedProducerKey == null
        ? _uuid.v4()
        : _uuid.v5(
            Namespace.url.value,
            'tapix-sync:${state.read<String>('database_id')}:$normalizedProducerKey',
          );
    if (normalizedProducerKey != null) {
      final existing = await _db
          .customSelect(
            'SELECT * FROM sync_outbox_events WHERE event_id=?',
            variables: [Variable.withString(eventId)],
          )
          .getSingleOrNull();
      if (existing != null) {
        final event = _eventFromRow(existing);
        final samePayload =
            jsonEncode(_canonical(event.payload)) ==
            jsonEncode(_canonical(payload));
        if (event.eventType == eventType.trim() &&
            event.aggregateType == aggregateType.trim() &&
            event.aggregateId == aggregateId.trim() &&
            event.contractVersion == contractVersion &&
            samePayload) {
          return event;
        }
        throw const OfflineSyncException(
          'producer_key_conflict',
          'The producer key is already bound to different event content.',
        );
      }
    }
    final sequence = state.read<int>('next_sequence');
    await _db.customStatement(
      'UPDATE sync_local_state SET next_sequence=next_sequence+1 WHERE id=1',
    );
    final draft = SyncEventEnvelope(
      eventId: eventId,
      sourceDatabaseId: state.read<String>('database_id'),
      organizationId: state.read<String>('organization_id'),
      branchId: state.read<String>('branch_id'),
      sequence: sequence,
      eventType: eventType.trim(),
      aggregateType: aggregateType.trim(),
      aggregateId: aggregateId.trim(),
      contractVersion: contractVersion,
      payload: Map.unmodifiable(payload),
      occurredAt: (occurredAt ?? DateTime.now()).toUtc(),
      eventHash: '',
    );
    final event = SyncEventEnvelope(
      eventId: draft.eventId,
      sourceDatabaseId: draft.sourceDatabaseId,
      organizationId: draft.organizationId,
      branchId: draft.branchId,
      sequence: draft.sequence,
      eventType: draft.eventType,
      aggregateType: draft.aggregateType,
      aggregateId: draft.aggregateId,
      contractVersion: draft.contractVersion,
      payload: draft.payload,
      occurredAt: draft.occurredAt,
      eventHash: eventHashFor(draft),
    );
    final stamp = event.occurredAt.toIso8601String();
    final queuedAt = DateTime.now().toUtc();
    final readyAt =
        (event.occurredAt.isBefore(queuedAt) ? event.occurredAt : queuedAt)
            .toIso8601String();
    await _db.customStatement(
      'INSERT INTO sync_outbox_events(event_id,source_database_id,'
      'organization_id,branch_id,local_sequence,event_type,aggregate_type,'
      'aggregate_id,contract_version,payload_json,event_hash,occurred_at,'
      'next_attempt_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        event.eventId,
        event.sourceDatabaseId,
        event.organizationId,
        event.branchId,
        event.sequence,
        event.eventType,
        event.aggregateType,
        event.aggregateId,
        event.contractVersion,
        jsonEncode(_canonical(event.payload)),
        event.eventHash,
        stamp,
        readyAt,
      ],
    );
    await _db.customStatement(
      '''INSERT OR IGNORE INTO sync_outbox_deliveries(
        target_database_id,event_id,source_sequence,next_attempt_at)
        SELECT target_database_id,?,?,?
        FROM sync_delivery_peers WHERE status='active' AND ?>=first_sequence''',
      [event.eventId, event.sequence, readyAt, event.sequence],
    );
    return event;
  }

  static SyncEventEnvelope _eventFromRow(QueryRow row) => SyncEventEnvelope(
    eventId: row.read<String>('event_id'),
    sourceDatabaseId: row.read<String>('source_database_id'),
    organizationId: row.read<String>('organization_id'),
    branchId: row.read<String>('branch_id'),
    sequence: row.read<int>('local_sequence'),
    eventType: row.read<String>('event_type'),
    aggregateType: row.read<String>('aggregate_type'),
    aggregateId: row.read<String>('aggregate_id'),
    contractVersion: row.read<int>('contract_version'),
    payload: (jsonDecode(row.read<String>('payload_json')) as Map).map(
      (key, value) => MapEntry(key.toString(), value as Object?),
    ),
    occurredAt: DateTime.parse(row.read<String>('occurred_at')).toUtc(),
    eventHash: row.read<String>('event_hash'),
  );

  static String eventHashFor(SyncEventEnvelope event) =>
      SyncWireContract.eventHashFor(event);
  static Object? _canonical(Object? value) => SyncWireContract.canonical(value);
  static void _validateJson(Object? value) =>
      SyncWireContract.validateJson(value);
}

class _LocalIdentity {
  const _LocalIdentity(this.databaseId, this.organizationId, this.branchId);
  final String databaseId;
  final String organizationId;
  final String branchId;
}
