import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../utils/platform_utils.dart';

/// Generates and manages a device-specific fingerprint.
///
/// The fingerprint is a SHA256 hash of:
/// - A persistent installation UUID (generated once, stored securely)
/// - Device model
/// - OS identifier
class DeviceFingerprintService {
  static const _installationIdKey = 'tapix_installation_uuid';

  final FlutterSecureStorage _secureStorage;
  final DeviceInfoPlugin _deviceInfo;

  String? _cachedFingerprint;
  String? _cachedInstallationId;

  DeviceFingerprintService({
    FlutterSecureStorage? secureStorage,
    DeviceInfoPlugin? deviceInfo,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  /// Get or create the persistent installation UUID.
  Future<String> getInstallationId() async {
    if (_cachedInstallationId != null) return _cachedInstallationId!;

    try {
      String? stored = await _secureStorage.read(key: _installationIdKey);
      if (stored == null || stored.isEmpty) {
        stored = const Uuid().v4();
        await _secureStorage.write(key: _installationIdKey, value: stored);
        debugPrint('DeviceFingerprint: New installation UUID created');
      }
      _cachedInstallationId = stored;
      return stored;
    } catch (e) {
      debugPrint('DeviceFingerprint: Error reading installation ID: $e');
      // Fallback: generate but don't persist (will change on next restart)
      final fallback = const Uuid().v4();
      _cachedInstallationId = fallback;
      return fallback;
    }
  }

  /// Get the device model string.
  Future<String> getDeviceModel() async {
    try {
      if (PlatformUtils.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return '${info.manufacturer}_${info.model}';
      } else if (PlatformUtils.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return info.utsname.machine;
      } else if (PlatformUtils.isLinux) {
        final info = await _deviceInfo.linuxInfo;
        return info.prettyName;
      } else if (PlatformUtils.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        return info.computerName;
      } else if (PlatformUtils.isMacOS) {
        final info = await _deviceInfo.macOsInfo;
        return info.model;
      }
      return 'unknown_device';
    } catch (e) {
      debugPrint('DeviceFingerprint: Error getting device model: $e');
      return 'unknown_device';
    }
  }

  /// Get the OS identifier string.
  Future<String> getOsIdentifier() async {
    try {
      if (PlatformUtils.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return 'android_${info.version.sdkInt}_${info.id}';
      } else if (PlatformUtils.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return 'ios_${info.systemVersion}_${info.identifierForVendor ?? "unknown"}';
      } else if (PlatformUtils.isLinux) {
        final info = await _deviceInfo.linuxInfo;
        return 'linux_${info.id}_${info.versionId ?? "unknown"}';
      } else if (PlatformUtils.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        return 'windows_${info.productId}';
      } else if (PlatformUtils.isMacOS) {
        final info = await _deviceInfo.macOsInfo;
        return 'macos_${info.osRelease}';
      }
      return 'unknown_os';
    } catch (e) {
      debugPrint('DeviceFingerprint: Error getting OS identifier: $e');
      return 'unknown_os';
    }
  }

  /// Compute the device fingerprint hash.
  /// This is a SHA256 hash of: installationId + deviceModel + osIdentifier.
  Future<String> getFingerprint() async {
    if (_cachedFingerprint != null) return _cachedFingerprint!;

    final installationId = await getInstallationId();
    final deviceModel = await getDeviceModel();
    final osId = await getOsIdentifier();

    final raw = '$installationId|$deviceModel|$osId';
    final hash = sha256.convert(utf8.encode(raw)).toString();

    _cachedFingerprint = hash;
    debugPrint('DeviceFingerprint: Generated fingerprint');
    return hash;
  }

  /// Verify that a given fingerprint matches the current device.
  Future<bool> verifyFingerprint(String fingerprint) async {
    final current = await getFingerprint();
    return current == fingerprint;
  }

  /// Clear cached values (useful for testing).
  void clearCache() {
    _cachedFingerprint = null;
    _cachedInstallationId = null;
  }
}
