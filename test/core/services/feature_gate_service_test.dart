import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/services/feature_gate_service.dart';
import 'package:tapix/core/services/revenuecat_service.dart';

void main() {
  group('FeatureGateService — licensed Linux desktop', () {
    // RevenueCat is intentionally unsupported on desktop. Windows/Linux now
    // receive Pro entitlement from DesktopLicenseService instead, so absence
    // of a valid desktop license must never unlock Pro features.
    test('isSupported is false on the test host', () {
      expect(RevenueCatConfig.isSupported, isFalse);
    });

    test('isPro is false when no valid desktop license is supplied', () {
      final gate = FeatureGateService(
        revenueCatService: RevenueCatService.instance,
      );
      addTearDown(gate.dispose);

      expect(gate.isPro, isFalse);
      expect(gate.isInitialized, isTrue);
    });

    test('canAccess grants free features and denies Pro features', () {
      final gate = FeatureGateService(
        revenueCatService: RevenueCatService.instance,
      );
      addTearDown(gate.dispose);

      for (final f in AppFeature.values) {
        final access = gate.canAccess(f);
        final requiresPro = FeatureGateService.requiresPro(f);
        expect(
          access.granted,
          !requiresPro,
          reason: '$f must follow its tier when no desktop license is valid',
        );
        expect(
          access.denyReason,
          requiresPro ? FeatureDenyReason.requiresPro : isNull,
        );
      }
    });
  });

  group('FeatureGateService.requiresPro — Pro-only matrix', () {
    test('barcodePrint requires Pro (free users cannot print labels)', () {
      expect(FeatureGateService.requiresPro(AppFeature.barcodePrint), isTrue);
    });

    test('backupRestore requires Pro', () {
      expect(FeatureGateService.requiresPro(AppFeature.backupRestore), isTrue);
    });

    test('purchases requires Pro', () {
      expect(FeatureGateService.requiresPro(AppFeature.purchases), isTrue);
    });

    test('customers requires Pro', () {
      expect(FeatureGateService.requiresPro(AppFeature.customers), isTrue);
    });

    test('suppliers requires Pro', () {
      expect(FeatureGateService.requiresPro(AppFeature.suppliers), isTrue);
    });

    test('employees requires Pro', () {
      expect(FeatureGateService.requiresPro(AppFeature.employees), isTrue);
    });

    test('cashierShifts requires Pro on every entitlement platform', () {
      expect(FeatureGateService.requiresPro(AppFeature.cashierShifts), isTrue);
    });

    test('inventoryAdvanced requires Pro', () {
      expect(
        FeatureGateService.requiresPro(AppFeature.inventoryAdvanced),
        isTrue,
      );
    });

    test('returns requires Pro', () {
      expect(FeatureGateService.requiresPro(AppFeature.returns), isTrue);
    });

    test('cheques requires Pro', () {
      expect(FeatureGateService.requiresPro(AppFeature.cheques), isTrue);
    });

    test('reports requires Pro', () {
      expect(FeatureGateService.requiresPro(AppFeature.reports), isTrue);
    });

    test('accounting requires Pro', () {
      expect(FeatureGateService.requiresPro(AppFeature.accounting), isTrue);
    });

    test('reconciliation requires Pro', () {
      expect(
        FeatureGateService.requiresPro(AppFeature.reconciliation),
        isTrue,
      );
    });

    test('multiUser requires Pro', () {
      expect(FeatureGateService.requiresPro(AppFeature.multiUser), isTrue);
    });
  });

  group('FeatureGateService.requiresPro — Always-free matrix', () {
    test('productsManage is free', () {
      expect(
        FeatureGateService.requiresPro(AppFeature.productsManage),
        isFalse,
      );
    });

    test('salesCreate is free', () {
      expect(FeatureGateService.requiresPro(AppFeature.salesCreate), isFalse);
    });

    test('salesView is free', () {
      expect(FeatureGateService.requiresPro(AppFeature.salesView), isFalse);
    });

    test('productMetadata is free (categories, tax, units)', () {
      expect(
        FeatureGateService.requiresPro(AppFeature.productMetadata),
        isFalse,
      );
    });

    test('barcodeScan is free (POS lookup must work for free tier)', () {
      expect(FeatureGateService.requiresPro(AppFeature.barcodeScan), isFalse);
    });

    test('authentication is free', () {
      expect(
        FeatureGateService.requiresPro(AppFeature.authentication),
        isFalse,
      );
    });

    test('basicSettings is free (language, theme)', () {
      expect(
        FeatureGateService.requiresPro(AppFeature.basicSettings),
        isFalse,
      );
    });
  });

  group('FeatureGateService.requiresPro — exhaustive enum coverage', () {
    test('every AppFeature value is classified', () {
      // Guards against a future enum value forgotten in the switch.
      for (final f in AppFeature.values) {
        // Should not throw — switch must cover every case.
        // (If a new enum value is added without updating requiresPro,
        // Dart's exhaustive switch will fail at compile time.)
        // ignore: unused_local_variable
        final _ = FeatureGateService.requiresPro(f);
      }
    });

    test('barcode asymmetry: scan free, print Pro', () {
      // Specifically pinned per product requirement (Phase B1):
      // POS must work for free users, but generating barcode labels is Pro.
      expect(FeatureGateService.requiresPro(AppFeature.barcodeScan), isFalse);
      expect(FeatureGateService.requiresPro(AppFeature.barcodePrint), isTrue);
    });
  });
}
