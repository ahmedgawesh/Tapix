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
  }) : isUnlocked = true,
       isFreeTier = true;

  /// Hard lock — used only for SECURITY violations.
  const AppGuardStatus.locked({
    required this.lockReason,
    this.requiresInternet = false,
    this.subscriptionStatus,
  }) : isUnlocked = false,
       isFreeTier = false;
}

/// Central orchestrator that enforces:
/// User Account → Subscription (RevenueCat) → Device-locked License → Offline Usage
///
/// Startup is deliberately local-first. The app validates code, cached
/// security policy and its signed device licence before it performs any
/// network work. Store and remote-policy refreshes run after the UI opens.
class AppGuardService {
  static const _freshStoreSnapshotWindow = Duration(minutes: 5);
  final RevenueCatService _revenueCat;
  final LicenseService _licenseService;
  final DeviceFingerprintService _fingerprintService;
  final ConnectivityService _connectivityService;
  final RemoteSecurityService _remoteSecurityService;
  final CodeIntegrityService _codeIntegrityService;
  final bool Function() _isRevenueCatSupported;

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
    bool Function()? revenueCatSupported,
  }) : _revenueCat = revenueCat,
       _licenseService = licenseService,
       _fingerprintService = fingerprintService,
       _connectivityService = connectivityService,
       _remoteSecurityService = remoteSecurityService,
       _codeIntegrityService = codeIntegrityService,
       _isRevenueCatSupported =
           revenueCatSupported ?? (() => RevenueCatConfig.isSupported);

  /// Run the full guard sequence. Call once at app startup.
  Future<AppGuardStatus> initialize() async {
    // On unsupported platforms (web/desktop), purchases are impossible, so the
    // freemium gate must not apply. Treat the user as fully-entitled Pro so the
    // whole app — and any consumer reading `subscriptionStatus.isPro` — unlocks.
    if (!_isRevenueCatSupported()) {
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
      const status = AppGuardStatus.locked(
        lockReason: AppLockReason.codeTampered,
      );
      _emit(status);
      return status;
    }

    // 2. Enforce the cached security policy. This reads local secure storage
    // only and therefore cannot make startup depend on internet availability.
    final fingerprint = await _fingerprintService.getFingerprint();
    final securityResult = await _remoteSecurityService.runChecks(
      deviceFingerprint: fingerprint,
    );

    switch (securityResult) {
      case SecurityCheckResult.deviceBlocked:
        const status = AppGuardStatus.locked(
          lockReason: AppLockReason.deviceBlocked,
        );
        _emit(status);
        return status;
      case SecurityCheckResult.versionKilled:
        const status = AppGuardStatus.locked(
          lockReason: AppLockReason.versionKilled,
        );
        _emit(status);
        return status;
      case SecurityCheckResult.versionUnsupported:
        const status = AppGuardStatus.locked(
          lockReason: AppLockReason.versionUnsupported,
        );
        _emit(status);
        return status;
      case SecurityCheckResult.forceUpdateRequired:
        const status = AppGuardStatus.locked(
          lockReason: AppLockReason.forceUpdate,
        );
        _emit(status);
        return status;
      case SecurityCheckResult.passed:
        break;
    }

    // 3. Decide access from the signed, device-bound local licence.
    return await _localLicenseValidation();
  }

  /// Called when the device comes back online.
  Future<AppGuardStatus> revalidateOnline() async {
    if (!_isRevenueCatSupported()) {
      return const AppGuardStatus.unlocked(
        subscriptionStatus: SubscriptionStatus(isActive: true, isPro: true),
      );
    }

    debugPrint('AppGuard: Revalidating online');
    final hasNetworkInterface = await _connectivityService.checkNow();
    if (!hasNetworkInterface) return await _localLicenseValidation();

    // Refresh remote policy only outside the startup critical path, then
    // enforce it before accepting any store result.
    await _remoteSecurityService.fetchConfig();
    final fingerprint = await _fingerprintService.getFingerprint();
    final securityResult = await _remoteSecurityService.runChecks(
      deviceFingerprint: fingerprint,
    );
    final securityStatus = _statusForSecurityResult(securityResult);
    if (securityStatus != null) {
      _emit(securityStatus);
      return securityStatus;
    }
    return _onlineValidation();
  }

  AppGuardStatus? _statusForSecurityResult(SecurityCheckResult result) {
    return switch (result) {
      SecurityCheckResult.deviceBlocked => const AppGuardStatus.locked(
        lockReason: AppLockReason.deviceBlocked,
      ),
      SecurityCheckResult.versionKilled => const AppGuardStatus.locked(
        lockReason: AppLockReason.versionKilled,
      ),
      SecurityCheckResult.versionUnsupported => const AppGuardStatus.locked(
        lockReason: AppLockReason.versionUnsupported,
      ),
      SecurityCheckResult.forceUpdateRequired => const AppGuardStatus.locked(
        lockReason: AppLockReason.forceUpdate,
      ),
      SecurityCheckResult.passed => null,
    };
  }

  bool _isFreshStoreSnapshot(SubscriptionStatus status) {
    final checkedAt = status.checkedAt?.toUtc();
    if (checkedAt == null) return false;
    final age = DateTime.now().toUtc().difference(checkedAt);
    return !age.isNegative && age <= _freshStoreSnapshotWindow;
  }

  /// Full online validation: check RevenueCat, update license.
  Future<AppGuardStatus> _onlineValidation() async {
    try {
      final subStatus = await _revenueCat.checkSubscription(throwOnError: true);

      if (subStatus.verificationFailed) {
        const status = AppGuardStatus.locked(
          lockReason: AppLockReason.licenseTampered,
        );
        _emit(status);
        return status;
      }

      if (subStatus.isPro) {
        // An old cached active snapshot must not extend the offline allowance
        // forever. Fall back to the bounded signed licence until RevenueCat
        // supplies a recent snapshot.
        if (!_isFreshStoreSnapshot(subStatus)) {
          return await _localLicenseValidation();
        }
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

      // A stale cached inactive snapshot is not proof of cancellation. Keep
      // the current locally signed entitlement until a recent store result is
      // available.
      if (!_isFreshStoreSnapshot(subStatus)) {
        return await _localLicenseValidation();
      }

      // Not subscribed → free tier (NOT a hard lock).
      // The app boots; Pro features are gated by FeatureGateService /
      // FreeQuotaService at the widget / router level.
      // This is an authoritative online result, so invalidate the bounded
      // offline ticket as well. Otherwise a cancelled/refunded subscription
      // could regain Pro access on the next offline launch.
      await _licenseService.revokeLicense();
      final status = AppGuardStatus.freeTier(
        subscriptionStatus: subStatus,
        lockReason: AppLockReason.noSubscription,
      );
      _emit(status);
      return status;
    } catch (e) {
      debugPrint(
        'AppGuard: Online validation failed, falling back to offline: $e',
      );
      return await _localLicenseValidation();
    }
  }

  /// Local validation performs no connectivity or store SDK calls.
  Future<AppGuardStatus> _localLicenseValidation() async {
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

      case LicenseValidationResult.onlineValidationRequired:
        const status = AppGuardStatus.freeTier(
          lockReason: AppLockReason.offlineTooLong,
          requiresInternet: true,
        );
        _emit(status);
        return status;
    }
  }

  /// Start listening for connectivity changes and RevenueCat updates.
  void startListening() {
    // Auto-revalidate when connectivity returns.
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivityService.onConnectivityChanged
        .listen((online) {
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
        });

    // Listen to RevenueCat customer info updates.
    if (_isRevenueCatSupported() && _revenueCat.isInitialized) {
      _rcSubscription?.cancel();
      _rcSubscription = _revenueCat.subscriptionStatusStream.listen((
        subStatus,
      ) {
        if (subStatus.verificationFailed) {
          _emit(
            const AppGuardStatus.locked(
              lockReason: AppLockReason.licenseTampered,
            ),
          );
          return;
        }
        final wasProUnlocked =
            _lastStatus.isUnlocked && !_lastStatus.isFreeTier;
        if (subStatus.isPro &&
            _isFreshStoreSnapshot(subStatus) &&
            !wasProUnlocked) {
          // Free → Pro upgrade (or recovery from lock). Re-run full guard.
          revalidateOnline();
        } else if (!subStatus.isPro &&
            _isFreshStoreSnapshot(subStatus) &&
            wasProUnlocked) {
          // Subscription was revoked while app was open → demote to free.
          // The listener carries an authoritative RevenueCat customer-info
          // update, so the cached offline ticket must be revoked too.
          unawaited(_licenseService.revokeLicense());
          _emit(
            AppGuardStatus.freeTier(
              lockReason: AppLockReason.noSubscription,
              subscriptionStatus: subStatus,
            ),
          );
        }
      });
    }
  }

  /// Silently refresh the license expiry when already unlocked and online.
  Future<void> _silentRefresh() async {
    try {
      final subStatus = await _revenueCat.checkSubscription(throwOnError: true);
      if (subStatus.verificationFailed) {
        _emit(
          const AppGuardStatus.locked(
            lockReason: AppLockReason.licenseTampered,
          ),
        );
        return;
      }
      if (subStatus.isPro && _isFreshStoreSnapshot(subStatus)) {
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
