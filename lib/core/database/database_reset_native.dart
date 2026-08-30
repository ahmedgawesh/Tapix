import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String> getDatabaseLocationImpl() async {
  // Must match the path used in database_native.dart (getApplicationSupportDirectory)
  final dbFolder = await getApplicationSupportDirectory();
  return p.join(dbFolder.path, 'tapix.db');
}

Future<bool> deleteDatabaseFileImpl() async {
  final path = await getDatabaseLocationImpl();
  final file = File(path);
  if (await file.exists()) {
    await file.delete();
    return true;
  }
  return false;
}

Future<void> deleteAllLocalDatabaseFilesImpl() async {
  final dbFolder = await getApplicationSupportDirectory();
  const databaseNames = ['tapix.db', 'tapix_encrypted.db'];
  const suffixes = ['', '-wal', '-shm'];

  for (final name in databaseNames) {
    for (final suffix in suffixes) {
      final file = File(p.join(dbFolder.path, '$name$suffix'));
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}
