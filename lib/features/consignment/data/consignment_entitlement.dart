import '../../../core/services/business/local_branch_scope.dart';
import '../../../core/services/feature_gate_service.dart';

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

/// Uses the same verified Pro state as the rest of the application, including
/// AppGuard's device-bound offline licence and signed desktop licences.
/// A separate store request here would disable valid offline installations.
class PlatformConsignmentEntitlement implements ConsignmentEntitlement {
  const PlatformConsignmentEntitlement({
    required FeatureGateService featureGate,
  }) : _featureGate = featureGate;

  final FeatureGateService _featureGate;

  @override
  Future<bool> permits(LocalBranchScope scope) async =>
      _featureGate.canAccess(AppFeature.inventoryAdvanced).granted;
}

class GrantedConsignmentEntitlement implements ConsignmentEntitlement {
  const GrantedConsignmentEntitlement();

  @override
  Future<bool> permits(LocalBranchScope scope) async => true;
}
