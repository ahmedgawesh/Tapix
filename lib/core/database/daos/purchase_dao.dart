import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../measurement/measurement.dart';
import '../app_database.dart';
import '../tables/transactions.dart';
import '../tables/parties.dart';
import '../tables/products.dart';
import '../../services/stock_service.dart';
import '../../services/balance_service.dart';
import '../../services/batch_service.dart';
import '../../services/price_history_service.dart';
import '../../services/inventory/product_cost_service.dart';
import '../../services/inventory/wac_movement_service.dart';
import '../../services/inventory/inventory_valuation_delta_service.dart';
import '../../services/document_number_service.dart';
import '../../services/journal_entry_service.dart';
import '../../services/return_calculation_service.dart';

part 'purchase_dao.g.dart';

/// Data class for purchase with supplier info
class PurchaseWithSupplier {
  final Purchase purchase;
  final Supplier supplier;

  PurchaseWithSupplier({required this.purchase, required this.supplier});
}

/// Data class for purchase return item with full product details
class PurchaseReturnItemWithDetails {
  final PurchaseReturnItem returnItem;
  final Product product;
  final ProductVariant? variant;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;

  PurchaseReturnItemWithDetails({
    required this.returnItem,
    required this.product,
    this.variant,
    this.colorName,
    this.colorHex,
    this.sizeName,
  });
}

/// Data class for purchase item with product and variant info.
///
/// `colorName` / `colorHex` / `sizeName` are resolved per-variant via
/// `productColors` and `sizes` joins so that a single invoice carrying
/// multiple variants of the same product renders each line's true
/// attributes. Mirrors the sales-side join (`SaleItemWithDetails`) and the
/// purchase-return-side join (`PurchaseReturnItemWithDetails`).
class PurchaseItemWithDetails {
  final PurchaseItem item;
  final Product product;
  final ProductVariant? variant;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;

  PurchaseItemWithDetails({
    required this.item,
    required this.product,
    this.variant,
    this.colorName,
    this.colorHex,
    this.sizeName,
  });
}

/// Data class for purchase return joined with supplier info
class PurchaseReturnWithParty {
  final PurchaseReturn purchaseReturn;
  final String? supplierName;
  final String? supplierPhone;

  PurchaseReturnWithParty({
    required this.purchaseReturn,
    this.supplierName,
    this.supplierPhone,
  });
}

/// Dashboard stats for purchases
class PurchaseDashboardStats {
  final int totalCount;
  final int draftCount;
  final int postedCount;
  final int totalPayableCents;
  final int totalPaidCents;
  final int overdueCount;
  final int returnsCount;

  PurchaseDashboardStats({
    required this.totalCount,
    required this.draftCount,
    required this.postedCount,
    required this.totalPayableCents,
    required this.totalPaidCents,
    required this.overdueCount,
    required this.returnsCount,
  });
}

@DriftAccessor(
  tables: [
    Purchases,
    PurchaseItems,
    PurchaseReturns,
    PurchaseReturnItems,
    PurchasePayments,
    Suppliers,
    SupplierTransactions,
    Products,
    ProductVariants,
    ProductBatches,
  ],
)
class PurchaseDao extends DatabaseAccessor<AppDatabase>
    with _$PurchaseDaoMixin {
  PurchaseDao(super.db);

  /// Returns `true` when the product needs **batch-level books** (a
  /// `product_batches` row per purchase, frozen unit cost, FIFO/FEFO
  /// consumption on sale).
  ///
  /// Phase B (two-layer inventory architecture): the predicate is the OR of
  /// the two columns so the helper is robust against any transient skew
  /// between them (e.g. a freshly-restored backup, a direct SQL update, or a
  /// test fixture that only sets one):
  ///   * `inventory_tracking_type IN ('batch','batch_expiry')`  ⇒ `true`.
  ///   * legacy `costing_method = 'fifo'`                       ⇒ `true`.
  ///   * otherwise                                              ⇒ `false`.
  ///
  /// `setInventoryTrackingType` keeps both columns in sync, and migration
  /// v10048 backfills them, so in normal production both signals agree.
  Future<bool> _isFifoProduct(int productId) async {
    final row = await customSelect(
      'SELECT inventory_tracking_type, costing_method FROM products WHERE id = ?',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();
    if (row == null) return false;
    final tracking = row.read<String?>('inventory_tracking_type');
    if (tracking == 'batch' || tracking == 'batch_expiry') return true;
    return (row.read<String?>('costing_method') ?? 'wac') == 'fifo';
  }

  Future<bool> _tracksInventory(int productId) async {
    final row = await customSelect(
      'SELECT track_inventory FROM products WHERE id = ?',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();
    return (row?.read<int?>('track_inventory') ?? 1) != 0;
  }

  // ==================== PURCHASES ====================

  /// Watch all purchases ordered by date descending
  Stream<List<Purchase>> watchAllPurchases() {
    return (select(
      purchases,
    )..orderBy([(p) => OrderingTerm.desc(p.purchaseDate)])).watch();
  }

  /// Watch all purchases with supplier info
  Stream<List<PurchaseWithSupplier>> watchAllPurchasesWithSupplier() {
    final query = select(purchases).join([
      innerJoin(suppliers, suppliers.id.equalsExp(purchases.supplierId)),
    ])..orderBy([OrderingTerm.desc(purchases.purchaseDate)]);

    return query.watch().map(
      (rows) => rows.map((row) {
        return PurchaseWithSupplier(
          purchase: row.readTable(purchases),
          supplier: row.readTable(suppliers),
        );
      }).toList(),
    );
  }

  /// Get purchase by ID
  Future<Purchase?> getPurchaseById(int id) {
    return (select(purchases)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// Get purchase with supplier by ID
  Future<PurchaseWithSupplier?> getPurchaseWithSupplierById(int id) async {
    final query = select(purchases).join([
      innerJoin(suppliers, suppliers.id.equalsExp(purchases.supplierId)),
    ])..where(purchases.id.equals(id));

    final row = await query.getSingleOrNull();
    if (row == null) return null;

    return PurchaseWithSupplier(
      purchase: row.readTable(purchases),
      supplier: row.readTable(suppliers),
    );
  }

  /// Watch purchase items for a purchase
  Stream<List<PurchaseItem>> watchPurchaseItems(int purchaseId) {
    return (select(
      purchaseItems,
    )..where((i) => i.purchaseId.equals(purchaseId))).watch();
  }

  /// Get purchase items for a purchase
  Future<List<PurchaseItem>> getPurchaseItems(int purchaseId) {
    return (select(
      purchaseItems,
    )..where((i) => i.purchaseId.equals(purchaseId))).get();
  }

  /// Net purchase value that belongs in Inventory (1200).
  ///
  /// Service/non-stock lines are intentionally excluded; their net value is
  /// posted to Expenses (5100) by JournalEntryService. Using line total less
  /// line tax preserves allocated discounts and cent rounding exactly.
  Future<int> computePurchaseInventoryNetCents(int purchaseId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(CASE WHEN p.track_inventory = 1 '
      'THEN MAX(pi.total_cents - pi.tax_cents, 0) ELSE 0 END), 0) AS c '
      'FROM purchase_items pi '
      'JOIN products p ON p.id = pi.product_id '
      'WHERE pi.purchase_id = ?',
      variables: [Variable.withInt(purchaseId)],
    ).getSingle();
    return row.read<int>('c');
  }

  /// Exact carrying-value increase produced by a posted purchase.
  ///
  /// This can differ by one cent from the independently rounded invoice
  /// lines when a measured SKU crosses a rounded-pool boundary. The
  /// difference is an inventory-rounding revaluation, not a supplier amount.
  Future<int> computePurchaseInventoryValueAtPostCents(int purchaseId) async {
    final row = await customSelect(
      'SELECT COALESCE(SUM(CASE WHEN p.track_inventory = 1 THEN '
      'COALESCE(pi.inventory_value_at_post_cents, '
      'MAX(pi.total_cents - pi.tax_cents, 0)) ELSE 0 END), 0) AS c '
      'FROM purchase_items pi '
      'JOIN products p ON p.id = pi.product_id '
      'WHERE pi.purchase_id = ?',
      variables: [Variable.withInt(purchaseId)],
    ).getSingle();
    return row.read<int>('c');
  }

  /// Get purchase items with product and variant details.
  ///
  /// Joins `productColors` and `sizes` so each line carries its OWN
  /// variant attributes — required for invoices that contain multiple
  /// variants of the same product (otherwise a productId-keyed lookup
  /// on the UI side would collapse every line to the first variant).
  Future<List<PurchaseItemWithDetails>> getPurchaseItemsWithDetails(
    int purchaseId,
  ) async {
    final query = select(purchaseItems).join([
      innerJoin(products, products.id.equalsExp(purchaseItems.productId)),
      leftOuterJoin(
        productVariants,
        productVariants.id.equalsExp(purchaseItems.variantId),
      ),
      leftOuterJoin(
        productColors,
        productColors.id.equalsExp(productVariants.colorId),
      ),
      leftOuterJoin(sizes, sizes.id.equalsExp(productVariants.sizeId)),
    ])..where(purchaseItems.purchaseId.equals(purchaseId));

    final rows = await query.get();
    return rows.map((row) {
      return PurchaseItemWithDetails(
        item: row.readTable(purchaseItems),
        product: row.readTable(products),
        variant: row.readTableOrNull(productVariants),
        colorName: row.readTableOrNull(productColors)?.name,
        colorHex: row.readTableOrNull(productColors)?.hexCode,
        sizeName: row.readTableOrNull(sizes)?.name,
      );
    }).toList();
  }

  /// Watch purchase items with product and variant details. See
  /// [getPurchaseItemsWithDetails] for the per-variant join rationale.
  Stream<List<PurchaseItemWithDetails>> watchPurchaseItemsWithDetails(
    int purchaseId,
  ) {
    final query = select(purchaseItems).join([
      innerJoin(products, products.id.equalsExp(purchaseItems.productId)),
      leftOuterJoin(
        productVariants,
        productVariants.id.equalsExp(purchaseItems.variantId),
      ),
      leftOuterJoin(
        productColors,
        productColors.id.equalsExp(productVariants.colorId),
      ),
      leftOuterJoin(sizes, sizes.id.equalsExp(productVariants.sizeId)),
    ])..where(purchaseItems.purchaseId.equals(purchaseId));

    return query.watch().map(
      (rows) => rows.map((row) {
        return PurchaseItemWithDetails(
          item: row.readTable(purchaseItems),
          product: row.readTable(products),
          variant: row.readTableOrNull(productVariants),
          colorName: row.readTableOrNull(productColors)?.name,
          colorHex: row.readTableOrNull(productColors)?.hexCode,
          sizeName: row.readTableOrNull(sizes)?.name,
        );
      }).toList(),
    );
  }

  /// Generate next purchase number
  Future<String> generatePurchaseNumber() =>
      DocumentNumberService(attachedDatabase).nextPurchaseInvoice();

  /// Create purchase with items
  Future<int> createPurchase(
    PurchasesCompanion purchase,
    List<PurchaseItemsCompanion> items,
  ) {
    return transaction(() async {
      final purchaseId = await into(purchases).insert(purchase);

      for (final item in items) {
        final itemWithPurchaseId = item.copyWith(purchaseId: Value(purchaseId));
        await into(purchaseItems).insert(itemWithPurchaseId);
      }

      return purchaseId;
    });
  }

  /// Update a purchase and replace its items.
  ///
  /// I1 (defense-in-depth): only `draft`/`pending` purchases may be edited.
  /// A posted/voided purchase has opening batches, stock movements and
  /// journal entries that would silently desync if items were rewritten
  /// without re-running the post pipeline. The repository layer already
  /// gates on this, but we re-check inside the DAO so any future caller
  /// (test, script, new feature) cannot bypass the policy.
  Future<bool> updatePurchaseWithItems(
    int purchaseId,
    PurchasesCompanion purchase,
    List<PurchaseItemsCompanion> items,
  ) {
    return transaction(() async {
      final existing = await (select(
        purchases,
      )..where((p) => p.id.equals(purchaseId))).getSingleOrNull();
      if (existing == null) return false;
      if (existing.status != 'draft' && existing.status != 'pending') {
        throw StateError(
          'I1 violation: cannot edit a "${existing.status}" purchase '
          '(#$purchaseId). Void it and create a new one instead.',
        );
      }

      final updated = await updatePurchase(purchaseId, purchase);
      if (!updated) return false;

      await (delete(
        purchaseItems,
      )..where((i) => i.purchaseId.equals(purchaseId))).go();

      for (final item in items) {
        final itemWithPurchaseId = item.copyWith(purchaseId: Value(purchaseId));
        await into(purchaseItems).insert(itemWithPurchaseId);
      }

      return true;
    });
  }

  /// Update purchase
  Future<bool> updatePurchase(int purchaseId, PurchasesCompanion purchase) {
    return (update(purchases)..where((p) => p.id.equals(purchaseId)))
        .write(purchase.copyWith(updatedAt: Value(DateTime.now())))
        .then((rows) => rows > 0);
  }

  /// Update purchase status
  Future<bool> updatePurchaseStatus(
    int purchaseId,
    String status, {
    int? userId,
  }) {
    final companion = PurchasesCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now()),
    );

    return (update(purchases)..where((p) => p.id.equals(purchaseId)))
        .write(companion)
        .then((rows) => rows > 0);
  }

  /// Post purchase - update variant stock quantities and costs.
  ///
  /// Cost-update strategy is read from each product's own `costing_method`
  /// column (`'wac'` | `'fifo'`) via [ProductCostService], aligning the
  /// per-product user choice with the actual cost write. The legacy
  /// [costStrategy] parameter is retained for source compatibility with
  /// older callers (none in production) but is IGNORED — it used to apply
  /// weighted-average to every product regardless of its configured
  /// method, which silently broke the FIFO option in the product form.
  ///
  /// All writes to `products.cost_cents` and `product_variants.cost_cents`
  /// funnel through [ProductCostService] (the single sanctioned writer).
  /// The post-loop parent aggregation now uses a TRUE weighted average
  /// across active variants — replacing the buggy `MAX(cost_cents)` that
  /// surfaced as the "55.63 instead of 65" report.
  Future<void> postPurchase(
    int purchaseId, {
    int? userId,
    String costStrategy = 'weighted_average',
  }) {
    return transaction(() async {
      final purchase = await getPurchaseById(purchaseId);
      if (purchase == null) {
        throw Exception('Purchase not found');
      }
      if (purchase.status == 'posted') {
        throw Exception('Purchase already posted');
      }

      final items = await getPurchaseItems(purchaseId);

      // Track which products were affected so we can sync them afterwards
      final affectedProductIds = <int>{};
      // I4 (Invariant I1): products whose batch ledger was actually mutated
      // (a new batch row created via createBatchFromPurchase). Used to bound
      // the cross-table assertion to FIFO/batch products — WAC products
      // legitimately have stock without matching batch rows so an
      // unconditional assertion would false-positive.
      final batchedProductIds = <int>{};
      // Check if the purchase has any tax (to update product taxable flag)
      final purchaseTaxCents = purchase.taxCents.toBigInt().toInt();

      for (final item in items) {
        final variantId = item.variantId;
        final productId = item.productId;
        affectedProductIds.add(productId);
        // IAS 2 / ASC 330 — trade discounts taken at purchase reduce the
        // cost basis. The purchase JE already debits 1200 Inventory at
        // (subtotal − discount) (= `purchase.totalCents − taxCents`); storing
        // the GROSS unit cost on the variant/batch would systematically
        // inflate Σ(stock × cost) by Σ(line_discount) and break the
        // reconciliation invariant `Inventory GL == Σ(stock × cost)`.
        // We therefore record the EFFECTIVE per-unit cost = max(0, gross −
        // (lineDiscount / qty)). Half-up rounding aligns with the JE's
        // banker rounding for typical 1-unit-of-precision cases. The
        // typed-in `purchase_items.unit_cost_cents` is preserved as the
        // user-facing "list price" snapshot — only the variant/batch cost
        // basis is netted.
        final grossUnitCost = item.unitCostCents.toBigInt().toInt();
        final lineDiscount = item.discountCents.toBigInt().toInt();
        final lineQty = item.quantity;
        final discountPerMajorUnit = MeasuredAmount.unitCentsFromTotal(
          totalCents: lineDiscount,
          quantity: lineQty,
          quantityScale: item.quantityScale,
        );
        final newCostCents = (lineQty > 0 && lineDiscount > 0)
            ? (grossUnitCost - discountPerMajorUnit).clamp(0, 1 << 62)
            : grossUnitCost;
        final newSellPrice = item.newSellPriceCents?.toBigInt().toInt();
        final newWholesalePrice = item.newWholesalePriceCents
            ?.toBigInt()
            .toInt();
        final now = DateTime.now().toIso8601String();

        // Per-product `track_inventory` flag — gates every physical-stock and
        // batch write below. When false (services / non-stocked items) we
        // still apply the per-line sell/wholesale overrides and post the GL
        // legs, but we do NOT touch stock, do NOT update cost (no WAC base),
        // and do NOT create a batch (no inventory ledger to feed).
        final trackInventoryRow = await customSelect(
          'SELECT track_inventory FROM products WHERE id = ?',
          variables: [Variable.withInt(productId)],
        ).getSingleOrNull();
        final tracks =
            (trackInventoryRow?.read<int>('track_inventory') ?? 1) != 0;
        final valuationSnapshot = tracks
            ? await InventoryValuationDeltaService.capture(
                this,
                productId: productId,
                variantId: variantId,
              )
            : null;

        // Snapshot old cost/price/wholesale BEFORE any mutation so price
        // history records the correct deltas. Routed through
        // PriceHistoryService at the end of this iteration — the SINGLE
        // sanctioned writer for product_price_histories.
        //
        // Two cost snapshots are taken on purpose:
        //   * `oldCostBefore`       — NET basis (cost_cents). Feeds the WAC /
        //                             FIFO / last-cost math inside
        //                             `ProductCostService` and must stay net
        //                             of line discounts (IAS-2).
        //   * `oldGrossCostBefore`  — GROSS basis (last_purchase_price_cents,
        //                             with a fallback to cost_cents for
        //                             pre-migration rows). Feeds the
        //                             user-facing price-history audit log so
        //                             "what did I pay last time" matches the
        //                             value the supplier invoiced before
        //                             discounts — the same value the product
        //                             edit screen now surfaces.
        int oldCostBefore;
        int oldGrossCostBefore;
        int oldPriceBefore;
        int? oldWholesaleBefore;
        if (variantId != null) {
          final r = await customSelect(
            'SELECT cost_cents, last_purchase_price_cents, '
            'price_cents, wholesale_price_cents '
            'FROM product_variants WHERE id = ?',
            variables: [Variable.withInt(variantId)],
          ).getSingleOrNull();
          oldCostBefore = r?.read<int>('cost_cents') ?? 0;
          oldGrossCostBefore =
              r?.readNullable<int>('last_purchase_price_cents') ??
              oldCostBefore;
          oldPriceBefore = r?.read<int>('price_cents') ?? 0;
          oldWholesaleBefore = r?.readNullable<int>('wholesale_price_cents');
        } else {
          final r = await customSelect(
            'SELECT cost_cents, last_purchase_price_cents, '
            'price_cents, wholesale_price_cents '
            'FROM products WHERE id = ?',
            variables: [Variable.withInt(productId)],
          ).getSingleOrNull();
          oldCostBefore = r?.read<int>('cost_cents') ?? 0;
          oldGrossCostBefore =
              r?.readNullable<int>('last_purchase_price_cents') ??
              oldCostBefore;
          oldPriceBefore = r?.read<int>('price_cents') ?? 0;
          oldWholesaleBefore = r?.readNullable<int>('wholesale_price_cents');
        }

        if (variantId != null) {
          // Save current prices as previous before any update
          await customUpdate(
            'UPDATE product_variants SET '
            'previous_cost_cents = cost_cents, '
            'previous_price_cents = price_cents, '
            'previous_wholesale_price_cents = wholesale_price_cents '
            'WHERE id = ?',
            variables: [Variable.withInt(variantId)],
            updates: {productVariants},
            updateKind: UpdateKind.update,
          );

          // Increase variant stock — only when the product is inventory-tracked.
          if (tracks) {
            await StockService.adjustStock(
              this,
              productId: productId,
              variantId: variantId,
              quantity: item.quantity,
              direction: StockDirection.increase,
            );
          }

          // Update cost — only when tracking. Funnels through
          // ProductCostService so the strategy (wac | fifo | last) is
          // resolved per-product and the math lives in one tested place.
          if (tracks) {
            // Read the post-increase stock to derive the pre-increase
            // quantity (`oldCostBefore` was already snapshotted).
            final postQtyRow = await customSelect(
              'SELECT stock_quantity FROM product_variants WHERE id = ?',
              variables: [Variable.withInt(variantId)],
            ).getSingleOrNull();
            final postQty = postQtyRow?.read<int>('stock_quantity') ?? 0;
            final beforeQty = postQty - item.quantity;

            // Resolve costing method from the product row. Falls back to
            // 'wac' on read failure to match the schema default.
            final methodRow = await customSelect(
              'SELECT costing_method FROM products WHERE id = ?',
              variables: [Variable.withInt(productId)],
            ).getSingleOrNull();
            final method = methodRow?.read<String>('costing_method') ?? 'wac';

            await ProductCostService.applyPurchaseCostToVariant(
              this,
              variantId: variantId,
              beforeQty: beforeQty < 0 ? 0 : beforeQty,
              beforeCostCents: oldCostBefore,
              addedQty: item.quantity,
              newPaidCostCents: newCostCents,
              costingMethod: method,
            );

            // Stamp the supplier reference price (GROSS unit cost — pre line
            // discount) so the product/variant edit screen shows what the
            // user typed on the most recent purchase line. Decoupled from
            // `cost_cents` which carries the IAS-2 net basis. See migration
            // 10055 and `Products.lastPurchasePriceCents` docs.
            await customUpdate(
              'UPDATE product_variants SET last_purchase_price_cents = ?, '
              'updated_at = ? WHERE id = ?',
              variables: [
                Variable.withInt(grossUnitCost),
                Variable.withString(now),
                Variable.withInt(variantId),
              ],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          }

          // Update sell price on variant if user specified a new one
          if (newSellPrice != null) {
            await customUpdate(
              'UPDATE product_variants SET price_cents = ?, updated_at = ? WHERE id = ?',
              variables: [
                Variable.withInt(newSellPrice),
                Variable.withString(now),
                Variable.withInt(variantId),
              ],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          }

          // Update wholesale price on variant if user specified a new one
          if (newWholesalePrice != null) {
            await customUpdate(
              'UPDATE product_variants SET wholesale_price_cents = ?, updated_at = ? WHERE id = ?',
              variables: [
                Variable.withInt(newWholesalePrice),
                Variable.withString(now),
                Variable.withInt(variantId),
              ],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          }
        } else {
          // Save current prices as previous before any update on the product
          await customUpdate(
            'UPDATE products SET '
            'previous_cost_cents = cost_cents, '
            'previous_price_cents = price_cents, '
            'previous_wholesale_price_cents = wholesale_price_cents '
            'WHERE id = ?',
            variables: [Variable.withInt(productId)],
            updates: {products},
            updateKind: UpdateKind.update,
          );
          // Also save previous on the default variant
          await customUpdate(
            'UPDATE product_variants SET '
            'previous_cost_cents = cost_cents, '
            'previous_price_cents = price_cents, '
            'previous_wholesale_price_cents = wholesale_price_cents '
            'WHERE id = (SELECT v.id FROM product_variants v '
            'JOIN products p ON p.id = v.product_id '
            'WHERE v.product_id = ? AND v.is_active = 1 '
            'AND p.has_variants = 0 ORDER BY v.id LIMIT 1)',
            variables: [Variable.withInt(productId)],
            updates: {productVariants},
            updateKind: UpdateKind.update,
          );

          // Non-variant product: read pre-increase state, then bump
          // stock, then update cost via ProductCostService. Order matters:
          // we capture `beforeQty` BEFORE adjustStock so the WAC math is
          // unambiguous regardless of any concurrent stock writers.
          if (tracks) {
            final preRow = await customSelect(
              'SELECT stock_quantity FROM products WHERE id = ?',
              variables: [Variable.withInt(productId)],
            ).getSingleOrNull();
            final beforeQty = preRow?.read<int>('stock_quantity') ?? 0;

            // Increase stock via StockService (handles products + default variant)
            await StockService.adjustStock(
              this,
              productId: productId,
              variantId: null,
              quantity: item.quantity,
              direction: StockDirection.increase,
            );

            final methodRow = await customSelect(
              'SELECT costing_method FROM products WHERE id = ?',
              variables: [Variable.withInt(productId)],
            ).getSingleOrNull();
            final method = methodRow?.read<String>('costing_method') ?? 'wac';

            await ProductCostService.applyPurchaseCostToProduct(
              this,
              productId: productId,
              beforeQty: beforeQty,
              beforeCostCents: oldCostBefore,
              addedQty: item.quantity,
              newPaidCostCents: newCostCents,
              costingMethod: method,
            );

            // Stamp the supplier reference price (GROSS) on the product row.
            // See sibling write in the variant branch for the full rationale.
            await customUpdate(
              'UPDATE products SET last_purchase_price_cents = ?, '
              'updated_at = ? WHERE id = ?',
              variables: [
                Variable.withInt(grossUnitCost),
                Variable.withString(now),
                Variable.withInt(productId),
              ],
              updates: {products},
              updateKind: UpdateKind.update,
            );
          }

          // Update sell price on product if user specified a new one
          if (newSellPrice != null) {
            await customUpdate(
              'UPDATE products SET price_cents = ?, updated_at = ? WHERE id = ?',
              variables: [
                Variable.withInt(newSellPrice),
                Variable.withString(now),
                Variable.withInt(productId),
              ],
              updates: {products},
              updateKind: UpdateKind.update,
            );
          }

          // Update wholesale price on product if user specified a new one
          if (newWholesalePrice != null) {
            await customUpdate(
              'UPDATE products SET wholesale_price_cents = ?, updated_at = ? WHERE id = ?',
              variables: [
                Variable.withInt(newWholesalePrice),
                Variable.withString(now),
                Variable.withInt(productId),
              ],
              updates: {products},
              updateKind: UpdateKind.update,
            );
          }

          // Mirror the parent's resolved cost onto the default variant so
          // both rows stay consistent. Read the just-written value back
          // (cheaper than re-deriving the WAC) and write it through.
          if (tracks) {
            final parentRow = await customSelect(
              'SELECT cost_cents FROM products WHERE id = ?',
              variables: [Variable.withInt(productId)],
            ).getSingleOrNull();
            final mirroredCost =
                parentRow?.read<int>('cost_cents') ?? newCostCents;
            await customUpdate(
              'UPDATE product_variants SET cost_cents = ?, updated_at = ? '
              'WHERE id = (SELECT v.id FROM product_variants v '
              'JOIN products p ON p.id = v.product_id '
              'WHERE v.product_id = ? AND v.is_active = 1 '
              'AND p.has_variants = 0 ORDER BY v.id LIMIT 1)',
              variables: [
                Variable.withInt(mirroredCost),
                Variable.withString(now),
                Variable.withInt(productId),
              ],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );

            // Mirror the GROSS supplier reference price onto the default
            // variant too so variant-level UI reads stay consistent with
            // the parent product row.
            await customUpdate(
              'UPDATE product_variants SET last_purchase_price_cents = ?, '
              'updated_at = ? '
              'WHERE id = (SELECT v.id FROM product_variants v '
              'JOIN products p ON p.id = v.product_id '
              'WHERE v.product_id = ? AND v.is_active = 1 '
              'AND p.has_variants = 0 ORDER BY v.id LIMIT 1)',
              variables: [
                Variable.withInt(grossUnitCost),
                Variable.withString(now),
                Variable.withInt(productId),
              ],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          }

          // Sync sell/wholesale prices to default variant too
          if (newSellPrice != null) {
            await customUpdate(
              'UPDATE product_variants SET price_cents = ?, updated_at = ? '
              'WHERE id = (SELECT v.id FROM product_variants v '
              'JOIN products p ON p.id = v.product_id '
              'WHERE v.product_id = ? AND v.is_active = 1 '
              'AND p.has_variants = 0 ORDER BY v.id LIMIT 1)',
              variables: [
                Variable.withInt(newSellPrice),
                Variable.withString(now),
                Variable.withInt(productId),
              ],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          }
          if (newWholesalePrice != null) {
            await customUpdate(
              'UPDATE product_variants SET wholesale_price_cents = ?, updated_at = ? '
              'WHERE id = (SELECT v.id FROM product_variants v '
              'JOIN products p ON p.id = v.product_id '
              'WHERE v.product_id = ? AND v.is_active = 1 '
              'AND p.has_variants = 0 ORDER BY v.id LIMIT 1)',
              variables: [
                Variable.withInt(newWholesalePrice),
                Variable.withString(now),
                Variable.withInt(productId),
              ],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          }
        }

        // Create a batch row for every posted purchase line — the batch
        // ledger is the source of truth for FIFO COGS *and* the only place
        // that holds expiry-aware remaining quantity. Skipped for
        // non-tracked products (services have no inventory ledger).
        if (tracks) {
          await BatchService.createBatchFromPurchase(
            this,
            productId: productId,
            variantId: variantId,
            purchaseItemId: item.id,
            supplierId: purchase.supplierId,
            quantity: item.quantity,
            unitCostCents: newCostCents,
            receivedDate: purchase.purchaseDate,
            expiryDate: item.expiryDate,
          );
          if (await _isFifoProduct(productId)) {
            batchedProductIds.add(productId);
          }
        }

        final inventoryValue = !tracks
            ? 0
            : valuationSnapshot != null
            ? await InventoryValuationDeltaService.signedDeltaAfter(
                this,
                valuationSnapshot,
              )
            : MeasuredAmount.cents(
                unitCents: newCostCents,
                quantity: item.quantity,
                quantityScale: item.quantityScale,
              );
        await (update(purchaseItems)..where((i) => i.id.equals(item.id))).write(
          PurchaseItemsCompanion(
            inventoryValueAtPostCents: Value(Decimal.fromInt(inventoryValue)),
          ),
        );

        // ── Centralized price-history audit ──
        // The price-history widget is a USER-FACING audit log answering "what
        // did I pay / charge over time". For COST we therefore record the
        // GROSS unit cost the user typed on the purchase line
        // (`grossUnitCost`), NOT:
        //   * the post-WAC variant cost — WAC blends old qty × old cost with
        //     new qty × new cost (e.g. 50×3 + 60×1 / 4 = 52.50) which made
        //     users ask "why is the new cost 52?", and
        //   * the post-discount NET basis (`newCostCents`) — that's the
        //     IAS-2 inventory basis (correct for COGS / GL) but it caused
        //     the user-reported "I typed 100 but history shows 99" bug
        //     whenever a per-line discount was applied.
        // Pairs with `oldGrossCostBefore` (which falls back to cost_cents on
        // pre-migration rows) so consecutive history rows compare gross-to-
        // gross. Non-tracked products carry no inventory cost basis, so we
        // leave the recorded cost equal to the prior gross value
        // (PriceHistoryService no-ops on equal values).
        //
        // For sell/wholesale we read the POST-mutation values: those reflect
        // either (a) the user's per-line override (newSellPrice /
        // newWholesalePrice) when supplied or (b) the unchanged prior value
        // — both are correct, since these prices are user-set, not computed.
        final int recordedNewCost = tracks ? grossUnitCost : oldGrossCostBefore;
        int newPriceAfter;
        int? newWholesaleAfter;
        if (variantId != null) {
          final r = await customSelect(
            'SELECT price_cents, wholesale_price_cents '
            'FROM product_variants WHERE id = ?',
            variables: [Variable.withInt(variantId)],
          ).getSingleOrNull();
          newPriceAfter = r?.read<int>('price_cents') ?? oldPriceBefore;
          newWholesaleAfter = r?.readNullable<int>('wholesale_price_cents');
        } else {
          final r = await customSelect(
            'SELECT price_cents, wholesale_price_cents '
            'FROM products WHERE id = ?',
            variables: [Variable.withInt(productId)],
          ).getSingleOrNull();
          newPriceAfter = r?.read<int>('price_cents') ?? oldPriceBefore;
          newWholesaleAfter = r?.readNullable<int>('wholesale_price_cents');
        }
        await PriceHistoryService.recordIfChanged(
          this,
          productId: productId,
          variantId: variantId,
          oldCostCents: oldGrossCostBefore,
          newCostCents: recordedNewCost,
          oldPriceCents: oldPriceBefore,
          newPriceCents: newPriceAfter,
          oldWholesalePriceCents: oldWholesaleBefore,
          newWholesalePriceCents: newWholesaleAfter,
          userId: userId,
          changeReason: 'purchase_post:#$purchaseId',
        );
      }

      // Sync products table from variants for ALL affected products.
      // ProductCostService.syncProductFromVariants computes a TRUE
      // weighted average across active variants — replacing the legacy
      // `MAX(cost_cents)` aggregation that produced misleading parent
      // cost values when variants had different costs (the user-reported
      // "55.63 instead of 65" bug).
      for (final productId in affectedProductIds) {
        await ProductCostService.syncProductFromVariants(
          this,
          productId: productId,
        );
      }

      // Update isTaxable flag on affected products when purchase has tax
      if (purchaseTaxCents > 0) {
        for (final productId in affectedProductIds) {
          await customUpdate(
            'UPDATE products SET is_taxable = 1, updated_at = ? WHERE id = ? AND is_taxable = 0',
            variables: [
              Variable.withString(DateTime.now().toIso8601String()),
              Variable.withInt(productId),
            ],
            updates: {products},
            updateKind: UpdateKind.update,
          );
        }
      }

      // I4 (Invariant I1): assert Σ(batch.remaining) == variant.stock_quantity
      // for every FIFO product whose batch ledger was touched. Catches any
      // silent desync BEFORE the transaction commits.
      for (final productId in batchedProductIds) {
        await BatchService.assertInvariantForProduct(
          this,
          productId: productId,
        );
      }

      // Update purchase status to posted
      await updatePurchaseStatus(purchaseId, 'posted', userId: userId);

      // Supplier accounting (one source of truth = suppliers.balanceCents):
      // - A posted purchase increases payable by total.
      // - Any paid amount decreases payable.
      // This keeps balances accurate even when paidAmountCents is used to settle
      // previous balance + this invoice.
      final totalCents = purchase.totalCents.toBigInt().toInt();

      // Ensure paidAmountCents is backed by purchase_payments rows so it doesn't
      // get lost when later payments are recorded.
      var totalPaidCents = (await getPurchasePayments(
        purchaseId,
      )).fold<int>(0, (sum, p) => sum + p.amountCents.toBigInt().toInt());
      final headerPaidCents = purchase.paidAmountCents.toBigInt().toInt();
      int? backfilledInitialPaymentId;
      int? excessPaymentId;
      if (totalPaidCents == 0 && headerPaidCents > 0) {
        // If overpaying, split into invoice payment + excess credit payment
        final invoicePayment = headerPaidCents > totalCents
            ? totalCents
            : headerPaidCents;
        final excessPayment = headerPaidCents > totalCents
            ? headerPaidCents - totalCents
            : 0;

        backfilledInitialPaymentId = await into(purchasePayments).insert(
          PurchasePaymentsCompanion.insert(
            purchaseId: purchaseId,
            amountCents: Decimal.fromInt(invoicePayment),
            currencyId: purchase.currencyId,
            paymentMethod: purchase.paymentMethod ?? 'cash',
            reference: const Value(null),
            notes: const Value('Initial payment on posting'),
            paymentDate: Value(purchase.purchaseDate),
          ),
        );

        if (excessPayment > 0) {
          excessPaymentId = await into(purchasePayments).insert(
            PurchasePaymentsCompanion.insert(
              purchaseId: purchaseId,
              amountCents: Decimal.fromInt(excessPayment),
              currencyId: purchase.currencyId,
              paymentMethod: purchase.paymentMethod ?? 'cash',
              reference: const Value(null),
              notes: const Value('Excess cash — added to supplier balance'),
              paymentDate: Value(purchase.purchaseDate),
            ),
          );
        }

        totalPaidCents = headerPaidCents;
      }

      // Keep purchases.paid_amount_cents consistent with payment rows.
      await (update(purchases)..where((p) => p.id.equals(purchaseId))).write(
        PurchasesCompanion(
          paidAmountCents: Value(Decimal.fromInt(totalPaidCents)),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Record supplier transactions for audit.
      await into(supplierTransactions).insert(
        SupplierTransactionsCompanion.insert(
          supplierId: purchase.supplierId,
          transactionType: 'purchase',
          transactionNumber: Value(purchase.purchaseNumber),
          amountCents: Decimal.fromInt(totalCents),
          currencyId: purchase.currencyId,
          description: Value('Purchase ${purchase.purchaseNumber}'),
          referenceId: Value(purchaseId),
          referenceType: const Value('purchase'),
        ),
      );

      // Record payment transaction(s) only when we backfilled payment rows.
      // Later payments are logged via recordPayment().
      if (backfilledInitialPaymentId != null) {
        final invoicePayment = headerPaidCents > totalCents
            ? totalCents
            : headerPaidCents;
        if (invoicePayment > 0) {
          final paymentNumber = await DocumentNumberService(
            attachedDatabase,
          ).nextSupplierTransaction('CPS');
          await into(supplierTransactions).insert(
            SupplierTransactionsCompanion.insert(
              supplierId: purchase.supplierId,
              transactionType: 'payment',
              transactionNumber: Value(paymentNumber),
              amountCents: Decimal.fromInt(-invoicePayment),
              currencyId: purchase.currencyId,
              description: Value('Payment for ${purchase.purchaseNumber}'),
              referenceId: Value(backfilledInitialPaymentId),
              referenceType: const Value('purchase_payment'),
            ),
          );
        }
      }

      // Record excess cash as a separate payment transaction
      if (excessPaymentId != null) {
        final excessPayment = headerPaidCents - totalCents;
        final paymentNumber = await DocumentNumberService(
          attachedDatabase,
        ).nextSupplierTransaction('CPS');
        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: purchase.supplierId,
            transactionType: 'payment',
            transactionNumber: Value(paymentNumber),
            amountCents: Decimal.fromInt(-excessPayment),
            currencyId: purchase.currencyId,
            description: Value(
              'Excess cash added to balance — ${purchase.purchaseNumber}',
            ),
            referenceId: Value(excessPaymentId),
            referenceType: const Value('purchase_payment'),
          ),
        );
      }

      // Apply net balance delta once.
      final deltaCents = totalCents - totalPaidCents;
      await BalanceService.adjustSupplierBalance(
        this,
        supplierId: purchase.supplierId,
        deltaCents: deltaCents,
      );
    });
  }

  /// Ensure supplier accounting exists for an already-posted purchase.
  /// This is used to repair legacy data created before supplier accounting was implemented.
  /// The method is idempotent: it only inserts missing supplier_transactions and only applies
  /// the corresponding missing balance deltas.
  Future<void> ensureSupplierAccountingForPostedPurchase(int purchaseId) {
    return transaction(() async {
      final purchase = await getPurchaseById(purchaseId);
      if (purchase == null) return;
      if (purchase.status != 'posted') return;

      final supplierId = purchase.supplierId;
      final currencyId = purchase.currencyId;
      final totalCents = purchase.totalCents.toBigInt().toInt();

      var deltaBalanceCents = 0;

      final existingPurchaseTx =
          await (select(supplierTransactions)..where(
                (t) =>
                    t.referenceType.equals('purchase') &
                    t.referenceId.equals(purchaseId) &
                    t.transactionType.equals('purchase'),
              ))
              .getSingleOrNull();

      if (existingPurchaseTx == null) {
        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: supplierId,
            transactionType: 'purchase',
            transactionNumber: Value(purchase.purchaseNumber),
            amountCents: Decimal.fromInt(totalCents),
            currencyId: currencyId,
            description: Value(
              'Purchase ${purchase.purchaseNumber} (backfilled)',
            ),
            referenceId: Value(purchaseId),
            referenceType: const Value('purchase'),
          ),
        );
        deltaBalanceCents += totalCents;
      }

      // Ensure there are payment rows when header paidAmountCents was used.
      var payments = await getPurchasePayments(purchaseId);
      if (payments.isEmpty) {
        final headerPaidCents = purchase.paidAmountCents.toBigInt().toInt();
        if (headerPaidCents > 0) {
          final backfilledPaymentId = await into(purchasePayments).insert(
            PurchasePaymentsCompanion.insert(
              purchaseId: purchaseId,
              amountCents: Decimal.fromInt(headerPaidCents),
              currencyId: currencyId,
              paymentMethod: purchase.paymentMethod ?? 'cash',
              reference: const Value(null),
              notes: const Value('Backfilled legacy payment'),
              paymentDate: Value(purchase.purchaseDate),
            ),
          );

          payments = await getPurchasePayments(purchaseId);

          // If we created a payment row, ensure its supplier transaction exists too.
          final existingPaymentTx =
              await (select(supplierTransactions)..where(
                    (t) =>
                        t.referenceType.equals('purchase_payment') &
                        t.referenceId.equals(backfilledPaymentId) &
                        t.transactionType.equals('payment'),
                  ))
                  .getSingleOrNull();

          if (existingPaymentTx == null) {
            final paymentNumber = await DocumentNumberService(
              attachedDatabase,
            ).nextSupplierTransaction('CPS');
            await into(supplierTransactions).insert(
              SupplierTransactionsCompanion.insert(
                supplierId: supplierId,
                transactionType: 'payment',
                transactionNumber: Value(paymentNumber),
                amountCents: Decimal.fromInt(-headerPaidCents),
                currencyId: currencyId,
                description: Value(
                  'Payment for ${purchase.purchaseNumber} (backfilled)',
                ),
                referenceId: Value(backfilledPaymentId),
                referenceType: const Value('purchase_payment'),
              ),
            );
            deltaBalanceCents -= headerPaidCents;
          }
        }
      }

      // Ensure each payment row has a matching supplier transaction.
      for (final p in payments) {
        final payId = p.id;
        final payCents = p.amountCents.toBigInt().toInt();

        final existingPaymentTx =
            await (select(supplierTransactions)..where(
                  (t) =>
                      t.referenceType.equals('purchase_payment') &
                      t.referenceId.equals(payId) &
                      t.transactionType.equals('payment'),
                ))
                .getSingleOrNull();

        if (existingPaymentTx == null) {
          final paymentNumber = await DocumentNumberService(
            attachedDatabase,
          ).nextSupplierTransaction('CPS');
          await into(supplierTransactions).insert(
            SupplierTransactionsCompanion.insert(
              supplierId: supplierId,
              transactionType: 'payment',
              transactionNumber: Value(paymentNumber),
              amountCents: Decimal.fromInt(-payCents),
              currencyId: currencyId,
              description: Value(
                'Payment for ${purchase.purchaseNumber} (backfilled)',
              ),
              referenceId: Value(payId),
              referenceType: const Value('purchase_payment'),
            ),
          );
          deltaBalanceCents -= payCents;
        }
      }

      if (deltaBalanceCents != 0) {
        await BalanceService.adjustSupplierBalance(
          this,
          supplierId: supplierId,
          deltaCents: deltaBalanceCents,
        );
      }
    });
  }

  /// Void purchase - reverse stock changes if posted
  /// Also cascade-voids all associated returns to keep stock/accounting consistent.
  ///
  /// 2026-05-13 — accepts an optional [journalEntryService]. When provided,
  /// the cascade reverses the linked purchase-returns' journal entries
  /// before flipping their status. See `sale_dao.voidSale` for the full
  /// rationale (same root-cause symmetry on the purchase side).
  Future<void> voidPurchase(
    int purchaseId, {
    JournalEntryService? journalEntryService,
    int? userId,
  }) {
    return transaction(() async {
      final purchase = await getPurchaseById(purchaseId);
      if (purchase == null) {
        throw Exception('Purchase not found');
      }
      if (purchase.status == 'voided') {
        throw Exception('Purchase already voided');
      }

      // Cascade-void all associated returns first (reverses their stock/accounting)
      final associatedReturns = await (select(
        purchaseReturns,
      )..where((r) => r.purchaseId.equals(purchaseId))).get();
      for (final ret in associatedReturns) {
        if (ret.status != 'voided') {
          // 2026-05-13 — emit the JE reversal BEFORE flipping the row's
          // status, mirroring `PurchaseRepositoryImpl.voidPurchaseReturn`.
          if (journalEntryService != null) {
            await journalEntryService.voidJournalEntriesForSource(
              sourceTable: 'purchase_returns',
              sourceId: ret.id,
              reason: 'Purchase voided — cascade',
              userId: userId,
            );
          }
          await voidPurchaseReturn(ret.id);
        }
      }

      // If posted, reverse stock changes with negative-stock guard
      if (purchase.status == 'posted') {
        final items = await getPurchaseItems(purchaseId);
        final voidAffectedProductIds = <int>{};
        // I4: FIFO products whose batches we deactivate.
        final voidBatchedProductIds = <int>{};

        for (final item in items) {
          final variantId = item.variantId;
          final productId = item.productId;
          if (!await _tracksInventory(productId)) continue;
          voidAffectedProductIds.add(productId);
          final wacSnapshot = await WacMovementService.capture(
            this,
            productId: productId,
            variantId: variantId,
          );
          final grossUnitCost = item.unitCostCents.toBigInt().toInt();
          final lineDiscount = item.discountCents.toBigInt().toInt();
          final discountPerMajorUnit = MeasuredAmount.unitCentsFromTotal(
            totalCents: lineDiscount,
            quantity: item.quantity,
            quantityScale: item.quantityScale,
          );
          final purchasedUnitCost = (item.quantity > 0 && lineDiscount > 0)
              ? (grossUnitCost - discountPerMajorUnit).clamp(0, 1 << 62)
              : grossUnitCost;

          // FIFO safety: if any batch sourced from this purchase line has
          // been (even partially) consumed, voiding the purchase would
          // orphan the linked sales/returns and break the invariant. Refuse
          // — the user must reverse the dependent transactions first. We
          // deactivate untouched batches AFTER stock reversal below.
          if (await _isFifoProduct(productId)) {
            final batchRows = await customSelect(
              'SELECT id, received_quantity, remaining_quantity '
              '  FROM product_batches '
              ' WHERE purchase_item_id = ? AND is_active = 1',
              variables: [Variable.withInt(item.id)],
            ).get();
            for (final r in batchRows) {
              final received = r.read<int>('received_quantity');
              final remaining = r.read<int>('remaining_quantity');
              if (remaining != received) {
                throw Exception(
                  'Cannot void purchase: batch from purchase_item #${item.id} '
                  'has been partially consumed ($remaining of $received remaining). '
                  'Reverse the dependent sales/returns first.',
                );
              }
            }
          }

          if (variantId != null) {
            // Check current stock before deducting
            final variantRow = await customSelect(
              'SELECT stock_quantity FROM product_variants WHERE id = ?',
              variables: [Variable.withInt(variantId)],
            ).getSingleOrNull();
            if (variantRow != null) {
              final currentStock = variantRow.read<int>('stock_quantity');
              if (currentStock < item.quantity) {
                throw Exception(
                  'Cannot void: variant #$variantId stock ($currentStock) '
                  'is less than purchased quantity (${item.quantity}). '
                  'Some items may have been sold or returned.',
                );
              }
            }
            await StockService.adjustStock(
              this,
              productId: productId,
              variantId: variantId,
              quantity: item.quantity,
              direction: StockDirection.decrease,
            );
          } else {
            // Non-variant product: check stock before deducting
            final productRow = await customSelect(
              'SELECT stock_quantity FROM products WHERE id = ?',
              variables: [Variable.withInt(productId)],
            ).getSingleOrNull();
            if (productRow != null) {
              final currentStock = productRow.read<int>('stock_quantity');
              if (currentStock < item.quantity) {
                throw Exception(
                  'Cannot void: product #$productId stock ($currentStock) '
                  'is less than purchased quantity (${item.quantity}). '
                  'Some items may have been sold or returned.',
                );
              }
            }
            await StockService.adjustStock(
              this,
              productId: productId,
              variantId: null,
              quantity: item.quantity,
              direction: StockDirection.decrease,
            );
          }

          if (wacSnapshot != null) {
            await WacMovementService.reverseInbound(
              this,
              snapshot: wacSnapshot,
              removedQty: item.quantity,
              removedUnitCostCents: purchasedUnitCost,
            );
          }

          // 2026-05-18 — Phase 15.2 — Batch deactivation must be SYMMETRIC
          // with batch creation in `postPurchase`. The post path creates a
          // batch row for EVERY tracked product (`if (tracks)`, line 707),
          // regardless of `costing_method`. Pre-Phase-15.2 the void path
          // only deactivated batches for FIFO products, so a posted purchase
          // of a `wac`/`standard` tracked product left an orphan
          // `is_active=1` batch on void — inflating
          // `Σ(active batch remaining × cost)` (the Phase 15 inventory
          // valuation formula) by exactly that batch's value. Root cause of
          // the Inventory drift = 29700¢ (= 3 × 9900) reproduced in
          // `tapix_backup_20260518_051956.db`.
          //
          // The UPDATE is a no-op for untracked products (no batches were
          // created on post), so we can run it unconditionally. We still
          // gate `voidBatchedProductIds` (for the I4 invariant assert) on
          // `_isFifoProduct`, because `BatchService.assertInvariantForProduct`
          // is only meaningful for FIFO products — WAC sales don't decrement
          // batch.remaining_quantity, so the cross-table invariant doesn't
          // hold for WAC after any sale.
          await customUpdate(
            'UPDATE product_batches '
            '   SET is_active = 0, remaining_quantity = 0, updated_at = ? '
            ' WHERE purchase_item_id = ? AND is_active = 1',
            variables: [
              Variable.withString(DateTime.now().toIso8601String()),
              Variable.withInt(item.id),
            ],
            updates: {productBatches},
            updateKind: UpdateKind.update,
          );
          if (await _isFifoProduct(productId)) {
            voidBatchedProductIds.add(productId);
          }
        }

        // Sync products table from variants for ALL affected products via
        // ProductCostService — same single-writer path as postPurchase, so
        // the parent cost on void is also a TRUE weighted average instead
        // of the legacy `MAX(cost_cents)` aggregation. Price columns are
        // intentionally skipped (`syncPrice: false`) because voiding a
        // purchase must not retroactively rewrite the user's retail/
        // wholesale prices, which are governed by sale-side documents.
        for (final productId in voidAffectedProductIds) {
          await ProductCostService.syncProductFromVariants(
            this,
            productId: productId,
            syncPrice: false,
          );
        }

        // I4 (Invariant I1): cross-table invariant for FIFO products.
        for (final productId in voidBatchedProductIds) {
          await BatchService.assertInvariantForProduct(
            this,
            productId: productId,
          );
        }

        // Reverse supplier balance: undo the net delta that was applied on posting.
        // On posting: balance += (totalCents - paidCents).
        // Each subsequent payment also reduced balance.
        // To fully reverse: credit back totalCents, then debit back all payments.
        final totalCents = purchase.totalCents.toBigInt().toInt();
        final payments = await getPurchasePayments(purchaseId);
        final totalPaidCents = payments.fold<int>(
          0,
          (sum, p) => sum + p.amountCents.toBigInt().toInt(),
        );

        // Record reversal transaction for the purchase
        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: purchase.supplierId,
            transactionType: 'purchase_void',
            amountCents: Decimal.fromInt(-totalCents),
            currencyId: purchase.currencyId,
            description: Value('Voided purchase ${purchase.purchaseNumber}'),
            referenceId: Value(purchaseId),
            referenceType: const Value('purchase'),
          ),
        );

        // Record reversal transactions for each payment
        if (totalPaidCents > 0) {
          await into(supplierTransactions).insert(
            SupplierTransactionsCompanion.insert(
              supplierId: purchase.supplierId,
              transactionType: 'payment_reversal',
              amountCents: Decimal.fromInt(totalPaidCents),
              currencyId: purchase.currencyId,
              description: Value(
                'Reversed payments for voided purchase ${purchase.purchaseNumber}',
              ),
              referenceId: Value(purchaseId),
              referenceType: const Value('purchase'),
            ),
          );
        }

        // Net balance change: -(totalCents - totalPaidCents)
        final netReversalCents = totalCents - totalPaidCents;
        await BalanceService.adjustSupplierBalance(
          this,
          supplierId: purchase.supplierId,
          deltaCents: -netReversalCents,
        );
      }

      await updatePurchaseStatus(purchaseId, 'voided', userId: userId);
    });
  }

  /// Delete purchase (only if draft)
  Future<int> deletePurchase(int purchaseId) {
    return transaction(() async {
      final purchase = await getPurchaseById(purchaseId);
      if (purchase == null || purchase.status != 'draft') {
        throw Exception('Cannot delete non-draft purchase');
      }

      // Items are deleted by cascade
      return (delete(purchases)..where((p) => p.id.equals(purchaseId))).go();
    });
  }

  /// Watch purchases by status
  Stream<List<Purchase>> watchPurchasesByStatus(String status) {
    return (select(purchases)
          ..where((p) => p.status.equals(status))
          ..orderBy([(p) => OrderingTerm.desc(p.purchaseDate)]))
        .watch();
  }

  /// Watch purchases by supplier
  Stream<List<Purchase>> watchPurchasesBySupplier(int supplierId) {
    return (select(purchases)
          ..where((p) => p.supplierId.equals(supplierId))
          ..orderBy([(p) => OrderingTerm.desc(p.purchaseDate)]))
        .watch();
  }

  /// Watch upcoming due purchases for a supplier (posted, not fully paid, with due date)
  Stream<List<Purchase>> watchUpcomingDuePurchases(int supplierId) {
    return (select(purchases)
          ..where(
            (p) =>
                p.supplierId.equals(supplierId) &
                p.status.equals('posted') &
                p.dueDate.isNotNull(),
          )
          ..orderBy([(p) => OrderingTerm.asc(p.dueDate)]))
        .watch()
        .map(
          (list) => list.where((p) {
            final total = p.totalCents.toBigInt().toInt();
            final paid = p.paidAmountCents.toBigInt().toInt();
            return paid < total;
          }).toList(),
        );
  }

  /// Search purchases by number, supplier name, or supplier phone
  Stream<List<PurchaseWithSupplier>> searchPurchases(String query) {
    final searchQuery = '%$query%';
    final joinQuery =
        select(purchases).join([
            innerJoin(suppliers, suppliers.id.equalsExp(purchases.supplierId)),
          ])
          ..where(
            purchases.purchaseNumber.like(searchQuery) |
                suppliers.name.like(searchQuery) |
                suppliers.phone.like(searchQuery),
          )
          ..orderBy([OrderingTerm.desc(purchases.purchaseDate)]);

    return joinQuery.watch().map(
      (rows) => rows.map((row) {
        return PurchaseWithSupplier(
          purchase: row.readTable(purchases),
          supplier: row.readTable(suppliers),
        );
      }).toList(),
    );
  }

  /// Watch product search terms for all purchases (product name, barcode, SKU).
  Stream<Map<int, List<String>>> watchPurchaseProductSearchTerms() {
    final query = select(purchaseItems).join([
      innerJoin(products, products.id.equalsExp(purchaseItems.productId)),
      leftOuterJoin(
        productVariants,
        productVariants.id.equalsExp(purchaseItems.variantId),
      ),
    ]);

    return query.watch().map((rows) {
      final map = <int, List<String>>{};
      for (final row in rows) {
        final item = row.readTable(purchaseItems);
        final product = row.readTable(products);
        final variant = row.readTableOrNull(productVariants);
        final terms = <String>[];
        terms.add(product.name);
        if (product.nameAr != null) terms.add(product.nameAr!);
        if (product.nameFr != null) terms.add(product.nameFr!);
        if (product.barcode != null) terms.add(product.barcode!);
        if (product.sku != null) terms.add(product.sku!);
        if (variant?.barcode != null) terms.add(variant!.barcode!);
        if (variant?.sku != null) terms.add(variant!.sku!);
        map.putIfAbsent(item.purchaseId, () => []).addAll(terms);
      }
      return map;
    });
  }

  /// Get dashboard stats using SQL aggregation (no full-table load).
  Future<PurchaseDashboardStats> getDashboardStats() async {
    final nowIso = DateTime.now().toIso8601String();

    // Single aggregation query for all purchase stats
    // COALESCE ensures NULL (from empty table) becomes 0
    final statsRow = await customSelect(
      'SELECT '
      "  COALESCE(SUM(CASE WHEN status != 'voided' THEN 1 ELSE 0 END), 0) AS total_count, "
      "  COALESCE(SUM(CASE WHEN status IN ('draft', 'pending') THEN 1 ELSE 0 END), 0) AS draft_count, "
      "  COALESCE(SUM(CASE WHEN status = 'posted' THEN 1 ELSE 0 END), 0) AS posted_count, "
      "  COALESCE(SUM(CASE WHEN status = 'posted' THEN total_cents ELSE 0 END), 0) AS total_posted_cents, "
      "  COALESCE(SUM(CASE WHEN status = 'posted' THEN paid_amount_cents ELSE 0 END), 0) AS total_paid_cents, "
      "  COALESCE(SUM(CASE WHEN status = 'posted' AND due_date IS NOT NULL AND due_date < ? "
      '    AND paid_amount_cents < total_cents THEN 1 ELSE 0 END), 0) AS overdue_count '
      'FROM purchases',
      variables: [Variable.withString(nowIso)],
    ).getSingle();

    // Returns count via SQL
    final returnsRow = await customSelect(
      'SELECT COUNT(*) AS returns_count FROM purchase_returns',
    ).getSingle();

    final totalPostedCents = statsRow.read<int>('total_posted_cents');
    final totalPaidCents = statsRow.read<int>('total_paid_cents');
    final payable = (totalPostedCents - totalPaidCents).clamp(0, 1 << 62);

    return PurchaseDashboardStats(
      totalCount: statsRow.read<int>('total_count'),
      draftCount: statsRow.read<int>('draft_count'),
      postedCount: statsRow.read<int>('posted_count'),
      totalPayableCents: payable,
      totalPaidCents: totalPaidCents,
      overdueCount: statsRow.read<int>('overdue_count'),
      returnsCount: returnsRow.read<int>('returns_count'),
    );
  }

  /// Watch dashboard stats
  Stream<PurchaseDashboardStats> watchDashboardStats() {
    return watchAllPurchases().asyncMap((_) => getDashboardStats());
  }

  // ==================== PURCHASE ITEMS ====================

  /// Add item to purchase
  Future<int> addPurchaseItem(PurchaseItemsCompanion item) {
    return into(purchaseItems).insert(item);
  }

  /// Update a single purchase item.
  ///
  /// I1 (defense-in-depth): only items belonging to a `draft`/`pending`
  /// purchase may be updated. Editing a single item on a posted purchase
  /// would silently desync opening batches and the GL.
  Future<bool> updatePurchaseItem(int itemId, PurchaseItemsCompanion item) {
    return transaction(() async {
      final parentRow = await customSelect(
        'SELECT p.id AS pid, p.status AS status FROM purchase_items pi '
        'INNER JOIN purchases p ON p.id = pi.purchase_id '
        'WHERE pi.id = ?',
        variables: [Variable.withInt(itemId)],
      ).getSingleOrNull();
      if (parentRow == null) return false;
      final status = parentRow.read<String>('status');
      if (status != 'draft' && status != 'pending') {
        final pid = parentRow.read<int>('pid');
        throw StateError(
          'I1 violation: cannot edit an item on a "$status" purchase '
          '(#$pid). Void it and create a new one instead.',
        );
      }
      return (update(purchaseItems)..where((i) => i.id.equals(itemId)))
          .write(item)
          .then((rows) => rows > 0);
    });
  }

  /// Delete a single purchase item.
  ///
  /// I1 (defense-in-depth): only items belonging to a `draft`/`pending`
  /// purchase may be deleted. Removing an item from a posted purchase
  /// would silently desync opening batches and the GL.
  Future<int> deletePurchaseItem(int itemId) {
    return transaction(() async {
      final parentRow = await customSelect(
        'SELECT p.id AS pid, p.status AS status FROM purchase_items pi '
        'INNER JOIN purchases p ON p.id = pi.purchase_id '
        'WHERE pi.id = ?',
        variables: [Variable.withInt(itemId)],
      ).getSingleOrNull();
      if (parentRow == null) return 0;
      final status = parentRow.read<String>('status');
      if (status != 'draft' && status != 'pending') {
        final pid = parentRow.read<int>('pid');
        throw StateError(
          'I1 violation: cannot delete an item from a "$status" purchase '
          '(#$pid). Void it and create a new one instead.',
        );
      }
      return (delete(purchaseItems)..where((i) => i.id.equals(itemId))).go();
    });
  }

  /// Get items with expiry dates approaching (within days)
  Stream<List<PurchaseItemWithDetails>> watchExpiringItems(int withinDays) {
    final cutoff = DateTime.now().add(Duration(days: withinDays));
    final query =
        select(purchaseItems).join([
          innerJoin(products, products.id.equalsExp(purchaseItems.productId)),
          leftOuterJoin(
            productVariants,
            productVariants.id.equalsExp(purchaseItems.variantId),
          ),
        ])..where(
          purchaseItems.expiryDate.isNotNull() &
              purchaseItems.expiryDate.isSmallerOrEqualValue(cutoff),
        );

    return query.watch().map(
      (rows) => rows.map((row) {
        return PurchaseItemWithDetails(
          item: row.readTable(purchaseItems),
          product: row.readTable(products),
          variant: row.readTableOrNull(productVariants),
        );
      }).toList(),
    );
  }

  /// Get expiry info for a specific product (all purchase items with expiry dates)
  Future<List<({int quantity, DateTime expiryDate})>> getProductExpiryInfo(
    int productId,
  ) async {
    final query = select(purchaseItems)
      ..where((i) => i.productId.equals(productId) & i.expiryDate.isNotNull())
      ..orderBy([(i) => OrderingTerm.asc(i.expiryDate)]);

    final rows = await query.get();
    return rows
        .map((r) => (quantity: r.quantity, expiryDate: r.expiryDate!))
        .toList();
  }

  // ==================== PURCHASE RETURNS ====================

  Future<void> updatePurchaseReturnTotals(int returnId) async {
    final totalsRow = await customSelect(
      'SELECT '
      '  COALESCE(SUM(pri.subtotal_cents), 0) AS subtotal, '
      '  COALESCE(SUM(pri.discount_cents), 0) AS discount, '
      '  COALESCE(SUM(pri.tax_cents), 0) AS tax, '
      '  COALESCE(SUM(pri.refund_cents), 0) AS total '
      'FROM purchase_return_items pri '
      'WHERE pri.return_id = ?',
      variables: [Variable.withInt(returnId)],
    ).getSingle();

    final subtotalCents = totalsRow.read<int>('subtotal');
    final discountCents = totalsRow.read<int>('discount');
    final taxCents = totalsRow.read<int>('tax');
    final totalCents = totalsRow.read<int>('total');

    await customUpdate(
      'UPDATE purchase_returns '
      'SET subtotal_cents = ?, discount_cents = ?, tax_cents = ?, total_cents = ? '
      'WHERE id = ?',
      variables: [
        Variable.withInt(subtotalCents),
        Variable.withInt(discountCents),
        Variable.withInt(taxCents),
        Variable.withInt(totalCents),
        Variable.withInt(returnId),
      ],
      updates: {purchaseReturns},
      updateKind: UpdateKind.update,
    );
  }

  /// Watch all purchase returns with supplier info (name, phone)
  Stream<List<PurchaseReturnWithParty>> watchAllPurchaseReturnsWithParty() {
    final query = select(purchaseReturns).join([
      innerJoin(purchases, purchases.id.equalsExp(purchaseReturns.purchaseId)),
      innerJoin(suppliers, suppliers.id.equalsExp(purchases.supplierId)),
    ])..orderBy([OrderingTerm.desc(purchaseReturns.returnDate)]);

    return query.watch().map(
      (rows) => rows.map((row) {
        return PurchaseReturnWithParty(
          purchaseReturn: row.readTable(purchaseReturns),
          supplierName: row.readTable(suppliers).name,
          supplierPhone: row.readTable(suppliers).phone,
        );
      }).toList(),
    );
  }

  /// Watch all purchase returns (raw, without party info)
  Stream<List<PurchaseReturn>> watchAllPurchaseReturns() {
    return (select(
      purchaseReturns,
    )..orderBy([(r) => OrderingTerm.desc(r.returnDate)])).watch();
  }

  /// Watch product search terms for purchase return items.
  Stream<Map<String, List<String>>> watchPurchaseReturnProductSearchTerms() {
    final linkedQuery = select(purchaseReturnItems).join([
      innerJoin(
        purchaseItems,
        purchaseItems.id.equalsExp(purchaseReturnItems.purchaseItemId),
      ),
      innerJoin(products, products.id.equalsExp(purchaseItems.productId)),
      leftOuterJoin(
        productVariants,
        productVariants.id.equalsExp(purchaseItems.variantId),
      ),
    ]);

    return linkedQuery.watch().map((rows) {
      final map = <String, List<String>>{};
      for (final row in rows) {
        final item = row.readTable(purchaseReturnItems);
        final product = row.readTable(products);
        final variant = row.readTableOrNull(productVariants);
        final key = 'PR-${item.returnId}';
        final terms = <String>[];
        terms.add(product.name);
        if (product.nameAr != null) terms.add(product.nameAr!);
        if (product.nameFr != null) terms.add(product.nameFr!);
        if (product.barcode != null) terms.add(product.barcode!);
        if (product.sku != null) terms.add(product.sku!);
        if (variant?.barcode != null) terms.add(variant!.barcode!);
        if (variant?.sku != null) terms.add(variant!.sku!);
        map.putIfAbsent(key, () => []).addAll(terms);
      }
      return map;
    });
  }

  /// Get purchase return by ID
  Future<PurchaseReturn?> getPurchaseReturnById(int id) {
    return (select(
      purchaseReturns,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  /// Generate next return number
  Future<String> generateReturnNumber() =>
      DocumentNumberService(attachedDatabase).nextPurchaseReturn();

  /// Create purchase return with items
  Future<int> createPurchaseReturn(
    PurchaseReturnsCompanion returnData,
    List<PurchaseReturnItemsCompanion> items,
  ) {
    return transaction(() async {
      final returnId = await into(purchaseReturns).insert(returnData);

      for (final item in items) {
        final itemWithReturnId = item.copyWith(returnId: Value(returnId));
        await into(purchaseReturnItems).insert(itemWithReturnId);
      }

      return returnId;
    });
  }

  /// Post purchase return - update variant stock based on disposition.
  /// Validates that return quantities don't exceed available (purchased - already returned).
  ///
  /// Posting a purchase return DECREASES stock (goods leaving the warehouse
  /// back to the supplier). If [allowNegativeStock] is false and current stock
  /// is insufficient, the operation is rejected — matching the inventory
  /// policy used by SAP / NetSuite / Odoo / QuickBooks.
  Future<void> postPurchaseReturn(
    int returnId, {
    int? userId,
    bool allowNegativeStock = false,
  }) {
    return transaction(() async {
      final returnData = await getPurchaseReturnById(returnId);
      if (returnData == null) {
        throw Exception('Return not found');
      }
      if (returnData.status == 'posted') {
        throw Exception('Return already posted');
      }

      // Validate return quantities don't exceed available
      final returnItemsQuery = select(purchaseReturnItems).join([
        innerJoin(
          purchaseItems,
          purchaseItems.id.equalsExp(purchaseReturnItems.purchaseItemId),
        ),
      ])..where(purchaseReturnItems.returnId.equals(returnId));

      final returnItemRows = await returnItemsQuery.get();
      for (final row in returnItemRows) {
        final returnItem = row.readTable(purchaseReturnItems);
        final purchaseItem = row.readTable(purchaseItems);

        // Check total already returned for this purchase item (excluding voided returns)
        final alreadyReturned = await getReturnedQuantity(purchaseItem.id);
        // Subtract this return's own quantity since it's not yet posted
        final previouslyReturned = alreadyReturned - returnItem.quantity;
        final maxReturnable = purchaseItem.quantity - previouslyReturned;

        if (returnItem.quantity > maxReturnable) {
          throw Exception(
            'Cannot return ${returnItem.quantity} units of item #${purchaseItem.id}. '
            'Only $maxReturnable available (purchased: ${purchaseItem.quantity}, '
            'already returned: $previouslyReturned).',
          );
        }
      }

      // Always deduct stock for purchase returns regardless of disposition.
      // The goods are leaving inventory whether restocked, refunded, written off,
      // or sent for repair. Disposition only affects financial treatment.
      {
        final returnAffectedProductIds = <int>{};
        // I4: FIFO products whose batch ledger we consume from on this return.
        final returnBatchedProductIds = <int>{};
        for (final row in returnItemRows) {
          final returnItem = row.readTable(purchaseReturnItems);
          final purchaseItem = row.readTable(purchaseItems);
          final variantId = purchaseItem.variantId;
          final productId = purchaseItem.productId;
          if (!await _tracksInventory(productId)) {
            await (update(
              purchaseReturnItems,
            )..where((i) => i.id.equals(returnItem.id))).write(
              PurchaseReturnItemsCompanion(
                unitCostAtPostCents: Value(Decimal.zero),
              ),
            );
            continue;
          }
          returnAffectedProductIds.add(productId);

          final valuationSnapshot =
              await InventoryValuationDeltaService.capture(
                this,
                productId: productId,
                variantId: variantId,
              );

          // A WAC outflow removes inventory at the average immediately
          // before posting. Freeze it on the return line so GL rebuilds and
          // a later void never depend on a changed live product cost.
          final wacSnapshot = await WacMovementService.capture(
            this,
            productId: productId,
            variantId: variantId,
          );
          final frozenUnitCost =
              returnItem.unitCostAtPostCents?.toBigInt().toInt() ??
              wacSnapshot?.unitCostCents ??
              purchaseItem.unitCostCents.toBigInt().toInt();
          await (update(
            purchaseReturnItems,
          )..where((i) => i.id.equals(returnItem.id))).write(
            PurchaseReturnItemsCompanion(
              unitCostAtPostCents: Value(Decimal.fromInt(frozenUnitCost)),
            ),
          );

          if (variantId != null) {
            // Guard against negative stock unless explicitly allowed by policy.
            if (!allowNegativeStock) {
              final variantRow = await customSelect(
                'SELECT stock_quantity FROM product_variants WHERE id = ?',
                variables: [Variable.withInt(variantId)],
              ).getSingleOrNull();
              if (variantRow != null) {
                final currentStock = variantRow.read<int>('stock_quantity');
                if (currentStock < returnItem.quantity) {
                  throw Exception(
                    'Cannot return: variant #$variantId stock ($currentStock) '
                    'is less than return quantity (${returnItem.quantity}).',
                  );
                }
              }
            }

            await StockService.adjustStock(
              this,
              productId: productId,
              variantId: variantId,
              quantity: returnItem.quantity,
              direction: StockDirection.decrease,
            );

            // FIFO sync: deduct oldest batches for FIFO products and link
            // the consumption to this return item so a later void can mirror
            // it back precisely to the same batches at the FROZEN unit cost.
            if (await _isFifoProduct(productId)) {
              await BatchService.consumeFifo(
                this,
                productId: productId,
                variantId: variantId,
                quantity: returnItem.quantity,
                consumptionType: 'purchase_return',
                purchaseReturnItemId: returnItem.id,
              );
              returnBatchedProductIds.add(productId);
            }
          } else {
            // Non-variant product: check stock unless explicitly allowed.
            if (!allowNegativeStock) {
              final productRow = await customSelect(
                'SELECT stock_quantity FROM products WHERE id = ?',
                variables: [Variable.withInt(productId)],
              ).getSingleOrNull();
              if (productRow != null) {
                final currentStock = productRow.read<int>('stock_quantity');
                if (currentStock < returnItem.quantity) {
                  throw Exception(
                    'Cannot return: product #$productId stock ($currentStock) '
                    'is less than return quantity (${returnItem.quantity}).',
                  );
                }
              }
            }
            await StockService.adjustStock(
              this,
              productId: productId,
              variantId: null,
              quantity: returnItem.quantity,
              direction: StockDirection.decrease,
            );

            // FIFO sync (non-variant branch): same intent as the variant
            // branch above — BatchService resolves null variantId to the
            // product's default variant internally.
            if (await _isFifoProduct(productId)) {
              await BatchService.consumeFifo(
                this,
                productId: productId,
                variantId: null,
                quantity: returnItem.quantity,
                consumptionType: 'purchase_return',
                purchaseReturnItemId: returnItem.id,
              );
              returnBatchedProductIds.add(productId);
            }
          }

          final inventoryValue = valuationSnapshot != null
              ? -await InventoryValuationDeltaService.signedDeltaAfter(
                  this,
                  valuationSnapshot,
                )
              : await _purchaseReturnBatchValueCents(
                  returnItem.id,
                  returnItem.quantityScale,
                );
          await (update(
            purchaseReturnItems,
          )..where((i) => i.id.equals(returnItem.id))).write(
            PurchaseReturnItemsCompanion(
              inventoryValueAtPostCents: Value(Decimal.fromInt(inventoryValue)),
            ),
          );
        }

        // Sync products.stock_quantity from variants
        for (final productId in returnAffectedProductIds) {
          await StockService.syncProductStockFromVariants(
            this,
            productId: productId,
          );
        }

        // I4 (Invariant I1): cross-table invariant for FIFO products.
        for (final productId in returnBatchedProductIds) {
          await BatchService.assertInvariantForProduct(
            this,
            productId: productId,
          );
        }
      }

      // ── Atomic counters: bump qty_returned_linked on each purchase_item.
      //    Phase 0 hard cap — keeps the linked + adjustment counters in
      //    sync so subsequent adjustment returns can never exceed history.
      for (final row in returnItemRows) {
        final returnItem = row.readTable(purchaseReturnItems);
        await customStatement(
          'UPDATE purchase_items '
          'SET qty_returned_linked = qty_returned_linked + ? '
          'WHERE id = ?',
          [returnItem.quantity, returnItem.purchaseItemId],
        );
      }

      // Update return status to posted
      await (update(purchaseReturns)..where((r) => r.id.equals(returnId)))
          .write(const PurchaseReturnsCompanion(status: Value('posted')));

      // Create supplier transaction and adjust balance based on refund method
      final purchase = await getPurchaseById(returnData.purchaseId);
      if (purchase != null) {
        final refundCents = returnData.totalCents.toBigInt().toInt();
        final refundMethod = returnData.refundMethod;

        // Determine transaction type based on refund method
        // - credit: supplier owes us → deduct from balance (credit note)
        // - cash/cheque: supplier already paid us back → no balance change
        final isCreditRefund = refundMethod == 'credit';
        final txType = isCreditRefund ? 'credit_note' : 'refund';

        // Record supplier transaction for audit trail
        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: purchase.supplierId,
            transactionType: txType,
            transactionNumber: Value(returnData.returnNumber),
            amountCents: Decimal.fromInt(-refundCents),
            currencyId: purchase.currencyId,
            description: Value(
              'Purchase return ${returnData.returnNumber} ($refundMethod)',
            ),
            referenceId: Value(returnId),
            referenceType: const Value('purchase_return'),
          ),
        );

        // Only adjust supplier balance for credit refunds.
        // Cash/cheque means the supplier already gave us the money back,
        // so the balance (what we owe them) doesn't change.
        if (isCreditRefund) {
          await BalanceService.adjustSupplierBalance(
            this,
            supplierId: purchase.supplierId,
            deltaCents: -refundCents,
          );
        }
      }
    });
  }

  /// Watch purchase return items (raw)
  Stream<List<PurchaseReturnItem>> watchPurchaseReturnItems(int returnId) {
    return (select(
      purchaseReturnItems,
    )..where((i) => i.returnId.equals(returnId))).watch();
  }

  /// Watch purchase return items with full product details (name, color, size, SKU)
  Stream<List<PurchaseReturnItemWithDetails>>
  watchPurchaseReturnItemsWithDetails(int returnId) {
    final query = select(purchaseReturnItems).join([
      innerJoin(
        purchaseItems,
        purchaseItems.id.equalsExp(purchaseReturnItems.purchaseItemId),
      ),
      innerJoin(products, products.id.equalsExp(purchaseItems.productId)),
      leftOuterJoin(
        productVariants,
        productVariants.id.equalsExp(purchaseItems.variantId),
      ),
      leftOuterJoin(
        productColors,
        productColors.id.equalsExp(productVariants.colorId),
      ),
      leftOuterJoin(sizes, sizes.id.equalsExp(productVariants.sizeId)),
    ])..where(purchaseReturnItems.returnId.equals(returnId));

    return query.watch().map(
      (rows) => rows.map((row) {
        return PurchaseReturnItemWithDetails(
          returnItem: row.readTable(purchaseReturnItems),
          product: row.readTable(products),
          variant: row.readTableOrNull(productVariants),
          colorName: row.readTableOrNull(productColors)?.name,
          colorHex: row.readTableOrNull(productColors)?.hexCode,
          sizeName: row.readTableOrNull(sizes)?.name,
        );
      }).toList(),
    );
  }

  /// Get purchase return items with full product details
  Future<List<PurchaseReturnItemWithDetails>> getPurchaseReturnItemsWithDetails(
    int returnId,
  ) async {
    final query = select(purchaseReturnItems).join([
      innerJoin(
        purchaseItems,
        purchaseItems.id.equalsExp(purchaseReturnItems.purchaseItemId),
      ),
      innerJoin(products, products.id.equalsExp(purchaseItems.productId)),
      leftOuterJoin(
        productVariants,
        productVariants.id.equalsExp(purchaseItems.variantId),
      ),
      leftOuterJoin(
        productColors,
        productColors.id.equalsExp(productVariants.colorId),
      ),
      leftOuterJoin(sizes, sizes.id.equalsExp(productVariants.sizeId)),
    ])..where(purchaseReturnItems.returnId.equals(returnId));

    final rows = await query.get();
    return rows.map((row) {
      return PurchaseReturnItemWithDetails(
        returnItem: row.readTable(purchaseReturnItems),
        product: row.readTable(products),
        variant: row.readTableOrNull(productVariants),
        colorName: row.readTableOrNull(productColors)?.name,
        colorHex: row.readTableOrNull(productColors)?.hexCode,
        sizeName: row.readTableOrNull(sizes)?.name,
      );
    }).toList();
  }

  /// Void a purchase return
  Future<void> voidPurchaseReturn(int returnId) {
    return transaction(() async {
      final returnData = await getPurchaseReturnById(returnId);
      if (returnData == null) throw Exception('Return not found');
      if (returnData.status == 'voided') {
        throw Exception('Return already voided');
      }

      // If posted, always reverse stock changes (mirrors postPurchaseReturn).
      if (returnData.status == 'posted') {
        final query = select(purchaseReturnItems).join([
          innerJoin(
            purchaseItems,
            purchaseItems.id.equalsExp(purchaseReturnItems.purchaseItemId),
          ),
        ])..where(purchaseReturnItems.returnId.equals(returnId));

        final items = await query.get();
        final voidReturnAffectedProductIds = <int>{};
        // I4: FIFO products whose batches we restore to.
        final voidReturnBatchedProductIds = <int>{};
        for (final row in items) {
          final returnItem = row.readTable(purchaseReturnItems);
          final purchaseItem = row.readTable(purchaseItems);
          if (!await _tracksInventory(purchaseItem.productId)) continue;
          voidReturnAffectedProductIds.add(purchaseItem.productId);

          final wacSnapshot = await WacMovementService.capture(
            this,
            productId: purchaseItem.productId,
            variantId: purchaseItem.variantId,
          );
          final frozenUnitCost =
              returnItem.unitCostAtPostCents?.toBigInt().toInt() ??
              wacSnapshot?.unitCostCents ??
              purchaseItem.unitCostCents.toBigInt().toInt();

          await StockService.adjustStock(
            this,
            productId: purchaseItem.productId,
            variantId: purchaseItem.variantId,
            quantity: returnItem.quantity,
            direction: StockDirection.increase,
          );

          if (wacSnapshot != null) {
            await WacMovementService.applyInbound(
              this,
              snapshot: wacSnapshot,
              addedQty: returnItem.quantity,
              inboundUnitCostCents: frozenUnitCost,
            );
          }

          // FIFO restoration: mirror every 'out' consumption row this
          // return item produced back into its source batch at the FROZEN
          // unit_cost. No-op for WAC products (no consumption rows exist).
          await BatchService.restoreConsumptions(
            this,
            reverseConsumptionType: 'purchase_return_void',
            purchaseReturnItemId: returnItem.id,
          );
          if (await _isFifoProduct(purchaseItem.productId)) {
            voidReturnBatchedProductIds.add(purchaseItem.productId);
          }
        }

        // Sync products.stock_quantity from variants
        for (final productId in voidReturnAffectedProductIds) {
          await StockService.syncProductStockFromVariants(
            this,
            productId: productId,
          );
        }

        // I4 (Invariant I1): cross-table invariant for FIFO products.
        for (final productId in voidReturnBatchedProductIds) {
          await BatchService.assertInvariantForProduct(
            this,
            productId: productId,
          );
        }

        // ── Atomic counters: reverse qty_returned_linked on each
        //    purchase_item so the cap returns to its pre-post state.
        for (final row in items) {
          final returnItem = row.readTable(purchaseReturnItems);
          await customStatement(
            'UPDATE purchase_items '
            'SET qty_returned_linked = qty_returned_linked - ? '
            'WHERE id = ? AND qty_returned_linked >= ?',
            [
              returnItem.quantity,
              returnItem.purchaseItemId,
              returnItem.quantity,
            ],
          );
        }
      }

      // Reverse supplier accounting if return was posted
      if (returnData.status == 'posted') {
        final purchase = await getPurchaseById(returnData.purchaseId);
        if (purchase != null) {
          final refundCents = returnData.totalCents.toBigInt().toInt();
          final isCreditRefund = returnData.refundMethod == 'credit';

          // Record reversal transaction for audit trail (always)
          final reversalType = isCreditRefund
              ? 'credit_note_reversal'
              : 'refund_reversal';
          await into(supplierTransactions).insert(
            SupplierTransactionsCompanion.insert(
              supplierId: purchase.supplierId,
              transactionType: reversalType,
              amountCents: Decimal.fromInt(refundCents),
              currencyId: purchase.currencyId,
              description: Value(
                'Voided purchase return ${returnData.returnNumber}',
              ),
              referenceId: Value(returnId),
              referenceType: const Value('purchase_return'),
            ),
          );

          // Only restore supplier balance for credit refunds.
          // Cash/cheque refunds did not change the balance on posting,
          // so voiding them should not change it either.
          if (isCreditRefund) {
            await BalanceService.adjustSupplierBalance(
              this,
              supplierId: purchase.supplierId,
              deltaCents: refundCents,
            );
          }
        }
      }

      await (update(purchaseReturns)..where((r) => r.id.equals(returnId)))
          .write(const PurchaseReturnsCompanion(status: Value('voided')));
    });
  }

  // ==================== PURCHASE PAYMENTS ====================

  /// Watch all payments for a purchase
  Stream<List<PurchasePayment>> watchPurchasePayments(int purchaseId) {
    return (select(purchasePayments)
          ..where((p) => p.purchaseId.equals(purchaseId))
          ..orderBy([(p) => OrderingTerm.desc(p.paymentDate)]))
        .watch();
  }

  /// Get all payments for a purchase
  Future<List<PurchasePayment>> getPurchasePayments(int purchaseId) {
    return (select(purchasePayments)
          ..where((p) => p.purchaseId.equals(purchaseId))
          ..orderBy([(p) => OrderingTerm.desc(p.paymentDate)]))
        .get();
  }

  /// Record a payment for a purchase and update paid_amount_cents
  Future<int> recordPayment(PurchasePaymentsCompanion payment) {
    return transaction(() async {
      final paymentId = await into(purchasePayments).insert(payment);

      final purchase = await getPurchaseById(payment.purchaseId.value);
      if (purchase == null) {
        throw Exception('Purchase not found');
      }

      // Recalculate total paid
      final payments = await getPurchasePayments(payment.purchaseId.value);
      final totalPaid = payments.fold<int>(
        0,
        (sum, p) => sum + p.amountCents.toBigInt().toInt(),
      );

      await (update(
        purchases,
      )..where((p) => p.id.equals(payment.purchaseId.value))).write(
        PurchasesCompanion(
          paidAmountCents: Value(Decimal.fromInt(totalPaid)),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Supplier accounting: only posted purchases affect supplier balance.
      if (purchase.status == 'posted') {
        final amountCents = payment.amountCents.value.toBigInt().toInt();
        final paymentNumber = await DocumentNumberService(
          attachedDatabase,
        ).nextSupplierTransaction('CPS');

        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: purchase.supplierId,
            transactionType: 'payment',
            transactionNumber: Value(paymentNumber),
            amountCents: Decimal.fromInt(-amountCents),
            currencyId: purchase.currencyId,
            description: Value('Payment for ${purchase.purchaseNumber}'),
            referenceId: Value(paymentId),
            referenceType: const Value('purchase_payment'),
          ),
        );

        await BalanceService.adjustSupplierBalance(
          this,
          supplierId: purchase.supplierId,
          deltaCents: -amountCents,
        );
      }

      return paymentId;
    });
  }

  /// Delete a payment and recalculate paid_amount_cents
  Future<void> deletePayment(int paymentId) {
    return transaction(() async {
      final payment = await (select(
        purchasePayments,
      )..where((p) => p.id.equals(paymentId))).getSingleOrNull();
      if (payment == null) return;

      final purchase = await getPurchaseById(payment.purchaseId);

      await (delete(
        purchasePayments,
      )..where((p) => p.id.equals(paymentId))).go();

      // Recalculate total paid
      final remaining = await getPurchasePayments(payment.purchaseId);
      final totalPaid = remaining.fold<int>(
        0,
        (sum, p) => sum + p.amountCents.toBigInt().toInt(),
      );

      await (update(
        purchases,
      )..where((p) => p.id.equals(payment.purchaseId))).write(
        PurchasesCompanion(
          paidAmountCents: Value(Decimal.fromInt(totalPaid)),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // Reverse supplier balance effect if purchase is posted.
      if (purchase != null && purchase.status == 'posted') {
        final amountCents = payment.amountCents.toBigInt().toInt();

        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: purchase.supplierId,
            transactionType: 'payment_reversal',
            amountCents: Decimal.fromInt(amountCents),
            currencyId: purchase.currencyId,
            description: Value(
              'Deleted payment for ${purchase.purchaseNumber}',
            ),
            referenceId: Value(paymentId),
            referenceType: const Value('purchase_payment'),
          ),
        );

        await BalanceService.adjustSupplierBalance(
          this,
          supplierId: purchase.supplierId,
          deltaCents: amountCents,
        );
      }
    });
  }

  /// Get total already returned quantity for a specific purchase item.
  ///
  /// Returns the union of two history streams:
  ///   • `purchase_return_items` rows where the parent
  ///     `purchase_returns.status != 'voided'` (linked-return path).
  ///   • `purchase_items.qty_returned_adjustment` — FIFO-allocated quantity
  ///     that posted **adjustment** (unlinked) purchase returns have
  ///     attributed to this purchase_item via
  ///     `AdjustmentReturnDao._allocatePurchaseItemsForAdjustment`. The
  ///     counter is bumped on `postPurchaseAdjReturn` and decremented on
  ///     void, so it is always the current authoritative adjustment-side
  ///     total per line.
  ///
  /// Why both? Adjustment returns are not linked to a purchase_item via
  /// FK, so the legacy SQL silently missed adjustment-return quantity.
  /// The cap in `postPurchaseReturn` then allowed a linked return to
  /// over-return units that were already adjusted — driving GL inventory
  /// above on-hand stock. Including the counter closes the bypass.
  Future<int> getReturnedQuantity(int purchaseItemId) async {
    final rows = await customSelect(
      'SELECT '
      '  COALESCE(('
      '    SELECT SUM(pri.quantity) FROM purchase_return_items pri '
      '    JOIN purchase_returns pr ON pr.id = pri.return_id '
      "    WHERE pri.purchase_item_id = ? AND pr.status != 'voided'"
      '  ), 0) '
      '  + '
      '  COALESCE(('
      '    SELECT qty_returned_adjustment FROM purchase_items WHERE id = ?'
      '  ), 0) AS total',
      variables: [
        Variable.withInt(purchaseItemId),
        Variable.withInt(purchaseItemId),
      ],
    ).get();
    return rows.isEmpty ? 0 : rows.first.read<int>('total');
  }

  /// Amounts already reversed by non-voided returns linked to this purchase
  /// line. Adjustment-return amounts are excluded from the financial history
  /// but remain part of [getReturnedQuantity] for the quantity cap.
  Future<LinkedReturnHistory> getLinkedReturnHistory(int purchaseItemId) async {
    final row = await customSelect(
      'SELECT '
      '  COALESCE(SUM(pri.quantity), 0) AS quantity, '
      '  COALESCE(SUM(pri.subtotal_cents), 0) AS subtotal_cents, '
      '  COALESCE(SUM(pri.discount_cents), 0) AS discount_cents, '
      '  COALESCE(SUM(pri.tax_cents), 0) AS tax_cents, '
      '  COALESCE(SUM(pri.refund_cents), 0) AS refund_cents '
      'FROM purchase_return_items pri '
      'JOIN purchase_returns pr ON pr.id = pri.return_id '
      "WHERE pri.purchase_item_id = ? AND pr.status != 'voided'",
      variables: [Variable.withInt(purchaseItemId)],
    ).getSingle();

    return LinkedReturnHistory(
      quantity: row.read<int>('quantity'),
      subtotalCents: row.read<int>('subtotal_cents'),
      discountCents: row.read<int>('discount_cents'),
      taxCents: row.read<int>('tax_cents'),
      refundCents: row.read<int>('refund_cents'),
    );
  }

  /// Actual inventory valuation removed by a posted (linked) purchase return.
  ///
  /// SINGLE SOURCE OF TRUTH for the 1200 Inventory GL leg. It MUST mirror the
  /// cost basis used by `getTotalInventoryValueCents`, otherwise 1200 drifts
  /// away from Σ(stock×cost):
  ///   • FIFO products → Σ(batch_consumptions.quantity × unit_cost_cents)
  ///     recorded by `BatchService.consumeFifo` for this return's items. The
  ///     goods leave specific batches at their FROZEN per-batch cost, which is
  ///     exactly how the batch ledger is valued.
  ///   • WAC products  → qty × the variant/product CURRENT cost (an outflow
  ///     never changes the WAC unit cost, so current == the value removed).
  ///
  /// The difference between the refund (net) and this cost is a purchase price
  /// variance that the journal policy routes to 4100 (contra-COGS).
  Future<int> computePurchaseReturnInventoryCostCents(int returnId) async {
    final rows = await (select(purchaseReturnItems).join([
      innerJoin(
        purchaseItems,
        purchaseItems.id.equalsExp(purchaseReturnItems.purchaseItemId),
      ),
    ])..where(purchaseReturnItems.returnId.equals(returnId))).get();

    int total = 0;
    for (final row in rows) {
      final ri = row.readTable(purchaseReturnItems);
      final pi = row.readTable(purchaseItems);
      if (!await _tracksInventory(pi.productId)) continue;

      if (ri.inventoryValueAtPostCents != null) {
        total += ri.inventoryValueAtPostCents!.toBigInt().toInt();
        continue;
      }

      if (await _isFifoProduct(pi.productId)) {
        final costRow = await customSelect(
          'SELECT CAST((COALESCE(SUM(quantity * unit_cost_cents), 0) + '
          '${ri.quantityScale ~/ 2}) / ${ri.quantityScale} AS INTEGER) AS c '
          'FROM batch_consumptions '
          "WHERE purchase_return_item_id = ? AND direction = 'out'",
          variables: [Variable.withInt(ri.id)],
        ).getSingle();
        total += costRow.read<int>('c');
      } else if (ri.unitCostAtPostCents != null) {
        total += MeasuredAmount.cents(
          unitCents: ri.unitCostAtPostCents!.toBigInt().toInt(),
          quantity: ri.quantity,
          quantityScale: ri.quantityScale,
        );
      } else {
        // Legacy rows posted before the snapshot column was populated.
        // This fallback is intentionally last-resort only; all new posts
        // freeze the WAC above.
        int unitCost = 0;
        if (pi.variantId != null) {
          final r = await customSelect(
            'SELECT cost_cents FROM product_variants WHERE id = ?',
            variables: [Variable.withInt(pi.variantId!)],
          ).getSingleOrNull();
          unitCost = r?.read<int>('cost_cents') ?? 0;
        } else {
          final r = await customSelect(
            'SELECT cost_cents FROM products WHERE id = ?',
            variables: [Variable.withInt(pi.productId)],
          ).getSingleOrNull();
          unitCost = r?.read<int>('cost_cents') ?? 0;
        }
        total += MeasuredAmount.cents(
          unitCents: unitCost,
          quantity: ri.quantity,
          quantityScale: ri.quantityScale,
        );
      }
    }
    return total;
  }

  /// Exact FIFO value removed by one linked purchase-return line.
  Future<int> _purchaseReturnBatchValueCents(
    int purchaseReturnItemId,
    int quantityScale,
  ) async {
    final row = await customSelect(
      'SELECT CAST((COALESCE(SUM(quantity * unit_cost_cents), 0) + ?) / ? '
      'AS INTEGER) AS value_cents '
      'FROM batch_consumptions '
      "WHERE purchase_return_item_id = ? AND direction = 'out' "
      "AND consumption_type = 'purchase_return'",
      variables: [
        Variable.withInt(quantityScale ~/ 2),
        Variable.withInt(quantityScale),
        Variable.withInt(purchaseReturnItemId),
      ],
    ).getSingle();
    return row.read<int>('value_cents');
  }

  /// Watch set of purchase IDs that have at least one non-voided return
  Stream<Set<int>> watchPurchaseIdsWithReturns() {
    return (select(purchaseReturns)..where((r) => r.status.equals('posted')))
        .watch()
        .map((list) => list.map((r) => r.purchaseId).toSet());
  }
}
