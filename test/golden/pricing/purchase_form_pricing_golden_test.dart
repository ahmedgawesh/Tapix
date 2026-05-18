// ════════════════════════════════════════════════════════════════════════════
// PHASE 0 — PURCHASE FORM PRICING · GOLDEN CHARACTERISATION TESTS
// ════════════════════════════════════════════════════════════════════════════
//
// Purpose
// -------
// Pin the CURRENT outputs of PurchaseFormState / PurchaseLineItem getters
// across 8 canonical scenarios. These tests form the Phase-0 safety net for
// the scattered-calculation-logic migration (see
// docs/adr/0001-pricing-engines-as-sot.md):
//
//   * While the bloc is still the SoT — these tests lock today's behaviour.
//   * After migration to InvoicePricingEngine — these tests must STILL pass.
//     Any deliberate correctness fix that changes a value is an ADR-worthy
//     decision; update this golden alongside the fix.
//
// NO bloc wiring. NO repositories, NO DAOs, NO database. Pure state getters.
//
// Coverage:
//   P1  empty invoice
//   P2  single taxable line, no discount, tax-exclusive
//   P3  per-item discount, taxable 10%
//   P4  invoice-level percent discount, tax disabled
//   P5  invoice-level fixed discount, mixed taxable + non-taxable
//   P6  multi-line per-item discounts, mixed tax rates
//   P7  tax rounding at the .5 boundary (halfUp)
//   P8  discount == subtotal -> net clamps to 0; tax = 0
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_form_bloc.dart';

Product _product({
  required int id,
  required String name,
  required bool isTaxable,
  required int purchaseTaxRateBps,
}) =>
    Product(
      id: id,
      name: name,
      costCents: Decimal.zero,
      priceCents: Decimal.zero,
      stockQuantity: 0,
      minQuantity: 0,
      hasVariants: false,
      isTaxable: isTaxable,
      purchaseTaxRateBps: purchaseTaxRateBps,
      salesTaxRateBps: 0,
      isActive: true,
      trackInventory: true,
    );

PurchaseLineItem _line({
  required String tempId,
  required Product product,
  required int qty,
  required int unitCostCents,
  int discountCents = 0,
}) =>
    PurchaseLineItem(
      tempId: tempId,
      product: product,
      quantity: qty,
      unitCostCents: Decimal.fromInt(unitCostCents),
      discountCents: Decimal.fromInt(discountCents),
      originalCostCents: unitCostCents,
      originalPriceCents: unitCostCents * 2,
    );

PurchaseFormState _state({
  required List<PurchaseLineItem> items,
  DiscountMode discountMode = DiscountMode.perItem,
  int invoiceDiscountCents = 0,
  int invoiceDiscountPercent = 0,
  bool enableTaxCalculations = true,
  int defaultPurchaseTaxRateBps = 0,
}) =>
    PurchaseFormState(
      currencyId: 1,
      purchaseDate: DateTime(2026, 1, 15),
      items: items,
      discountMode: discountMode,
      invoiceDiscountCents: Decimal.fromInt(invoiceDiscountCents),
      invoiceDiscountPercent: Decimal.fromInt(invoiceDiscountPercent),
      enableTaxCalculations: enableTaxCalculations,
      defaultPurchaseTaxRateBps: defaultPurchaseTaxRateBps,
    );

void _expectState(
  PurchaseFormState state, {
  required int subtotal,
  required int itemDiscount,
  required int effectiveInvoiceDiscount,
  required int totalDiscount,
  required int tax,
  required int total,
}) {
  expect(state.subtotalCents, Decimal.fromInt(subtotal), reason: 'subtotal');
  expect(state.itemDiscountCents, Decimal.fromInt(itemDiscount),
      reason: 'itemDiscount');
  expect(state.effectiveInvoiceDiscountCents,
      Decimal.fromInt(effectiveInvoiceDiscount),
      reason: 'effectiveInvoiceDiscount');
  expect(state.totalDiscountCents, Decimal.fromInt(totalDiscount),
      reason: 'totalDiscount');
  expect(state.taxCents, Decimal.fromInt(tax), reason: 'tax');
  expect(state.totalCents, Decimal.fromInt(total), reason: 'total');
}

void main() {
  final taxable10 = _product(
      id: 1, name: 'Taxable 10%', isTaxable: true, purchaseTaxRateBps: 1000);
  final taxable15 = _product(
      id: 2, name: 'Taxable 15%', isTaxable: true, purchaseTaxRateBps: 1500);
  final nonTaxable = _product(
      id: 3, name: 'Non-taxable', isTaxable: false, purchaseTaxRateBps: 0);

  group('Purchase form — Phase 0 golden characterisation', () {
    // ── P1 ─────────────────────────────────────────────────────────────
    test('P1 empty invoice → all zeros', () {
      final s = _state(items: const []);
      _expectState(s,
          subtotal: 0,
          itemDiscount: 0,
          effectiveInvoiceDiscount: 0,
          totalDiscount: 0,
          tax: 0,
          total: 0);
      expect(s.totalQuantity, 0);
    });

    // ── P2 ─────────────────────────────────────────────────────────────
    test('P2 single taxable line, no discount, tax-exclusive', () {
      // qty=1 × 10000 = 10000 subtotal. 10% tax = 1000. Total = 11000.
      final s = _state(items: [
        _line(tempId: '1', product: taxable10, qty: 1, unitCostCents: 10000),
      ]);
      _expectState(s,
          subtotal: 10000,
          itemDiscount: 0,
          effectiveInvoiceDiscount: 0,
          totalDiscount: 0,
          tax: 1000,
          total: 11000);
      expect(s.totalQuantity, 1);
      final line = s.items.single;
      expect(line.subtotalCents, Decimal.fromInt(10000));
      expect(line.netCents, Decimal.fromInt(10000));
      expect(line.taxCents, Decimal.fromInt(1000));
      expect(line.totalCents, Decimal.fromInt(11000));
    });

    // ── P3 ─────────────────────────────────────────────────────────────
    test('P3 per-item discount, taxable 10% — tax on net-after-discount', () {
      // qty=2 × 5000 = 10000; discount 500 → net 9500; tax 10% = 950;
      // total = 10000 - 500 + 950 = 10450.
      final s = _state(items: [
        _line(
            tempId: '1',
            product: taxable10,
            qty: 2,
            unitCostCents: 5000,
            discountCents: 500),
      ]);
      _expectState(s,
          subtotal: 10000,
          itemDiscount: 500,
          effectiveInvoiceDiscount: 0,
          totalDiscount: 500,
          tax: 950,
          total: 10450);
    });

    // ── P4 ─────────────────────────────────────────────────────────────
    test('P4 invoice-level 10% discount, tax disabled', () {
      // Subtotal 10000+10000=20000. 10% → effective 2000. Tax disabled.
      // Total = 20000 - 2000 = 18000.
      final s = _state(
        items: [
          _line(
              tempId: '1',
              product: nonTaxable,
              qty: 1,
              unitCostCents: 10000),
          _line(
              tempId: '2',
              product: nonTaxable,
              qty: 2,
              unitCostCents: 5000),
        ],
        discountMode: DiscountMode.invoice,
        invoiceDiscountPercent: 10,
        enableTaxCalculations: false,
      );
      _expectState(s,
          subtotal: 20000,
          itemDiscount: 0,
          effectiveInvoiceDiscount: 2000,
          totalDiscount: 2000,
          tax: 0,
          total: 18000);
    });

    // ── P5 ─────────────────────────────────────────────────────────────
    test('P5 invoice-fixed discount, mixed taxable + non-taxable', () {
      // A: 10000 taxable 10%; B: 6000 non-taxable. Subtotal=16000.
      // Invoice discount 1600 distributed proportionally:
      //   A share = 1600 * 10000/16000 = 1000
      //   B share = 1600 *  6000/16000 =  600
      // A taxable base = 9000 → tax = 900
      // B non-taxable → tax = 0
      // totalTax = 900, total = 16000 - 1600 + 900 = 15300.
      final s = _state(
        items: [
          _line(
              tempId: '1', product: taxable10, qty: 1, unitCostCents: 10000),
          _line(
              tempId: '2', product: nonTaxable, qty: 1, unitCostCents: 6000),
        ],
        discountMode: DiscountMode.invoice,
        invoiceDiscountCents: 1600,
      );
      _expectState(s,
          subtotal: 16000,
          itemDiscount: 0,
          effectiveInvoiceDiscount: 1600,
          totalDiscount: 1600,
          tax: 900,
          total: 15300);
    });

    // ── P6 ─────────────────────────────────────────────────────────────
    test('P6 multi-line per-item discounts, mixed tax rates', () {
      // Line A: qty=3 × 2000 = 6000, discount 600 → net 5400, tax 15% = 810
      // Line B: qty=1 × 4000 = 4000, discount   0 → net 4000, tax 10% = 400
      // Line C: qty=2 × 1500 = 3000, discount 300 → net 2700, tax  0% =   0
      // subtotal       = 6000 + 4000 + 3000 = 13000
      // itemDiscount   =  600 +    0 +  300 =   900
      // tax            =  810 +  400 +    0 =  1210
      // total          = 13000 - 900 + 1210 = 13310
      final s = _state(items: [
        _line(
            tempId: '1',
            product: taxable15,
            qty: 3,
            unitCostCents: 2000,
            discountCents: 600),
        _line(
            tempId: '2',
            product: taxable10,
            qty: 1,
            unitCostCents: 4000),
        _line(
            tempId: '3',
            product: nonTaxable,
            qty: 2,
            unitCostCents: 1500,
            discountCents: 300),
      ]);
      _expectState(s,
          subtotal: 13000,
          itemDiscount: 900,
          effectiveInvoiceDiscount: 0,
          totalDiscount: 900,
          tax: 1210,
          total: 13310);
      expect(s.totalQuantity, 6);
    });

    // ── P7 ─────────────────────────────────────────────────────────────
    test('P7 tax rounding at the .5 boundary (halfUp)', () {
      // qty=1 × 333 subtotal; tax 15% = 333 × 0.15 = 49.95 cents;
      // halfUp → 50. total = 333 + 50 = 383.
      final s = _state(items: [
        _line(tempId: '1', product: taxable15, qty: 1, unitCostCents: 333),
      ]);
      _expectState(s,
          subtotal: 333,
          itemDiscount: 0,
          effectiveInvoiceDiscount: 0,
          totalDiscount: 0,
          tax: 50,
          total: 383);
    });

    // ── P8 ─────────────────────────────────────────────────────────────
    test('P8 full-discount line — net clamps to 0, tax = 0', () {
      // qty=1 × 1000, discount 1000. Net = 0 → tax skipped even if taxable.
      // totalTax = 0, total = 1000 - 1000 + 0 = 0.
      final s = _state(items: [
        _line(
            tempId: '1',
            product: taxable10,
            qty: 1,
            unitCostCents: 1000,
            discountCents: 1000),
      ]);
      _expectState(s,
          subtotal: 1000,
          itemDiscount: 1000,
          effectiveInvoiceDiscount: 0,
          totalDiscount: 1000,
          tax: 0,
          total: 0);
    });

    // ── Structural invariants (apply across all scenarios) ────────────
    test('invariant: totalCents == subtotal − totalDiscount + tax (clamp 0)',
        () {
      final scenarios = <PurchaseFormState>[
        _state(items: const []),
        _state(items: [
          _line(
              tempId: '1', product: taxable10, qty: 1, unitCostCents: 10000),
        ]),
        _state(items: [
          _line(
              tempId: '1',
              product: taxable15,
              qty: 3,
              unitCostCents: 2000,
              discountCents: 600),
        ]),
        _state(
          items: [
            _line(
                tempId: '1',
                product: taxable10,
                qty: 1,
                unitCostCents: 10000),
          ],
          discountMode: DiscountMode.invoice,
          invoiceDiscountPercent: 10,
        ),
      ];
      for (final s in scenarios) {
        final reconstructed = s.subtotalCents - s.totalDiscountCents + s.taxCents;
        final expected =
            reconstructed < Decimal.zero ? Decimal.zero : reconstructed;
        expect(s.totalCents, expected,
            reason: 'totalCents invariant violated for $s');
      }
    });
  });
}
