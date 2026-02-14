import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionService {
  final FlutterSecureStorage _storage;
  final Duration _sessionTimeout;
  static const String _userIdKey = 'current_user_id';
  static const String _sessionTokenKey = 'session_token';
  static const String _lastActivityKey = 'last_activity';

  /// In-memory cache of the current user ID.
  /// This avoids relying on async FlutterSecureStorage reads for every
  /// audit log call, which can return null on some Android devices.
  int? _cachedUserId;
  bool _cacheInitialized = false;

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
    _cachedUserId = userId;
    _cacheInitialized = true;
    developer.log('SessionService.saveSession: userId=$userId', name: 'SessionService');
    final token = _generateToken();
    await _storage.write(key: _userIdKey, value: userId.toString());
    await _storage.write(key: _sessionTokenKey, value: token);
    await _updateLastActivity();
    _sessionController.add(userId);
  }

  Future<int?> getCurrentUserId() async {
    // Fast path: return from in-memory cache
    if (_cacheInitialized) {
      return _cachedUserId;
    }

    // First call: hydrate cache from storage
    try {
      final userIdStr = await _storage.read(key: _userIdKey);
      _cachedUserId = userIdStr != null ? int.tryParse(userIdStr) : null;
    } catch (e) {
      developer.log('SessionService.getCurrentUserId: storage read failed: $e', name: 'SessionService');
      _cachedUserId = null;
    }
    _cacheInitialized = true;
    developer.log('SessionService.getCurrentUserId: resolved userId=$_cachedUserId', name: 'SessionService');
    return _cachedUserId;
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
    _cachedUserId = null;
    _cacheInitialized = true;
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
