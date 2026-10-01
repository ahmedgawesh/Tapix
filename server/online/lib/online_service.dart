import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:tapbix_sync_contracts/tapbix_sync_contracts.dart';
import 'package:uuid/uuid.dart';

String tokenDigest(String value) =>
    sha256.convert(utf8.encode(value)).toString();
String newSecret() => base64UrlEncode(
  List<int>.generate(32, (_) => Random.secure().nextInt(256)),
).replaceAll('=', '');

class ApiFailure implements Exception {
  const ApiFailure(this.status, this.code);
  final int status;
  final String code;
}

class OnlineService {
  OnlineService(this.connect);
  final Future<Connection> Function() connect;
  int _inFlight = 0;

  Future<HttpServer> start({int port = 45830}) async {
    final connection = await connect();
    try {
      final role = await connection.execute(
        'SELECT rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user',
      );
      if (role.single[0] != false || role.single[1] != false) {
        throw StateError(
          'The API requires a non-superuser, non-BYPASSRLS database role.',
        );
      }
      final owner = await connection.execute(
        "SELECT count(*) FROM pg_tables WHERE schemaname='tapbix_online' AND tableowner=current_user",
      );
      if (owner.single[0] != 0) {
        throw StateError('Migration and API database roles must be separate.');
      }
    } finally {
      await connection.close();
    }
    // Internet ingress must terminate HTTPS in a separately configured proxy.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server.idleTimeout = const Duration(seconds: 15);
    server.listen((request) => unawaited(_handle(request)));
    return server;
  }

  Future<void> _handle(HttpRequest request) async {
    request.response.headers.contentType = ContentType.json;
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.headers.set('X-Content-Type-Options', 'nosniff');
    if (_inFlight >= 8) {
      request.response.statusCode = 503;
      request.response.write('{"error":"server_busy"}');
      await request.response.close();
      return;
    }
    _inFlight++;
    Connection? connection;
    try {
      if (request.method == 'GET' && request.uri.path == '/healthz') {
        request.response.write(
          '{"status":"ok","protocol":1,"release":"development"}',
        );
        return;
      }
      final org = request.headers.value('X-Organization-Id') ?? '';
      if (!Uuid.isValidUUID(fromString: org)) {
        throw const ApiFailure(400, 'invalid_organization');
      }
      final body = request.method == 'POST'
          ? await _body(request)
          : <String, Object?>{};
      connection = await connect();
      final result = await connection.runTx((tx) async {
        await tx.execute("SET LOCAL statement_timeout='5s'");
        await tx.execute(
          Sql.named("SELECT set_config('tapbix.organization_id',@org,true)"),
          parameters: {'org': org},
        );
        // One ordering boundary for enrollments, event commit and delivery fan-out.
        await tx.execute(
          Sql.named('SELECT pg_advisory_xact_lock(hashtextextended(@org,0))'),
          parameters: {'org': org},
        );
        final organization = await tx.execute(
          'SELECT online_until > now() FROM tapbix_online.organizations',
        );
        if (organization.isEmpty || organization.single[0] != true) {
          throw const ApiFailure(403, 'online_entitlement_required');
        }
        if (request.method == 'POST' && request.uri.path == '/v1/enroll') {
          return _enroll(tx, org, body);
        }
        final header =
            request.headers.value(HttpHeaders.authorizationHeader) ?? '';
        if (!header.startsWith('Bearer ') || header.length > 200) {
          throw const ApiFailure(401, 'unauthorized');
        }
        final identity = await tx.execute(
          Sql.named('''SELECT c.database_id::text,w.branch_id::text,c.role
          FROM tapbix_online.credentials c JOIN tapbix_online.writers w USING(organization_id,database_id)
          WHERE c.token_hash=@hash AND c.active AND w.active'''),
          parameters: {'hash': tokenDigest(header.substring(7))},
        );
        if (identity.length != 1) throw const ApiFailure(401, 'unauthorized');
        final db = identity.single[0] as String;
        final branch = identity.single[1] as String;
        final owner = identity.single[2] == 'owner';
        switch ('${request.method} ${request.uri.path}') {
          case 'POST /v1/session':
            final writer = await tx.execute(
              Sql.named(
                'SELECT name FROM tapbix_online.writers WHERE database_id=@db::uuid',
              ),
              parameters: {'db': db},
            );
            return {
              'organizationId': org,
              'databaseId': db,
              'branchId': branch,
              'deviceName': writer.single[0],
              'role': owner ? 'owner' : 'writer',
              // A transport identity, distinct from every LAN database cursor.
              'relayId': const Uuid().v5(
                Namespace.url.value,
                'tapbix:online-relay:$org',
              ),
            };
          case 'POST /v1/invitations':
            if (!owner) throw const ApiFailure(403, 'owner_required');
            return _invite(tx, org, body);
          case 'POST /v1/sync/push':
            return _push(tx, org, db, branch, owner, body);
          case 'POST /v1/sync/pull':
            return _pull(tx, org, db, body);
          case 'POST /v1/sync/ack':
            return _ack(tx, org, db, body);
          case 'GET /v1/events':
            if (!owner) throw const ApiFailure(403, 'owner_required');
            final source = request.uri.queryParameters['sourceDatabaseId'];
            if (source != null && !Uuid.isValidUUID(fromString: source)) {
              throw const ApiFailure(400, 'invalid_source');
            }
            final offset = int.tryParse(
              request.uri.queryParameters['offset'] ?? '0',
            );
            if (offset == null || offset < 0 || offset > 100000) {
              throw const ApiFailure(400, 'invalid_offset');
            }
            final rows = await tx.execute(
              Sql.named('''SELECT envelope FROM tapbix_online.events
              WHERE (@source::uuid IS NULL OR source_database_id=@source::uuid)
              ORDER BY received_at,event_id LIMIT 50 OFFSET @offset'''),
              parameters: {'source': source, 'offset': offset},
            );
            return {
              'events': rows.map((r) => r[0]).toList(),
              'nextOffset': offset + rows.length,
            };
          default:
            throw const ApiFailure(404, 'not_found');
        }
      });
      request.response.write(jsonEncode(result));
    } on ApiFailure catch (e) {
      request.response.statusCode = e.status;
      request.response.write(jsonEncode({'error': e.code}));
    } on OfflineSyncException catch (e) {
      request.response.statusCode = 422;
      request.response.write(jsonEncode({'error': e.code}));
    } on FormatException {
      request.response.statusCode = 400;
      request.response.write('{"error":"invalid_json"}');
    } on TimeoutException {
      request.response.statusCode = 408;
      request.response.write('{"error":"request_timeout"}');
    } on ServerException catch (e) {
      request.response.statusCode = e.code == '23505' ? 409 : 503;
      request.response.write(
        jsonEncode({
          'error': e.code == '23505'
              ? 'identity_conflict'
              : 'storage_unavailable',
        }),
      );
    } catch (_) {
      request.response.statusCode = 503;
      request.response.write('{"error":"service_unavailable"}');
    } finally {
      await connection?.close();
      _inFlight--;
      await request.response.close();
    }
  }

  Future<Map<String, Object?>> _body(HttpRequest request) async {
    if (request.headers.contentType?.mimeType != 'application/json') {
      throw const ApiFailure(415, 'json_required');
    }
    const max = 2 * 1024 * 1024;
    if (request.contentLength > max) {
      throw const ApiFailure(413, 'body_too_large');
    }
    final bytes = <int>[];
    await for (final chunk in request.timeout(const Duration(seconds: 10))) {
      if (bytes.length + chunk.length > max) {
        throw const ApiFailure(413, 'body_too_large');
      }
      bytes.addAll(chunk);
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const ApiFailure(400, 'json_object_required');
    }
    return decoded;
  }

  String _uuid(Map<String, Object?> body, String key) {
    final value = body[key];
    if (value is! String ||
        !Uuid.isValidUUID(fromString: value) ||
        value != value.toLowerCase()) {
      throw const ApiFailure(400, 'invalid_identity');
    }
    return value;
  }

  Future<Map<String, Object?>> _invite(
    TxSession tx,
    String org,
    Map<String, Object?> body,
  ) async {
    final branch = _uuid(body, 'branchId');
    final db = _uuid(body, 'databaseId');
    final name = body['name'];
    if (name is! String || name.trim().isEmpty || name.length > 80) {
      throw const ApiFailure(400, 'invalid_name');
    }
    final code = newSecret();
    await tx.execute(
      Sql.named(
        '''INSERT INTO tapbix_online.invitations
      (organization_id,code_hash,branch_id,database_id,name,expires_at)
      VALUES(@org::uuid,@hash,@branch::uuid,@db::uuid,@name,now()+interval '10 minutes')''',
      ),
      parameters: {
        'org': org,
        'hash': tokenDigest(code),
        'branch': branch,
        'db': db,
        'name': name.trim(),
      },
    );
    return {
      'organizationId': org,
      'invitationCode': code,
      'expiresInSeconds': 600,
      'branchId': branch,
      'databaseId': db,
    };
  }

  Future<Map<String, Object?>> _enroll(
    TxSession tx,
    String org,
    Map<String, Object?> body,
  ) async {
    final code = body['invitationCode'];
    final db = _uuid(body, 'databaseId');
    if (code is! String || code.length != 43) {
      throw const ApiFailure(401, 'invalid_invitation');
    }
    final rows = await tx.execute(
      Sql.named(
        '''SELECT branch_id::text,name,consumed FROM tapbix_online.invitations
      WHERE code_hash=@hash AND database_id=@db::uuid AND expires_at>now() FOR UPDATE''',
      ),
      parameters: {'hash': tokenDigest(code), 'db': db},
    );
    if (rows.isEmpty) throw const ApiFailure(401, 'invalid_invitation');
    final row = rows.single;
    // A lost response can be retried with the same short-lived, identity-bound invite.
    final token = tokenDigest('tapbix-online-writer:$code:$db');
    if (row[2] == false) {
      await tx.execute(
        Sql.named(
          '''INSERT INTO tapbix_online.writers(organization_id,database_id,branch_id,name)
        VALUES(@org::uuid,@db::uuid,@branch::uuid,@name)''',
        ),
        parameters: {'org': org, 'db': db, 'branch': row[0], 'name': row[1]},
      );
      await tx.execute(
        Sql.named(
          "INSERT INTO tapbix_online.credentials VALUES(@org::uuid,@hash,@db::uuid,'writer',true)",
        ),
        parameters: {'org': org, 'hash': tokenDigest(token), 'db': db},
      );
      await tx.execute(
        Sql.named(
          '''INSERT INTO tapbix_online.deliveries(organization_id,target_database_id,event_id)
        SELECT organization_id,@db::uuid,event_id FROM tapbix_online.events WHERE source_database_id<>@db::uuid''',
        ),
        parameters: {'db': db},
      );
      await tx.execute(
        Sql.named(
          'UPDATE tapbix_online.invitations SET consumed=true WHERE code_hash=@hash',
        ),
        parameters: {'hash': tokenDigest(code)},
      );
    }
    return {
      'organizationId': org,
      'databaseId': db,
      'branchId': row[0],
      'deviceName': row[1],
      'accessToken': token,
    };
  }

  Future<Map<String, Object?>> _push(
    TxSession tx,
    String org,
    String db,
    String branch,
    bool owner,
    Map<String, Object?> body,
  ) async {
    final raw = body['events'];
    if (raw is! List || raw.isEmpty || raw.length > 50) {
      throw const ApiFailure(400, 'invalid_batch');
    }
    final counter = await tx.execute(
      Sql.named(
        'SELECT next_sequence FROM tapbix_online.writers WHERE database_id=@db::uuid FOR UPDATE',
      ),
      parameters: {'db': db},
    );
    var next = counter.single[0] as int;
    final accepted = <String>[];
    for (final value in raw) {
      if (value is! Map<String, dynamic>) {
        throw const ApiFailure(400, 'invalid_event');
      }
      final event = SyncEventEnvelope.fromJson(value);
      SyncWireContract.validateJson(event.payload);
      if (event.sourceDatabaseId != db ||
          event.organizationId != org ||
          event.branchId != branch) {
        throw const ApiFailure(403, 'sync_source_mismatch');
      }
      if (!Uuid.isValidUUID(fromString: event.eventId) ||
          event.aggregateId.isEmpty ||
          event.aggregateId.length > 200 ||
          event.aggregateType.isEmpty ||
          event.aggregateType.length > 100 ||
          event.sequence <= 0) {
        throw const ApiFailure(422, 'invalid_event');
      }
      if (event.contractVersion != 1 ||
          !SyncWireContract.supportedContracts.contains(event.eventType)) {
        throw const ApiFailure(422, 'unsupported_event_contract');
      }
      if (!owner &&
          (event.eventType == 'catalogue.snapshot_page.v1' ||
              event.eventType == 'location.snapshot_page.v1')) {
        throw const ApiFailure(403, 'catalogue_authority_required');
      }
      if (event.eventHash != SyncWireContract.eventHashFor(event)) {
        throw const ApiFailure(422, 'event_hash_mismatch');
      }
      final prior = await tx.execute(
        Sql.named(
          'SELECT event_hash FROM tapbix_online.events WHERE event_id=@id::uuid',
        ),
        parameters: {'id': event.eventId},
      );
      if (prior.isNotEmpty) {
        if (prior.single[0] != event.eventHash) {
          throw const ApiFailure(409, 'event_conflict');
        }
        accepted.add(event.eventId);
        continue;
      }
      if (event.sequence != next) {
        throw const ApiFailure(409, 'sequence_gap_or_conflict');
      }
      await tx.execute(
        Sql.named(
          '''INSERT INTO tapbix_online.events(organization_id,event_id,source_database_id,sequence,event_hash,event_type,envelope)
        VALUES(@org::uuid,@id::uuid,@db::uuid,@seq,@hash,@type,@envelope::jsonb)''',
        ),
        parameters: {
          'org': org,
          'id': event.eventId,
          'db': db,
          'seq': event.sequence,
          'hash': event.eventHash,
          'type': event.eventType,
          'envelope': jsonEncode(event.toJson()),
        },
      );
      await tx.execute(
        Sql.named(
          '''INSERT INTO tapbix_online.deliveries(organization_id,target_database_id,event_id)
        SELECT organization_id,database_id,@id::uuid FROM tapbix_online.writers WHERE active AND database_id<>@db::uuid''',
        ),
        parameters: {'id': event.eventId, 'db': db},
      );
      next++;
      accepted.add(event.eventId);
    }
    await tx.execute(
      Sql.named(
        'UPDATE tapbix_online.writers SET next_sequence=@next WHERE database_id=@db::uuid',
      ),
      parameters: {'next': next, 'db': db},
    );
    return {'acceptedEventIds': accepted, 'nextExpectedSequence': next};
  }

  Future<Map<String, Object?>> _pull(
    TxSession tx,
    String org,
    String db,
    Map<String, Object?> body,
  ) async {
    final limit = body['limit'] ?? 50;
    if (limit is! int || limit < 1 || limit > 50) {
      throw const ApiFailure(400, 'invalid_batch_limit');
    }
    final active = await tx.execute(
      Sql.named(
        '''SELECT lease_token::text FROM tapbix_online.deliveries WHERE target_database_id=@db::uuid
      AND acknowledged_at IS NULL AND lease_until>now() ORDER BY lease_until LIMIT 1''',
      ),
      parameters: {'db': db},
    );
    final lease = active.isEmpty
        ? const Uuid().v4()
        : active.single[0] as String;
    if (active.isEmpty) {
      await tx.execute(
        Sql.named(
          '''UPDATE tapbix_online.deliveries SET lease_token=@lease::uuid,lease_until=now()+interval '60 seconds'
        WHERE target_database_id=@db::uuid AND event_id IN (
          SELECT d.event_id FROM tapbix_online.deliveries d JOIN tapbix_online.events e USING(organization_id,event_id)
          WHERE d.target_database_id=@db::uuid AND d.acknowledged_at IS NULL
          ORDER BY e.source_database_id,e.sequence LIMIT @limit)''',
        ),
        parameters: {'lease': lease, 'db': db, 'limit': limit},
      );
    }
    final rows = await tx.execute(
      Sql.named(
        '''SELECT e.envelope FROM tapbix_online.deliveries d JOIN tapbix_online.events e USING(organization_id,event_id)
      WHERE d.target_database_id=@db::uuid AND d.lease_token=@lease::uuid AND d.acknowledged_at IS NULL
      ORDER BY e.source_database_id,e.sequence''',
      ),
      parameters: {'db': db, 'lease': lease},
    );
    return {'leaseToken': lease, 'events': rows.map((r) => r[0]).toList()};
  }

  Future<Map<String, Object?>> _ack(
    TxSession tx,
    String org,
    String db,
    Map<String, Object?> body,
  ) async {
    final lease = _uuid(body, 'leaseToken');
    final ids = body['eventIds'];
    if (ids is! List || ids.isEmpty || ids.length > 50) {
      throw const ApiFailure(400, 'invalid_ack');
    }
    for (final id in ids) {
      if (id is! String || !Uuid.isValidUUID(fromString: id)) {
        throw const ApiFailure(400, 'invalid_ack');
      }
      final result = await tx.execute(
        Sql.named(
          '''UPDATE tapbix_online.deliveries SET acknowledged_at=coalesce(acknowledged_at,now())
        WHERE target_database_id=@db::uuid AND event_id=@id::uuid AND lease_token=@lease::uuid RETURNING event_id''',
        ),
        parameters: {'db': db, 'id': id, 'lease': lease},
      );
      if (result.isEmpty) throw const ApiFailure(409, 'lease_mismatch');
    }
    return {'acknowledged': ids.length};
  }
}
