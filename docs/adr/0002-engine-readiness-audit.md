# ADR 0002 — Engine Readiness Audit (Phase 2)

* **Status**: Accepted
* **Date**: Phase 2 of the scattered-calculation-logic migration.
* **Companion**: builds on @docs/adr/0001-pricing-engines-as-sot.md.
* **Companion data**: @progress.txt (decision log Q1–Q5).

## Purpose

Phase 2 of the 10-phase migration. Before touching `purchase_form_bloc` or
`sale_form_bloc`, we field-by-field map every existing pricing getter onto
either:

1. **`InvoicePricingEngine.compute(...)`** (single source of truth, see
   @lib/core/pricing/invoice_pricing_engine.dart), **or**
2. **A non-pricing layer** that stays in the bloc (tender / loyalty /
   change-due / settlement).

The goal is to commit, in writing, to one of those two destinations for
every field — so the Phase 3/4 migration is mechanical, not creative.

## Scope

The four form-state classes whose math is duplicating engine semantics:

| State class | File |
|---|---|
| `PurchaseFormState` + `PurchaseLineItem` | @lib/features/purchases/presentation/bloc/purchase_form_bloc.dart |
| `SaleFormState` + `SaleLineItem` | @lib/features/sales/presentation/bloc/sale_form_bloc.dart |
| `PurchaseReturnFormState` + `ReturnLineItem` | @lib/features/purchases/presentation/bloc/purchase_return_form_bloc.dart |
| `SaleReturnFormState` + `SaleReturnLineItem` | @lib/features/sales/presentation/bloc/sale_return_form_bloc.dart |

The **two already-migrated** Adjustment-Return blocs are the reference
implementation (model citizens; see Section 5):

* @lib/features/sales/presentation/bloc/sale_adj_return_form_bloc.dart
* @lib/features/purchases/presentation/bloc/purchase_adj_return_form_bloc.dart

## 1. Field-by-field mapping — `PurchaseFormState`

> Source field references: `purchase_form_bloc.dart:92-155`.

| Bloc field (today) | Maps to | Notes |
|---|---|---|
| `subtotalCents` | `pricing.subtotal.decimalCents` | Σ qty×price. Engine-owned. |
| `itemDiscountCents` | `pricing.itemDiscountTotal.decimalCents` | Σ per-line discounts. |
| `invoiceDiscountCents` (raw field) | **kept** as user-entered value | Input to engine, not output. |
| `invoiceDiscountPercent` (raw field) | **kept** as user-entered value | Input. |
| `effectiveInvoiceDiscountCents` | `pricing.overallDiscount.decimalCents` | Engine resolves percent or fixed and clamps to base. |
| `totalDiscountCents` | `pricing.totalDiscount.decimalCents` | item + overall. |
| `itemTaxCents` / `taxCents` | `pricing.tax.decimalCents` | Engine computes tax post-discount-allocation. |
| `totalCents` | `pricing.total.decimalCents` | subtotal − totalDiscount + tax, clamped ≥ 0. |
| `remainingCents` | **stays in bloc** | Tender layer: `max(0, total − paid)`. |
| `changeCents` | **stays in bloc** | Tender layer: `max(0, paid − total)`. |
| `totalQuantity` | **stays in bloc** | Not a money value. |

> `PurchaseLineItem` field references: `purchase_form_bloc.dart:289-316`.

| Line field (today) | Maps to | Notes |
|---|---|---|
| `subtotalCents` | `pricing.lines[i].subtotal.decimalCents` | unit × qty. |
| `netCents` | `pricing.lines[i].local.net.decimalCents` | subtotal − line discount. |
| `taxCents` / `taxCentsWithSettings(...)` | `pricing.lines[i].tax.decimalCents` | Engine post-allocation tax. |
| `totalCents` | `pricing.lines[i].total.decimalCents` | adjustedNet + tax. |

## 2. Field-by-field mapping — `SaleFormState`

> Source field references: `sale_form_bloc.dart:130-191`.

| Bloc field (today) | Maps to | Notes |
|---|---|---|
| `subtotalCents` | `pricing.subtotal.decimalCents` | Σ qty×price. |
| `itemDiscountCents` | `pricing.itemDiscountTotal.decimalCents` | Σ per-line discounts. |
| `invoiceDiscountCents` | **kept** as user-entered value | Input. |
| `totalDiscountCents` | `pricing.totalDiscount.decimalCents` | item + overall. |
| `itemTaxCents` / `taxCents` | `pricing.tax.decimalCents` | Engine post-discount tax. |
| `totalBeforeLoyaltyCents` | `pricing.total.decimalCents` | Engine's `total` IS the pre-loyalty figure. |
| `totalCents` | **stays in bloc** = `pricing.total − loyaltyDiscountCents` | Tender-layer adjustment (see §4). |
| `remainingCents` | **stays in bloc** | Tender. |
| `changeCents` | **stays in bloc** | Tender. |
| `loyaltyDiscountCents` | **stays in bloc** | Tender-side input. |
| `loyaltyPointsToRedeem` | **stays in bloc** | Tender-side input. |
| `loyaltyPointsBalance` | **stays in bloc** | Read-only customer state. |
| `belowCostWarning` / `belowCostOverrides` | **stays in bloc** | Compliance, not pricing. |
| `totalQuantity` | **stays in bloc** | Counter. |

> `SaleLineItem` field references: `sale_form_bloc.dart:347-374`.

| Line field (today) | Maps to | Notes |
|---|---|---|
| `subtotalCents` | `pricing.lines[i].subtotal.decimalCents` | unit × qty. |
| `netCents` | `pricing.lines[i].local.net.decimalCents` | subtotal − line discount. |
| `taxCents` / `taxCentsWithSettings(...)` | `pricing.lines[i].tax.decimalCents` | Post-allocation tax. |
| `totalCents` | `pricing.lines[i].total.decimalCents` | adjustedNet + tax. |
| `netCentsWithInvoiceDiscount` | `pricing.lines[i].adjustedNet.decimalCents` | Line's share of overall already deducted. |

## 3. Field-by-field mapping — Return form states

> `SaleReturnFormState` references `sale_return_form_bloc.dart:123-144`,
> `PurchaseReturnFormState` references `purchase_return_form_bloc.dart:128-146`.

Returns are NOT computed by `InvoicePricingEngine`. They use a sibling
SoT: @lib/core/services/return_calculation_service.dart, which proportionally
mirrors the **already-posted** original invoice. The engine's role here is
**zero**.

The duplication to fix is the four parallel `fold` getters
(`totalRefundCents` / `totalSubtotalCents` / `totalDiscountCents` /
`totalTaxCents`). They all read different fields off the same
`ReturnCalculationService` result list.

| Bloc getter (today) | Maps to | Phase-5 target |
|---|---|---|
| `totalRefundCents` | Σ `item.refundCents` | `rollup.totalRefundCents` |
| `totalSubtotalCents` | Σ `item.subtotalCents` | `rollup.totalSubtotalCents` |
| `totalDiscountCents` | Σ `item.discountCents` | `rollup.totalDiscountCents` |
| `totalTaxCents` | Σ `item.taxCents` | `rollup.totalTaxCents` |

Phase-5 plan: introduce
`ReturnCalculationService.rollupLineResults(List<...>) → ReturnRollup`,
a tiny aggregate type, and have the two return blocs read from a single
memoized `late final ReturnRollup rollup` field. No new business math.

## 4. Cross-cutting decisions (Q-log resolutions)

### Q2 — Loyalty redemption: pricing or tender?  **→ TENDER**

Loyalty redemption is settlement: customer pays partially with points
instead of cash. It MUST NOT reduce taxable revenue (GAAP / IFRS 15:
revenue is recognised at transaction price including the points used as
consideration). The journal entry that posts loyalty redemption today
debits a contra-AR account, **not** Sales Revenue.

Therefore loyalty is **out of `InvoicePricingEngine`**:

* `pricing.total` = "what the customer owes" (subtotal − discounts + tax).
* `state.totalCents` = `pricing.total − loyaltyDiscountCents` (post-tax tender adjustment).
* `state.remainingCents` / `changeCents` derived from `state.totalCents`.

This is the same pattern as a gift card / store-credit tender. No engine
extension is needed.

Q2 is **CLOSED**.

### Q3 — Purchase invoice-discount percent base mismatch  **→ EQUIVALENT IN PRACTICE**

* `PurchaseFormState.effectiveInvoiceDiscountCents` uses
  `subtotalCents` as the percent base.
* `InvoicePricingEngine` uses `Σ line.net` (per-line net) as the base.

Mathematically these differ **only when per-line discounts AND an
invoice-level discount are both non-zero**. In tapix this is impossible:
`discountMode` is the enum `perItem | invoice` (exclusive). When
`discountMode == invoice`, every line's discount is bypassed (see
@lib/core/services/tax_calculation_service.dart:482-494) — so
`Σ net == subtotal` per line and the engine's base equals the bloc's
base.

The engine's model is a strict superset; current tapix usage hits the
intersection where both bases coincide. Migration preserves byte-identical
totals.

Q3 is **CLOSED** with the documented invariant: *"the bloc surfaces
`perItem | invoice` exclusivity; the engine permits both at once but is
only fed one at a time."* A regression test in Phase 3 will pin this.

### Q5 — "1 % per-item ≡ 1 % overall" exact-parity tolerance

Already documented as ±1 cent / line drift on arbitrary inputs. Dual-compute
assertions in Phase 3/4 will tolerate `≤ lineCount` cents.

### Q1 / Q1b — Tax-rate fallback

Unchanged. Documented in Phase 0 goldens (`S11`).

## 5. The reference implementation already exists

The two adjustment-return blocs are the migration template
(`sale_adj_return_form_bloc.dart:76-122`):

```dart
// Memoized engine result. Built on first access of an immutable state.
late final InvoicePricingResult pricing = _computePricing();

InvoicePricingResult _computePricing() {
  return InvoicePricingEngine.compute(InvoicePricingInput(
    lines: items.map((i) => i.toPricingInput()).toList(growable: false),
    overallDiscount: overallDiscountIsPercent
        ? Discount.percent(overallDiscountCents)
        : (overallDiscountCents > 0
            ? Discount.fixed(Money.fromCents(overallDiscountCents))
            : Discount.none),
    enableTaxCalculations: true,
    defaultTaxRateBps: 0,
    taxInclusivePricing: false,
  ));
}

int get totalSubtotalCents       => pricing.subtotal.cents;
int get totalItemDiscountCents   => pricing.itemDiscountTotal.cents;
int get effectiveOverallDiscount => pricing.overallDiscount.cents;
int get totalAdjustedTaxCents    => pricing.tax.cents;
int get totalCents               => pricing.total.cents;
```

Every Phase 3/4 migration must look like this. **No bespoke math allowed
in the bloc body.**

## 6. Engine capability gaps — required actions

| # | Gap | Severity | Action |
|---|---|---|---|
| G1 | `Money` has `fromCents(int)` and `fromDecimalCents(Decimal)`; blocs hold `Decimal`. | LOW | Use existing `Money.fromCents(d.toBigInt().toInt())` at the bloc→engine boundary. All bloc `Decimal` cents are factually integer (built from `unitPriceCents × Decimal.fromInt(qty)` where `unitPriceCents` originates from `MoneyInputParser` returning `int`). |
| G2 | Bloc percent fields use `Decimal` percent (e.g. `12.5`); engine wants bps (`int`). | LOW | One-line conversion at the call site: `bps = (percent × 100).round()`. Centralise as a static helper on `Discount` or a new tiny `BpsConverter` only **if** more than one call site needs it; otherwise inline. |
| G3 | Engine has no post-tax adjustment slot for loyalty. | **By design** | Not a gap. Loyalty lives in the tender layer (§4 Q2). |
| G4 | Engine percent base = Σ net; bloc base = subtotal in invoice mode. | **None in current usage** | Mode exclusivity guarantees equivalence (§4 Q3). Pin with a regression test in Phase 3. |
| G5 | Engine distributes overall discount by net weights; `TaxCalculationService.calculateInvoiceTax` uses subtotal weights. | **None in current usage** | Same reason as G4. |
| G6 | Engine consumes `LineItemPricingInput`; blocs hold `PurchaseLineItem` / `SaleLineItem`. | LOW | Add a `toPricingInput()` extension on each line type (mirror of `AdjReturnLineItem.toPricingInput()`). One adapter per line type, no logic. |
| G7 | Engine cannot be told "ignore per-line discounts". | LOW | Handled at the bridge: when `discountMode == invoice` the bloc passes `Discount.none` per line and the overall discount as the engine's `overallDiscount`. |

**Conclusion: no engine code changes required.** The migration is
mechanically a bloc-side adapter + a memoized `pricing` field.

## 7. Risk register before Phase 3

| Risk | Likelihood | Mitigation |
|---|---|---|
| Persisted `total_cents` differs by 1 cent post-migration | LOW | Phase 0 goldens (39 ✓) re-run before/after each migration; dual-compute assertion in `kDebugMode` during the migration commit. |
| Tax-rounding mode silently changes | LOW | Engine defaults to `halfUp`; current `TaxCalculationService.calculateInvoiceTax` defaults to `halfUp`. Same. |
| Loyalty redemption accidentally moves into pricing | MED | This ADR documents §4 Q2. Phase 4 PR must include a test that pins `state.totalCents = pricing.total - loyaltyDiscountCents`. |
| `Decimal → int` overflow on huge invoices | NIL | `Money.cents` rejects non-integers; values in tapix are bounded by `int64`. |
| Discount-mode bridging bug (per-item discount applied when mode is `invoice`) | LOW | Pin with a Phase 3 test: `discountMode == invoice` ⇒ `pricing.itemDiscountTotal == Money.zero`. |

## 8. Non-changes — explicitly preserved

* `taxInclusivePricing` flag semantics — already engine-supported.
* `enableTaxCalculations` flag — already engine-supported.
* `defaultPurchaseTaxRateBps` / `defaultSalesTaxRateBps` fallback chain.
* Rounding mode (`halfUp` for both tax and discount).
* Persisted `sales.total_cents` / `purchases.total_cents` byte-for-byte (per §7 mitigation).
* All non-pricing bloc state (employee, salesperson, notes, dueDate, paymentMethod, …).

## 9. Phase-3 entry checklist (purchase pilot)

Before opening the Phase-3 PR:

1. [ ] Re-run Phase 0 goldens (`flutter test test/golden test/core/pricing`) → 39/39 ✓.
2. [ ] Add `PurchaseLineItem.toPricingInput()` extension.
3. [ ] Add `late final InvoicePricingResult pricing` to `PurchaseFormState`.
4. [ ] Rewrite the seven `Decimal get …Cents` getters as thin
   delegations to `pricing.*.decimalCents`.
5. [ ] Add dual-compute `assert(() {...})` in `kDebugMode` comparing
   legacy getter output against `pricing.*` for the lifetime of the PR
   only (deleted at the end of Phase 3 once goldens prove parity).
6. [ ] Add the two Q3/Q5 regression tests (mode exclusivity, ≤ lineCount-cent drift tolerance).
7. [ ] Confirm zero changes to `purchase_repository_impl.dart` /
   `purchase_dao.dart` — bloc surface stays identical.

## 10. Decision

Phase 2 is closed. The mapping is unambiguous, no engine changes are
required, and Phase 3 (purchase pilot) is unblocked.

The next ADR (`0003-phase-3-purchase-pilot.md`) will be opened when the
Phase 3 PR is merged.
