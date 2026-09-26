import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'dart:io';
import 'dart:developer' as developer;

import 'database_encryption.dart';
import 'database_encryption_migration.dart';

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
  final dbFolder = await getApplicationSupportDirectory();
  final keyManager = DatabaseEncryptionKeyManager();
  return openDatabaseFrom(
    dbFolder: dbFolder,
    keyManager: keyManager,
    targetSchemaVersion: targetSchemaVersion,
  );
}

/// Opens a database from an explicit folder.
///
/// Production delegates here after resolving the support directory. Keeping
/// the file-state machine independent from path_provider lets the real
/// sqlite3mc engine exercise every migration and recovery path in tests.
@visibleForTesting
Future<QueryExecutor> openDatabaseFrom({
  required Directory dbFolder,
  required DatabaseEncryptionKeyManager keyManager,
  int? targetSchemaVersion,
}) async {
  await dbFolder.create(recursive: true);
  await discardEncryptionMigrationTemps(dbFolder);

  final plainFile = File(p.join(dbFolder.path, 'tapix.db'));
  final encryptedFile = File(p.join(dbFolder.path, 'tapix_encrypted.db'));
  final encryptionEnabled = await keyManager.isEncryptionEnabled();
  debugPrint('Encryption enabled: $encryptionEnabled');

  String? activeEncryptionKey;
  var activeIsEncrypted = false;

  if (encryptionEnabled) {
    activeEncryptionKey = encryptedFile.existsSync()
        ? await _requireExistingEncryptionKey(keyManager)
        : await keyManager.getOrCreateKey();

    if (encryptedFile.existsSync()) {
      await repairEncryptedDatabase(
        encryptedFile: encryptedFile,
        key: activeEncryptionKey,
      );
      await discardVerifiedReplacementRecovery(encryptedFile);
      if (plainFile.existsSync()) {
        await quarantineLegacyPlainDatabase(
          databaseFolder: dbFolder,
          plainFile: plainFile,
          key: activeEncryptionKey,
        );
      }
    } else if (plainFile.existsSync()) {
      try {
        await enableDatabaseEncryption(
          plainFile: plainFile,
          encryptedFile: encryptedFile,
          key: activeEncryptionKey,
        );
        await discardVerifiedReplacementRecovery(encryptedFile);
      } catch (error, stackTrace) {
        developer.log(
          'Encryption migration failed; the verified plain database remains active.',
          name: 'DB_ENCRYPTION',
          error: error,
          stackTrace: stackTrace,
        );
        if (targetSchemaVersion != null) {
          await createPreMigrationBackupIfNeededFrom(
            dbFolder: dbFolder,
            keyManager: keyManager,
            encryptionEnabled: false,
            targetSchemaVersion: targetSchemaVersion,
          );
        }
        return NativeDatabase(plainFile);
      }
    }
    activeIsEncrypted = true;
  } else if (encryptedFile.existsSync()) {
    activeEncryptionKey = await _requireExistingEncryptionKey(keyManager);
    await repairEncryptedDatabase(
      encryptedFile: encryptedFile,
      key: activeEncryptionKey,
    );
    await discardVerifiedReplacementRecovery(encryptedFile);
    if (plainFile.existsSync()) {
      await quarantineLegacyPlainDatabase(
        databaseFolder: dbFolder,
        plainFile: plainFile,
        key: activeEncryptionKey,
      );
    }
    try {
      await disableDatabaseEncryption(
        encryptedFile: encryptedFile,
        plainFile: plainFile,
        key: activeEncryptionKey,
      );
      await discardVerifiedReplacementRecovery(plainFile);
    } catch (error, stackTrace) {
      developer.log(
        'Encryption disable failed; continuing with the encrypted database.',
        name: 'DB_ENCRYPTION',
        error: error,
        stackTrace: stackTrace,
      );
      activeIsEncrypted = true;
    }
  }

  if (targetSchemaVersion != null) {
    await createPreMigrationBackupIfNeededFrom(
      dbFolder: dbFolder,
      keyManager: keyManager,
      encryptionEnabled: activeIsEncrypted,
      targetSchemaVersion: targetSchemaVersion,
    );
  }

  if (activeIsEncrypted) {
    final key =
        activeEncryptionKey ?? await _requireExistingEncryptionKey(keyManager);
    return NativeDatabase(
      encryptedFile,
      setup: (rawDb) => applyCanonicalCipherPragmas(rawDb, key),
    );
  }
  return NativeDatabase(plainFile);
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
    this.encryptionKey,
  });

  final File file;
  final bool isEncrypted;
  final String? encryptionKey;
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
  final preferred = _selectActiveDatabaseFile(
    dbFolder,
    encryptionEnabled: enabled,
  );
  final fallback = File(
    p.join(dbFolder.path, enabled ? 'tapix.db' : 'tapix_encrypted.db'),
  );
  final file = preferred.existsSync() ? preferred : fallback;
  if (!file.existsSync()) return null;

  final isEncrypted = p.basename(file.path) == 'tapix_encrypted.db';
  if (!isEncrypted) {
    return _DatabaseTarget(file: file, isEncrypted: false);
  }

  final key = await _requireExistingEncryptionKey(keyManager);
  return _DatabaseTarget(file: file, isEncrypted: true, encryptionKey: key);
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
      applyCanonicalCipherPragmas(db, target.encryptionKey!);
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
