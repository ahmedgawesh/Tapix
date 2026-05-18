# Phase 0 — Audit Report (Tapix v1.0 Pre-Launch)

**Date:** 2026-05-13
**Scope:** 7 sub-audits to validate or refute the 10 commercial gaps identified in
`tapix-v1-final-roadmap-e443aa.md` before committing engineering effort.
**Method:** read-only exploration — `code_search`, `grep`, file inspection. No
production code touched.

---

## Executive Summary (TL;DR)

| Area | Status | Surprise |
|------|--------|----------|
| WAC architecture | ✅ Well-isolated, refactor-safe | Better than feared |
| AccountingRepository merge | ✅ Phase 11 complete, no bypass | Cleaner than expected |
| Manual JE form | ❌ Confirmed missing | Bloc explicitly read-only |
| Schema version | ✅ 10054, ready for 10055-10070 | As documented |
| Reports inventory | ✅ 36 reports already, 1 IFRS gap | **Massive** surprise |
| RevenueCat / License system | ✅ **Already fully wired** | Huge time-saver |
| Crashlytics | ⚠️ Wired but **missing GDPR opt-in** | New high-priority gap |

**Net effect on Phase 1 plan:**

- **Removed 2 gaps** (G2 Chart-of-Accounts editor exists; AccountingRepository merge already complete).
- **Downscoped 1 gap** (G7 VAT — line-item tax reports exist, need only jurisdiction-form templates).
- **Added 2 NEW gaps**: G11 (GDPR Crashlytics opt-in), G12 (Windows desktop license validator).
- **Phase 1 estimate revised**: 10-12 weeks → **8-10 weeks** (CoA + merge work removed).

---

## A0.1 — WAC Recalculation Risk Audit

### Findings

The Weighted-Average Cost architecture is the **single biggest technical concern**
for any future fractional-quantity migration. After tracing every cost write:

**Single Source of Truth (SoT):** `lib/core/services/inventory/product_cost_service.dart`
holds 4 sanctioned writers:

- `applyPurchaseCostToVariant` — moving WAC blend on purchase
- `applyPurchaseCostToProduct` — non-variant equivalent
- `setVariantCost` / `setProductCost` — direct overwrite (revaluation)
- `syncProductFromVariants` — true weighted average across variants

**Quantity types — ALL `int`:**

- `beforeQty`, `addedQty`, `quantityDelta` → `int`
- SQL aggregation: `SUM(cost_cents * stock_quantity)` (integer multiplication)
- Final formula: `(beforeCost*beforeQty + newCost*addedQty) / totalQty`, rounded to int cents

**Strategy interface:** `lib/core/services/inventory/costing_strategy.dart` — pluggable
`CostingStrategy` (WAC + FIFO via batches). Production already uses it correctly.

### Risk Assessment for fractional quantities (Track C — DEFERRED)

| File | Change required | Risk |
|------|-----------------|------|
| `product_cost_service.dart` | int → Decimal/Rational throughout | Medium |
| `purchase_dao.dart` (postPurchase, voidPurchase) | quantity types | Medium |
| `sale_dao.dart` (consumeFifo blend) | division rounding semantics | Medium |
| `inventory_adjustment_service.dart` | quantityDelta validation | Low |
| `batch_service.consumeFifo` | per-layer fractional consumption | High |
| Schema: `stock_quantity INTEGER` columns | migration 10070+ | High |

**Verdict:** WAC is **refactorable but expensive**. Touching 6-8 files + a schema
migration on int→Decimal columns. Consistent with the original plan to defer Track C
to v2.x. **No work needed in v1.0.**

### Hidden positive

The `ProductCostService` migration (per memory `cc8912a1`/`8d813897`) already
fixed the buggy `MAX(cost)` aggregation pattern. The hard work is done. Future
fractional migration just needs type-widening + math review, not a rebuild.

---

## A0.2 — AccountingRepository ↔ JournalRepository Merge Gap

### Findings

**Verdict:** ✅ **No critical merge gap.** Phase 11 closed it cleanly.

`lib/features/accounting/data/repositories/journal_repository_impl.dart`
delegates **every write** to `AccountingRepository`:

```@/home/ahmed/AhmedF/tapix projects/tapix/lib/features/accounting/data/repositories/journal_repository_impl.dart:188-195
      ],
    );

    return _accountingRepo.createJournalEntry(
      entryData: entryData,
      userId: createdBy,
    );
  }
```

Same pattern for `postJournalEntry` (line 215) and `voidJournalEntry` (line 240).

### `AccountingRepository.createJournalEntry` guards confirmed in place

- Double-entry validation (debits == credits)
- ≥ 2 lines required
- **Single-currency invariant** (Phase 11.3a) — line 234-242
- Control account protection (1100 AR, 2000 AP — only system entry types) — line 246-257
- Closed-period lock (`accounting_periods` table) — line 261
- Fiscal-period guard (`fiscal_periods` + `FiscalPeriodService`) — line 271
- Atomic transaction wrapping — line 274

### Minor exposure (non-blocking)

`AccountingDao.createJournalEntry(JournalEntriesCompanion)` is a raw insert that
bypasses validations. Currently only used internally by Drift codegen and
read-side wrappers. **Recommendation:** add a `@protected` / package-private marker
or doc comment in Phase 1 prep.

---

## A0.3 — Manual JE Form Gap

### Findings — CONFIRMED REAL GAP

`lib/features/accounting/presentation/bloc/journal_entry_form_bloc.dart` is
**explicitly read-only**:

```@/home/ahmed/AhmedF/tapix projects/tapix/lib/features/accounting/presentation/bloc/journal_entry_form_bloc.dart:6-9
/// Events for JournalEntryFormBloc (read-only — no manual entry creation)
abstract class JournalEntryFormEvent extends RealtimeEvent {
  const JournalEntryFormEvent();
}
```

```@/home/ahmed/AhmedF/tapix projects/tapix/lib/features/accounting/presentation/bloc/journal_entry_form_bloc.dart:29-31
/// Bloc for viewing journal entry details (read-only — no manual creation)
class JournalEntryFormBloc extends RealtimeBloc<JournalEntryFormData, JournalEntryFormEvent> {
  final JournalRepository _repository;
```

Screens in `lib/features/accounting/presentation/screens/`:

- `journal_entries_list_screen.dart` (list view)
- `journal_entry_detail_screen.dart` (detail/post/void only)

**No** `journal_entry_form_screen.dart` for creation. **G1 stands.** Phase 1.1 will
build the create-flow on top of the existing `AccountingRepository.createJournalEntry`
contract — the backend is fully ready.

---

## A0.4 — Schema Baseline Freeze

### Findings

```@/home/ahmed/AhmedF/tapix projects/tapix/lib/core/database/app_database.dart:856-858

  @override
  int get schemaVersion => 10054;
```

### Reservations for Phase 1

| Version | Feature | Sub-phase |
|---------|---------|-----------|
| **10054** | (current) Pricing snapshot stamping | Phase 11.2 (closed) |
| 10055 | (reserved) Manual JE metadata | Phase 1.1 |
| 10056 | (reserved) Chart of Accounts UX polish | Phase 1.2 (likely no schema change) |
| 10057 | (reserved) GL Opening Balances Wizard | Phase 1.3 |
| 10058 | (reserved) Bank Reconciliation tables | Phase 1.4 |
| 10059 | (reserved) Fixed Assets + Depreciation tables | Phase 1.5 |
| 10060 | (reserved) Year-End Closing + Notes to FS | Phase 1.8 |
| 10061-10064 | (reserved) Phase 1 buffer | — |
| 10065-10069 | (reserved) Phase 2 if needed | — |
| 10070+ | (reserved) Phase 4 regional editions | ZATCA/ETA |

**Rule:** sequential, no skipping, no reuse. Each migration must include `up()`
SQL + idempotency check + test.

---

## A0.5 — Existing Reports Inventory

### Findings — MASSIVE pleasant surprise

**36 reports already exist** in `lib/features/reports/presentation/screens/`. The original
plan assumed many were missing.

### IFRS-SME Core Statements

| Statement | Status | File |
|-----------|--------|------|
| Trial Balance | ✅ | `trial_balance_screen.dart` |
| Profit & Loss | ✅ | `profit_loss_screen.dart` |
| Balance Sheet | ✅ | `balance_sheet_screen.dart` |
| General Ledger | ✅ | `general_ledger_screen.dart` |
| **Cash Flow Statement** | ❌ | **MISSING — G6 stands** |
| Notes to Financial Statements | ❌ | MISSING — G8 stands |

### Auxiliary Reports — all present

- Customer Aging, Customer Statement, Customer Sales, Customer Ledger, Customer Analysis (5 reports)
- Supplier Aging, Supplier Statement, Supplier Balance, Supplier Ledger, Supplier Credit Balance, Supplier Debit Balance, Supplier Balance Drilldown, Supplier Analysis (8 reports)
- Sales Report, Sales Tax Report, Sales Reports Hub
- Purchase Report, Purchase Tax Report, Purchase Reports Hub
- Inventory Reports, Product Movement Detail, Product Variant Movement, Category Movement, Expiry Report
- Profit Report, Profit Reports Hub, Discount Report, Discount Reports Hub
- Expense Report, Salesperson Commission Report
- Customer Returns Reports, Customer Payment Reports
- Accounting Health Screen (integrity dashboard)

### Tax Reports — partially present

- ✅ `sales_tax_report_screen.dart` — line-by-line VAT collected
- ✅ `purchase_tax_report_screen.dart` — line-by-line VAT paid
- ❌ **No jurisdiction-specific VAT Return forms** (Egypt VAT, KSA VAT, UAE VAT, EU VAT)

### G7 (VAT Returns) — DOWNSCOPED

The data layer is done. Phase 1.7 only needs **printable form templates** matching
each jurisdiction's official format. Likely 1 week, not 2.

---

## A0.6 — RevenueCat Configuration Audit

### Findings — Fully wired with sophisticated guard architecture

This was the biggest positive surprise. Not just a `pubspec` entry — a complete
3-tier guard system:

**1. `lib/core/services/revenuecat_service.dart`**

- Singleton `RevenueCatService` with init, configure, listener
- API key: `goog_bmcvleZZMqUhtEkYvqaknUJRzvB` (Android only — iOS key TBD)
- Products: weekly / monthly / yearly / **lifetime** (4 tiers!)
- Entitlement: `'pro'`
- `Purchases.configure(...)` invoked at startup
- `Purchases.setLogLevel(LogLevel.debug)` in debug mode

**2. `lib/core/services/license_service.dart`**

- Device-bound license: `DeviceLicense` with fingerprint, expiry, offline period
- Signed local storage via `flutter_secure_storage`
- Last-online-validation timestamp tracked

**3. `lib/core/services/app_guard_service.dart`**

- Orchestrator: User Account → Subscription → Device License → Offline Usage
- Online path: validate via RevenueCat, refresh license
- Offline path: validate fingerprint + expiry + offline grace
- Auto-revalidates on connectivity restore
- Listens to RevenueCat customer-info stream

**4. `main.dart`** — `SubscriptionBloc` started with `SubscriptionStartGuard` event

### Platform coverage

| Platform | Status |
|----------|--------|
| Android | ✅ Fully supported (`goog_` API key) |
| iOS | ⚠️ API key not configured (RevenueCat supports it, just needs iOS key) |
| Web | ❌ Skipped (RevenueCat doesn't support) |
| Windows / macOS / Linux | ❌ **NOT covered** — `RevenueCatConfig.isSupported = isAndroid \|\| isIOS` |

### NEW gap discovered: G12

**Windows desktop subscription validator.** RevenueCat ends at Android+iOS. For
Windows distribution (Microsoft Store + sideload), need a separate path:

- **Option A:** Microsoft Store IAP (12% rev share, native to MS Store)
- **Option B:** Paddle/Stripe + activation key (works for sideload too)
- **Option C:** Defer Windows monetization to v1.1 (free tier only on desktop)

**Recommendation:** Phase 2.3 will add this. The existing `LicenseService` +
`AppGuardService` are reusable — just need a desktop-specific
`SubscriptionValidator` impl.

---

## A0.7 — Crashlytics Wiring Audit

### Findings

**Wiring: ✅** `lib/main.dart:46-74` initializes Crashlytics, hooks
`FlutterError.onError`, `PlatformDispatcher.onError`, and `runZonedGuarded` —
textbook complete.

```@/home/ahmed/AhmedF/tapix projects/tapix/lib/main.dart:46-62
    // Initialize Crashlytics
    final crashlytics = CrashlyticsService.instance;
    await crashlytics.initialize();

    Bloc.observer = SimpleBlocObserver();

    // Flutter framework errors
    FlutterError.onError = (details) {
      LoggingService.error(
        'FlutterError.onError',
        error: details.exception,
        stackTrace: details.stack,
      );
      // Report to Crashlytics
      crashlytics.recordFlutterFatalError(details);
      FlutterError.presentError(details);
    };
```

### NEW gap discovered: G11 — GDPR Opt-in

`lib/core/services/crashlytics_service.dart:42-45` hardcodes auto-collection ON:

```@/home/ahmed/AhmedF/tapix projects/tapix/lib/core/services/crashlytics_service.dart:42-45
    _crashlytics = FirebaseCrashlytics.instance;

    // Enable automatic crash collection in release mode
    await _crashlytics!.setCrashlyticsCollectionEnabled(true);
```

**Problem:** EU GDPR requires explicit user consent BEFORE telemetry collection
begins. This single hardcoded `true` would block App Store + Google Play approval
for the EU market.

**Fix (Phase 2.4):**

1. Default `setCrashlyticsCollectionEnabled(false)`
2. Add a settings toggle (`AppSettingsBloc` extension)
3. First-run consent screen — explain Crashlytics, default OFF, opt-in checkbox
4. Persist choice; only enable collection after consent

This is a **HIGH priority** — without it, EU launch is blocked.

---

## Risk Register

| # | Risk | Severity | Phase | Mitigation |
|---|------|----------|-------|-----------|
| R1 | GDPR Crashlytics opt-in missing | **HIGH** | Phase 2.4 | G11 — default off + consent toggle |
| R2 | Windows monetization gap | MEDIUM | Phase 2.3 | G12 — desktop license validator |
| R3 | iOS RevenueCat key not configured | MEDIUM | Phase 2.3 | Add iOS API key to `RevenueCatConfig` |
| R4 | Manual JE form missing | MEDIUM | Phase 1.1 | G1 — build form on existing repo |
| R5 | Cash Flow Statement missing | MEDIUM | Phase 1.6 | G6 — IFRS report |
| R6 | Bank Reconciliation missing | MEDIUM | Phase 1.4 | G4 — full feature |
| R7 | Fixed Assets missing | MEDIUM | Phase 1.5 | G5 — full feature |
| R8 | VAT Return forms missing | LOW | Phase 1.7 | G7 — templates only |
| R9 | Year-End closing UI missing | LOW | Phase 1.8 | G8 — UI only, repo has `closeAccountingPeriod` |
| R10 | WAC fractional-qty migration | LOW (deferred) | v2.x | Track C — explicitly out of v1.0 |

---

## Updated Phase 1 Plan (post-audit)

### Removed / downscoped

- ~~G2 Chart of Accounts editor~~ → **EXISTS** (`chart_of_accounts_screen.dart`).
  Phase 1.2 reduced to **2-3 days UX polish** (remove dev-password unlock gating,
  add validation guard rails).
- ~~AccountingRepository merge work~~ → **NOT NEEDED** (Phase 11 complete).
- G7 VAT Returns: data exists, only need 4 jurisdiction-form PDF templates → **1 week**.

### New gaps to integrate

- **G11** — GDPR Crashlytics opt-in (Phase 2.4) — 2-3 days
- **G12** — Windows desktop license validator (Phase 2.3) — 1 week

### Updated estimates

| Phase | Original | Revised |
|-------|----------|---------|
| Phase 0 (Audit) | 1 week | ✅ Complete (this report) |
| Phase 1 (Accounting) | 10-12 weeks | **8-10 weeks** (CoA + merge removed, VAT downscoped) |
| Phase 2 (Commercial) | 8-10 weeks | **9-11 weeks** (G11 + G12 added) |
| Phase 3 (Beta + Launch) | 4-6 weeks | unchanged |
| **Total to v1.0** | 23-29 weeks | **22-28 weeks** |

---

## Go / No-Go Decisions for Phase 1

| Sub-phase | Decision | Justification |
|-----------|----------|---------------|
| 1.1 — Manual JE Form (G1) | ✅ **GO** | Backend ready, only UI work. Read-only bloc → upgrade to write. |
| 1.2 — CoA editor polish | ✅ **GO (downscoped)** | Already works, needs UX cleanup. |
| 1.3 — Opening Balances Wizard (G3) | ✅ **GO** | Customer/supplier opening balances exist; need GL-level wizard. |
| 1.4 — Bank Reconciliation (G4) | ✅ **GO** | Full feature build. Schema 10058. |
| 1.5 — Fixed Assets (G5) | ✅ **GO** | Full feature. Depends on 1.1 (manual JE for adjustments). |
| 1.6 — Cash Flow Statement (G6) | ✅ **GO** | Reporting only, no schema change. Indirect method. |
| 1.7 — VAT Returns (G7) | ✅ **GO (downscoped)** | Data exists; build 4 PDF templates. |
| 1.8 — Year-End Closing + Notes (G8) | ✅ **GO** | `closeAccountingPeriod` repo method exists; needs UI + Notes authoring. |

---

## Recommended Next Action

Start **Phase 1.1 — Manual Journal Entry Form**.

**Why first:**

1. Unblocks Phase 1.5 (Fixed Assets needs manual JE for depreciation
   adjustments).
2. Smallest scope (UI + bloc upgrade), validates the Phase 1 dev rhythm.
3. `AccountingRepository.createJournalEntry` is fully ready — zero backend risk.
4. Closed-period guard + control-account protection + fiscal-period guard all
   already enforced. The form only needs to construct `JournalEntryData` and
   call the existing repo.

**Estimated:** 5-7 days (form + bloc upgrade + 4-6 tests + e2e flow).

---

## Files Touched in Phase 0

**Read-only:** No production files modified. Only this audit report
(`_bmad-output/PHASE_0_AUDIT_REPORT.md`) was created.

## Phase 0 Verification Commands

```bash
# Re-confirm schema baseline
grep -n "schemaVersion" lib/core/database/app_database.dart

# Re-confirm RevenueCat platform support
grep -n "isSupported" lib/core/services/revenuecat_service.dart

# Re-confirm Crashlytics opt-in gap
grep -n "setCrashlyticsCollectionEnabled" lib/core/services/crashlytics_service.dart

# Re-confirm Manual JE bloc is read-only
grep -n "read-only" lib/features/accounting/presentation/bloc/journal_entry_form_bloc.dart

# Re-confirm AccountingRepository delegation
grep -n "_accountingRepo.createJournalEntry" lib/features/accounting/data/repositories/journal_repository_impl.dart
```

---

**Phase 0 status:** ✅ COMPLETE.
**Next gate:** user approval to proceed to Phase 1.1.
