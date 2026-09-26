import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_fingerprint_service.dart';
import 'local_integrity_key_service.dart';
import 'revenuecat_service.dart';

abstract interface class LicenseStorage {
  Future<String?> read();

  Future<void> write(String value);

  Future<void> delete();
}

class SecureLicenseStorage implements LicenseStorage {
  static const _key = 'tapix_device_license';
  final FlutterSecureStorage _storage;

  SecureLicenseStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Local license data bound to a specific device.
class DeviceLicense {
  final String userId;
  final String deviceFingerprint;
  final String subscriptionType;
  final DateTime expiryDate;
  final DateTime lastOnlineValidation;
  final String integrityHash;
  final int integrityVersion;

  const DeviceLicense({
    required this.userId,
    required this.deviceFingerprint,
    required this.subscriptionType,
    required this.expiryDate,
    required this.lastOnlineValidation,
    required this.integrityHash,
    this.integrityVersion = 2,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'deviceFingerprint': deviceFingerprint,
    'subscriptionType': subscriptionType,
    'expiryDate': expiryDate.toIso8601String(),
    'lastOnlineValidation': lastOnlineValidation.toIso8601String(),
    'integrityHash': integrityHash,
    'integrityVersion': integrityVersion,
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
      integrityVersion: (json['integrityVersion'] as num?)?.toInt() ?? 1,
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
  onlineValidationRequired,
}

/// Manages encrypted local license storage and validation.
class LicenseService {
  static const _integrityScope = 'tapix.mobile_license.v2';

  final LicenseStorage _storage;
  final DeviceFingerprintService _fingerprintService;
  final LocalIntegritySigner _integritySigner;

  DeviceLicense? _cachedLicense;

  LicenseService({
    required DeviceFingerprintService fingerprintService,
    required LocalIntegritySigner integritySigner,
    LicenseStorage? storage,
  }) : _fingerprintService = fingerprintService,
       _integritySigner = integritySigner,
       _storage = storage ?? SecureLicenseStorage();

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
      integrityVersion: 2,
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
      integrityVersion: 2,
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
      integrityVersion: 2,
    );

    final hash = _computeIntegrityHash(updated);
    final signed = DeviceLicense(
      userId: updated.userId,
      deviceFingerprint: updated.deviceFingerprint,
      subscriptionType: updated.subscriptionType,
      expiryDate: updated.expiryDate,
      lastOnlineValidation: updated.lastOnlineValidation,
      integrityHash: hash,
      integrityVersion: 2,
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
      final encoded = await _storage.read();
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

    // Version 1 used a secret embedded in the app binary. It cannot be a
    // trustworthy offline proof, so it is never accepted after this upgrade.
    // RevenueCat cache/online validation transparently issues version 2.
    if (license.integrityVersion < 2) {
      return LicenseValidationResult.onlineValidationRequired;
    }

    // Verify integrity hash.
    final payload = _integrityPayload(license);
    if (!_integritySigner.verify(
      _integrityScope,
      payload,
      license.integrityHash,
    )) {
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
      await _storage.delete();
      _cachedLicense = null;
      debugPrint('LicenseService: License revoked');
    } catch (e) {
      debugPrint('LicenseService: Failed to revoke license: $e');
    }
  }

  /// Store encrypted license data.
  Future<void> _storeLicense(DeviceLicense license) async {
    final encoded = jsonEncode(license.toJson());
    await _storage.write(encoded);
  }

  /// Compute HMAC-SHA256 with the installation key, never a compiled secret.
  String _computeIntegrityHash(DeviceLicense license) {
    return _integritySigner.sign(_integrityScope, _integrityPayload(license));
  }

  String _integrityPayload(DeviceLicense license) =>
      '${license.userId}'
      '|${license.deviceFingerprint}'
      '|${license.subscriptionType}'
      '|${license.expiryDate.toIso8601String()}'
      '|${license.lastOnlineValidation.toIso8601String()}'
      '|${license.integrityVersion}';
}
