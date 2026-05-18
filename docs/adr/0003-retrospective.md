# ADR 0003 — Scattered-Calculation-Logic Migration · Retrospective

- **Status:** Accepted — May 2026 (closeout)
- **Scope:** Whole-program retrospective on the 10-phase migration described
  by [`0001-pricing-engines-as-sot.md`](0001-pricing-engines-as-sot.md) and
  the engine readiness audit in
  [`0002-engine-readiness-audit.md`](0002-engine-readiness-audit.md).
- **Audience:** Future maintainers and AI agents working on tapix's
  calculation core.

---

## 1. Outcome at a glance

| Metric | Before migration | After Phase 9 |
|---|---|---|
| Total green tests | 1874 | **2027** (+153) |
| Distinct writers of `accounts.balance_cents` | 2 | **1** |
| Distinct writers of `customers/suppliers.balance_cents` | 4 paths | **1 service** |
| Pricing math implementations in form layer | 4 (sale + purchase × line + invoice) | **0** |
| Commission + loyalty math sites in `sale_repository_impl.dart` | 4 private methods | **0** (extracted) |
| Trial-balance writers | 2 | **1** |
| `getTrialBalance` implementations | 2 | **1** |
| Inline `(double * 100).round()` text→cents sites | 14 | **0 unguarded** (ratchet allow-list = 11, shrinking) |
| `runningBalance += amount` duplicates | 6 | **0** |
| Account-type signing duplicates | 12 across screens | **0** (helper-driven) |
| `bps / 100` inline display sites | ~5 | **0** |
| Pricing engine has dual-compute drift in dev assertions | yes | **0** ever observed |
| Persisted-totals semantic changes | n/a | **0** (every phase audited) |

No production rollback was required at any phase.

---

## 2. What worked

### 2.1 Tests-first and goldens-as-oracle

Phase 0 wrote characterisation goldens *against the existing bloc math*
before any production code moved. Every subsequent phase had a
zero-tolerance regression net. When a deliberate behaviour change
(e.g. fixed-discount clamping in Phase 3/4) needed to land, it was
visible in the diff and gated by an explicit ADR-approved decision.

**Lesson:** A characterisation golden is cheaper than a post-hoc bug
hunt by an order of magnitude. The 39 goldens caught two near-misses
before they merged.

### 2.2 Bottom-up phasing (kernels → engines → services → DAOs → consumers)

We resisted ChatGPT's instinct to start at `sale_form_bloc.dart` (the
highest-stakes file in the POS). The bottom-up approach paid off:

1. Layer 0 primitives (`Money`, `MoneyInputParser`) were already
   correct; we just had to enforce consumption.
2. Layer 1 engines (`InvoicePricingEngine`, `LineItemPricingEngine`)
   existed and were correct; the migration was glue, not calculation.
3. Layer 2 services needed extraction for commission + loyalty, but the
   pattern was already proven by `BalanceService` / `StockService`.
4. Only after layers 0–2 were locked did we touch the blocs.

**Lesson:** When a refactor touches "every formula in the codebase",
fixing the foundation first turns the user-facing layer into a
mechanical rewrite, not a calculation re-derivation.

### 2.3 Engine-readiness audit (Phase 2)

Phase 2 was pure documentation — no code. It produced
`docs/adr/0002-engine-readiness-audit.md`: a field-by-field map of
`{Sale,Purchase}FormState` → engine output. It uncovered three subtle
gaps before Phase 3:

- Q2: Loyalty redemption ≠ pricing (contra-AR settlement under IFRS 15).
- Q3: Discount-mode exclusivity means engine and bloc bases agree
  even though their formulas look different.
- G7: A small adapter (`toPricingInput()` extension) bridges the
  discount mode without engine changes.

**Lesson:** A capability audit before a calculation migration is worth
its weight in postmortems-avoided.

### 2.4 `kDebugMode` dual-compute (not shadow mode)

We rejected ChatGPT's "production shadow mode" proposal as overkill for
a single-developer offline app. Instead, each phase ran the legacy and
the engine paths *side by side under `kDebugMode`* and asserted
equality. Zero drift observed across Phases 3, 4, 5. Scaffolds were
removed in Phase 5 once confidence was established.

**Lesson:** Right-size the safety mechanism to the runtime profile. We
saved every drop of build / runtime overhead a production shadow would
have cost.

### 2.5 Pricing / Tender separation in Phase 4

Loyalty redemption was the headline confusion: legacy code treated it
as a discount; GAAP/IFRS 15 treats it as settlement. The Phase 4 split
made this explicit at the API level:

```dart
late final InvoicePricingResult pricing;   // SoT, revenue-recognition
int get totalCents => max(0, pricing.total.decimalCents
                              - loyaltyDiscountCents);  // tender
```

After the split, `sales.total_cents` is **provably** post-loyalty and
`pricing.total` is **provably** the pre-loyalty revenue-recognition
figure, both with zero possibility of confusion at call sites.

**Lesson:** When two concerns share a number-line they need different
names. Don't overload one field with two meanings.

### 2.6 Single static-guard test instead of analyzer plugins

A custom `analyzer` plugin would have given us cleaner editor
underlines but cost a build dependency and a maintenance lifecycle. The
plain Dart `test/architecture/scattered_patterns_guard_test.dart`:

- Scans `lib/**/*.dart` with comments stripped (so prose can't trip
  regexes).
- Six pattern guards, two tiers (zero-tolerance and shrinking
  ratchet allow-list).
- Runs in <1 second on the existing test infrastructure.

**Lesson:** When the rule surface is small (~10 patterns), one
characterisation-style test is more robust than introducing a build-
time tool with its own configuration drift.

### 2.7 Largest-remainder allocation (`Money.allocate`)

Replacing `~/` (floor-division) with `Money.allocate` in
`CommissionService.reverseForReturn` mathematically guarantees that
the sum of partial reversals can never exceed the original commission.
Same applies to engine-level proration. This is IFRS-aligned and
matches QuickBooks / SAP behaviour.

**Lesson:** Floor division as a proration strategy is almost always
wrong. Default to largest-remainder unless you can articulate a
business reason to prefer truncation.

---

## 3. What surprised us

### 3.1 Engine gaps were all *adapter* gaps, never *math* gaps

The Phase 2 audit identified 7 candidate gaps (G1–G7). Five of them
collapsed into "wrap the input in `Discount.percent(bps)` at the bloc
boundary". Two were one-line conversions
(`Money.fromCents(d.toBigInt().toInt())`). Zero required new engine
math.

### 3.2 `(double * 100).round()` was *byte-identical* on real inputs

The IEEE-754 risk we feared (e.g. `99999.99 * 100 → 9999998.999...`)
was theoretically valid but extremely rare for operator-entered data.
The migration produced **zero observed cent drift** on existing
recorded transactions during dev testing. We migrated anyway —
correctness invariants should be invariants by construction, not by
empirical luck.

### 3.3 The duplicated `getTrialBalance` was a *classification fork*

Both implementations were correct on the happy path but diverged on
unknown account types. Consolidating to one writer normalised the
fallback to "treat as debit-natural" (the safe default).

### 3.4 Adjustment-return DAO had inline tax-rate recovery

`taxRateBps = (taxOnLine * 10000 / subtotal).round()` was buried in a
DAO. It's the only place outside `TaxCalculationService` that performs
a tax-shape calculation. Phase 7 added `recoverRateBps` so the DAO
became a consumer; the 49-cell parity sweep proved byte-identity.

---

## 4. What we'd do differently

### 4.1 Start the SoT map earlier

[`SOURCE_OF_TRUTH_MAP.md`](../SOURCE_OF_TRUTH_MAP.md) was a Phase 9
artefact. It would have saved an hour of "where does this calculation
live?" during Phases 3–6 if it had existed in Phase 1.

**Action for future migrations:** Generate the SoT skeleton at Phase 0
(it's mostly the layer-2 service list anyway). Fill in the columns as
the migration progresses.

### 4.2 Capture the allow-list rationale inline, not in commit messages

Phase 8's Tier-2 ratchet allow-list carries per-entry comments. Earlier
phases relied on commit messages for "why is this still here?"
explanations. Comment-as-rationale wins every time.

### 4.3 The Phase-1 deprecation throw-pattern was scarier than necessary

`updateCustomerBalance` / `updateSupplierBalance` were marked
`@Deprecated` *and* made to throw `StateError` if called outside
`BalanceService`. The throw caught one regression in tests but no
production callers ever survived to hit it. A pure `@Deprecated` with
the guard test would have been simpler.

### 4.4 We under-tested the rare-currency path

`MoneyInputParser` is currency-aware (3-digit JOD/KWD/BHD/OMR, 0-digit
JPY/KRW/IQD), but our golden tests focused on 2-digit currencies. The
parser unit tests were extended in Phase 8.C, but we could have caught
edge cases earlier with explicit currency-matrix tests in Phase 0.

---

## 5. Process meta-observations

### 5.1 Phase length

The phases ranged from 1 session (Phase 2 docs) to several sessions
(Phase 6 service extraction). The dual-compute scaffolds let phases
land in independently revertible commits; the 10-phase plan was the
right granularity.

### 5.2 Decision log (`progress.txt`)

A flat, append-only file outperformed inline code comments for cross-
phase context. Future migrations should keep this artifact.

### 5.3 ADR cadence

Three ADRs across nine phases (0001 master plan, 0002 readiness audit,
0003 this retrospective). One ADR per architectural decision is enough;
do not document mechanical refactors as ADRs.

### 5.4 AI-pair-programming pattern

Each phase started with a written plan ("what I will and will not
touch"), executed in narrow batches, ended with a verification report
listing test count delta. This kept the user's review burden bounded
and made rollback impossible to confuse.

---

## 6. Recommended hooks for the next migration

1. **Always start by writing characterisation tests** against current
   behaviour, even if you "know" the answer.
2. **Identify writers before readers.** Concentrate single-writer
   invariants in Phase 1; everything else gets easier.
3. **A capability-audit ADR before any consumer migration.** It is
   cheap, exposes hidden contracts, and gives reviewers a checklist.
4. **Use `kDebugMode` dual-compute as the safety net** for any
   migration that changes a hot calculation path; do not pay for
   production shadow mode.
5. **Lock the invariant the moment you close it.** A static-guard
   test takes 5 minutes to write and prevents months of regression
   work.
6. **Use largest-remainder allocation** (`Money.allocate`) by default
   for any proration. Floor-division proration is almost always wrong.
7. **Document the SoT map and the banned patterns in the
   integrity-guidelines doc.** New contributors and AI agents will
   read this first.
8. **Treat every field bug as a diagnose-before-touch event.** Phase 12
   (the void-integrity hardening) confirmed that the only safe path
   when the user reports an accounting drift is: (a) reproduce the
   exact numbers on the supplied backup with raw SQL, (b) walk the
   journal-entries table to find the offending source, then (c) fix
   *upstream* in the existing SoT. The Phase 12 backup `tapix_backup_20260513_121448.db`
   surfaced three root causes within minutes by following this script;
   each fix was 10–50 lines.
9. **Every cascade must own both sides of the books.** When a parent
   void cascades into a child (linked return → cascade-voided), the
   *same transaction* must reverse the child's journal entry too.
   Otherwise you flip a status flag while leaving a posted GL leg
   orphaned. Lesson learned in Phase 12 (root cause #2 of the
   `22997` / `-14850` drift): never let a status flip and a GL
   reversal be in different procedure scopes. The DAO now takes
   `JournalEntryService?` as a first-class collaborator.
10. **A pre-flight `…ImpactAnalyzer` SoT pays for itself.** World-class
    tools (NetSuite, SAP, Odoo, QuickBooks) never let a destructive
    operation proceed without showing the user the full GL/stock
    delta. In Tapix this is now a tiny pattern: a read-only service
    plus a single shared dialog widget. Repeat the pattern for any
    future destructive op (refund, period close, mass delete, etc.)
    rather than scattering ad-hoc checks across screens.
11. **The atomic counter is the contract.** When `qty_returned_linked`
    and `qty_returned_adjustment` already existed on `sale_items` /
    `purchase_items`, the right fix for Phase 12 was *not* to add new
    tracking, but to teach the existing readers to honour them
    (status filter + cascade-aware void). Resist the urge to bolt on
    a new table whenever a bug surfaces — first prove the existing
    SoT cannot answer the question.

12. **When dismissal-style UX state is written outside the DB
    (`SharedPreferences`, in-memory caches, file system), treat it as
    a hidden source of truth that will silently drift.** The Phase 14
    cheque audit found a `SharedPreferences`-backed "Confirm
    Collected" button that disappeared on reinstall and was never
    auditable. The cure is the standard one: a small DAO with a
    natural key over the existing source rows. Resist adding a
    "cheques" master table until JE policy forces it — the
    confirmation layer alone closes the field-visible bug.

13. **Whenever a feature has six or more equivalent source flows
    (cheques: sale, purchase, two linked returns, two adjustment
    returns), pin the UNION with a single integration test that
    asserts one row from each branch surfaces.** Drift in this kind
    of feed is otherwise invisible until a user reports a missing
    reminder weeks later.

---

## 7. References

- [`0001-pricing-engines-as-sot.md`](0001-pricing-engines-as-sot.md) — master plan + final status.
- [`0002-engine-readiness-audit.md`](0002-engine-readiness-audit.md) — field mapping.
- [`../SOURCE_OF_TRUTH_MAP.md`](../SOURCE_OF_TRUTH_MAP.md) — visual SoT map.
- [`../ACCOUNTING_INTEGRITY_GUIDELINES.md`](../ACCOUNTING_INTEGRITY_GUIDELINES.md) — developer rules.
- `../../progress.txt` — append-only decision log of every phase.
- `../../test/architecture/scattered_patterns_guard_test.dart` — enforcement.
