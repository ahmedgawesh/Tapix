# Inventory Architecture — Tapix

> **Status:** Active design (final, post Phase G)
> **Last updated:** 2026-04-29
> **Schema baseline:** v10047
> **Companion documents:** `INVENTORY_ARCHITECTURE_PLAN.md` (rollout history),
> `PRICING_ENGINE.md` (line-level totals), `ACCOUNTING_INTEGRITY_GUIDELINES.md`.

## 1. Overview — the two-layer model

Tapix separates **how inventory is *valued*** from **how stock is *physically
tracked***. This mirrors world-class ERPs (Odoo, SAP B1, NetSuite, Cin7) and
aligns with **IAS 2** / **ASC 330**.

| Layer | Concern | Scope | Source of truth |
|-------|---------|-------|-----------------|
| **1 — Cost Valuation** | What number goes into the books for COGS / inventory? | **Global** (one method per business) | `app_settings.inventory_valuation_method` |
| **2 — Inventory Tracking** | Do we keep batch-level books for this product? | **Per-product** | `products.inventory_tracking_type` |

The **legacy** `products.costing_method` column conflated these two concerns
into a single per-product flag (`wac` / `fifo`). It is preserved for one
release for offline-installed apps and removed from runtime read paths in
Phase D/F.

## 2. Layer 1 — Cost valuation (global)

Stored in `app_settings` under the key `inventory_valuation_method` and read
through `InventoryValuationService`.

| Value | Meaning |
|-------|---------|
| `wac` (default) | Weighted Average Cost — running blended cost recomputed on each receipt. |
| `fifo` | First-In-First-Out — COGS uses each batch's frozen unit cost in receipt order. |

### Lock semantics

`InventoryValuationService.hasPostedTransactions()` reports whether any
posted purchase or sale exists. Once it does, the UI hides the global
toggle. Changing the method after movements is allowed only through a
direct DB intervention with a written audit-log reason — this satisfies
**IAS 8 §14** (changes in accounting policies must be audit-justified).

### Consumers

* `ProductCostService.applyPurchaseCost` — writes `cost_cents` per the
  global method.
* `purchase_dao.postPurchase` — selects between WAC blend and FIFO frozen
  cost using the global flag.
* `sale_dao.postSale` — picks COGS source per Layer 2 (see §3).

## 3. Layer 2 — Inventory tracking (per-product)

Stored in `products.inventory_tracking_type`. Allowed values:

| Value | Behaviour | Use case |
|-------|-----------|----------|
| `standard` (default) | Single pool. No rows in `product_batches`. COGS draws from `cost_cents`. | T-shirts, mugs, services. |
| `batch` | Each purchase line creates a batch (lot). Sales consume oldest received first. | Canned food, building materials. |
| `batch_expiry` | Like `batch`, plus `expiry_date` is **required** at purchase. Sales consume **nearest expiry first** (FEFO). Expiry alerts fire at 30/60/90 days. | Pharmacies, supermarkets, cosmetics. |

### Lock semantics

`ProductDao.getInventoryTrackingTypeLockReason(int productId)` returns:

* `'has_stock'` — current `stock_quantity > 0` for any active variant.
* `'has_consumptions'` — any historical `batch_consumptions` row exists.
* `null` — safe to change.

The product form respects this lock and surfaces a localised explanation
under the segmented selector (`product.tracking_locked_stock` /
`product.tracking_locked_consumptions`).

## 4. Decision matrix (purchase / sale)

```
                     ┌────────────────────────────────────┐
                     │  inventory_valuation_method        │  Layer 1 (global)
                     │  ◉ wac  (default)  ◯ fifo          │
                     └────────────────────────────────────┘
                                      │
                                      ▼
   ┌─────────────────────────────  PURCHASE  ─────────────────────────────┐
   │                                                                      │
   │  inventory_tracking_type      Path                                   │
   │  ───────────────────────      ────                                   │
   │  standard                     ProductCostService.applyPurchaseCost   │
   │                               (per global method)                    │
   │                                                                      │
   │  batch                        ProductCostService.applyPurchaseCost   │
   │                               + BatchService.createBatchFromPurchase │
   │                                                                      │
   │  batch_expiry                 ProductCostService.applyPurchaseCost   │
   │                               + BatchService.createBatchFromPurchase │
   │                               + REQUIRE expiry_date (UI + bloc)      │
   └──────────────────────────────────────────────────────────────────────┘

   ┌─────────────────────────────────  SALE  ──────────────────────────────┐
   │                                                                       │
   │  inventory_tracking_type      Path                                    │
   │  ───────────────────────      ────                                    │
   │  standard                     COGS = cost_cents × qty                 │
   │                                                                       │
   │  batch                        BatchService.consumeFifo (received ASC) │
   │  batch_expiry                 BatchService.consumeFifo (FEFO)         │
   │                               COGS = Σ(batch.unit_cost × take)        │
   └───────────────────────────────────────────────────────────────────────┘
```

## 5. FEFO ordering contract

`BatchService.consumeFifo` orders candidate batches with this exact SQL:

```sql
ORDER BY (expiry_date IS NULL) ASC,
         expiry_date           ASC,
         received_date         ASC,
         id                    ASC
```

Read top-to-bottom this means:

1. Batches with `expiry_date NOT NULL` are consumed **before** any batch
   with `expiry_date IS NULL` (NULLS LAST).
2. Among expiring batches, the **earliest expiry** wins.
3. Tie-breakers in order: `received_date` ASC, then `id` ASC (deterministic).

The contract is exercised by property-style tests in
`test/core/services/batch_service_fefo_property_test.dart`:

* random 12-batch lineup → consumed order must equal the SQL key sort.
* explicit NULL-expiry placement → expiry-bearing batches always go first.
* tied expiry dates → received_date / id tiebreaker.
* Σ(remaining) decrement equals requested quantity exactly.
* `restoreConsumptions` is symmetric: round-trip restores remaining and
  preserves the **frozen** `unit_cost_cents`.
* `BatchInsufficientStockException` is thrown on shortfall, and the
  outer Drift transaction rolls back any partial mutation.

## 6. Invariants enforced by the system

| # | Invariant | Where enforced |
|---|-----------|----------------|
| I1 | `Σ(batch.remaining_quantity WHERE active=1) == variant.stock_quantity` | `BatchService.assertInvariant` (called at end of every batch-mutating DAO transaction) |
| I2 | `batch.unit_cost_cents` is **frozen** after creation (only inventory revaluation touches it) | `BatchService` write paths; revaluation lives in `InventoryAdjustmentDao` |
| I3 | Reversals (`restoreConsumptions`) write a mirrored `'in'` row at the **original** unit cost — never current cost | `BatchService.restoreConsumptions` |
| I4 | A `batch_expiry` product cannot be saved without an `expiry_date` | `purchase_form_bloc._onSubmitted` + `_ItemEditSheet` (UI gate) + plan §C |
| I5 | Σ Dr = Σ Cr per journal entry | `JournalEntryService.validateAndPost` |
| I6 | Layer-1 method change after any posted transaction requires admin override | `InventoryValuationService.setMethod` + audit log |
| I7 | `product_batches.expiry_date` is **frozen** once any `direction='out'` row exists in `batch_consumptions` for that batch | `BatchService.updateExpiryDate` (single allowed write path); throws `BatchExpiryLockedException(reason='has_consumptions')` after first consumption and `reason='inactive'` on voided lots |

Invariant I1 is enforced by two independent layers (added in Phase I — the
hardening pass):

* **Runtime cross-table check:** `BatchService.assertInvariantForProduct`
  is called at the end of every batch-mutating path:
  `SaleDao.{postSale, voidSale, postSaleReturn, voidSaleReturn}`,
  `PurchaseDao.{postPurchase, voidPurchase, postPurchaseReturn, voidPurchaseReturn}`,
  `AdjustmentReturnDao.{post,void}{Purchase,Sale}AdjReturn`, and
  `InventoryAdjustmentService.adjust`. Any silent desync rolls back the
  enclosing Drift transaction with `StateError('BatchService.assertInvariant…')`.
* **Status gating on edit paths:** `SaleDao.updateSaleWithItems`,
  `PurchaseDao.{updatePurchaseWithItems, updatePurchaseItem, deletePurchaseItem}`
  re-check `status ∈ {draft, pending}` inside the DAO so a future caller
  that bypasses the repository-layer guard cannot rewrite items on a
  posted/voided document. Violation throws `StateError('I1 violation: …')`.

## 7. Expiry alerts (Phase E)

* `ExpiryAlertService.fetchAlerts({nearDays: [30,60,90]})` — single SQL pass
  over `product_batches` filtered by `inventory_tracking_type='batch_expiry'`.
* Buckets: `expired`, `≤30d`, `≤60d`, `≤90d`. An item enters at most one
  bucket — the most urgent it qualifies for.
* `ExpiryAlertsBloc` — Realtime bloc consuming `watchAlerts()` for
  reactive dashboard widgets.
* UI: `ExpiryAlertsSection` on the dashboard (top-5 + summary chips) and
  `ExpiryReportScreen` for the full report (filterable by bucket).
* Per-product list badge: amber pill ≤30d, red pill if any expired stock
  remains (`ExpirySummary.statusFor`).

## 8. Migration history

| Schema | Migration |
|--------|-----------|
| 10044 → 10045 | FIFO foundation: `product_batches`, `batch_consumptions` tables. |
| 10046 | Indexes for `product_batches(product_id, variant_id, is_active, remaining_quantity, expiry_date, received_date)`. |
| 10047 | **This architecture.** Adds `app_settings.inventory_valuation_method` (default `'wac'`) and `products.inventory_tracking_type` with a backfill from `costing_method` (`wac` → `standard`, `fifo` + ∃ batch w/ expiry → `batch_expiry`, else `batch`). |
| (future) | Drop `products.costing_method` after 30 days of zero-read telemetry. |

Rollback for Phases A–D: ignore the new columns. The legacy code path
keyed on `costing_method` continues to function until Phase F deletes it.

## 9. Forbidden patterns

```
❌ Reading products.costing_method in new code (Phase D forbids this).
❌ Mutating product_batches.unit_cost_cents outside InventoryAdjustmentDao.
❌ Decrementing stock_quantity without going through StockService.
❌ Posting a sale on a batch_expiry product without consuming via BatchService.
❌ Using product.cost_cents as COGS source when inventory_tracking_type != 'standard'.
❌ Hand-rolling FIFO ordering — always go through BatchService.consumeFifo.
❌ Editing items on a posted/voided sale or purchase. Use void+repost only.
   Tapix has NO in-place edit path for posted documents — all four DAO
   methods (`SaleDao.updateSaleWithItems`, `PurchaseDao.updatePurchaseWithItems`,
   `PurchaseDao.updatePurchaseItem`, `PurchaseDao.deletePurchaseItem`) throw
   `StateError('I1 violation: …')` if invoked on anything other than a
   draft/pending document, both at repository and DAO layers.
❌ Hand-rolling `UPDATE product_batches SET expiry_date = …`. The single
   allowed write path is `BatchService.updateExpiryDate` (Invariant I7).
   It refuses any edit after the first `'out'` consumption — re-dating a
   lot whose stock has already moved would silently re-order historical
   FEFO consumptions in audit views. Use a corrective inventory
   adjustment instead.
```

These are caught by:
* Architecture tests under `test/core/services/`.
* `BatchService.assertInvariantForProduct` called at the end of every
  batch-mutating DAO/service path (Phase I4 — catches I1).
* DAO-level status guards on edit/delete-item methods (Phase I1 — see
  `test/integration/i1_status_guard_test.dart`).
* `BatchService.updateExpiryDate` Invariant-I7 freeze (Phase I2 — see
  `test/core/services/batch_service_update_expiry_test.dart`).
* `flutter analyze` (caught the legacy `costingMethod` reads removed in Phase F).

## 10. References

* IAS 2 — Inventories (cost formulas §25–§27, consistency §36).
* ASC 330 — Inventory.
* IAS 8 §14 — Changes in accounting policies require justification.
* Odoo 17 docs — *Inventory Valuation* and *Removal Strategies* (the
  conceptual basis for our two-layer split).
* SAP Business One — *Item Master Data → Inventory tab → Valuation Method*.

## 11. How to verify FEFO manually

Phase H (audit/transparency) gave the system three read-only surfaces that
mirror the same SQL the sale path uses, so an auditor can reproduce any
COGS figure end-to-end without running tests. The verification ladder
below escalates from "click around the UI" to "reconstruct from raw rows".

### 11.1 UI-only walkthrough (no tooling required)

1. **Pick a `batch_expiry` product with ≥ 2 active batches.**
   * Products → open one with the *yellow/red* expiry pill, *or*
   * Reports → **Batch management** → filter `Expiry: ≤ 30 days`.
2. **Confirm FEFO ordering at rest.**
   * On the product detail screen → *Batches* tab. Rows are
     `ORDER BY (expiry_date IS NULL) ASC, expiry_date ASC, received_date ASC, id ASC`.
   * The top row is exactly what the next sale will consume from.
3. **Make a sale of N units** (smaller than the top batch's `remaining`).
4. **Re-open the *Batches* tab** — the top batch's
   `remaining / received` ticker should drop by N. Expand it: a new
   `OUT` row appears with `−N` and the `INV-…` reference.
5. **Cross-check from the Batch management screen.**
   * Reports → Batch management → search by SKU → tap the same batch.
   * The drill-down sheet shows the identical OUT row. Same data, two
     entry points — by design (`BatchAuditDao.watchBatchesForProduct`
     and `BatchAuditDao.watchAllBatches` both feed
     `BatchConsumptionList`).
6. **Make a sale ≥ remaining of the top batch** so it spills into the
   next-earliest batch. Verify the *Batches* tab now shows two new OUT
   rows on two different batches, summing to the ordered quantity, in
   FEFO order.

### 11.2 Database-level verification (SQL console)

Useful when a customer escalates a COGS dispute on a specific invoice.

```sql
-- All consumptions a single sale produced, with frozen unit costs.
SELECT pb.batch_number,
       pb.expiry_date,
       bc.direction,
       bc.quantity,
       bc.unit_cost_cents,
       (bc.quantity * bc.unit_cost_cents) AS total_cents
  FROM batch_consumptions bc
  JOIN product_batches    pb ON pb.id = bc.batch_id
  JOIN sale_items         si ON si.id = bc.sale_item_id
 WHERE si.sale_id = :sale_id
 ORDER BY bc.id ASC;
```

The reconstructed COGS must equal `Σ (quantity × unit_cost_cents)` for
all `direction='out'` rows, *minus* the same expression for any
`direction='in'` rows produced by a partial sale return. Compare against
`sale_items.cost_cents` — they should match for batched products.

### 11.3 Programmatic helpers (Dart)

`BatchAuditDao` exposes three helpers used by the UI surfaces above and
also intended for one-off verification scripts:

```dart
final dao = sl<BatchAuditDao>();

// (a) Per-batch ledger — matches the *Batches* tab drill-down.
final perBatch = await dao.getConsumptionsForBatch(batchId);

// (b) Per-sale-line ledger — matches the sale detail "where did COGS come
//     from?" surface.
final perLine = await dao.getConsumptionsForSaleItem(saleItemId);

// (c) Per-sale reconstruction (nets partial-return 'in' rows automatically).
final flow = await dao.getBatchFlowForSale(saleId);
for (final line in flow) {
  assert(line.reconstructedCogsCents == line.snapshotCostCents,
         'Reconstructed COGS must equal the snapshot for batched lines');
}
```

For `tracking='standard'` lines `flow.batches` is empty by design —
those products have no batch ledger and the displayed COGS comes from
`sale_items.cost_cents` directly.

### 11.4 Codified regression tests

The verification path above is also enforced by tests so it cannot
silently regress:

* `test/core/services/batch_service_fefo_property_test.dart` — randomised
  property test asserting that earlier expiry always consumes first.
* `test/core/database/daos/batch_audit_dao_test.dart` — DAO contract
  tests for `watchBatchesForProduct`, `watchAllBatches` (Phase H3),
  `getConsumptionsForBatch`, `getBatchFlowForSale` (including the
  partial-return netting case), and the standard-tracked fall-back.
* `test/integration/i1_status_guard_test.dart` — proves no posted/voided
  document edit can corrupt the ledger downstream.

## 12. Returns behaviour reference

Every "return" in Tapix produces a *symmetric* batch-ledger movement
that preserves both the `Σ remaining == stock_quantity` invariant (I1)
and the original frozen unit cost. There are four return shapes the
system handles, summarised below.

### 12.1 Sale return (with original invoice) — `SaleDao.postSaleReturn`

```
sale       → product_batches.remaining_quantity  −= qty   (OUT row)
                                                  ↓
return     → BatchService.restoreConsumptions(    ↑
                  saleItemId: …,                  │ symmetrical
                  reverseConsumptionType:         │ "+qty" IN row
                  'sale_return_reverse',          │ on the SAME batch_id
              )                                   │ at the SAME unit_cost
            → product_batches.remaining_quantity  += qty
            → product_variants.stock_quantity     += qty
```

Key properties:

* The IN row reuses the **original** batch's frozen `unit_cost_cents`,
  *not* the current product cost — preserves COGS truth across
  revaluations.
* `upToQuantity` caps partial restorations: the **earliest** OUT rows
  are restored first, so the remaining OUT rows still represent units
  the customer actually kept.
* For `tracking='standard'` products there are no consumption rows;
  `restoreConsumptions` is a silent no-op and the stock movement is
  applied directly to `product_variants.stock_quantity`.
* Auditor view: the per-batch drill-down shows the OUT row followed by
  a paired `+qty` IN row labelled *"SR-…"*. `getBatchFlowForSale`
  **nets** these so `reconstructedCogsCents` reflects only the COGS
  still recognised on the sale.

### 12.2 Purchase return — `PurchaseDao.postPurchaseReturn`

```
purchase   → CREATE batch (remaining_quantity = qty, source='purchase')
return     → BatchService.consumeFifo(
                  consumptionType: 'purchase_return',
                  purchaseReturnItemId: …,
              )                              (OUT row on the SAME batch
                                              the original purchase fed)
            → product_batches.remaining_quantity  −= qty
            → product_variants.stock_quantity     −= qty
```

Key properties:

* A purchase return DEPLETES the original batch — the supplier took the
  goods back, so we remove the same units that were received. The OUT
  row's `consumptionType='purchase_return'` distinguishes it from a
  sale OUT.
* If the original batch is already partially consumed by sales,
  `consumeFifo` drains the remainder first then surfaces a
  `BatchInsufficientStockException` unless `allowNegativeStock=true`
  (matches SAP / NetSuite default policy).
* Voiding the return reverses the OUT via
  `BatchService.restoreConsumptions(reverseConsumptionType:`
  `'purchase_return_void')`.

### 12.3 Sale-adjustment return — no original invoice

The "adjustment-return" feature lets ops enter post-hoc returns for
sales whose source invoice was never digitised (legacy data, manual
intake, …). Because there is no original OUT row to mirror, we instead
**create a fresh batch**:

```
sale_adj_return → BatchService.createOpeningBatch(
                       source: 'sale_return',
                       quantity, unitCostCents,
                       receivedDate: today,
                   )
                 → product_batches: NEW row, remaining=qty, source='sale_return'
                 → product_variants.stock_quantity += qty
```

That batch participates in FEFO consumption like any other; the source
flag (`'sale_return'`) is preserved so the Batch Management screen and
the inventory valuation report can break it out separately if needed.

### 12.4 Purchase-adjustment return — no original invoice

Symmetric to §12.3 but reduces stock. Implemented as a direct
`product_variants.stock_quantity` decrement plus a synthetic batch
consumption row (`consumptionType='purchase_adj_return'`,
`purchaseReturnAdjustmentItemId=…`). The Batch Management drill-down
labels it via the `LEFT JOIN purchase_return_adjustments` chain
in `BatchAuditDao._kRefJoins`, so the auditor sees a friendly
*"PRA-…"* reference rather than a bare adjustment id.

### 12.5 Invariants preserved across all four shapes

* I1 — `Σ remaining_quantity = stock_quantity` is asserted by
  `BatchService.assertInvariantForProduct` at the end of every return
  posting / voiding path.
* I7 — Expiry dates of any batch involved in a return cannot be edited
  once it has any `'out'` consumption (`BatchService.updateExpiryDate`
  freeze, Phase I2).
* COGS truth — IN rows always carry the **original** frozen unit cost,
  guaranteeing Σ(out·cost) − Σ(in·cost) over the lifetime of the batch
  equals the cost of the units permanently consumed.
