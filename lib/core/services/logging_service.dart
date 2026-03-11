import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Centralized logging service for the application
/// Provides different log levels and ensures all errors are visible in console
class LoggingService {
  static const String _defaultTag = 'TAPIX';
  
  /// Log debug information
  static void debug(String message, {Map<String, dynamic>? params, String? tag}) {
    if (kDebugMode) {
      _log('DEBUG', message, params: params, tag: tag);
    }
  }
  
  /// Log informational messages
  static void info(String message, {Map<String, dynamic>? params, String? tag}) {
    _log('INFO', message, params: params, tag: tag);
  }
  
  /// Log warnings
  static void warning(String message, {Map<String, dynamic>? params, String? tag}) {
    _log('WARNING', message, params: params, tag: tag);
  }
  
  /// Log errors with stack trace
  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? params,
    String? tag,
  }) {
    _log('ERROR', message, params: params, tag: tag);
    
    if (error != null) {
      developer.log(
        'Error details: $error',
        name: tag ?? _defaultTag,
        error: error,
        stackTrace: stackTrace,
      );
    }
    
    if (stackTrace != null && kDebugMode) {
      debug('Stack trace:\n$stackTrace', tag: tag);
    }
  }
  
  /// Log exceptions with full details
  static void exception(
    String message,
    Object exception, {
    StackTrace? stackTrace,
    String? tag,
  }) {
    error(message, error: exception, stackTrace: stackTrace, tag: tag);
  }
  
  /// Internal logging method
  static void _log(
    String level,
    String message, {
    Map<String, dynamic>? params,
    String? tag,
  }) {
    final timestamp = DateTime.now().toIso8601String();
    final logTag = tag ?? _defaultTag;
    final paramsStr = _formatParams(params);
    final logMessage = '[$timestamp] $level: $logTag - $message${paramsStr.isNotEmpty ? ' | $paramsStr' : ''}';
    
    // Always print to console for visibility
    debugPrint(logMessage);
    
    // Also use developer.log for better filtering in IDE
    developer.log(message, name: '$logTag [$level]', time: DateTime.now());
  }

  static String _formatParams(Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return '';
    return params.entries.map((e) => '${e.key}=${e.value}').join(', ');
  }
  
  /// Log method entry for debugging
  static void methodEntry(String methodName, {Map<String, dynamic>? params, String? tag}) {
    if (kDebugMode) {
      final paramStr = _formatParams(params);
      debug('→ $methodName${paramStr.isNotEmpty ? '($paramStr)' : ''}', tag: tag);
    }
  }
  
  /// Log method exit for debugging
  static void methodExit(String methodName, {dynamic result, String? tag}) {
    if (kDebugMode) {
      debug('← $methodName${result != null ? ' -> $result' : ''}', tag: tag);
    }
  }
  
  /// Log bloc events for debugging
  static void blocEvent(String blocName, String eventName, {String? tag}) {
    debug('BLOC Event: $blocName -> $eventName', tag: tag ?? 'BLOC');
  }
  
  /// Log repository operations
  static void repositoryOperation(String repoName, String operation, {Map<String, dynamic>? params, String? tag}) {
    final paramStr = _formatParams(params);
    info('REPO: $repoName.$operation${paramStr.isNotEmpty ? '($paramStr)' : ''}', tag: tag ?? 'REPO');
  }
  
  /// Log service operations
  static void serviceOperation(String serviceName, String operation, {dynamic data, String? tag}) {
    info('SERVICE: $serviceName.$operation${data != null ? ' -> $data' : ''}', tag: tag ?? 'SERVICE');
  }

  // ---------------------------------------------------------------------------
  // Structured domain-specific logging
  // ---------------------------------------------------------------------------

  /// Log a database operation (migration, backup, integrity check)
  static void database(String operation, {Map<String, dynamic>? params, bool isError = false}) {
    if (isError) {
      error('DB: $operation', params: params, tag: 'DB');
    } else {
      info('DB: $operation', params: params, tag: 'DB');
    }
  }

  /// Log an accounting operation (journal create, void, balance change)
  static void accounting(
    String operation, {
    int? journalEntryId,
    int? sourceId,
    String? sourceTable,
    int? amountCents,
    String? tag,
  }) {
    final params = <String, dynamic>{};
    if (journalEntryId != null) params['journalEntryId'] = journalEntryId;
    if (sourceId != null) params['sourceId'] = sourceId;
    if (sourceTable != null) params['sourceTable'] = sourceTable;
    if (amountCents != null) params['amountCents'] = amountCents;
    info('ACCT: $operation', params: params, tag: tag ?? 'ACCOUNTING');
  }

  /// Log an authentication event (login, logout, session expiry, token refresh)
  static void auth(
    String event, {
    int? userId,
    String? username,
    bool success = true,
    String? reason,
  }) {
    final params = <String, dynamic>{};
    if (userId != null) params['userId'] = userId;
    if (username != null) params['username'] = username;
    params['success'] = success;
    if (reason != null) params['reason'] = reason;
    info('AUTH: $event', params: params, tag: 'AUTH');
  }

  /// Log a data integrity event (invariant check result)
  static void integrity(
    String check, {
    bool passed = true,
    String? details,
  }) {
    if (passed) {
      info('INTEGRITY: $check PASSED', tag: 'INTEGRITY');
    } else {
      error('INTEGRITY: $check FAILED${details != null ? ' — $details' : ''}', tag: 'INTEGRITY');
    }
  }
}
