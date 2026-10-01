import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'online_sync_gateway.dart';

/// Copyable setup data. Requests contain no credential; invitations and owner
/// activation codes must be treated as secrets and never logged.
class OnlineSetupCode {
  const OnlineSetupCode({
    required this.type,
    required this.organizationId,
    required this.databaseId,
    required this.branchId,
    required this.name,
    this.endpoint,
    this.secret,
    this.expiresAt,
  });
  final String type, organizationId, databaseId, branchId, name;
  final Uri? endpoint;
  final String? secret;
  final DateTime? expiresAt;

  String encode() => base64Url.encode(
    utf8.encode(
      jsonEncode({
        'format': 'tapbix.online.setup',
        'version': 1,
        'type': type,
        'organizationId': organizationId,
        'databaseId': databaseId,
        'branchId': branchId,
        'name': name,
        if (endpoint != null) 'endpoint': endpoint.toString(),
        if (secret != null) 'secret': secret,
        if (expiresAt != null)
          'expiresAt': expiresAt!.toUtc().toIso8601String(),
      }),
    ),
  );

  factory OnlineSetupCode.decode(String encoded, {DateTime? now}) {
    try {
      if (encoded.length > 8192) throw const FormatException();
      final json =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(encoded.trim())),
                ),
              )
              as Map<String, dynamic>;
      if (json['format'] != 'tapbix.online.setup' ||
          json['version'] != 1 ||
          !const {
            'request',
            'invitation',
            'activation',
          }.contains(json['type'])) {
        throw const FormatException();
      }
      for (final key in ['organizationId', 'databaseId', 'branchId']) {
        final value = json[key];
        if (value is! String ||
            !Uuid.isValidUUID(fromString: value) ||
            value != value.toLowerCase()) {
          throw const FormatException();
        }
      }
      final name = json['name'];
      if (name is! String || name.trim().isEmpty || name.length > 80) {
        throw const FormatException();
      }
      final type = json['type'] as String;
      Uri? endpoint;
      String? secret;
      DateTime? expiry;
      if (type != 'request') {
        endpoint = Uri.parse(json['endpoint'] as String);
        if (endpoint.host.isEmpty ||
            endpoint.userInfo.isNotEmpty ||
            endpoint.hasQuery ||
            endpoint.hasFragment ||
            (endpoint.path.isNotEmpty && endpoint.path != '/') ||
            (endpoint.scheme != 'https' &&
                !(endpoint.scheme == 'http' &&
                    const {
                      '127.0.0.1',
                      'localhost',
                      '::1',
                    }.contains(endpoint.host)))) {
          throw const FormatException();
        }

        secret = json['secret'] as String;
        if (!RegExp(r'^[A-Za-z0-9_-]{32,128}$').hasMatch(secret)) {
          throw const FormatException();
        }
        expiry = DateTime.parse(json['expiresAt'] as String).toUtc();
        if (!expiry.isAfter((now ?? DateTime.now()).toUtc())) {
          throw const OnlineSyncException('online_invitation_expired');
        }
      } else if (json.containsKey('secret') || json.containsKey('endpoint')) {
        throw const FormatException();
      }
      return OnlineSetupCode(
        type: type,
        organizationId: json['organizationId'] as String,
        databaseId: json['databaseId'] as String,
        branchId: json['branchId'] as String,
        name: name,
        endpoint: endpoint,
        secret: secret,
        expiresAt: expiry,
      );
    } on OnlineSyncException {
      rethrow;
    } catch (_) {
      throw const OnlineSyncException('online_code_invalid');
    }
  }
}

class OnlinePilot {
  static const enabled = bool.fromEnvironment('TAPBIX_ONLINE_PILOT');
  // Development HTTP is allowed only for an explicit loopback build. Actual
  // devices connecting across a network always require HTTPS.
  static const loopback = bool.fromEnvironment('TAPBIX_ONLINE_LOOPBACK');
}
