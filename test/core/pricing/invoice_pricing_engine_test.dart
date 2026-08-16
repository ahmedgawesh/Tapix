// InvoicePricingEngine tests — covers the full invoice contract:
//   per-line breakdown → overall discount on Σ net → proration → tax → totals.
//
// The hero test is the regression for the user-reported bug:
//   "799.84 vs 799.92" — invoice-level 1 % must equal per-item 1 %.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/money/money.dart';
import 'package:tapix/core/pricing/discount.dart';
import 'package:tapix/core/pricing/invoice_pricing_engine.dart';
import 'package:tapix/core/pricing/line_item_pricing_engine.dart';

LineItemPricingInput _line({
  required int unitPriceCents,
  required int qty,
  Discount discount = Discount.none,
  bool isTaxable = false,
  int productTaxRateBps = 0,
}) => LineItemPricingInput(
  unitPrice: Money.fromCents(unitPriceCents),
  quantity: qty,
  discount: discount,
  isTaxable: isTaxable,
  productTaxRateBps: productTaxRateBps,
);

InvoicePricingResult _compute({
  required List<LineItemPricingInput> lines,
  Discount overall = Discount.none,
  bool enableTax = true,
  int defaultTaxRateBps = 0,
  bool taxInclusive = false,
}) => InvoicePricingEngine.compute(
  InvoicePricingInput(
    lines: lines,
    overallDiscount: overall,
    enableTaxCalculations: enableTax,
    defaultTaxRateBps: defaultTaxRateBps,
    taxInclusivePricing: taxInclusive,
  ),
);

void main() {
  group('InvoicePricingEngine — empty / trivial', () {
    test('no lines → empty result', () {
      final r = _compute(lines: const []);
      expect(r.subtotal, Money.zero);
      expect(r.total, Money.zero);
      expect(r.lines, isEmpty);
    });

    test('single line, no discount, no tax', () {
      final r = _compute(lines: [_line(unitPriceCents: 5000, qty: 3)]);
      expect(r.subtotal.cents, 15000);
      expect(r.itemDiscountTotal, Money.zero);
      expect(r.overallDiscount, Money.zero);
      expect(r.tax, Money.zero);
      expect(r.total.cents, 15000);
    });
  });

  group(
    'InvoicePricingEngine — bug regression: 1 % per-item == 1 % overall',
    () {
      // Reproduces the user's exact bug: 800.00 invoice with 1 % tax,
      // discount = 1 %. Per-item gave 799.92, overall gave 799.84.
      // After fix: both must give 799.92.
      final taxLine = _line(
        unitPriceCents: 80000,
        qty: 1,
        isTaxable: true,
        productTaxRateBps: 100, // 1 %
      );

      test('per-item 1 % discount on a single 800.00 line → total 799.92', () {
        final r = _compute(
          lines: [
            _line(
              unitPriceCents: 80000,
              qty: 1,
              discount: Discount.percent(100),
              isTaxable: true,
              productTaxRateBps: 100,
            ),
          ],
        );
        expect(r.subtotal.cents, 80000);
        expect(r.itemDiscountTotal.cents, 800);
        expect(r.overallDiscount, Money.zero);
        // net = 79200, tax = 792, total = 79992
        expect(r.tax.cents, 792);
        expect(r.total.cents, 79992);
      });

      test('overall 1 % discount on the same line → MUST equal 799.92', () {
        final r = _compute(lines: [taxLine], overall: Discount.percent(100));
        expect(r.subtotal.cents, 80000);
        expect(r.itemDiscountTotal, Money.zero);
        expect(
          r.overallDiscount.cents,
          800,
          reason: 'overall % base must be net (=80000), giving 800, not 808',
        );
        expect(r.tax.cents, 792);
        expect(r.total.cents, 79992);
      });

      test('per-item == overall for many random shapes (parity invariant)', () {
        // Same invoice computed two different ways — must agree.
        final shapes = <List<List<int>>>[
          // [unitPrice, qty, taxBps]
          [
            [80000, 1, 100],
          ],
          [
            [10000, 3, 1500],
            [25000, 2, 1500],
          ],
          [
            [12345, 7, 500],
            [6789, 4, 500],
            [99, 11, 500],
          ],
          [
            [50000, 1, 0],
            [50000, 1, 0],
          ], // no tax
        ];

        for (final shape in shapes) {
          final perItem = _compute(
            lines: shape
                .map(
                  (s) => _line(
                    unitPriceCents: s[0],
                    qty: s[1],
                    discount: Discount.percent(100),
                    isTaxable: true,
                    productTaxRateBps: s[2],
                  ),
                )
                .toList(),
          );
          final overall = _compute(
            lines: shape
                .map(
                  (s) => _line(
                    unitPriceCents: s[0],
                    qty: s[1],
                    isTaxable: true,
                    productTaxRateBps: s[2],
                  ),
                )
                .toList(),
            overall: Discount.percent(100),
          );

          // Totals must agree exactly.
          expect(
            overall.total.cents,
            perItem.total.cents,
            reason: 'parity broken for shape $shape',
          );
          expect(
            overall.tax.cents,
            perItem.tax.cents,
            reason: 'tax parity broken for shape $shape',
          );
        }
      });
    },
  );

  group('InvoicePricingEngine — proration of overall discount', () {
    test('overall discount distributed proportionally to net', () {
      // Two lines of 100.00 and 200.00, no per-line discount.
      // Net = 300.00. Overall fixed = 30.00 → shares 10 + 20.
      final r = _compute(
        lines: [
          _line(unitPriceCents: 10000, qty: 1),
          _line(unitPriceCents: 20000, qty: 1),
        ],
        overall: Discount.fixed(Money.fromCents(3000)),
      );
      expect(r.lines[0].shareOfOverallDiscount.cents, 1000);
      expect(r.lines[1].shareOfOverallDiscount.cents, 2000);
    });

    test(
      'shares always sum exactly to overall discount (no rounding drift)',
      () {
        // Use weights that don't divide evenly. Overall = 1 cent → must
        // land on exactly one slot.
        final r = _compute(
          lines: [
            _line(unitPriceCents: 333, qty: 1),
            _line(unitPriceCents: 333, qty: 1),
            _line(unitPriceCents: 334, qty: 1),
          ],
          overall: Discount.fixed(Money.fromCents(1)),
        );
        final sum = r.lines
            .map((l) => l.shareOfOverallDiscount.cents)
            .fold<int>(0, (a, b) => a + b);
        expect(sum, 1);
      },
    );

    test('overall discount > base clamps to base (cannot over-discount)', () {
      final r = _compute(
        lines: [_line(unitPriceCents: 1000, qty: 1)],
        overall: Discount.fixed(Money.fromCents(99999)),
      );
      expect(r.overallDiscount.cents, 1000);
      expect(r.total.cents, 0);
    });
  });

  group('InvoicePricingEngine — composition with per-line discounts', () {
    test('per-line + overall combined correctly', () {
      // Line A: 100.00 with 10 % per-line discount → net 90.00
      // Line B: 200.00 with 0 discount → net 200.00
      // Overall: 10 % of net (90+200=290) = 29.00
      // Distributed: A = 29 * 90/290 = 9 (rounded), B = 20.
      // Adjusted nets: A = 81, B = 180.
      final r = _compute(
        lines: [
          _line(
            unitPriceCents: 10000,
            qty: 1,
            discount: Discount.percent(1000), // 10 %
          ),
          _line(unitPriceCents: 20000, qty: 1),
        ],
        overall: Discount.percent(1000), // 10 %
      );
      expect(r.subtotal.cents, 30000);
      expect(r.itemDiscountTotal.cents, 1000);
      expect(r.overallDiscount.cents, 2900);
      expect(r.totalDiscount.cents, 3900);
      // Sum of shares
      final shareSum = r.lines
          .map((l) => l.shareOfOverallDiscount.cents)
          .fold<int>(0, (a, b) => a + b);
      expect(shareSum, 2900);
      // No tax → total == subtotal − totalDiscount
      expect(r.total.cents, 30000 - 3900);
    });
  });

  group('InvoicePricingEngine — invariants', () {
    test('subtotal − totalDiscount + tax == total (always)', () {
      final cases = <Map<String, dynamic>>[
        {
          'lines': [
            _line(
              unitPriceCents: 10000,
              qty: 2,
              isTaxable: true,
              productTaxRateBps: 1500,
            ),
            _line(
              unitPriceCents: 5000,
              qty: 3,
              isTaxable: true,
              productTaxRateBps: 1500,
            ),
          ],
          'overall': Discount.percent(500),
        },
        {
          'lines': [
            _line(
              unitPriceCents: 12345,
              qty: 7,
              isTaxable: true,
              productTaxRateBps: 100,
            ),
          ],
          'overall': Discount.fixed(Money.fromCents(1234)),
        },
        {
          'lines': [_line(unitPriceCents: 99, qty: 100)],
          'overall': Discount.percent(50),
        },
      ];
      for (final c in cases) {
        final r = _compute(
          lines: c['lines'] as List<LineItemPricingInput>,
          overall: c['overall'] as Discount,
        );
        expect(
          (r.subtotal - r.totalDiscount + r.tax).cents,
          r.total.cents,
          reason: 'invariant broken for case $c',
        );
      }
    });

    test('Σ line.total == invoice.total (no escaped cents)', () {
      final r = _compute(
        lines: [
          _line(
            unitPriceCents: 333,
            qty: 5,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
          _line(
            unitPriceCents: 777,
            qty: 3,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
          _line(
            unitPriceCents: 1111,
            qty: 1,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
        ],
        overall: Discount.percent(123),
      );
      final lineSum = r.lines.fold<int>(0, (s, l) => s + l.total.cents);
      expect(lineSum, r.total.cents);
    });

    test(
      'quantity change reflects on overall percent (closes bug #2 invoice-side)',
      () {
        // Invoice with 1 line, 1 unit @100, overall 1 % → discount 1.
        final r1 = _compute(
          lines: [_line(unitPriceCents: 10000, qty: 1)],
          overall: Discount.percent(100),
        );
        // Same line but qty=4 — overall percent must rescale.
        final r4 = _compute(
          lines: [_line(unitPriceCents: 10000, qty: 4)],
          overall: Discount.percent(100),
        );
        expect(r4.overallDiscount.cents, r1.overallDiscount.cents * 4);
      },
    );
  });

  group('InvoicePricingEngine — tax disabled', () {
    test('enableTax=false zeros all tax', () {
      final r = _compute(
        lines: [
          _line(
            unitPriceCents: 10000,
            qty: 1,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
        ],
        overall: Discount.percent(100),
        enableTax: false,
      );
      expect(r.tax, Money.zero);
      expect(r.total.cents, r.subtotal.cents - r.totalDiscount.cents);
    });
  });

  group('InvoicePricingEngine — tax-inclusive pricing', () {
    test('115.00 inclusive at 15% stays 115.00 and exposes 15.00 tax', () {
      final r = _compute(
        lines: [
          _line(
            unitPriceCents: 11500,
            qty: 1,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
        ],
        taxInclusive: true,
      );

      expect(r.subtotal.cents, 11500);
      expect(r.tax.cents, 1500);
      expect(r.total.cents, 11500);
      expect(r.lines.single.total.cents, 11500);
    });

    test('discount reduces inclusive gross and tax is re-extracted', () {
      final r = _compute(
        lines: [
          _line(
            unitPriceCents: 11500,
            qty: 1,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
        ],
        overall: Discount.percent(1000),
        taxInclusive: true,
      );

      expect(r.overallDiscount.cents, 1150);
      expect(r.tax.cents, 1350);
      expect(r.total.cents, 10350);
      expect(r.lines.single.total.cents, 10350);
    });

    test('non-taxable line remains exempt even with a global default', () {
      final r = _compute(
        lines: [_line(unitPriceCents: 10000, qty: 1, isTaxable: false)],
        defaultTaxRateBps: 1400,
        taxInclusive: true,
      );

      expect(r.tax, Money.zero);
      expect(r.lines.single.effectiveTaxRateBps, 0);
      expect(r.total.cents, 10000);
    });
  });
}
