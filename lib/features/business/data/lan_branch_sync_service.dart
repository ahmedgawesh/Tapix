import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/lan/lan_models.dart';
import '../../../core/services/sync/offline_sync_event_store.dart';
import '../../../core/services/sync/branch_catalogue_sync_service.dart';
import '../../../core/services/sync/branch_location_directory_sync_service.dart';
import '../../../core/services/sync/sync_inbound_projection_service.dart';

class LanBranchSyncException implements Exception {
  const LanBranchSyncException(this.code);

  final String code;

  @override
  String toString() => 'LanBranchSyncException($code)';
}

/// Coordinator authority for TLS branch event exchange.
///
/// Authentication is bound to enrollment id + remote database id + token.
/// Uploaded events are applied in source order. Coordinator events are leased
/// independently for this branch and remain pending until an explicit ack.
class LanBranchSyncService implements LanBranchSyncGateway {
  LanBranchSyncService({
    required AppDatabase database,
    required OfflineSyncEventStore events,
    required SyncInboundProjectionService projections,
    BranchCatalogueSyncService? catalogue,
    BranchLocationDirectorySyncService? locations,
    Uuid uuid = const Uuid(),
  }) : _db = database,
       _events = events,
       _projections = projections,
       _catalogue = catalogue,
       _locations = locations,
       _uuid = uuid;

  final AppDatabase _db;
  final OfflineSyncEventStore _events;
  final SyncInboundProjectionService _projections;
  final BranchCatalogueSyncService? _catalogue;
  final BranchLocationDirectorySyncService? _locations;
  final Uuid _uuid;

  @override
  Future<LanBranchSyncPushResult> push(
    LanBranchSyncAuth auth,
    List<Map<String, Object?>> events,
  ) async {
    final enrollment = await _authenticate(auth);
    if (events.length > 50) {
      throw const LanBranchSyncException('sync_batch_too_large');
    }
    final accepted = <String>[];
    for (final json in events) {
      late SyncEventEnvelope event;
      try {
        event = SyncEventEnvelope.fromJson(json);
      } catch (_) {
        throw const LanBranchSyncException('invalid_sync_event');
      }
      if (event.sourceDatabaseId != auth.remoteDatabaseId ||
          event.organizationId != enrollment.organizationId ||
          event.branchId != enrollment.branchId) {
        throw const LanBranchSyncException('sync_source_mismatch');
      }
      await _projections.apply(event);
      // This is intentionally idempotent and runs even when the inbox reports
      // a duplicate. If the coordinator stopped after persisting the inbound
      // projection but before fan-out, the sender's retry repairs delivery to
      // every other active branch without forging a coordinator-authored event.
      await _events.stageRelayDeliveries(event);
      accepted.add(event.eventId);
    }
    await _touch(auth.enrollmentId);
    return LanBranchSyncPushResult(
      acceptedEventIds: List.unmodifiable(accepted),
      nextExpectedSequence: await _projections.nextSequenceFor(
        auth.remoteDatabaseId,
      ),
    );
  }

  @override
  Future<LanBranchSyncPullResult> pull(
    LanBranchSyncAuth auth, {
    int limit = 50,
  }) async {
    await _authenticate(auth);
    if (limit <= 0 || limit > 50) {
      throw const LanBranchSyncException('invalid_sync_batch_limit');
    }
    // A pull is also the coordinator's safe publication boundary for shared
    // master data. Snapshot IDs are content-addressed and appendOnce makes
    // unchanged pulls a no-op, while product/customer/location edits become
    // available without copying any stock, party balance, or journal history.
    await _catalogue?.publishSnapshot();
    await _locations?.publishSnapshot();
    final lease = _uuid.v4().toLowerCase();
    final localEvents = await _events.claimDispatchBatchForPeer(
      targetDatabaseId: auth.remoteDatabaseId,
      leaseToken: lease,
      limit: limit,
    );
    final relayEvents = localEvents.length == limit
        ? const <SyncEventEnvelope>[]
        : await _events.claimRelayBatchForPeer(
            targetDatabaseId: auth.remoteDatabaseId,
            leaseToken: lease,
            limit: limit - localEvents.length,
          );
    final events = <SyncEventEnvelope>[...localEvents, ...relayEvents];
    await _touch(auth.enrollmentId);
    return LanBranchSyncPullResult(
      leaseToken: lease,
      events: List.unmodifiable(
        events.map((event) => event.toJson()).toList(growable: false),
      ),
    );
  }

  @override
  Future<void> acknowledge(
    LanBranchSyncAuth auth, {
    required String leaseToken,
    required List<String> eventIds,
  }) async {
    await _authenticate(auth);
    if (leaseToken.trim().isEmpty ||
        eventIds.isEmpty ||
        eventIds.length > 50 ||
        eventIds.any((id) => !Uuid.isValidUUID(fromString: id))) {
      throw const LanBranchSyncException('invalid_sync_acknowledgement');
    }
    for (final eventId in eventIds) {
      await _events.acknowledgeForPeer(
        targetDatabaseId: auth.remoteDatabaseId,
        eventId: eventId,
        leaseToken: leaseToken,
      );
    }
    await _touch(auth.enrollmentId);
  }

  Future<_EnrollmentIdentity> _authenticate(LanBranchSyncAuth auth) async {
    final enrollmentId = auth.enrollmentId.trim().toLowerCase();
    final remoteDatabaseId = auth.remoteDatabaseId.trim().toLowerCase();
    if (!Uuid.isValidUUID(fromString: enrollmentId) ||
        !Uuid.isValidUUID(fromString: remoteDatabaseId) ||
        auth.accessToken.length < 40 ||
        auth.accessToken.length > 128) {
      throw const LanBranchSyncException('branch_sync_denied');
    }
    final row = await _db
        .customSelect(
          '''SELECT organization_id,branch_id,remote_database_id,status
          FROM lan_branch_enrollments WHERE enrollment_id=?''',
          variables: [Variable.withString(enrollmentId)],
        )
        .getSingleOrNull();
    final recoveryCredential = await _db
        .customSelect(
          'SELECT token_hash FROM lan_branch_recovery_credentials '
          "WHERE enrollment_id=? AND status='active' "
          'ORDER BY generation DESC LIMIT 1',
          variables: [Variable.withString(enrollmentId)],
        )
        .getSingleOrNull();
    final originalCredential = recoveryCredential == null
        ? await _db
              .customSelect(
                'SELECT token_hash FROM lan_branch_sync_credentials '
                "WHERE enrollment_id=? AND status='active'",
                variables: [Variable.withString(enrollmentId)],
              )
              .getSingleOrNull()
        : null;
    final credential = recoveryCredential ?? originalCredential;
    final suppliedHash = sha256
        .convert(utf8.encode(auth.accessToken))
        .toString();
    if (row == null ||
        row.read<String>('status') != 'active' ||
        credential == null ||
        row.read<String>('remote_database_id') != remoteDatabaseId ||
        !_constantTimeEquals(
          credential.read<String>('token_hash'),
          suppliedHash,
        )) {
      throw const LanBranchSyncException('branch_sync_denied');
    }
    return _EnrollmentIdentity(
      organizationId: row.read<String>('organization_id'),
      branchId: row.read<String>('branch_id'),
    );
  }

  Future<void> _touch(String enrollmentId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final normalized = enrollmentId.trim().toLowerCase();
    await _db.customStatement(
      'UPDATE lan_branch_sync_credentials SET last_seen_at=? '
      "WHERE enrollment_id=? AND status='active'",
      [now, normalized],
    );
    await _db.customStatement(
      'UPDATE lan_branch_recovery_credentials SET last_seen_at=? '
      "WHERE enrollment_id=? AND status='active'",
      [now, normalized],
    );
  }

  bool _constantTimeEquals(String left, String right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}

class _EnrollmentIdentity {
  const _EnrollmentIdentity({
    required this.organizationId,
    required this.branchId,
  });

  final String organizationId;
  final String branchId;
}
