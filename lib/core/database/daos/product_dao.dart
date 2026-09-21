import '../../services/business/warehouse_catalog_scope.dart';
import '../../services/business/warehouse_batch_scope.dart';
import '../../services/business/warehouse_stock_scope.dart';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/products.dart';
import '../tables/transactions.dart';

part 'product_dao.g.dart';

/// A shared product cannot be hidden while any location still holds stock.
class ProductStockNotZeroException implements Exception {
  final int productId;
  const ProductStockNotZeroException(this.productId);

  @override
  String toString() => 'ProductStockNotZeroException(productId: $productId)';
}

@DriftAccessor(
  tables: [
    Products,
    ProductVariants,
    ProductCategories,
    ProductColors,
    Sizes,
    ProductBatches,
    BatchConsumptions,
    ProductPriceHistories,
    Purchases,
    PurchaseItems,
  ],
)
class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
  ProductDao(super.db);

  Stream<List<Product>> watchAllProducts({bool? isActive = true}) {
    final query = select(products);
    if (isActive != null) {
      query.where((p) => p.isActive.equals(isActive));
    }
    query.orderBy([(p) => OrderingTerm(expression: p.name)]);
    return query.watch();
  }

  Stream<Product?> watchProduct(int id) {
    return (select(
      products,
    )..where((p) => p.id.equals(id))).watchSingleOrNull();
  }

  /// Synchronous single-row fetch by primary key. Used by guards that need
  /// to preserve server-authoritative fields (e.g. `stock_quantity`,
  /// `cost_cents`, `created_at`) during product updates.
  Future<Product?> getProductById(int id) {
    return (select(products)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  Future<List<Product>> searchProducts(String query, {bool? isActive = true}) {
    final q = select(products)
      ..where(
        (p) =>
            p.name.like('%$query%') |
            p.sku.like('%$query%') |
            p.sku.equals(query),
      );
    if (isActive != null) {
      q.where((p) => p.isActive.equals(isActive));
    }
    return q.get();
  }

  Future<Product?> findBySkuOrBarcode(String code) {
    return (select(products)
          ..where((p) => p.sku.equals(code) | p.barcode.equals(code))
          ..where((p) => p.isActive.equals(true)))
        .getSingleOrNull();
  }

  // Legacy products without an operational row retain their stored balance.
  // Otherwise the warehouse ledger is the source for stock-status decisions.
  static const _primaryProductQuantity =
      '''CASE WHEN EXISTS (
    SELECT 1 FROM product_variants v WHERE v.product_id = p.id AND v.is_active = 1
  ) THEN (
    SELECT SUM(ws.quantity) FROM product_variants v
    JOIN ${WarehouseStockScope.primaryStocks} ws ON ws.variant_id = v.id
    WHERE v.product_id = p.id AND v.is_active = 1
  ) ELSE p.stock_quantity END''';

  Product _mapStockFilteredProduct(QueryRow row) => products.map({
    ...row.data,
    'stock_quantity': row.read<int>('warehouse_stock_quantity'),
  });

  Future<List<Product>> filterProducts({
    int? categoryId,
    String? stockStatus,
    int limit = 50,
    int offset = 0,
    bool? isActive = true,
    int lowStockThreshold = 5,
  }) {
    if (stockStatus == null) {
      final query = select(products);

      if (isActive != null) {
        query.where((p) => p.isActive.equals(isActive));
      }

      if (categoryId != null) {
        query.where((p) => p.categoryId.equals(categoryId));
      }

      query
        ..orderBy([(p) => OrderingTerm(expression: p.name)])
        ..limit(limit, offset: offset);

      return query.get();
    }

    final where = StringBuffer('WHERE 1=1');
    final vars = <Variable<Object>>[];

    if (isActive != null) {
      where.write(' AND p.is_active = ?');
      vars.add(Variable.withInt(isActive ? 1 : 0));
    }
    if (categoryId != null) {
      where.write(' AND p.category_id = ?');
      vars.add(Variable.withInt(categoryId));
    }

    if (stockStatus == 'out_of_stock') {
      where.write(
        ' AND ((p.has_variants = 0 AND ($_primaryProductQuantity) = 0) OR (p.has_variants = 1 AND NOT EXISTS (SELECT 1 FROM product_variants v JOIN ${WarehouseStockScope.primaryStocks} ws ON ws.variant_id = v.id WHERE v.product_id = p.id AND v.is_active = 1 AND ws.quantity > 0)))',
      );
    } else if (stockStatus == 'low_stock') {
      where.write(
        ' AND ((p.has_variants = 0 AND ($_primaryProductQuantity) > 0 AND ($_primaryProductQuantity) <= CASE WHEN p.min_quantity > 0 THEN p.min_quantity ELSE ? END) OR (p.has_variants = 1 AND EXISTS (SELECT 1 FROM product_variants v JOIN ${WarehouseStockScope.primaryStocks} ws ON ws.variant_id = v.id WHERE v.product_id = p.id AND v.is_active = 1 AND ws.quantity > 0 AND ws.quantity <= CASE WHEN p.min_quantity > 0 THEN p.min_quantity ELSE ? END)))',
      );
      vars.add(Variable.withInt(lowStockThreshold));
      vars.add(Variable.withInt(lowStockThreshold));
    }

    where.write(' ORDER BY p.name LIMIT ? OFFSET ?');
    vars.add(Variable.withInt(limit));
    vars.add(Variable.withInt(offset));

    return customSelect(
      'SELECT p.*, ($_primaryProductQuantity) AS warehouse_stock_quantity FROM products p ${where.toString()}',
      variables: vars,
      readsFrom: {
        products,
        productVariants,
        ...WarehouseStockScope.dependencies(db),
      },
    ).map(_mapStockFilteredProduct).get();
  }

  Stream<List<Product>> watchFilteredProducts({
    int? categoryId,
    String? stockStatus,
    bool? isActive = true,
    int lowStockThreshold = 5,
  }) {
    if (stockStatus == null) {
      final query = select(products);

      if (isActive != null) {
        query.where((p) => p.isActive.equals(isActive));
      }

      if (categoryId != null) {
        query.where((p) => p.categoryId.equals(categoryId));
      }

      query.orderBy([(p) => OrderingTerm(expression: p.name)]);

      return query.watch();
    }

    final where = StringBuffer('WHERE 1=1');
    final vars = <Variable<Object>>[];

    if (isActive != null) {
      where.write(' AND p.is_active = ?');
      vars.add(Variable.withInt(isActive ? 1 : 0));
    }
    if (categoryId != null) {
      where.write(' AND p.category_id = ?');
      vars.add(Variable.withInt(categoryId));
    }

    if (stockStatus == 'out_of_stock') {
      where.write(
        ' AND ((p.has_variants = 0 AND ($_primaryProductQuantity) = 0) OR (p.has_variants = 1 AND NOT EXISTS (SELECT 1 FROM product_variants v JOIN ${WarehouseStockScope.primaryStocks} ws ON ws.variant_id = v.id WHERE v.product_id = p.id AND v.is_active = 1 AND ws.quantity > 0)))',
      );
    } else if (stockStatus == 'low_stock') {
      where.write(
        ' AND ((p.has_variants = 0 AND ($_primaryProductQuantity) > 0 AND ($_primaryProductQuantity) <= CASE WHEN p.min_quantity > 0 THEN p.min_quantity ELSE ? END) OR (p.has_variants = 1 AND EXISTS (SELECT 1 FROM product_variants v JOIN ${WarehouseStockScope.primaryStocks} ws ON ws.variant_id = v.id WHERE v.product_id = p.id AND v.is_active = 1 AND ws.quantity > 0 AND ws.quantity <= CASE WHEN p.min_quantity > 0 THEN p.min_quantity ELSE ? END)))',
      );
      vars.add(Variable.withInt(lowStockThreshold));
      vars.add(Variable.withInt(lowStockThreshold));
    }

    where.write(' ORDER BY p.name');

    return customSelect(
      'SELECT p.*, ($_primaryProductQuantity) AS warehouse_stock_quantity FROM products p ${where.toString()}',
      variables: vars,
      readsFrom: {
        products,
        productVariants,
        ...WarehouseStockScope.dependencies(db),
      },
    ).map(_mapStockFilteredProduct).watch();
  }

  Selectable<Product> _exportProducts({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
    int? limit,
    int offset = 0,
  }) {
    final filters = <String>[];
    final variables = <Variable>[];
    if (activeOnly) filters.add('is_active = 1');
    if (categoryId != null) {
      filters.add('category_id = ?');
      variables.add(Variable.withInt(categoryId));
    }
    if (supplierId != null) {
      filters.add('supplier_id = ?');
      variables.add(Variable.withInt(supplierId));
    }
    var sql = 'SELECT * FROM ${WarehouseCatalogScope.products}';
    if (filters.isNotEmpty) sql += ' WHERE ${filters.join(' AND ')}';
    sql += ' ORDER BY name';
    if (limit != null) {
      sql += ' LIMIT ? OFFSET ?';
      variables.addAll([Variable.withInt(limit), Variable.withInt(offset)]);
    }
    return customSelect(
      sql,
      variables: variables,
      readsFrom: WarehouseCatalogScope.dependencies(db),
    ).map((row) => WarehouseCatalogScope.mapProduct(db, row));
  }

  Stream<List<Product>> watchProductsForExport({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
  }) => _exportProducts(
    categoryId: categoryId,
    supplierId: supplierId,
    activeOnly: activeOnly,
  ).watch();

  Future<List<Product>> fetchProductsForExport({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
    int limit = 1000,
    int offset = 0,
  }) => _exportProducts(
    categoryId: categoryId,
    supplierId: supplierId,
    activeOnly: activeOnly,
    limit: limit,
    offset: offset,
  ).get();

  Future<Product?> findBySku(String sku) {
    return (select(
      products,
    )..where((p) => p.sku.equals(sku))).getSingleOrNull();
  }

  Future<Product?> findByBarcode(String barcode) {
    return (select(
      products,
    )..where((p) => p.barcode.equals(barcode))).getSingleOrNull();
  }

  /// Case-insensitive name lookup. Treating "iPhone" and "iphone" as the
  /// same name prevents accidental duplicate SKUs when the bulk import or
  /// manual entry typo-shifts capitalisation. Equivalent to the standard
  /// `LOWER(name) = LOWER(?)` pattern in QuickBooks/Xero/Odoo.
  Future<Product?> findByName(String name) {
    final lowered = name.toLowerCase();
    return (select(
      products,
    )..where((p) => p.name.lower().equals(lowered))).getSingleOrNull();
  }

  Future<int> createProduct(ProductsCompanion product) {
    return into(products).insert(product);
  }

  Future<void> _requireZeroStock(Iterable<int> ids) async {
    for (final id in ids.toSet()) {
      final row = await customSelect(
        'SELECT EXISTS(SELECT 1 FROM products p WHERE p.id = ? '
        'AND (p.stock_quantity != 0 OR EXISTS(SELECT 1 FROM product_variants v '
        'WHERE v.product_id = p.id AND (v.stock_quantity != 0 OR EXISTS('
        'SELECT 1 FROM business_warehouse_stocks ws WHERE ws.variant_id = v.id '
        'AND ws.quantity != 0))))) AS has_stock',
        variables: [Variable.withInt(id)],
      ).getSingle();
      if (row.read<int>('has_stock') == 1) {
        throw ProductStockNotZeroException(id);
      }
    }
  }

  Future<bool> updateProduct(Product product) {
    return transaction(() async {
      final persisted = await (select(
        products,
      )..where((p) => p.id.equals(product.id))).getSingleOrNull();
      if (persisted == null) return false;
      if (!product.isActive) await _requireZeroStock([product.id]);
      // Stock/cost and inventory policy have dedicated accounting/lock-checked
      // writers. Generic catalog changes cannot replace them with stale values.
      final changes = product
          .toCompanion(false)
          .copyWith(
            id: const Value.absent(),
            stockQuantity: const Value.absent(),
            costCents: const Value.absent(),
            previousCostCents: const Value.absent(),
            previousPriceCents: const Value.absent(),
            previousWholesalePriceCents: const Value.absent(),
            lastPurchasePriceCents: const Value.absent(),
            createdAt: const Value.absent(),
            trackInventory: const Value.absent(),
            measurementType: const Value.absent(),
            costingMethod: const Value.absent(),
            inventoryTrackingType: const Value.absent(),
          );
      final ok =
          await (update(
            products,
          )..where((p) => p.id.equals(product.id))).write(changes) ==
          1;
      if (persisted.isActive != product.isActive) {
        await customUpdate(
          'UPDATE product_variants SET is_active = ? WHERE product_id = ?',
          variables: [
            Variable.withInt(product.isActive ? 1 : 0),
            Variable.withInt(product.id),
          ],
          updates: {productVariants},
        );
      }
      return ok;
    });
  }

  Future<int> deleteProduct(int id) {
    return transaction(() async {
      await _requireZeroStock([id]);
      return (delete(products)..where((p) => p.id.equals(id))).go();
    });
  }

  /// Runs [action] inside a Drift transaction scoped to this DAO's database.
  /// Nested `transaction(...)` calls made by other DAOs on the same database
  /// are automatically reused (single physical transaction), which lets the
  /// bloc orchestrate `updateProduct + ensureDefaultVariant + updateVariant`
  /// as a single atomic save — critical for accounting/stock integrity.
  Future<T> runInTransaction<T>(Future<T> Function() action) {
    return transaction(action);
  }

  /// Count historical references to [productId] across all transactional
  /// tables (sale items, purchase items, adjustment return items). Used by
  /// the smart-delete flow: any product with a non-zero reference count must
  /// be deactivated (soft-delete) rather than hard-deleted so audit trail,
  /// COGS, and journal entries stay intact — the standard approach in
  /// QuickBooks / Xero / Odoo.
  Future<int> countProductReferences(int productId) async {
    final row = await customSelect(
      '''
      SELECT
        (SELECT COUNT(*) FROM sale_items WHERE product_id = ?1)
        + (SELECT COUNT(*) FROM purchase_items WHERE product_id = ?1)
        + (SELECT COUNT(*) FROM purchase_return_adjustment_items WHERE product_id = ?1)
        + (SELECT COUNT(*) FROM sale_return_adjustment_items WHERE product_id = ?1)
        + (SELECT COUNT(*) FROM inventory_adjustments WHERE product_id = ?1)
        + (SELECT COUNT(*) FROM product_batches WHERE product_id = ?1)
        AS ref_count
      ''',
      variables: [Variable.withInt(productId)],
    ).getSingle();
    return row.read<int>('ref_count');
  }

  /// Smart delete that mirrors QuickBooks/Xero behaviour: products with
  /// historical references are deactivated (is_active = false, variants
  /// deactivated transitively) to preserve audit trail and journal integrity;
  /// products with no references are hard-deleted.
  ///
  /// Returns `(wasDeleted, referenceCount)`.
  ///   - `wasDeleted = true`  -> row removed from products
  ///   - `wasDeleted = false` -> row deactivated (had `referenceCount` refs)
  Future<({bool wasDeleted, int referenceCount})> smartDeleteProduct(
    int productId,
  ) {
    return transaction(() async {
      await _requireZeroStock([productId]);
      final refCount = await countProductReferences(productId);
      if (refCount > 0) {
        await (update(products)..where((p) => p.id.equals(productId))).write(
          ProductsCompanion(
            isActive: const Value(false),
            updatedAt: Value(DateTime.now()),
          ),
        );
        await customUpdate(
          'UPDATE product_variants SET is_active = 0, updated_at = ? WHERE product_id = ?',
          variables: [
            Variable.withDateTime(DateTime.now()),
            Variable.withInt(productId),
          ],
          updates: {productVariants},
        );
        return (wasDeleted: false, referenceCount: refCount);
      }
      await (delete(products)..where((p) => p.id.equals(productId))).go();
      return (wasDeleted: true, referenceCount: 0);
    });
  }

  Future<int> bulkDeleteProducts(List<int> ids) {
    if (ids.isEmpty) return Future.value(0);
    return transaction(() async {
      await _requireZeroStock(ids);
      return (delete(products)..where((p) => p.id.isIn(ids))).go();
    });
  }

  // ──────────────────────────────────────────────────────────────────────
  // COSTING METHOD (WAC ↔ FIFO)
  // ──────────────────────────────────────────────────────────────────────

  /// Reasons that prevent flipping the costing method on an existing product.
  /// Mirrors Odoo / SAP B1 behaviour: once stock or COGS history exists, the
  /// method is frozen — switching mid-flight would mix WAC- and FIFO-priced
  /// COGS in the same period, breaking IAS 8 consistency.
  ///
  ///   - `null`              → unlocked, may be edited freely.
  ///   - `'has_stock'`       → non-zero on-hand stock on the product or any variant.
  ///   - `'has_consumptions'`→ at least one batch_consumptions row exists.
  ///   - `'has_transactions'`→ an inventory document already references the product.
  Future<String?> getCostingMethodLockReason(int productId) async {
    final stockRow = await customSelect(
      '''
      SELECT
        (SELECT COALESCE(stock_quantity, 0) FROM products WHERE id = ?1) AS p_stock,
        EXISTS(SELECT 1 FROM product_variants
          WHERE product_id = ?1 AND (stock_quantity != 0 OR EXISTS (
            SELECT 1 FROM business_warehouse_stocks ws
            WHERE ws.variant_id = product_variants.id AND ws.quantity != 0))) AS has_v_stock
      ''',
      variables: [Variable.withInt(productId)],
    ).getSingle();
    final pStock = stockRow.read<int>('p_stock');
    final hasVariantStock = stockRow.read<int>('has_v_stock') == 1;
    if (pStock != 0 || hasVariantStock) return 'has_stock';

    final consumptionRow = await customSelect(
      '''
      SELECT EXISTS(
        SELECT 1 FROM batch_consumptions bc
        INNER JOIN product_batches pb ON pb.id = bc.batch_id
        WHERE pb.product_id = ?1
        LIMIT 1
      ) AS has_any
      ''',
      variables: [Variable.withInt(productId)],
    ).getSingle();
    if (consumptionRow.read<int>('has_any') == 1) {
      return 'has_consumptions';
    }
    if (await countProductReferences(productId) > 0) {
      return 'has_transactions';
    }
    return null;
  }

  /// Changes the stock dimension only while the product is pristine. A
  /// measured quantity is stored at scale 1000, so changing this field after
  /// activity would reinterpret every historical quantity and valuation.
  Future<String?> setMeasurementType({
    required int productId,
    required String measurementType,
  }) {
    if (!const {
      'piece',
      'length',
      'weight',
      'volume',
    }.contains(measurementType)) {
      throw ArgumentError.value(
        measurementType,
        'measurementType',
        'Unsupported inventory policy',
      );
    }
    return transaction(() async {
      final reason = await getCostingMethodLockReason(productId);
      if (reason != null) return reason;
      await (update(products)..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          measurementType: Value(measurementType),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return null;
    });
  }

  /// Enables/disables stock tracking only before stock activity exists.
  Future<String?> setTrackInventory({
    required int productId,
    required bool trackInventory,
  }) {
    return transaction(() async {
      final reason = await getCostingMethodLockReason(productId);
      if (reason != null) return reason;
      await (update(products)..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          trackInventory: Value(trackInventory),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return null;
    });
  }

  /// Update [Products.costingMethod]. Refuses the change when the product is
  /// locked (see [getCostingMethodLockReason]) — caller must surface the
  /// returned reason to the user.
  ///
  /// Returns `null` on success or a non-null lock-reason string on refusal.
  Future<String?> setCostingMethod({
    required int productId,
    required String method,
  }) async {
    if (!const {'wac', 'fifo'}.contains(method)) {
      throw ArgumentError.value(
        method,
        'method',
        'Unsupported inventory policy',
      );
    }
    return transaction(() async {
      final reason = await getCostingMethodLockReason(productId);
      if (reason != null) return reason;
      await (update(products)..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          costingMethod: Value(method),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return null;
    });
  }

  // ──────────────────────────────────────────────────────────────────────
  // INVENTORY TRACKING TYPE (Phase B — two-layer architecture)
  // ──────────────────────────────────────────────────────────────────────

  /// Returns the per-product inventory tracking type.
  /// One of: `'standard'` | `'batch'` | `'batch_expiry'`.
  ///
  /// Defaults to `'standard'` if the product is not found (fail-safe — the
  /// cheapest path that produces no batch rows).
  Future<String> getInventoryTrackingType(int productId) async {
    final row = await customSelect(
      'SELECT inventory_tracking_type FROM products WHERE id = ?',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();
    final raw = row?.read<String?>('inventory_tracking_type');
    if (raw == 'batch' || raw == 'batch_expiry' || raw == 'standard') {
      return raw!;
    }
    return 'standard';
  }

  /// Update [Products.inventoryTrackingType]. Refuses the change when the
  /// product is locked (re-uses the same lock semantics as [setCostingMethod]
  /// because the implications are identical: existing batches/consumptions
  /// would otherwise be left in an inconsistent state).
  ///
  /// Returns `null` on success or a non-null lock-reason string on refusal.
  Future<String?> setInventoryTrackingType({
    required int productId,
    required String trackingType,
  }) async {
    if (!const {'standard', 'batch', 'batch_expiry'}.contains(trackingType)) {
      throw ArgumentError.value(
        trackingType,
        'trackingType',
        'Unsupported inventory policy',
      );
    }
    return transaction(() async {
      final reason = await getCostingMethodLockReason(productId);
      if (reason != null) return reason;
      await (update(products)..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(
          inventoryTrackingType: Value(trackingType),
          // Keep legacy column in sync during the expand → migrate → contract
          // window so older code paths that still read `costing_method` see a
          // consistent view. `'batch'` and `'batch_expiry'` both imply FIFO
          // costing semantics; `'standard'` implies WAC.
          costingMethod: Value(trackingType == 'standard' ? 'wac' : 'fifo'),
          updatedAt: Value(DateTime.now()),
        ),
      );
      return null;
    });
  }

  // ──────────────────────────────────────────────────────────────────────
  // EXPIRY (FIFO-aware)
  // ──────────────────────────────────────────────────────────────────────

  /// Returns expiry rows for [productId] **based on remaining batch
  /// quantities** — not the original purchase quantities. This is the
  /// number the user actually has on the shelf today: if a 100-unit batch
  /// expiring 2026-12-01 has been sold down to 12, the row reports 12.
  ///
  /// Excludes batches that are exhausted (`remaining_quantity = 0`) or have
  /// no expiry date (non-perishable). Sorted earliest-expiry first so the
  /// UI surfaces the most urgent rows at the top.
  Future<List<({int quantity, DateTime expiryDate})>>
  getProductRemainingExpiryInfo(int productId) async {
    final query = select(productBatches)
      ..where(
        (b) =>
            b.productId.equals(productId) &
            b.expiryDate.isNotNull() &
            b.remainingQuantity.isBiggerThanValue(0) &
            b.isActive.equals(true),
      )
      ..orderBy([(b) => OrderingTerm.asc(b.expiryDate)]);

    final rows = await query.get();
    return rows
        .map((r) => (quantity: r.remainingQuantity, expiryDate: r.expiryDate!))
        .toList();
  }

  /// Streams a per-product expiry summary used by the product list to render
  /// near-expiry / expired badges. Only emits an entry for products whose
  /// `inventory_tracking_type = 'batch_expiry'` and which currently have at
  /// least one active batch with on-hand stock and a non-null `expiry_date`.
  ///
  /// Each row carries:
  ///   * `expired_qty`     — SUM(remaining_quantity) for batches whose
  ///                         `expiry_date < today` (already expired but still
  ///                         on the shelf — accounting still owes COGS).
  ///   * `next_expiry_iso` — earliest `expiry_date >= today` across batches
  ///                         with stock; null when every remaining batch is
  ///                         already expired.
  ///
  /// Re-evaluates on writes to `products` or `product_batches` so the UI
  /// updates without manual refresh — same pattern as the variant summaries
  /// stream that drives the same screen.
  ///
  /// SQLite NOTE: `dateTime` columns are stored as ISO 8601 text under the
  /// project's `storeDateTimeValuesAsText` setting, so lexicographic string
  /// comparison matches chronological ordering. We pass `today` as an ISO
  /// 8601 string for the same reason.
  Stream<Map<int, ({int expiredQty, DateTime? nextExpiry})>>
  watchExpirySummaries() {
    return _expirySummariesQuery().watch().map((rows) {
      final out = <int, ({int expiredQty, DateTime? nextExpiry})>{};
      for (final row in rows) {
        final productId = row.read<int>('product_id');
        final expiredQty = row.read<int>('expired_qty');
        final nextExpiryIso = row.read<String?>('next_expiry_iso');
        DateTime? nextExpiry;
        if (nextExpiryIso != null && nextExpiryIso.isNotEmpty) {
          nextExpiry = DateTime.tryParse(nextExpiryIso);
        }
        out[productId] = (expiredQty: expiredQty, nextExpiry: nextExpiry);
      }
      return out;
    });
  }

  /// Builds the underlying [Selectable] for [watchExpirySummaries]. Extracted
  /// so the same query can be re-used by Phase E (alert dashboard / report)
  /// without copying the SQL.
  Selectable<QueryRow> _expirySummariesQuery() {
    // Beginning of today, local time, formatted as ISO 8601. Using start-of-
    // day means a batch that expires *today* is treated as "already expired"
    // (matches Odoo / SAP B1 semantics — once the calendar day arrives, the
    // batch is no longer sellable for FEFO).
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final todayIso = startOfToday.toIso8601String();
    return customSelect(
      '''
      SELECT
        p.id AS product_id,
        COALESCE(SUM(
          CASE WHEN b.expiry_date < ?1 THEN b.remaining_quantity ELSE 0 END
        ), 0) AS expired_qty,
        MIN(
          CASE WHEN b.expiry_date >= ?1 THEN b.expiry_date ELSE NULL END
        ) AS next_expiry_iso
      FROM products p
      INNER JOIN ${WarehouseBatchScope.primaryBatches} b ON b.product_id = p.id
      WHERE p.inventory_tracking_type = 'batch_expiry'
        AND b.is_active = 1
        AND b.remaining_quantity > 0
        AND b.expiry_date IS NOT NULL
      GROUP BY p.id
      HAVING expired_qty > 0 OR next_expiry_iso IS NOT NULL
      ''',
      variables: [Variable.withString(todayIso)],
      readsFrom: {
        products,
        productBatches,
        ...WarehouseBatchScope.dependencies(attachedDatabase),
      },
    );
  }

  Future<int> deactivateProduct(int id) {
    return transaction(() async {
      await _requireZeroStock([id]);
      return (update(products)..where((p) => p.id.equals(id))).write(
        const ProductsCompanion(isActive: Value(false)),
      );
    });
  }

  Future<int> bulkDeactivateProducts(List<int> ids) {
    if (ids.isEmpty) return Future.value(0);
    return transaction(() async {
      await _requireZeroStock(ids);
      return (update(products)..where((p) => p.id.isIn(ids))).write(
        const ProductsCompanion(isActive: Value(false)),
      );
    });
  }

  Future<List<int>> findProductIdsReferencedByOpenPurchases(
    List<int> productIds, {
    Set<String> closedPurchaseStatuses = const {
      'closed',
      'paid',
      'completed',
      'posted',
    },
  }) async {
    if (productIds.isEmpty) return const [];

    final purchases = db.purchases;
    final purchaseItems = db.purchaseItems;

    final query = selectOnly(purchaseItems, distinct: true)
      ..addColumns([purchaseItems.productId])
      ..join([
        innerJoin(purchases, purchases.id.equalsExp(purchaseItems.purchaseId)),
      ])
      ..where(purchaseItems.productId.isIn(productIds));
    query.where(purchases.status.isNotIn(closedPurchaseStatuses.toList()));

    final rows = await query.get();
    return rows
        .map((r) => r.read(purchaseItems.productId))
        .whereType<int>()
        .toList();
  }

  Stream<List<ProductVariant>> watchProductVariants(int productId) {
    return (select(productVariants)
          ..where((v) => v.productId.equals(productId))
          ..where((v) => v.isActive.equals(true)))
        .watch();
  }

  Future<int> createVariant(ProductVariantsCompanion variant) {
    return into(productVariants).insert(variant);
  }

  Stream<List<ProductCategory>> watchCategories() {
    return (select(productCategories)
          ..where((c) => c.isActive.equals(true))
          ..orderBy([(c) => OrderingTerm(expression: c.name)]))
        .watch();
  }

  /// Bulk create products in a single transaction for performance
  /// Returns a map of index to product ID
  Future<Map<int, int>> bulkCreateProducts(
    List<ProductsCompanion> productList,
  ) async {
    final results = <int, int>{};

    await db.transaction(() async {
      for (int i = 0; i < productList.length; i++) {
        final id = await into(products).insert(productList[i]);
        results[i] = id;
      }
    });

    return results;
  }

  /// Append a new immutable price-history row. Rows are never updated or
  /// deleted — every write is a fresh audit record.
  Future<int> insertPriceHistory(ProductPriceHistoriesCompanion entry) {
    return into(productPriceHistories).insert(entry);
  }

  /// Fetch the full price-history for a product, newest first. Includes
  /// entries scoped to individual variants as well as product-level edits.
  Future<List<ProductPriceHistory>> getPriceHistoryForProduct(int productId) {
    return (select(productPriceHistories)
          ..where((h) => h.productId.equals(productId))
          ..orderBy([(h) => OrderingTerm.desc(h.createdAt)]))
        .get();
  }
}
