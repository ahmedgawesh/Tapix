import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/business/data/online_branches_entitlement.dart';

void main() {
  final now = DateTime.utc(2026, 9, 25, 12);

  group('online branches commercial boundary', () {
    test('base Pro keeps local operations without online add-on', () {
      final result = OnlineBranchesEntitlementPolicy.evaluate(
        baseProActive: true,
        addOnActive: false,
        now: now,
      );

      expect(result.state, OnlineBranchesEntitlementState.addOnRequired);
      expect(result.permitsLocalOperations, isTrue);
      expect(result.permitsOnlineBranches, isFalse);
    });

    test('active add-on requires base Pro and preserves plan metadata', () {
      final result = OnlineBranchesEntitlementPolicy.evaluate(
        baseProActive: true,
        addOnActive: true,
        expirationDate: now.add(const Duration(days: 30)),
        willRenew: true,
        productId: 'online.yearly',
        maxBranches: 8,
        maxWarehouses: 24,
        now: now,
      );

      expect(result.state, OnlineBranchesEntitlementState.active);
      expect(result.permitsOnlineBranches, isTrue);
      expect(result.willRenew, isTrue);
      expect(result.productId, 'online.yearly');
      expect(result.maxBranches, 8);
      expect(result.maxWarehouses, 24);
    });

    test('online add-on never substitutes for base Pro', () {
      final result = OnlineBranchesEntitlementPolicy.evaluate(
        baseProActive: false,
        addOnActive: true,
        now: now,
      );

      expect(result.state, OnlineBranchesEntitlementState.baseProRequired);
      expect(result.permitsLocalOperations, isFalse);
      expect(result.permitsOnlineBranches, isFalse);
    });

    test('expired add-on leaves local Pro operations available', () {
      final result = OnlineBranchesEntitlementPolicy.evaluate(
        baseProActive: true,
        addOnActive: true,
        expirationDate: now,
        willRenew: true,
        maxBranches: -1,
        maxWarehouses: 0,
        now: now,
      );

      expect(result.state, OnlineBranchesEntitlementState.expired);
      expect(result.permitsLocalOperations, isTrue);
      expect(result.permitsOnlineBranches, isFalse);
      expect(result.addOnActive, isFalse);
      expect(result.willRenew, isFalse);
      expect(result.maxBranches, isNull);
      expect(result.maxWarehouses, isNull);
    });

    test('unsupported platform fails closed for online access', () {
      final result = OnlineBranchesEntitlementPolicy.evaluate(
        baseProActive: true,
        addOnActive: true,
        platformAvailable: false,
        now: now,
      );

      expect(result.state, OnlineBranchesEntitlementState.unavailable);
      expect(result.permitsOnlineBranches, isFalse);
    });
  });
}
