import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tapix/core/database/database_encryption.dart';
import 'package:tapix/core/database/database_encryption_migration.dart';
import 'package:tapix/core/services/backup/database_backup_service.dart';

class _FakeKeyManager extends DatabaseEncryptionKeyManager {
  _FakeKeyManager({required this.enabled, this.key});

  final bool enabled;
  final String? key;

  @override
  Future<bool> isEncryptionEnabled() async => enabled;

  @override
  Future<String?> getExistingKey() async => key;

  @override
  Future<String> getOrCreateKey() async =>
      key ?? (throw StateError('Missing test key'));
}

void _createTapixDatabase(File file, String marker, {int version = 17}) {
  final db = sqlite.sqlite3.open(file.path);
  try {
    db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);');
    db.execute(
      'CREATE TABLE sales (id INTEGER PRIMARY KEY, invoice_number TEXT);',
    );
    db.execute('CREATE TABLE source_marker (value TEXT NOT NULL);');
    db.execute('INSERT INTO users (name) VALUES (?);', ['owner-$marker']);
    db.execute('INSERT INTO sales (invoice_number) VALUES (?);', [marker]);
    db.execute('INSERT INTO source_marker VALUES (?);', [marker]);
    db.userVersion = version;
  } finally {
    db.close();
  }
}

String _plainMarker(File file) {
  final db = sqlite.sqlite3.open(file.path);
  try {
    return db.select('SELECT value FROM source_marker;').single['value']
        as String;
  } finally {
    db.close();
  }
}

String _encryptedMarker(File file, String key) {
  final db = openEncryptedDatabase(file, key);
  try {
    return db.select('SELECT value FROM source_marker;').single['value']
        as String;
  } finally {
    db.close();
  }
}

void main() {
  const deviceKey = 'device-secure-key';
  const passphrase = 'portable-backup-passphrase';
  late Directory folder;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('tapix_backup_service_');
  });

  tearDown(() async {
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  test('encrypted live database requires a portable passphrase', () async {
    final encrypted = File(p.join(folder.path, 'tapix_encrypted.db'));
    _createTapixDatabase(encrypted, 'encrypted');
    await encryptPlainDatabaseInPlace(encrypted, deviceKey);
    final service = DatabaseBackupService(
      databaseDirectory: folder,
      keyManager: _FakeKeyManager(enabled: true, key: deviceKey),
    );

    await expectLater(
      service.createPortableBackup(
        destination: File(p.join(folder.path, 'backup.db')),
      ),
      throwsA(isA<BackupPassphraseRequiredException>()),
    );
  });

  test('passphrase backup restores on a different plain device', () async {
    final encrypted = File(p.join(folder.path, 'tapix_encrypted.db'));
    _createTapixDatabase(encrypted, 'portable');
    await encryptPlainDatabaseInPlace(encrypted, deviceKey);
    final source = DatabaseBackupService(
      databaseDirectory: folder,
      keyManager: _FakeKeyManager(enabled: true, key: deviceKey),
    );
    final portable = await source.createPortableBackup(
      destination: File(p.join(folder.path, 'portable.db')),
      passphrase: passphrase,
    );
    expect(await DatabaseBackupService.isPlainSqliteFile(portable), isFalse);

    final targetFolder = await Directory.systemTemp.createTemp(
      'tapix_backup_target_',
    );
    addTearDown(() async {
      if (await targetFolder.exists()) {
        await targetFolder.delete(recursive: true);
      }
    });
    _createTapixDatabase(
      File(p.join(targetFolder.path, 'tapix.db')),
      'old-target',
    );
    final target = DatabaseBackupService(
      databaseDirectory: targetFolder,
      keyManager: _FakeKeyManager(enabled: false),
    );
    await target.restorePortableBackup(
      backup: portable,
      passphrase: passphrase,
      currentSchemaVersion: 17,
      closeDatabase: () async {},
    );

    expect(
      _plainMarker(File(p.join(targetFolder.path, 'tapix.db'))),
      'portable',
    );
    expect(
      Directory(p.join(targetFolder.path, 'backups'))
          .listSync()
          .whereType<File>()
          .where((file) => p.basename(file.path).startsWith('pre_restore_')),
      isNotEmpty,
    );
  });

  test('plain portable backup restores into encrypted mode', () async {
    final plain = File(p.join(folder.path, 'tapix.db'));
    _createTapixDatabase(plain, 'incoming');
    final source = DatabaseBackupService(
      databaseDirectory: folder,
      keyManager: _FakeKeyManager(enabled: false),
    );
    final portable = await source.createPortableBackup(
      destination: File(p.join(folder.path, 'plain-backup.db')),
    );

    final targetFolder = await Directory.systemTemp.createTemp(
      'tapix_encrypted_target_',
    );
    addTearDown(() async {
      if (await targetFolder.exists()) {
        await targetFolder.delete(recursive: true);
      }
    });
    final oldEncrypted = File(p.join(targetFolder.path, 'tapix_encrypted.db'));
    _createTapixDatabase(oldEncrypted, 'old');
    await encryptPlainDatabaseInPlace(oldEncrypted, deviceKey);
    final target = DatabaseBackupService(
      databaseDirectory: targetFolder,
      keyManager: _FakeKeyManager(enabled: true, key: deviceKey),
    );
    await target.restorePortableBackup(
      backup: portable,
      currentSchemaVersion: 17,
      closeDatabase: () async {},
    );

    expect(_encryptedMarker(oldEncrypted, deviceKey), 'incoming');
    expect(File(p.join(targetFolder.path, 'tapix.db')).existsSync(), isFalse);
  });

  test('wrong passphrase never changes the live database', () async {
    final plain = File(p.join(folder.path, 'tapix.db'));
    _createTapixDatabase(plain, 'live');
    final service = DatabaseBackupService(
      databaseDirectory: folder,
      keyManager: _FakeKeyManager(enabled: false),
    );
    final protected = File(p.join(folder.path, 'protected.db'));
    final sourcePlain = File(p.join(folder.path, 'source.db'));
    _createTapixDatabase(sourcePlain, 'incoming');
    await encryptPlainDatabaseInPlace(sourcePlain, passphrase);
    await sourcePlain.rename(protected.path);

    await expectLater(
      service.restorePortableBackup(
        backup: protected,
        passphrase: 'this-is-the-wrong-passphrase',
        currentSchemaVersion: 17,
        closeDatabase: () async {},
      ),
      throwsA(isA<BackupPassphraseInvalidException>()),
    );
    expect(_plainMarker(plain), 'live');
  });

  test('newer schema is rejected before closing the live database', () async {
    final live = File(p.join(folder.path, 'tapix.db'));
    _createTapixDatabase(live, 'live');
    final newer = File(p.join(folder.path, 'newer.db'));
    _createTapixDatabase(newer, 'newer', version: 18);
    var closed = false;
    final service = DatabaseBackupService(
      databaseDirectory: folder,
      keyManager: _FakeKeyManager(enabled: false),
    );

    await expectLater(
      service.restorePortableBackup(
        backup: newer,
        currentSchemaVersion: 17,
        closeDatabase: () async => closed = true,
      ),
      throwsA(isA<BackupFromNewerVersionException>()),
    );
    expect(closed, isFalse);
    expect(_plainMarker(live), 'live');
  });
}
