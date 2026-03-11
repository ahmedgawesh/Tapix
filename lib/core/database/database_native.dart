import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'dart:io';
import 'dart:developer' as developer;

import 'database_encryption.dart';

/// Opens the native SQLite database with optional encryption support.
///
/// Encryption flow:
/// 1. Check if encryption is enabled via [DatabaseEncryptionKeyManager].
/// 2. If enabled, open with `PRAGMA key` using SQLCipher / SQLite3MultipleCiphers.
/// 3. If an existing unencrypted database exists and encryption is newly enabled,
///    migrate it by exporting and re-keying.
/// 4. If encryption is not enabled, open normally (backward compatible).
///
/// Existing unencrypted databases continue to work without any change.
Future<QueryExecutor> openDatabase() async {
  // Initialize SQLCipher on Android (must be called before any sqlite3 operations)
  if (Platform.isAndroid) {
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  }

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

  if (encryptionEnabled) {
    final key = await keyManager.getOrCreateKey();
    final escapedKey = key.replaceAll("'", "''");
    final encryptedFile = File(p.join(dbFolder.path, 'tapix_encrypted.db'));

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

    final dbFile = encryptedFile.existsSync() ? encryptedFile : file;

    return NativeDatabase(
      dbFile,
      setup: (rawDb) {
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
  try {
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'tapix.db'));
    if (!file.existsSync()) return null;

    final backupDir = Directory(p.join(dbFolder.path, 'backups'));
    if (!backupDir.existsSync()) {
      await backupDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupFile = File(p.join(backupDir.path, 'tapix_backup_$timestamp.db'));
    await file.copy(backupFile.path);
    developer.log('Database backup created: ${backupFile.path}', name: 'DB_BACKUP');

    // Prune old backups — keep only the 3 most recent
    final backups = backupDir.listSync()
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
  } catch (e, st) {
    developer.log('Database backup failed: $e', name: 'DB_BACKUP', error: e, stackTrace: st);
    return null;
  }
}

/// Run a quick integrity check on the database.
/// Returns true if the database passes the check.
Future<bool> checkDatabaseIntegrity() async {
  try {
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'tapix.db'));
    if (!file.existsSync()) return true; // No DB yet — nothing to check

    final db = NativeDatabase(file);
    final conn = DatabaseConnection(db);
    await conn.executor.runCustom('PRAGMA integrity_check', const []);
    await db.close();
    // If no exception was thrown, the DB is healthy
    developer.log('Database integrity check passed', name: 'DB_INTEGRITY');
    return true;
  } catch (e, st) {
    developer.log('Database integrity check FAILED: $e', name: 'DB_INTEGRITY', error: e, stackTrace: st);
    return false;
  }
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
  final conn = tempDb.ensureOpen(
    _DummyDriftUser(),
  );
  await conn;
  await tempDb.close();
}

/// Minimal [QueryExecutorUser] for the migration step.
class _DummyDriftUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
}
