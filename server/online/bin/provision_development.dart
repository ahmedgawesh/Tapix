import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:tapbix_online/online_service.dart';
import 'package:uuid/uuid.dart';

/// Creates an isolated demo company. This is not paid entitlement validation.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Provide a NEW private output JSON path.');
  }
  final output = File(args.single);
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
  final org = uuid.v4(),
      db = uuid.v4(),
      branch = uuid.v4(),
      token = newSecret();
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
          "INSERT INTO tapbix_online.writers(organization_id,database_id,branch_id,name) VALUES(@org::uuid,@db::uuid,@branch::uuid,'Development main branch')",
        ),
        parameters: {'org': org, 'db': db, 'branch': branch},
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
