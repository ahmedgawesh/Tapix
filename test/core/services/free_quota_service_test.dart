import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/services/feature_gate_service.dart';
import 'package:tapix/core/services/free_quota_service.dart';

/// Minimal fake that lets us flip [isPro] freely without touching the real
/// RevenueCat SDK or its stream. Extends [ChangeNotifier] so it satisfies the
/// `FeatureGateService` interface (which is itself a [ChangeNotifier]).
class _FakeFeatureGateService extends ChangeNotifier
    implements FeatureGateService {
  @override
  bool isPro = false;

  @override
  bool get isInitialized => true;

  @override
  FeatureAccess canAccess(AppFeature feature) {
    if (!FeatureGateService.requiresPro(feature)) {
      return const FeatureAccess.granted();
    }
    return isPro
        ? const FeatureAccess.granted()
        : const FeatureAccess.denied(FeatureDenyReason.requiresPro);
  }

  @override
  Future<void> refresh() async {}
}

void main() {
  late SharedPreferences prefs;
  late _FakeFeatureGateService fakeGate;
  late FreeQuotaService quota;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    fakeGate = _FakeFeatureGateService();
    quota = FreeQuotaService(
      prefs: prefs,
      featureGateService: fakeGate,
      // Use tiny limits to keep tests fast and unambiguous.
      maxProductsLifetime: 3,
      maxSalesLifetime: 3,
    );
  });

  group('Initial state', () {
    test('zero counters on fresh install', () {
      expect(quota.productsCreatedLifetime, 0);
      expect(quota.salesCreatedLifetime, 0);
    });

    test('canCreateProduct returns true initially', () {
      expect(quota.canCreateProduct(), isTrue);
    });

    test('canCreateSale returns true initially', () {
      expect(quota.canCreateSale(), isTrue);
    });

    test('status reflects free tier with full quota remaining', () {
      final s = quota.status();
      expect(s.productsLimit, 3);
      expect(s.salesLimit, 3);
      expect(s.productsRemaining, 3);
      expect(s.salesRemaining, 3);
      expect(s.productsExhausted, isFalse);
      expect(s.salesExhausted, isFalse);
    });
  });

  group('Increment + cap (free tier)', () {
    test('increments lift counters by 1', () async {
      await quota.incrementProductsCreated();
      expect(quota.productsCreatedLifetime, 1);

      await quota.incrementProductsCreated();
      expect(quota.productsCreatedLifetime, 2);
    });

    test('canCreateProduct flips false at exact cap', () async {
      await quota.incrementProductsCreated();
      await quota.incrementProductsCreated();
      await quota.incrementProductsCreated();
      expect(quota.canCreateProduct(), isFalse);
    });

    test('guardProductCreation throws at exact cap', () async {
      await quota.incrementProductsCreated();
      await quota.incrementProductsCreated();
      await quota.incrementProductsCreated();

      expect(
        () => quota.guardProductCreation(),
        throwsA(isA<FreeQuotaExceededException>()
            .having((e) => e.kind, 'kind', FreeQuotaKind.products)
            .having((e) => e.limit, 'limit', 3)
            .having((e) => e.currentCount, 'current', 3)),
      );
    });

    test('guardSaleCreation throws at exact cap', () async {
      for (var i = 0; i < 3; i++) {
        await quota.incrementSalesCreated();
      }

      expect(
        () => quota.guardSaleCreation(),
        throwsA(isA<FreeQuotaExceededException>()
            .having((e) => e.kind, 'kind', FreeQuotaKind.sales)),
      );
    });

    test('products and sales counters are independent', () async {
      for (var i = 0; i < 3; i++) {
        await quota.incrementProductsCreated();
      }
      expect(quota.canCreateProduct(), isFalse);
      // Sales counter is untouched → can still create sales.
      expect(quota.canCreateSale(), isTrue);
    });

    test('status reflects remaining at boundary', () async {
      await quota.incrementProductsCreated();
      await quota.incrementProductsCreated();

      final s = quota.status();
      expect(s.productsCreatedLifetime, 2);
      expect(s.productsRemaining, 1);
      expect(s.productsExhausted, isFalse);

      await quota.incrementProductsCreated();
      final s2 = quota.status();
      expect(s2.productsRemaining, 0);
      expect(s2.productsExhausted, isTrue);
    });
  });

  group('Pro bypass', () {
    test('Pro user can create unlimited products even past the cap', () async {
      fakeGate.isPro = true;
      for (var i = 0; i < 10; i++) {
        await quota.incrementProductsCreated();
      }
      // Counter still increments (audit trail), but guard always passes.
      expect(quota.productsCreatedLifetime, 10);
      expect(quota.canCreateProduct(), isTrue);
      expect(() => quota.guardProductCreation(), returnsNormally);
    });

    test('Pro user status has null limits (unlimited)', () {
      fakeGate.isPro = true;
      final s = quota.status();
      expect(s.productsLimit, isNull);
      expect(s.salesLimit, isNull);
      expect(s.productsRemaining, isNull);
      expect(s.isUnlimited, isTrue);
    });

    test('Pro→free downgrade re-applies cap with retained counter', () async {
      fakeGate.isPro = true;
      for (var i = 0; i < 5; i++) {
        await quota.incrementProductsCreated();
      }
      // Subscription lapses.
      fakeGate.isPro = false;

      // Counter is 5, cap is 3 → already past cap, guard throws.
      expect(() => quota.guardProductCreation(), throwsA(isA<FreeQuotaExceededException>()));
      expect(quota.canCreateProduct(), isFalse);
    });
  });

  group('Counter never decrements (cumulative invariant)', () {
    test('reset is only available through @visibleForTesting helper', () async {
      await quota.incrementProductsCreated();
      await quota.incrementProductsCreated();
      expect(quota.productsCreatedLifetime, 2);

      // Public API offers no decrement / reset method.
      // Only the test helper can reset.
      await quota.resetCountersForTesting();
      expect(quota.productsCreatedLifetime, 0);
      expect(quota.salesCreatedLifetime, 0);
    });
  });

  group('Persistence across instances', () {
    test('counters persist via SharedPreferences', () async {
      await quota.incrementProductsCreated();
      await quota.incrementProductsCreated();
      await quota.incrementSalesCreated();

      // Re-construct service with the same prefs instance.
      final quota2 = FreeQuotaService(
        prefs: prefs,
        featureGateService: fakeGate,
        maxProductsLifetime: 3,
        maxSalesLifetime: 3,
      );
      expect(quota2.productsCreatedLifetime, 2);
      expect(quota2.salesCreatedLifetime, 1);
    });
  });
}
