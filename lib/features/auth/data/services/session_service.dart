import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Callback type for getting session timeout settings dynamically
typedef SessionTimeoutSettingsCallback = ({bool enabled, int timeoutMinutes, int rememberMeDurationHours}) Function();

class SessionService {
  final FlutterSecureStorage _storage;
  static const String _userIdKey = 'current_user_id';
  static const String _sessionTokenKey = 'session_token';
  static const String _lastActivityKey = 'last_activity';
  static const String _rememberMeKey = 'remember_me';
  static const String _rememberMeExpiryKey = 'remember_me_expiry';

  /// Callback to get current session timeout settings from AppSettings
  SessionTimeoutSettingsCallback? _getTimeoutSettings;

  /// In-memory cache of the current user ID.
  /// This avoids relying on async FlutterSecureStorage reads for every
  /// audit log call, which can return null on some Android devices.
  int? _cachedUserId;
  bool _cacheInitialized = false;

  final _sessionController = StreamController<int?>.broadcast();

  SessionService({
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage(
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        );

  /// Configure the callback to get session timeout settings dynamically
  void configureTimeoutSettings(SessionTimeoutSettingsCallback callback) {
    _getTimeoutSettings = callback;
  }

  Stream<int?> get sessionStream => _sessionController.stream;

  Future<void> saveSession(int userId, {bool rememberMe = false}) async {
    _cachedUserId = userId;
    _cacheInitialized = true;
    developer.log('SessionService.saveSession: userId=$userId, rememberMe=$rememberMe', name: 'SessionService');
    final token = _generateToken();
    await _storage.write(key: _userIdKey, value: userId.toString());
    await _storage.write(key: _sessionTokenKey, value: token);
    await _storage.write(key: _rememberMeKey, value: rememberMe.toString());
    if (rememberMe) {
      final settings = _getTimeoutSettings?.call();
      final durationHours = settings?.rememberMeDurationHours ?? 72;
      final expiry = DateTime.now().add(Duration(hours: durationHours));
      await _storage.write(key: _rememberMeExpiryKey, value: expiry.toIso8601String());
    } else {
      await _storage.delete(key: _rememberMeExpiryKey);
    }
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

    // Check if "Remember Me" is active
    final rememberMeStr = await _storage.read(key: _rememberMeKey);
    final isRememberMe = rememberMeStr == 'true';

    if (isRememberMe) {
      // Remember Me bypasses session timeout; check its own expiry instead
      final expiryStr = await _storage.read(key: _rememberMeExpiryKey);
      if (expiryStr == null) return false;
      final expiry = DateTime.tryParse(expiryStr);
      if (expiry == null) return false;
      return DateTime.now().isBefore(expiry);
    }

    // Normal session timeout logic
    // Get timeout settings from AppSettings via callback
    final settings = _getTimeoutSettings?.call();
    
    // If session timeout is disabled, session is always valid (if token exists)
    if (settings != null && !settings.enabled) {
      return true;
    }

    final lastActivityStr = await _storage.read(key: _lastActivityKey);
    if (lastActivityStr == null) return false;

    final lastActivity = DateTime.tryParse(lastActivityStr);
    if (lastActivity == null) return false;

    final now = DateTime.now();
    // Use timeout from settings, default to 30 minutes if not configured
    final timeoutMinutes = settings?.timeoutMinutes ?? 30;
    return now.difference(lastActivity) < Duration(minutes: timeoutMinutes);
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
    await _storage.delete(key: _rememberMeKey);
    await _storage.delete(key: _rememberMeExpiryKey);
    _sessionController.add(null);
  }

  Future<void> _updateLastActivity() async {
    await _storage.write(
      key: _lastActivityKey,
      value: DateTime.now().toIso8601String(),
    );
  }

  String _generateToken() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64Url.encode(bytes);
  }

  void dispose() {
    _sessionController.close();
  }
}
