import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../logging_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// PRODUCT COST SERVICE
// ══════════════════════════════════════════════════════════════════════════════

/// SINGLE SOURCE OF TRUTH for writes to `products.cost_cents` and
/// `product_variants.cost_cents`.
///
/// Before this service existed, cost updates were scattered across:
///   * `purchase_dao.postPurchase` — inline WAC formula duplicated twice
///     (variant and non-variant paths), plus a post-loop parent aggregation
///     that used the semantically-wrong `MAX(cost_cents)` across variants
///     instead of a true weighted average.
///   * `purchase_dao.voidPurchase` — same buggy `MAX` aggregation.
///   * `inventory_adjustment_service` — direct `UPDATE products SET cost_cents`
///     bypassing every other call site.
///
/// The scattered writers caused two production bugs:
///   1. The parent `products.cost_cents` shown in the product edit screen
///      was `MAX(variants.cost_cents)` — a meaningless aggregate that
///      drifted from any accounting convention.
///   2. The `costing_method` flag on the product (wac | fifo) was silently
///      ignored: every purchase applied weighted-average to the variant
///      regardless of the flag, so the FIFO option was cosmetic.
///
/// This service consolidates every cost write behind four methods:
///   * [applyPurchaseCostToVariant] — moving-average / FIFO-latest / last-cost
///     blend when a purchase line increases stock.
///   * [applyPurchaseCostToProduct] — same but for non-variant products
///     (legacy path, kept because some call sites still write to the
///     `products` row directly alongside the default variant).
///   * [setVariantCost] / [setProductCost] — hard overwrite used by
///     inventory revaluation (no blending, no history of its own — caller
///     records the GL posting and the price-history row).
///   * [syncProductFromVariants] — recomputes the parent `products` row
///     as a TRUE weighted average (`SUM(cost × qty) / SUM(qty)`) across
///     all active variants, matching the QuickBooks / Xero convention.
///
/// Style follows `StockService` and `BalanceService`:
///   * Static-only, private constructor.
///   * Takes a [DatabaseAccessor] so it composes inside any DAO transaction.
///   * Uses `customUpdate` + explicit `updates:` set for Drift invalidation.
///   * Debug logging via [LoggingService] with the `ProductCostService` tag.
class ProductCostService {
  ProductCostService._();

  static const String _tag = 'ProductCostService';

  /// Supported costing methods. Mirrors the enum values stored in
  /// `products.costing_method` plus the legacy `last` strategy kept for
  /// migration tests.
  ///
  /// Resolution rules when applying a purchase cost:
  ///   * `wac`  → moving weighted average using prior cost × prior qty.
  ///   * `fifo` → `cost_cents` stores the LATEST paid cost as a display
  ///              value; actual per-layer costs live in `product_batches`,
  ///              which is what `BatchService.consumeFifo` reads at sale
  ///              time. Storing the latest paid cost keeps the product
  ///              edit screen intuitive (matches what the user just typed).
  ///   * `last` → overwrite with the latest paid cost. Same as fifo for the
  ///              `cost_cents` cell; distinct only because FIFO additionally
  ///              relies on batches being created by the caller.
  static const String methodWac = 'wac';
  static const String methodFifo = 'fifo';
  static const String methodLast = 'last';

  // ────────────────────────────────────────────────────────────────────────
  // VARIANT-LEVEL WRITERS
  // ────────────────────────────────────────────────────────────────────────

  /// Apply the cost side-effect of a purchase line to
  /// `product_variants.cost_cents`.
  ///
  /// [beforeQty] and [beforeCostCents] MUST be read BEFORE the stock
  /// increase so the weighted-average denominator matches the intent
  /// ("old × old + new × new / total"). Passing them explicitly makes the
  /// math testable and removes the subtle bug where the old code read
  /// `stock_quantity` after the increase and subtracted the added qty —
  /// fragile if any other path mutated stock in between.
  ///
  /// [addedQty] is the quantity the purchase line just added (> 0).
  /// [newPaidCostCents] is the unit cost the user paid on this line.
  /// [costingMethod] resolves to one of [methodWac] / [methodFifo] /
  /// [methodLast]; unknown values default to WAC with a debug log so the
  /// call site is surfaced but the posting still lands.
  ///
  /// Returns the cost value that was actually written (rounded cents).
  static Future<int> applyPurchaseCostToVariant(
    DatabaseAccessor<AppDatabase> dao, {
    required int variantId,
    required int beforeQty,
    required int beforeCostCents,
    required int addedQty,
    required int newPaidCostCents,
    required String costingMethod,
  }) async {
    assert(variantId > 0, 'variantId must be positive');
    assert(addedQty > 0, 'addedQty must be positive');
    assert(beforeQty >= 0, 'beforeQty must be non-negative');
    assert(newPaidCostCents >= 0, 'newPaidCostCents must be non-negative');

    final resolvedCost = _resolvePurchaseCost(
      beforeQty: beforeQty,
      beforeCostCents: beforeCostCents,
      addedQty: addedQty,
      newPaidCostCents: newPaidCostCents,
      costingMethod: costingMethod,
    );

    LoggingService.debug(
      'applyPurchaseCostToVariant: variant=$variantId '
      'method=$costingMethod beforeQty=$beforeQty '
      'beforeCost=$beforeCostCents addedQty=$addedQty '
      'newPaid=$newPaidCostCents → resolved=$resolvedCost',
      tag: _tag,
    );

    final now = DateTime.now().toIso8601String();
    await dao.customUpdate(
      'UPDATE product_variants SET cost_cents = ?, updated_at = ? WHERE id = ?',
      variables: [
        Variable.withInt(resolvedCost),
        Variable.withString(now),
        Variable.withInt(variantId),
      ],
      updates: {dao.attachedDatabase.productVariants},
      updateKind: UpdateKind.update,
    );

    return resolvedCost;
  }

  /// Non-variant product path. Same contract as
  /// [applyPurchaseCostToVariant] but writes to the `products` row.
  ///
  /// The sanctioned caller is `PurchaseDao.postPurchase` for products
  /// without dimensional variants. The default variant row is updated by
  /// the caller separately (it stores the same value for parity, mirroring
  /// the existing purchase-posting contract).
  static Future<int> applyPurchaseCostToProduct(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    required int beforeQty,
    required int beforeCostCents,
    required int addedQty,
    required int newPaidCostCents,
    required String costingMethod,
  }) async {
    assert(productId > 0, 'productId must be positive');
    assert(addedQty > 0, 'addedQty must be positive');
    assert(beforeQty >= 0, 'beforeQty must be non-negative');
    assert(newPaidCostCents >= 0, 'newPaidCostCents must be non-negative');

    final resolvedCost = _resolvePurchaseCost(
      beforeQty: beforeQty,
      beforeCostCents: beforeCostCents,
      addedQty: addedQty,
      newPaidCostCents: newPaidCostCents,
      costingMethod: costingMethod,
    );

    LoggingService.debug(
      'applyPurchaseCostToProduct: product=$productId '
      'method=$costingMethod beforeQty=$beforeQty '
      'beforeCost=$beforeCostCents addedQty=$addedQty '
      'newPaid=$newPaidCostCents → resolved=$resolvedCost',
      tag: _tag,
    );

    final now = DateTime.now().toIso8601String();
    await dao.customUpdate(
      'UPDATE products SET cost_cents = ?, updated_at = ? WHERE id = ?',
      variables: [
        Variable.withInt(resolvedCost),
        Variable.withString(now),
        Variable.withInt(productId),
      ],
      updates: {dao.attachedDatabase.products},
      updateKind: UpdateKind.update,
    );

    return resolvedCost;
  }

  // ────────────────────────────────────────────────────────────────────────
  // DIRECT OVERWRITE WRITERS (revaluation, opening balance, etc.)
  // ────────────────────────────────────────────────────────────────────────

  /// Overwrite `product_variants.cost_cents` with an absolute value. No
  /// weighted-average blending — used by inventory revaluation and similar
  /// paths where the caller has already decided the new cost.
  ///
  /// Does NOT touch price history or GL. The caller is responsible for
  /// posting the revaluation journal entry and recording the price-history
  /// row (the established contract in `InventoryAdjustmentService`).
  static Future<void> setVariantCost(
    DatabaseAccessor<AppDatabase> dao, {
    required int variantId,
    required int newCostCents,
  }) async {
    assert(variantId > 0, 'variantId must be positive');
    assert(newCostCents >= 0, 'newCostCents must be non-negative');

    LoggingService.debug(
      'setVariantCost: variant=$variantId newCost=$newCostCents',
      tag: _tag,
    );

    final now = DateTime.now().toIso8601String();
    await dao.customUpdate(
      'UPDATE product_variants SET previous_cost_cents = cost_cents, '
      'cost_cents = ?, updated_at = ? WHERE id = ?',
      variables: [
        Variable.withInt(newCostCents),
        Variable.withString(now),
        Variable.withInt(variantId),
      ],
      updates: {dao.attachedDatabase.productVariants},
      updateKind: UpdateKind.update,
    );
  }

  /// Overwrite `products.cost_cents` with an absolute value. Mirrors the
  /// write to the default variant so both rows stay consistent — matches
  /// the existing purchase-posting contract.
  static Future<void> setProductCost(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    required int newCostCents,
    bool mirrorToDefaultVariant = true,
  }) async {
    assert(productId > 0, 'productId must be positive');
    assert(newCostCents >= 0, 'newCostCents must be non-negative');

    LoggingService.debug(
      'setProductCost: product=$productId newCost=$newCostCents '
      'mirror=$mirrorToDefaultVariant',
      tag: _tag,
    );

    final now = DateTime.now().toIso8601String();
    await dao.customUpdate(
      'UPDATE products SET previous_cost_cents = cost_cents, '
      'cost_cents = ?, updated_at = ? WHERE id = ?',
      variables: [
        Variable.withInt(newCostCents),
        Variable.withString(now),
        Variable.withInt(productId),
      ],
      updates: {dao.attachedDatabase.products},
      updateKind: UpdateKind.update,
    );

    if (mirrorToDefaultVariant) {
      await dao.customUpdate(
        'UPDATE product_variants SET previous_cost_cents = cost_cents, '
        'cost_cents = ?, updated_at = ? '
        'WHERE product_id = ? AND color_id IS NULL AND size_id IS NULL',
        variables: [
          Variable.withInt(newCostCents),
          Variable.withString(now),
          Variable.withInt(productId),
        ],
        updates: {dao.attachedDatabase.productVariants},
        updateKind: UpdateKind.update,
      );
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // PARENT AGGREGATION
  // ────────────────────────────────────────────────────────────────────────

  /// Recompute `products.cost_cents` / `stock_quantity` / `price_cents` /
  /// `wholesale_price_cents` as a TRUE weighted average across active
  /// variants:
  ///
  /// ```
  ///   cost      = round( SUM(cost_cents × stock_quantity) / SUM(stock_quantity) )
  ///   stock     = SUM(stock_quantity)
  ///   price     = MAX(price_cents)      ← price is retail — blending makes no sense
  ///   wholesale = MAX(wholesale_price_cents)
  /// ```
  ///
  /// When every variant has zero stock the weighted average is
  /// mathematically undefined; in that case the parent cost falls back to
  /// the simple average of active-variant `cost_cents` values, which keeps
  /// the "most recently paid" information visible to the user even when
  /// nothing is on-hand (matches QuickBooks Online's "item cost" behaviour
  /// for fully-depleted SKUs).
  ///
  /// [syncStock] / [syncCost] / [syncPrice] gate which columns are
  /// rewritten. Default is "all three" — matches the existing
  /// `purchase_dao.postPurchase` contract.
  static Future<void> syncProductFromVariants(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    bool syncStock = true,
    bool syncCost = true,
    bool syncPrice = true,
  }) async {
    assert(productId > 0, 'productId must be positive');
    if (!syncStock && !syncCost && !syncPrice) return;

    // Weighted average via SQL keeps the aggregation atomic and avoids
    // pulling every variant into Dart memory. `NULLIF` guards against the
    // zero-denominator case — we fall back to the simple average further
    // down when weighted_cost is NULL.
    final row = await dao.customSelect(
      '''
      SELECT
        COALESCE(SUM(stock_quantity), 0) AS total_stock,
        CAST(ROUND(
          CAST(SUM(cost_cents * stock_quantity) AS REAL)
          / NULLIF(SUM(stock_quantity), 0)
        ) AS INTEGER) AS weighted_cost,
        CAST(ROUND(AVG(cost_cents)) AS INTEGER) AS avg_cost,
        COALESCE(MAX(price_cents), 0) AS max_price,
        MAX(wholesale_price_cents) AS max_wholesale,
        MAX(last_purchase_price_cents) AS max_last_purchase,
        COUNT(*) AS variant_count
      FROM product_variants
      WHERE product_id = ? AND is_active = 1
      ''',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();

    if (row == null) return;

    final variantCount = row.read<int>('variant_count');
    if (variantCount == 0) return;

    final totalStock = row.read<int>('total_stock');
    final weightedCost = row.readNullable<int>('weighted_cost');
    final avgCost = row.read<int>('avg_cost');
    final maxPrice = row.read<int>('max_price');
    final maxWholesale = row.readNullable<int>('max_wholesale');
    // Supplier reference price aggregation — mirrors the existing
    // `MAX(price_cents)` convention. NULL when every variant is still on
    // the legacy schema (no purchase posted after migration 10055); in
    // that case we leave the parent column untouched so the
    // `lastPurchasePriceCents ?? costCents` fallback at read sites keeps
    // working.
    final maxLastPurchase = row.readNullable<int>('max_last_purchase');

    // Fall back to simple average when every variant is out of stock
    // (weighted_cost is NULL because SUM(stock_quantity) == 0).
    final resolvedCost = weightedCost ?? avgCost;

    LoggingService.debug(
      'syncProductFromVariants: product=$productId '
      'variants=$variantCount totalStock=$totalStock '
      'weightedCost=$weightedCost avgCost=$avgCost '
      'resolvedCost=$resolvedCost',
      tag: _tag,
    );

    // Build the SET clause dynamically so callers can opt out of individual
    // column syncs. The common case (all three) still compiles to a single
    // UPDATE statement.
    final setClauses = <String>[];
    final variables = <Variable>[];
    if (syncStock) {
      setClauses.add('stock_quantity = ?');
      variables.add(Variable.withInt(totalStock));
    }
    if (syncCost) {
      setClauses.add('cost_cents = ?');
      variables.add(Variable.withInt(resolvedCost));
      // Propagate the supplier reference price from variants to parent so
      // the product detail screen reads from a single, kept-fresh column.
      // Skipped when every variant predates migration 10055 (NULL); the
      // UI fallback (`lastPurchasePriceCents ?? costCents`) covers that.
      if (maxLastPurchase != null) {
        setClauses.add('last_purchase_price_cents = ?');
        variables.add(Variable.withInt(maxLastPurchase));
      }
    }
    if (syncPrice) {
      setClauses.add('price_cents = ?');
      variables.add(Variable.withInt(maxPrice));
      if (maxWholesale != null) {
        setClauses.add('wholesale_price_cents = ?');
        variables.add(Variable.withInt(maxWholesale));
      }
    }
    if (setClauses.isEmpty) return;

    final nowIso = DateTime.now().toIso8601String();
    setClauses.add('updated_at = ?');
    variables.add(Variable.withString(nowIso));
    variables.add(Variable.withInt(productId));

    await dao.customUpdate(
      'UPDATE products SET ${setClauses.join(', ')} WHERE id = ?',
      variables: variables,
      updates: {dao.attachedDatabase.products},
      updateKind: UpdateKind.update,
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // INTERNAL MATH
  // ────────────────────────────────────────────────────────────────────────

  /// Pure cost-resolution function. Extracted so unit tests can exercise
  /// every costing method without touching a database.
  ///
  /// Visible for testing; prefer the public writers above.
  static int resolvePurchaseCostForTest({
    required int beforeQty,
    required int beforeCostCents,
    required int addedQty,
    required int newPaidCostCents,
    required String costingMethod,
  }) {
    return _resolvePurchaseCost(
      beforeQty: beforeQty,
      beforeCostCents: beforeCostCents,
      addedQty: addedQty,
      newPaidCostCents: newPaidCostCents,
      costingMethod: costingMethod,
    );
  }

  static int _resolvePurchaseCost({
    required int beforeQty,
    required int beforeCostCents,
    required int addedQty,
    required int newPaidCostCents,
    required String costingMethod,
  }) {
    switch (costingMethod) {
      case methodFifo:
      case methodLast:
        // FIFO / last-cost: the cost_cents cell is a display value that
        // reflects the latest paid price. Per-layer accounting lives in
        // product_batches for FIFO.
        return newPaidCostCents;

      case methodWac:
      default:
        // Moving weighted average. When prior stock is zero the formula
        // collapses to the new paid cost (no blending possible).
        final totalQty = beforeQty + addedQty;
        if (totalQty <= 0) return newPaidCostCents;
        if (beforeQty <= 0) return newPaidCostCents;
        final weightedSum =
            (beforeCostCents * beforeQty) + (newPaidCostCents * addedQty);
        // Banker-style rounding isn't available on int division; use
        // (num / den).round() which is half-away-from-zero. The error is
        // at most 0.5¢ per line and does not affect GL balance because
        // the journal entries use the invoice total, not the derived cost.
        return (weightedSum / totalQty).round();
    }
  }
}
