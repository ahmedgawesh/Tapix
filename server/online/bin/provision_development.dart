import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:tapbix_online/online_service.dart';
import 'package:uuid/uuid.dart';

/// Creates an isolated demo company. This is not paid entitlement validation.
Future<void> main(List<String> args) async {
  if (args.length != 1 &&
      (args.length != 5 || args[0] != '--request' || args[2] != '--endpoint')) {
    throw ArgumentError(
      'Use OUTPUT.json or --request REQUEST.txt --endpoint ORIGIN OUTPUT.json.',
    );
  }
  final output = File(args.last);
  Map<String, dynamic>? binding;
  final endpoint = Uri.parse(
    args.length == 5 ? args[3] : 'http://127.0.0.1:45830',
  );
  if (endpoint.host.isEmpty ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment ||
      (endpoint.path.isNotEmpty && endpoint.path != '/') ||
      (endpoint.scheme != 'https' &&
          !(endpoint.scheme == 'http' && endpoint.host == '127.0.0.1'))) {
    throw ArgumentError(
      'Use an HTTPS origin or the explicit development loopback origin.',
    );
  }
  if (args.length == 5) {
    final requestFile = File(args[1]);
    if (await requestFile.length() > 8192) {
      throw ArgumentError('Request too large.');
    }
    final text = (await requestFile.readAsString()).trim();
    binding =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(text))))
            as Map<String, dynamic>;
    if (binding['format'] != 'tapbix.online.setup' ||
        binding['version'] != 1 ||
        binding['type'] != 'request' ||
        binding['name'] is! String ||
        (binding['name'] as String).trim().isEmpty ||
        (binding['name'] as String).length > 80) {
      throw ArgumentError('Invalid branch binding request.');
    }
    for (final key in ['organizationId', 'databaseId', 'branchId']) {
      if (binding[key] is! String ||
          !Uuid.isValidUUID(fromString: binding[key] as String) ||
          binding[key] != (binding[key] as String).toLowerCase()) {
        throw ArgumentError('Invalid branch identity.');
      }
    }
  }
  if (output.existsSync()) {
    throw StateError('Refusing to overwrite credentials.');
  }
  final url = Platform.environment['TAPBIX_DEVELOPMENT_ADMIN_URL'];
  if (url == null) throw StateError('Set TAPBIX_DEVELOPMENT_ADMIN_URL.');
  final uri = Uri.parse(url);
  if (uri.host != '127.0.0.1' || uri.path != '/tapbix_online_dev') {
    throw StateError(
      'Development provisioning is restricted to loopback tapbix_online_dev.',
    );
  }
  final connection = await Connection.openFromUrl(url);
  const uuid = Uuid();
  final org = binding?['organizationId'] as String? ?? uuid.v4(),
      db = binding?['databaseId'] as String? ?? uuid.v4(),
      branch = binding?['branchId'] as String? ?? uuid.v4(),
      token = newSecret();
  final name = binding?['name'] as String? ?? 'Development main branch';
  try {
    await connection.runTx((tx) async {
      await tx.execute(
        Sql.named(
          "INSERT INTO tapbix_online.organizations VALUES(@org::uuid,'TapBix development company',now()+interval '7 days')",
        ),
        parameters: {'org': org},
      );
      await tx.execute(
        Sql.named(
          'INSERT INTO tapbix_online.writers(organization_id,database_id,branch_id,name) VALUES(@org::uuid,@db::uuid,@branch::uuid,@name)',
        ),
        parameters: {'org': org, 'db': db, 'branch': branch, 'name': name},
      );
      await tx.execute(
        Sql.named(
          "INSERT INTO tapbix_online.credentials VALUES(@org::uuid,@hash,@db::uuid,'owner',true)",
        ),
        parameters: {'org': org, 'hash': tokenDigest(token), 'db': db},
      );
      await output.create(exclusive: true);
      // This development tool runs on Linux; fail before writing secrets if chmod fails.
      final mode = await Process.run('chmod', ['600', output.path]);
      if (mode.exitCode != 0) {
        throw StateError('Cannot secure credential file.');
      }
      await output.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'organizationId': org,
          'databaseId': db,
          'branchId': branch,
          'accessToken': token,
          'developmentOnly': true,
          'activationCode': base64Url.encode(
            utf8.encode(
              jsonEncode({
                'format': 'tapbix.online.setup',
                'version': 1,
                'type': 'activation',
                'organizationId': org,
                'databaseId': db,
                'branchId': branch,
                'name': name,
                'endpoint': endpoint.toString(),
                'secret': token,
                'expiresAt': DateTime.now()
                    .toUtc()
                    .add(const Duration(days: 7))
                    .toIso8601String(),
              }),
            ),
          ),
        }),
      );
    });
    stdout.writeln(
      'Created a seven-day development company. Credentials saved to ${output.path}.',
    );
  } finally {
    await connection.close();
  }
}
