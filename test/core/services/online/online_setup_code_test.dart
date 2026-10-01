import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/online/online_setup_code.dart';
import 'package:tapix/core/services/online/online_sync_gateway.dart';
import 'package:uuid/uuid.dart';

void main() {
  final now = DateTime.utc(2026, 10, 1);
  OnlineSetupCode code(String type) => OnlineSetupCode(
    type: type,
    organizationId: const Uuid().v4(),
    databaseId: const Uuid().v4(),
    branchId: const Uuid().v4(),
    name: 'فرع القاهرة',
    endpoint: type == 'request' ? null : Uri.parse('https://example.test'),
    secret: type == 'request' ? null : List.filled(43, 'a').join(),
    expiresAt: type == 'request' ? null : now.add(const Duration(minutes: 10)),
  );
  test('request and invitation preserve exact binding and Unicode', () {
    for (final type in ['request', 'invitation', 'activation']) {
      final original = code(type),
          decoded = OnlineSetupCode.decode(originalEncoded(type), now: now);
      expect(decoded.type, type);
      final roundtrip = OnlineSetupCode.decode(original.encode(), now: now);
      expect(roundtrip.databaseId, original.databaseId);
      expect(roundtrip.name, original.name);
      if (type == 'request') expect(roundtrip.secret, isNull);
    }
  });
  test('expired, malformed, oversized and unsupported codes are rejected', () {
    final original = code('invitation');
    expect(
      () => OnlineSetupCode.decode(
        original.encode(),
        now: now.add(const Duration(minutes: 11)),
      ),
      throwsA(isA<OnlineSyncException>()),
    );
    for (final value in [
      'broken',
      List.filled(8193, 'a').join(),
      base64Url.encode(utf8.encode('{"version":99}')),
    ]) {
      expect(
        () => OnlineSetupCode.decode(value, now: now),
        throwsA(isA<OnlineSyncException>()),
      );
    }
  });
  test('malformed endpoints fail before confirmation', () {
    for (final endpoint in [
      'invalid',
      'http://external.example',
      'https://user:password@example.test',
      'https://example.test/path',
    ]) {
      final valid = code('invitation');
      final changed = OnlineSetupCode(
        type: valid.type,
        organizationId: valid.organizationId,
        databaseId: valid.databaseId,
        branchId: valid.branchId,
        name: valid.name,
        endpoint: Uri.parse(endpoint),
        secret: valid.secret,
        expiresAt: valid.expiresAt,
      );
      expect(
        () => OnlineSetupCode.decode(changed.encode(), now: now),
        throwsA(isA<OnlineSyncException>()),
      );
    }
  });
}

String originalEncoded(String type) => OnlineSetupCode(
  type: type,
  organizationId: const Uuid().v4(),
  databaseId: const Uuid().v4(),
  branchId: const Uuid().v4(),
  name: 'Test',
  endpoint: type == 'request' ? null : Uri.parse('https://example.test'),
  secret: type == 'request' ? null : List.filled(43, 'a').join(),
  expiresAt: type == 'request' ? null : DateTime.utc(2026, 10, 1, 0, 10),
).encode();
