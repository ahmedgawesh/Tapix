import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:tapbix_online/online_service.dart';

Future<void> main() async {
  final url = Platform.environment['TAPBIX_DATABASE_URL'];
  if (url == null) {
    throw StateError(
      'Set TAPBIX_DATABASE_URL for the restricted API database role.',
    );
  }
  final service = OnlineService(() => Connection.openFromUrl(url));
  final server = await service.start(
    port: int.parse(Platform.environment['TAPBIX_API_PORT'] ?? '45830'),
  );
  stdout.writeln(
    'TapBix online development service: http://127.0.0.1:${server.port}',
  );
  ProcessSignal.sigint.watch().listen((_) async {
    await server.close(force: true);
    exit(0);
  });
  ProcessSignal.sigterm.watch().listen((_) async {
    await server.close(force: true);
    exit(0);
  });
}
