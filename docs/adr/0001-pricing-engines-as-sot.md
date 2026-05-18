# ADR 0001 — Pricing Engines as the Single Source of Truth

- **Status:** Accepted — May 2026 · **CLOSED (all 10 phases delivered)** 2026-05-12
- **Scope:** `lib/features/{sales,purchases}/presentation/bloc/*_form_bloc.dart`, `lib/core/pricing/**`, `lib/core/money/money.dart`
- **Supersedes:** none
- **Related:**
  - `docs/PRICING_ENGINE.md` (pre-existing engine design doc)
  - `docs/ACCOUNTING_INTEGRITY_GUIDELINES.md`
  - `_bmad-output/TAPIX_ACCOUNTING_INTEGRITY_ARCHITECTURE.md`
  - `_bmad-output/TAPIX_ACCOUNTING_DEEP_AUDIT_REPORT.md`

---

## 1. Context

A system-wide calculation-logic audit identified **scattered pricing math** as
the highest-risk duplication in the codebase (section 2.A of the audit).

The authoritative pricing engines already exist and are correct:

- `lib/core/money/money.dart` — exact-cents arithmetic, `percentage(bps)`,
  largest-remainder `allocate(weights)`, 3 rounding modes.
- `lib/core/pricing/line_item_pricing_engine.dart` — per-line
  `subtotal → discount → net → tax → total`.
- `lib/core/pricing/invoice_pricing_engine.dart` — invoice composition,
  overall-discount proration against `Σ line.net` (closes the documented
  "799.84 vs 799.92" bug), tax on adjusted net.
- `lib/core/services/tax_calculation_service.dart` — tax primitives.

Yet `SaleFormState` / `SaleLineItem` and `PurchaseFormState` /
`PurchaseLineItem` re-implement the same math in parallel:

```
SaleLineItem.subtotalCents      = unitPrice * qty
SaleLineItem.netCents            = subtotal - discount
SaleLineItem.taxCents            = TaxCalculationService.calculateLineItemTax(...)
SaleLineItem.totalCents          = net + tax    // hard-coded enable=true, default=0
SaleFormState.itemTaxCents       = TaxCalculationService.calculateInvoiceTax(...)
SaleFormState.totalBeforeLoyalty = clamp0(subtotal - discount + tax)
SaleFormState.totalCents         = clamp0(totalBeforeLoyalty - loyaltyDiscount)
```

The *adj-return* blocs (`sale_adj_return_form_bloc.dart`,
`purchase_adj_return_form_bloc.dart`) have already been migrated to consume
`InvoicePricingEngine` via a memoised `PricingSnapshot` and are the pattern
the remaining blocs will follow.

## 2. Decision

The pricing engines are the **Single Source of Truth** (SoT) for *all*
subtotal / discount / net / tax / total arithmetic in tapix.

| Column owner (SoT)                    | File                                                                      |
| ------------------------------------- | ------------------------------------------------------------------------- |
| cents arithmetic & allocation         | `lib/core/money/money.dart`                                               |
| text → cents parsing                  | `lib/core/money/money_input_parser.dart`                                  |
| % ↔ ¢ conversion                      | `lib/core/services/pricing/discount_converter.dart`                       |
| per-line pricing                      | `lib/core/pricing/line_item_pricing_engine.dart`                          |
| invoice composition + proration + tax | `lib/core/pricing/invoice_pricing_engine.dart`                            |
| tax primitives                        | `lib/core/services/tax_calculation_service.dart`                          |
| return proportional reversal          | `lib/core/services/return_calculation_service.dart`                       |

Every form-state, preview widget, PDF service, and report bloc becomes a
**consumer** of these engines. Direct cents arithmetic on domain values
outside the SoT files is a defect.

### 2.1. Boundary — what stays in the bloc

The following are *not* pricing math and remain in the form blocs:

- **Tendering**: `paidAmountCents`, `remainingCents`, `changeCents`,
  `overpaymentHandling`.
- **Loyalty redemption**: `loyaltyPointsToRedeem`, `loyaltyDiscountCents`
  (applied post-tax, before `totalCents`).
- **Commission preview / Below-cost warning** (feature-specific services).

A future migration will compose these into a `_TenderSnapshot` alongside the
engine-produced `_PricingSnapshot`, keeping them clearly separated.

## 3. Contracts (invariants the tests pin)

1. **Line-level**:
   `subtotal = unitPrice * qty`, `net = max(0, subtotal − discount)`,
   `tax` via `TaxCalculationService`, `total = net + tax`.
2. **Invoice-level**:
   overall-discount base = `Σ line.net` (pre-tax); proration uses
   `Money.allocate(weights=line.net)` (largest-remainder);
   tax is recomputed on `line.net − line.shareOfOverall`.
3. **No escaped cents**:
   `Σ (line.total) == invoice.total`, always.
4. **Rounding**:
   default `MoneyRoundingMode.halfUp` / `TaxRoundingMode.halfUp` everywhere.
   Any caller needing a different mode passes it explicitly.
5. **Negative guard**:
   totals clamp to `>= 0` at invoice level; line results do not clamp below
   their natural value.
6. **Persisted totals == engine output**:
   `sales.{subtotal,discount,tax,total}_cents` and
   `purchases.{subtotal,discount,tax,total}_cents` are written *verbatim*
   from `InvoicePricingEngine.compute(...).{subtotal,itemDiscountTotal+overallDiscount,tax,total}`.

## 4. Migration policy (tests-first, drift-detection-first)

The migration is done **bottom-up** and **never** in a flag-day cut. Each
PR is independently revertible.

1. **Phase 0 — Safety net.** Golden characterisation tests pin the *current*
   bloc-calculated outputs for 12 sale + 8 purchase + 6 return scenarios.
   Property-based tests pin the `Σ parts == total` invariant on `Money.allocate`
   and `InvoicePricingEngine`.
2. **Phase 1 — Correctness first.** Collapse the duplicate
   `accounts.balance_cents` writer and the duplicate `getTrialBalance`
   implementation before migrating any bloc.
3. **Phase 2 — Engine readiness audit.** Verify the engine covers every
   bloc field; document any gap as a ticketed extension before Phase 3.
4. **Phase 3 — Pilot on purchase form** (back-office, lower stakes).
   Dual-compute under `kDebugMode`: run both the legacy getters and the
   engine, `assert`-fail if they disagree. Ship; observe; then delete
   the legacy path in a follow-up commit.
5. **Phase 4 — Sale form.** Same pattern as Phase 3 but with explicit
   `_PricingSnapshot` vs `_TenderSnapshot` separation.
6. **Phase 5 — Returns** — consolidate the 4 parallel folds into a single
   rollup helper over `ReturnCalculationService`.
7. **Phase 6 — Commission + loyalty services** — extract from
   `sale_repository_impl.dart`.
8. **Phase 7 — Reporting** — `TrialBalance.totalForType(...)` +
   `LedgerRunningBalance` + `TaxCalculationService.recoverRateBps` +
   `RatioHelper` helpers. ✅ **DONE 2026-05-12** (1996/1996 tests; +31
   helper tests; zero persisted-totals changes; byte-identical to
   legacy on the sweep grids).
9. **Phase 8 — Lints / hooks** — ban the old patterns by regex so they
   cannot return.
10. **Phase 9 — Docs** — close the ADR with an "as-built" retrospective.

## 5. Consequences

### Positive

- Pricing correctness becomes a property of *one* file tree, not of every
  form bloc / preview widget / PDF builder.
- The "1% per-item ≠ 1% overall" class of bugs is impossible once all
  callers use the engine.
- Reasoning about rounding is localised to `Money.round(mode)`.
- Persisted invoice totals (`sales.total_cents` / `purchases.total_cents`)
  are provably equal to what any consumer would re-compute today.

### Negative / costs

- One-time migration cost across `sale_form_bloc.dart`,
  `purchase_form_bloc.dart`, `purchase_form_screen.dart`,
  `sale_form_dialogs.dart`.
- A transient *dual-compute* phase in debug builds slightly increases
  per-render CPU; reverted at the end of each migration phase.

### Guarded by

- `test/golden/pricing/**` — characterisation snapshots.
- `test/core/pricing/**` — engine unit + property tests.
- `test/features/{sales,purchases}/*_adj_return_*_parity_test.dart` —
  already in place for the adj-return blocs.

## 6. Non-goals

- This ADR does **not** change journal-entry schemas, return posting rules,
  loyalty math, or commission math. Those are addressed by subsequent
  ADRs.
- This ADR does **not** introduce a production "shadow mode". The drift
  detection mechanism is `kDebugMode`-gated `assert`s, appropriate for an
  offline, single-developer build.

---

## 7. As-built status (closure 2026-05-12)

All ten phases delivered. Net test delta: **1874 → 2027 (+153)**. Zero
persisted-total semantic changes. Zero unintentional rounding changes.
Every banned legacy pattern is now mechanically enforced by
`test/architecture/scattered_patterns_guard_test.dart`.

| Phase | Title                                       | Status | Verification |
|-------|---------------------------------------------|--------|--------------|
| 0     | Safety net (goldens + property tests + ADR) | DONE   | 39 goldens + properties + parity |
| 1     | Stop-the-bleeding (single-writer invariants) | DONE   | 1892/1892 + static guard |
| 2     | Engine readiness audit                      | DONE   | ADR 0002 (mapping + Q-log closure) |
| 3     | Pilot: `purchase_form_bloc` → engine        | DONE   | 1901/1901 + 9 regression |
| 4     | `sale_form_bloc` → engine + pricing/tender split | DONE | 1915/1915 + 14 regression |
| 5     | Return-form rollup + dual-compute removal   | DONE   | 1927/1927 + 12 regression |
| 6     | Extract `CommissionService` + `LoyaltyPointsService` | DONE | 1965/1965 + 38 service tests |
| 7     | Reporting consolidation (4 new helpers)     | DONE   | 1996/1996 + 31 helper tests |
| 8     | Lints & tooling enforcement                 | DONE   | 2027/2027 + 28 guard + 9 parser tests |
| 9     | Documentation closeout                      | DONE   | this revision + ADR 0003 retrospective |
| 11    | Compliance hardening (post-closeout)        | DONE   | 2053/2053 + 26 Phase-11 tests (see §8) |

### Final single-writer matrix (write-side mutation SoTs)

| Domain                                              | Sole writer                                                   |
|-----------------------------------------------------|---------------------------------------------------------------|
| `accounts.balance_cents`                            | `AccountingRepository._updateAccountBalance` (via `createJournalEntry`) |
| `customers.balance_cents`                           | `BalanceService.adjustCustomerBalance`                        |
| `suppliers.balance_cents`                           | `BalanceService.adjustSupplierBalance`                        |
| Opening-balance party adjustments                   | `Customer/SupplierRepository.adjustOpeningBalance`            |
| Invoice pricing totals (sale + purchase)            | `InvoicePricingEngine.compute`                                |
| Line-level pricing totals                           | `LineItemPricingEngine.compute`                               |
| Return-line proportional reversals                  | `ReturnCalculationService.computeProportionalReturn`          |
| Return-rollup aggregates                            | `ReturnCalculationService.aggregate`                          |
| `commissions` rows                                  | `CommissionService`                                           |
| `loyalty_point_transactions` + `customers.loyalty_points_balance` | `LoyaltyPointsService`                          |
| `products.stock_quantity` / `product_variants.stock_quantity` | `StockService`                                      |
| `product_batches.remaining_quantity`                | `BatchService`                                                |
| `products.cost_cents` / `product_variants.cost_cents` | `ProductCostService`                                        |
| `customer_credit_notes.balance_cents`               | `CustomerCreditNoteService`                                   |
| Payroll calculation                                 | `PayrollCalculationService`                                   |
| Inventory adjustment value (shrinkage/gain/reval)   | `InventoryAdjustmentService`                                  |

### Final read-side reporting SoTs (no DB mutation)

| Concern                                             | Sole owner                                                    |
|-----------------------------------------------------|---------------------------------------------------------------|
| Account-type signing for reports                    | `TrialBalance.totalForType` / `TrialBalanceItem.naturalBalanceCents` |
| Ledger running-balance loop                         | `LedgerRunningBalance`                                        |
| Tax-rate snapshot recovery                          | `TaxCalculationService.recoverRateBps`                        |
| Ratio / percent display                             | `RatioHelper`                                                 |
| Text → cents (with sign)                            | `MoneyInputParser.parseSignedOrZero`                          |
| Text → cents (magnitude)                            | `MoneyInputParser.parseOrZero` / `parse`                      |
| % ↔ ¢ conversion                                    | `DiscountConverter`                                           |
| Original cost / price / wholesale snapshot          | `OriginalPriceResolver`                                       |

### Enforcement layer

`test/architecture/scattered_patterns_guard_test.dart` codifies six
zero-tolerance pattern bans plus a one-way-shrinking allow-list. Any
regression of a closed invariant fails CI on first push.

See also:

- `docs/adr/0002-engine-readiness-audit.md` — phase-2 field-by-field mapping.
- `docs/adr/0003-retrospective.md` — what worked, what we'd do differently.
- `docs/SOURCE_OF_TRUTH_MAP.md` — visual SoT diagram (Mermaid).
- `progress.txt` — append-only decision log of every phase.

---

## 8. Phase 11 — Compliance hardening (post-closeout)

After the Phase 9 closeout an external architectural review identified
15 alleged gaps. Code-level verification reduced that list to **3
genuine, small-surface, high-ROI gaps**; the remaining 12 were either
already implemented (fiscal-period service, RBAC, backup/restore, audit
log, multi-currency schema, encryption, reactive Drift streams) or
inapplicable to the offline single-tenant deployment model (idempotency
layer, sync conflict resolution, distributed event bus, external-API
ACL). Phase 11 closes the 3 real gaps — and only those 3 — under the
same YAGNI / single-writer doctrine as Phases 0–9.

### Sub-phase grid

| Sub-phase | Title                                                   | Status | Verification |
|-----------|---------------------------------------------------------|--------|--------------|
| 11.1      | Wire `FiscalPeriodService.assertOpen` into generic JE   | DONE   | 6 tests — `test/integration/phase11_1_fiscal_period_je_guard_test.dart` |
| 11.2      | Engine-version + tax-inclusive + rounding-mode snapshot | DONE   | 9 tests — `test/integration/phase11_2_pricing_snapshot_stamping_test.dart` |
| 11.3a     | Single-currency invariant in `createJournalEntry`       | DONE   | 4 tests — `test/integration/phase11_3a_single_currency_invariant_test.dart` |
| 11.3b     | Granular accounting permissions                         | DONE   | 7 tests — `test/features/auth/data/services/phase11_3b_granular_accounting_permissions_test.dart` |

### Additions to the SoT matrices

**Write-side (new entries):**

| Domain                                              | Sole owner                                                    |
|-----------------------------------------------------|---------------------------------------------------------------|
| Fiscal-period closure guard on every JE             | `FiscalPeriodService.assertOpen` (called from `AccountingRepository.createJournalEntry`) |
| Pricing-engine version / tax-inclusive / rounding-mode header snapshot | `PricingSnapshot` + `withPricingSnapshot(taxInclusive:)` extension (single helper used by all 6 header tables) |
| Single-currency invariant on JE lines               | `AccountingRepository.createJournalEntry` (rejects mixed-currency entries before transaction opens) |
| Granular accounting permissions (void JE, close/reopen period) | `Permissions.voidJournalEntry`, `Permissions.closeFiscalPeriod`, `Permissions.reopenFiscalPeriod` |

### Schema change

Migration **10053 → 10054** adds three nullable columns to the six
header tables (`sales`, `purchases`, `sale_returns`, `purchase_returns`,
`sale_return_adjustments`, `purchase_return_adjustments`):

- `pricing_engine_version  TEXT`
- `tax_inclusive_at_post   INTEGER (0/1)`
- `rounding_mode_at_post   TEXT`

Columns are nullable so every pre-Phase-11.2 row reads back as `NULL`
— no rewrite of history, no semantic change. New rows are always
stamped via `withPricingSnapshot(...)`.

### Constraints honoured (zero-regression discipline)

- No engine API change.
- No persisted-totals semantic change.
- No rounding-behaviour change.
- No new banned legacy patterns required (Phase 11 is additive — it
  introduces new invariants rather than reshaping old code).

### YAGNI gates explicitly held

Items deliberately **not** done in Phase 11, and the trigger that
would re-open them:

| Deferred | Re-open trigger |
|----------|-----------------|
| Idempotency / `processed_operations` table | Network-sync layer is added (no replay risk today). |
| Domain-event bus | Third-party integration (Shopify, banks) requires fan-out. |
| Multi-currency FX gain/loss accounts | Product decision to support more than one currency per book. |
| Inventory reservation system | Quotations / pending-invoice feature is greenlit. |
| Fractional quantities | Selling by weight/length is greenlit. |
| External-API anti-corruption layer | First external integration is scoped. |

### Verification

- `flutter analyze --no-pub` — 0 issues.
- Full suite — **2053 / 2053 ✓** (+26 from Phase-9 close at 2027).
- Each sub-phase was test-gated **before** the next began (same
  cadence as Phases 0–9).

---

## 9. Phase 12 — Void integrity hardening (2026-05-13)

### Trigger

Field report on backup `tapix_backup_20260513_121448.db`:

- Reconciliation screen flagged `AR mismatch (GL=45997 vs customers=68994)`
  and `Inventory mismatch (GL=153450 vs Σstock×cost=138600)` — exactly
  `22997` AR drift and `−14850` inventory drift.
- User report: "adjustment returns again allow returning more than was
  ever sold/purchased; voiding an invoice silently corrupts the books".

### Three root causes (all upstream, all in existing SoTs)

| # | SoT file | Bug |
|---|----------|-----|
| **R1** | `lib/core/database/daos/adjustment_return_dao.dart` (`getCustomerProductPurchasedQty`, `getCustomerProductReturnedQty`, `getSupplierProductSuppliedQty`, `getSupplierProductReturnedQty`) | Cap queries did not filter by `sales.status='completed'` / `purchases.status='posted'`, so voided & draft documents inflated the "ever sold/purchased" totals. The unlinked-return form happily accepted return quantities greater than what was physically delivered. |
| **R2** | `lib/core/database/daos/sale_dao.dart::voidSale` & `purchase_dao.dart::voidPurchase` | The cascade flipped linked `sale_returns` / `purchase_returns` rows to `'voided'` but never asked `JournalEntryService` to reverse the corresponding posted JE. Result: the return's GL leg stayed posted while the parent's leg was reversed → the exact `22997` AR drift and `−14850` inventory drift seen in the field backup (sale#3 INV-202605-0003). |
| **R3** | `sale_repository_impl.dart::voidSale` & `purchase_repository_impl.dart::voidPurchase` | No pre-flight integrity check. A user could void an invoice that already had unlinked adjustment returns FIFO-allocated against its lines. Voiding orphaned the allocations (the items disappeared from the cap, but the GL/stock impact remained). |

### Fixes (additive, single-source-of-truth, no scattered code)

| Fix | SoT | Δ |
|-----|-----|---|
| **A** Status filter on the four cap queries | `adjustment_return_dao.dart` | +13 lines (4 `..where(...status.equals('posted'/'completed'))` clauses) |
| **B** Cascade-void of linked-return JEs | `sale_dao.voidSale` + `purchase_dao.voidPurchase` (optional `JournalEntryService` param threaded from repo → datasource → DAO) | ~50 lines |
| **C** New SoT `VoidImpactAnalyzer` | `lib/core/services/void_impact_analyzer.dart` | 443 lines (read-only, side-effect-free) |
| **D** Repository pre-flight guard + `VoidBlockedByImpactException` | `sale_repository_impl.voidSale` + `purchase_repository_impl.voidPurchase` | ~30 lines (analyzer call + throw on `hasBlockers`) |
| **E** Shared UX surface `VoidImpactDialog` | `lib/core/widgets/void_impact_dialog.dart` + 3-language i18n (`void_impact.*` + missing `sales.void_failed_title` / `voided_success`) | 280 lines |
| **F** Detail screens consume the dialog | `sale_detail_screen.dart` + `purchase_detail_screen.dart` | ~80 lines |
| **G** Regression test pack | `test/integration/void_corruption_regression_test.dart` | 624 lines / 8 tests pinning Fix A, B, and C across both sides |

### Schema change

**None.** All four counters (`qty_returned_linked`, `qty_returned_adjustment`
on `sale_items`/`purchase_items`) already existed and were already the
atomic SoT for "what came back". Phase 12 just teaches the cap and the
void path to read them honestly.

### Constraints honoured

- No engine API change.
- No persisted-totals semantic change.
- No rounding-behaviour change.
- No new banned legacy patterns.
- Existing tests adjusted only where they relied on the buggy default
  (`adjustment_return_dao_history_test.dart` now seeds purchases as
  `'posted'`, matching the production lifecycle).

### YAGNI gates explicitly held

| Deferred | Re-open trigger |
|----------|-----------------|
| Domain-event bus for void cascades | Third-party integration that needs fan-out (covered by Phase 11 gate). |
| Per-line auditable allocation table linking each `sale_return_adjustment_item` to the exact `sale_item` rows it consumed | A regulator requires per-allocation traceability, or FIFO-reversal-on-void is requested. The analyzer's product-level entanglement check is sufficient for the current pre-flight UX. |
| Automatic re-creation of orphaned adjustment returns when their parent sale is voided | User research shows the manual "void adjustment return → void sale" loop is too painful. |

### Verification

- `flutter analyze --no-pub` — **0 issues**.
- Full suite — **2093 / 2093 ✓** (+40 from Phase 11: +32 from regression pack and migrated edge cases, +8 net new gates).
- DB diagnostic on `tapix_backup_20260513_121448.db` reproduced the
  `22997` AR drift and `−14850` inventory drift; the regression suite
  fails on the pre-fix DAOs and passes on the post-fix DAOs.
- `_bmad-output/PHASE_0_AUDIT_REPORT.md` and reconciliation screen are
  the field-side telemetry that triggered Phase 12; future drifts will
  surface there first by design.


---

## 10. Phase 14 — Cheque lifecycle (minimal-risk slice, 2026-05-17)

### Trigger

Field question: do all six invoice/return flows that can be paid by
cheque surface reminders in the dashboard, and can the user confirm
collection / payment in a way that persists across devices and
reinstalls?

The audit revealed two structural gaps:

1. Linked sale-returns and linked purchase-returns paid by cheque
   were invisible to the dashboard reminder feed — they had a
   `refund_method` column but no `due_date`, and the dashboard UNION
   did not read them.
2. The "Confirm Collected" button on the existing reminder card
   wrote dismissals to `SharedPreferences`, so state was lost on
   reinstall, was not auditable, and was not synchronised across
   devices.

### Scope chosen — Minimal-Risk

Closes both gaps **without touching journal-entry policy**. The full
IAS 7 / QuickBooks-style two-step cheque JE pipeline (Dr `1020 Cheques
in Hand` on issue → Dr `1010 Bank` on clear, symmetric on the
outgoing side via `2030 Cheques Issued`) is intentionally deferred —
see YAGNI gates below.

### Changes

#### Schema — migration 10055 → 10056 (additive, idempotent)

- New table `cheque_confirmations` with natural key
  `(source_table, source_id)` UNIQUE, lifecycle column `status ∈
  {confirmed, bounced, cancelled}`, optional `bounce_reason`, audit
  timestamps, and `user_id` FK.
- New nullable column `sale_returns.due_date`.
- New nullable column `purchase_returns.due_date`.
- Indexes on `cheque_confirmations(status)` and
  `cheque_confirmations(source_table)`.

#### Single sources of truth (added to §7 of this ADR by reference)

| Concern | SoT |
|---|---|
| Cheque confirmation state (DB-authoritative) | `ChequeConfirmationDao` |
| Linked return cheque due date | `sale_returns.due_date`, `purchase_returns.due_date` |
| Dashboard cheque feed (six sources UNION) | `ChequeRemindersSection` |

#### Wire-up

- `SaleRepository.createSaleReturn` and `PurchaseRepository.createPurchaseReturn`
  gained an additive `DateTime? dueDate` parameter (default `null`,
  back-compat for every existing caller).
- `SaleReturnFormBloc` and `PurchaseReturnFormBloc` gained a `dueDate`
  state field, a `*DueDateChanged` event, and the form-level invariant
  `isChequeMissingDueDate` which gates the submit button.
- Form screens render `_buildChequeDueDatePicker` only when the
  selected refund method is cheque.
- `ChequeRemindersSection` was rewritten end-to-end:
  - reads `ChequeConfirmationDao.watchAllAsMap()` alongside the
    six-source cheque UNION;
  - splits the card into two grouped lists ("Cheques to collect" /
    "Cheques to pay");
  - each row exposes a primary action (Confirm Collected / Confirm
    Paid) and an overflow (Mark Bounced, Cancel Cheque);
  - bounce dialog captures a nullable `bounce_reason`;
  - filters out resolved rows where `status IN ('confirmed','cancelled')`.

#### Tests (+17 net)

- `test/core/database/daos/cheque_confirmation_dao_test.dart` (13).
- `test/integration/cheque_reminder_six_sources_test.dart` (4).
- Schema-version pins bumped 10055 → 10056 in
  `production_hardening_test.dart` and `fifo_phase_6_4_test.dart`.

### Invariants pinned

- Every cheque-bearing source row (six tables) has a `due_date`
  populated when its payment / refund method is `cheque`.
- Confirmation state is DB-authoritative — no `SharedPreferences`
  reads or writes anywhere in the cheque path.
- The dashboard UNION reads exactly the six canonical source tables,
  filters on `status NOT IN ('voided','draft')`, and joins
  `cheque_confirmations` by natural key `<source_table>|<source_id>`.

### YAGNI gates explicitly held (deferred, NOT killed)

| Deferred | Re-open trigger |
|----------|-----------------|
| Full cheque JE engine (Dr `1020` on issue → Dr `1010` on clear; mirror `2030` outgoing) | Field reconciliation report showing the current single-step JE materially overstates `1010 Bank` at any reporting boundary, OR auditor request for IAS 7 conformance. |
| Dedicated `/cheques` register screen (QuickBooks-style) | Field user requests historical browsing or bank-rec workflow. |
| Cheque-number / bank / branch / account-no capture | The JE engine lands and these columns become part of that same migration. |
| Bounce-fee bank-charges JE | The JE engine lands. |
| Replace-cheque workflow (old → new linked) | The JE engine lands. |
| Backfill of pre-existing dismissals from `SharedPreferences` | Never. Old dismissals were never authoritative state; users will see the relevant cheques reappear on first launch and can re-confirm them. |

### Verification

- `flutter analyze --no-pub` — **0 issues**.
- Full suite — **2131 / 2131 ✓** (+17 from Phase 13 close at 2114).
- No persisted-totals semantic change.
- No rounding-behaviour change.
- No JE policy change (existing Dr/Cr `1010` direct posting preserved).

---

## 11. Phase 15 — Cheque lifecycle JE wiring + batch-ledger valuation (2026-05-18)

### Trigger

Field report on backup `tapix_backup_20260518_011740.db` (schema 10056):

1. **P0 — cheque confirmation with no GL effect.** User confirmed a
   `cheque`-method purchase (`PO-202605-0002`, total 59394¢) via the
   dashboard "Confirm Paid" button. The `cheque_confirmations` row
   was written (`status='cleared'`), but `purchase_payments` was
   empty, `purchases.paid_amount_cents` stayed at 0,
   `supplier_transactions` had no payment row, and
   `suppliers.balance_cents` remained 360364 instead of the correct
   300970. The full 59394¢ AP liability was never extinguished.
   Root cause: `ChequeConfirmationDao.confirm()` only writes the
   lifecycle sidecar — it was never wired to call
   `PurchaseRepository.recordPayment` / `JournalEntryService`. Phase 14
   explicitly deferred this wiring; Phase 15 closes the gap.

2. **P1 — false 990¢ inventory drift on Reconciliation & Health.**
   The health-check formula computed Σ(stock × variant.cost_cents)
   against `GL(1200)`. For FIFO / batch / batch_expiry products,
   `variant.cost_cents` holds the *display value* (latest paid unit
   cost from `ProductCostService`), not the per-layer accounting
   basis. Two batches of variant 1 (10 units @ 9900¢ + 3 units @
   9801¢) have a true FIFO value of 128403¢, but the formula
   computed 13 × 9801 = 127413¢ — 990¢ short — matching exactly the
   false positive on the screen.

### Two root causes

| # | SoT file | Bug |
|---|----------|-----|
| **R1** | `ChequeConfirmationDao.confirm` (Phase 14 deliberate deferral) | Wrote only the lifecycle row; never delegated to the payment repository. The AP balance, GL, and supplier-transaction ledger were untouched. |
| **R2** | `JournalLocalDatasourceImpl.getTotalInventoryValueCents` | Used `variant.stock_quantity × variant.cost_cents` for ALL costing methods. For FIFO/batch products `cost_cents` is a display snapshot, not a per-layer basis — the batch ledger (`product_batches.remaining_quantity × unit_cost_cents`) is the authoritative accounting value. |

### Fixes (additive, single SoT, zero scattered code)

| Fix | SoT | Δ |
|-----|-----|---|
| **A** Schema — migration 10056 → 10057 | `cheque_confirmations.cleared_payment_id` nullable INT column | ~20 lines (table, companion, migration) |
| **B** New orchestrator `ChequeLifecycleService` | `lib/core/services/cheque_lifecycle_service.dart` | ~420 lines. Three public methods: `markCleared`, `markBounced`, `markCancelled`. Each is a single Drift transaction: calls `repo.recordPayment` / `repo.deletePayment` for invoice sources, skips payment logic for return sources (refund JE already posted at return-time), then calls `ChequeConfirmationDao.confirm`. Stores `cleared_payment_id` on clear; NULLs it on bounce/cancel. |
| **C** Dashboard widget | `ChequeRemindersSection` — action handlers replaced to go through `ChequeLifecycleService` | ~120 lines changed |
| **D** DI registration | `injection_container.dart` — `ChequeLifecycleService` registered as lazy singleton after sale/purchase repositories | 14 lines |
| **E** Inventory valuation formula | `JournalLocalDatasourceImpl.getTotalInventoryValueCents` — 3-branch COALESCE SQL | ~70 lines — branch 1: active `product_batches` sum for the variant; branch 2: `variant.stock × variant.cost_cents` fallback; branch 3: `product.stock × product.cost_cents` for products with no variants and no batches |
| **F** i18n | `en.json` / `ar.json` / `fr.json` — 5 new `dashboard.cheque_*` snackbar keys + `done_editing` | 5 keys × 3 languages = 15 rows |

### Schema change

Migration **10056 → 10057** (additive, idempotent):

```sql
ALTER TABLE cheque_confirmations
  ADD COLUMN cleared_payment_id INTEGER;
```

Nullable — NULL for every pre-Phase-15 row and for return-source
confirmations. Populated with the `purchase_payments.id` or
`sale_payments.id` created by the lifecycle service on `→ cleared`
for invoice-source cheques.

### Additions to the SoT matrices

**Write-side (new entries):**

| Domain | Sole owner |
|--------|------------|
| Cheque lifecycle transitions that change books (cleared / bounced / cancelled) | `ChequeLifecycleService.markCleared` / `markBounced` / `markCancelled` — the DAO `ChequeConfirmationDao.confirm` MUST NOT be called directly from UI |
| `cheque_confirmations.cleared_payment_id` | `ChequeLifecycleService` — written on `→ cleared`, NULLed on `→ bounced` / `→ cancelled` |

**Read-side (updated entry):**

| Concern | Sole owner |
|---------|------------|
| Inventory Σ(stock-at-cost) for GL reconciliation | `JournalLocalDatasourceImpl.getTotalInventoryValueCents` — 3-branch formula; branch 1 (active batches) is authoritative for FIFO/batch/batch_expiry; branches 2–3 are WAC/simple fallbacks |

### Constraints honoured

- No engine API change.
- No persisted-totals semantic change.
- No rounding-behaviour change.
- No new banned legacy patterns in `scattered_patterns_guard_test.dart`
  (Phase 15 is additive; it introduces new paths rather than closing
  old ones).
- Existing Phase 14 `ChequeConfirmationDao` contract unchanged —
  `ChequeLifecycleService` wraps it; the DAO test suite still passes.

### YAGNI gates explicitly held

| Deferred | Re-open trigger |
|----------|-----------------|
| Two-step IAS 7 cheque pipeline (`1020 Cheques in Hand` → `1010 Bank`; `2030 Cheques Issued`) | Field cash-flow statement compliance requirement or auditor request. |
| Bounce-fee bank-charges JE (`5100 Expenses`) | User request to track bounce fees per supplier. |
| Replace-cheque workflow | User request to issue a replacement cheque linked to the bounced one. |
| Per-cheque metadata (cheque number, bank, branch, account) | Regulatory print requirement or e-invoicing schema. |
| Historical drift reconciliation for pre-Phase-15 DBs | Data-free: re-open Reconciliation & Health (formula fix) + re-confirm the cheque (lifecycle service records the missing payment atomically). No DB sweep required. |

### Verification

- `flutter analyze --no-pub` — **0 issues**.
- Full suite — **2153 / 2153 ✓** (+22 from Phase 14.2 close at 2131).
- No persisted-totals semantic change.
- No rounding-behaviour change.
- No engine API change.

### Regression tests (+22 net from Phase 14.2)

| File | Count | What is pinned |
|------|-------|----------------|
| `test/core/services/cheque_lifecycle_service_test.dart` | 9 | Settlement on `→ cleared` (purchase + sale), idempotency, return-source no-payment, `cleared → bounced` reversal, `cleared → cancelled` reversal, `pending → bounced` no-reversal, empty-reason guard, missing-source exception |
| `test/integration/inventory_valuation_batch_ledger_test.dart` | 5 | FIFO multi-batch field case (128403¢), WAC variant fallback, no-variant fallback, inactive-batch exclusion, mixed-mode sum |
| Schema-version pins | 2 | `production_hardening_test.dart` + `fifo_phase_6_4_test.dart` bumped 10056 → 10057 |
