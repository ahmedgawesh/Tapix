import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_fingerprint_service.dart';
import 'revenuecat_service.dart';

/// Local license data bound to a specific device.
class DeviceLicense {
  final String userId;
  final String deviceFingerprint;
  final String subscriptionType;
  final DateTime expiryDate;
  final DateTime lastOnlineValidation;
  final String integrityHash;

  const DeviceLicense({
    required this.userId,
    required this.deviceFingerprint,
    required this.subscriptionType,
    required this.expiryDate,
    required this.lastOnlineValidation,
    required this.integrityHash,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'deviceFingerprint': deviceFingerprint,
    'subscriptionType': subscriptionType,
    'expiryDate': expiryDate.toIso8601String(),
    'lastOnlineValidation': lastOnlineValidation.toIso8601String(),
    'integrityHash': integrityHash,
  };

  factory DeviceLicense.fromJson(Map<String, dynamic> json) {
    return DeviceLicense(
      userId: json['userId'] as String,
      deviceFingerprint: json['deviceFingerprint'] as String,
      subscriptionType: json['subscriptionType'] as String,
      expiryDate: DateTime.parse(json['expiryDate'] as String),
      lastOnlineValidation: DateTime.parse(
        json['lastOnlineValidation'] as String,
      ),
      integrityHash: json['integrityHash'] as String,
    );
  }

  SubscriptionType get type => SubscriptionType.values.firstWhere(
    (t) => t.name == subscriptionType,
    orElse: () => SubscriptionType.none,
  );

  bool get isExpired => DateTime.now().isAfter(expiryDate);

  bool get isOfflinePeriodExceeded {
    final maxDays = type.maxOfflineDays;
    if (maxDays == 0) return true;
    final deadline = lastOnlineValidation.add(Duration(days: maxDays));
    return DateTime.now().isAfter(deadline);
  }
}

/// Validation result from the license service.
enum LicenseValidationResult {
  valid,
  noLicense,
  expired,
  deviceMismatch,
  offlinePeriodExceeded,
  integrityFailed,
}

/// Manages encrypted local license storage and validation.
class LicenseService {
  static const _licenseKey = 'tapix_device_license';
  static const _licenseSignSecret = 'tapix_license_integrity_2024';

  final FlutterSecureStorage _secureStorage;
  final DeviceFingerprintService _fingerprintService;

  DeviceLicense? _cachedLicense;

  LicenseService({
    required DeviceFingerprintService fingerprintService,
    FlutterSecureStorage? secureStorage,
  }) : _fingerprintService = fingerprintService,
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Create and store a license after successful subscription validation.
  Future<DeviceLicense> createLicense({
    required String userId,
    required SubscriptionType subscriptionType,
    required DateTime? expiryDate,
  }) async {
    final fingerprint = await _fingerprintService.getFingerprint();
    final now = DateTime.now();

    // For lifetime, set expiry far in the future
    final effectiveExpiry = subscriptionType == SubscriptionType.lifetime
        ? now.add(const Duration(days: 36500)) // ~100 years
        : (expiryDate ?? now.add(const Duration(days: 30)));

    final license = DeviceLicense(
      userId: userId,
      deviceFingerprint: fingerprint,
      subscriptionType: subscriptionType.name,
      expiryDate: effectiveExpiry,
      lastOnlineValidation: now,
      integrityHash: '', // Will be computed below
    );

    // Compute integrity hash over all fields (excluding the hash itself)
    final hash = _computeIntegrityHash(license);
    final signedLicense = DeviceLicense(
      userId: license.userId,
      deviceFingerprint: license.deviceFingerprint,
      subscriptionType: license.subscriptionType,
      expiryDate: license.expiryDate,
      lastOnlineValidation: license.lastOnlineValidation,
      integrityHash: hash,
    );

    await _storeLicense(signedLicense);
    _cachedLicense = signedLicense;
    debugPrint(
      'LicenseService: License created for $userId (${subscriptionType.name})',
    );
    return signedLicense;
  }

  /// Update the last online validation timestamp and expiry from RevenueCat.
  Future<DeviceLicense?> refreshLicense({
    DateTime? newExpiryDate,
    SubscriptionType? newType,
  }) async {
    final license = await loadLicense();
    if (license == null) return null;

    final now = DateTime.now();
    final effectiveExpiry = newExpiryDate ?? license.expiryDate;
    final effectiveType = newType?.name ?? license.subscriptionType;

    final updated = DeviceLicense(
      userId: license.userId,
      deviceFingerprint: license.deviceFingerprint,
      subscriptionType: effectiveType,
      expiryDate: effectiveExpiry,
      lastOnlineValidation: now,
      integrityHash: '',
    );

    final hash = _computeIntegrityHash(updated);
    final signed = DeviceLicense(
      userId: updated.userId,
      deviceFingerprint: updated.deviceFingerprint,
      subscriptionType: updated.subscriptionType,
      expiryDate: updated.expiryDate,
      lastOnlineValidation: updated.lastOnlineValidation,
      integrityHash: hash,
    );

    await _storeLicense(signed);
    _cachedLicense = signed;
    debugPrint('LicenseService: License refreshed');
    return signed;
  }

  /// Load and decrypt the stored license.
  Future<DeviceLicense?> loadLicense() async {
    if (_cachedLicense != null) return _cachedLicense;

    try {
      final encoded = await _secureStorage.read(key: _licenseKey);
      if (encoded == null || encoded.isEmpty) return null;

      final json = jsonDecode(encoded) as Map<String, dynamic>;
      final license = DeviceLicense.fromJson(json);
      _cachedLicense = license;
      return license;
    } catch (e) {
      debugPrint('LicenseService: Failed to load license: $e');
      return null;
    }
  }

  /// Validate the local license fully:
  /// 1. License exists
  /// 2. Integrity hash matches
  /// 3. Device fingerprint matches
  /// 4. Not expired
  /// 5. Offline period not exceeded
  Future<LicenseValidationResult> validateLicense() async {
    final license = await loadLicense();

    if (license == null) {
      return LicenseValidationResult.noLicense;
    }

    // Verify integrity hash
    final expectedHash = _computeIntegrityHash(license);
    if (license.integrityHash != expectedHash) {
      debugPrint(
        'LicenseService: Integrity hash mismatch – possible tampering',
      );
      return LicenseValidationResult.integrityFailed;
    }

    // Verify device fingerprint
    final fingerprintValid = await _fingerprintService.verifyFingerprint(
      license.deviceFingerprint,
    );
    if (!fingerprintValid) {
      debugPrint('LicenseService: Device fingerprint mismatch');
      return LicenseValidationResult.deviceMismatch;
    }

    // Check expiry
    if (license.isExpired) {
      debugPrint('LicenseService: License expired');
      return LicenseValidationResult.expired;
    }

    // Check offline period
    if (license.isOfflinePeriodExceeded) {
      debugPrint('LicenseService: Offline period exceeded');
      return LicenseValidationResult.offlinePeriodExceeded;
    }

    return LicenseValidationResult.valid;
  }

  /// Remove the stored license (e.g. on logout or revocation).
  Future<void> revokeLicense() async {
    try {
      await _secureStorage.delete(key: _licenseKey);
      _cachedLicense = null;
      debugPrint('LicenseService: License revoked');
    } catch (e) {
      debugPrint('LicenseService: Failed to revoke license: $e');
    }
  }

  /// Store encrypted license data.
  Future<void> _storeLicense(DeviceLicense license) async {
    final encoded = jsonEncode(license.toJson());
    await _secureStorage.write(key: _licenseKey, value: encoded);
  }

  /// Compute HMAC-SHA256 over the license data fields (excluding the hash).
  String _computeIntegrityHash(DeviceLicense license) {
    final payload =
        '${license.userId}'
        '|${license.deviceFingerprint}'
        '|${license.subscriptionType}'
        '|${license.expiryDate.toIso8601String()}'
        '|${license.lastOnlineValidation.toIso8601String()}';

    final key = utf8.encode(_licenseSignSecret);
    final bytes = utf8.encode(payload);
    final hmacSha256 = Hmac(sha256, key);
    return hmacSha256.convert(bytes).toString();
  }
}
