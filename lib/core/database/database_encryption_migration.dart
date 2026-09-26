import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// Cipher profiles understood by TapBix database recovery.
///
/// [canonical] is the only profile used for newly encrypted databases. The
/// other profiles exist solely to repair databases created by older builds.
enum DatabaseCipherProfile { canonical, legacyChacha20, sqlCipherCurrent }

const _criticalCountTables = <String>{
  'users',
  'products',
  'variants',
  'sales',
  'sale_items',
  'purchases',
  'purchase_items',
  // Used by the focused file-level tests.
  'source_marker',
};

String escapeSqlLiteral(String value) => value.replaceAll("'", "''");

/// Applies the one production cipher configuration used by TapBix.
void applyCanonicalCipherPragmas(sqlite.Database db, String key) {
  final escapedKey = escapeSqlLiteral(key);
  db.execute("PRAGMA cipher = 'sqlcipher';");
  db.execute('PRAGMA legacy = 4;');
  db.execute("PRAGMA key = '$escapedKey';");
}

void _applyCipherProfile(
  sqlite.Database db,
  String key,
  DatabaseCipherProfile profile,
) {
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
}

sqlite.Database openEncryptedDatabase(
  File file,
  String key, {
  DatabaseCipherProfile profile = DatabaseCipherProfile.canonical,
}) {
  final db = sqlite.sqlite3.open(file.path);
  try {
    _applyCipherProfile(db, key, profile);
    // PRAGMA key is lazy. Force a schema read before returning so callers never
    // mistake a connection with the wrong key/profile for a valid database.
    db.select('SELECT count(*) FROM sqlite_master;');
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}

bool _integrityIsOk(sqlite.Database db) {
  final rows = db.select('PRAGMA integrity_check;');
  if (rows.length != 1) return false;
  final column = rows.columnNames.first;
  return rows.single[column]?.toString().trim().toLowerCase() == 'ok';
}

class DatabaseVerificationSnapshot {
  const DatabaseVerificationSnapshot({
    required this.userVersion,
    required this.schemaObjectCount,
    required this.criticalRowCounts,
  });

  final int userVersion;
  final int schemaObjectCount;
  final Map<String, int> criticalRowCounts;

  @override
  bool operator ==(Object other) {
    if (other is! DatabaseVerificationSnapshot ||
        userVersion != other.userVersion ||
        schemaObjectCount != other.schemaObjectCount ||
        criticalRowCounts.length != other.criticalRowCounts.length) {
      return false;
    }
    for (final entry in criticalRowCounts.entries) {
      if (other.criticalRowCounts[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    userVersion,
    schemaObjectCount,
    Object.hashAll(
      criticalRowCounts.entries.map(
        (entry) => Object.hash(entry.key, entry.value),
      ),
    ),
  );
}

DatabaseVerificationSnapshot captureDatabaseVerificationSnapshot(
  sqlite.Database db,
) {
  if (!_integrityIsOk(db)) {
    throw StateError('Database integrity check failed.');
  }

  final schemaObjectCount =
      db
              .select(
                'SELECT count(*) AS value FROM sqlite_master '
                "WHERE name NOT LIKE 'sqlite_%';",
              )
              .single['value']
          as int;
  final tableRows = db.select(
    "SELECT name FROM sqlite_master WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%';",
  );
  final presentTables = <String>{
    for (final row in tableRows) row['name'] as String,
  };
  final counts = <String, int>{};
  for (final table in _criticalCountTables.intersection(presentTables)) {
    // Names originate from sqlite_master and are limited to a fixed allow-list.
    counts[table] =
        db.select('SELECT count(*) AS value FROM "$table";').single['value']
            as int;
  }

  return DatabaseVerificationSnapshot(
    userVersion: db.userVersion,
    schemaObjectCount: schemaObjectCount,
    criticalRowCounts: counts,
  );
}

DatabaseVerificationSnapshot snapshotPlainDatabase(File file) {
  final db = sqlite.sqlite3.open(file.path);
  try {
    return captureDatabaseVerificationSnapshot(db);
  } finally {
    db.close();
  }
}

DatabaseVerificationSnapshot snapshotEncryptedDatabase(
  File file,
  String key, {
  DatabaseCipherProfile profile = DatabaseCipherProfile.canonical,
}) {
  final db = openEncryptedDatabase(file, key, profile: profile);
  try {
    return captureDatabaseVerificationSnapshot(db);
  } finally {
    db.close();
  }
}

void _requireSameSnapshot(
  DatabaseVerificationSnapshot expected,
  DatabaseVerificationSnapshot actual,
  String operation,
) {
  if (expected != actual) {
    throw StateError(
      '$operation verification did not match the source database.',
    );
  }
}

void _requireCheckpoint(sqlite.Database db) {
  final rows = db.select('PRAGMA wal_checkpoint(TRUNCATE);');
  if (rows.isEmpty) return;
  final busy = rows.first[rows.columnNames.first];
  if (busy is num && busy != 0) {
    throw StateError('Database WAL checkpoint is busy ($busy).');
  }
}

Future<void> checkpointPlainDatabase(File file) async {
  final db = sqlite.sqlite3.open(file.path);
  try {
    _requireCheckpoint(db);
  } finally {
    db.close();
  }
}

Future<void> checkpointEncryptedDatabase(
  File file,
  String key, {
  DatabaseCipherProfile profile = DatabaseCipherProfile.canonical,
}) async {
  final db = openEncryptedDatabase(file, key, profile: profile);
  try {
    _requireCheckpoint(db);
  } finally {
    db.close();
  }
}

/// Produces a self-contained plain SQLite snapshot, including committed WAL.
Future<void> snapshotPlainDatabaseTo(File source, File target) async {
  if (await target.exists()) await target.delete();
  final db = sqlite.sqlite3.open(source.path);
  try {
    final escapedTarget = escapeSqlLiteral(target.path);
    try {
      db.execute("VACUUM INTO '$escapedTarget';");
    } catch (_) {
      _requireCheckpoint(db);
      await source.copy(target.path);
    }
  } finally {
    db.close();
  }
}

/// Encrypts a standalone plain database in-place with the canonical profile.
Future<void> encryptPlainDatabaseInPlace(File file, String key) async {
  final db = sqlite.sqlite3.open(file.path);
  try {
    db.execute('PRAGMA journal_mode = DELETE;');
    db.execute("PRAGMA cipher = 'sqlcipher';");
    db.execute('PRAGMA legacy = 4;');
    db.execute("PRAGMA rekey = '${escapeSqlLiteral(key)}';");
  } finally {
    db.close();
  }
  snapshotEncryptedDatabase(file, key);
}

/// Removes encryption from a standalone encrypted database copy.
Future<void> decryptEncryptedDatabaseInPlace(
  File file,
  String key, {
  DatabaseCipherProfile profile = DatabaseCipherProfile.canonical,
}) async {
  final db = openEncryptedDatabase(file, key, profile: profile);
  try {
    db.execute('PRAGMA journal_mode = DELETE;');
    db.execute("PRAGMA rekey = '';");
  } finally {
    db.close();
  }
  snapshotPlainDatabase(file);
}

Future<DatabaseCipherProfile?> detectEncryptedDatabaseProfile(
  File file,
  String key,
) async {
  for (final profile in DatabaseCipherProfile.values) {
    try {
      snapshotEncryptedDatabase(file, key, profile: profile);
      return profile;
    } catch (_) {
      // Expected while probing a legacy profile. The source file is untouched.
    }
  }
  return null;
}

Future<void> deleteDatabaseSidecars(File file) async {
  for (final suffix in const ['-wal', '-shm']) {
    final sidecar = File('${file.path}$suffix');
    if (await sidecar.exists()) await sidecar.delete();
  }
}

/// Best-effort overwrite before deletion.
///
/// Flash wear-levelling and filesystem snapshots mean physical erasure cannot
/// be guaranteed. Cryptographic key destruction remains the primary control.
Future<void> secureDeleteDatabaseFile(File file) async {
  await deleteDatabaseSidecars(file);
  if (!await file.exists()) return;
  final length = await file.length();
  RandomAccessFile? handle;
  try {
    handle = await file.open(mode: FileMode.write);
    const chunkSize = 64 * 1024;
    final zeroes = List<int>.filled(chunkSize, 0);
    var remaining = length;
    while (remaining > 0) {
      final count = min(remaining, chunkSize);
      await handle.writeFrom(zeroes, 0, count);
      remaining -= count;
    }
    await handle.flush();
  } finally {
    await handle?.close();
  }
  await file.delete();
}

Future<void> atomicReplaceDatabase(File temporary, File target) async {
  await deleteDatabaseSidecars(target);
  final recovery = File('${target.path}.replace-backup');
  if (await recovery.exists()) await recovery.delete();
  var movedOldTarget = false;
  try {
    if (await target.exists()) {
      await target.rename(recovery.path);
      movedOldTarget = true;
    }
    await temporary.rename(target.path);
    if (movedOldTarget) {
      try {
        await secureDeleteDatabaseFile(recovery);
      } catch (error, stackTrace) {
        developer.log(
          'A verified replacement is active, but its obsolete recovery copy '
          'could not be removed.',
          name: 'DB_ENCRYPTION',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  } catch (_) {
    if (!await target.exists() && movedOldTarget && await recovery.exists()) {
      await recovery.rename(target.path);
    }
    rethrow;
  }
}

Future<void> discardEncryptionMigrationTemps(Directory folder) async {
  for (final name in const ['tapix.db.tmp', 'tapix_encrypted.db.tmp']) {
    final file = File(p.join(folder.path, name));
    if (await file.exists()) await file.delete();
    await deleteDatabaseSidecars(file);
  }

  // A process can be killed between moving the old target aside and renaming
  // the verified replacement. Restore the old target if that happened. When
  // both exist, keep the recovery copy until the new target has been opened
  // and verified by the state machine.
  for (final name in const ['tapix.db', 'tapix_encrypted.db']) {
    final target = File(p.join(folder.path, name));
    final recovery = File('${target.path}.replace-backup');
    if (!await target.exists() && await recovery.exists()) {
      await recovery.rename(target.path);
    }
  }
}

Future<void> discardVerifiedReplacementRecovery(File target) async {
  final recovery = File('${target.path}.replace-backup');
  if (await recovery.exists()) {
    await secureDeleteDatabaseFile(recovery);
  }
}

Future<void> enableDatabaseEncryption({
  required File plainFile,
  required File encryptedFile,
  required String key,
}) async {
  final expected = snapshotPlainDatabase(plainFile);
  final temporary = File('${encryptedFile.path}.tmp');
  try {
    await snapshotPlainDatabaseTo(plainFile, temporary);
    await encryptPlainDatabaseInPlace(temporary, key);
    final actual = snapshotEncryptedDatabase(temporary, key);
    _requireSameSnapshot(expected, actual, 'Encryption migration');
    await atomicReplaceDatabase(temporary, encryptedFile);
    try {
      await secureDeleteDatabaseFile(plainFile);
    } catch (error, stackTrace) {
      developer.log(
        'Encryption is active, but the obsolete plain database could not be removed.',
        name: 'DB_ENCRYPTION',
        error: error,
        stackTrace: stackTrace,
      );
    }
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    await deleteDatabaseSidecars(temporary);
    rethrow;
  }
}

Future<void> disableDatabaseEncryption({
  required File encryptedFile,
  required File plainFile,
  required String key,
}) async {
  final expected = snapshotEncryptedDatabase(encryptedFile, key);
  final temporary = File('${plainFile.path}.tmp');
  try {
    await checkpointEncryptedDatabase(encryptedFile, key);
    await encryptedFile.copy(temporary.path);
    await decryptEncryptedDatabaseInPlace(temporary, key);
    final actual = snapshotPlainDatabase(temporary);
    _requireSameSnapshot(expected, actual, 'Encryption disable');
    await atomicReplaceDatabase(temporary, plainFile);
    try {
      await secureDeleteDatabaseFile(encryptedFile);
    } catch (error, stackTrace) {
      developer.log(
        'Plain database export is active, but the encrypted source could not be removed.',
        name: 'DB_ENCRYPTION',
        error: error,
        stackTrace: stackTrace,
      );
    }
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    await deleteDatabaseSidecars(temporary);
    rethrow;
  }
}

Future<void> repairEncryptedDatabase({
  required File encryptedFile,
  required String key,
}) async {
  final profile = await detectEncryptedDatabaseProfile(encryptedFile, key);
  if (profile == null) {
    throw StateError(
      'Encrypted database cannot be opened with any known cipher configuration.',
    );
  }
  if (profile == DatabaseCipherProfile.canonical) return;

  final expected = snapshotEncryptedDatabase(
    encryptedFile,
    key,
    profile: profile,
  );
  final temporary = File('${encryptedFile.path}.tmp');
  try {
    await checkpointEncryptedDatabase(encryptedFile, key, profile: profile);
    await encryptedFile.copy(temporary.path);
    await decryptEncryptedDatabaseInPlace(temporary, key, profile: profile);
    await encryptPlainDatabaseInPlace(temporary, key);
    final actual = snapshotEncryptedDatabase(temporary, key);
    _requireSameSnapshot(expected, actual, 'Legacy encryption repair');
    await atomicReplaceDatabase(temporary, encryptedFile);
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    await deleteDatabaseSidecars(temporary);
    rethrow;
  }
}

Future<File> quarantineLegacyPlainDatabase({
  required Directory databaseFolder,
  required File plainFile,
  required String key,
}) async {
  final backups = Directory(p.join(databaseFolder.path, 'backups'));
  await backups.create(recursive: true);
  final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    ':',
    '-',
  );
  final output = File(p.join(backups.path, 'legacy_plain_$timestamp.db'));
  final temporary = File('${output.path}.tmp');
  final expected = snapshotPlainDatabase(plainFile);
  try {
    await snapshotPlainDatabaseTo(plainFile, temporary);
    await encryptPlainDatabaseInPlace(temporary, key);
    final actual = snapshotEncryptedDatabase(temporary, key);
    _requireSameSnapshot(expected, actual, 'Legacy plain quarantine');
    await temporary.rename(output.path);
    try {
      await secureDeleteDatabaseFile(plainFile);
    } catch (error, stackTrace) {
      developer.log(
        'Legacy plain database was quarantined, but its obsolete source could not be removed.',
        name: 'DB_ENCRYPTION',
        error: error,
        stackTrace: stackTrace,
      );
    }
    developer.log(
      'Legacy plain database quarantined as an encrypted support backup.',
      name: 'DB_ENCRYPTION',
    );
    return output;
  } catch (_) {
    if (await temporary.exists()) await temporary.delete();
    await deleteDatabaseSidecars(temporary);
    rethrow;
  }
}
