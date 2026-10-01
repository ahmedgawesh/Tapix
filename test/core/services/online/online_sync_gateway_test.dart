import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/lan/lan_models.dart';
import 'package:tapix/core/services/online/online_sync_gateway.dart';

void main() {
  const auth = LanBranchSyncAuth(
    enrollmentId: 'enrollment',
    remoteDatabaseId: 'database',
    accessToken: 'test-token',
  );
  test('HTTPS required except explicit development loopback', () {
    for (final url in [
      'http://example.com',
      'http://127.0.0.1',
      'https://user:password@example.com',
      'https://example.com/?token=secret',
    ]) {
      expect(
        () => OnlineSyncGateway(
          endpoint: Uri.parse(url),
          organizationId: 'company',
        ),
        throwsArgumentError,
      );
    }
    final gateway = OnlineSyncGateway(
      endpoint: Uri.parse('http://127.0.0.1'),
      organizationId: 'company',
      allowLoopbackDevelopment: true,
    );
    gateway.close();
  });
  test(
    'gateway sends scoped token and parses existing push contract',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        expect(request.uri.path, '/v1/sync/push');
        expect(request.headers.value('Authorization'), 'Bearer test-token');
        expect(request.headers.value('X-Organization-Id'), 'company');
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        expect(body['events'], [
          {'eventId': 'event'},
        ]);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          '{"acceptedEventIds":["event"],"nextExpectedSequence":2}',
        );
        await request.response.close();
      });
      final gateway = OnlineSyncGateway(
        endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
        organizationId: 'company',
        allowLoopbackDevelopment: true,
      );
      try {
        final result = await gateway.push(auth, [
          {'eventId': 'event'},
        ]);
        expect(result.acceptedEventIds, ['event']);
        expect(result.nextExpectedSequence, 2);
      } finally {
        gateway.close();
        await server.close(force: true);
      }
    },
  );
  test('redirects never forward credentials', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var redirected = false;
    server.listen((request) async {
      if (request.uri.path == '/steal') {
        redirected = true;
      }
      request.response.statusCode = 302;
      request.response.headers.set('Location', '/steal');
      request.response.headers.contentType = ContentType.json;
      request.response.write('{}');
      await request.response.close();
    });
    final gateway = OnlineSyncGateway(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      organizationId: 'company',
      allowLoopbackDevelopment: true,
    );
    try {
      await expectLater(
        gateway.pull(auth),
        throwsA(isA<OnlineSyncException>()),
      );
      expect(redirected, false);
    } finally {
      gateway.close();
      await server.close(force: true);
    }
  });
  test('unsubmitted event cannot be marked delivered', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      await r.drain<void>();
      r.response.headers.contentType = ContentType.json;
      r.response.write(
        '{"acceptedEventIds":["another-event"],"nextExpectedSequence":2}',
      );
      await r.response.close();
    });
    final gateway = OnlineSyncGateway(
      endpoint: Uri.parse('http://127.0.0.1:${server.port}'),
      organizationId: 'company',
      allowLoopbackDevelopment: true,
    );
    try {
      await expectLater(
        gateway.push(auth, [
          {'eventId': 'event'},
        ]),
        throwsA(isA<OnlineSyncException>()),
      );
    } finally {
      gateway.close();
      await server.close(force: true);
    }
  });
}
