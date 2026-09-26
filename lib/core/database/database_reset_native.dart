import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database_encryption_migration.dart';

Future<String> getDatabaseLocationImpl() async {
  final dbFolder = await getApplicationSupportDirectory();
  return p.join(dbFolder.path, 'tapix.db');
}

Future<bool> deleteDatabaseFileImpl() async {
  final dbFolder = await getApplicationSupportDirectory();
  final existed = _localDatabaseArtifacts(
    dbFolder,
  ).any((file) => file.existsSync());
  await deleteAllLocalDatabaseFilesImpl();
  return existed;
}

Iterable<File> _localDatabaseArtifacts(Directory folder) sync* {
  const names = [
    'tapix.db',
    'tapix_encrypted.db',
    'tapix.db.tmp',
    'tapix_encrypted.db.tmp',
    'tapix.db.replace-backup',
    'tapix_encrypted.db.replace-backup',
    'tapix_restore_import.tmp',
  ];
  const suffixes = ['', '-wal', '-shm'];
  for (final name in names) {
    for (final suffix in suffixes) {
      yield File(p.join(folder.path, '$name$suffix'));
    }
  }
}

Future<void> deleteAllLocalDatabaseFilesImpl() async {
  final dbFolder = await getApplicationSupportDirectory();
  for (final file in _localDatabaseArtifacts(dbFolder)) {
    if (await file.exists()) await secureDeleteDatabaseFile(file);
  }

  // Internal migration and pre-restore backups are part of the local database
  // state. User-created portable backups in Downloads/Documents are untouched.
  final backups = Directory(p.join(dbFolder.path, 'backups'));
  if (await backups.exists()) {
    await for (final entity in backups.list(recursive: true)) {
      if (entity is File) await secureDeleteDatabaseFile(entity);
    }
    if (await backups.exists()) await backups.delete(recursive: true);
  }
}
