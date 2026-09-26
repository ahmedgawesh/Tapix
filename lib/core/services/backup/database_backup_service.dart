import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../database/database_encryption.dart';
import '../../database/database_encryption_migration.dart';

class BackupPassphraseRequiredException implements Exception {
  const BackupPassphraseRequiredException();
}

class BackupPassphraseInvalidException implements Exception {
  const BackupPassphraseInvalidException();
}

class BackupFromNewerVersionException implements Exception {
  const BackupFromNewerVersionException(this.version);
  final int version;
}

class InvalidTapixBackupException implements Exception {
  const InvalidTapixBackupException();
}

class DatabaseBackupService {
  DatabaseBackupService({
    DatabaseEncryptionKeyManager? keyManager,
    Directory? databaseDirectory,
  }) : _keyManager = keyManager ?? DatabaseEncryptionKeyManager(),
       _databaseDirectory = databaseDirectory;

  static const int minimumPassphraseLength = 12;

  final DatabaseEncryptionKeyManager _keyManager;
  final Directory? _databaseDirectory;

  Future<Directory> _folder() async =>
      _databaseDirectory ?? await getApplicationSupportDirectory();

  Future<bool> get activeDatabaseIsEncrypted async =>
      (await _activeDatabase()).encrypted;

  Future<({File file, bool encrypted, String? key})> _activeDatabase() async {
    final folder = await _folder();
    final plain = File(p.join(folder.path, 'tapix.db'));
    final encrypted = File(p.join(folder.path, 'tapix_encrypted.db'));
    final enabled = await _keyManager.isEncryptionEnabled();

    if ((enabled && await encrypted.exists()) ||
        (!await plain.exists() && await encrypted.exists())) {
      final key = await _keyManager.getExistingKey();
      if (key == null || key.isEmpty) {
        throw StateError(
          'The encrypted database key is missing from secure storage.',
        );
      }
      return (file: encrypted, encrypted: true, key: key);
    }
    return (file: plain, encrypted: false, key: null);
  }

  /// Creates a portable, self-contained backup.
  ///
  /// When the live database is encrypted, [passphrase] is mandatory. The
  /// exported snapshot is re-encrypted with that user-owned passphrase rather
  /// than the device secure-storage key, so it remains restorable after a
  /// reinstall or on another device.
  Future<File> createPortableBackup({
    required File destination,
    String? passphrase,
  }) async {
    final active = await _activeDatabase();
    if (!await active.file.exists()) {
      throw const InvalidTapixBackupException();
    }
    if (active.encrypted && !_validPassphrase(passphrase)) {
      throw const BackupPassphraseRequiredException();
    }
    if (passphrase != null &&
        passphrase.isNotEmpty &&
        !_validPassphrase(passphrase)) {
      throw const BackupPassphraseRequiredException();
    }

    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    if (await temporary.exists()) await temporary.delete();

    try {
      if (active.encrypted) {
        await checkpointEncryptedDatabase(active.file, active.key!);
        await active.file.copy(temporary.path);
        await decryptEncryptedDatabaseInPlace(temporary, active.key!);
      } else {
        await snapshotPlainDatabaseTo(active.file, temporary);
      }

      // Validate the portable plain snapshot before optionally protecting it.
      snapshotPlainDatabase(temporary);
      if (passphrase != null && passphrase.isNotEmpty) {
        await encryptPlainDatabaseInPlace(temporary, passphrase);
        snapshotEncryptedDatabase(temporary, passphrase);
      }

      if (await destination.exists()) await destination.delete();
      await temporary.rename(destination.path);
      return destination;
    } catch (_) {
      if (await temporary.exists()) {
        await secureDeleteDatabaseFile(temporary);
      }
      rethrow;
    }
  }

  /// Validates and restores a portable backup without overwriting a live file
  /// until the replacement has passed integrity, schema and product checks.
  Future<void> restorePortableBackup({
    required File backup,
    required int currentSchemaVersion,
    required Future<void> Function() closeDatabase,
    String? passphrase,
  }) async {
    final folder = await _folder();
    await folder.create(recursive: true);
    final importedPlain = File(p.join(folder.path, 'tapix_restore_import.tmp'));
    if (await importedPlain.exists()) await importedPlain.delete();
    await backup.copy(importedPlain.path);

    File? safetyCopy;
    File? liveTarget;
    var replacementStarted = false;
    try {
      if (!await _hasPlainSqliteHeader(importedPlain)) {
        if (!_validPassphrase(passphrase)) {
          throw const BackupPassphraseRequiredException();
        }
        try {
          await decryptEncryptedDatabaseInPlace(importedPlain, passphrase!);
        } catch (_) {
          throw const BackupPassphraseInvalidException();
        }
      }

      final importedSnapshot = _validateTapixBackup(
        importedPlain,
        currentSchemaVersion: currentSchemaVersion,
      );

      await closeDatabase();
      final active = await _activeDatabase();
      liveTarget = active.file;
      safetyCopy = await _createPreRestoreSafetyCopy(active);

      final replacement = File('${liveTarget.path}.tmp');
      if (await replacement.exists()) await replacement.delete();
      await importedPlain.copy(replacement.path);
      if (active.encrypted) {
        await encryptPlainDatabaseInPlace(replacement, active.key!);
        final actual = snapshotEncryptedDatabase(replacement, active.key!);
        if (actual != importedSnapshot) {
          throw StateError('Encrypted restore verification failed.');
        }
      } else {
        final actual = snapshotPlainDatabase(replacement);
        if (actual != importedSnapshot) {
          throw StateError('Plain restore verification failed.');
        }
      }

      replacementStarted = true;
      await atomicReplaceDatabase(replacement, liveTarget);
      await discardVerifiedReplacementRecovery(liveTarget);

      final obsolete = File(
        p.join(
          folder.path,
          active.encrypted ? 'tapix.db' : 'tapix_encrypted.db',
        ),
      );
      try {
        if (await obsolete.exists()) await secureDeleteDatabaseFile(obsolete);
        await _prunePreRestoreCopies(folder);
      } on Object catch (error, stackTrace) {
        // The verified replacement is already active. A cleanup failure must
        // not roll it back or report the restore itself as failed.
        developer.log(
          'Portable restore completed but cleanup was incomplete.',
          name: 'DB_BACKUP',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } catch (_) {
      if (replacementStarted && safetyCopy != null && liveTarget != null) {
        final rollback = File('${liveTarget.path}.tmp');
        if (await rollback.exists()) await rollback.delete();
        await safetyCopy.copy(rollback.path);
        await atomicReplaceDatabase(rollback, liveTarget);
      }
      rethrow;
    } finally {
      if (await importedPlain.exists()) {
        await secureDeleteDatabaseFile(importedPlain);
      }
    }
  }

  DatabaseVerificationSnapshot _validateTapixBackup(
    File file, {
    required int currentSchemaVersion,
  }) {
    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(file.path);
      final snapshot = captureDatabaseVerificationSnapshot(db);
      if (snapshot.userVersion <= 0) {
        throw const InvalidTapixBackupException();
      }
      if (snapshot.userVersion > currentSchemaVersion) {
        throw BackupFromNewerVersionException(snapshot.userVersion);
      }
      final tables = db
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name IN ('users', 'sales');",
          )
          .map((row) => row['name'] as String)
          .toSet();
      if (!tables.containsAll(const {'users', 'sales'})) {
        throw const InvalidTapixBackupException();
      }
      return snapshot;
    } on BackupFromNewerVersionException {
      rethrow;
    } on InvalidTapixBackupException {
      rethrow;
    } catch (_) {
      throw const InvalidTapixBackupException();
    } finally {
      db?.close();
    }
  }

  Future<File?> _createPreRestoreSafetyCopy(
    ({File file, bool encrypted, String? key}) active,
  ) async {
    if (!await active.file.exists()) return null;
    final folder = await _folder();
    final backupFolder = Directory(p.join(folder.path, 'backups'));
    await backupFolder.create(recursive: true);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final output = File(p.join(backupFolder.path, 'pre_restore_$stamp.db'));
    if (active.encrypted) {
      await checkpointEncryptedDatabase(active.file, active.key!);
      await active.file.copy(output.path);
      snapshotEncryptedDatabase(output, active.key!);
    } else {
      await snapshotPlainDatabaseTo(active.file, output);
      snapshotPlainDatabase(output);
    }
    return output;
  }

  Future<void> _prunePreRestoreCopies(Directory folder) async {
    final backupFolder = Directory(p.join(folder.path, 'backups'));
    if (!await backupFolder.exists()) return;
    final files =
        backupFolder
            .listSync()
            .whereType<File>()
            .where((file) => p.basename(file.path).startsWith('pre_restore_'))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in files.skip(2)) {
      await secureDeleteDatabaseFile(old);
    }
  }

  bool _validPassphrase(String? value) =>
      value != null && value.length >= minimumPassphraseLength;

  static Future<bool> isPlainSqliteFile(File file) =>
      _hasPlainSqliteHeader(file);

  static Future<bool> _hasPlainSqliteHeader(File file) async {
    const header = <int>[
      0x53,
      0x51,
      0x4c,
      0x69,
      0x74,
      0x65,
      0x20,
      0x66,
      0x6f,
      0x72,
      0x6d,
      0x61,
      0x74,
      0x20,
      0x33,
      0x00,
    ];
    if (!await file.exists() || await file.length() < header.length) {
      return false;
    }
    final handle = await file.open();
    try {
      final bytes = await handle.read(header.length);
      for (var index = 0; index < header.length; index++) {
        if (bytes[index] != header[index]) return false;
      }
      return true;
    } finally {
      await handle.close();
    }
  }
}
