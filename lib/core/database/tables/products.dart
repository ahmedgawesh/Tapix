import 'package:drift/drift.dart';
import '../converters/money_converter.dart';
import 'settings.dart';
import 'parties.dart';
import 'users.dart';

@DataClassName('ProductCategory')
class ProductCategories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get parentId => integer().nullable().references(ProductCategories, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ProductColor')
class ProductColors extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get hexCode => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Size')
class Sizes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Product')
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sku => text().nullable().unique()();
  TextColumn get barcode => text().nullable().unique()();
  TextColumn get name => text()();
  TextColumn get nameAr => text().nullable()();
  TextColumn get nameFr => text().nullable()();
  TextColumn get description => text().nullable()();
  IntColumn get categoryId => integer().nullable().references(ProductCategories, #id, onDelete: KeyAction.restrict)();
  IntColumn get supplierId => integer().nullable().references(Suppliers, #id, onDelete: KeyAction.restrict)();
  IntColumn get costCents => integer().map(const MoneyConverter())();
  IntColumn get priceCents => integer().map(const MoneyConverter())();
  IntColumn get wholesalePriceCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get previousCostCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get previousPriceCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get previousWholesalePriceCents => integer().nullable().map(const MoneyConverter())();

  /// Supplier reference price — the **gross** unit cost the user paid on the
  /// most recent purchase line, **before** any per-line trade discount.
  ///
  /// Decouples the user-facing "آخر سعر شراء" UX from the IAS-2-compliant
  /// inventory cost basis stored in [costCents]:
  ///   * [costCents]                = net of discounts → drives COGS,
  ///                                  inventory valuation, GL reconciliation.
  ///   * [lastPurchasePriceCents]   = gross/list price → drives the product
  ///                                  edit screen, margin display, pricing
  ///                                  analysis, supplier negotiation.
  ///
  /// Nullable for backwards compatibility — legacy products predating this
  /// column display [costCents] as a fallback. Populated automatically on
  /// every purchase post (gross unit cost typed by the user) and propagated
  /// to the parent products row via `ProductCostService.syncProductFromVariants`.
  IntColumn get lastPurchasePriceCents => integer().nullable().map(const MoneyConverter())();

  IntColumn get currencyId => integer().nullable().references(Currencies, #id, onDelete: KeyAction.restrict)();
  BoolColumn get trackInventory => boolean().withDefault(const Constant(true))();
  IntColumn get stockQuantity => integer().withDefault(const Constant(0))(); // quantity in requirements
  IntColumn get minQuantity => integer().withDefault(const Constant(0))(); // reorderLevel in requirements
  BoolColumn get hasVariants => boolean().withDefault(const Constant(false))();
  BoolColumn get isTaxable => boolean().withDefault(const Constant(false))();
  IntColumn get purchaseTaxRateBps => integer().withDefault(const Constant(0))();
  IntColumn get salesTaxRateBps => integer().withDefault(const Constant(0))();
  TextColumn get imagePath => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  /// Costing method for inventory valuation. One of:
  ///   - 'wac'  → Weighted Average Cost (default; uses [costCents])
  ///   - 'fifo' → First-In, First-Out (uses [ProductBatches] + [BatchConsumptions])
  /// Locked once any batch consumption exists for this product.
  ///
  /// **DEPRECATED (Phase B+, two-layer inventory architecture).**
  /// New code should:
  ///   * Read the **global** valuation method from `InventoryValuationService`.
  ///   * Read the **per-product** batch policy from [inventoryTrackingType].
  /// This column is preserved for one release for offline-installed apps and
  /// for the Phase B migration's backfill query. Reads from runtime code are
  /// being removed in Phase D/F.
  TextColumn get costingMethod =>
      text().withDefault(const Constant('wac'))();

  /// Inventory tracking type — the per-product batch/expiry policy.
  ///
  /// One of:
  ///   - `'standard'`     → single stock pool, no batches. Cheapest path,
  ///                        suitable for non-perishables (e.g. mug, cable).
  ///   - `'batch'`        → every purchase creates a [ProductBatches] row;
  ///                        consumption is FIFO by `received_date`.
  ///                        Suitable for lot-tracked goods without expiry.
  ///   - `'batch_expiry'` → batch + required `expiry_date`; consumption is
  ///                        FEFO (First-Expired-First-Out) automatically via
  ///                        `BatchService.consumeFifo`. Required for
  ///                        pharmacies, dairy, cosmetics, chemicals.
  ///
  /// Locked once any batch row or stock movement exists for this product.
  ///
  /// Backfilled in migration v10048 from the legacy [costingMethod] column:
  ///   * `wac`  → `standard`
  ///   * `fifo` + ∃ batch with expiry → `batch_expiry`
  ///   * `fifo` (no expiry) → `batch`
  TextColumn get inventoryTrackingType =>
      text().withDefault(const Constant('standard'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('ProductVariant')
class ProductVariants extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.cascade)();
  TextColumn get sku => text().nullable().unique()();
  TextColumn get barcode => text().nullable().unique()();
  IntColumn get colorId => integer().nullable().references(ProductColors, #id, onDelete: KeyAction.restrict)();
  IntColumn get sizeId => integer().nullable().references(Sizes, #id, onDelete: KeyAction.restrict)();
  IntColumn get costCents => integer().map(const MoneyConverter())();
  IntColumn get priceCents => integer().map(const MoneyConverter())();
  IntColumn get wholesalePriceCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get previousCostCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get previousPriceCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get previousWholesalePriceCents => integer().nullable().map(const MoneyConverter())();

  /// Variant-level supplier reference price (gross of trade discounts) —
  /// mirrors [Products.lastPurchasePriceCents]. See that column's docs for
  /// the full rationale. Each variant carries its own value because every
  /// variant can be purchased on a separate line with its own discount.
  IntColumn get lastPurchasePriceCents => integer().nullable().map(const MoneyConverter())();

  IntColumn get priceAdjustmentCents => integer().map(const MoneyConverter()).withDefault(const Constant(0))();
  IntColumn get stockQuantity => integer().withDefault(const Constant(0))(); // quantity in requirements
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Immutable audit trail of price/cost changes on a product (or a specific
/// variant). Rows are append-only — never updated or deleted — so the history
/// can be relied on for margin analysis, compliance reports and debugging.
///
/// Emitted by `ProductFormBloc` whenever a user-driven edit changes
/// `price_cents` / `wholesale_price_cents` on a product, and by
/// `InventoryAdjustmentDao` for revaluation adjustments that alter cost.
@DataClassName('ProductPriceHistory')
class ProductPriceHistories extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id, onDelete: KeyAction.cascade)();
  IntColumn get variantId => integer().nullable().references(ProductVariants, #id, onDelete: KeyAction.cascade)();
  IntColumn get oldCostCents => integer().map(const MoneyConverter())();
  IntColumn get newCostCents => integer().map(const MoneyConverter())();
  IntColumn get oldPriceCents => integer().map(const MoneyConverter())();
  IntColumn get newPriceCents => integer().map(const MoneyConverter())();
  IntColumn get oldWholesalePriceCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get newWholesalePriceCents => integer().nullable().map(const MoneyConverter())();
  IntColumn get userId => integer().nullable().references(Users, #id, onDelete: KeyAction.setNull)();
  TextColumn get changeReason => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// FIFO/Lot tracking — single source of truth for "how many units of which
/// product/variant arrived from which purchase, at what unit cost, and when
/// they expire". A batch is the atomic unit of inventory valuation under FIFO.
///
/// Rules:
///   - [unitCostCents] is FROZEN at creation. Only inventory revaluation
///     adjustments may rewrite it (and they emit a journal entry).
///   - [remainingQuantity] is mutated by FIFO consumption / restoration only.
///   - Invariant: Σ(remainingQuantity WHERE product_id=P, variant_id=V, is_active=1)
///                == products.stock_quantity (or product_variants.stock_quantity).
///   - [source] traces *why* the batch exists:
///       'purchase'    → created from a posted purchase line
///       'opening'     → migration / initial stock at FIFO activation
///       'found'       → inventory_adjustment of type 'gain'
///       'sale_return' → unlinked sale-adjustment-return that increased stock
@DataClassName('ProductBatch')
class ProductBatches extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();
  IntColumn get variantId => integer()
      .nullable()
      .references(ProductVariants, #id, onDelete: KeyAction.cascade)();

  /// Human-readable unique batch identifier, e.g. `BATCH-202604-12-3`.
  TextColumn get batchNumber => text().unique()();

  /// Source purchase item that created this batch (null for opening / found /
  /// return-originated batches). Restrict prevents losing audit trail.
  IntColumn get purchaseItemId => integer()
      .nullable()
      .customConstraint('NULL REFERENCES purchase_items(id) ON DELETE RESTRICT')();

  IntColumn get supplierId => integer()
      .nullable()
      .references(Suppliers, #id, onDelete: KeyAction.restrict)();

  /// One of: 'purchase' | 'opening' | 'found' | 'sale_return'.
  TextColumn get source => text().withDefault(const Constant('purchase'))();

  DateTimeColumn get receivedDate => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get expiryDate => dateTime().nullable()();

  /// Quantity received at creation. Immutable.
  IntColumn get receivedQuantity => integer()();

  /// Currently available quantity. Mutated only by [BatchConsumptions] postings.
  IntColumn get remainingQuantity => integer()();

  /// Unit cost in cents — FROZEN at creation (revaluation adjustments aside).
  IntColumn get unitCostCents => integer().map(const MoneyConverter())();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Append-only ledger of every movement against a [ProductBatches] row.
///
/// Two directions:
///   - 'out' → quantity removed from the batch (sale, shrinkage, purchase
///             return, void purchase, purchase-adjustment-return)
///   - 'in'  → quantity restored to the batch (sale return, void sale, etc.)
///
/// [unitCostCents] is FROZEN at the moment of consumption so historical COGS
/// cannot drift even if the batch is revalued later.
///
/// Invariant per batch:
///   remainingQuantity == receivedQuantity
///                       − Σ(quantity WHERE direction='out')
///                       + Σ(quantity WHERE direction='in')
@DataClassName('BatchConsumption')
class BatchConsumptions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get batchId =>
      integer().references(ProductBatches, #id, onDelete: KeyAction.restrict)();

  /// One of: 'sale' | 'sale_return_reverse' | 'purchase_return' |
  ///         'shrinkage' | 'revaluation' | 'purchase_adj_return' |
  ///         'sale_adj_return_reverse' | 'void_purchase' | 'void_sale_reverse'.
  TextColumn get consumptionType => text()();

  /// 'out' = quantity removed from batch ; 'in' = quantity restored to batch.
  TextColumn get direction => text()();

  IntColumn get quantity => integer()();

  /// Frozen unit cost at the time of consumption. For 'in' directions this is
  /// the cost the batch carried when the original 'out' was recorded so that
  /// reversals are perfectly symmetric.
  IntColumn get unitCostCents => integer().map(const MoneyConverter())();

  // Optional source FKs — exactly one is expected to be set per row, but we
  // tolerate NULL across all to keep migrations safe.
  IntColumn get saleItemId => integer()
      .nullable()
      .customConstraint('NULL REFERENCES sale_items(id) ON DELETE RESTRICT')();
  IntColumn get saleReturnItemId => integer()
      .nullable()
      .customConstraint(
          'NULL REFERENCES sale_return_items(id) ON DELETE RESTRICT')();
  IntColumn get purchaseReturnItemId => integer()
      .nullable()
      .customConstraint(
          'NULL REFERENCES purchase_return_items(id) ON DELETE RESTRICT')();
  IntColumn get inventoryAdjustmentId => integer()
      .nullable()
      .customConstraint(
          'NULL REFERENCES inventory_adjustments(id) ON DELETE RESTRICT')();
  IntColumn get purchaseReturnAdjustmentItemId => integer()
      .nullable()
      .customConstraint(
          'NULL REFERENCES purchase_return_adjustment_items(id) ON DELETE RESTRICT')();
  IntColumn get saleReturnAdjustmentItemId => integer()
      .nullable()
      .customConstraint(
          'NULL REFERENCES sale_return_adjustment_items(id) ON DELETE RESTRICT')();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
