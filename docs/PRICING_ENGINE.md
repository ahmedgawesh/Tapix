# Pricing Engine — Single Source of Truth for Money Math

> **Status:** Phase 1 (`Money` + engines) — landed.
> Adopted by: `PurchaseAdjReturnFormState`, `SaleAdjReturnFormState`.
> Pending: `PurchaseFormState`, `SaleFormState`, `PurchaseReturnFormState`,
> `SaleReturnFormState` (Phase 5 of the roadmap).

## Why this exists

Before Phase 1, the `subtotal → discount → tax → total` formula lived
inside *every* form-state class. Six copies of the same arithmetic, each
free to drift from the others. Two real bugs were directly caused by that
drift:

| Bug | Cause | Fix |
|-----|-------|-----|
| `799.84 ≠ 799.92` (1 % overall vs. 1 % per-item) | The overall % discount used `subtotal+tax` as its base; per-item % used `subtotal`. | Engine forces **one** rule: percent base = `Σ line.net` (pre-tax). |
| `qty change does not re-apply discount %` | UI converted `1%` to absolute cents on entry. | `Discount.percent` is a value type; the engine resolves it against the *current* subtotal on every read. |

Phase 1 makes those bugs **impossible to re-introduce in any new feature
that uses the engine**, because there is now exactly one place where the
math runs.

## Modules

```
lib/core/
├── money/
│   └── money.dart                      ← Money value object + RoundingMode
└── pricing/
    ├── discount.dart                   ← sealed Discount: none | fixed | percent
    ├── line_item_pricing_engine.dart   ← one-line math
    └── invoice_pricing_engine.dart     ← whole-invoice math (composes line + tax)
```

`TaxCalculationService` (in `lib/core/services/`) is **unchanged**.
The pricing engines call it; they do not duplicate it.

## Contracts (the rules — all callers must obey)

### Money
- All money is `Money` (cents internally as `Decimal`/`BigInt`). Never `double`.
- `Money` is immutable, value-equal, currency-agnostic for now (single-currency assumption).
- `Money.percentage(bps)` — the **only** way to compute a percent of money.
- `Money.allocate(weights)` — the **only** way to split a sum so that
  `Σ allocations == total` exactly (largest-remainder method).
- Default rounding: **HALF_UP** for display/discount; tax follows
  `TaxRoundingMode` from `TaxCalculationService` (typically `halfUp`).

### LineItemPricingEngine
1. `subtotal = unitPrice × quantity` (exact).
2. `discount = Discount.resolve(base = subtotal)` — **percent base is
   subtotal, never `subtotal+tax`**.
3. `net = max(0, subtotal − discount)`.
4. `tax = TaxCalculationService.calculateTax(net, rate, inclusive)`.
5. `total = net + tax`.

### InvoicePricingEngine
1. Each line's local breakdown follows `LineItemPricingEngine` rules.
2. **Overall percent discount base = `Σ line.net`** (i.e. net-after-line-
   discounts, **before** tax). Symmetric with per-line percent semantics.
3. Overall discount distributed proportionally across lines via
   `Money.allocate` → `Σ shares == overall` (no escaped cents).
4. Per-line tax computed on `line.net − line.share` (post-allocation
   base). Matches QuickBooks / SAP / Xero behavior.
5. `total = subtotal − totalDiscount + tax  ==  Σ line.total`.

## Rounding policy

| Operation | Default mode | Why |
|-----------|--------------|-----|
| Multiplication of money by a scalar | exact (no rounding) | preserves precision |
| Money × percent (`bps`) | `halfUp` | matches what cashiers expect on receipts |
| Tax calculation | `halfUp` (configurable) | aligned with existing `TaxCalculationService` |
| Allocation (split sum) | largest-remainder | guarantees `Σ allocations == total` |

`halfEven` (banker's) is available on `MoneyRoundingMode` for callers
that need IFRS-aligned rounding; not the default to keep parity with
the legacy receipts users have already seen.

## How a form-state plugs in

```dart
class PurchaseAdjReturnFormState extends Equatable {
  // … existing fields …

  /// Single memoized engine result.
  late final InvoicePricingResult pricing = _computePricing();

  InvoicePricingResult _computePricing() => InvoicePricingEngine.compute(
        InvoicePricingInput(
          lines: items.map((i) => i.toPricingInput()).toList(growable: false),
          overallDiscount: overallDiscountIsPercent
              ? Discount.percent(overallDiscountCents)
              : (overallDiscountCents > 0
                  ? Discount.fixed(Money.fromCents(overallDiscountCents))
                  : Discount.none),
          enableTaxCalculations: true,
          defaultTaxRateBps: 0,
          taxInclusivePricing: false,
        ),
      );

  // All public getters return ints (cents) for back-compat with the UI,
  // but they are *thin views* over `pricing`. No arithmetic lives here.
  int get totalSubtotalCents       => pricing.subtotal.cents;
  int get totalItemDiscountCents   => pricing.itemDiscountTotal.cents;
  int get effectiveOverallDiscountCents => pricing.overallDiscount.cents;
  int get totalAdjustedTaxCents    => pricing.tax.cents;
  int get totalCents               => pricing.total.cents;
}
```

The `_onSubmitted` handler reads `state.pricing.lines[idx]` to populate
companions — there is **no second arithmetic path** between the UI and
the DAO.

## Tests

| File | Scope |
|------|-------|
| `test/core/money/money_test.dart` | `Money` value object (26 tests, incl. allocate property test) |
| `test/core/pricing/line_item_pricing_engine_test.dart` | one-line math + bug regressions (14 tests) |
| `test/core/pricing/invoice_pricing_engine_test.dart` | invoice math + per-item ↔ overall parity invariant (13 tests) |
| `test/features/purchases/adj_return_discount_parity_test.dart` | bloc-level invariants on the purchase side (5 tests) |
| `test/features/sales/sale_adj_return_engine_parity_test.dart` | bloc-level invariants on the sale side (5 tests) |
| `test/integration/adjustment_return_accounting_test.dart` | DAO + JE balance unchanged after migration (4 tests) |

**62 tests** locking the contracts. Any future scattered arithmetic that
diverges will fail one of them.

## Roadmap (Phases 2 – 5)

| Phase | What | Why |
|-------|------|-----|
| 2 | Property-based tests with `glados`/`fast_check` (Σ allocations, parity, void(post(x)) round-trip). | Catch what example-tests miss. |
| 3 | Custom lints + arch-tests forbidding raw `cents` arithmetic outside `lib/core/`. | Make scattered code unbuildable. |
| 4 | Pre-posting validator on `JournalEntryService`: reject any post where `subtotal − discount + tax ≠ total`. | Defense-in-depth at the boundary. |
| 5 | Migrate the four remaining `*FormState` classes onto the engine. Remove copy-pasted formulas. | Finish the centralization. |

## Don'ts (banned patterns)

- ❌ `int discountCents = (subtotalCents * bps / 10000).round();`
  → use `Money.percentage(bps)` or `Discount.percent(bps).resolve(...)`.
- ❌ `int taxCents = (netCents * rateBps / 10000).round();`
  → already wrong (loses inclusive-pricing semantics); use `TaxCalculationService.calculateTax`.
- ❌ Manual proration loops: `share = idx == last ? remainder : (total * weight / sum).round();`
  → use `Money.allocate(weights)` — handles the rounding drift correctly.
- ❌ `double` anywhere in money flow.
- ❌ Operating on `int cents` outside `lib/core/money/` or `lib/core/pricing/`
  except as a thin view (e.g. `pricing.total.cents`).

## Maintainers

Owner: `@ahmedgawesh`. Touching any file under `lib/core/money/`,
`lib/core/pricing/`, `lib/core/services/journal_entry_service.dart`,
`lib/core/services/balance_service.dart`, or
`lib/core/database/daos/*_dao.dart` requires:

1. ✅ All tests under `test/core/{money,pricing}/` pass.
2. ✅ All `*adj_return*` parity tests pass.
3. ✅ All integration tests under `test/integration/` pass.
4. ✅ This document updated if a contract changes.
