import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionService {
  final FlutterSecureStorage _storage;
  final Duration _sessionTimeout;
  static const String _userIdKey = 'current_user_id';
  static const String _sessionTokenKey = 'session_token';
  static const String _lastActivityKey = 'last_activity';

  final _sessionController = StreamController<int?>.broadcast();

  SessionService({
    FlutterSecureStorage? storage,
    Duration sessionTimeout = const Duration(hours: 24),
  })  : _storage = storage ?? const FlutterSecureStorage(
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        ),
        _sessionTimeout = sessionTimeout;

  Stream<int?> get sessionStream => _sessionController.stream;

  Future<void> saveSession(int userId) async {
    final token = _generateToken();
    await _storage.write(key: _userIdKey, value: userId.toString());
    await _storage.write(key: _sessionTokenKey, value: token);
    await _updateLastActivity();
    _sessionController.add(userId);
  }

  Future<int?> getCurrentUserId() async {
    final userIdStr = await _storage.read(key: _userIdKey);
    if (userIdStr == null) return null;
    return int.tryParse(userIdStr);
  }

  Future<bool> isSessionValid() async {
    final token = await _storage.read(key: _sessionTokenKey);
    if (token == null) return false;

    final lastActivityStr = await _storage.read(key: _lastActivityKey);
    if (lastActivityStr == null) return false;

    final lastActivity = DateTime.tryParse(lastActivityStr);
    if (lastActivity == null) return false;

    final now = DateTime.now();
    return now.difference(lastActivity) < _sessionTimeout;
  }

  Future<void> updateActivity() async {
    await _updateLastActivity();
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _userIdKey);
    await _storage.delete(key: _sessionTokenKey);
    await _storage.delete(key: _lastActivityKey);
    _sessionController.add(null);
  }

  Future<void> _updateLastActivity() async {
    await _storage.write(
      key: _lastActivityKey,
      value: DateTime.now().toIso8601String(),
    );
  }

  String _generateToken() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = timestamp.hashCode;
    return base64Encode(utf8.encode('$timestamp:$random'));
  }

  void dispose() {
    _sessionController.close();
  }
}
