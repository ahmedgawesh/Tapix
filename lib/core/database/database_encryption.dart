import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages the encryption key for the SQLite database.
///
/// The key is stored in platform-secure storage:
/// - iOS: Keychain
/// - Android: EncryptedSharedPreferences (Tink)
/// - Desktop: OS keyring via flutter_secure_storage
///
/// On first use, a cryptographically random 32-byte hex key is generated
/// and persisted. Subsequent calls return the same key.
class DatabaseEncryptionKeyManager {
  static const _storageKey = 'tapix_db_encryption_key';
  static const _encryptionEnabledKey = 'tapix_db_encryption_enabled';

  final FlutterSecureStorage _secureStorage;

  DatabaseEncryptionKeyManager({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Check if database encryption is enabled.
  Future<bool> isEncryptionEnabled() async {
    final value = await _secureStorage.read(key: _encryptionEnabledKey);
    return value == 'true';
  }

  /// Enable database encryption. This sets the flag; the actual migration
  /// happens on next database open.
  Future<void> enableEncryption() async {
    await _secureStorage.write(key: _encryptionEnabledKey, value: 'true');
    // Ensure a key exists
    await getOrCreateKey();
  }

  /// Disable database encryption flag.
  Future<void> disableEncryption() async {
    await _secureStorage.write(key: _encryptionEnabledKey, value: 'false');
  }

  /// Get the existing encryption key, or generate and store a new one.
  Future<String> getOrCreateKey() async {
    final existing = await _secureStorage.read(key: _storageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final key = _generateSecureKey();
    await _secureStorage.write(key: _storageKey, value: key);
    return key;
  }

  /// Generate a cryptographically secure 32-byte hex key.
  String _generateSecureKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
