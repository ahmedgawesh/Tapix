import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/lan/lan_business_models.dart';
import 'package:tapix/features/settings/domain/entities/app_settings.dart';

void main() {
  group('LAN receipt messages', () {
    test('catalog transport preserves master header and footer exactly', () {
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
        receiptHeaderText: 'Master header',
        receiptFooterText: 'Master footer',
      );

      final restored = LanCatalogPage.fromJson(page.toJson());
      expect(restored.receiptHeaderText, 'Master header');
      expect(restored.receiptFooterText, 'Master footer');
      expect(LanCatalogPage.fromJson(const {}).receiptHeaderText, isNull);
      expect(LanCatalogPage.fromJson(const {}).receiptFooterText, isNull);
    });

    test('sale details transport preserves blank master messages', () {
      final now = DateTime.utc(2026, 9, 13);
      final details = LanSaleDetails(
        sale: LanSaleSummary(
          id: 1,
          invoiceNumber: 'SI-202609-000001',
          subtotalCents: 100,
          taxCents: 0,
          discountCents: 0,
          totalCents: 100,
          paidAmountCents: 100,
          currencyId: 1,
          paymentMethod: 'cash',
          status: 'completed',
          saleDate: now,
          taxInclusiveAtPost: false,
          createdAt: now,
          updatedAt: now,
        ),
        lines: const [],
        currencyCode: 'USD',
        currencySymbol: r'$',
        currencyDecimalDigits: 2,
        currencySymbolAfter: false,
        receiptHeaderText: '',
        receiptFooterText: '',
      );

      final restored = LanSaleDetails.fromJson(details.toJson());
      expect(restored.receiptHeaderText, '');
      expect(restored.receiptFooterText, '');
    });

    test('sale result transport carries the latest master messages', () {
      const result = LanSaleResult(
        saleId: 1,
        invoiceNumber: 'SI-202609-000001',
        subtotalCents: 100,
        discountCents: 0,
        taxCents: 0,
        totalCents: 100,
        paidAmountCents: 100,
        receiptHeaderText: 'Latest header',
        receiptFooterText: 'Latest footer',
      );

      final restored = LanSaleResult.fromJson(result.toJson());
      expect(restored.receiptHeaderText, 'Latest header');
      expect(restored.receiptFooterText, 'Latest footer');
    });
  });

  group('below-cost sale policy', () {
    test('is deny-by-default and survives settings JSON persistence', () {
      expect(const AppSettings().allowBelowCostSales, isFalse);
      expect(AppSettings.fromMap(const {}).allowBelowCostSales, isFalse);

      final enabled = const AppSettings().copyWith(allowBelowCostSales: true);
      expect(
        AppSettings.fromJson(enabled.toJson()).allowBelowCostSales,
        isTrue,
      );
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
        allowBelowCostSales: true,
      );

      final restored = LanCatalogPage.fromJson(page.toJson());
      expect(restored.allowBelowCostSales, isTrue);
      expect(LanCatalogPage.fromJson(const {}).allowBelowCostSales, isFalse);
    });
  });

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
