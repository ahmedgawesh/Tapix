// LineItemPricingEngine tests — covers the per-line contract:
//   subtotal → discount (% base = subtotal) → net → tax → total
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/money/money.dart';
import 'package:tapix/core/pricing/discount.dart';
import 'package:tapix/core/pricing/line_item_pricing_engine.dart';

LineItemPricingResult _compute({
  int unitPriceCents = 10000,
  int quantity = 1,
  Discount discount = Discount.none,
  bool isTaxable = false,
  int productTaxRateBps = 0,
  bool enableTax = true,
  int defaultTaxRateBps = 0,
  bool taxInclusive = false,
}) {
  return LineItemPricingEngine.compute(
    input: LineItemPricingInput(
      unitPrice: Money.fromCents(unitPriceCents),
      quantity: quantity,
      discount: discount,
      isTaxable: isTaxable,
      productTaxRateBps: productTaxRateBps,
    ),
    enableTaxCalculations: enableTax,
    defaultTaxRateBps: defaultTaxRateBps,
    taxInclusivePricing: taxInclusive,
  );
}

void main() {
  group('LineItemPricingEngine — basic composition', () {
    test('no discount, no tax', () {
      final r = _compute(unitPriceCents: 10000, quantity: 5);
      expect(r.subtotal.cents, 50000);
      expect(r.discount.cents, 0);
      expect(r.net.cents, 50000);
      expect(r.tax.cents, 0);
      expect(r.total.cents, 50000);
      expect(r.effectiveTaxRateBps, 0);
    });

    test('zero quantity → all zero', () {
      final r = _compute(quantity: 0);
      expect(r.subtotal, Money.zero);
      expect(r.total, Money.zero);
    });

    test('negative quantity throws', () {
      expect(
        () => _compute(quantity: -1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('LineItemPricingEngine — discount contract', () {
    test('Discount.percent base IS the subtotal (the bug fix)', () {
      // 100.00 × 5 = 500.00 subtotal. 1 % = 5.00.
      final r = _compute(
        unitPriceCents: 10000,
        quantity: 5,
        discount: Discount.percent(100),
      );
      expect(r.subtotal.cents, 50000);
      expect(r.discount.cents, 500);
      expect(r.net.cents, 49500);
    });

    test('Discount.fixed clamps to subtotal (cannot over-discount)', () {
      final r = _compute(
        unitPriceCents: 1000,
        quantity: 1,
        discount: Discount.fixed(Money.fromCents(99999)),
      );
      expect(r.discount.cents, 1000);
      expect(r.net.cents, 0);
      expect(r.total.cents, 0);
    });

    test('Discount.percent > 100 % clamps to subtotal', () {
      final r = _compute(
        unitPriceCents: 1000,
        quantity: 1,
        discount: Discount.percent(15000), // 150 %
      );
      expect(r.discount.cents, 1000);
      expect(r.net.cents, 0);
    });

    test('Discount.none → zero discount', () {
      final r = _compute(unitPriceCents: 5000, quantity: 2);
      expect(r.discount, Money.zero);
    });
  });

  group('LineItemPricingEngine — tax composition', () {
    test('exclusive tax on net after discount', () {
      // 200.00 subtotal, 10 % discount = 20.00 → net 180.00, 15 % tax = 27.00
      final r = _compute(
        unitPriceCents: 20000,
        quantity: 1,
        discount: Discount.percent(1000), // 10 %
        isTaxable: true,
        productTaxRateBps: 1500,
      );
      expect(r.subtotal.cents, 20000);
      expect(r.discount.cents, 2000);
      expect(r.net.cents, 18000);
      expect(r.tax.cents, 2700);
      expect(r.total.cents, 20700);
      expect(r.effectiveTaxRateBps, 1500);
    });

    test('global tax disabled → tax always zero', () {
      final r = _compute(
        unitPriceCents: 10000,
        quantity: 1,
        isTaxable: true,
        productTaxRateBps: 1500,
        enableTax: false,
      );
      expect(r.tax.cents, 0);
    });

    test('falls back to default tax rate when product rate is 0', () {
      final r = _compute(
        unitPriceCents: 10000,
        quantity: 1,
        isTaxable: true,
        productTaxRateBps: 0,
        defaultTaxRateBps: 1400,
      );
      expect(r.effectiveTaxRateBps, 1400);
      expect(r.tax.cents, 1400);
    });

    test('isTaxable=false but defaultTaxRateBps>0 still applies default rate '
        '(matches existing TaxCalculationService.resolveLineItemTaxRateBps '
        'semantic — refactor preserves behavior)', () {
      final r = _compute(
        unitPriceCents: 10000,
        quantity: 1,
        isTaxable: false,
        productTaxRateBps: 0,
        defaultTaxRateBps: 1400,
      );
      expect(r.effectiveTaxRateBps, 1400);
      expect(r.tax.cents, 1400);
    });
  });

  group('LineItemPricingEngine — invariants', () {
    test('subtotal − discount + tax == total', () {
      for (final qty in [1, 3, 7, 12]) {
        for (final pct in [0, 50, 100, 250, 999]) {
          final r = _compute(
            unitPriceCents: 12345,
            quantity: qty,
            discount: Discount.percent(pct),
            isTaxable: true,
            productTaxRateBps: 1500,
          );
          expect(
            (r.subtotal - r.discount + r.tax).cents,
            r.total.cents,
            reason: 'qty=$qty pct=$pct',
          );
          expect(r.net.cents >= 0, isTrue);
        }
      }
    });

    test('quantity change re-evaluates percent discount (closes bug #2)', () {
      final base = _compute(
        unitPriceCents: 10000,
        quantity: 1,
        discount: Discount.percent(100),
      );
      final doubled = _compute(
        unitPriceCents: 10000,
        quantity: 2,
        discount: Discount.percent(100),
      );
      expect(doubled.discount.cents, base.discount.cents * 2);
      expect(doubled.subtotal.cents, base.subtotal.cents * 2);
    });
  });

  group('LineItemPricingEngine — resolveDiscount', () {
    test('matches what compute() applies', () {
      final d = LineItemPricingEngine.resolveDiscount(
        unitPrice: Money.fromCents(10000),
        quantity: 5,
        discount: Discount.percent(100),
      );
      expect(d.cents, 500);
    });
  });
}
