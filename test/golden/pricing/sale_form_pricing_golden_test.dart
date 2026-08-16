// ════════════════════════════════════════════════════════════════════════════
// PHASE 0 — SALE FORM PRICING · GOLDEN CHARACTERISATION TESTS
// ════════════════════════════════════════════════════════════════════════════
//
// Purpose
// -------
// Pin the CURRENT outputs of SaleFormState / SaleLineItem getters across 12
// canonical scenarios. These tests form the Phase-0 safety net for the
// scattered-calculation-logic migration (see
// docs/adr/0001-pricing-engines-as-sot.md). The 12 scenarios cover pricing,
// tendering, and loyalty redemption — the three concerns that currently
// coexist in the sale bloc and that the Phase-4 migration will separate
// into _PricingSnapshot (engine-owned) vs _TenderSnapshot (bloc-owned).
//
// NO bloc wiring. NO repositories, NO DAOs. Pure state-getter assertions.
//
// Coverage
// --------
//   S01  empty invoice
//   S02  single taxable line, no discount, tax-exclusive
//   S03  per-item discount, taxable
//   S04  invoice-level fixed discount, taxable (mixed lines)
//   S05  multi-line, mixed tax rates, mixed per-item discounts
//   S06  tax rounding at the .5 boundary (halfUp)
//   S07  loyalty redemption after tax
//   S08  multi-payment (paid) → remaining
//   S09  multi-payment overpay → change
//   S10  discount == subtotal → net clamps to 0, totals zero
//   S11  returns as negative lines (sanity: today we don't support negative
//        qty in the form; this test pins the assert-free zero-qty path)
//   S12  invariants across random mixed scenarios
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/sales/presentation/bloc/sale_form_bloc.dart';

Product _product({
  required int id,
  required String name,
  required bool isTaxable,
  required int salesTaxRateBps,
}) => Product(
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
}) => SaleLineItem(
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
}) => SaleFormState(
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

/// Assert a sale-form-state snapshot. If [remaining]/[change] are omitted,
/// they default to the natural values derived from [total] and the state's
/// `paidAmountCents`.
void _expectState(
  SaleFormState state, {
  required int subtotal,
  required int itemDiscount,
  required int totalDiscount,
  required int tax,
  required int totalBeforeLoyalty,
  required int total,
  int? remaining,
  int? change,
}) {
  expect(state.subtotalCents, Decimal.fromInt(subtotal), reason: 'subtotal');
  expect(
    state.itemDiscountCents,
    Decimal.fromInt(itemDiscount),
    reason: 'itemDiscount',
  );
  expect(
    state.totalDiscountCents,
    Decimal.fromInt(totalDiscount),
    reason: 'totalDiscount',
  );
  expect(state.taxCents, Decimal.fromInt(tax), reason: 'tax');
  expect(
    state.totalBeforeLoyaltyCents,
    Decimal.fromInt(totalBeforeLoyalty),
    reason: 'totalBeforeLoyalty',
  );
  expect(state.totalCents, Decimal.fromInt(total), reason: 'total');

  final paid = state.paidAmountCents.toBigInt().toInt();
  final expectedRemaining = remaining ?? (total - paid).clamp(0, total);
  final expectedChange = change ?? (paid > total ? paid - total : 0);
  expect(
    state.remainingCents,
    Decimal.fromInt(expectedRemaining),
    reason: 'remaining',
  );
  expect(state.changeCents, Decimal.fromInt(expectedChange), reason: 'change');
}

void main() {
  final taxable10 = _product(
    id: 1,
    name: 'Taxable 10%',
    isTaxable: true,
    salesTaxRateBps: 1000,
  );
  final taxable15 = _product(
    id: 2,
    name: 'Taxable 15%',
    isTaxable: true,
    salesTaxRateBps: 1500,
  );
  final taxable5 = _product(
    id: 3,
    name: 'Taxable 5%',
    isTaxable: true,
    salesTaxRateBps: 500,
  );
  final nonTaxable = _product(
    id: 4,
    name: 'Non-taxable',
    isTaxable: false,
    salesTaxRateBps: 0,
  );

  group('Sale form — Phase 0 golden characterisation', () {
    // ── S01 ────────────────────────────────────────────────────────────
    test('S01 empty invoice → all zeros', () {
      final s = _state(items: const []);
      _expectState(
        s,
        subtotal: 0,
        itemDiscount: 0,
        totalDiscount: 0,
        tax: 0,
        totalBeforeLoyalty: 0,
        total: 0,
      );
      expect(s.totalQuantity, 0);
    });

    // ── S02 ────────────────────────────────────────────────────────────
    test('S02 single taxable line, no discount, tax-exclusive', () {
      // qty=1 × 10000 = 10000; tax 10% = 1000; total = 11000.
      final s = _state(
        items: [
          _line(tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
        ],
      );
      _expectState(
        s,
        subtotal: 10000,
        itemDiscount: 0,
        totalDiscount: 0,
        tax: 1000,
        totalBeforeLoyalty: 11000,
        total: 11000,
      );
      // Line-level pinning
      final line = s.items.single;
      expect(line.subtotalCents, Decimal.fromInt(10000));
      expect(line.netCents, Decimal.fromInt(10000));
      // SaleLineItem.taxCents hard-codes enable=true, default=0 —
      // uses product's own 10% rate.
      expect(line.taxCents, Decimal.fromInt(1000));
      expect(line.totalCents, Decimal.fromInt(11000));
    });

    // ── S03 ────────────────────────────────────────────────────────────
    test('S03 per-item discount, taxable 15%', () {
      // qty=2 × 5000 = 10000; discount 1000; net 9000; tax 15% = 1350;
      // total = 10000 - 1000 + 1350 = 10350.
      final s = _state(
        items: [
          _line(
            tempId: '1',
            product: taxable15,
            qty: 2,
            unitPriceCents: 5000,
            discountCents: 1000,
          ),
        ],
      );
      _expectState(
        s,
        subtotal: 10000,
        itemDiscount: 1000,
        totalDiscount: 1000,
        tax: 1350,
        totalBeforeLoyalty: 10350,
        total: 10350,
      );
    });

    // ── S04 ────────────────────────────────────────────────────────────
    test('S04 invoice-level fixed discount, mixed taxable + non-taxable', () {
      // A: 10000 taxable 10%; B: 6000 non-taxable. Subtotal=16000.
      // Invoice discount 1600 → proportional:
      //   A share = 1000, B share = 600
      // A base = 9000 → tax 900; B base = 5400 → tax 0.
      // total = 16000 - 1600 + 900 = 15300.
      final s = _state(
        items: [
          _line(tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
          _line(tempId: '2', product: nonTaxable, qty: 1, unitPriceCents: 6000),
        ],
        discountMode: SaleDiscountMode.invoice,
        invoiceDiscountCents: 1600,
      );
      _expectState(
        s,
        subtotal: 16000,
        itemDiscount: 0,
        totalDiscount: 1600,
        tax: 900,
        totalBeforeLoyalty: 15300,
        total: 15300,
      );
    });

    // ── S05 ────────────────────────────────────────────────────────────
    test('S05 multi-line, mixed tax rates, mixed per-item discounts', () {
      // Line A: qty=3 × 2000 = 6000, discount 600 → net 5400, tax 15% = 810
      // Line B: qty=1 × 4000 = 4000, discount   0 → net 4000, tax 10% = 400
      // Line C: qty=2 × 1500 = 3000, discount 300 → net 2700, tax  5% = 135
      // subtotal=13000; itemDiscount=900; tax=1345; total=13445.
      final s = _state(
        items: [
          _line(
            tempId: '1',
            product: taxable15,
            qty: 3,
            unitPriceCents: 2000,
            discountCents: 600,
          ),
          _line(tempId: '2', product: taxable10, qty: 1, unitPriceCents: 4000),
          _line(
            tempId: '3',
            product: taxable5,
            qty: 2,
            unitPriceCents: 1500,
            discountCents: 300,
          ),
        ],
      );
      _expectState(
        s,
        subtotal: 13000,
        itemDiscount: 900,
        totalDiscount: 900,
        tax: 1345,
        totalBeforeLoyalty: 13445,
        total: 13445,
      );
      expect(s.totalQuantity, 6);
    });

    // ── S06 ────────────────────────────────────────────────────────────
    test('S06 tax rounding at the .5 boundary (halfUp)', () {
      // qty=1 × 333; tax 15% = 49.95 → halfUp → 50; total = 383.
      final s = _state(
        items: [
          _line(tempId: '1', product: taxable15, qty: 1, unitPriceCents: 333),
        ],
      );
      _expectState(
        s,
        subtotal: 333,
        itemDiscount: 0,
        totalDiscount: 0,
        tax: 50,
        totalBeforeLoyalty: 383,
        total: 383,
      );
    });

    // ── S07 ────────────────────────────────────────────────────────────
    test('S07 loyalty redemption subtracts AFTER tax', () {
      // qty=1 × 10000; tax 10% = 1000; totalBeforeLoyalty = 11000.
      // Loyalty redeems 500 → total = 10500. This is the documented
      // post-tax adjustment that will live in _TenderSnapshot post-migration.
      final s = _state(
        items: [
          _line(tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
        ],
        loyaltyDiscountCents: 500,
      );
      _expectState(
        s,
        subtotal: 10000,
        itemDiscount: 0,
        totalDiscount: 0,
        tax: 1000,
        totalBeforeLoyalty: 11000,
        total: 10500,
      );
    });

    // ── S08 ────────────────────────────────────────────────────────────
    test('S08 partial payment → remaining', () {
      // Total 11000, paid 4000 → remaining 7000, change 0.
      final s = _state(
        items: [
          _line(tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
        ],
        paidAmountCents: 4000,
      );
      _expectState(
        s,
        subtotal: 10000,
        itemDiscount: 0,
        totalDiscount: 0,
        tax: 1000,
        totalBeforeLoyalty: 11000,
        total: 11000,
        remaining: 7000,
        change: 0,
      );
    });

    // ── S09 ────────────────────────────────────────────────────────────
    test('S09 overpayment → change, remaining clamped to 0', () {
      // Total 11000, paid 15000 → remaining 0, change 4000.
      final s = _state(
        items: [
          _line(tempId: '1', product: taxable10, qty: 1, unitPriceCents: 10000),
        ],
        paidAmountCents: 15000,
      );
      _expectState(
        s,
        subtotal: 10000,
        itemDiscount: 0,
        totalDiscount: 0,
        tax: 1000,
        totalBeforeLoyalty: 11000,
        total: 11000,
        remaining: 0,
        change: 4000,
      );
    });

    // ── S10 ────────────────────────────────────────────────────────────
    test('S10 full per-item discount → net clamps, tax = 0', () {
      // qty=1 × 1000, discount 1000; net=0 → tax skipped.
      final s = _state(
        items: [
          _line(
            tempId: '1',
            product: taxable10,
            qty: 1,
            unitPriceCents: 1000,
            discountCents: 1000,
          ),
        ],
      );
      _expectState(
        s,
        subtotal: 1000,
        itemDiscount: 1000,
        totalDiscount: 1000,
        tax: 0,
        totalBeforeLoyalty: 0,
        total: 0,
      );
    });

    // ── S11 ────────────────────────────────────────────────────────────
    test('S11 default-tax fallback only applies to taxable products', () {
      // Documented semantic of TaxCalculationService.resolveLineItemTaxRateBps:
      //   1. non-taxable product → 0
      //   2. taxable product rate when > 0
      //   3. otherwise the default rate
      // This keeps an explicit product exemption authoritative.

      // Path 1 (non-taxable + default rate → remains exempt).
      final sDefaultOnNonTax = _state(
        items: [
          _line(
            tempId: '1',
            product: nonTaxable,
            qty: 1,
            unitPriceCents: 10000,
          ),
        ],
        defaultSalesTaxRateBps: 1000, // 10%
      );
      expect(
        sDefaultOnNonTax.taxCents,
        Decimal.zero,
        reason: 'explicitly non-taxable product must remain exempt',
      );
      expect(sDefaultOnNonTax.totalCents, Decimal.fromInt(10000));

      // Path 3 (taxable + own-rate=0 → default kicks in).
      final taxableZeroRate = _product(
        id: 99,
        name: 'T0',
        isTaxable: true,
        salesTaxRateBps: 0,
      );
      final sFallback = _state(
        items: [
          _line(
            tempId: '1',
            product: taxableZeroRate,
            qty: 1,
            unitPriceCents: 10000,
          ),
        ],
        defaultSalesTaxRateBps: 1000,
      );
      expect(sFallback.taxCents, Decimal.fromInt(1000));
      expect(sFallback.totalCents, Decimal.fromInt(11000));

      // Path 1 (non-taxable, default=0 → no tax).
      final sNoTaxAtAll = _state(
        items: [
          _line(
            tempId: '1',
            product: nonTaxable,
            qty: 1,
            unitPriceCents: 10000,
          ),
        ],
      );
      expect(sNoTaxAtAll.taxCents, Decimal.zero);
    });

    // ── S12 ────────────────────────────────────────────────────────────
    test('S12 invariant: totalBeforeLoyalty == subtotal − totalDiscount + tax '
        '(clamp 0); total == totalBeforeLoyalty − loyalty (clamp 0)', () {
      final scenarios = <SaleFormState>[
        _state(items: const []),
        _state(
          items: [
            _line(
              tempId: '1',
              product: taxable10,
              qty: 1,
              unitPriceCents: 10000,
            ),
          ],
        ),
        _state(
          items: [
            _line(
              tempId: '1',
              product: taxable15,
              qty: 3,
              unitPriceCents: 2000,
              discountCents: 600,
            ),
          ],
        ),
        _state(
          items: [
            _line(
              tempId: '1',
              product: taxable10,
              qty: 2,
              unitPriceCents: 5000,
            ),
            _line(
              tempId: '2',
              product: nonTaxable,
              qty: 1,
              unitPriceCents: 3000,
            ),
          ],
          discountMode: SaleDiscountMode.invoice,
          invoiceDiscountCents: 1300,
          loyaltyDiscountCents: 250,
        ),
      ];
      for (final s in scenarios) {
        final netPreLoyalty =
            s.subtotalCents - s.totalDiscountCents + s.taxCents;
        final expectedBefore = netPreLoyalty < Decimal.zero
            ? Decimal.zero
            : netPreLoyalty;
        expect(
          s.totalBeforeLoyaltyCents,
          expectedBefore,
          reason: 'totalBeforeLoyalty invariant violated',
        );

        final reconstructed =
            s.totalBeforeLoyaltyCents - Decimal.fromInt(s.loyaltyDiscountCents);
        final expectedTotal = reconstructed < Decimal.zero
            ? Decimal.zero
            : reconstructed;
        expect(
          s.totalCents,
          expectedTotal,
          reason: 'total invariant violated (after loyalty)',
        );
      }
    });
  });
}
