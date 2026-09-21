import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/money/money.dart';
import 'package:tapix/core/pricing/invoice_pricing_engine.dart';
import 'package:tapix/core/pricing/line_item_pricing_engine.dart';
import 'package:tapix/core/pricing/pricing_preview_fingerprint.dart';

void main() {
  InvoicePricingResult price(List<int> rates) => InvoicePricingEngine.compute(
    InvoicePricingInput(
      lines: [
        for (final rate in rates)
          LineItemPricingInput(
            unitPrice: Money.fromCents(1000),
            quantity: 1,
            isTaxable: true,
            productTaxRateBps: rate,
          ),
      ],
      enableTaxCalculations: true,
      defaultTaxRateBps: 0,
      taxInclusivePricing: false,
    ),
  );

  test('equal invoice totals do not hide different line taxes', () {
    final first = price([1000, 2000]);
    final swapped = price([2000, 1000]);
    expect(first.total.cents, 2300);
    expect(first.total.cents, swapped.total.cents);
    expect(first.tax.cents, swapped.tax.cents);
    expect(
      pricingPreviewFingerprint(first, taxInclusive: false),
      isNot(pricingPreviewFingerprint(swapped, taxInclusive: false)),
    );
    expect(
      pricingPreviewFingerprint(first, taxInclusive: false),
      pricingPreviewFingerprint(price([1000, 2000]), taxInclusive: false),
    );
  });

  test('tax inclusion differs even when zero tax leaves totals equal', () {
    final result = price([0]);
    expect(
      pricingPreviewFingerprint(result, taxInclusive: false),
      isNot(pricingPreviewFingerprint(result, taxInclusive: true)),
    );
  });
}
