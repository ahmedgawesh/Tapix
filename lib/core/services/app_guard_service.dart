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
///
/// Three terminal states:
/// - **Unlocked Pro** — `isUnlocked = true`, `isFreeTier = false`. Full access.
/// - **Unlocked Free** — `isUnlocked = true`, `isFreeTier = true`. App boots,
///   but Pro features are gated by `FeatureGateService` at widget / router
///   level, and creation is capped by `FreeQuotaService`.
/// - **Locked** — `isUnlocked = false`. Only for SECURITY violations
///   (code tampered, device blocked, version killed, device mismatch,
///   license tampered, force update). NEVER for "no subscription".
class AppGuardStatus {
  final bool isUnlocked;

  /// `true` when the app is unlocked but the user does NOT have an active
  /// Pro entitlement. Free-tier rules apply.
  final bool isFreeTier;

  final AppLockReason lockReason;
  final bool requiresInternet;
  final SubscriptionStatus? subscriptionStatus;

  const AppGuardStatus({
    this.isUnlocked = false,
    this.isFreeTier = false,
    this.lockReason = AppLockReason.none,
    this.requiresInternet = false,
    this.subscriptionStatus,
  });

  /// Unlocked Pro user — full feature set.
  const AppGuardStatus.unlocked({this.subscriptionStatus})
      : isUnlocked = true,
        isFreeTier = false,
        lockReason = AppLockReason.none,
        requiresInternet = false;

  /// Unlocked free-tier user — app boots, Pro features are gated downstream.
  /// `lockReason` may carry a hint (e.g. `noSubscription`, `licenseExpired`,
  /// `offlineTooLong`) so the UI can show a contextual upsell banner.
  const AppGuardStatus.freeTier({
    this.subscriptionStatus,
    this.lockReason = AppLockReason.noSubscription,
    this.requiresInternet = false,
  })  : isUnlocked = true,
        isFreeTier = true;

  /// Hard lock — used only for SECURITY violations.
  const AppGuardStatus.locked({
    required this.lockReason,
    this.requiresInternet = false,
    this.subscriptionStatus,
  })  : isUnlocked = false,
        isFreeTier = false;
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
    // On unsupported platforms (web/desktop), purchases are impossible, so the
    // freemium gate must not apply. Treat the user as fully-entitled Pro so the
    // whole app — and any consumer reading `subscriptionStatus.isPro` — unlocks.
    if (!RevenueCatConfig.isSupported) {
      debugPrint('AppGuard: Unsupported platform – granting full access');
      const status = AppGuardStatus.unlocked(
        subscriptionStatus: SubscriptionStatus(isActive: true, isPro: true),
      );
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
      return const AppGuardStatus.unlocked(
        subscriptionStatus: SubscriptionStatus(isActive: true, isPro: true),
      );
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

      // Not subscribed → free tier (NOT a hard lock).
      // The app boots; Pro features are gated by FeatureGateService /
      // FreeQuotaService at the widget / router level.
      final status = AppGuardStatus.freeTier(
        subscriptionStatus: subStatus,
        lockReason: AppLockReason.noSubscription,
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
        // No license yet (never subscribed, or first run offline) → free tier.
        const status = AppGuardStatus.freeTier(
          lockReason: AppLockReason.noSubscription,
          requiresInternet: true,
        );
        _emit(status);
        return status;

      case LicenseValidationResult.expired:
        // Was Pro, license expired naturally → drop to free tier.
        // User can keep using free features; Pro UI surfaces an upsell.
        const status = AppGuardStatus.freeTier(
          lockReason: AppLockReason.licenseExpired,
          requiresInternet: true,
        );
        _emit(status);
        return status;

      case LicenseValidationResult.deviceMismatch:
        // SECURITY: license tied to a different device → hard lock.
        const status = AppGuardStatus.locked(
          lockReason: AppLockReason.deviceMismatch,
        );
        _emit(status);
        return status;

      case LicenseValidationResult.offlinePeriodExceeded:
        // Was Pro, just offline too long → drop to free tier and require
        // internet to re-verify Pro entitlement.
        const status = AppGuardStatus.freeTier(
          lockReason: AppLockReason.offlineTooLong,
          requiresInternet: true,
        );
        _emit(status);
        return status;

      case LicenseValidationResult.integrityFailed:
        // SECURITY: license blob tampered → hard lock.
        const status = AppGuardStatus.locked(
          lockReason: AppLockReason.licenseTampered,
        );
        _emit(status);
        return status;
    }
  }

  /// Start listening for connectivity changes and RevenueCat updates.
  void startListening() {
    // Auto-revalidate when connectivity returns.
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivityService.onConnectivityChanged.listen(
      (online) {
        if (!online) return;
        // If hard-locked OR currently free-tier waiting for internet,
        // try a full revalidation to upgrade to Pro if entitled.
        if (!_lastStatus.isUnlocked ||
            (_lastStatus.isFreeTier && _lastStatus.requiresInternet)) {
          revalidateOnline();
        } else {
          // Silently refresh license while already unlocked and stable.
          _silentRefresh();
        }
      },
    );

    // Listen to RevenueCat customer info updates.
    if (RevenueCatConfig.isSupported && _revenueCat.isInitialized) {
      _rcSubscription?.cancel();
      _rcSubscription = _revenueCat.subscriptionStatusStream.listen(
        (subStatus) {
          final wasProUnlocked =
              _lastStatus.isUnlocked && !_lastStatus.isFreeTier;
          if (subStatus.isPro && !wasProUnlocked) {
            // Free → Pro upgrade (or recovery from lock). Re-run full guard.
            revalidateOnline();
          } else if (!subStatus.isPro && wasProUnlocked) {
            // Subscription was revoked while app was open → demote to free.
            _emit(AppGuardStatus.freeTier(
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
