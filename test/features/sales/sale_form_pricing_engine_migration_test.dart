// ════════════════════════════════════════════════════════════════════════════
// PHASE 4 — SALE FORM · ENGINE-MIGRATION REGRESSION TESTS
// ════════════════════════════════════════════════════════════════════════════
//
// Purpose
// -------
// Pin the invariants introduced by migrating `sale_form_bloc.dart` from
// hand-rolled cents math to `InvoicePricingEngine` / `LineItemPricingEngine`
// as the single source of truth, with an explicit Pricing / Tender split:
//
//   * Pricing layer  → engine-owned: subtotal, item-discount, overall-
//                      discount, tax, totalBeforeLoyalty.
//   * Tender layer   → bloc-owned:   loyaltyDiscount, totalCents (post-
//                      loyalty), paid, remaining, change.
//
// References
//   * ADR `docs/adr/0001-pricing-engines-as-sot.md`
//   * ADR `docs/adr/0002-engine-readiness-audit.md` §2, §4 (Q2 loyalty).
//   * Phase-0 goldens — `test/golden/pricing/sale_form_pricing_golden_test.dart`.
//   * Q-log (`progress.txt`) — Q1, Q3, Q5.
//
// No bloc wiring, no repositories, no database. Pure state-getter assertions.
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/pricing/invoice_pricing_engine.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_form_bloc.dart';

Product _product({
  required int id,
  required String name,
  required bool isTaxable,
  required int salesTaxRateBps,
}) =>
    Product(
      id: id,
      name: name,
      costCents: Decimal.zero,
      priceCents: Decimal.zero,
      stockQuantity: 1000,
      minQuantity: 0,
      hasVariants: false,
      isTaxable: isTaxable,
      purchaseTaxRateBps: 0,
      salesTaxRateBps: salesTaxRateBps,
      isActive: true,
      trackInventory: true,
    );

SaleLineItem _line({
  required String tempId,
  required Product product,
  required int qty,
  required int unitPriceCents,
  int discountCents = 0,
}) =>
    SaleLineItem(
      tempId: tempId,
      product: product,
      quantity: qty,
      unitPriceCents: Decimal.fromInt(unitPriceCents),
      discountCents: Decimal.fromInt(discountCents),
    );

SaleFormState _state({
  required List<SaleLineItem> items,
  SaleDiscountMode discountMode = SaleDiscountMode.perItem,
  int invoiceDiscountCents = 0,
  bool enableTaxCalculations = true,
  int defaultSalesTaxRateBps = 0,
  bool taxInclusivePricing = false,
  int paidAmountCents = 0,
  int loyaltyDiscountCents = 0,
}) =>
    SaleFormState(
      currencyId: 1,
      saleDate: DateTime(2026, 1, 15),
      items: items,
      discountMode: discountMode,
      invoiceDiscountCents: Decimal.fromInt(invoiceDiscountCents),
      enableTaxCalculations: enableTaxCalculations,
      defaultSalesTaxRateBps: defaultSalesTaxRateBps,
      taxInclusivePricing: taxInclusivePricing,
      paidAmountCents: Decimal.fromInt(paidAmountCents),
      loyaltyDiscountCents: loyaltyDiscountCents,
    );

void main() {
  final taxable10 = _product(
      id: 1, name: 'Taxable 10%', isTaxable: true, salesTaxRateBps: 1000);
  final taxable15 = _product(
      id: 2, name: 'Taxable 15%', isTaxable: true, salesTaxRateBps: 1500);
  final nonTaxable = _product(
      id: 3, name: 'Non-taxable', isTaxable: false, salesTaxRateBps: 0);

  group('Phase 4 — engine SoT migration (sale form)', () {
    // ── Q3 — discount-mode exclusivity ────────────────────────────────────
    test(
        'Q3a — perItem mode: engine reports itemDiscount = Σ line.discount, '
        'overall = 0', () {
      final s = _state(items: [
        _line(
            tempId: '1',
            product: taxable10,
            qty: 1,
            unitPriceCents: 10000,
            discountCents: 1000),
        _line(
            tempId: '2',
            product: taxable10,
            qty: 1,
            unitPriceCents: 5000,
            discountCents: 500),
      ]);
      expect(s.pricing.itemDiscountTotal.cents, 1500);
      expect(s.pricing.overallDiscount.cents, 0);
      expect(s.pricing.totalDiscount.cents, 1500);
    });

    test(
        'Q3b — invoice mode: per-line discounts are suppressed at the engine, '
        'overall = invoice value', () {
      final s = _state(
        items: [
          _line(
              tempId: '1',
              product: taxable10,
              qty: 1,
              unitPriceCents: 10000,
              // Stale per-line discount must be ignored by the engine.
              discountCents: 1000),
          _line(
              tempId: '2',
              product: taxable10,
              qty: 1,
              unitPriceCents: 5000,
              discountCents: 500),
        ],
        discountMode: SaleDiscountMode.invoice,
        invoiceDiscountCents: 750,
      );
      expect(s.pricing.itemDiscountTotal.cents, 0);
      expect(s.pricing.overallDiscount.cents, 750);
      expect(s.pricing.totalDiscount.cents, 750);
      // UI surface still shows the stale user-entered per-line values.
      expect(s.itemDiscountCents, Decimal.fromInt(1500));
      // The persisted figure reflects the engine (single arithmetic path).
      expect(s.totalDiscountCents, Decimal.fromInt(750));
    });

    test(
        'Q3c — invoice-mode fixed discount > subtotal: engine clamps to '
        'subtotal (IFRS-correct; matches Phase-3 purchase semantics)', () {
      // Legacy returned 99999 unclamped for the fixed path; new engine path
      // clamps to subtotal. This is the same ADR-approved behavioural
      // change made in Phase 3 for purchases.
      final s = _state(
        items: [
          _line(
              tempId: '1', product: nonTaxable, qty: 1, unitPriceCents: 10000),
        ],
        discountMode: SaleDiscountMode.invoice,
        invoiceDiscountCents: 99999,
        enableTaxCalculations: false,
      );
      expect(s.effectiveInvoiceDiscountCents, Decimal.fromInt(10000));
      expect(s.totalDiscountCents, Decimal.fromInt(10000));
      expect(s.totalBeforeLoyaltyCents, Decimal.zero);
      expect(s.totalCents, Decimal.zero);
    });

    // ── Q5 — engine vs reconstruction invariant ───────────────────────────
    test(
        'Q5a — totalBeforeLoyalty == subtotal − totalDiscount + tax '
        '(clamped ≥ 0)', () {
      final scenarios = <SaleFormState>[
        _state(items: const []),
        _state(items: [
          _line(
              tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
        ]),
        _state(items: [
          _line(
              tempId: '1',
              product: taxable15,
              qty: 3,
              unitPriceCents: 2000,
              discountCents: 600),
          _line(
              tempId: '2', product: taxable10, qty: 1, unitPriceCents: 4000),
          _line(
              tempId: '3',
              product: nonTaxable,
              qty: 2,
              unitPriceCents: 1500,
              discountCents: 300),
        ]),
        _state(
          items: [
            _line(
                tempId: '1',
                product: taxable10,
                qty: 1,
                unitPriceCents: 10000),
            _line(
                tempId: '2',
                product: nonTaxable,
                qty: 1,
                unitPriceCents: 6000),
          ],
          discountMode: SaleDiscountMode.invoice,
          invoiceDiscountCents: 1600,
        ),
      ];
      for (final s in scenarios) {
        final reconstructed =
            s.subtotalCents - s.totalDiscountCents + s.taxCents;
        final expected =
            reconstructed < Decimal.zero ? Decimal.zero : reconstructed;
        expect(s.totalBeforeLoyaltyCents, expected,
            reason: 'totalBeforeLoyalty invariant violated for scenario: $s');
      }
    });

    test('Q5b — Σ engine.line.total == invoice.total exactly (no lost cents)',
        () {
      final s = _state(
        items: [
          _line(tempId: '1', product: taxable10, qty: 3, unitPriceCents: 3333),
          _line(tempId: '2', product: taxable15, qty: 7, unitPriceCents: 1234),
          _line(tempId: '3', product: nonTaxable, qty: 2, unitPriceCents: 999),
        ],
        discountMode: SaleDiscountMode.invoice,
        invoiceDiscountCents: 1000,
      );
      final summed =
          s.pricing.lines.fold<int>(0, (acc, l) => acc + l.total.cents);
      expect(summed, s.pricing.total.cents);
    });

    // ── ADR 0002 §4 Q2 — Loyalty stays in the tender layer ────────────────
    test(
        'Q2a — loyaltyDiscount does NOT reduce pricing.total '
        '(GAAP/IFRS-15: revenue is the gross transaction price)', () {
      final s = _state(
        items: [
          _line(
              tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
        ],
        loyaltyDiscountCents: 500,
      );
      // Pricing layer: untouched by loyalty.
      expect(s.pricing.subtotal.cents, 10000);
      expect(s.pricing.tax.cents, 1000);
      expect(s.pricing.total.cents, 11000);
      expect(s.totalBeforeLoyaltyCents, Decimal.fromInt(11000));
      // Tender layer: post-tax deduction.
      expect(s.totalCents, Decimal.fromInt(10500));
    });

    test(
        'Q2b — totalCents == max(0, pricing.total − loyaltyDiscountCents) '
        'across mixed scenarios', () {
      final scenarios = <SaleFormState>[
        _state(items: const [], loyaltyDiscountCents: 250),
        _state(
          items: [
            _line(
                tempId: '1',
                product: taxable10,
                qty: 1,
                unitPriceCents: 10000),
          ],
          loyaltyDiscountCents: 0,
        ),
        _state(
          items: [
            _line(
                tempId: '1',
                product: taxable10,
                qty: 1,
                unitPriceCents: 10000),
          ],
          // Loyalty exceeds pricing.total → clamp to zero.
          loyaltyDiscountCents: 99999,
        ),
        _state(
          items: [
            _line(
                tempId: '1',
                product: taxable10,
                qty: 2,
                unitPriceCents: 5000),
            _line(
                tempId: '2',
                product: nonTaxable,
                qty: 1,
                unitPriceCents: 3000),
          ],
          discountMode: SaleDiscountMode.invoice,
          invoiceDiscountCents: 1300,
          loyaltyDiscountCents: 250,
        ),
      ];
      for (final s in scenarios) {
        final reconstructed = s.pricing.total.decimalCents -
            Decimal.fromInt(s.loyaltyDiscountCents);
        final expected =
            reconstructed < Decimal.zero ? Decimal.zero : reconstructed;
        expect(s.totalCents, expected,
            reason: 'tender invariant violated for scenario: $s');
      }
    });

    // ── Tender invariants ────────────────────────────────────────────────
    test('remaining = max(0, totalCents − paid); change = max(0, paid − total)',
        () {
      final s = _state(
        items: [
          _line(
              tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
        ],
        loyaltyDiscountCents: 1000,
        paidAmountCents: 8000,
      );
      // pricing.total = 11000; loyalty = 1000 → totalCents = 10000.
      // paid 8000 → remaining 2000, change 0.
      expect(s.totalCents, Decimal.fromInt(10000));
      expect(s.remainingCents, Decimal.fromInt(2000));
      expect(s.changeCents, Decimal.zero);
    });

    test('overpayment routes through change, never to remaining', () {
      final s = _state(
        items: [
          _line(
              tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
        ],
        paidAmountCents: 15000,
      );
      // pricing.total = 11000; no loyalty → totalCents = 11000.
      expect(s.totalCents, Decimal.fromInt(11000));
      expect(s.remainingCents, Decimal.zero);
      expect(s.changeCents, Decimal.fromInt(4000));
    });

    // ── Engine consumer contract ─────────────────────────────────────────
    test('state exposes the same engine instance to bloc & UI (memoized)', () {
      final s = _state(items: [
        _line(tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
      ]);
      final a = s.pricing;
      final b = s.pricing;
      expect(identical(a, b), isTrue,
          reason: 'pricing must be memoized — computing it twice is a perf bug');
    });

    test('SaleLineItem.toPricingInput round-trips through the engine', () {
      final item = _line(
          tempId: '1',
          product: taxable15,
          qty: 4,
          unitPriceCents: 2500,
          discountCents: 500);
      // qty 4 × 2500 = 10000; disc 500 → net 9500; tax 15% = 1425;
      // total = 10925.
      expect(item.subtotalCents, Decimal.fromInt(10000));
      expect(item.netCents, Decimal.fromInt(9500));
      expect(item.taxCents, Decimal.fromInt(1425));
      expect(item.totalCents, Decimal.fromInt(10925));
    });

    test(
        'SaleLineItem.taxCentsWithSettings honors global toggle + '
        'default fallback (Q1 contract preserved)', () {
      final untaxedProduct = _product(
          id: 99,
          name: 'No rate',
          isTaxable: true,
          salesTaxRateBps: 0); // taxable but no own rate
      final item = _line(
          tempId: '1',
          product: untaxedProduct,
          qty: 1,
          unitPriceCents: 10000);
      expect(
        item.taxCentsWithSettings(
          enableTaxCalculations: false,
          defaultTaxRateBps: 1000,
        ),
        Decimal.zero,
      );
      expect(
        item.taxCentsWithSettings(
          enableTaxCalculations: true,
          defaultTaxRateBps: 1000,
        ),
        Decimal.fromInt(1000),
      );
    });

    // ── Type-system check — engine result is reachable from state ────────
    test('pricing is an InvoicePricingResult (engine SoT, not a duplicate)',
        () {
      final s = _state(items: [
        _line(tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
      ]);
      expect(s.pricing, isA<InvoicePricingResult>());
    });

    // ── Pricing / Tender separation guard ────────────────────────────────
    test(
        'loyalty redemption never alters subtotal / tax / pricing.total — '
        'pure tender-side adjustment', () {
      final base = _state(
        items: [
          _line(
              tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
        ],
        loyaltyDiscountCents: 0,
      );
      final withLoyalty = _state(
        items: [
          _line(
              tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
        ],
        loyaltyDiscountCents: 1234,
      );
      expect(base.subtotalCents, withLoyalty.subtotalCents);
      expect(base.taxCents, withLoyalty.taxCents);
      expect(base.totalDiscountCents, withLoyalty.totalDiscountCents);
      expect(base.totalBeforeLoyaltyCents, withLoyalty.totalBeforeLoyaltyCents);
      expect(base.pricing.total.cents, withLoyalty.pricing.total.cents);
      // Only the tender-layer totalCents differs.
      expect(base.totalCents, Decimal.fromInt(11000));
      expect(withLoyalty.totalCents, Decimal.fromInt(11000 - 1234));
    });
  });
}
