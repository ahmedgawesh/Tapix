// Isolated process fixture for the Flutter/SQLite/PostgreSQL integration test.
// Credentials travel over a private parent/child pipe, never a command argument.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:tapbix_online/online_service.dart';
import 'package:tapbix_sync_contracts/tapbix_sync_contracts.dart';
import 'package:uuid/uuid.dart';

Future<void> main() async {
  final adminUrl = Platform.environment['TAPBIX_TEST_ADMIN_URL'];
  final appUrl = Platform.environment['TAPBIX_TEST_DATABASE_URL'];
  if (adminUrl == null ||
      appUrl == null ||
      Uri.parse(adminUrl).path != '/tapbix_online_test' ||
      Uri.parse(appUrl).path != '/tapbix_online_test') {
    throw StateError('Requires the isolated tapbix_online_test database.');
  }
  final raw = await stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .first;
  final identity = jsonDecode(raw) as Map<String, dynamic>;
  for (final key in ['organizationId', 'databaseId', 'branchId']) {
    if (identity[key] is! String ||
        !Uuid.isValidUUID(fromString: identity[key] as String)) {
      throw StateError('Invalid test fixture identity.');
    }
  }
  final org = identity['organizationId'] as String;
  final db = identity['databaseId'] as String;
  final branch = identity['branchId'] as String;
  final token = newSecret();
  final admin = await Connection.openFromUrl(adminUrl);
  await admin.runTx((tx) async {
    await tx.execute(
      Sql.named(
        "INSERT INTO tapbix_online.organizations VALUES(@org::uuid,'Flutter bridge test',now()+interval '1 hour')",
      ),
      parameters: {'org': org},
    );
    await tx.execute(
      Sql.named(
        "INSERT INTO tapbix_online.writers(organization_id,database_id,branch_id,name) VALUES(@org::uuid,@db::uuid,@branch::uuid,'SQLite writer')",
      ),
      parameters: {'org': org, 'db': db, 'branch': branch},
    );
    await tx.execute(
      Sql.named(
        "INSERT INTO tapbix_online.credentials VALUES(@org::uuid,@hash,@db::uuid,'owner',true)",
      ),
      parameters: {'org': org, 'hash': tokenDigest(token), 'db': db},
    );
  });
  final server = await OnlineService(
    () => Connection.openFromUrl(appUrl),
  ).start(port: 0);
  final client = HttpClient();
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, Object?> body,
    String credential,
  ) async {
    final r = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    r.headers.contentType = ContentType.json;
    r.headers.set('X-Organization-Id', org);
    r.headers.set('Authorization', 'Bearer $credential');
    r.write(jsonEncode(body));
    final response = await r.close();
    if (response.statusCode != 200) {
      throw StateError('Fixture API failed: ${response.statusCode}');
    }
    return jsonDecode(await utf8.decoder.bind(response).join())
        as Map<String, dynamic>;
  }

  final remoteDb = const Uuid().v4(), remoteBranch = const Uuid().v4();
  final invitation = await post('/v1/invitations', {
    'databaseId': remoteDb,
    'branchId': remoteBranch,
    'name': 'فرع اختبار',
  }, token);
  final enrollment = await post('/v1/enroll', {
    'databaseId': remoteDb,
    'invitationCode': invitation['invitationCode'],
  }, token);
  final remoteToken = enrollment['accessToken'] as String;
  final event = SyncEventEnvelope(
    eventId: const Uuid().v4(),
    sourceDatabaseId: remoteDb,
    organizationId: org,
    branchId: remoteBranch,
    sequence: 1,
    eventType: 'sale.posted.v1',
    aggregateType: 'sale',
    aggregateId: const Uuid().v4(),
    contractVersion: 1,
    payload: {
      'totalCents': 13860,
      'quantityMilli': 1250,
      'productName': 'كريم عناية',
    },
    occurredAt: DateTime.now().toUtc(),
    eventHash: '',
  );
  await post('/v1/sync/push', {
    'events': [
      {...event.toJson(), 'eventHash': SyncWireContract.eventHashFor(event)},
    ],
  }, remoteToken);
  client.close(force: true);
  stdout.writeln(
    jsonEncode({
      'port': server.port,
      'token': token,
      'remoteToken': remoteToken,
      'remoteEventId': event.eventId,
    }),
  );
  final termination = Completer<void>();
  final subscription = ProcessSignal.sigterm.watch().listen((_) {
    if (!termination.isCompleted) termination.complete();
  });
  await termination.future;
  await subscription.cancel();
  await server.close(force: true);
  await admin.close();
}
