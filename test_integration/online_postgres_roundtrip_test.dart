import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/online/online_branch_sync_service.dart';
import 'package:tapix/core/services/sync/offline_sync_event_store.dart';
import 'package:tapix/core/services/sync/sync_inbound_projection_service.dart';
import 'package:uuid/uuid.dart';
import 'package:tapix/core/services/online/online_setup_code.dart';

class TestVault implements OnlineConnectionVault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

void main() {
  test(
    'SQLite writer and projection exchange durable events through real PostgreSQL',
    () async {
      if (Platform.environment['TAPBIX_TEST_ADMIN_URL'] == null ||
          Platform.environment['TAPBIX_TEST_DATABASE_URL'] == null) {
        throw StateError(
          'Run this integration test with the isolated PostgreSQL test configuration.',
        );
      }
      final folder = await Directory.systemTemp.createTemp(
        'tapbix-online-bridge-',
      );
      final file = File('${folder.path}/branch.sqlite');
      AppDatabase open() =>
          AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      var db = open();
      Process? fixture;
      final client = HttpClient();
      try {
        final identity = await db
            .customSelect('SELECT * FROM sync_local_state WHERE id=1')
            .getSingle();
        final org = identity.read<String>('organization_id');
        final database = identity.read<String>('database_id');
        final branch = identity.read<String>('branch_id');
        fixture = await Process.start('dart', [
          'run',
          'tool/flutter_bridge.dart',
        ], workingDirectory: 'server/online');
        // The fixture never prints credential-bearing request bodies on failure.
        fixture.stderr.drain<void>();
        final response = fixture.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first;
        fixture.stdin.writeln(
          jsonEncode({
            'organizationId': org,
            'databaseId': database,
            'branchId': branch,
          }),
        );
        final boot =
            jsonDecode(await response.timeout(const Duration(seconds: 30)))
                as Map<String, dynamic>;
        final endpoint = Uri.parse('http://127.0.0.1:${boot['port']}');
        Future<Map<String, dynamic>> call(
          String path,
          String token,
          Map<String, Object?> body,
        ) async {
          final r = await client.postUrl(endpoint.resolve(path));
          r.headers.contentType = ContentType.json;
          r.headers.set('X-Organization-Id', org);
          r.headers.set('Authorization', 'Bearer $token');
          r.write(jsonEncode(body));
          final response = await r.close();
          expect(response.statusCode, 200);
          return jsonDecode(await utf8.decoder.bind(response).join())
              as Map<String, dynamic>;
        }

        var events = OfflineSyncEventStore(db);
        await events.activateWriterRecording(enrollmentId: const Uuid().v4());
        final localEvent = await events.transaction(
          (tx) => tx.append(
            eventType: 'purchase.posted.v1',
            aggregateType: 'purchase',
            aggregateId: const Uuid().v4(),
            payload: {
              'totalCents': 9007199254740993,
              'quantityMilli': 2500,
              'productName': 'عصير برتقال',
            },
          ),
        );
        final vault = TestVault();
        OnlineBranchSyncService service() => OnlineBranchSyncService(
          database: db,
          projection: SyncInboundProjectionService(db, events),
          authorizeConfiguration: () async {},
          vault: vault,
          allowLoopbackDevelopment: true,
        );
        final binding = await service().bindingRequest();
        expect(binding.organizationId, org);
        expect(binding.databaseId, database);
        await service().connectCode(
          OnlineSetupCode(
            type: 'activation',
            organizationId: org,
            databaseId: database,
            branchId: branch,
            name: binding.name,
            endpoint: endpoint,
            secret: boot['token'] as String,
            expiresAt: DateTime.now().add(const Duration(minutes: 10)),
          ).encode(),
        );
        final result = await service().synchronizeOnce();
        expect(result.uploaded, 1);
        expect(result.downloaded, 1);
        final remote = await call(
          '/v1/sync/pull',
          boot['remoteToken'] as String,
          {},
        );
        final received =
            (remote['events'] as List).single as Map<String, dynamic>;
        expect(received['eventId'], localEvent.eventId);
        expect(received['eventHash'], localEvent.eventHash);
        expect((received['payload'] as Map)['totalCents'], 9007199254740993);
        expect((received['payload'] as Map)['productName'], 'عصير برتقال');
        final projection = await db
            .customSelect(
              'SELECT event_id,payload_json FROM sync_remote_event_projections',
            )
            .getSingle();
        expect(projection.read<String>('event_id'), boot['remoteEventId']);
        expect(
          jsonDecode(projection.read<String>('payload_json'))['totalCents'],
          13860,
        );
        // Close the SQLite file and recreate the service; saved pairing and both
        // durable cursors must survive without another invitation or duplicate.
        await db.close();
        db = open();
        events = OfflineSyncEventStore(db);
        final again = await service().synchronizeOnce();
        expect(again.uploaded, 0);
        expect(again.downloaded, 0);
        expect(
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM sync_inbox_receipts')
                  .getSingle())
              .read<int>('n'),
          1,
        );
      } finally {
        client.close(force: true);
        if (fixture != null) {
          fixture.kill(ProcessSignal.sigterm);
          await fixture.exitCode.timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              fixture!.kill(ProcessSignal.sigkill);
              return -1;
            },
          );
        }
        await db.close();
        await folder.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
