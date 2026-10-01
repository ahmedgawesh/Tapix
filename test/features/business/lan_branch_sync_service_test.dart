import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/lan/lan_models.dart';
import 'package:tapix/core/services/sync/branch_catalogue_sync_service.dart';
import 'package:tapix/core/services/sync/branch_location_directory_sync_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_entity_identity_store.dart';
import 'package:tapix/core/services/sync/sync_inbound_projection_service.dart';
import 'package:tapix/features/business/data/lan_branch_sync_service.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late OfflineSyncEventStore events;
  late LanBranchSyncService service;
  late String organizationId;

  const remoteDatabaseId = '11111111-1111-4111-8111-111111111111';
  const remoteBranchId = '22222222-2222-4222-8222-222222222222';
  const remoteWarehouseId = '33333333-3333-4333-8333-333333333333';
  const enrollmentId = '44444444-4444-4444-8444-444444444444';
  const token = 'secure-sync-token-012345678901234567890123456789';
  const secondDatabaseId = '77777777-7777-4777-8777-777777777777';
  const secondBranchId = '88888888-8888-4888-8888-888888888888';
  const secondWarehouseId = '99999999-9999-4999-8999-999999999999';
  const secondEnrollmentId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  const secondToken = 'second-sync-token-0123456789012345678901234567890';

  LanBranchSyncAuth auth([String accessToken = token]) => LanBranchSyncAuth(
    enrollmentId: enrollmentId,
    remoteDatabaseId: remoteDatabaseId,
    accessToken: accessToken,
  );

  LanBranchSyncAuth secondAuth() => const LanBranchSyncAuth(
    enrollmentId: secondEnrollmentId,
    remoteDatabaseId: secondDatabaseId,
    accessToken: secondToken,
  );

  setUp(() async {
    db = fixtures.memoryDb();
    await db.customSelect('SELECT 1').get();
    final context = await db
        .customSelect(
          'SELECT organization_id FROM business_contexts WHERE id=1',
        )
        .getSingle();
    organizationId = context.read<String>('organization_id');
    await db.customStatement(
      'INSERT INTO users(id,username,password_hash,role,is_active,created_at,updated_at) '
      "VALUES(91,'sync-owner','x','owner',1,0,0)",
    );
    await db.customStatement(
      'INSERT INTO business_branches(id,organization_id,code,name,is_active) '
      "VALUES(?,?,'REMOTE','Remote',1)",
      [remoteBranchId, organizationId],
    );
    await db.customStatement(
      'INSERT INTO business_warehouses('
      'id,organization_id,branch_id,code,name,is_active) '
      "VALUES(?,?,?,'REMOTE-MAIN','Remote main',1)",
      [remoteWarehouseId, organizationId, remoteBranchId],
    );
    await db.customStatement(
      'INSERT INTO business_branches(id,organization_id,code,name,is_active) '
      "VALUES(?,?,'SECOND','Second',1)",
      [secondBranchId, organizationId],
    );
    await db.customStatement(
      'INSERT INTO business_warehouses('
      'id,organization_id,branch_id,code,name,is_active) '
      "VALUES(?,?,?,'SECOND-MAIN','Second main',1)",
      [secondWarehouseId, organizationId, secondBranchId],
    );
    final coordinatorDatabaseId = await db
        .customSelect('SELECT database_id FROM business_contexts WHERE id=1')
        .map((row) => row.read<String>('database_id'))
        .getSingle();
    await db.customStatement(
      '''INSERT INTO lan_branch_enrollments(
        enrollment_id,organization_id,branch_id,warehouse_id,
        coordinator_database_id,secret_hash,status,issued_by,expires_at,
        remote_database_id,activated_at)
        VALUES(?,?,?,?,?,?,'active',?,?,?,?)''',
      [
        enrollmentId,
        organizationId,
        remoteBranchId,
        remoteWarehouseId,
        coordinatorDatabaseId,
        List.filled(64, 'a').join(),
        91,
        DateTime.utc(2026, 10, 1).toIso8601String(),
        remoteDatabaseId,
        DateTime.utc(2026, 9, 28).toIso8601String(),
      ],
    );
    await db.customStatement(
      'INSERT INTO lan_branch_sync_credentials('
      'enrollment_id,remote_database_id,token_hash) VALUES(?,?,?)',
      [
        enrollmentId,
        remoteDatabaseId,
        sha256.convert(token.codeUnits).toString(),
      ],
    );
    await db.customStatement(
      '''INSERT INTO lan_branch_enrollments(
        enrollment_id,organization_id,branch_id,warehouse_id,
        coordinator_database_id,secret_hash,status,issued_by,expires_at,
        remote_database_id,activated_at)
        VALUES(?,?,?,?,?,?,'active',?,?,?,?)''',
      [
        secondEnrollmentId,
        organizationId,
        secondBranchId,
        secondWarehouseId,
        coordinatorDatabaseId,
        List.filled(64, 'b').join(),
        91,
        DateTime.utc(2026, 10, 1).toIso8601String(),
        secondDatabaseId,
        DateTime.utc(2026, 9, 28).toIso8601String(),
      ],
    );
    await db.customStatement(
      'INSERT INTO lan_branch_sync_credentials('
      'enrollment_id,remote_database_id,token_hash) VALUES(?,?,?)',
      [
        secondEnrollmentId,
        secondDatabaseId,
        sha256.convert(secondToken.codeUnits).toString(),
      ],
    );
    events = OfflineSyncEventStore(db);
    await events.enrollSource(
      sourceDatabaseId: remoteDatabaseId,
      organizationId: organizationId,
      branchId: remoteBranchId,
    );
    await events.registerDeliveryPeer(
      targetDatabaseId: remoteDatabaseId,
      organizationId: organizationId,
      branchId: remoteBranchId,
    );
    await events.registerDeliveryPeer(
      targetDatabaseId: secondDatabaseId,
      organizationId: organizationId,
      branchId: secondBranchId,
    );
    service = LanBranchSyncService(
      database: db,
      events: events,
      projections: SyncInboundProjectionService(db, events),
    );
  });

  tearDown(() => db.close());

  test('authenticated branch pushes an ordered event exactly once', () async {
    final event = _remoteEvent(organizationId);
    final first = await service.push(auth(), [event.toJson()]);
    final retry = await service.push(auth(), [event.toJson()]);
    expect(first.acceptedEventIds, [event.eventId]);
    expect(retry.acceptedEventIds, [event.eventId]);
    expect(retry.nextExpectedSequence, 2);
    expect(
      await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM sync_remote_event_projections',
          )
          .map((row) => row.read<int>('n'))
          .getSingle(),
      1,
    );
  });

  test('wrong token and mismatched source are rejected', () async {
    await expectLater(
      service.pull(auth('wrong-token-that-is-long-enough-012345678901234567')),
      throwsA(
        isA<LanBranchSyncException>().having(
          (error) => error.code,
          'code',
          'branch_sync_denied',
        ),
      ),
    );
    final foreign = _remoteEvent(
      organizationId,
      sourceDatabaseId: '55555555-5555-4555-8555-555555555555',
    );
    await expectLater(
      service.push(auth(), [foreign.toJson()]),
      throwsA(
        isA<LanBranchSyncException>().having(
          (error) => error.code,
          'code',
          'sync_source_mismatch',
        ),
      ),
    );
  });

  test('pull lease and acknowledgement are retry safe', () async {
    final local = await events.transaction(
      (transaction) => transaction.append(
        eventType: 'sale.posted.v1',
        aggregateType: 'sale',
        aggregateId: 'local-sale',
        payload: const {'totalMinor': 900},
      ),
    );
    final pulled = await service.pull(auth());
    expect(pulled.events.single['eventId'], local.eventId);
    await service.acknowledge(
      auth(),
      leaseToken: pulled.leaseToken,
      eventIds: [local.eventId],
    );
    await service.acknowledge(
      auth(),
      leaseToken: pulled.leaseToken,
      eventIds: [local.eventId],
    );
    expect((await service.pull(auth())).events, isEmpty);
  });

  test(
    'pull publishes current catalogue and location snapshots only when changed',
    () async {
      await events.activateWriterRecording(
        enrollmentId: '12121212-1212-4212-8212-121212121212',
      );
      final publishingService = LanBranchSyncService(
        database: db,
        events: events,
        projections: SyncInboundProjectionService(db, events),
        catalogue: BranchCatalogueSyncService(
          db,
          events,
          SyncEntityIdentityStore(db),
        ),
        locations: BranchLocationDirectorySyncService(db, events),
      );

      final first = await publishingService.pull(auth());
      final firstTypes = first.events
          .map((event) => event['eventType'])
          .toSet();
      expect(firstTypes, contains(BranchCatalogueSyncService.eventType));
      expect(
        firstTypes,
        contains(BranchLocationDirectorySyncService.eventType),
      );
      await publishingService.acknowledge(
        auth(),
        leaseToken: first.leaseToken,
        eventIds: [
          for (final event in first.events) event['eventId']! as String,
        ],
      );
      expect((await publishingService.pull(auth())).events, isEmpty);

      await db.customStatement(
        "UPDATE business_branches SET name='Remote renamed' WHERE id=?",
        [remoteBranchId],
      );
      final changed = await publishingService.pull(auth());
      expect(
        changed.events.where(
          (event) =>
              event['eventType'] ==
              BranchLocationDirectorySyncService.eventType,
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'coordinator relays a branch event unchanged to every other branch once',
    () async {
      final event = _remoteEvent(organizationId);

      await service.push(auth(), [event.toJson()]);
      final ownPull = await service.pull(auth());
      expect(ownPull.events, isEmpty);

      final relayed = await service.pull(secondAuth());
      expect(relayed.events, hasLength(1));
      expect(relayed.events.single, event.toJson());

      await service.acknowledge(
        secondAuth(),
        leaseToken: relayed.leaseToken,
        eventIds: [event.eventId],
      );
      await service.acknowledge(
        secondAuth(),
        leaseToken: relayed.leaseToken,
        eventIds: [event.eventId],
      );
      expect((await service.pull(secondAuth())).events, isEmpty);

      // A duplicate sender retry repairs fan-out idempotently and must not
      // create another delivery after the destination acknowledged it.
      await service.push(auth(), [event.toJson()]);
      expect((await service.pull(secondAuth())).events, isEmpty);
      expect(
        await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM sync_relay_deliveries '
              'WHERE target_database_id=? AND event_id=?',
              variables: [
                Variable.withString(secondDatabaseId),
                Variable.withString(event.eventId),
              ],
            )
            .map((row) => row.read<int>('n'))
            .getSingle(),
        1,
      );
    },
  );
}

SyncEventEnvelope _remoteEvent(
  String organizationId, {
  String sourceDatabaseId = '11111111-1111-4111-8111-111111111111',
}) {
  final draft = SyncEventEnvelope(
    eventId: '66666666-6666-4666-8666-666666666666',
    sourceDatabaseId: sourceDatabaseId,
    organizationId: organizationId,
    branchId: '22222222-2222-4222-8222-222222222222',
    sequence: 1,
    eventType: 'sale.posted.v1',
    aggregateType: 'sale',
    aggregateId: 'remote-sale',
    contractVersion: 1,
    payload: const {'totalMinor': 700},
    occurredAt: DateTime.utc(2026, 9, 28, 10),
    eventHash: '',
  );
  return SyncEventEnvelope(
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
    eventHash: OfflineSyncTransaction.eventHashFor(draft),
  );
}
