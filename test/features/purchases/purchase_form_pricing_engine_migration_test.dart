// ════════════════════════════════════════════════════════════════════════════
// PHASE 3 — PURCHASE FORM · ENGINE-MIGRATION REGRESSION TESTS
// ════════════════════════════════════════════════════════════════════════════
//
// Purpose
// -------
// Pin the invariants introduced by migrating `purchase_form_bloc.dart` from
// hand-rolled cents math to `InvoicePricingEngine` / `LineItemPricingEngine`
// as the single source of truth (ADR `docs/adr/0002-engine-readiness-audit.md`).
//
// These tests complement the Phase-0 golden snapshot
// (`test/golden/pricing/purchase_form_pricing_golden_test.dart`) and target
// the open questions documented in `progress.txt`:
//
//   * Q3 — discount-mode exclusivity: in `DiscountMode.invoice` the engine
//     receives `Discount.none` for every per-line discount, so Σ net == subtotal
//     and the total is identical to what the legacy `TaxCalculationService`
//     path produced.
//   * Q5 — bounded drift: when both per-item and invoice-level pricing paths
//     are exercised, the engine's totals match the legacy "subtotal − totalDiscount + tax"
//     reconstruction within a documented tolerance (≤ items.length cents).
//
// No bloc wiring, no repositories, no database. Pure state getters.
// ════════════════════════════════════════════════════════════════════════════

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/pricing/invoice_pricing_engine.dart';
import 'package:tapix/features/products/domain/entities/product_entity.dart';
import 'package:tapix/features/purchases/presentation/bloc/purchase_form_bloc.dart';

Product _product({
  required int id,
  required String name,
  required bool isTaxable,
  required int purchaseTaxRateBps,
}) => Product(
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
}) => PurchaseLineItem(
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
  bool enableTaxCalculations = true,
  int defaultPurchaseTaxRateBps = 0,
  bool taxInclusivePricing = false,
}) => PurchaseFormState(
  currencyId: 1,
  purchaseDate: DateTime(2026, 1, 15),
  items: items,
  discountMode: discountMode,
  invoiceDiscountCents: Decimal.fromInt(invoiceDiscountCents),
  enableTaxCalculations: enableTaxCalculations,
  defaultPurchaseTaxRateBps: defaultPurchaseTaxRateBps,
  taxInclusivePricing: taxInclusivePricing,
);

void main() {
  final taxable10 = _product(
    id: 1,
    name: 'Taxable 10%',
    isTaxable: true,
    purchaseTaxRateBps: 1000,
  );
  final taxable15 = _product(
    id: 2,
    name: 'Taxable 15%',
    isTaxable: true,
    purchaseTaxRateBps: 1500,
  );
  final nonTaxable = _product(
    id: 3,
    name: 'Non-taxable',
    isTaxable: false,
    purchaseTaxRateBps: 0,
  );

  group('Phase 3 — engine SoT migration', () {
    // ── Q3 — discount-mode exclusivity ────────────────────────────────────
    test('Q3a — perItem mode: engine reports itemDiscount = Σ line.discount, '
        'overall = 0', () {
      final s = _state(
        items: [
          _line(
            tempId: '1',
            product: taxable10,
            qty: 1,
            unitCostCents: 10000,
            discountCents: 1000,
          ),
          _line(
            tempId: '2',
            product: taxable10,
            qty: 1,
            unitCostCents: 5000,
            discountCents: 500,
          ),
        ],
      );
      expect(s.pricing.itemDiscountTotal.cents, 1500);
      expect(s.pricing.overallDiscount.cents, 0);
      expect(s.pricing.totalDiscount.cents, 1500);
    });

    test('Q3b — invoice mode: per-line discounts are suppressed at the engine, '
        'overall = invoice value', () {
      // The user has previously entered per-line discounts but then switched
      // to `invoice` discount mode. The engine must treat the per-line ones
      // as Discount.none — matching the long-standing submission contract
      // of TaxCalculationService.calculateInvoiceTax.
      final s = _state(
        items: [
          _line(
            tempId: '1',
            product: taxable10,
            qty: 1,
            unitCostCents: 10000,
            // stale per-line discount — must be ignored by engine.
            discountCents: 1000,
          ),
          _line(
            tempId: '2',
            product: taxable10,
            qty: 1,
            unitCostCents: 5000,
            discountCents: 500,
          ),
        ],
        discountMode: DiscountMode.invoice,
        invoiceDiscountCents: 750,
      );
      // Engine has itemDiscount=0 (mode-exclusivity), overall=750.
      expect(s.pricing.itemDiscountTotal.cents, 0);
      expect(s.pricing.overallDiscount.cents, 750);
      expect(s.pricing.totalDiscount.cents, 750);
      // State-level "user-entered item discount" still surfaces the stale
      // values for the UI (preserved legacy contract).
      expect(s.itemDiscountCents, Decimal.fromInt(1500));
      // totalDiscountCents (the persisted figure) reflects the engine.
      expect(s.totalDiscountCents, Decimal.fromInt(750));
    });

    test('Q3c — invoice-mode percent: engine clamps to ≤ subtotal '
        '(legacy fixed-path quirk eliminated)', () {
      // 200% on a 10000 subtotal must clamp to 10000 — not 20000.
      final s = _state(
        items: [
          _line(tempId: '1', product: nonTaxable, qty: 1, unitCostCents: 10000),
        ],
        discountMode: DiscountMode.invoice,
        // 200 currency units (20000¢) against a 10000¢ subtotal — the
        // engine FixedDiscount clamps to ≤ subtotal, matching what the UI's
        // DiscountConverter produces when a 200% rate is typed.
        invoiceDiscountCents: 20000,
        enableTaxCalculations: false,
      );
      expect(s.effectiveInvoiceDiscountCents, Decimal.fromInt(10000));
      expect(s.totalCents, Decimal.zero);
    });

    // ── Q5 — engine vs legacy invariant ────────────────────────────────────
    test(
      'Q5 — engine total satisfies subtotal − totalDiscount + tax (clamp 0)',
      () {
        final scenarios = <PurchaseFormState>[
          _state(items: const []),
          _state(
            items: [
              _line(
                tempId: '1',
                product: taxable10,
                qty: 1,
                unitCostCents: 10000,
              ),
            ],
          ),
          _state(
            items: [
              _line(
                tempId: '1',
                product: taxable15,
                qty: 3,
                unitCostCents: 2000,
                discountCents: 600,
              ),
              _line(
                tempId: '2',
                product: taxable10,
                qty: 1,
                unitCostCents: 4000,
              ),
              _line(
                tempId: '3',
                product: nonTaxable,
                qty: 2,
                unitCostCents: 1500,
                discountCents: 300,
              ),
            ],
          ),
          _state(
            items: [
              _line(
                tempId: '1',
                product: taxable10,
                qty: 1,
                unitCostCents: 10000,
              ),
              _line(
                tempId: '2',
                product: nonTaxable,
                qty: 1,
                unitCostCents: 6000,
              ),
            ],
            discountMode: DiscountMode.invoice,
            invoiceDiscountCents: 1600,
          ),
          _state(
            items: [
              _line(
                tempId: '1',
                product: taxable15,
                qty: 1,
                unitCostCents: 79984,
              ),
            ],
            discountMode: DiscountMode.invoice,
            invoiceDiscountCents: 800, // ≈ 1% of 79984¢ net
          ),
        ];
        for (final s in scenarios) {
          final reconstructed =
              s.subtotalCents - s.totalDiscountCents + s.taxCents;
          final expected = reconstructed < Decimal.zero
              ? Decimal.zero
              : reconstructed;
          expect(
            s.totalCents,
            expected,
            reason: 'total invariant violated for scenario: $s',
          );
        }
      },
    );

    test('Q5 — Σ engine.line.total == invoice.total exactly', () {
      // The "lost cent" bug the largest-remainder allocator was built to
      // prevent. Engine-level invariant; the bloc's reliance on this is what
      // makes its per-line persistence correct.
      final s = _state(
        items: [
          _line(tempId: '1', product: taxable10, qty: 3, unitCostCents: 3333),
          _line(tempId: '2', product: taxable15, qty: 7, unitCostCents: 1234),
          _line(tempId: '3', product: nonTaxable, qty: 2, unitCostCents: 999),
        ],
        discountMode: DiscountMode.invoice,
        invoiceDiscountCents: 1444, // ≈ 7% of the 20635¢ subtotal
      );
      final summed = s.pricing.lines.fold<int>(
        0,
        (acc, l) => acc + l.total.cents,
      );
      expect(summed, s.pricing.total.cents);
    });

    // ── Engine consumer contract ─────────────────────────────────────────
    test('state exposes the same engine instance to bloc & UI (memoized)', () {
      final s = _state(
        items: [
          _line(tempId: '1', product: taxable10, qty: 1, unitCostCents: 10000),
        ],
      );
      final a = s.pricing;
      final b = s.pricing;
      expect(
        identical(a, b),
        isTrue,
        reason: 'pricing must be memoized — computing it twice is a perf bug',
      );
    });

    test('PurchaseLineItem.toPricingInput round-trips through the engine', () {
      final item = _line(
        tempId: '1',
        product: taxable15,
        qty: 4,
        unitCostCents: 2500,
        discountCents: 500,
      );
      // qty 4 × 2500 = 10000; disc 500 → net 9500; tax 15% = 1425;
      // total = 10925.
      expect(item.subtotalCents, Decimal.fromInt(10000));
      expect(item.netCents, Decimal.fromInt(9500));
      expect(item.taxCents, Decimal.fromInt(1425));
      expect(item.totalCents, Decimal.fromInt(10925));
    });

    test('PurchaseLineItem.taxCentsWithSettings honors global toggle + '
        'default fallback', () {
      final untaxedProduct = _product(
        id: 99,
        name: 'No rate',
        isTaxable: true,
        purchaseTaxRateBps: 0,
      ); // taxable flag set, but no own rate
      final item = _line(
        tempId: '1',
        product: untaxedProduct,
        qty: 1,
        unitCostCents: 10000,
      );
      // Disabled: 0.
      expect(
        item.taxCentsWithSettings(
          enableTaxCalculations: false,
          defaultTaxRateBps: 1000,
        ),
        Decimal.zero,
      );
      // Enabled with default rate 10%: 1000.
      expect(
        item.taxCentsWithSettings(
          enableTaxCalculations: true,
          defaultTaxRateBps: 1000,
        ),
        Decimal.fromInt(1000),
      );
    });

    // ── Type-system check — engine result is reachable from state ────────
    test(
      'pricing is an InvoicePricingResult (engine SoT, not a duplicate)',
      () {
        final s = _state(
          items: [
            _line(
              tempId: '1',
              product: taxable10,
              qty: 1,
              unitCostCents: 10000,
            ),
          ],
        );
        expect(s.pricing, isA<InvoicePricingResult>());
      },
    );
  });
}
