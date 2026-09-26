import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Signs local security state with a random key generated for this app
/// installation. The key is kept in platform secure storage and is never
/// compiled into the application binary.
abstract interface class LocalIntegritySigner {
  bool get isReady;

  String sign(String scope, String payload);

  bool verify(String scope, String payload, String signature);
}

class LocalIntegrityKeyService implements LocalIntegritySigner {
  static const _storageKey = 'tapix.local_integrity_key.v1';
  static const _keyLengthBytes = 32;

  final FlutterSecureStorage _storage;
  Uint8List? _key;

  LocalIntegrityKeyService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @visibleForTesting
  LocalIntegrityKeyService.testing(List<int> keyBytes)
    : assert(keyBytes.isNotEmpty),
      _storage = const FlutterSecureStorage(),
      _key = Uint8List.fromList(keyBytes);

  @override
  bool get isReady => _key != null;

  /// Loads the installation key or creates it once using a cryptographically
  /// secure random generator.
  Future<void> initialize() async {
    if (_key != null) return;

    try {
      final stored = await _storage.read(key: _storageKey);
      if (stored != null && stored.isNotEmpty) {
        try {
          final decoded = base64Url.decode(stored);
          if (decoded.length == _keyLengthBytes) {
            _key = Uint8List.fromList(decoded);
            return;
          }
        } on FormatException {
          // Replace malformed key material below. Existing signed state will
          // fail verification and its owner decides the safe reconciliation.
        }
      }

      final generated = _generateKey();
      await _storage.write(
        key: _storageKey,
        value: base64Url.encode(generated),
      );
      _key = generated;
    } on Object catch (error) {
      // Platform secure storage can be temporarily unavailable (for example,
      // a locked desktop keyring). Keep the app available with an ephemeral
      // key. Previously signed state then fails closed instead of crashing
      // startup or silently using a hard-coded fallback secret.
      _key = _generateKey();
      debugPrint(
        'LocalIntegrityKeyService: secure storage unavailable; '
        'using an ephemeral fail-closed key: $error',
      );
    }
  }

  Uint8List _generateKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_keyLengthBytes, (_) => random.nextInt(256)),
    );
  }

  @override
  String sign(String scope, String payload) {
    final key = _requireKey();
    final message = utf8.encode('$scope\u0000$payload');
    return Hmac(sha256, key).convert(message).toString();
  }

  @override
  bool verify(String scope, String payload, String signature) {
    if (signature.length != 64) return false;
    final expected = sign(scope, payload);
    var difference = 0;
    for (var index = 0; index < expected.length; index++) {
      difference |= expected.codeUnitAt(index) ^ signature.codeUnitAt(index);
    }
    return difference == 0;
  }

  Uint8List _requireKey() {
    final key = _key;
    if (key == null) {
      throw StateError('LocalIntegrityKeyService must be initialized first.');
    }
    return key;
  }
}
