import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/desktop_license_service.dart';
import '../../../core/services/revenuecat_service.dart';
import '../../../core/utils/platform_utils.dart';
import 'online_branches_entitlement.dart';

class OnlineBranchesPlan {
  const OnlineBranchesPlan({
    required this.id,
    required this.productId,
    required this.title,
    required this.description,
    required this.price,
  });

  final String id;
  final String productId;
  final String title;
  final String description;
  final String price;
}

enum OnlineBranchesStoreResult { success, cancelled, failed, unavailable }

class OnlineBranchesPurchaseOutcome {
  const OnlineBranchesPurchaseOutcome(this.result, {this.errorCode});

  final OnlineBranchesStoreResult result;
  final String? errorCode;
  bool get activated => result == OnlineBranchesStoreResult.success;
}

abstract interface class OnlineBranchesPurchaseGateway {
  Future<List<OnlineBranchesPlan>> loadPlans();
  Future<OnlineBranchesStoreResult> purchase(String planId);
  Future<OnlineBranchesStoreResult> restore();
  Future<bool> openManagement();
}

abstract interface class OnlineBranchesPurchaseService {
  Future<List<OnlineBranchesPlan>> loadPlans();
  Future<OnlineBranchesPurchaseOutcome> purchase(String planId);
  Future<OnlineBranchesPurchaseOutcome> restore();
  Future<bool> openManagement();
}

class DefaultOnlineBranchesPurchaseService
    implements OnlineBranchesPurchaseService {
  const DefaultOnlineBranchesPurchaseService({
    required OnlineBranchesPurchaseGateway gateway,
    required OnlineBranchesEntitlement entitlement,
  }) : _gateway = gateway,
       _entitlement = entitlement;

  final OnlineBranchesPurchaseGateway _gateway;
  final OnlineBranchesEntitlement _entitlement;

  @override
  Future<List<OnlineBranchesPlan>> loadPlans() => _gateway.loadPlans();

  @override
  Future<OnlineBranchesPurchaseOutcome> purchase(String planId) async {
    if (planId.trim().isEmpty) {
      return const OnlineBranchesPurchaseOutcome(
        OnlineBranchesStoreResult.failed,
        errorCode: 'invalid_plan',
      );
    }
    return _complete(await _gateway.purchase(planId));
  }

  @override
  Future<OnlineBranchesPurchaseOutcome> restore() async =>
      _complete(await _gateway.restore());

  Future<OnlineBranchesPurchaseOutcome> _complete(
    OnlineBranchesStoreResult storeResult,
  ) async {
    if (storeResult != OnlineBranchesStoreResult.success) {
      return OnlineBranchesPurchaseOutcome(storeResult);
    }
    final status = await _entitlement.inspect();
    if (!status.permitsOnlineBranches) {
      return const OnlineBranchesPurchaseOutcome(
        OnlineBranchesStoreResult.failed,
        errorCode: 'entitlement_not_granted',
      );
    }
    return const OnlineBranchesPurchaseOutcome(
      OnlineBranchesStoreResult.success,
    );
  }

  @override
  Future<bool> openManagement() => _gateway.openManagement();
}

/// Store adapter for the online-branches add-on only. The offering must be
/// configured with this exact identifier in RevenueCat; base Pro offerings are
/// never used as a fallback.
class PlatformOnlineBranchesPurchaseGateway
    implements OnlineBranchesPurchaseGateway {
  PlatformOnlineBranchesPurchaseGateway({required RevenueCatService revenueCat})
    : _revenueCat = revenueCat;

  final RevenueCatService _revenueCat;
  final Map<String, Package> _packages = {};

  @override
  Future<List<OnlineBranchesPlan>> loadPlans() async {
    if (!RevenueCatConfig.isSupported || !_revenueCat.isInitialized) {
      _packages.clear();
      return const [];
    }
    final offerings = await _revenueCat.getOfferings();
    final offering = offerings?.all[RevenueCatConfig.onlineBranchesOfferingId];
    if (offering == null) {
      _packages.clear();
      return const [];
    }
    _packages
      ..clear()
      ..addEntries(
        offering.availablePackages.map((package) {
          return MapEntry(package.identifier, package);
        }),
      );
    return offering.availablePackages
        .map(
          (package) => OnlineBranchesPlan(
            id: package.identifier,
            productId: package.storeProduct.identifier,
            title: package.storeProduct.title,
            description: package.storeProduct.description,
            price: package.storeProduct.priceString,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<OnlineBranchesStoreResult> purchase(String planId) async {
    final package = _packages[planId];
    if (package == null) return OnlineBranchesStoreResult.unavailable;
    final result = await _revenueCat.purchasePackage(package);
    if (result.userCancelled) return OnlineBranchesStoreResult.cancelled;
    return result.success
        ? OnlineBranchesStoreResult.success
        : OnlineBranchesStoreResult.failed;
  }

  @override
  Future<OnlineBranchesStoreResult> restore() async {
    if (!RevenueCatConfig.isSupported || !_revenueCat.isInitialized) {
      return OnlineBranchesStoreResult.unavailable;
    }
    final result = await _revenueCat.restorePurchases();
    return result.success
        ? OnlineBranchesStoreResult.success
        : OnlineBranchesStoreResult.failed;
  }

  @override
  Future<bool> openManagement() async {
    if (RevenueCatConfig.isSupported) {
      return _revenueCat.openSubscriptionManagement();
    }
    if (PlatformUtils.isWindows || PlatformUtils.isLinux) {
      return launchUrl(
        Uri.parse(DesktopLicenseService.manageLicenseUrl),
        mode: LaunchMode.externalApplication,
      );
    }
    return false;
  }
}
