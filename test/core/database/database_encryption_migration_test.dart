import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tapix/core/database/database_encryption.dart';
import 'package:tapix/core/database/database_encryption_migration.dart';
import 'package:tapix/core/database/database_native.dart';

class _FakeEncryptionKeyManager extends DatabaseEncryptionKeyManager {
  _FakeEncryptionKeyManager({required this.enabled, required this.key});

  final bool enabled;
  final String? key;

  @override
  Future<bool> isEncryptionEnabled() async => enabled;

  @override
  Future<String?> getExistingKey() async => key;

  @override
  Future<String> getOrCreateKey() async {
    return key ?? (throw StateError('No test encryption key configured.'));
  }
}

void _createPlainDatabase(File file, String marker, {int rows = 1}) {
  final db = sqlite.sqlite3.open(file.path);
  try {
    db.execute('CREATE TABLE source_marker (value TEXT NOT NULL);');
    for (var i = 0; i < rows; i++) {
      db.execute('INSERT INTO source_marker VALUES (?);', ['$marker-$i']);
    }
    db.userVersion = 17;
  } finally {
    db.close();
  }
}

void _createEncryptedDatabase(
  File file,
  String key,
  String marker, {
  DatabaseCipherProfile profile = DatabaseCipherProfile.canonical,
}) {
  final db = sqlite.sqlite3.open(file.path);
  try {
    final escapedKey = escapeSqlLiteral(key);
    switch (profile) {
      case DatabaseCipherProfile.canonical:
        applyCanonicalCipherPragmas(db, key);
      case DatabaseCipherProfile.legacyChacha20:
        db.execute("PRAGMA cipher = 'chacha20';");
        db.execute("PRAGMA key = '$escapedKey';");
      case DatabaseCipherProfile.sqlCipherCurrent:
        db.execute("PRAGMA cipher = 'sqlcipher';");
        db.execute("PRAGMA key = '$escapedKey';");
    }
    db.execute('CREATE TABLE source_marker (value TEXT NOT NULL);');
    db.execute('INSERT INTO source_marker VALUES (?);', [marker]);
    db.userVersion = 17;
  } finally {
    db.close();
  }
}

List<String> _readPlainMarkers(File file) {
  final db = sqlite.sqlite3.open(file.path);
  try {
    return [
      for (final row in db.select(
        'SELECT value FROM source_marker ORDER BY value',
      ))
        row['value'] as String,
    ];
  } finally {
    db.close();
  }
}

List<String> _readEncryptedMarkers(File file, String key) {
  final db = openEncryptedDatabase(file, key);
  try {
    return [
      for (final row in db.select(
        'SELECT value FROM source_marker ORDER BY value',
      ))
        row['value'] as String,
    ];
  } finally {
    db.close();
  }
}

void main() {
  const key = "migration-test-key-with-'quote";
  late Directory folder;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp(
      'tapix_encryption_migration_',
    );
  });

  tearDown(() async {
    if (await folder.exists()) await folder.delete(recursive: true);
  });

  test('enabling encryption uses the production cipher profile', () async {
    final plain = File(p.join(folder.path, 'tapix.db'));
    final encrypted = File(p.join(folder.path, 'tapix_encrypted.db'));
    _createPlainDatabase(plain, 'canonical', rows: 3);

    final executor = await openDatabaseFrom(
      dbFolder: folder,
      keyManager: _FakeEncryptionKeyManager(enabled: true, key: key),
    );
    await executor.close();

    expect(await plain.exists(), isFalse);
    expect(_readEncryptedMarkers(encrypted, key), [
      'canonical-0',
      'canonical-1',
      'canonical-2',
    ]);
    expect(
      () => _readPlainMarkers(encrypted),
      throwsA(anything),
      reason: 'The encrypted file must not open without its key.',
    );
  });

  test('migration includes committed rows held in WAL', () async {
    final plain = File(p.join(folder.path, 'tapix.db'));
    final writer = sqlite.sqlite3.open(plain.path);
    writer.execute('PRAGMA journal_mode = WAL;');
    writer.execute('PRAGMA wal_autocheckpoint = 0;');
    writer.execute('CREATE TABLE source_marker (value TEXT NOT NULL);');
    writer.execute("INSERT INTO source_marker VALUES ('wal-row');");
    expect(File('${plain.path}-wal').existsSync(), isTrue);

    final executor = await openDatabaseFrom(
      dbFolder: folder,
      keyManager: _FakeEncryptionKeyManager(enabled: true, key: key),
    );
    await executor.close();
    writer.close();

    expect(
      _readEncryptedMarkers(
        File(p.join(folder.path, 'tapix_encrypted.db')),
        key,
      ),
      ['wal-row'],
    );
  });

  test(
    'failed enable keeps the readable plain database and removes temp',
    () async {
      final plain = File(p.join(folder.path, 'tapix.db'));
      _createPlainDatabase(plain, 'safe');
      await Directory(p.join(folder.path, 'tapix_encrypted.db')).create();

      expect(
        () => enableDatabaseEncryption(
          plainFile: plain,
          encryptedFile: File(p.join(folder.path, 'tapix_encrypted.db')),
          key: key,
        ),
        throwsA(anything),
      );
      expect(_readPlainMarkers(plain), ['safe-0']);
      expect(
        File(p.join(folder.path, 'tapix_encrypted.db.tmp')).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'leftover temp is removed and interrupted replacement is restored',
    () async {
      final temp = File(p.join(folder.path, 'tapix_encrypted.db.tmp'));
      temp.writeAsStringSync('unfinished');
      final recovery = File(p.join(folder.path, 'tapix.db.replace-backup'));
      _createPlainDatabase(recovery, 'recovered');

      await discardEncryptionMigrationTemps(folder);

      expect(temp.existsSync(), isFalse);
      expect(recovery.existsSync(), isFalse);
      expect(_readPlainMarkers(File(p.join(folder.path, 'tapix.db'))), [
        'recovered-0',
      ]);
    },
  );

  test(
    'legacy chacha database is repaired and stale plain is quarantined',
    () async {
      final plain = File(p.join(folder.path, 'tapix.db'));
      final encrypted = File(p.join(folder.path, 'tapix_encrypted.db'));
      _createPlainDatabase(plain, 'stale-plain');
      _createEncryptedDatabase(
        encrypted,
        key,
        'legacy-active',
        profile: DatabaseCipherProfile.legacyChacha20,
      );

      final executor = await openDatabaseFrom(
        dbFolder: folder,
        keyManager: _FakeEncryptionKeyManager(enabled: true, key: key),
      );
      await executor.close();

      expect(_readEncryptedMarkers(encrypted, key), ['legacy-active']);
      expect(plain.existsSync(), isFalse);
      final quarantined = Directory(p.join(folder.path, 'backups'))
          .listSync()
          .whereType<File>()
          .where((file) => p.basename(file.path).startsWith('legacy_plain_'))
          .single;
      expect(_readEncryptedMarkers(quarantined, key), ['stale-plain-0']);
    },
  );

  test('unopenable encrypted database is preserved', () async {
    final encrypted = File(p.join(folder.path, 'tapix_encrypted.db'));
    final bytes = List<int>.generate(2048, (index) => index % 251);
    encrypted.writeAsBytesSync(bytes);

    await expectLater(
      openDatabaseFrom(
        dbFolder: folder,
        keyManager: _FakeEncryptionKeyManager(enabled: true, key: key),
      ),
      throwsA(isA<StateError>()),
    );
    expect(encrypted.readAsBytesSync(), bytes);
  });

  test('disabling encryption exports all data to a plain database', () async {
    final encrypted = File(p.join(folder.path, 'tapix_encrypted.db'));
    _createEncryptedDatabase(encrypted, key, 'decrypted');

    final executor = await openDatabaseFrom(
      dbFolder: folder,
      keyManager: _FakeEncryptionKeyManager(enabled: false, key: key),
    );
    await executor.close();

    final plain = File(p.join(folder.path, 'tapix.db'));
    expect(_readPlainMarkers(plain), ['decrypted']);
    expect(encrypted.existsSync(), isFalse);
  });
}
