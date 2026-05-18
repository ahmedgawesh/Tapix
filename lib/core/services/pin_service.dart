import 'package:bcrypt/bcrypt.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service for managing the void/refund PIN.
/// The PIN is stored securely using FlutterSecureStorage with bcrypt hashing.
/// Only the owner can set/change the PIN via the security settings.
class PinService {
  static const String _pinHashKey = 'tapix_void_refund_pin_hash';

  final FlutterSecureStorage _storage;

  PinService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// Check if a PIN has been configured.
  Future<bool> isPinSet() async {
    final hash = await _storage.read(key: _pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  /// Set or update the PIN. The PIN is hashed with bcrypt before storage.
  Future<void> setPin(String pin) async {
    final hash = BCrypt.hashpw(pin, BCrypt.gensalt(logRounds: 10));
    await _storage.write(key: _pinHashKey, value: hash);
  }

  /// Verify a PIN against the stored hash.
  /// Returns true if the PIN matches, false otherwise.
  Future<bool> verifyPin(String pin) async {
    final hash = await _storage.read(key: _pinHashKey);
    if (hash == null || hash.isEmpty) return false;
    try {
      return BCrypt.checkpw(pin, hash);
    } catch (_) {
      return false;
    }
  }

  /// Remove the stored PIN.
  Future<void> clearPin() async {
    await _storage.delete(key: _pinHashKey);
  }
}
