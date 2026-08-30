import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tapix/core/database/database_encryption.dart';
import 'package:tapix/core/database/database_native.dart';

class _FakeEncryptionKeyManager extends DatabaseEncryptionKeyManager {
  _FakeEncryptionKeyManager({required this.enabled, this.key});

  final bool enabled;
  final String? key;

  @override
  Future<bool> isEncryptionEnabled() async => enabled;

  @override
  Future<String?> getExistingKey() async => key;

  @override
  Future<String> getOrCreateKey() async {
    final value = key;
    if (value == null) {
      throw StateError('No test encryption key was configured.');
    }
    return value;
  }
}

void _createPlainDatabase(File file, String marker) {
  final db = sqlite.sqlite3.open(file.path);
  try {
    db.execute('CREATE TABLE source_marker (value TEXT NOT NULL);');
    db.execute('INSERT INTO source_marker VALUES (?);', [marker]);
  } finally {
    db.close();
  }
}

void _createEncryptedDatabase(File file, String key, String marker) {
  final escapedKey = key.replaceAll("'", "''");
  final db = sqlite.sqlite3.open(file.path);
  try {
    db.execute("PRAGMA cipher = 'sqlcipher';");
    db.execute('PRAGMA legacy = 4;');
    db.execute("PRAGMA key = '$escapedKey';");
    db.execute('CREATE TABLE source_marker (value TEXT NOT NULL);');
    db.execute('INSERT INTO source_marker VALUES (?);', [marker]);
  } finally {
    db.close();
  }
}

String _readMarker(File file, {String? encryptionKey}) {
  final db = sqlite.sqlite3.open(file.path);
  try {
    if (encryptionKey != null) {
      final escapedKey = encryptionKey.replaceAll("'", "''");
      db.execute("PRAGMA cipher = 'sqlcipher';");
      db.execute('PRAGMA legacy = 4;');
      db.execute("PRAGMA key = '$escapedKey';");
    }
    return db.select('SELECT value FROM source_marker;').single['value']
        as String;
  } finally {
    db.close();
  }
}

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'tapix_database_reliability_',
    );
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('backs up tapix.db when encryption is disabled', () async {
    final plainFile = File(p.join(tempDirectory.path, 'tapix.db'));
    final encryptedFile = File(
      p.join(tempDirectory.path, 'tapix_encrypted.db'),
    );
    _createPlainDatabase(plainFile, 'plain');
    _createPlainDatabase(encryptedFile, 'must-not-be-selected');

    final backup = await createDatabaseBackupFrom(
      databaseDirectory: tempDirectory,
      keyManager: _FakeEncryptionKeyManager(enabled: false),
    );

    expect(backup, isNotNull);
    expect(_readMarker(backup!), 'plain');
  });

  test(
    'backs up the encrypted active database without decrypting it',
    () async {
      const key = "safe-test-key-with-'quote";
      final plainFile = File(p.join(tempDirectory.path, 'tapix.db'));
      final encryptedFile = File(
        p.join(tempDirectory.path, 'tapix_encrypted.db'),
      );
      _createPlainDatabase(plainFile, 'plain');
      _createEncryptedDatabase(encryptedFile, key, 'encrypted');

      final backup = await createDatabaseBackupFrom(
        databaseDirectory: tempDirectory,
        keyManager: _FakeEncryptionKeyManager(enabled: true, key: key),
      );

      expect(backup, isNotNull);
      expect(_readMarker(backup!, encryptionKey: key), 'encrypted');
      expect(
        () => _readMarker(backup),
        throwsA(anything),
        reason: 'The backup must remain encrypted at rest.',
      );
    },
  );

  test('integrity check validates plain and encrypted databases', () async {
    final plainFile = File(p.join(tempDirectory.path, 'tapix.db'));
    _createPlainDatabase(plainFile, 'plain');

    expect(
      await checkDatabaseIntegrityFrom(
        databaseDirectory: tempDirectory,
        keyManager: _FakeEncryptionKeyManager(enabled: false),
      ),
      isTrue,
    );

    await plainFile.delete();
    const key = 'integrity-test-key';
    _createEncryptedDatabase(
      File(p.join(tempDirectory.path, 'tapix_encrypted.db')),
      key,
      'encrypted',
    );

    expect(
      await checkDatabaseIntegrityFrom(
        databaseDirectory: tempDirectory,
        keyManager: _FakeEncryptionKeyManager(enabled: true, key: key),
      ),
      isTrue,
    );
  });

  test('encrypted database fails safely when its key is missing', () async {
    const key = 'existing-key';
    _createEncryptedDatabase(
      File(p.join(tempDirectory.path, 'tapix_encrypted.db')),
      key,
      'encrypted',
    );
    final manager = _FakeEncryptionKeyManager(enabled: true);

    expect(
      await createDatabaseBackupFrom(
        databaseDirectory: tempDirectory,
        keyManager: manager,
      ),
      isNull,
    );
    expect(
      await checkDatabaseIntegrityFrom(
        databaseDirectory: tempDirectory,
        keyManager: manager,
      ),
      isFalse,
    );
  });

  test('backup retention keeps only the three newest copies', () async {
    _createPlainDatabase(File(p.join(tempDirectory.path, 'tapix.db')), 'plain');
    final manager = _FakeEncryptionKeyManager(enabled: false);

    for (var i = 0; i < 5; i++) {
      expect(
        await createDatabaseBackupFrom(
          databaseDirectory: tempDirectory,
          keyManager: manager,
        ),
        isNotNull,
      );
    }

    final backups = Directory(p.join(tempDirectory.path, 'backups'))
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path).startsWith('tapix_backup_'))
        .toList();
    expect(backups, hasLength(3));
  });

  test('pre-migration backup runs only when schema versions differ', () async {
    final databaseFile = File(p.join(tempDirectory.path, 'tapix.db'));
    _createPlainDatabase(databaseFile, 'before-migration');
    final db = sqlite.sqlite3.open(databaseFile.path);
    try {
      db.userVersion = 41;
    } finally {
      db.close();
    }
    final manager = _FakeEncryptionKeyManager(enabled: false);

    final skipped = await createPreMigrationBackupIfNeededFrom(
      dbFolder: tempDirectory,
      keyManager: manager,
      encryptionEnabled: false,
      targetSchemaVersion: 41,
    );
    expect(skipped, isNull);

    final backup = await createPreMigrationBackupIfNeededFrom(
      dbFolder: tempDirectory,
      keyManager: manager,
      encryptionEnabled: false,
      targetSchemaVersion: 42,
    );
    expect(backup, isNotNull);
    expect(_readMarker(backup!), 'before-migration');
  });
}
