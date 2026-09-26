import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/business/data/online_branches_entitlement.dart';
import 'package:tapix/features/business/data/online_branches_purchase_service.dart';

class _Gateway implements OnlineBranchesPurchaseGateway {
  List<OnlineBranchesPlan> plans = const [];
  OnlineBranchesStoreResult purchaseResult =
      OnlineBranchesStoreResult.unavailable;
  OnlineBranchesStoreResult restoreResult =
      OnlineBranchesStoreResult.unavailable;
  bool managementResult = false;
  int purchaseCalls = 0;
  int restoreCalls = 0;

  @override
  Future<List<OnlineBranchesPlan>> loadPlans() async => plans;

  @override
  Future<bool> openManagement() async => managementResult;

  @override
  Future<OnlineBranchesStoreResult> purchase(String planId) async {
    purchaseCalls++;
    return purchaseResult;
  }

  @override
  Future<OnlineBranchesStoreResult> restore() async {
    restoreCalls++;
    return restoreResult;
  }
}

class _Entitlement implements OnlineBranchesEntitlement {
  _Entitlement(this.snapshot);
  OnlineBranchesEntitlementSnapshot snapshot;
  int calls = 0;

  @override
  Future<OnlineBranchesEntitlementSnapshot> inspect() async {
    calls++;
    return snapshot;
  }
}

OnlineBranchesEntitlementSnapshot _snapshot(bool active) =>
    OnlineBranchesEntitlementPolicy.evaluate(
      baseProActive: true,
      addOnActive: active,
      now: DateTime.utc(2026, 9, 25),
    );

void main() {
  test('loads only plans exposed by the dedicated gateway', () async {
    final gateway = _Gateway()
      ..plans = const [
        OnlineBranchesPlan(
          id: 'annual',
          productId: 'online.annual',
          title: 'Annual',
          description: 'Online branches',
          price: r'$99',
        ),
      ];
    final service = DefaultOnlineBranchesPurchaseService(
      gateway: gateway,
      entitlement: _Entitlement(_snapshot(false)),
    );

    final plans = await service.loadPlans();
    expect(plans.single.productId, 'online.annual');
  });

  test(
    'successful store purchase activates only after entitlement verification',
    () async {
      final gateway = _Gateway()
        ..purchaseResult = OnlineBranchesStoreResult.success;
      final entitlement = _Entitlement(_snapshot(true));
      final service = DefaultOnlineBranchesPurchaseService(
        gateway: gateway,
        entitlement: entitlement,
      );

      final outcome = await service.purchase('annual');
      expect(outcome.activated, isTrue);
      expect(gateway.purchaseCalls, 1);
      expect(entitlement.calls, 1);
    },
  );

  test('store success without entitlement fails closed', () async {
    final gateway = _Gateway()
      ..purchaseResult = OnlineBranchesStoreResult.success;
    final service = DefaultOnlineBranchesPurchaseService(
      gateway: gateway,
      entitlement: _Entitlement(_snapshot(false)),
    );

    final outcome = await service.purchase('annual');
    expect(outcome.result, OnlineBranchesStoreResult.failed);
    expect(outcome.errorCode, 'entitlement_not_granted');
  });

  test('cancelled purchase does not query or change entitlement', () async {
    final gateway = _Gateway()
      ..purchaseResult = OnlineBranchesStoreResult.cancelled;
    final entitlement = _Entitlement(_snapshot(false));
    final service = DefaultOnlineBranchesPurchaseService(
      gateway: gateway,
      entitlement: entitlement,
    );

    final outcome = await service.purchase('annual');
    expect(outcome.result, OnlineBranchesStoreResult.cancelled);
    expect(entitlement.calls, 0);
  });

  test('restore succeeds only when the online entitlement exists', () async {
    final gateway = _Gateway()
      ..restoreResult = OnlineBranchesStoreResult.success;
    final entitlement = _Entitlement(_snapshot(true));
    final service = DefaultOnlineBranchesPurchaseService(
      gateway: gateway,
      entitlement: entitlement,
    );

    final outcome = await service.restore();
    expect(outcome.activated, isTrue);
    expect(gateway.restoreCalls, 1);
    expect(entitlement.calls, 1);
  });

  test('blank plan id is rejected before contacting the store', () async {
    final gateway = _Gateway()
      ..purchaseResult = OnlineBranchesStoreResult.success;
    final service = DefaultOnlineBranchesPurchaseService(
      gateway: gateway,
      entitlement: _Entitlement(_snapshot(true)),
    );

    final outcome = await service.purchase('  ');
    expect(outcome.result, OnlineBranchesStoreResult.failed);
    expect(outcome.errorCode, 'invalid_plan');
    expect(gateway.purchaseCalls, 0);
  });
}
