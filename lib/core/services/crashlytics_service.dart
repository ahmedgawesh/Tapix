import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Service for Firebase Crashlytics integration.
/// Provides automatic crash reporting and manual error logging.
///
/// - Crashlytics is only supported on Android, iOS, and macOS.
/// - Logging/reporting is only active in **release** mode.
/// - On unsupported platforms or non-release builds, all methods are no-ops.
class CrashlyticsService {
  CrashlyticsService._();

  static final CrashlyticsService _instance = CrashlyticsService._();
  static CrashlyticsService get instance => _instance;

  FirebaseCrashlytics? _crashlytics;

  /// Whether Crashlytics is available (supported platform + release mode).
  bool get _isActive => _crashlytics != null;

  /// Whether Crashlytics is supported on the current platform.
  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  /// Initialize Crashlytics. Call this after Firebase.initializeApp().
  /// Only activates in release mode on supported platforms.
  Future<void> initialize() async {
    if (!isSupported) {
      debugPrint('CrashlyticsService: Not supported on this platform');
      return;
    }

    if (kDebugMode) {
      debugPrint('CrashlyticsService: Disabled in debug mode');
      return;
    }

    _crashlytics = FirebaseCrashlytics.instance;

    // Enable automatic crash collection in release mode
    await _crashlytics!.setCrashlyticsCollectionEnabled(true);

    // Attach platform info as custom keys
    await _crashlytics!.setCustomKey('platform', Platform.operatingSystem);
    await _crashlytics!.setCustomKey(
      'os_version',
      Platform.operatingSystemVersion,
    );
    await _crashlytics!.setCustomKey('dart_version', Platform.version);
    await _crashlytics!.setCustomKey('app_version', _appVersion);

    debugPrint('CrashlyticsService: Initialized successfully');
  }

  /// The app version string. Populated from pubspec via the build system.
  /// Falls back to 'unknown' if not available.
  static const String _appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );

  // ── User & Context ────────────────────────────────────────────────

  /// Set the authenticated user's identifier and role for crash reports.
  /// Called on login. Uses the numeric user ID (no PII).
  Future<void> setUser({required int userId, required String role}) async {
    if (!_isActive) return;
    await _crashlytics!.setUserIdentifier(userId.toString());
    await _crashlytics!.setCustomKey('user_id', userId);
    await _crashlytics!.setCustomKey('user_role', role);
  }

  /// Clear user context on logout.
  Future<void> clearUser() async {
    if (!_isActive) return;
    await _crashlytics!.setUserIdentifier('');
    await _crashlytics!.setCustomKey('user_id', '');
    await _crashlytics!.setCustomKey('user_role', '');
    await _crashlytics!.setCustomKey('shop_id', '');
  }

  /// Attach the shop / company identifier to crash reports.
  Future<void> setShopId(String shopId) async {
    if (!_isActive) return;
    await _crashlytics!.setCustomKey('shop_id', shopId);
  }

  // ── Action Logging ────────────────────────────────────────────────

  /// Log a named user action.
  /// These breadcrumb messages appear in the Crashlytics log trail.
  Future<void> logAction(
    String actionName, [
    Map<String, String>? extras,
  ]) async {
    if (!_isActive) return;
    final buffer = StringBuffer('action: $actionName');
    if (extras != null && extras.isNotEmpty) {
      extras.forEach((k, v) => buffer.write(' | $k=$v'));
    }
    await _crashlytics!.log(buffer.toString());
  }

  // ── Error Reporting ───────────────────────────────────────────────

  /// Record a non-fatal error with optional stack trace and reason.
  Future<void> recordError(
    dynamic exception, {
    StackTrace? stackTrace,
    String? reason,
    bool fatal = false,
    Iterable<Object> information = const [],
  }) async {
    if (!_isActive) {
      debugPrint('CrashlyticsService.recordError: $exception');
      return;
    }

    await _crashlytics!.recordError(
      exception,
      stackTrace,
      reason: reason,
      fatal: fatal,
      information: information,
    );
  }

  /// Log a message to Crashlytics.
  /// These messages appear in the crash report logs.
  Future<void> log(String message) async {
    if (!_isActive) {
      debugPrint('CrashlyticsService.log: $message');
      return;
    }

    await _crashlytics!.log(message);
  }

  /// Set a custom key-value pair for crash reports.
  Future<void> setCustomKey(String key, Object value) async {
    if (!_isActive) return;
    await _crashlytics!.setCustomKey(key, value);
  }

  /// Set the user identifier for crash reports.
  Future<void> setUserIdentifier(String identifier) async {
    if (!_isActive) return;
    await _crashlytics!.setUserIdentifier(identifier);
  }

  /// Record a Flutter error (from FlutterError.onError).
  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    if (!_isActive) {
      debugPrint('CrashlyticsService.recordFlutterError: ${details.exception}');
      return;
    }

    await _crashlytics!.recordFlutterError(details);
  }

  /// Record a fatal Flutter error.
  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {
    if (!_isActive) {
      debugPrint(
        'CrashlyticsService.recordFlutterFatalError: ${details.exception}',
      );
      return;
    }

    await _crashlytics!.recordFlutterFatalError(details);
  }

  /// Force a crash for testing purposes.
  /// Only use this in debug/test builds!
  void crash() {
    if (!_isActive) {
      debugPrint('CrashlyticsService.crash: Not supported');
      return;
    }

    _crashlytics!.crash();
  }

  /// Check if crash reports are being sent.
  Future<bool> checkForUnsentReports() async {
    if (!_isActive) return false;
    return await _crashlytics!.checkForUnsentReports();
  }

  /// Send any unsent crash reports.
  Future<void> sendUnsentReports() async {
    if (!_isActive) return;
    await _crashlytics!.sendUnsentReports();
  }

  /// Delete any unsent crash reports.
  Future<void> deleteUnsentReports() async {
    if (!_isActive) return;
    await _crashlytics!.deleteUnsentReports();
  }
}
