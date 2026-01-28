# Tapix — Product Variants + Barcode + Invoice Printing (Implementation Plan)

## Decisions (Locked)
- **Barcode generation**: automatic, deterministic **prefix + `variantId`** after insert.
  - Example: `29 + zeroPad(variantId, 11)` → `2900000001234`
  - Must be **unique** and stable.
- **Invoices**: line items should point to a **Variant**, not a Product, to keep inventory math correct.
- **Default Variant** (aka **single variant**): products without variants use **one Variant** as the canonical sellable unit.
  - **Important**: this “single variant” may still carry `colorId` / `sizeId` (coming from product form fields).
  - DAO fallback: if a strict `(colorId=null,sizeId=null)` default is not found, we fallback to the **first active variant** for the product.
  - This unifies: purchase/sales, printing, export/import, and inventory logic.
- **Printing from invoice**: default label count = **invoice line quantity**.
- **UI rule**: when `hasVariants=true`, the **main product-level color/size fields are disabled/hidden**; management moves to “Variants Manager”.

---

## Target End-State (What “Correct” Looks Like)

### Data model
- **Product** = container (name, category, description, image, hasVariants, etc.)
- **Variant** = sellable/stockable unit (barcode, sku, cost, price, stock, color, size, active)

### Inventory math
- Variant stock is authoritative.
- Product stock displayed = **sum of variants** (computed), not manually edited when `hasVariants=true`.

### Invoices
- Purchase/Sales lines reference **variantId**.
- Scanning barcode resolves to **variantId**.

### Printing
- Print single variant, all variants of a product, all variants filtered (category/supplier), or print from invoice.
- A4 labels grid: configurable columns/rows, margins, label size; prints multiple labels in one page.

---

## Phase 0 — Baseline & Safety (No functional changes)

### 0.1 Confirm current schema and code entry points
- Identify existing tables and columns for:
  - `products`
  - `product_variants`
  - `product_colors`, `sizes`
  - invoice tables (purchase/sales)
- Confirm current flows:
  - Product create/update
  - Bulk create
  - Variant create/update

### 0.2 Guardrails
- Ensure these commands are used at the end of each phase:
  - `flutter analyze`
  - unit tests affected by changes

Deliverable:
- A short note in the PR/commit description: “Phase 0 complete”.

---

## Phase 1 — Variant as the Single Source of Truth

### Phase 1 Status
- Implemented: **2026-01-27**

### What was implemented (code-level)
- `ProductVariantDao.createVariant` now sets `products.has_variants = 1` **only** when the created variant has real dimensions (`colorId != null` or `sizeId != null`). This prevents a default variant from incorrectly flipping the product into variants mode.
- Added variant combination uniqueness at the DB level via index:
  - `idx_product_variants_product_color_size_unique`
  - `UNIQUE (product_id, IFNULL(color_id, -1), IFNULL(size_id, -1))`
  - This prevents duplicate variants and ensures only one default variant per product.
- Added default variant support in repositories:
  - `getDefaultVariantByProduct(productId)`
  - `ensureDefaultVariantForProduct(productId, costCents, priceCents, stockQuantity)`
- Added automatic barcode generation for variants when barcode is missing/blank:
  - Format (13 digits): `29` + `variantId` padded to 11 digits
  - Example: `29` + `00000001234` => `2900000001234`
  - Implemented in `ProductVariantRepositoryImpl.createVariant` using a post-insert update (`updateVariantBarcode`).
- Verification: `flutter analyze` => **No issues found**.

### 1.1 Database (Drift) — enforce variant uniqueness + support auto-barcode

#### 1.1.1 Add/verify constraints
- Add a **unique constraint** to prevent duplicate combinations per product:
  - Unique: `(product_id, color_id, size_id)`
- Add a **unique constraint** for `barcode` in `product_variants`.

Notes:
- `NULL` handling differs by SQLite for unique constraints.
  - If we keep `color_id` and `size_id` nullable, we must ensure the default variant is unique.
  - Recommended approach:
    - Keep nullable, but enforce with additional application-level checks.
    - Or set default variant to explicit `0`/sentinel IDs (not recommended unless you want fake “None” records).

#### 1.1.2 Barcode generation fields
- Add a field if needed:
  - `barcode` is already in `product_variants`.
- Ensure it can be updated after insert.

### 1.2 Repository & Service Layer

#### 1.2.1 Variant creation helpers
Add methods in `ProductVariantRepository`:
- `Future<int> ensureDefaultVariantForProduct({required int productId, required Decimal costCents, required Decimal priceCents, required int stockQuantity})`
  - If default variant exists → return its id.
  - Else create it.

- `Future<int> createVariantIfNotExists({required int productId, int? colorId, int? sizeId, ...})`
  - Uses `(productId,colorId,sizeId)` uniqueness.

#### 1.2.2 Barcode generation service
Create a small domain service (or method in repository) to generate barcode:
- `String buildVariantBarcode(int variantId)`
- Format (locked): `29 + variantId padded to 11 digits`.

Implementation steps:
1. Insert variant with `barcode=null`.
2. Get `variantId`.
3. Generate barcode.
4. Update variant barcode.

Edge handling:
- If barcode already set by user, do not overwrite.
- If generated barcode conflicts (should not), fallback:
  - Use another prefix or add checksum (rare).

### 1.3 Product create/update flow

#### 1.3.1 Product without variants
When `hasVariants=false`:
- On product save:
  - Create/update product.
  - Ensure **default variant** exists.
  - Store cost/price/stock on default variant.

UI:
- Product form still shows stock/cost/price.
- Internally these fields map to default variant.

#### 1.3.2 Product with variants
When `hasVariants=true`:
- On product save:
  - Create/update product container fields.
  - No single “selectedColorId/selectedSizeId” on product.
  - Variants created/edited only via Variants Manager.

UI:
- Disable/Hide product-level color/size selectors.
- Disable/Hide product-level stock editing, or show computed total.

### 1.4 Bulk Import/Create adjustments
- For bulk create:
  - If row has no variants → create product + default variant with stock/price/cost.
  - If row includes a specific color/size → treat it as a **variant row** and create product + variant.

Deliverable:
- Product create/edit produces correct variant records.
- Barcode auto-generated for any new variant missing barcode.
- `flutter analyze` clean.

---

## Phase 2 — Variants Manager UI

### Phase 2 Status
- Implemented: **2026-01-27**

### What was implemented (code-level)
- Product form UX:
  - Main product-level color/size selection is now disabled when `hasVariants=true`.
  - Added localized hint text via `product_form.color_size_disabled_when_has_variants`.
- Variants in Product:
  - `VariantManagementWidget` now uses localized strings (no hardcoded English), including:
    - `product_form.variant_item_title`
    - `product_form.variant_item_stock`
    - `product_form.variant_item_barcode`
  - Dialog validation uses `common.required` and `common.invalidNumber`.
- Standalone Variants Screen:
  - Added `/products/variants` route and new `VariantsScreen`.
  - Screen shows all variants with realtime updates (via `ProductVariantsBloc` in all-variants mode).
  - Responsive layout (mobile list, tablet/desktop grid).
  - Search filters locally by barcode/SKU/color/size.
- Product form inventory correctness:
  - For `hasVariants=true`, product stock input is disabled and total stock is shown as the sum of variant stocks.
  - For `hasVariants=false`, cost/price/stock are mapped to the product's single variant.
- Reliability fixes:
  - Variant add/edit dialog made responsive to avoid layout overflows.
  - Size selector dropdown deduplicates IDs and no longer crashes when duplicate items exist.
  - Product form now validates SKU/barcode uniqueness against both `products` and `product_variants` and shows field errors.
  - Database open includes an idempotent dedupe repair for legacy duplicate SKU/barcode values (nulling duplicates) to avoid UNIQUE failures.
  - Product form stock/minQuantity controllers are focus-safe and stay in sync with bloc state (no fighting user edits).
- Routing & permissions:
  - Added route permission entry for `/products/variants`.
  - Added Products menu entry to navigate to Variants screen.
- Localization:
  - Added `variants.*` keys for EN/AR/FR.
- Verification: `flutter analyze` => **No issues found**.

### Phase 2 — What is considered complete vs pending

#### Complete (Phase 2)
- Variants manager inside Product Form (`VariantManagementWidget`): add/edit/delete variants per product.
- Dialog UI is responsive.
- Size dropdown dedupe + safe selection handling.
- Product Form inventory correctness:
  - `hasVariants=true` shows **total stock = sum(variant.stockQuantity)** and disables direct editing.
  - `hasVariants=false` uses the product's **single variant** as the source of truth.
- SKU/Barcode uniqueness validation:
  - Prevents duplicates across both `products` and `product_variants`.
  - Errors displayed on the specific fields (SKU / Barcode).
- DB repair on open (idempotent): clears legacy duplicates in SKU/Barcode to prevent runtime UNIQUE constraint failures.
- Standalone `VariantsScreen` is now a **full CRUD view**.
  - Create, edit, and delete actions are available from this screen.

#### ✅ Phase 2 Complete (2026-01-27)
- Product list display improvements:
  - `ProductTileWidget` now supports optional `variantCount` and `totalVariantStock` parameters.
  - When provided, displays "N × Stock" format (e.g., "3 × 150" for 3 variants with 150 total stock).
  - ✅ `VariantSummariesBloc` created to watch variant summaries (count + total stock per product).
  - ✅ `ProductListScreen` now wires up variant summaries to `ProductTileWidget`.
- Bug fixes:
  - ✅ Fixed `ProductVariantsBloc` initialization (was watching wrong stream before init event).
  - ✅ Fixed `ProductFormScreen` total stock display (now correctly shows sum of variant stocks).

### 2.1 Product details: Variants tab
Add a “Variants” section:
- Table/grid showing:
  - Color, Size, Barcode, SKU, Cost, Price, Stock, Active
- Actions:
  - Add variant
  - Edit variant
  - Delete variant
  - Print label(s) for variant

### 2.2 Generate combinations UI
User selects:
- multiple Colors
- multiple Sizes
Then click: “Generate”
System creates missing combinations only.

Rules:
- Don’t duplicate existing variants.
- Default values for cost/price can come from:
  - product base values or a user-entered “base” in the dialog.

### 2.3 Product list display
- Products list shows products only.
- For products with variants:
  - show total stock = sum variants
  - show “Variants: N”

Deliverable:
- You can manage all variants of a product and see accurate stock.

---

## Phase 3 — Invoices (Purchases first) Using Variants

### Phase 3 Status
- ✅ **Implemented** (2026-01-27) - *Needs end-to-end verification*

### What was implemented
- `PurchaseDao` with full CRUD operations and stock posting logic
- `PurchaseEntity`, `PurchaseItemEntity` domain entities
- `PurchaseRepository` with variant-aware item creation
- `PurchasesBloc` for list management with status filtering
- `PurchaseFormBloc` for form state management with line items
- `PurchaseListScreen` with status filter (all/pending/posted)
- `PurchaseFormScreen` with:
  - Date picker
  - Product/variant selection via bottom sheet
  - Line item management (add/remove/quantity adjustment)
  - Totals calculation
  - Save and Post actions
- Routes: `/purchases`, `/purchases/new`, `/purchases/:id`
- Translations for EN/AR/FR

### 3.1 Purchase invoice line model
Update purchase invoice line to include:
- `variantId` (required)
- optionally keep `productId` cached for reporting, but not required.

### 3.2 Scanning & selection
- Barcode scan resolves variant:
  - `getVariantByBarcode(barcode)`
- Adding a line:
  - choose product → if has variants → force choose variant
  - if no variants → choose default variant automatically

### 3.3 Posting inventory
On invoice confirm/post:
- Increase `variant.stockQuantity` by line quantity.

Accounting/money:
- Save `unitCostCents` on invoice line.
- Totals computed from line values.

Deliverable:
- Purchase invoice updates variant stocks correctly.

---

## Phase 4 — Printing (A4 Labels) Including “Print from Invoice”

### Phase 4 Status
- 🟡 **Partially Implemented** (2026-01-27) - *Needs end-to-end verification*

### What was implemented
- Print labels button added to `PurchaseFormScreen` app bar
- When clicked, navigates to `/products/barcode-design` with purchase products
- Existing barcode design screen handles the printing workflow
- Translations added for EN/AR/FR

### What is still missing / incorrect vs target end-state
- **Print from invoice quantity rule is NOT implemented**:
  - Current implementation passes only `products` to the barcode design screen.
  - No data is passed for **invoice line quantities** (default label count should equal line quantity).
  - `BarcodeDesignBloc` currently determines copies using:
    - selected `printType` (e.g. `all_quantity` uses `product.stockQuantity`)
    - or `settings.copies`
  - This is **not equivalent** to `quantity = invoiceLine.quantity`.
- **Variant-level printing from invoice is not wired**:
  - Purchase items store `variantId`, but print-from-purchase currently ignores `variantId`.
- **A4 grid “layout engine” is not verified here** (depends on barcode printer service/template implementation).

### 4.1 Label data model (in-memory)
Create a simple structure (not necessarily DB):
- `LabelItem(variantId, barcode, productName, colorName, sizeName, priceCents, quantity)`

### 4.2 Print settings
Add print settings:
- label width/height (mm)
- page margins
- horizontal/vertical spacing
- columns/rows
- show fields toggles (price, name, color/size)

### 4.3 Print flows
- From Product → print all variants (quantities chosen)
- From Variant row → print this variant (quantity chosen)
- From Invoice → generate label list where:
  - `quantity = invoiceLine.quantity` by default

### 4.4 Layout engine
- Render A4 PDF (recommended) or print widget.
- Place labels in grid.

Deliverable:
- One click prints all labels for a large invoice (e.g. 40 pieces).

---

## Phase 5 — Export/Import Variant-Aware

### Phase 5 Status
- 🟡 **Partially Implemented** - *Needs end-to-end verification*

### What was implemented
- `ProductImportService` creates colors/sizes automatically during import
- Import creates **variants** with proper color/size associations when input contains color/size
- Default variant created for products without color/size

### What is still missing / incorrect vs target end-state
- **Export is NOT variant-aware (per the plan)**:
  - Current `ExportService` exports **Products** (one row per product).
  - It only adds `color` / `size` columns by reading the **first variant** if any.
  - This does **not** match the required format “each row = Variant”.
- **Roundtrip export→import does not preserve variants**:
  - Since export is product-level, a product with multiple variants cannot be roundtripped.

### 5.1 Export format
CSV/Excel (each row = Variant):
- product fields: name, category, has_variants
- variant fields: color, size, barcode, sku, cost, price, stock, active

### 5.2 Import rules
- Group by `product_name` (+ category) or `product_sku` if available.
- Create/resolve category/colors/sizes by name (already partially exists for category, color, size).
- For each row:
  - create/find product
  - create/find variant by (productId,colorId,sizeId) OR barcode
  - set stock/cost/price
- If `has_variants=false`:
  - route to default variant.

Deliverable:
- Roundtrip export→import preserves variants and stock accurately.

---

## Phase 6 — Reporting (No math mistakes)

### Phase 6 Status
- ⏳ **Pending** - Basic infrastructure exists, full reporting screens not yet implemented

### 6.1 Variant-level reporting
- stock by variant
- sales/purchases by variant

### 6.2 Product-level rollups
- rollup = sum(variants)

### 6.3 Consistency checks
Add checks:
- If `hasVariants=true`, product stock fields are not used for math.
- Prevent negative stocks unless explicitly allowed.

Deliverable:
- Reports show correct numbers with no double counting.

---

## Testing Checklist (Per Phase)

### Unit tests
- Variant repo:
  - ensure default variant creation
  - uniqueness behavior
  - barcode generation

- Invoice posting:
  - stock increments by variant

### Integration tests (where appropriate)
- Create product with variants → generate combinations → print labels.

### Static analysis
- `flutter analyze` must be **0 issues**.

---

## Implementation Order (Recommended)
1. Phase 1 (data correctness, default variant, barcode generation)
2. Phase 2 (variants manager UI)
3. Phase 3 (purchase invoices referencing variants)
4. Phase 4 (printing from invoice)
5. Phase 5 (export/import)
6. Phase 6 (reports)

---

## Open Items to Confirm Before Coding (Quick answers)
- Barcode length: **13 digits** (locked by current implementation).
- Barcode regeneration: **No** (barcode is stable per `variantId`).
- Print defaults (still open): show price by default on labels?
