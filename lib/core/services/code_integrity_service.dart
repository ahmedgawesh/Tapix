import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/platform_utils.dart';

/// Result of a code integrity check.
enum IntegrityCheckResult {
  passed,
  tampered,
  unavailable,
}

/// Service that verifies application code integrity by computing SHA256
/// hashes of important application bundles and comparing against known values.
///
/// On first run, the hash is stored as the "known good" baseline.
/// On subsequent runs, the hash is compared against the stored baseline.
/// If they differ, the app may have been tampered with.
class CodeIntegrityService {
  static const _hashKey = 'tapix_code_integrity_hash';

  final FlutterSecureStorage _secureStorage;

  CodeIntegrityService({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Verify code integrity.
  ///
  /// - On first run: stores the baseline hash and returns [IntegrityCheckResult.passed].
  /// - On subsequent runs: compares current hash against baseline.
  /// - In debug mode: always returns [IntegrityCheckResult.passed] (hash changes during development).
  Future<IntegrityCheckResult> verify() async {
    // Skip in debug mode – hashes change constantly during development
    if (kDebugMode) {
      return IntegrityCheckResult.passed;
    }

    try {
      final currentHash = await _computeAppHash();
      if (currentHash == null) {
        return IntegrityCheckResult.unavailable;
      }

      final storedHash = await _secureStorage.read(key: _hashKey);

      if (storedHash == null || storedHash.isEmpty) {
        // First run: store baseline
        await _secureStorage.write(key: _hashKey, value: currentHash);
        debugPrint('CodeIntegrity: Baseline hash stored');
        return IntegrityCheckResult.passed;
      }

      if (storedHash == currentHash) {
        return IntegrityCheckResult.passed;
      }

      debugPrint('CodeIntegrity: Hash mismatch – possible tampering');
      return IntegrityCheckResult.tampered;
    } catch (e) {
      debugPrint('CodeIntegrity: Verification error: $e');
      return IntegrityCheckResult.unavailable;
    }
  }

  /// Update the stored baseline hash (e.g. after a legitimate app update).
  Future<void> updateBaseline() async {
    try {
      final hash = await _computeAppHash();
      if (hash != null) {
        await _secureStorage.write(key: _hashKey, value: hash);
        debugPrint('CodeIntegrity: Baseline updated');
      }
    } catch (e) {
      debugPrint('CodeIntegrity: Failed to update baseline: $e');
    }
  }

  /// Compute a hash of the application binary or important assets.
  Future<String?> _computeAppHash() async {
    try {
      if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
        // Hash the main Dart kernel snapshot (compiled app code)
        return await _hashNativeBinary();
      }

      // On desktop/web, hash critical asset bundles
      return await _hashAssetBundle();
    } catch (e) {
      debugPrint('CodeIntegrity: Hash computation failed: $e');
      return null;
    }
  }

  /// Hash the native binary on Android/iOS.
  Future<String?> _hashNativeBinary() async {
    try {
      // Use the app executable path
      final execPath = Platform.resolvedExecutable;
      final file = File(execPath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        return sha256.convert(bytes).toString();
      }
    } catch (e) {
      debugPrint('CodeIntegrity: Native binary hash failed: $e');
    }

    // Fallback: hash a known asset
    return _hashAssetBundle();
  }

  /// Hash critical asset bundles as a fallback integrity check.
  Future<String?> _hashAssetBundle() async {
    try {
      // Load the AssetManifest as a proxy for code integrity
      final manifestJson =
          await rootBundle.loadString('AssetManifest.json', cache: false);
      final hash = sha256.convert(utf8.encode(manifestJson)).toString();
      return hash;
    } catch (e) {
      debugPrint('CodeIntegrity: Asset bundle hash failed: $e');
      return null;
    }
  }
}
