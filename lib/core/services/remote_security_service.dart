import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Remote security configuration fetched from server.
class SecurityConfig {
  final String minimumSupportedVersion;
  final List<String> blockedDeviceIds;
  final bool forceUpdate;
  final List<String> killedVersions;
  final DateTime fetchedAt;

  const SecurityConfig({
    required this.minimumSupportedVersion,
    required this.blockedDeviceIds,
    required this.forceUpdate,
    required this.killedVersions,
    required this.fetchedAt,
  });

  Map<String, dynamic> toJson() => {
    'minimumSupportedVersion': minimumSupportedVersion,
    'blockedDeviceIds': blockedDeviceIds,
    'forceUpdate': forceUpdate,
    'killedVersions': killedVersions,
    'fetchedAt': fetchedAt.toIso8601String(),
  };

  factory SecurityConfig.fromJson(Map<String, dynamic> json) {
    return SecurityConfig(
      minimumSupportedVersion:
          json['minimumSupportedVersion'] as String? ?? '1.0.0',
      blockedDeviceIds:
          (json['blockedDeviceIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      forceUpdate: json['forceUpdate'] as bool? ?? false,
      killedVersions:
          (json['killedVersions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      fetchedAt: json['fetchedAt'] != null
          ? DateTime.parse(json['fetchedAt'] as String)
          : DateTime.now(),
    );
  }

  /// Default config used when no remote or cached config is available.
  factory SecurityConfig.defaultConfig() {
    return SecurityConfig(
      minimumSupportedVersion: '1.0.0',
      blockedDeviceIds: [],
      forceUpdate: false,
      killedVersions: [],
      fetchedAt: DateTime.now(),
    );
  }

  /// Whether the cached config is still fresh (within 24 hours).
  bool get isFresh => DateTime.now().difference(fetchedAt).inHours < 24;
}

/// Result of a security check.
enum SecurityCheckResult {
  passed,
  deviceBlocked,
  versionUnsupported,
  versionKilled,
  forceUpdateRequired,
}

/// Service that fetches and validates remote security configuration.
class RemoteSecurityService {
  static const _cacheKey = 'tapix_security_config';

  /// TODO: Replace with your actual security config endpoint.
  static const _configUrl = 'https://api.tapix.app/security/config';

  final FlutterSecureStorage _secureStorage;
  final Dio _dio;

  SecurityConfig? _cachedConfig;

  RemoteSecurityService({FlutterSecureStorage? secureStorage, Dio? dio})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
      _dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 10)));

  /// Fetch config from remote, falling back to cache, then defaults.
  Future<SecurityConfig> fetchConfig() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(_configUrl);
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : response.data as Map<String, dynamic>;
        data['fetchedAt'] = DateTime.now().toIso8601String();
        final config = SecurityConfig.fromJson(data);
        await _cacheConfig(config);
        _cachedConfig = config;
        debugPrint('RemoteSecurity: Config fetched from server');
        return config;
      }
    } catch (e) {
      debugPrint('RemoteSecurity: Failed to fetch remote config: $e');
    }

    // Fall back to cached config
    return await loadCachedConfig();
  }

  /// Load cached config from secure storage.
  Future<SecurityConfig> loadCachedConfig() async {
    if (_cachedConfig != null) return _cachedConfig!;

    try {
      final encoded = await _secureStorage.read(key: _cacheKey);
      if (encoded != null && encoded.isNotEmpty) {
        final json = jsonDecode(encoded) as Map<String, dynamic>;
        final config = SecurityConfig.fromJson(json);
        _cachedConfig = config;
        debugPrint(
          'RemoteSecurity: Loaded cached config (fresh: ${config.isFresh})',
        );
        return config;
      }
    } catch (e) {
      debugPrint('RemoteSecurity: Failed to load cached config: $e');
    }

    return SecurityConfig.defaultConfig();
  }

  /// Run security checks against the given device fingerprint.
  Future<SecurityCheckResult> runChecks({
    required String deviceFingerprint,
  }) async {
    final config = _cachedConfig ?? await loadCachedConfig();
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    // Check if device is blocked
    if (config.blockedDeviceIds.contains(deviceFingerprint)) {
      debugPrint('RemoteSecurity: Device is blocked');
      return SecurityCheckResult.deviceBlocked;
    }

    // Check if current version is killed
    if (config.killedVersions.contains(currentVersion)) {
      debugPrint('RemoteSecurity: Version $currentVersion is killed');
      return SecurityCheckResult.versionKilled;
    }

    // Check force update flag
    if (config.forceUpdate) {
      final minVersion = config.minimumSupportedVersion;
      if (_isVersionLessThan(currentVersion, minVersion)) {
        debugPrint(
          'RemoteSecurity: Force update required ($currentVersion < $minVersion)',
        );
        return SecurityCheckResult.forceUpdateRequired;
      }
    }

    // Check minimum supported version
    if (_isVersionLessThan(currentVersion, config.minimumSupportedVersion)) {
      debugPrint(
        'RemoteSecurity: Version unsupported ($currentVersion < ${config.minimumSupportedVersion})',
      );
      return SecurityCheckResult.versionUnsupported;
    }

    return SecurityCheckResult.passed;
  }

  /// Compare semantic versions. Returns true if a < b.
  bool _isVersionLessThan(String a, String b) {
    final partsA = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final partsB = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va < vb) return true;
      if (va > vb) return false;
    }
    return false;
  }

  Future<void> _cacheConfig(SecurityConfig config) async {
    try {
      final encoded = jsonEncode(config.toJson());
      await _secureStorage.write(key: _cacheKey, value: encoded);
    } catch (e) {
      debugPrint('RemoteSecurity: Failed to cache config: $e');
    }
  }
}
