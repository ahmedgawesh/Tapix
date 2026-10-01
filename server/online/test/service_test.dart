import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:tapbix_online/online_service.dart';
import 'package:tapbix_sync_contracts/tapbix_sync_contracts.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

void main() {
  final appUrl = Platform.environment['TAPBIX_TEST_DATABASE_URL'];
  final adminUrl = Platform.environment['TAPBIX_TEST_ADMIN_URL'];
  if (appUrl == null || adminUrl == null) {
    throw StateError(
      'Integration tests require isolated TAPBIX_TEST_DATABASE_URL and TAPBIX_TEST_ADMIN_URL.',
    );
  }
  if (Uri.parse(adminUrl).path != '/tapbix_online_test' ||
      Uri.parse(appUrl).path != '/tapbix_online_test') {
    throw StateError('Refusing a database other than tapbix_online_test.');
  }
  late Connection admin;
  late HttpServer server;
  late HttpClient client;
  late String org, db, branch, token, otherOrg, otherToken;
  String id() => const Uuid().v4();
  Future<(int, Map<String, dynamic>)> call(
    String path, {
    Map<String, Object?>? body,
    String? asOrg,
    String? asToken,
    String method = 'POST',
  }) async {
    final r = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    r.headers.set('X-Organization-Id', asOrg ?? org);
    r.headers.set('Authorization', 'Bearer ${asToken ?? token}');
    if (method == 'POST') {
      r.headers.contentType = ContentType.json;
      r.write(jsonEncode(body ?? {}));
    }
    final response = await r.close();
    return (
      response.statusCode,
      jsonDecode(await utf8.decoder.bind(response).join())
          as Map<String, dynamic>,
    );
  }

  Future<void> company(String o, String d, String b, String t) async {
    await admin.execute(
      Sql.named(
        "INSERT INTO tapbix_online.organizations VALUES(@o::uuid,'شركة اختبار',now()+interval '1 day')",
      ),
      parameters: {'o': o},
    );
    await admin.execute(
      Sql.named(
        "INSERT INTO tapbix_online.writers(organization_id,database_id,branch_id,name) VALUES(@o::uuid,@d::uuid,@b::uuid,'الفرع الرئيسي')",
      ),
      parameters: {'o': o, 'd': d, 'b': b},
    );
    await admin.execute(
      Sql.named(
        "INSERT INTO tapbix_online.credentials VALUES(@o::uuid,@h,@d::uuid,'owner',true)",
      ),
      parameters: {'o': o, 'h': tokenDigest(t), 'd': d},
    );
  }

  Map<String, Object?> event({
    int sequence = 1,
    String? eventId,
    String? organization,
    String? source,
    String? site,
    String type = 'sale.posted.v1',
    Map<String, Object?>? payload,
  }) {
    final e = SyncEventEnvelope(
      eventId: eventId ?? id(),
      sourceDatabaseId: source ?? db,
      organizationId: organization ?? org,
      branchId: site ?? branch,
      sequence: sequence,
      eventType: type,
      aggregateType: 'sale',
      aggregateId: id(),
      contractVersion: 1,
      payload:
          payload ??
          {'totalCents': 12345, 'name': 'منتج عربي', 'quantityMilli': 1250},
      occurredAt: DateTime.utc(2026, 10, 1),
      eventHash: '',
    );
    return {...e.toJson(), 'eventHash': SyncWireContract.eventHashFor(e)};
  }

  Future<Map<String, dynamic>> enroll(
    String writerDb,
    String writerBranch,
  ) async {
    final invite = await call(
      '/v1/invitations',
      body: {
        'databaseId': writerDb,
        'branchId': writerBranch,
        'name': 'فرع مستقل',
      },
    );
    expect(invite.$1, 200);
    final result = await call(
      '/v1/enroll',
      body: {
        'databaseId': writerDb,
        'invitationCode': invite.$2['invitationCode'],
      },
    );
    expect(result.$1, 200);
    return result.$2;
  }

  setUpAll(() async {
    admin = await Connection.openFromUrl(adminUrl);
    server = await OnlineService(
      () => Connection.openFromUrl(appUrl),
    ).start(port: 0);
    client = HttpClient();
  });
  tearDownAll(() async {
    client.close(force: true);
    await server.close(force: true);
    await admin.close();
  });
  setUp(() async {
    org = id();
    db = id();
    branch = id();
    token = newSecret();
    otherOrg = id();
    otherToken = newSecret();
    await company(org, db, branch, token);
    await company(otherOrg, id(), id(), otherToken);
  });
  test('health endpoint and unauthorized access', () async {
    expect((await call('/healthz', method: 'GET')).$1, 200);
    expect((await call('/v1/events', method: 'GET', asToken: 'wrong')).$1, 401);
  });
  test('retries persist an event exactly once', () async {
    final e = event();
    for (var i = 0; i < 2; i++) {
      final r = await call(
        '/v1/sync/push',
        body: {
          'events': [e],
        },
      );
      expect(r.$1, 200);
      expect(r.$2['nextExpectedSequence'], 2);
    }
    expect(
      ((await call('/v1/events', method: 'GET')).$2['events'] as List).length,
      1,
    );
  });
  test('altered duplicate is a conflict', () async {
    final e = event();
    expect(
      (await call(
        '/v1/sync/push',
        body: {
          'events': [e],
        },
      )).$1,
      200,
    );
    final changed = event(eventId: e['eventId'] as String);
    expect(
      (await call(
        '/v1/sync/push',
        body: {
          'events': [changed],
        },
      )).$1,
      409,
    );
  });
  test('batch is atomic and sequence gaps are rejected', () async {
    expect(
      (await call(
        '/v1/sync/push',
        body: {
          'events': [event(), event(sequence: 3)],
        },
      )).$1,
      409,
    );
    expect((await call('/v1/events', method: 'GET')).$2['events'], isEmpty);
    expect(
      (await call(
        '/v1/sync/push',
        body: {
          'events': [event()],
        },
      )).$1,
      200,
    );
  });
  test('cross-company token and forged event rejected', () async {
    expect((await call('/v1/events', method: 'GET', asOrg: otherOrg)).$1, 401);
    expect(
      (await call(
        '/v1/sync/push',
        body: {
          'events': [event(organization: otherOrg)],
        },
      )).$1,
      403,
    );
  });
  test('RLS restricts direct SQL and resets across transactions', () async {
    final c = await Connection.openFromUrl(appUrl);
    try {
      expect(
        await c.execute('SELECT * FROM tapbix_online.organizations'),
        isEmpty,
      );
      await c.runTx((tx) async {
        await tx.execute(
          Sql.named("SELECT set_config('tapbix.organization_id',@o,true)"),
          parameters: {'o': org},
        );
        final rows = await tx.execute(
          'SELECT id::text FROM tapbix_online.organizations',
        );
        expect(rows.length, 1);
        expect(rows.single[0], org);
      });
      expect(
        await c.execute('SELECT * FROM tapbix_online.organizations'),
        isEmpty,
      );
    } finally {
      await c.close();
    }
  });
  test('floating point payload and tampered hash rejected', () async {
    expect(
      (await call(
        '/v1/sync/push',
        body: {
          'events': [
            event(payload: {'money': 1.25}),
          ],
        },
      )).$2['error'],
      'floating_point_payload',
    );
    final e = event();
    e['eventHash'] = 'invalid';
    expect(
      (await call(
        '/v1/sync/push',
        body: {
          'events': [e],
        },
      )).$2['error'],
      'event_hash_mismatch',
    );
  });
  test('unknown contract rejected', () async {
    expect(
      (await call(
        '/v1/sync/push',
        body: {
          'events': [event(type: 'sale.posted.v2')],
        },
      )).$2['error'],
      'unsupported_event_contract',
    );
  });
  test('invite fixes branch and device name and is retryable', () async {
    final d = id(), b = id();
    final invite = await call(
      '/v1/invitations',
      body: {'databaseId': d, 'branchId': b, 'name': 'مخزن الفرع'},
    );
    final body = {
      'databaseId': d,
      'invitationCode': invite.$2['invitationCode'],
    };
    final a = await call('/v1/enroll', body: body);
    final repeat = await call('/v1/enroll', body: body);
    expect(a.$1, 200);
    expect(repeat.$2, a.$2);
    expect(a.$2['deviceName'], 'مخزن الفرع');
    expect(a.$2['branchId'], b);
    expect(
      (await call('/v1/enroll', body: {...body, 'databaseId': id()})).$1,
      401,
    );
  });
  test('only one writer per branch', () async {
    final r = await call(
      '/v1/invitations',
      body: {'databaseId': id(), 'branchId': branch, 'name': 'duplicate'},
    );
    expect(
      (await call(
        '/v1/enroll',
        body: {
          'databaseId': r.$2['databaseId'],
          'invitationCode': r.$2['invitationCode'],
        },
      )).$1,
      409,
    );
  });
  test('writer cannot invite or publish central catalogue', () async {
    final d = id(), b = id();
    final w = await enroll(d, b);
    expect(
      (await call('/v1/invitations', asToken: w['accessToken'] as String)).$1,
      403,
    );
    expect(
      (await call(
        '/v1/sync/push',
        asToken: w['accessToken'] as String,
        body: {
          'events': [
            event(source: d, site: b, type: 'catalogue.snapshot_page.v1'),
          ],
        },
      )).$1,
      403,
    );
  });
  test('delivery survives repeated pull and acknowledgement retry', () async {
    final d = id(), b = id();
    final w = await enroll(d, b);
    final wt = w['accessToken'] as String;
    final e = event();
    expect(
      (await call(
        '/v1/sync/push',
        body: {
          'events': [e],
        },
      )).$1,
      200,
    );
    final p = await call('/v1/sync/pull', asToken: wt);
    expect((p.$2['events'] as List).length, 1);
    expect((await call('/v1/sync/pull', asToken: wt)).$2, p.$2);
    final ack = {
      'leaseToken': p.$2['leaseToken'],
      'eventIds': [e['eventId']],
    };
    expect((await call('/v1/sync/ack', asToken: wt, body: ack)).$1, 200);
    expect((await call('/v1/sync/ack', asToken: wt, body: ack)).$1, 200);
    expect((await call('/v1/sync/pull', asToken: wt)).$2['events'], isEmpty);
    expect((await call('/v1/sync/pull')).$2['events'], isEmpty);
  });
  test(
    'new writer receives earlier events, another company does not',
    () async {
      await call(
        '/v1/sync/push',
        body: {
          'events': [event()],
        },
      );
      final w = await enroll(id(), id());
      expect(
        ((await call(
                  '/v1/sync/pull',
                  asToken: w['accessToken'] as String,
                )).$2['events']
                as List)
            .length,
        1,
      );
      expect(
        (await call(
          '/v1/sync/pull',
          asOrg: otherOrg,
          asToken: otherToken,
        )).$2['events'],
        isEmpty,
      );
    },
  );
  test('wrong delivery lease does not acknowledge anything', () async {
    final w = await enroll(id(), id());
    final e = event();
    await call(
      '/v1/sync/push',
      body: {
        'events': [e],
      },
    );
    expect(
      (await call(
        '/v1/sync/ack',
        asToken: w['accessToken'] as String,
        body: {
          'leaseToken': id(),
          'eventIds': [e['eventId']],
        },
      )).$1,
      409,
    );
    expect(
      ((await call(
                '/v1/sync/pull',
                asToken: w['accessToken'] as String,
              )).$2['events']
              as List)
          .length,
      1,
    );
  });
  test(
    'expired online entitlement blocks service without changing events',
    () async {
      await admin.execute(
        Sql.named(
          "UPDATE tapbix_online.organizations SET online_until=now()-interval '1 second' WHERE id=@o::uuid",
        ),
        parameters: {'o': org},
      );
      expect(
        (await call(
          '/v1/sync/push',
          body: {
            'events': [event()],
          },
        )).$2['error'],
        'online_entitlement_required',
      );
    },
  );
  test('expired invitation cannot be redeemed', () async {
    final d = id();
    final r = await call(
      '/v1/invitations',
      body: {'databaseId': d, 'branchId': id(), 'name': 'expired'},
    );
    await admin.execute(
      Sql.named(
        "UPDATE tapbix_online.invitations SET expires_at=now()-interval '1 second' WHERE organization_id=@o::uuid",
      ),
      parameters: {'o': org},
    );
    expect(
      (await call(
        '/v1/enroll',
        body: {'databaseId': d, 'invitationCode': r.$2['invitationCode']},
      )).$1,
      401,
    );
  });
  test('database role cannot update immutable event history', () async {
    await call(
      '/v1/sync/push',
      body: {
        'events': [event()],
      },
    );
    final c = await Connection.openFromUrl(appUrl);
    try {
      await expectLater(
        c.execute("UPDATE tapbix_online.events SET event_hash='tampered'"),
        throwsA(isA<ServerException>()),
      );
    } finally {
      await c.close();
    }
  });
  test('64-bit integers and Unicode survive PostgreSQL JSON storage', () async {
    final payload = {
      'quantityMilli': 9007199254740993,
      'name': 'صنف 🎁',
      'nested': {'ب': 5, 'a': -4},
    };
    final e = event(payload: payload);
    expect(
      (await call(
        '/v1/sync/push',
        body: {
          'events': [e],
        },
      )).$1,
      200,
    );
    final list = (await call('/v1/events', method: 'GET')).$2['events'] as List;
    expect((list.single as Map)['payload'], payload);
  });
  test('concurrent duplicate pushes still create one event', () async {
    final e = event();
    final results = await Future.wait(
      List.generate(
        4,
        (_) => call(
          '/v1/sync/push',
          body: {
            'events': [e],
          },
        ),
      ),
    );
    expect(results.map((r) => r.$1), everyElement(200));
    expect(
      ((await call('/v1/events', method: 'GET')).$2['events'] as List).length,
      1,
    );
  });
  test('oversized batches rejected', () async {
    expect(
      (await call(
        '/v1/sync/push',
        body: {'events': List.generate(51, (_) => event())},
      )).$1,
      400,
    );
  });
  test(
    'restart preserves accepted events and pending delivery leases',
    () async {
      final writer = await enroll(id(), id());
      final writerToken = writer['accessToken'] as String;
      final e = event();
      expect(
        (await call(
          '/v1/sync/push',
          body: {
            'events': [e],
          },
        )).$1,
        200,
      );
      final before = await call('/v1/sync/pull', asToken: writerToken);
      client.close(force: true);
      await server.close(force: true);
      server = await OnlineService(
        () => Connection.openFromUrl(appUrl),
      ).start(port: 0);
      client = HttpClient();
      final after = await call('/v1/sync/pull', asToken: writerToken);
      expect(after.$2, before.$2);
      expect(
        (await call(
          '/v1/sync/push',
          body: {
            'events': [e],
          },
        )).$1,
        200,
      );
      expect(
        ((await call('/v1/events', method: 'GET')).$2['events'] as List).length,
        1,
      );
      expect(
        (await call(
          '/v1/sync/ack',
          asToken: writerToken,
          body: {
            'leaseToken': after.$2['leaseToken'],
            'eventIds': [e['eventId']],
          },
        )).$1,
        200,
      );
    },
  );
}
