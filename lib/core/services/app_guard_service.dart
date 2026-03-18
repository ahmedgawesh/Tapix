import 'dart:async';

import 'package:flutter/foundation.dart';

import 'code_integrity_service.dart';
import 'connectivity_service.dart';
import 'device_fingerprint_service.dart';
import 'license_service.dart';
import 'remote_security_service.dart';
import 'revenuecat_service.dart';

/// Why the app is locked.
enum AppLockReason {
  none,
  noSubscription,
  licenseExpired,
  deviceMismatch,
  offlineTooLong,
  licenseTampered,
  deviceBlocked,
  versionUnsupported,
  versionKilled,
  forceUpdate,
  codeTampered,
}

/// Overall guard status emitted by [AppGuardService].
class AppGuardStatus {
  final bool isUnlocked;
  final AppLockReason lockReason;
  final bool requiresInternet;
  final SubscriptionStatus? subscriptionStatus;

  const AppGuardStatus({
    this.isUnlocked = false,
    this.lockReason = AppLockReason.none,
    this.requiresInternet = false,
    this.subscriptionStatus,
  });

  const AppGuardStatus.unlocked({this.subscriptionStatus})
      : isUnlocked = true,
        lockReason = AppLockReason.none,
        requiresInternet = false;

  const AppGuardStatus.locked({
    required this.lockReason,
    this.requiresInternet = false,
    this.subscriptionStatus,
  }) : isUnlocked = false;
}

/// Central orchestrator that enforces:
/// User Account → Subscription (RevenueCat) → Device-locked License → Offline Usage
///
/// Flow on every app start:
/// 1. Code integrity check
/// 2. Remote security config check (if online)
/// 3. If online: validate subscription via RevenueCat, update local license
/// 4. If offline: validate local license (fingerprint, expiry, offline period)
/// 5. Emit [AppGuardStatus] accordingly
class AppGuardService {
  final RevenueCatService _revenueCat;
  final LicenseService _licenseService;
  final DeviceFingerprintService _fingerprintService;
  final ConnectivityService _connectivityService;
  final RemoteSecurityService _remoteSecurityService;
  final CodeIntegrityService _codeIntegrityService;

  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<SubscriptionStatus>? _rcSubscription;

  final _statusController = StreamController<AppGuardStatus>.broadcast();

  /// Stream of guard status changes.
  Stream<AppGuardStatus> get statusStream => _statusController.stream;

  AppGuardStatus _lastStatus = const AppGuardStatus();
  AppGuardStatus get currentStatus => _lastStatus;

  AppGuardService({
    required RevenueCatService revenueCat,
    required LicenseService licenseService,
    required DeviceFingerprintService fingerprintService,
    required ConnectivityService connectivityService,
    required RemoteSecurityService remoteSecurityService,
    required CodeIntegrityService codeIntegrityService,
  })  : _revenueCat = revenueCat,
        _licenseService = licenseService,
        _fingerprintService = fingerprintService,
        _connectivityService = connectivityService,
        _remoteSecurityService = remoteSecurityService,
        _codeIntegrityService = codeIntegrityService;

  /// Run the full guard sequence. Call once at app startup.
  Future<AppGuardStatus> initialize() async {
    // On unsupported platforms (web/desktop), skip all guards
    if (!RevenueCatConfig.isSupported) {
      debugPrint('AppGuard: Unsupported platform – skipping guards');
      const status = AppGuardStatus.unlocked();
      _emit(status);
      return status;
    }

    // 1. Code integrity check
    final integrityResult = await _codeIntegrityService.verify();
    if (integrityResult == IntegrityCheckResult.tampered) {
      const status = AppGuardStatus.locked(lockReason: AppLockReason.codeTampered);
      _emit(status);
      return status;
    }

    // 2. Check connectivity
    final isOnline = await _connectivityService.checkNow();

    // 3. Remote security config (fetch if online, else use cache)
    if (isOnline) {
      await _remoteSecurityService.fetchConfig();
    }

    final fingerprint = await _fingerprintService.getFingerprint();
    final securityResult = await _remoteSecurityService.runChecks(
      deviceFingerprint: fingerprint,
    );

    switch (securityResult) {
      case SecurityCheckResult.deviceBlocked:
        const status = AppGuardStatus.locked(lockReason: AppLockReason.deviceBlocked);
        _emit(status);
        return status;
      case SecurityCheckResult.versionKilled:
        const status = AppGuardStatus.locked(lockReason: AppLockReason.versionKilled);
        _emit(status);
        return status;
      case SecurityCheckResult.versionUnsupported:
        const status = AppGuardStatus.locked(lockReason: AppLockReason.versionUnsupported);
        _emit(status);
        return status;
      case SecurityCheckResult.forceUpdateRequired:
        const status = AppGuardStatus.locked(lockReason: AppLockReason.forceUpdate);
        _emit(status);
        return status;
      case SecurityCheckResult.passed:
        break;
    }

    // 4. Online path: validate with RevenueCat and update license
    if (isOnline) {
      return _onlineValidation();
    }

    // 5. Offline path: validate local license
    return _offlineValidation();
  }

  /// Called when the device comes back online.
  Future<AppGuardStatus> revalidateOnline() async {
    if (!RevenueCatConfig.isSupported) {
      return const AppGuardStatus.unlocked();
    }

    debugPrint('AppGuard: Revalidating online');
    return _onlineValidation();
  }

  /// Full online validation: check RevenueCat, update license.
  Future<AppGuardStatus> _onlineValidation() async {
    try {
      final subStatus = await _revenueCat.checkSubscription();

      if (subStatus.isPro) {
        // Active subscription → create/refresh license
        await _licenseService.createLicense(
          userId: subStatus.userId ?? 'anonymous',
          subscriptionType: subStatus.subscriptionType,
          expiryDate: subStatus.expirationDate,
        );

        final status = AppGuardStatus.unlocked(subscriptionStatus: subStatus);
        _emit(status);
        return status;
      }

      // Not subscribed
      final status = AppGuardStatus.locked(
        lockReason: AppLockReason.noSubscription,
        subscriptionStatus: subStatus,
      );
      _emit(status);
      return status;
    } catch (e) {
      debugPrint('AppGuard: Online validation failed, falling back to offline: $e');
      return _offlineValidation();
    }
  }

  /// Offline validation: check local license.
  Future<AppGuardStatus> _offlineValidation() async {
    final result = await _licenseService.validateLicense();

    switch (result) {
      case LicenseValidationResult.valid:
        final license = await _licenseService.loadLicense();
        final subStatus = SubscriptionStatus(
          isActive: true,
          isPro: true,
          subscriptionType: license?.type ?? SubscriptionType.none,
          activeProductId: license?.subscriptionType,
          expirationDate: license?.expiryDate,
          userId: license?.userId,
        );
        final status = AppGuardStatus.unlocked(subscriptionStatus: subStatus);
        _emit(status);
        return status;

      case LicenseValidationResult.noLicense:
        const status = AppGuardStatus.locked(
          lockReason: AppLockReason.noSubscription,
          requiresInternet: true,
        );
        _emit(status);
        return status;

      case LicenseValidationResult.expired:
        const status = AppGuardStatus.locked(
          lockReason: AppLockReason.licenseExpired,
          requiresInternet: true,
        );
        _emit(status);
        return status;

      case LicenseValidationResult.deviceMismatch:
        const status = AppGuardStatus.locked(
          lockReason: AppLockReason.deviceMismatch,
        );
        _emit(status);
        return status;

      case LicenseValidationResult.offlinePeriodExceeded:
        const status = AppGuardStatus.locked(
          lockReason: AppLockReason.offlineTooLong,
          requiresInternet: true,
        );
        _emit(status);
        return status;

      case LicenseValidationResult.integrityFailed:
        const status = AppGuardStatus.locked(
          lockReason: AppLockReason.licenseTampered,
        );
        _emit(status);
        return status;
    }
  }

  /// Start listening for connectivity changes and RevenueCat updates.
  void startListening() {
    // Auto-revalidate when connectivity returns
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivityService.onConnectivityChanged.listen(
      (online) {
        if (online && !_lastStatus.isUnlocked) {
          revalidateOnline();
        } else if (online && _lastStatus.isUnlocked) {
          // Silently refresh license while app is unlocked
          _silentRefresh();
        }
      },
    );

    // Listen to RevenueCat customer info updates
    if (RevenueCatConfig.isSupported && _revenueCat.isInitialized) {
      _rcSubscription?.cancel();
      _rcSubscription = _revenueCat.subscriptionStatusStream.listen(
        (subStatus) {
          if (subStatus.isPro && !_lastStatus.isUnlocked) {
            revalidateOnline();
          } else if (!subStatus.isPro && _lastStatus.isUnlocked) {
            // Subscription was revoked while app was open
            _emit(AppGuardStatus.locked(
              lockReason: AppLockReason.noSubscription,
              subscriptionStatus: subStatus,
            ));
          }
        },
      );
    }
  }

  /// Silently refresh the license expiry when already unlocked and online.
  Future<void> _silentRefresh() async {
    try {
      final subStatus = await _revenueCat.checkSubscription();
      if (subStatus.isPro) {
        await _licenseService.refreshLicense(
          newExpiryDate: subStatus.expirationDate,
          newType: subStatus.subscriptionType,
        );
        debugPrint('AppGuard: License silently refreshed');
      }
    } catch (e) {
      debugPrint('AppGuard: Silent refresh failed: $e');
    }
  }

  void _emit(AppGuardStatus status) {
    _lastStatus = status;
    _statusController.add(status);
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _rcSubscription?.cancel();
    _statusController.close();
  }
}
