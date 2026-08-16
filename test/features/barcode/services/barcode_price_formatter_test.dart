import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/barcode/domain/models/barcode_design_state.dart';
import 'package:tapix/features/barcode/services/barcode_price_formatter.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';

void main() {
  final product = Product(
    id: 1,
    name: 'Test',
    costCents: Decimal.fromInt(700),
    priceCents: Decimal.fromInt(1500),
    wholesalePriceCents: Decimal.fromInt(1200),
    stockQuantity: 1,
    minQuantity: 0,
    hasVariants: false,
    isTaxable: false,
    purchaseTaxRateBps: 0,
    salesTaxRateBps: 0,
    isActive: true,
    trackInventory: true,
  );

  String format(int cents) => '\$$cents';

  test('retail mode formats selling price and never cost', () {
    expect(
      formatBarcodePrice(
        product: product,
        mode: PriceDisplayMode.retail,
        formatCurrency: format,
        retailLabel: 'Retail',
        wholesaleLabel: 'Wholesale',
      ),
      r'$1500',
    );
  });

  test('wholesale mode formats wholesale selling price', () {
    expect(
      formatBarcodePrice(
        product: product,
        mode: PriceDisplayMode.wholesale,
        formatCurrency: format,
        retailLabel: 'Retail',
        wholesaleLabel: 'Wholesale',
      ),
      r'Wholesale: $1200',
    );
  });

  test('both mode labels both selling prices', () {
    expect(
      formatBarcodePrice(
        product: product,
        mode: PriceDisplayMode.both,
        formatCurrency: format,
        retailLabel: 'Retail',
        wholesaleLabel: 'Wholesale',
      ),
      'Retail: \$1500\nWholesale: \$1200',
    );
  });

  test(
    'missing wholesale price is explicit instead of falling back to cost',
    () {
      final withoutWholesale = product.copyWith(
        wholesalePriceCents: Decimal.zero,
      );
      final legacyProduct = Product(
        id: withoutWholesale.id,
        name: withoutWholesale.name,
        costCents: withoutWholesale.costCents,
        priceCents: withoutWholesale.priceCents,
        stockQuantity: withoutWholesale.stockQuantity,
        minQuantity: withoutWholesale.minQuantity,
        hasVariants: withoutWholesale.hasVariants,
        isTaxable: withoutWholesale.isTaxable,
        purchaseTaxRateBps: withoutWholesale.purchaseTaxRateBps,
        salesTaxRateBps: withoutWholesale.salesTaxRateBps,
        isActive: withoutWholesale.isActive,
        trackInventory: withoutWholesale.trackInventory,
      );

      expect(
        formatBarcodePrice(
          product: legacyProduct,
          mode: PriceDisplayMode.wholesale,
          formatCurrency: format,
          retailLabel: 'Retail',
          wholesaleLabel: 'Wholesale',
        ),
        'Wholesale: -',
      );
    },
  );
}
