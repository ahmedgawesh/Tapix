import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'generate_comprehensive_acceptance_database.dart' as generator;

void main() {
  test('generate comprehensive acceptance database', () async {
    final outputPath = Platform.environment['TAPIX_ACCEPTANCE_DB_PATH'];
    final temp = outputPath == null
        ? await Directory.systemTemp.createTemp('tapix_acceptance_')
        : null;
    if (temp != null) addTearDown(() => temp.delete(recursive: true));
    final path = outputPath ?? '${temp!.path}/acceptance.db';
    await generator.main([path]);
    expect(File(path).existsSync(), isTrue);
    // Running an acceptance check must never replace an existing device backup.
    await expectLater(generator.main([path]), throwsStateError);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
