import '../../../core/services/desktop_license_service.dart';
import '../../../core/services/revenuecat_service.dart';
import '../../../core/utils/platform_utils.dart';

enum OnlineBranchesEntitlementState {
  active,
  baseProRequired,
  addOnRequired,
  expired,
  unavailable,
}

class OnlineBranchesEntitlementSnapshot {
  const OnlineBranchesEntitlementSnapshot({
    required this.state,
    required this.baseProActive,
    required this.addOnActive,
    this.expirationDate,
    this.willRenew = false,
    this.productId,
    this.maxBranches,
    this.maxWarehouses,
  });

  final OnlineBranchesEntitlementState state;
  final bool baseProActive;
  final bool addOnActive;
  final DateTime? expirationDate;
  final bool willRenew;
  final String? productId;
  final int? maxBranches;
  final int? maxWarehouses;

  bool get permitsOnlineBranches =>
      state == OnlineBranchesEntitlementState.active;

  /// Local warehouses and LAN belong to Pro and remain independent from the
  /// online add-on lifecycle.
  bool get permitsLocalOperations => baseProActive;
}

class OnlineBranchesEntitlementPolicy {
  const OnlineBranchesEntitlementPolicy._();

  static OnlineBranchesEntitlementSnapshot evaluate({
    required bool baseProActive,
    required bool addOnActive,
    required DateTime now,
    DateTime? expirationDate,
    bool willRenew = false,
    String? productId,
    int? maxBranches,
    int? maxWarehouses,
    bool platformAvailable = true,
  }) {
    final normalizedExpiry = expirationDate?.toUtc();
    final expired =
        normalizedExpiry != null && !now.toUtc().isBefore(normalizedExpiry);
    final state = !platformAvailable
        ? OnlineBranchesEntitlementState.unavailable
        : !baseProActive
        ? OnlineBranchesEntitlementState.baseProRequired
        : expired
        ? OnlineBranchesEntitlementState.expired
        : !addOnActive
        ? OnlineBranchesEntitlementState.addOnRequired
        : OnlineBranchesEntitlementState.active;
    return OnlineBranchesEntitlementSnapshot(
      state: state,
      baseProActive: baseProActive,
      addOnActive: addOnActive && !expired,
      expirationDate: normalizedExpiry,
      willRenew: willRenew && !expired,
      productId: productId,
      maxBranches: _positive(maxBranches),
      maxWarehouses: _positive(maxWarehouses),
    );
  }

  static int? _positive(int? value) =>
      value != null && value > 0 ? value : null;
}

abstract interface class OnlineBranchesEntitlement {
  Future<OnlineBranchesEntitlementSnapshot> inspect();
}

/// Commercial boundary for the separately priced online-branches module.
/// Local warehouses and LAN never call this service.
class PlatformOnlineBranchesEntitlement implements OnlineBranchesEntitlement {
  const PlatformOnlineBranchesEntitlement({
    required RevenueCatService revenueCat,
    required DesktopLicenseService desktopLicense,
    DateTime Function()? now,
  }) : _revenueCat = revenueCat,
       _desktopLicense = desktopLicense,
       _now = now ?? DateTime.now;

  static const desktopFeatureId = 'online_branches';

  final RevenueCatService _revenueCat;
  final DesktopLicenseService _desktopLicense;
  final DateTime Function() _now;

  @override
  Future<OnlineBranchesEntitlementSnapshot> inspect() async {
    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      final entitlements = await _revenueCat.checkEntitlements([
        RevenueCatConfig.entitlementId,
        RevenueCatConfig.onlineBranchesEntitlementId,
      ]);
      final base =
          entitlements[RevenueCatConfig.entitlementId] ??
          const RevenueCatEntitlementStatus();
      final addOn =
          entitlements[RevenueCatConfig.onlineBranchesEntitlementId] ??
          const RevenueCatEntitlementStatus();
      return OnlineBranchesEntitlementPolicy.evaluate(
        baseProActive: base.isActive,
        addOnActive: addOn.isActive,
        expirationDate: addOn.expirationDate,
        willRenew: addOn.willRenew,
        productId: addOn.productId,
        now: _now(),
      );
    }
    if (PlatformUtils.isWindows || PlatformUtils.isLinux) {
      final status = await _desktopLicense.initialize();
      final baseActive = status == DesktopLicenseStatus.valid;
      return OnlineBranchesEntitlementPolicy.evaluate(
        baseProActive: baseActive,
        addOnActive:
            baseActive && _desktopLicense.hasSignedFeature(desktopFeatureId),
        expirationDate: _desktopLicense.signedLicenseExpiration,
        maxBranches: _desktopLicense.signedFeatureLimit(
          desktopFeatureId,
          'max_branches',
        ),
        maxWarehouses: _desktopLicense.signedFeatureLimit(
          desktopFeatureId,
          'max_warehouses',
        ),
        now: _now(),
      );
    }
    return OnlineBranchesEntitlementPolicy.evaluate(
      baseProActive: false,
      addOnActive: false,
      platformAvailable: false,
      now: _now(),
    );
  }
}
