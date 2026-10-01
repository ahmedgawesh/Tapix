import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import '../lan/lan_models.dart';
import '../sync/offline_sync_event_store.dart';
import '../sync/sync_inbound_projection_service.dart';
import 'online_sync_gateway.dart';

abstract interface class OnlineConnectionVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Stores the whole binding in one secure record, never in plain app settings.
class SecureOnlineConnectionVault implements OnlineConnectionVault {
  const SecureOnlineConnectionVault({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;
  final FlutterSecureStorage _storage;
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Durable online synchronization for an already provisioned local writer.
///
/// Reuses the existing immutable outbox, inbox and operational projection. It
/// never adopts a new company identity or changes a LAN enrollment. New company
/// bootstrap and the customer-facing setup screen remain separate release gates.
class OnlineBranchSyncService {
  OnlineBranchSyncService({
    required AppDatabase database,
    required SyncInboundProjectionService projection,
    required Future<void> Function() authorizeConfiguration,
    OnlineConnectionVault vault = const SecureOnlineConnectionVault(),
    this.allowLoopbackDevelopment = false,
    DateTime Function()? clock,
  }) : _db = database,
       _events = OfflineSyncEventStore(database),
       _projection = projection,
       _authorizeConfiguration = authorizeConfiguration,
       _vault = vault,
       _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final OfflineSyncEventStore _events;
  final SyncInboundProjectionService _projection;
  final Future<void> Function() _authorizeConfiguration;
  final OnlineConnectionVault _vault;
  final bool allowLoopbackDevelopment;
  final DateTime Function() _clock;
  Future<LanBranchSyncRunResult>? _running;
  bool _configuring = false;

  Future<({String database, String organization, String branch})>
  _identity() async {
    final row = await _db.customSelect(
      '''SELECT s.database_id,s.organization_id,s.branch_id
      FROM sync_local_state s JOIN business_contexts b ON b.id=s.id
      AND b.database_id=s.database_id AND b.organization_id=s.organization_id
      AND b.branch_id=s.branch_id WHERE s.id=1''',
    ).getSingleOrNull();
    if (row == null || !await _events.isWriterRecordingEnabled()) {
      throw const OnlineSyncException('online_writer_not_enrolled');
    }
    return (
      database: row.read<String>('database_id'),
      organization: row.read<String>('organization_id'),
      branch: row.read<String>('branch_id'),
    );
  }

  String _key(String database) => 'online.branch.connection.v1.$database';

  OnlineSyncGateway _gateway(Uri endpoint, String organization) =>
      OnlineSyncGateway(
        endpoint: endpoint,
        organizationId: organization,
        allowLoopbackDevelopment: allowLoopbackDevelopment,
      );

  void _checkSession(
    OnlineWriterSession session,
    ({String database, String organization, String branch}) local,
  ) {
    final expectedRelay = const Uuid().v5(
      Namespace.url.value,
      'tapbix:online-relay:${local.organization}',
    );
    if (session.organizationId != local.organization ||
        session.databaseId != local.database ||
        session.branchId != local.branch ||
        session.relayId != expectedRelay ||
        session.relayId == local.database) {
      throw const OnlineSyncException('online_identity_mismatch');
    }
  }

  /// Configures an existing writer using a server-issued credential. The owner
  /// uses its provisioned credential; branch invitations use [connectInvitation].
  Future<OnlineWriterSession> connect({
    required Uri endpoint,
    required String accessToken,
  }) => _configure(endpoint: endpoint, accessToken: accessToken);

  Future<OnlineWriterSession> connectInvitation({
    required Uri endpoint,
    required String invitationCode,
  }) => _configure(endpoint: endpoint, invitationCode: invitationCode);

  Future<OnlineWriterSession> _configure({
    required Uri endpoint,
    String? accessToken,
    String? invitationCode,
  }) async {
    if (_configuring || _running != null) {
      throw const OnlineSyncException('online_sync_busy');
    }
    _configuring = true;
    try {
      await _authorizeConfiguration();
      final local = await _identity();
      final gateway = _gateway(endpoint, local.organization);
      try {
        final token =
            accessToken ??
            await gateway.enroll(
              databaseId: local.database,
              branchId: local.branch,
              invitationCode: invitationCode!,
            );
        final auth = LanBranchSyncAuth(
          enrollmentId: local.database,
          remoteDatabaseId: local.database,
          accessToken: token,
        );
        final session = await gateway.inspectSession(auth);
        _checkSession(session, local);
        await _events.registerDeliveryPeer(
          targetDatabaseId: session.relayId,
          organizationId: local.organization,
          branchId: local.branch,
          relayRemoteEvents: false,
        );
        await _vault.write(
          _key(local.database),
          jsonEncode({
            'endpoint': endpoint.toString(),
            'databaseId': local.database,
            'organizationId': local.organization,
            'branchId': local.branch,
            'relayId': session.relayId,
            'accessToken': token,
          }),
        );
        return session;
      } finally {
        gateway.close();
      }
    } finally {
      _configuring = false;
    }
  }

  /// Coalesces concurrent refreshes. Acknowledgement follows durable local
  /// application, so a lost network response can be safely retried after restart.
  Future<LanBranchSyncRunResult> synchronizeOnce() {
    if (_configuring) {
      return Future.error(const OnlineSyncException('online_sync_busy'));
    }
    return _running ??= _synchronize().whenComplete(() => _running = null);
  }

  Future<LanBranchSyncRunResult> _synchronize() async {
    final local = await _identity();
    final raw = await _vault.read(_key(local.database));
    if (raw == null) throw const OnlineSyncException('online_not_configured');
    Map<String, dynamic> config;
    try {
      config = jsonDecode(raw) as Map<String, dynamic>;
      if (config['databaseId'] != local.database ||
          config['organizationId'] != local.organization ||
          config['branchId'] != local.branch ||
          config['endpoint'] is! String ||
          config['accessToken'] is! String ||
          (config['accessToken'] as String).isEmpty) {
        throw const FormatException();
      }
    } catch (_) {
      throw const OnlineSyncException('online_connection_invalid');
    }
    final gateway = _gateway(
      Uri.parse(config['endpoint'] as String),
      local.organization,
    );
    final auth = LanBranchSyncAuth(
      enrollmentId: local.database,
      remoteDatabaseId: local.database,
      accessToken: config['accessToken'] as String,
    );
    try {
      final session = await gateway.inspectSession(auth);
      _checkSession(session, local);
      if (config['relayId'] != session.relayId) {
        throw const OnlineSyncException('online_identity_mismatch');
      }
      final lease = const Uuid().v4();
      final outbound = await _events.claimDispatchBatchForPeer(
        targetDatabaseId: session.relayId,
        leaseToken: lease,
        limit: 50,
        leaseDuration: const Duration(minutes: 2),
        now: _clock(),
      );
      if (outbound.isNotEmpty) {
        try {
          final result = await gateway.push(
            auth,
            outbound.map((e) => e.toJson()).toList(),
          );
          final accepted = result.acceptedEventIds.toSet();
          if (accepted.length != outbound.length ||
              result.acceptedEventIds.length != outbound.length ||
              outbound.any((e) => !accepted.contains(e.eventId))) {
            throw const OnlineSyncException(
              'unexpected_online_acknowledgement',
            );
          }
          // An interrupted local acknowledgement transaction rolls back all
          // items, letting the remote idempotency check verify the batch again.
          await _db.transaction(() async {
            for (final event in outbound) {
              await _events.acknowledgeForPeer(
                targetDatabaseId: session.relayId,
                eventId: event.eventId,
                leaseToken: lease,
                deliveredAt: _clock(),
              );
            }
          });
        } catch (error) {
          final code = error is OnlineSyncException
              ? error.code
              : 'online_sync_failed';
          for (final event in outbound) {
            try {
              await _events.recordPeerFailure(
                targetDatabaseId: session.relayId,
                eventId: event.eventId,
                leaseToken: lease,
                error: code,
                retryAt: _clock().toUtc().add(const Duration(seconds: 5)),
                // A long network outage must not permanently strand the head.
                maxAttempts: 2147483647,
              );
            } catch (_) {
              // Expiration of the original lease remains the recovery path.
            }
          }
          rethrow;
        }
      }
      final incoming = await gateway.pull(auth);
      if (incoming.events.isNotEmpty && incoming.leaseToken.isEmpty) {
        throw const OnlineSyncException('invalid_online_response');
      }
      final appliedIds = <String>[];
      for (final raw in incoming.events) {
        final event = SyncEventEnvelope.fromJson(raw);
        // Only this authenticated company relay may introduce a remote stream.
        await _events.enrollSource(
          sourceDatabaseId: event.sourceDatabaseId,
          organizationId: event.organizationId,
          branchId: event.branchId,
        );
        await _projection.apply(event);
        appliedIds.add(event.eventId);
      }
      if (appliedIds.isNotEmpty) {
        await gateway.acknowledge(
          auth,
          leaseToken: incoming.leaseToken,
          eventIds: appliedIds,
        );
      }
      return LanBranchSyncRunResult(
        uploaded: outbound.length,
        downloaded: appliedIds.length,
      );
    } finally {
      gateway.close();
    }
  }
}
