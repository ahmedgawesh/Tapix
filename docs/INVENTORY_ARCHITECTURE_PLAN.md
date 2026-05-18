# Two-Layer Inventory Architecture — Implementation Plan

> **Status:** Done (Phases A–I complete; Phase J in progress for closing-doc updates only).
> **Started:** 2026-04-28
> **Phase G completed:** 2026-04-29
> **Phase I completed:** 2026-05-03
> **Owner:** Engineering
> **Schema baseline (now):** v10047
> **Companion design doc:** [`docs/INVENTORY_ARCHITECTURE.md`](./INVENTORY_ARCHITECTURE.md)

## Executive summary

Tapix is moving from a **per-product FIFO/WAC** choice (which conflates two
unrelated concerns) to a **two-layer model** that mirrors world-class ERPs
(Odoo, SAP B1, NetSuite, Cin7):

| Layer | Concern | Scope |
|-------|---------|-------|
| **Layer 1 — Cost Valuation** | How do we value inventory in the books? | **Global** (one method per business) |
| **Layer 2 — Inventory Tracking** | Do we track this product as discrete batches with expiry? | **Per-product** |

This separation:
* Aligns with IAS 2 / ASC 330 *consistency principle* (one valuation method).
* Enables **FEFO** (First-Expired-First-Out) consumption for pharmacies /
  groceries / cosmetics — orthogonal to valuation.
* Removes ~70% of `if (isFifo)` branches across the codebase.
* Is what every audit-grade ERP does.

## Domain glossary

* **Cost valuation method** — how `cost_cents` and COGS are computed.
  * `wac` (Weighted Average Cost): the running blended cost.
  * `fifo` (First-In-First-Out): COGS = oldest batch's frozen unit cost.
  Choosing once per business is what IAS 2 §36 requires.

* **Inventory tracking type** — whether a product needs batch-level books.
  * `standard`     — single pool of stock; no batches; cheapest path.
  * `batch`        — every purchase creates a batch (lot); FIFO consumption.
  * `batch_expiry` — batch + expiry date; **FEFO** consumption + alerts.

* **FEFO** — First-Expired-First-Out. A *removal strategy*, not a valuation
  method. It is what pharmacies, food retailers and chemical stores need.
  Already implemented inside `BatchService.consumeFifo` via the SQL
  `ORDER BY (expiry_date IS NULL) ASC, expiry_date ASC, received_date ASC`.

## Current state (pre-refactor)

* `products.costing_method` (`wac` | `fifo`) — per-product, conflates the two
  concerns above.
* `BatchService` already orders consumption by expiry first → physical FEFO
  works today, just gated on `costing_method='fifo'`.
* `product_batches.expiry_date` exists; UI to enter it lives in
  `purchase_form_screen.dart` (lines ~2278-2313).
* `_ExpiryInfoWidget` exists on the product form.
* `ProductCostService` (created in the prior session) is the single writer
  for `cost_cents`.

This means the *physics* of the new design already work; we are mostly
**renaming, gating and documenting** rather than rebuilding.

## Target state

```
                        ┌────────────────────────────────────┐
   Settings → Accounting│  inventoryValuationMethod          │
                        │  ◉ Weighted Average  (default)     │
                        │  ◯ FIFO                            │
                        │  [Locked once any movement exists] │
                        └────────────────────────────────────┘
                                       │
                                       ▼
       ┌─────────────────────────────────────────────────────────┐
       │                  PurchaseDao.postPurchase                │
       │   reads valuation method from InventoryValuationService  │
       │   reads tracking type from products.inventory_tracking   │
       └─────────────────────────────────────────────────────────┘
                                       │
        ┌──────────────────────────────┼──────────────────────────────┐
        ▼                              ▼                              ▼
   tracking=standard              tracking=batch              tracking=batch_expiry
   (mug, t-shirt)                 (canned food, lots)         (medicines, dairy)
   ──────────────                 ──────────────              ───────────────────
   ProductCostService             ProductCostService           ProductCostService
   .applyPurchaseCost             .applyPurchaseCost           .applyPurchaseCost
   per global method              per global method            per global method
                                  + create batch              + create batch
                                                              + REQUIRE expiry_date
                                                              + emit expiry alert
                                                                eligibility
```

```
                       ┌────────────────────────────────┐
                       │      SaleDao.postSale          │
                       └────────────────────────────────┘
                                       │
        ┌──────────────────────────────┼─────────────────────────────┐
        ▼                              ▼                             ▼
   tracking=standard              tracking=batch              tracking=batch_expiry
   COGS = product.cost_cents      BatchService                BatchService
   (current value)                .consumeFifo                .consumeFifo
                                  (oldest received first)     (nearest expiry first
                                                               = FEFO, automatic)
```

## Migration strategy (10046 → 10050+)

We do **NOT** drop `products.costing_method` immediately. We follow the
"expand → migrate → contract" pattern used by professional schema migrations:

| Schema | Step |
|--------|------|
| **10047** | Add `products.inventory_tracking_type` (`standard`/`batch`/`batch_expiry`). Backfill from `costing_method`: `wac` → `standard`, `fifo` → `batch_expiry` if any batch has `expiry_date`, else `batch`. |
| **10048** | Add `app_settings` row `'inventory_valuation_method'`. Backfill from majority vote of `products.costing_method`. |
| **10049** | Stop reading `products.costing_method` from runtime code (still readable via DB browser). |
| **10050+** (future release) | Drop `products.costing_method` column once telemetry confirms zero reads for ≥ 30 days. |

Rollback paths:
* Phases A-D are additive: rolling back means ignoring the new fields, not
  reverting destructive change. `costing_method` keeps working.
* If a phase reveals a critical issue, the global setting can be flipped to
  match the legacy majority and the per-product flag re-enabled in code.

## Phase plan

| Phase | Goal | Risk | Status |
|-------|------|------|--------|
| **A** | Global valuation method (Settings + Service + reads) | Low | ✅ done |
| **B** | `inventory_tracking_type` column + migration + DAO writes | Medium | ✅ done |
| **C** | UI: Product form + Purchase form expiry validation | Medium | ✅ done |
| **D** | Sale flow gates on tracking type, not costing method | Medium | ✅ done |
| **E** | Expiry alerts dashboard, badge, dedicated report | Medium | ✅ done |
| **F** | Cleanup: remove per-product FIFO/WAC selector from UI; deprecate column | Low | ✅ done (UI removed; column kept one release for offline-installed apps) |
| **G** | Tests (FEFO property tests, expiry edge cases) + final docs | Low | ✅ done |
| **H** | Audit/transparency: `BatchAuditDao` + product *Batches* tab + sale-detail flow + standalone Batch Management screen | Medium | ✅ done |
| **I** | Production hardening: status guards (I1), expiry-date freeze (I2), invariant checks on every batch-mutating path (I4), edge-case tests (I3) | High | ✅ done |
| **J** | Closing documentation: §11 (FEFO verification), §12 (Returns reference), plan finalised | Low | 🚧 in progress |

### Phase A — Global valuation method (in progress)

**Out:**
1. New file `lib/core/services/inventory/inventory_valuation_method.dart` —
   sealed enum with `.wac` / `.fifo`, plus `fromKey` / `toKey`.
2. New file `lib/core/services/inventory/inventory_valuation_service.dart` —
   reads/writes/watches the global method via `SettingsDao`. Caches on
   first read; emits via `Stream` for BLoC consumers.
3. Wire it into `injection_container.dart`.
4. Add `inventoryValuationMethod` field to the `AppSettings` SharedPreferences
   entity for UI binding (Settings screen toggles it).
5. Refactor every reader of `products.costing_method` (purchase_dao,
   sale_dao, adjustment_return_dao, inventory_adjustment_service) to:
   * Read the **global** method as the *primary* signal.
   * Fall back to the per-product flag only if migration not yet run.
6. Settings UI: a new "Inventory Valuation" section with a `SegmentedButton`
   matching the existing UX of `tax_settings_section.dart`.
7. Tests (in `test/core/services/`):
   * Default value is `wac` on a fresh install.
   * Setting is persisted across restarts.
   * Once any sale or purchase exists, the service refuses to change without
     an admin-reason payload.

**Acceptance:**
* All 1592 tests still pass.
* New tests assert: posting a purchase reads the global method (not the
  per-product flag) when `Settings.useGlobalValuation == true`.
* No behaviour change for users who keep the global default == their old
  product-level majority.

### Phase B — Inventory tracking type column

**Out:**
1. New migration `10047`:
   ```sql
   ALTER TABLE products ADD COLUMN inventory_tracking_type TEXT NOT NULL
     DEFAULT 'standard';
   UPDATE products SET inventory_tracking_type =
     CASE
       WHEN costing_method = 'fifo' AND EXISTS (
         SELECT 1 FROM product_batches b
         WHERE b.product_id = products.id AND b.expiry_date IS NOT NULL
       ) THEN 'batch_expiry'
       WHEN costing_method = 'fifo' THEN 'batch'
       ELSE 'standard'
     END;
   ```
2. Add `inventoryTrackingType` to the `Products` Drift table.
3. Add helpers `ProductDao.getInventoryTrackingType(int productId)` and
   `setInventoryTrackingType(...)` with the same lock semantics as the
   current `setCostingMethod` (locked once batches exist).
4. Refactor batch creation gates:
   * `purchase_dao.postPurchase` → create batch when
     `inventoryTrackingType != 'standard'` (was `costing_method == 'fifo'`).
   * `adjustment_return_dao` and `inventory_adjustment_service` likewise.
5. Refactor sale-time gate:
   * `sale_dao` → consume from batches when
     `inventoryTrackingType != 'standard'`. Cost source is then the batch's
     frozen `unit_cost_cents` regardless of global valuation method (matches
     SAP and Odoo: when batches exist, batches are the truth).

**Acceptance:**
* No row in `products` has both `costing_method='wac'` and stock in
  `product_batches` after migration.
* All FIFO tests pass with `inventoryTrackingType='batch'`.
* New unit tests for the migration backfill rules.

### Phase C — UI for tracking type + expiry validation

**Out:**
1. Replace the `_buildCostingMethodSelector` in `product_form_screen.dart`
   with `_buildInventoryTrackingSelector`:
   * Three segments: Standard / Batch / Batch + Expiry.
   * Show explanatory help text for each (Arabic + English + French).
   * Lock with same rule (`'has_stock'` / `'has_consumptions'`).
2. In `purchase_form_screen.dart` `_ItemEditSheet`:
   * Make `expiryDate` **required** when the product's tracking type is
     `batch_expiry`.
   * Show clear validation message; disable confirm button until set.
3. New product list badge:
   * Yellow "near-expiry" pill when any batch will expire ≤ 30 days.
   * Red "expired" pill when any batch has `expiry_date < today` and
     `remaining_quantity > 0`.

### Phase D — Sale flow gates

**Out:**
1. `sale_dao.postSale`:
   * Replace `costingMethod == 'fifo'` check with
     `inventoryTrackingType != 'standard'`.
   * COGS = `Σ batch.unit_cost_cents × qty consumed` for batched products.
   * Else COGS = `cost_cents × qty` from variant or product (current path).
2. `adjustment_return_dao` / `inventory_adjustment_service` — mirror.

### Phase E — Expiry alerts

**Out:**
1. New service `lib/core/services/inventory/expiry_alert_service.dart` with
   queries for:
   * Items expiring in ≤ N days (default 30/60/90 buckets).
   * Items already expired but with `remaining_quantity > 0`.
2. Dashboard widget showing top 5 with link to a full report.
3. New report screen `lib/features/reports/presentation/screens/expiry_report_screen.dart`.
4. Optional Phase E.1: scheduled local notification (Android/iOS) when a
   product enters the 30-day window.

### Phase F — Cleanup

**Out:**
1. Remove the FIFO/WAC selector widget from `product_form_screen.dart`.
2. Remove `costingMethod` from `ProductFormState` and the BLoC's events.
3. Mark `Products.costingMethod` Drift column as
   `// DEPRECATED — kept for one release for offline-installed-apps safety`.
4. Remove the `ProductDao.getCostingMethodLockReason` /
   `setCostingMethod` methods (or keep stubs that delegate to tracking type).

### Phase G — Tests + docs

**Out:**
1. Property tests for FEFO consumption ordering (random batches with random
   expiry dates → expiring batches always go first).
2. Property tests for batch invariants under all valuation × tracking
   combinations.
3. New `docs/INVENTORY_ARCHITECTURE.md` describing the final design.
4. Update `docs/architecture.md` to point to the inventory chapter.

### Phase H — Audit / transparency surfaces

The system is correct (Phases A–G). Phase H makes that correctness
**visible** to operators and auditors without giving them edit power.
Everything in this phase is read-only by construction —
`BatchAuditDao` never mutates state; all writes still flow through
`BatchService`.

**Out:**

1. **H1 — `BatchAuditDao`** (`lib/core/database/daos/batch_audit_dao.dart`).
   Hand-rolled `customSelect` queries (no `@DriftAccessor`) covering:
   * `watchBatchesForProduct(productId, [variantId, includeDepleted])`
     — FEFO-ordered list with supplier/variant JOINs.
   * `getConsumptionsForBatch(batchId)` — full IN/OUT ledger of one
     batch, each row resolved to a friendly reference label
     (`INV-…`, `SR-…`, `ADJ-…`) via the `_kRefSelect` / `_kRefJoins`
     LEFT-JOIN chain across 8+ tables.
   * `getBatchFlowForSale(saleId)` — per-sale-line reconstruction of
     "where did COGS come from?". Nets partial-return IN rows so the
     report shows the *net* COGS still recognised.
   * `getConsumptionsForSaleItem(saleItemId)` — debug helper used by
     the manual verification workflow described in
     `INVENTORY_ARCHITECTURE.md §11`.
   Tests in `test/core/database/daos/batch_audit_dao_test.dart`.

2. **H2 — Product detail "Batches" tab.** New widget
   `BatchesSectionWidget` rendered inside `product_form_screen.dart`
   under the existing expiry info widget. Self-contained
   `StreamBuilder` over `watchBatchesForProduct`; lazy-loads each
   batch's consumption ledger on expansion via
   `getConsumptionsForBatch` and re-fetches when remaining quantity
   changes (cache key = `(batchId, remainingQuantity)`).

3. **H3 — Standalone Batch Management screen** at `/reports/batches`.
   Cross-product FEFO-ordered listing with filter chips for source
   (`purchase`/`opening`/`found`/`sale_return`), expiry bucket
   (matching `ExpiryAlertService` cadence: `none`/`expired`/`≤30`
   /`≤60`/`≤90`), free-text search across product name + SKU + batch
   number, and a `Show depleted batches` toggle. Each row opens a
   bottom-sheet drill-down that reuses `BatchConsumptionList` (the
   same widget the H2 tab uses) so both surfaces render identical
   ledger rows. Linked from the Reports hub.

**Acceptance:**
* Auditor can open ANY product / batch / sale and reconstruct COGS
  end-to-end without leaving the app.
* Identical numbers between the *Batches* tab, the Batch Management
  screen, and the existing Expiry report (single SQL owner per
  surface — no parallel implementations).
* `flutter analyze` clean. `flutter test test/core/database/daos/batch_audit_dao_test.dart`
  passes (13 tests including the 6 H3-specific filter cases).

### Phase I — Production hardening

Phase I tightens every still-open footgun before declaring the
inventory subsystem audit-grade.

**Out:**

1. **I1 — Status guards on edit/delete-item DAO methods.** All four
   spots that could mutate items on a posted/voided document now
   throw `StateError('I1 violation: …')` at both the repository and
   DAO layers:
   `SaleDao.updateSaleWithItems`, `PurchaseDao.updatePurchaseWithItems`,
   `PurchaseDao.updatePurchaseItem`, `PurchaseDao.deletePurchaseItem`.
   Tests in `test/integration/i1_status_guard_test.dart`.

2. **I2 — Expiry-date freeze.** `BatchService.updateExpiryDate` is
   now the single allowed write path for `product_batches.expiry_date`.
   It refuses any edit after the first `'out'` consumption — re-dating
   a lot whose stock has already moved would silently re-order
   historical FEFO consumptions in audit views (the user must use a
   corrective inventory adjustment instead). Tests in
   `test/core/services/batch_service_update_expiry_test.dart`.

3. **I3 — Edge-case test sweep.** Property + scenario tests covering
   midnight-rollover bucket calculations, partial-return netting,
   void-return-of-void, multi-product batches with mixed `'opening'`
   /`'found'`/`'sale_return'` sources, and the standard-tracked
   fall-back path. Lives across
   `test/integration/production_hardening_test.dart` and the existing
   service-level test files.

4. **I4 — `assertInvariantForProduct` at every batch-mutating path.**
   Every DAO/service method that ends a batch transaction now calls
   `BatchService.assertInvariantForProduct` so any drift in
   `Σ remaining_quantity = stock_quantity` is caught at write time
   rather than days later in an audit report.

**Acceptance:**
* No production code path can mutate a posted/voided sale or purchase
  item, mutate an expiry date after consumption, or commit a
  transaction that breaks I1 — all three throw and roll back.
* Full-suite `flutter test` and `flutter analyze` clean.

### Phase J — Closing documentation

**Out:**
1. **J1 — Architecture doc enriched with audit surfaces** (already
   merged with Phase H1: cross-references to `BatchAuditDao` from
   `INVENTORY_ARCHITECTURE.md §6/§7`).
2. **J2 — Two new sections in the architecture doc** (this commit):
   * `§11 How to verify FEFO manually` — UI walkthrough → SQL
     console → Dart helpers → codified regression tests.
   * `§12 Returns behaviour reference` — symmetric ledger movement
     for sale-return, purchase-return, sale-adjustment-return,
     purchase-adjustment-return, plus the invariants preserved
     across all four shapes.
3. Mark Phase I as done in this plan; flip the document header to
   "Done" once Phase J is merged.

## Audit log requirement

Every change to the global valuation method or a product's inventory tracking
type **MUST** be recorded in the existing `audit_log` table with the user id
and a free-form reason. This is what makes the system audit-ready under
IAS 8 §14 (changes in accounting policies).

## Open questions (deferred until Phase E)

1. Do we expose the *removal strategy* (FEFO vs FIFO) as a separate setting
   like Odoo, or keep it implicit ("FEFO when expiry is tracked, else FIFO")?
   → Recommend implicit for SMB simplicity.
2. Do we support multiple warehouses / locations in v1?
   → Out of scope for this plan. Single-location only.
3. Lot/batch numbers — auto-generated only, or allow user override?
   → Auto-generated already (`BATCH-YYYYMM-PI{n}`); deferred.
