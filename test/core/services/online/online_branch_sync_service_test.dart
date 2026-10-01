import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/online/online_branch_sync_service.dart';
import 'package:tapix/core/services/online/online_sync_gateway.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_inbound_projection_service.dart';
import 'package:uuid/uuid.dart';

class MemoryVault implements OnlineConnectionVault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  late AppDatabase db;
  late OfflineSyncEventStore store;
  late OnlineBranchSyncService service;
  late MemoryVault vault;
  late HttpServer server;
  late Uri endpoint;
  late String org, database, branch, relay;
  late Map<String, dynamic> session;
  late DateTime clock;
  var pushes = 0, pulls = 0, acknowledgements = 0, projections = 0;
  var failPush = false, failAck = false, failApply = false;
  var wrongAck = false, allowed = true, enrollments = 0;
  var incoming = <Map<String, Object?>>[];
  final remoteIds = <String>{};
  const token = 'test-secret-never-log';
  final grantedToken = List.filled(64, 'a').join();

  OnlineBranchSyncService createService() => OnlineBranchSyncService(
    database: db,
    projection: SyncInboundProjectionService(
      db,
      store,
      operationalProjector: (e) async {
        if (failApply) throw StateError('injected projection failure');
        await db.customStatement('INSERT INTO online_test_effects VALUES(?)', [
          e.eventId,
        ]);
      },
      appliedObserver: (_) async => projections++,
    ),
    vault: vault,
    authorizeConfiguration: () async {
      if (!allowed) throw StateError('not permitted');
    },
    allowLoopbackDevelopment: true,
    clock: () => clock,
  );

  Future<SyncEventEnvelope> append() => store.transaction(
    (tx) => tx.append(
      eventType: 'sale.posted.v1',
      aggregateType: 'sale',
      aggregateId: const Uuid().v4(),
      payload: {'totalCents': 12345, 'quantityMilli': 1250},
      occurredAt: clock,
    ),
  );

  Map<String, Object?> remoteEvent({String? organization}) {
    final e = SyncEventEnvelope(
      eventId: const Uuid().v4(),
      sourceDatabaseId: const Uuid().v4(),
      organizationId: organization ?? org,
      branchId: const Uuid().v4(),
      sequence: 1,
      eventType: 'sale.posted.v1',
      aggregateType: 'sale',
      aggregateId: const Uuid().v4(),
      contractVersion: 1,
      payload: {'totalCents': 5000},
      occurredAt: clock,
      eventHash: '',
    );
    return {...e.toJson(), 'eventHash': OfflineSyncTransaction.eventHashFor(e)};
  }

  Future<int> count(String table) => db
      .customSelect('SELECT COUNT(*) AS n FROM $table')
      .map((r) => r.read<int>('n'))
      .getSingle();

  setUp(() async {
    clock = DateTime.now().toUtc().add(const Duration(seconds: 1));
    pushes = pulls = acknowledgements = projections = enrollments = 0;
    failPush = failAck = failApply = wrongAck = false;
    allowed = true;
    incoming = [];
    remoteIds.clear();
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customStatement(
      'CREATE TABLE online_test_effects(id TEXT PRIMARY KEY)',
    );
    final identity = await db
        .customSelect('SELECT * FROM sync_local_state WHERE id=1')
        .getSingle();
    org = identity.read<String>('organization_id');
    database = identity.read<String>('database_id');
    branch = identity.read<String>('branch_id');
    relay = const Uuid().v5(Namespace.url.value, 'tapbix:online-relay:$org');
    session = {
      'organizationId': org,
      'databaseId': database,
      'branchId': branch,
      'relayId': relay,
      'deviceName': 'فرع تجريبي',
      'role': 'writer',
    };
    store = OfflineSyncEventStore(db);
    await store.activateWriterRecording(enrollmentId: const Uuid().v4());
    vault = MemoryVault();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    endpoint = Uri.parse('http://127.0.0.1:${server.port}');
    server.listen((r) async {
      expect(r.headers.value('X-Organization-Id'), org);
      final body =
          jsonDecode(await utf8.decoder.bind(r).join()) as Map<String, dynamic>;
      var status = 200;
      Object response = {};
      if (r.uri.path != '/v1/enroll') {
        expect(
          r.headers.value('Authorization'),
          anyOf('Bearer $token', 'Bearer $grantedToken'),
        );
      }
      switch (r.uri.path) {
        case '/v1/session':
          response = session;
        case '/v1/enroll':
          enrollments++;
          expect(r.headers.value('Authorization'), isNull);
          expect(body['databaseId'], database);
          response = {
            'organizationId': org,
            'databaseId': database,
            'branchId': branch,
            'accessToken': grantedToken,
          };
        case '/v1/sync/push':
          pushes++;
          final events = (body['events'] as List).cast<Map<String, dynamic>>();
          for (final event in events) {
            remoteIds.add(event['eventId'] as String);
          }
          if (failPush) {
            status = 503;
            response = {'error': 'storage_unavailable'};
          } else {
            response = {
              'acceptedEventIds': wrongAck
                  ? <Object?>[]
                  : events.map((e) => e['eventId']).toList(),
              'nextExpectedSequence': (events.last['sequence'] as int) + 1,
            };
          }
        case '/v1/sync/pull':
          pulls++;
          response = {'leaseToken': 'remote-lease', 'events': incoming};
        case '/v1/sync/ack':
          acknowledgements++;
          // The remote acknowledgement must follow the local durable commit.
          expect(await count('online_test_effects'), incoming.length);
          if (failAck) {
            status = 503;
            response = {'error': 'storage_unavailable'};
          } else {
            incoming = [];
            response = {'ok': true};
          }
      }
      r.response.statusCode = status;
      r.response.headers.contentType = ContentType.json;
      r.response.write(jsonEncode(response));
      await r.response.close();
    });
    service = createService();
  });
  tearDown(() async {
    await server.close(force: true);
    await db.close();
  });

  test(
    'reuses LAN enrollment and keeps cloud acknowledgement independent',
    () async {
      final originalSettings = await count('app_settings');
      final prior = await db
          .customSelect('SELECT enrollment_id FROM sync_writer_enrollment')
          .getSingle();
      final lanPeer = const Uuid().v4();
      await store.registerDeliveryPeer(
        targetDatabaseId: lanPeer,
        organizationId: org,
        branchId: const Uuid().v4(),
      );
      await append();
      await service.connect(endpoint: endpoint, accessToken: token);
      expect((await service.synchronizeOnce()).uploaded, 1);
      final pendingLan = await store.claimDispatchBatchForPeer(
        targetDatabaseId: lanPeer,
        leaseToken: 'lan',
      );
      expect(pendingLan, hasLength(1));
      expect(
        (await db
                .customSelect(
                  'SELECT enrollment_id FROM sync_writer_enrollment',
                )
                .getSingle())
            .data,
        prior.data,
      );
      expect(await count('app_settings'), originalSettings);
      expect(vault.values.values.single, contains(token));
    },
  );

  test(
    'invitation used once then persisted credential survives service recreation',
    () async {
      await service.connectInvitation(
        endpoint: endpoint,
        invitationCode: 'test-invite',
      );
      service = createService();
      await service.synchronizeOnce();
      await service.synchronizeOnce();
      expect(enrollments, 1);
      expect(pulls, 2);
    },
  );

  test(
    'wrong company or branch credentials cannot overwrite a connection',
    () async {
      await service.connect(endpoint: endpoint, accessToken: token);
      final previous = Map.of(vault.values);
      session['branchId'] = const Uuid().v4();
      await expectLater(
        service.connect(endpoint: endpoint, accessToken: token),
        throwsA(
          isA<OnlineSyncException>().having(
            (e) => e.code,
            'code',
            'online_identity_mismatch',
          ),
        ),
      );
      expect(vault.values, previous);
      expect(await count('sync_delivery_peers'), 1);
    },
  );

  test('configuration respects existing account authorization', () async {
    allowed = false;
    await expectLater(
      service.connectInvitation(endpoint: endpoint, invitationCode: 'test'),
      throwsStateError,
    );
    expect(enrollments, 0);
    expect(vault.values, isEmpty);
    expect(await count('sync_delivery_peers'), 0);
  });

  test(
    'lost push response retries immutable event without changing LAN state',
    () async {
      await service.connect(endpoint: endpoint, accessToken: token);
      final event = await append();
      failPush = true;
      await expectLater(
        service.synchronizeOnce(),
        throwsA(isA<OnlineSyncException>()),
      );
      var state = await db
          .customSelect('SELECT state,last_error FROM sync_outbox_deliveries')
          .getSingle();
      expect(state.read<String>('state'), 'pending');
      expect(state.read<String>('last_error'), 'storage_unavailable');
      clock = clock.add(const Duration(seconds: 6));
      service = createService();
      failPush = false;
      expect((await service.synchronizeOnce()).uploaded, 1);
      expect(remoteIds, {event.eventId});
      expect(pushes, 2);
    },
  );

  test(
    'incomplete batch acknowledgement never marks events delivered',
    () async {
      await service.connect(endpoint: endpoint, accessToken: token);
      await append();
      wrongAck = true;
      await expectLater(
        service.synchronizeOnce(),
        throwsA(isA<OnlineSyncException>()),
      );
      expect(
        (await db
                .customSelect('SELECT state FROM sync_outbox_deliveries')
                .getSingle())
            .read<String>('state'),
        'pending',
      );
    },
  );

  test(
    'lost pull acknowledgement replays without double application after restart',
    () async {
      await service.connect(endpoint: endpoint, accessToken: token);
      incoming = [remoteEvent()];
      failAck = true;
      await expectLater(
        service.synchronizeOnce(),
        throwsA(isA<OnlineSyncException>()),
      );
      expect(await count('online_test_effects'), 1);
      service = createService();
      failAck = false;
      await service.synchronizeOnce();
      expect(await count('online_test_effects'), 1);
      expect(await count('sync_inbox_receipts'), 1);
      expect(projections, 1);
      expect(acknowledgements, 2);
    },
  );

  test(
    'failed operational projection rolls back and sends no receipt',
    () async {
      await service.connect(endpoint: endpoint, accessToken: token);
      incoming = [remoteEvent()];
      failApply = true;
      await expectLater(service.synchronizeOnce(), throwsStateError);
      expect(await count('sync_inbox_receipts'), 0);
      expect(await count('sync_remote_event_projections'), 0);
      expect(acknowledgements, 0);
      failApply = false;
      await service.synchronizeOnce();
      expect(await count('online_test_effects'), 1);
    },
  );

  test('foreign company event cannot enter the local inbox', () async {
    await service.connect(endpoint: endpoint, accessToken: token);
    incoming = [remoteEvent(organization: const Uuid().v4())];
    await expectLater(
      service.synchronizeOnce(),
      throwsA(isA<OfflineSyncException>()),
    );
    expect(await count('sync_inbox_receipts'), 0);
    expect(acknowledgements, 0);
  });

  test('concurrent refreshes share a single exchange', () async {
    await service.connect(endpoint: endpoint, accessToken: token);
    await append();
    await Future.wait([
      service.synchronizeOnce(),
      service.synchronizeOnce(),
      service.synchronizeOnce(),
    ]);
    expect(pushes, 1);
    expect(pulls, 1);
  });

  test('cloud peer never queues another branch stream for re-upload', () async {
    final remote = SyncEventEnvelope.fromJson(remoteEvent());
    await store.enrollSource(
      sourceDatabaseId: remote.sourceDatabaseId,
      organizationId: org,
      branchId: remote.branchId,
    );
    await SyncInboundProjectionService(db, store).apply(remote);
    await service.connect(endpoint: endpoint, accessToken: token);
    await store.stageRelayDeliveries(remote);
    expect(await count('sync_relay_deliveries'), 0);
    await expectLater(
      store.registerDeliveryPeer(
        targetDatabaseId: relay,
        organizationId: org,
        branchId: branch,
        relayRemoteEvents: true,
      ),
      throwsA(isA<OfflineSyncException>()),
    );
  });
}
