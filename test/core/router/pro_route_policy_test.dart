import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/router/pro_route_policy.dart';
import 'package:tapix/core/services/feature_gate_service.dart';

void main() {
  group('ProRoutePolicy — free (never gated) paths', () {
    const freePaths = <String>[
      '/',
      '/splash',
      '/welcome',
      '/login',
      '/forgot-password',
      '/setup',
      '/access-denied',
      '/upgrade',
      '/dashboard',
    ];

    for (final path in freePaths) {
      test('$path does not require Pro', () {
        expect(ProRoutePolicy.requiresPro(path), isFalse);
      });
    }
  });

  group('ProRoutePolicy — products & sales are free', () {
    const freeFeaturePaths = <String>[
      '/products',
      '/products/new',
      '/products/123/edit',
      '/products/bulk',
      '/products/import',
      '/products/export',
      '/products/edit-prices',
      '/products/variants',
      '/products/categories',
      '/products/categories/new',
      '/products/colors',
      '/products/sizes',
      '/sales',
      '/sales/new',
      '/sales/42',
      '/sales/42/edit',
      '/barcode-scanner',
      '/settings',
      '/settings/company',
    ];

    for (final path in freeFeaturePaths) {
      test('$path is free', () {
        expect(
          ProRoutePolicy.requiresPro(path),
          isFalse,
          reason: '$path should be reachable on the free tier',
        );
      });
    }
  });

  group('ProRoutePolicy — Pro exceptions nested under free prefixes', () {
    const proNestedPaths = <String>[
      '/products/barcode-design',
      '/sales/returns',
      '/sales/returns/new',
      '/sales/returns/adjustment',
      '/settings/backup',
      '/settings/admin-tools',
    ];

    for (final path in proNestedPaths) {
      test('$path requires Pro', () {
        expect(
          ProRoutePolicy.requiresPro(path),
          isTrue,
          reason: '$path is a Pro-only nested route',
        );
      });
    }
  });

  group('ProRoutePolicy — fully locked Pro sections', () {
    const proPaths = <String>[
      '/customers',
      '/customers/new',
      '/customers/5',
      '/suppliers',
      '/suppliers/3',
      '/purchases',
      '/purchases/new',
      '/expenses',
      '/reports',
      '/reports/profit-loss',
      '/reports/sales/by-period',
      '/users',
      '/users/add',
      '/employees',
      '/employees/payroll',
      '/cashier-shifts',
      '/cashier-shifts/42',
      '/client-session',
      '/financial-management',
      '/financial-management/chart-of-accounts',
      '/cheques',
      '/accounting',
      '/accounting/journal-entries',
      '/audit',
      '/barcode-designer',
      '/promotions',
    ];

    for (final path in proPaths) {
      test('$path requires Pro', () {
        expect(ProRoutePolicy.requiresPro(path), isTrue);
      });
    }
  });

  group('ProRoutePolicy — featureFor mapping', () {
    test('barcode scan vs print asymmetry', () {
      expect(
        ProRoutePolicy.featureFor('/barcode-scanner'),
        AppFeature.barcodeScan,
      );
      expect(
        ProRoutePolicy.featureFor('/barcode-designer'),
        AppFeature.barcodePrint,
      );
      expect(
        ProRoutePolicy.featureFor('/products/barcode-design'),
        AppFeature.barcodePrint,
      );
    });

    test('sales returns override beats sales free prefix', () {
      expect(ProRoutePolicy.featureFor('/sales/new'), AppFeature.salesCreate);
      expect(ProRoutePolicy.featureFor('/sales/returns'), AppFeature.returns);
    });

    test('settings sub-route overrides', () {
      expect(ProRoutePolicy.featureFor('/settings'), AppFeature.basicSettings);
      expect(
        ProRoutePolicy.featureFor('/settings/backup'),
        AppFeature.backupRestore,
      );
    });

    test('manager and cashier shift routes use the same Pro feature', () {
      expect(
        ProRoutePolicy.featureFor('/cashier-shifts'),
        AppFeature.cashierShifts,
      );
      expect(
        ProRoutePolicy.featureFor('/cashier-shifts/42'),
        AppFeature.cashierShifts,
      );
      expect(
        ProRoutePolicy.featureFor('/client-session'),
        AppFeature.cashierShifts,
      );
    });

    test('unknown path is ungated (null)', () {
      expect(ProRoutePolicy.featureFor('/some-unknown-deep-link'), isNull);
      expect(ProRoutePolicy.requiresPro('/some-unknown-deep-link'), isFalse);
    });
  });

  test('reports/customers is gated by reports, not customers prefix', () {
    // Guards against prefix confusion: /reports/customers must NOT be treated
    // as the /customers section (both Pro here, but the feature must be reports).
    expect(ProRoutePolicy.featureFor('/reports/customers'), AppFeature.reports);
  });
}
