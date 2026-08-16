import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/services/tax_calculation_service.dart';

void main() {
  // ═══════════════════════════════════════════════════════════════════════════
  // resolveLineItemTaxRateBps
  // ═══════════════════════════════════════════════════════════════════════════

  group('resolveLineItemTaxRateBps', () {
    test('uses product rate when isTaxable and rate > 0', () {
      expect(
        TaxCalculationService.resolveLineItemTaxRateBps(
          isTaxable: true,
          productTaxRateBps: 1500,
          defaultTaxRateBps: 1000,
        ),
        1500,
      );
    });

    test('returns zero when product is explicitly non-taxable', () {
      expect(
        TaxCalculationService.resolveLineItemTaxRateBps(
          isTaxable: false,
          productTaxRateBps: 1500,
          defaultTaxRateBps: 1000,
        ),
        0,
      );
    });

    test('uses default rate when product taxable but rate is 0', () {
      expect(
        TaxCalculationService.resolveLineItemTaxRateBps(
          isTaxable: true,
          productTaxRateBps: 0,
          defaultTaxRateBps: 1000,
        ),
        1000,
      );
    });

    test('returns 0 when neither product nor default has rate', () {
      expect(
        TaxCalculationService.resolveLineItemTaxRateBps(
          isTaxable: false,
          productTaxRateBps: 0,
          defaultTaxRateBps: 0,
        ),
        0,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // calculateTax — core
  // ═══════════════════════════════════════════════════════════════════════════

  group('calculateTax', () {
    test('exclusive pricing: 10000 * 15% = 1500', () {
      final tax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(10000),
        taxRateBps: 1500,
        taxInclusivePricing: false,
      );
      expect(tax, Decimal.fromInt(1500));
    });

    test('exclusive pricing: 10000 * 10% = 1000', () {
      final tax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(10000),
        taxRateBps: 1000,
        taxInclusivePricing: false,
      );
      expect(tax, Decimal.fromInt(1000));
    });

    test('exclusive pricing: 333 * 15% = 50 (rounds from 49.95)', () {
      final tax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(333),
        taxRateBps: 1500,
        taxInclusivePricing: false,
      );
      expect(tax, Decimal.fromInt(50));
    });

    test('inclusive pricing: 11500 at 15% extracts 1500 tax', () {
      final tax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(11500),
        taxRateBps: 1500,
        taxInclusivePricing: true,
      );
      expect(tax, Decimal.fromInt(1500));
    });

    test('inclusive pricing: 11000 at 10% extracts 1000 tax', () {
      final tax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(11000),
        taxRateBps: 1000,
        taxInclusivePricing: true,
      );
      expect(tax, Decimal.fromInt(1000));
    });

    test('returns zero when amount is zero', () {
      final tax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.zero,
        taxRateBps: 1500,
        taxInclusivePricing: false,
      );
      expect(tax, Decimal.zero);
    });

    test('returns zero when rate is zero', () {
      final tax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(10000),
        taxRateBps: 0,
        taxInclusivePricing: false,
      );
      expect(tax, Decimal.zero);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // calculateTax — negative values (returns / reversals)
  // ═══════════════════════════════════════════════════════════════════════════

  group('calculateTax — negative symmetry', () {
    test('negative exclusive: tax(-10000) = -tax(10000)', () {
      final posTax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(10000),
        taxRateBps: 1500,
        taxInclusivePricing: false,
      );
      final negTax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(-10000),
        taxRateBps: 1500,
        taxInclusivePricing: false,
      );
      expect(negTax, -posTax);
      expect(negTax, Decimal.fromInt(-1500));
    });

    test('negative inclusive: tax(-11500) = -tax(11500)', () {
      final posTax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(11500),
        taxRateBps: 1500,
        taxInclusivePricing: true,
      );
      final negTax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(-11500),
        taxRateBps: 1500,
        taxInclusivePricing: true,
      );
      expect(negTax, -posTax);
      expect(negTax, Decimal.fromInt(-1500));
    });

    test(
      'negative with rounding maintains symmetry: tax(-333) = -tax(333)',
      () {
        final posTax = TaxCalculationService.calculateTax(
          taxableAmountCents: Decimal.fromInt(333),
          taxRateBps: 1500,
          taxInclusivePricing: false,
        );
        final negTax = TaxCalculationService.calculateTax(
          taxableAmountCents: Decimal.fromInt(-333),
          taxRateBps: 1500,
          taxInclusivePricing: false,
        );
        expect(negTax, -posTax);
      },
    );

    test('negative amount + zero rate = zero', () {
      final tax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(-5000),
        taxRateBps: 0,
        taxInclusivePricing: false,
      );
      expect(tax, Decimal.zero);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // calculateTax — rounding modes
  // ═══════════════════════════════════════════════════════════════════════════

  group('calculateTax — rounding modes', () {
    test('halfUp is the default', () {
      // 333 * 15% = 49.95 → should round to 50 (half-up)
      final tax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(333),
        taxRateBps: 1500,
        taxInclusivePricing: false,
      );
      expect(tax, Decimal.fromInt(50));
    });

    test('explicit halfUp matches default', () {
      final taxDefault = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(333),
        taxRateBps: 1500,
        taxInclusivePricing: false,
      );
      final taxExplicit = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(333),
        taxRateBps: 1500,
        taxInclusivePricing: false,
        roundingMode: TaxRoundingMode.halfUp,
      );
      expect(taxExplicit, taxDefault);
    });

    test('bankers rounding: exact half rounds to even', () {
      // 50 * 5% = 2.5 → bankers rounds to 2 (even), halfUp rounds to 3
      final taxBankers = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(50),
        taxRateBps: 500,
        taxInclusivePricing: false,
        roundingMode: TaxRoundingMode.bankers,
      );
      final taxHalfUp = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(50),
        taxRateBps: 500,
        taxInclusivePricing: false,
        roundingMode: TaxRoundingMode.halfUp,
      );
      // 50 * 500 / 10000 = 2.5
      // Bankers: floor=2 (even) → stays 2
      // HalfUp: 2.5 → 3
      expect(taxBankers, Decimal.fromInt(2));
      expect(taxHalfUp, Decimal.fromInt(3));
    });

    test('bankers rounding: non-half values round normally', () {
      // 10000 * 15% = 1500.0 → no rounding needed
      final tax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(10000),
        taxRateBps: 1500,
        taxInclusivePricing: false,
        roundingMode: TaxRoundingMode.bankers,
      );
      expect(tax, Decimal.fromInt(1500));
    });

    test('bankers rounding: half rounds to even (odd floor)', () {
      // 150 * 5% = 7.5 → bankers: floor=7 (odd) → rounds to 8
      final tax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(150),
        taxRateBps: 500,
        taxInclusivePricing: false,
        roundingMode: TaxRoundingMode.bankers,
      );
      expect(tax, Decimal.fromInt(8));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // calculateTax — validation
  // ═══════════════════════════════════════════════════════════════════════════

  group('calculateTax — validation', () {
    test('throws on negative tax rate', () {
      expect(
        () => TaxCalculationService.calculateTax(
          taxableAmountCents: Decimal.fromInt(10000),
          taxRateBps: -100,
          taxInclusivePricing: false,
        ),
        throwsA(isA<TaxValidationException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // calculateLineItemTax
  // ═══════════════════════════════════════════════════════════════════════════

  group('calculateLineItemTax', () {
    test('uses product tax rate when available', () {
      final tax = TaxCalculationService.calculateLineItemTax(
        netCents: Decimal.fromInt(10000),
        enableTaxCalculations: true,
        isTaxable: true,
        productTaxRateBps: 1500, // 15%
        defaultTaxRateBps: 1000, // 10% — should be ignored
        taxInclusivePricing: false,
      );
      expect(tax, Decimal.fromInt(1500));
    });

    test('non-taxable line never inherits the default rate', () {
      final tax = TaxCalculationService.calculateLineItemTax(
        netCents: Decimal.fromInt(10000),
        enableTaxCalculations: true,
        isTaxable: false,
        productTaxRateBps: 0,
        defaultTaxRateBps: 1000, // 10%
        taxInclusivePricing: false,
      );
      expect(tax, Decimal.zero);
    });

    test('returns zero when tax disabled', () {
      final tax = TaxCalculationService.calculateLineItemTax(
        netCents: Decimal.fromInt(10000),
        enableTaxCalculations: false,
        isTaxable: true,
        productTaxRateBps: 1500,
        defaultTaxRateBps: 1000,
        taxInclusivePricing: false,
      );
      expect(tax, Decimal.zero);
    });

    test('returns zero for zero net amount', () {
      final tax = TaxCalculationService.calculateLineItemTax(
        netCents: Decimal.zero,
        enableTaxCalculations: true,
        isTaxable: true,
        productTaxRateBps: 1500,
        defaultTaxRateBps: 1000,
        taxInclusivePricing: false,
      );
      expect(tax, Decimal.zero);
    });

    test('supports inclusive pricing', () {
      final tax = TaxCalculationService.calculateLineItemTax(
        netCents: Decimal.fromInt(11500),
        enableTaxCalculations: true,
        isTaxable: true,
        productTaxRateBps: 1500,
        defaultTaxRateBps: 0,
        taxInclusivePricing: true,
      );
      expect(tax, Decimal.fromInt(1500));
    });

    test('negative netCents returns negative tax (returns)', () {
      final tax = TaxCalculationService.calculateLineItemTax(
        netCents: Decimal.fromInt(-10000),
        enableTaxCalculations: true,
        isTaxable: true,
        productTaxRateBps: 1500,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      );
      expect(tax, Decimal.fromInt(-1500));
    });

    test('passes rounding mode through', () {
      // 50 * 5% = 2.5 → bankers=2, halfUp=3
      final taxBankers = TaxCalculationService.calculateLineItemTax(
        netCents: Decimal.fromInt(50),
        enableTaxCalculations: true,
        isTaxable: true,
        productTaxRateBps: 500,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
        roundingMode: TaxRoundingMode.bankers,
      );
      expect(taxBankers, Decimal.fromInt(2));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // calculateInvoiceTax
  // ═══════════════════════════════════════════════════════════════════════════

  group('calculateInvoiceTax', () {
    test('empty items returns zero breakdown', () {
      final result = TaxCalculationService.calculateInvoiceTax(
        items: [],
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 1000,
        taxInclusivePricing: false,
      );
      expect(result.subtotalCents, Decimal.zero);
      expect(result.totalDiscountCents, Decimal.zero);
      expect(result.totalTaxCents, Decimal.zero);
      expect(result.totalCents, Decimal.zero);
      expect(result.lineItems, isEmpty);
    });

    test('per-item discount mode: uses each item discount', () {
      final result = TaxCalculationService.calculateInvoiceTax(
        items: [
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(10000),
            itemDiscountCents: Decimal.fromInt(1000),
            isTaxable: true,
            productTaxRateBps: 1500, // 15%
          ),
        ],
        invoiceDiscountCents: Decimal.zero, // per-item mode
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      );

      expect(result.subtotalCents, Decimal.fromInt(10000));
      expect(result.totalDiscountCents, Decimal.fromInt(1000));
      // Tax on (10000 - 1000) = 9000 * 15% = 1350
      expect(result.totalTaxCents, Decimal.fromInt(1350));
      // Total = 10000 - 1000 + 1350 = 10350
      expect(result.totalCents, Decimal.fromInt(10350));

      final line = result.lineItems[0];
      expect(line.taxRateBps, 1500);
      expect(line.taxableAmountCents, Decimal.fromInt(9000));
    });

    test('invoice-level discount: prorated proportionally', () {
      final result = TaxCalculationService.calculateInvoiceTax(
        items: [
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(20000), // 2/3 weight
            itemDiscountCents: Decimal.zero,
            isTaxable: true,
            productTaxRateBps: 1500, // 15%
          ),
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(10000), // 1/3 weight
            itemDiscountCents: Decimal.zero,
            isTaxable: true,
            productTaxRateBps: 1500, // 15%
          ),
        ],
        invoiceDiscountCents: Decimal.fromInt(3000), // 3000 total discount
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      );

      // Item 1: discount = 3000 * 20000/30000 = 2000
      // Item 2: discount = 3000 * 10000/30000 = 1000
      expect(result.lineItems[0].discountCents, Decimal.fromInt(2000));
      expect(result.lineItems[1].discountCents, Decimal.fromInt(1000));

      // Item 1: tax = (20000 - 2000) * 15% = 2700
      // Item 2: tax = (10000 - 1000) * 15% = 1350
      expect(result.lineItems[0].taxCents, Decimal.fromInt(2700));
      expect(result.lineItems[1].taxCents, Decimal.fromInt(1350));

      expect(result.totalDiscountCents, Decimal.fromInt(3000));
      expect(result.totalTaxCents, Decimal.fromInt(4050));
      // Total = 30000 - 3000 + 4050 = 31050
      expect(result.totalCents, Decimal.fromInt(31050));
    });

    test('mixed taxable and non-taxable items', () {
      final result = TaxCalculationService.calculateInvoiceTax(
        items: [
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(10000),
            itemDiscountCents: Decimal.zero,
            isTaxable: true,
            productTaxRateBps: 1500, // 15%
          ),
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(5000),
            itemDiscountCents: Decimal.zero,
            isTaxable: false,
            productTaxRateBps: 0,
          ),
        ],
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0, // No default rate
        taxInclusivePricing: false,
      );

      // Only first item has tax: 10000 * 15% = 1500
      expect(result.lineItems[0].taxCents, Decimal.fromInt(1500));
      expect(result.lineItems[1].taxCents, Decimal.zero);
      expect(result.totalTaxCents, Decimal.fromInt(1500));
    });

    test('non-taxable items do not use the default rate', () {
      final result = TaxCalculationService.calculateInvoiceTax(
        items: [
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(10000),
            itemDiscountCents: Decimal.zero,
            isTaxable: false,
            productTaxRateBps: 0,
          ),
        ],
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 1000, // 10% default
        taxInclusivePricing: false,
      );

      expect(result.totalTaxCents, Decimal.zero);
      expect(result.lineItems[0].taxRateBps, 0);
    });

    test('tax calculations disabled returns zero tax', () {
      final result = TaxCalculationService.calculateInvoiceTax(
        items: [
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(10000),
            itemDiscountCents: Decimal.zero,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
        ],
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: false,
        defaultTaxRateBps: 1000,
        taxInclusivePricing: false,
      );

      expect(result.totalTaxCents, Decimal.zero);
      expect(result.lineItems[0].taxCents, Decimal.zero);
      expect(result.lineItems[0].taxRateBps, 0);
    });

    test('inclusive pricing: extracts tax from price', () {
      final result = TaxCalculationService.calculateInvoiceTax(
        items: [
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(11500), // includes 15% tax
            itemDiscountCents: Decimal.zero,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
        ],
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: true,
      );

      expect(result.totalTaxCents, Decimal.fromInt(1500));
      expect(
        result.totalCents,
        Decimal.fromInt(11500),
        reason: 'inclusive tax is extracted, not added a second time',
      );
      expect(result.lineItems.single.totalCents, Decimal.fromInt(11500));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // calculateInvoiceTax — validation
  // ═══════════════════════════════════════════════════════════════════════════

  group('calculateInvoiceTax — validation', () {
    test('throws on negative default tax rate', () {
      expect(
        () => TaxCalculationService.calculateInvoiceTax(
          items: [
            TaxableLineItem(
              subtotalCents: Decimal.fromInt(10000),
              itemDiscountCents: Decimal.zero,
              isTaxable: true,
              productTaxRateBps: 0,
            ),
          ],
          invoiceDiscountCents: Decimal.zero,
          enableTaxCalculations: true,
          defaultTaxRateBps: -500,
          taxInclusivePricing: false,
        ),
        throwsA(isA<TaxValidationException>()),
      );
    });

    test('throws on negative product tax rate', () {
      expect(
        () => TaxCalculationService.calculateInvoiceTax(
          items: [
            TaxableLineItem(
              subtotalCents: Decimal.fromInt(10000),
              itemDiscountCents: Decimal.zero,
              isTaxable: true,
              productTaxRateBps: -200,
            ),
          ],
          invoiceDiscountCents: Decimal.zero,
          enableTaxCalculations: true,
          defaultTaxRateBps: 1000,
          taxInclusivePricing: false,
        ),
        throwsA(isA<TaxValidationException>()),
      );
    });

    test('throws when item discount exceeds subtotal', () {
      expect(
        () => TaxCalculationService.calculateInvoiceTax(
          items: [
            TaxableLineItem(
              subtotalCents: Decimal.fromInt(1000),
              itemDiscountCents: Decimal.fromInt(2000), // > subtotal
              isTaxable: true,
              productTaxRateBps: 1500,
            ),
          ],
          invoiceDiscountCents: Decimal.zero,
          enableTaxCalculations: true,
          defaultTaxRateBps: 0,
          taxInclusivePricing: false,
        ),
        throwsA(isA<TaxValidationException>()),
      );
    });

    test('throws when invoice discount exceeds subtotal', () {
      expect(
        () => TaxCalculationService.calculateInvoiceTax(
          items: [
            TaxableLineItem(
              subtotalCents: Decimal.fromInt(5000),
              itemDiscountCents: Decimal.zero,
              isTaxable: true,
              productTaxRateBps: 1500,
            ),
          ],
          invoiceDiscountCents: Decimal.fromInt(6000), // > subtotal
          enableTaxCalculations: true,
          defaultTaxRateBps: 0,
          taxInclusivePricing: false,
        ),
        throwsA(isA<TaxValidationException>()),
      );
    });

    test('throws on negative discount', () {
      expect(
        () => TaxCalculationService.calculateInvoiceTax(
          items: [
            TaxableLineItem(
              subtotalCents: Decimal.fromInt(10000),
              itemDiscountCents: Decimal.fromInt(-500),
              isTaxable: true,
              productTaxRateBps: 1500,
            ),
          ],
          invoiceDiscountCents: Decimal.zero,
          enableTaxCalculations: true,
          defaultTaxRateBps: 0,
          taxInclusivePricing: false,
        ),
        throwsA(isA<TaxValidationException>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // calculateInvoiceTaxWithAudit
  // ═══════════════════════════════════════════════════════════════════════════

  group('calculateInvoiceTaxWithAudit', () {
    test('audit trail matches standard result', () {
      final items = [
        TaxableLineItem(
          subtotalCents: Decimal.fromInt(10000),
          itemDiscountCents: Decimal.fromInt(500),
          isTaxable: true,
          productTaxRateBps: 1500,
        ),
      ];

      final standard = TaxCalculationService.calculateInvoiceTax(
        items: items,
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      );

      final audit = TaxCalculationService.calculateInvoiceTaxWithAudit(
        items: items,
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      );

      expect(audit.breakdown.totalTaxCents, standard.totalTaxCents);
      expect(audit.breakdown.totalCents, standard.totalCents);
      expect(audit.breakdown.lineItems.length, standard.lineItems.length);
    });

    test('audit trail contains correct line details', () {
      final audit = TaxCalculationService.calculateInvoiceTaxWithAudit(
        items: [
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(10000),
            itemDiscountCents: Decimal.fromInt(1000),
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
        ],
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      );

      expect(audit.lineDetails.length, 1);
      final detail = audit.lineDetails[0];
      expect(detail.index, 0);
      expect(detail.inputSubtotalCents, Decimal.fromInt(10000));
      expect(detail.effectiveDiscountCents, Decimal.fromInt(1000));
      expect(detail.taxableAmountCents, Decimal.fromInt(9000));
      expect(detail.resolvedTaxRateBps, 1500);
      expect(detail.finalTaxCents, Decimal.fromInt(1350));
      expect(detail.negativeSymmetryApplied, false);
    });

    test('audit trail records rounding mode', () {
      final auditHalfUp = TaxCalculationService.calculateInvoiceTaxWithAudit(
        items: [
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(333),
            itemDiscountCents: Decimal.zero,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
        ],
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
        roundingMode: TaxRoundingMode.halfUp,
      );
      expect(auditHalfUp.roundingMode, TaxRoundingMode.halfUp);

      final auditBankers = TaxCalculationService.calculateInvoiceTaxWithAudit(
        items: [
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(333),
            itemDiscountCents: Decimal.zero,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
        ],
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
        roundingMode: TaxRoundingMode.bankers,
      );
      expect(auditBankers.roundingMode, TaxRoundingMode.bankers);
    });

    test('audit trail has calculatedAt timestamp', () {
      final before = DateTime.now().toUtc();
      final audit = TaxCalculationService.calculateInvoiceTaxWithAudit(
        items: [
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(1000),
            itemDiscountCents: Decimal.zero,
            isTaxable: true,
            productTaxRateBps: 1000,
          ),
        ],
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      );
      final after = DateTime.now().toUtc();

      expect(
        audit.calculatedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        true,
      );
      expect(
        audit.calculatedAt.isBefore(after.add(const Duration(seconds: 1))),
        true,
      );
    });

    test('audit trail toString() produces readable output', () {
      final audit = TaxCalculationService.calculateInvoiceTaxWithAudit(
        items: [
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(10000),
            itemDiscountCents: Decimal.zero,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
        ],
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      );

      final output = audit.toString();
      expect(output, contains('TAX AUDIT TRAIL'));
      expect(output, contains('Rounding: halfUp'));
      expect(output, contains('Line items (1)'));
    });

    test('audit trail reports negative symmetry when used', () {
      // Use negative subtotal to simulate a return scenario
      final auditReturn = TaxCalculationService.calculateInvoiceTaxWithAudit(
        items: [
          TaxableLineItem(
            subtotalCents: Decimal.fromInt(-5000), // return
            itemDiscountCents: Decimal.zero,
            isTaxable: true,
            productTaxRateBps: 1500,
          ),
        ],
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      );

      expect(auditReturn.anyNegativeSymmetryApplied, true);
      expect(auditReturn.lineDetails[0].negativeSymmetryApplied, true);
      expect(auditReturn.breakdown.totalTaxCents, Decimal.fromInt(-750));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // distributeProportionally
  // ═══════════════════════════════════════════════════════════════════════════

  group('distributeProportionally', () {
    test('distributes evenly when possible', () {
      final result = TaxCalculationService.distributeProportionally(300, [
        100,
        100,
        100,
      ], 300);
      expect(result, [100, 100, 100]);
    });

    test('handles uneven distribution with largest remainder', () {
      final result = TaxCalculationService.distributeProportionally(10, [
        1,
        1,
        1,
      ], 3);
      // 10/3 = 3.33 each, floor = 3 each = 9, remainder 1
      // Distribute 1 to first item with largest remainder
      expect(result.reduce((a, b) => a + b), 10);
    });

    test('sums exactly to total', () {
      final result = TaxCalculationService.distributeProportionally(3000, [
        20000,
        10000,
      ], 30000);
      expect(result.reduce((a, b) => a + b), 3000);
      expect(result[0], 2000); // 3000 * 20000/30000 = 2000
      expect(result[1], 1000); // 3000 * 10000/30000 = 1000
    });

    test('handles zero total', () {
      final result = TaxCalculationService.distributeProportionally(0, [
        100,
        200,
      ], 300);
      expect(result, [0, 0]);
    });

    test('handles empty weights', () {
      final result = TaxCalculationService.distributeProportionally(100, [], 0);
      expect(result, isEmpty);
    });

    test('handles zero weight sum', () {
      final result = TaxCalculationService.distributeProportionally(100, [
        0,
        0,
      ], 0);
      expect(result, [0, 0]);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // Consistency: same input → same output
  // ═══════════════════════════════════════════════════════════════════════════

  group('consistency guarantee', () {
    test('same input always produces same output', () {
      final items = [
        TaxableLineItem(
          subtotalCents: Decimal.fromInt(15000),
          itemDiscountCents: Decimal.fromInt(500),
          isTaxable: true,
          productTaxRateBps: 1500,
        ),
        TaxableLineItem(
          subtotalCents: Decimal.fromInt(8000),
          itemDiscountCents: Decimal.fromInt(200),
          isTaxable: true,
          productTaxRateBps: 1000,
        ),
      ];

      final result1 = TaxCalculationService.calculateInvoiceTax(
        items: items,
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      );

      final result2 = TaxCalculationService.calculateInvoiceTax(
        items: items,
        invoiceDiscountCents: Decimal.zero,
        enableTaxCalculations: true,
        defaultTaxRateBps: 0,
        taxInclusivePricing: false,
      );

      expect(result1.totalTaxCents, result2.totalTaxCents);
      expect(result1.totalCents, result2.totalCents);
      for (int i = 0; i < items.length; i++) {
        expect(result1.lineItems[i].taxCents, result2.lineItems[i].taxCents);
      }
    });

    test('positive and negative cancel out exactly', () {
      // Sale: 10000 at 15% → tax = 1500
      final saleTax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(10000),
        taxRateBps: 1500,
        taxInclusivePricing: false,
      );
      // Full return: -10000 at 15% → tax = -1500
      final returnTax = TaxCalculationService.calculateTax(
        taxableAmountCents: Decimal.fromInt(-10000),
        taxRateBps: 1500,
        taxInclusivePricing: false,
      );
      // Net tax should be exactly zero
      expect(saleTax + returnTax, Decimal.zero);
    });
  });
}
