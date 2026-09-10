import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/lan/lan_business_models.dart';
import 'package:tapix/features/settings/domain/entities/app_settings.dart';

void main() {
  group('optional promotions feature', () {
    test('is opt-in and survives settings JSON persistence', () {
      expect(const AppSettings().enablePromotions, isFalse);
      expect(AppSettings.fromMap(const {}).enablePromotions, isFalse);

      final enabled = const AppSettings().copyWith(enablePromotions: true);
      expect(AppSettings.fromJson(enabled.toJson()).enablePromotions, isTrue);
    });

    test('is explicitly propagated in the LAN catalog contract', () {
      const page = LanCatalogPage(
        products: [],
        offset: 0,
        limit: 50,
        hasMore: false,
        currencyId: 1,
        currencyCode: 'USD',
        currencySymbol: r'$',
        enableTaxCalculations: true,
        defaultSalesTaxRateBps: 0,
        taxInclusivePricing: false,
        allowNegativeStock: false,
        allowPartialPayments: false,
        requireCustomerForSales: false,
        enablePromotions: true,
      );

      final restored = LanCatalogPage.fromJson(page.toJson());
      expect(restored.enablePromotions, isTrue);
      expect(LanCatalogPage.fromJson(const {}).enablePromotions, isFalse);
    });
  });
}
