import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'dart:io';
import 'dart:developer' as developer;

import 'database_encryption.dart';

/// Opens the native SQLite database with optional encryption support.
///
/// Encryption flow:
/// 1. Check if encryption is enabled via [DatabaseEncryptionKeyManager].
/// 2. If enabled, open with `PRAGMA key` using SQLite3MultipleCiphers.
/// 3. If an existing unencrypted database exists and encryption is newly enabled,
///    migrate it by exporting and re-keying.
/// 4. If encryption is not enabled, open normally (backward compatible).
///
/// Existing unencrypted databases continue to work without any change.
/// SQLite3MultipleCiphers is compatible with existing SQLCipher databases.
Future<QueryExecutor> openDatabase({int? targetSchemaVersion}) async {
  // sqlite3 v3 uses build hooks — no manual library loading needed.

  // Use getApplicationSupportDirectory instead of getApplicationDocumentsDirectory
  // so the database is deleted when the app is uninstalled on Android
  final dbFolder = await getApplicationSupportDirectory();

  // Ensure the directory exists
  if (!dbFolder.existsSync()) {
    debugPrint('Creating database directory: ${dbFolder.path}');
    await dbFolder.create(recursive: true);
  }

  final file = File(p.join(dbFolder.path, 'tapix.db'));
  debugPrint('Opening database at: ${file.path}');
  debugPrint('Database file exists: ${file.existsSync()}');

  final keyManager = DatabaseEncryptionKeyManager();
  final encryptionEnabled = await keyManager.isEncryptionEnabled();
  debugPrint('Encryption enabled: $encryptionEnabled');

  if (targetSchemaVersion != null) {
    // This runs before Drift opens the database and starts onUpgrade. Keeping
    // the backup outside the migration transaction also lets us checkpoint WAL
    // safely so the copied .db file is self-contained.
    await createPreMigrationBackupIfNeededFrom(
      dbFolder: dbFolder,
      keyManager: keyManager,
      encryptionEnabled: encryptionEnabled,
      targetSchemaVersion: targetSchemaVersion,
    );
  }

  if (encryptionEnabled) {
    final encryptedFile = File(p.join(dbFolder.path, 'tapix_encrypted.db'));
    final key = encryptedFile.existsSync()
        ? await _requireExistingEncryptionKey(keyManager)
        : await keyManager.getOrCreateKey();
    final escapedKey = key.replaceAll("'", "''");

    // Migrate existing unencrypted DB → encrypted DB (one-time)
    if (file.existsSync() && !encryptedFile.existsSync()) {
      debugPrint('Migrating unencrypted database to encrypted...');
      try {
        await _migrateToEncrypted(file, encryptedFile, escapedKey);
        debugPrint('Database migration to encrypted completed.');
      } catch (e) {
        debugPrint('WARNING: Encryption migration failed: $e');
        debugPrint('Falling back to unencrypted database.');
        return NativeDatabase(file);
      }
    }

    final dbFile = _selectActiveDatabaseFile(dbFolder, encryptionEnabled: true);

    return NativeDatabase(
      dbFile,
      setup: (rawDb) {
        // SQLite3MultipleCiphers: set cipher to sqlcipher-compatible mode
        rawDb.execute("PRAGMA cipher = 'sqlcipher';");
        rawDb.execute('PRAGMA legacy = 4;');
        rawDb.execute("PRAGMA key = '$escapedKey';");
      },
    );
  }

  return NativeDatabase(file);
}

/// Create a timestamped backup of the database file before schema migrations.
/// Returns the backup [File] on success, or null if backup was skipped/failed.
/// Keeps only the 3 most recent backups to avoid unbounded disk usage.
Future<File?> createDatabaseBackup() async {
  return createDatabaseBackupFrom(databaseDirectory: null, keyManager: null);
}

/// Creates a backup of the database file that is actually active.
///
/// Optional dependencies are exposed for focused tests only. Production
/// callers should use [createDatabaseBackup].
@visibleForTesting
Future<File?> createDatabaseBackupFrom({
  Directory? databaseDirectory,
  DatabaseEncryptionKeyManager? keyManager,
}) async {
  try {
    final dbFolder =
        databaseDirectory ?? await getApplicationSupportDirectory();
    final manager = keyManager ?? DatabaseEncryptionKeyManager();
    final target = await _resolveExistingDatabaseTarget(dbFolder, manager);
    if (target == null) return null;

    return await _createDatabaseBackupForTarget(dbFolder, target);
  } catch (e, st) {
    developer.log(
      'Database backup failed: $e',
      name: 'DB_BACKUP',
      error: e,
      stackTrace: st,
    );
    return null;
  }
}

/// Run a quick integrity check on the database.
/// Returns true if the database passes the check.
Future<bool> checkDatabaseIntegrity() async {
  return checkDatabaseIntegrityFrom(databaseDirectory: null, keyManager: null);
}

/// Checks the database that is actually active and validates SQLite's result.
///
/// Optional dependencies are exposed for focused tests only. Production
/// callers should use [checkDatabaseIntegrity].
@visibleForTesting
Future<bool> checkDatabaseIntegrityFrom({
  Directory? databaseDirectory,
  DatabaseEncryptionKeyManager? keyManager,
}) async {
  sqlite.Database? db;
  try {
    final dbFolder =
        databaseDirectory ?? await getApplicationSupportDirectory();
    final manager = keyManager ?? DatabaseEncryptionKeyManager();
    final target = await _resolveExistingDatabaseTarget(dbFolder, manager);
    if (target == null) return true; // No DB yet — nothing to check

    db = _openRawDatabase(target);
    final rows = db.select('PRAGMA integrity_check;');
    final resultColumn = rows.columnNames.first;
    final messages = <String>[
      for (final row in rows) row[resultColumn]?.toString().trim() ?? '',
    ];
    final isHealthy =
        messages.length == 1 && messages.single.toLowerCase() == 'ok';

    if (!isHealthy) {
      developer.log(
        'Database integrity check reported ${messages.length} issue(s)',
        name: 'DB_INTEGRITY',
      );
      return false;
    }

    developer.log('Database integrity check passed', name: 'DB_INTEGRITY');
    return true;
  } catch (e, st) {
    developer.log(
      'Database integrity check FAILED: $e',
      name: 'DB_INTEGRITY',
      error: e,
      stackTrace: st,
    );
    return false;
  } finally {
    db?.close();
  }
}

class _DatabaseTarget {
  const _DatabaseTarget({
    required this.file,
    required this.isEncrypted,
    this.escapedKey,
  });

  final File file;
  final bool isEncrypted;
  final String? escapedKey;
}

File _selectActiveDatabaseFile(
  Directory dbFolder, {
  required bool encryptionEnabled,
}) {
  final encryptedFile = File(p.join(dbFolder.path, 'tapix_encrypted.db'));
  if (encryptionEnabled && encryptedFile.existsSync()) {
    return encryptedFile;
  }
  return File(p.join(dbFolder.path, 'tapix.db'));
}

Future<_DatabaseTarget?> _resolveExistingDatabaseTarget(
  Directory dbFolder,
  DatabaseEncryptionKeyManager keyManager, {
  bool? encryptionEnabled,
}) async {
  final enabled = encryptionEnabled ?? await keyManager.isEncryptionEnabled();
  final file = _selectActiveDatabaseFile(dbFolder, encryptionEnabled: enabled);
  if (!file.existsSync()) {
    return null;
  }

  final isEncrypted = enabled && p.basename(file.path) == 'tapix_encrypted.db';
  if (!isEncrypted) {
    return _DatabaseTarget(file: file, isEncrypted: false);
  }

  final key = await _requireExistingEncryptionKey(keyManager);
  return _DatabaseTarget(
    file: file,
    isEncrypted: true,
    escapedKey: key.replaceAll("'", "''"),
  );
}

Future<String> _requireExistingEncryptionKey(
  DatabaseEncryptionKeyManager keyManager,
) async {
  final key = await keyManager.getExistingKey();
  if (key == null) {
    throw StateError(
      'Database encryption is enabled but its secure-storage key is missing.',
    );
  }
  return key;
}

sqlite.Database _openRawDatabase(_DatabaseTarget target) {
  final db = sqlite.sqlite3.open(target.file.path);
  try {
    if (target.isEncrypted) {
      db.execute("PRAGMA cipher = 'sqlcipher';");
      db.execute('PRAGMA legacy = 4;');
      db.execute("PRAGMA key = '${target.escapedKey}';");
    }
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}

Future<void> _checkpointDatabase(_DatabaseTarget target) async {
  final db = _openRawDatabase(target);
  try {
    final rows = db.select('PRAGMA wal_checkpoint(TRUNCATE);');
    if (rows.isNotEmpty) {
      final busy = rows.first[rows.columnNames.first];
      if (busy is num && busy != 0) {
        throw StateError(
          'Could not checkpoint the database WAL before backup (busy=$busy).',
        );
      }
    }
  } finally {
    db.close();
  }
}

Future<File> _createDatabaseBackupForTarget(
  Directory dbFolder,
  _DatabaseTarget target,
) async {
  await _checkpointDatabase(target);

  final backupDir = Directory(p.join(dbFolder.path, 'backups'));
  if (!backupDir.existsSync()) {
    await backupDir.create(recursive: true);
  }

  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final backupFile = File(p.join(backupDir.path, 'tapix_backup_$timestamp.db'));
  final temporaryFile = File('${backupFile.path}.tmp');

  try {
    await target.file.copy(temporaryFile.path);
    final sourceLength = await target.file.length();
    final backupLength = await temporaryFile.length();
    if (sourceLength != backupLength) {
      throw StateError(
        'Database backup size verification failed '
        '(source=$sourceLength, copy=$backupLength).',
      );
    }
    await temporaryFile.rename(backupFile.path);
  } catch (_) {
    if (await temporaryFile.exists()) {
      await temporaryFile.delete();
    }
    rethrow;
  }

  developer.log(
    'Database backup created: ${backupFile.path} '
    '(encrypted=${target.isEncrypted})',
    name: 'DB_BACKUP',
  );

  // Prune old backups — keep only the 3 most recent.
  final backups =
      backupDir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('tapix_backup_'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
  for (final old in backups.skip(3)) {
    try {
      await old.delete();
    } catch (_) {}
  }

  return backupFile;
}

/// Creates a verified backup only when the stored schema needs migration.
///
/// Public for focused reliability tests; application code invokes this through
/// [openDatabase] before Drift is allowed to open the database.
@visibleForTesting
Future<File?> createPreMigrationBackupIfNeededFrom({
  required Directory dbFolder,
  required DatabaseEncryptionKeyManager keyManager,
  required bool encryptionEnabled,
  required int targetSchemaVersion,
}) async {
  final target = await _resolveExistingDatabaseTarget(
    dbFolder,
    keyManager,
    encryptionEnabled: encryptionEnabled,
  );
  if (target == null) return null;

  sqlite.Database? db;
  int currentSchemaVersion;
  try {
    db = _openRawDatabase(target);
    currentSchemaVersion = db.userVersion;
  } finally {
    db?.close();
  }

  if (currentSchemaVersion == targetSchemaVersion) {
    return null;
  }

  final backup = await _createDatabaseBackupForTarget(dbFolder, target);
  developer.log(
    'Pre-migration backup ready: ${backup.path} '
    '($currentSchemaVersion → $targetSchemaVersion)',
    name: 'DB_MIGRATION',
  );
  return backup;
}

/// Migrate an unencrypted database to an encrypted one.
///
/// Uses VACUUM INTO to create a plain copy, then applies PRAGMA rekey
/// to encrypt it in-place.
Future<void> _migrateToEncrypted(
  File plainFile,
  File encryptedFile,
  String escapedKey,
) async {
  // Copy the plain database to the encrypted path first
  await plainFile.copy(encryptedFile.path);

  // Open the copy and apply encryption via PRAGMA rekey
  final tempDb = NativeDatabase(
    encryptedFile,
    setup: (rawDb) {
      rawDb.execute("PRAGMA rekey = '$escapedKey';");
    },
  );

  // Force the database to open (triggers setup callback)
  final conn = tempDb.ensureOpen(_DummyDriftUser());
  await conn;
  await tempDb.close();
}

/// Minimal [QueryExecutorUser] for the migration step.
class _DummyDriftUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
