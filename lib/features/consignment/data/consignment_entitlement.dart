import '../../../core/services/business/local_branch_scope.dart';
import '../../../core/services/desktop_license_service.dart';
import '../../../core/services/revenuecat_service.dart';
import '../../../core/utils/platform_utils.dart';

/// Commercial boundary for consignment inventory, which is included in Pro.
abstract interface class ConsignmentEntitlement {
  Future<bool> permits(LocalBranchScope scope);
}

/// Production-safe default until the add-on is connected to the subscription
/// catalogue. The database foundation can ship while every business flow stays
/// closed.
class UnreleasedConsignmentEntitlement implements ConsignmentEntitlement {
  const UnreleasedConsignmentEntitlement();

  @override
  Future<bool> permits(LocalBranchScope scope) async => false;
}

/// Production adapter for the existing Tapix Pro entitlement.
///
/// Mobile reads the main RevenueCat Pro entitlement. A valid signed desktop
/// license is Pro on Windows/Linux. Web remains closed until its existing Pro
/// licensing path can be verified by a trusted server.
class PlatformConsignmentEntitlement implements ConsignmentEntitlement {
  const PlatformConsignmentEntitlement({
    required RevenueCatService revenueCat,
    required DesktopLicenseService desktopLicense,
  }) : _revenueCat = revenueCat,
       _desktopLicense = desktopLicense;

  final RevenueCatService _revenueCat;
  final DesktopLicenseService _desktopLicense;

  @override
  Future<bool> permits(LocalBranchScope scope) async {
    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      return _revenueCat.hasActiveEntitlement(RevenueCatConfig.entitlementId);
    }
    if (PlatformUtils.isWindows || PlatformUtils.isLinux) {
      final status = await _desktopLicense.initialize();
      return status == DesktopLicenseStatus.valid;
    }
    return false;
  }
}

class GrantedConsignmentEntitlement implements ConsignmentEntitlement {
  const GrantedConsignmentEntitlement();

  @override
  Future<bool> permits(LocalBranchScope scope) async => true;
}
