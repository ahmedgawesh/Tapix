import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../lan/lan_models.dart';

class OnlineSyncException implements Exception {
  const OnlineSyncException(this.code);
  final String code;
  @override
  String toString() => 'OnlineSyncException($code)';
}

/// Online transport for the existing branch synchronization gateway contract.
/// Not selected by the production UI until station 7 enrollment is complete.
/// TLS verification remains enabled; credentials never follow redirects.
class OnlineSyncGateway implements LanBranchSyncGateway {
  OnlineSyncGateway({
    required Uri endpoint,
    required this.organizationId,
    Dio? client,
    bool allowLoopbackDevelopment = false,
  }) : _endpoint = endpoint,
       _client = client ?? Dio() {
    _client.options.connectTimeout ??= const Duration(seconds: 15);
    final loopback = const {
      '127.0.0.1',
      'localhost',
      '::1',
    }.contains(endpoint.host);
    if (endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment ||
        endpoint.host.isEmpty ||
        (endpoint.path.isNotEmpty && endpoint.path != '/') ||
        (endpoint.scheme != 'https' &&
            !(allowLoopbackDevelopment &&
                loopback &&
                endpoint.scheme == 'http'))) {
      throw ArgumentError(
        'An HTTPS origin is required for online synchronization.',
      );
    }
  }

  final String organizationId;
  final Uri _endpoint;
  final Dio _client;

  Future<Map<String, dynamic>> _post(
    String path,
    LanBranchSyncAuth? auth,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        _endpoint.resolve(path).toString(),
        data: body,
        options: Options(
          headers: {
            if (auth != null) 'Authorization': 'Bearer ${auth.accessToken}',
            'X-Organization-Id': organizationId,
          },
          contentType: Headers.jsonContentType,
          followRedirects: false,
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      final result = response.data;
      if (response.statusCode != 200) {
        final error = result?['error'];
        throw OnlineSyncException(
          error is String ? error : 'online_request_failed',
        );
      }
      if (result == null) {
        throw const OnlineSyncException('invalid_online_response');
      }
      return result;
    } on DioException {
      // Do not expose request options, credentials or raw server errors in UI.
      throw const OnlineSyncException('online_connection_unavailable');
    }
  }

  /// Validates the server-side binding before saving or using a credential.
  Future<OnlineWriterSession> inspectSession(LanBranchSyncAuth auth) async =>
      OnlineWriterSession.fromJson(await _post('/v1/session', auth, {}));

  /// Only a company owner credential can issue an identity-bound invitation.
  Future<Map<String, dynamic>> createInvitation(
    LanBranchSyncAuth auth, {
    required String databaseId,
    required String branchId,
    required String name,
  }) => _post('/v1/invitations', auth, {
    'databaseId': databaseId,
    'branchId': branchId,
    'name': name,
  });

  /// A timed invitation is exchanged once; subsequent connections use the
  /// saved credential. Retrying a lost response preserves the same identity.
  Future<String> enroll({
    required String databaseId,
    required String branchId,
    required String invitationCode,
  }) async {
    final result = await _post('/v1/enroll', null, {
      'databaseId': databaseId,
      'invitationCode': invitationCode,
    });
    final token = result['accessToken'];
    if (result['organizationId'] != organizationId ||
        result['databaseId'] != databaseId ||
        result['branchId'] != branchId ||
        token is! String ||
        token.length != 64 ||
        !RegExp(r'^[0-9a-f]+$').hasMatch(token)) {
      throw const OnlineSyncException('online_identity_mismatch');
    }
    return token;
  }

  @override
  Future<LanBranchSyncPushResult> push(
    LanBranchSyncAuth auth,
    List<Map<String, Object?>> events,
  ) async {
    final result = await _post('/v1/sync/push', auth, {'events': events});
    final ids = result['acceptedEventIds'];
    final next = result['nextExpectedSequence'];
    if (ids is! List ||
        ids.any((id) => id is! String) ||
        next is! int ||
        next < 1) {
      throw const OnlineSyncException('invalid_online_response');
    }
    final submitted = events.map((e) => e['eventId']).toSet();
    if (ids.any((id) => !submitted.contains(id))) {
      throw const OnlineSyncException('unexpected_online_acknowledgement');
    }
    return LanBranchSyncPushResult(
      acceptedEventIds: ids.cast<String>(),
      nextExpectedSequence: next,
    );
  }

  @override
  Future<LanBranchSyncPullResult> pull(
    LanBranchSyncAuth auth, {
    int limit = 50,
  }) async {
    final result = await _post('/v1/sync/pull', auth, {'limit': limit});
    final lease = result['leaseToken'];
    final events = result['events'];
    if (lease is! String ||
        events is! List ||
        events.any((e) => e is! Map<String, dynamic>)) {
      throw const OnlineSyncException('invalid_online_response');
    }
    return LanBranchSyncPullResult(
      leaseToken: lease,
      events: events.cast<Map<String, dynamic>>(),
    );
  }

  @override
  Future<void> acknowledge(
    LanBranchSyncAuth auth, {
    required String leaseToken,
    required List<String> eventIds,
  }) async {
    await _post('/v1/sync/ack', auth, {
      'leaseToken': leaseToken,
      'eventIds': eventIds,
    });
  }

  void close() => _client.close();
}

/// Confirmed identity returned by the authenticated online service.
class OnlineWriterSession {
  const OnlineWriterSession({
    required this.organizationId,
    required this.databaseId,
    required this.branchId,
    required this.relayId,
    required this.deviceName,
    required this.role,
  });
  final String organizationId, databaseId, branchId, relayId, deviceName, role;

  factory OnlineWriterSession.fromJson(Map<String, dynamic> json) {
    for (final key in ['organizationId', 'databaseId', 'branchId', 'relayId']) {
      final value = json[key];
      if (value is! String ||
          !Uuid.isValidUUID(fromString: value) ||
          value != value.toLowerCase()) {
        throw const OnlineSyncException('invalid_online_response');
      }
    }
    final name = json['deviceName'];
    final role = json['role'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > 80 ||
        (role != 'owner' && role != 'writer')) {
      throw const OnlineSyncException('invalid_online_response');
    }
    return OnlineWriterSession(
      organizationId: json['organizationId'] as String,
      databaseId: json['databaseId'] as String,
      branchId: json['branchId'] as String,
      relayId: json['relayId'] as String,
      deviceName: name,
      role: role as String,
    );
  }
}
