import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tapix/core/services/feature_gate_service.dart';
import 'package:tapix/core/services/free_quota_service.dart';
import 'package:tapix/core/services/local_integrity_key_service.dart';

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
  bool isEnabled(AppFeature feature, {required bool settingEnabled}) =>
      settingEnabled && canAccess(feature).granted;

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
        throwsA(
          isA<FreeQuotaExceededException>()
              .having((e) => e.kind, 'kind', FreeQuotaKind.products)
              .having((e) => e.limit, 'limit', 3)
              .having((e) => e.currentCount, 'current', 3),
        ),
      );
    });

    test('atomic batch guard rejects the whole batch before the cap', () async {
      await quota.incrementProductsCreated();
      expect(
        () => quota.guardProductCreations(3),
        throwsA(
          isA<FreeQuotaExceededException>()
              .having((e) => e.currentCount, 'current', 1)
              .having((e) => e.limit, 'limit', 3),
        ),
      );
      expect(quota.productsCreatedLifetime, 1);
    });

    test('rolled-back batch restores the pre-transaction counter', () async {
      await quota.incrementProductsCreatedBy(2);
      final snapshot = quota.productsCreatedLifetime;
      await quota.incrementProductsCreatedBy(1);
      await quota.restoreProductsCreatedAfterRollback(snapshot);
      expect(quota.productsCreatedLifetime, 2);
    });

    test('guardSaleCreation throws at exact cap', () async {
      for (var i = 0; i < 3; i++) {
        await quota.incrementSalesCreated();
      }

      expect(
        () => quota.guardSaleCreation(),
        throwsA(
          isA<FreeQuotaExceededException>().having(
            (e) => e.kind,
            'kind',
            FreeQuotaKind.sales,
          ),
        ),
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
      expect(
        () => quota.guardProductCreation(),
        throwsA(isA<FreeQuotaExceededException>()),
      );
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

  group('Signed secure persistence', () {
    test(
      'migrates legacy counters and reconciles committed database rows',
      () async {
        await prefs.setInt('free_quota.products_created_lifetime', 2);
        await prefs.setInt('free_quota.sales_created_lifetime', 1);
        final store = _MemoryQuotaStateStore();
        final signer = LocalIntegrityKeyService.testing(
          List<int>.filled(32, 7),
        );
        final secured = FreeQuotaService(
          prefs: prefs,
          featureGateService: fakeGate,
          stateStore: store,
          integritySigner: signer,
          usageReader: () async => (products: 5, sales: 4),
          maxProductsLifetime: 10,
          maxSalesLifetime: 10,
        );

        await secured.initialize();

        expect(secured.productsCreatedLifetime, 5);
        expect(secured.salesCreatedLifetime, 4);
        expect(store.value, isNotNull);
      },
    );

    test('ignores edited SharedPreferences after secure migration', () async {
      final store = _MemoryQuotaStateStore();
      final signer = LocalIntegrityKeyService.testing(List<int>.filled(32, 8));
      final first = FreeQuotaService(
        prefs: prefs,
        featureGateService: fakeGate,
        stateStore: store,
        integritySigner: signer,
        usageReader: () async => (products: 0, sales: 0),
        maxProductsLifetime: 10,
        maxSalesLifetime: 10,
      );
      await first.initialize();
      await first.incrementProductsCreatedBy(6);
      await first.incrementSalesCreated();
      await prefs.setInt('free_quota.products_created_lifetime', 0);
      await prefs.setInt('free_quota.sales_created_lifetime', 0);

      final reloaded = FreeQuotaService(
        prefs: prefs,
        featureGateService: fakeGate,
        stateStore: store,
        integritySigner: signer,
        usageReader: () async => (products: 0, sales: 0),
        maxProductsLifetime: 10,
        maxSalesLifetime: 10,
      );
      await reloaded.initialize();

      expect(reloaded.productsCreatedLifetime, 6);
      expect(reloaded.salesCreatedLifetime, 1);
    });

    test('invalid secure signature fails closed at the free limit', () async {
      final store = _MemoryQuotaStateStore()
        ..value =
            '{"version":1,"products":0,"sales":0,"signature":"${'0' * 64}"}';
      final secured = FreeQuotaService(
        prefs: prefs,
        featureGateService: fakeGate,
        stateStore: store,
        integritySigner: LocalIntegrityKeyService.testing(
          List<int>.filled(32, 9),
        ),
        usageReader: () async => (products: 1, sales: 2),
        maxProductsLifetime: 3,
        maxSalesLifetime: 3,
      );

      await secured.initialize();

      expect(secured.productsCreatedLifetime, 3);
      expect(secured.salesCreatedLifetime, 3);
      expect(secured.canCreateProduct(), isFalse);
      expect(secured.canCreateSale(), isFalse);
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

class _MemoryQuotaStateStore implements FreeQuotaStateStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> delete() async => value = null;
}
