import '../../services/business/warehouse_batch_scope.dart';
import 'package:drift/drift.dart';

import '../app_database.dart';
import '../../measurement/measurement.dart';

// ══════════════════════════════════════════════════════════════════════════════
// BATCH AUDIT DAO  (Phase H1 — read-only audit/transparency layer)
// ══════════════════════════════════════════════════════════════════════════════
//
// Read-only companion to BatchService. Exposes:
//   • Per-product/variant batch listings (FEFO-ordered) for the product detail
//     "Batches" tab.
//   • Per-batch consumption ledger drill-down (every IN/OUT row resolved to a
//     human-readable reference such as INV-XXXX, SR-XXXX, ADJ-XXXX, …).
//   • Per-sale "batch flow" (where COGS came from) for the sale detail screen.
//   • A direct `getConsumptionsForSaleItem(saleItemId)` debug helper that the
//     manual-verification workflow described in INVENTORY_ARCHITECTURE.md §11
//     relies on.
//
// Architectural rule — this DAO MUST NEVER MUTATE STATE.  Any write path goes
// through BatchService so invariant I1 (Σ remaining == stock_quantity) cannot
// drift. Read paths here are append-only consumers of `product_batches` and
// `batch_consumptions`.
// ══════════════════════════════════════════════════════════════════════════════

/// Snapshot of a single batch alongside the JOINed metadata the UI needs to
/// render a row without N+1 follow-up queries (supplier name, color/size).
///
/// `productName` / `productSku` are populated by [BatchAuditDao.watchAllBatches]
/// (Phase H3 — Batch Management screen) where a single row may belong to any
/// product. The per-product variant ([BatchAuditDao.watchBatchesForProduct])
/// leaves them null because the surrounding screen already shows the product
/// name in its header.
class BatchSummary {
  final int batchId;
  final String batchNumber;
  final String? manufacturerLotNumber;
  final int productId;
  final int variantId;
  final String? productName;
  final String? productSku;
  final String? variantLabel;
  final String source;
  final int? supplierId;
  final String? supplierName;
  final int? purchaseItemId;
  final DateTime receivedDate;
  final DateTime? expiryDate;
  final int receivedQuantity;
  final int remainingQuantity;
  final int unitCostCents;
  final int quantityScale;
  final String measurementType;
  final bool isActive;

  const BatchSummary({
    required this.batchId,
    required this.batchNumber,
    this.manufacturerLotNumber,
    required this.productId,
    required this.variantId,
    this.productName,
    this.productSku,
    required this.variantLabel,
    required this.source,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseItemId,
    required this.receivedDate,
    required this.expiryDate,
    required this.receivedQuantity,
    required this.remainingQuantity,
    required this.unitCostCents,
    this.quantityScale = 1,
    this.measurementType = 'piece',
    required this.isActive,
  });

  int get consumedQuantity => receivedQuantity - remainingQuantity;
  int get totalRemainingValueCents => MeasuredAmount.cents(
    unitCents: unitCostCents,
    quantity: remainingQuantity,
    quantityScale: quantityScale,
  );
  bool get isDepleted => remainingQuantity <= 0;
}

/// Expiry filter buckets for the standalone Batch Management screen. Cadence
/// matches `ExpiryBucket` (Phase E) so identical numbers render across the
/// dashboard widget, the expiry report and this screen. Kept in this DAO so
/// it can be referenced from a UI surface that is already importing
/// `batch_audit_dao.dart` without pulling in the inventory feature module.
enum BatchExpiryFilter {
  /// expiry_date IS NULL — non-perishable batch.
  none,

  /// expiry_date <= today.
  expired,

  /// 0 < days_until_expiry <= 30.
  in30Days,

  /// 30 < days_until_expiry <= 60.
  in60Days,

  /// 60 < days_until_expiry <= 90.
  in90Days,
}

/// One row of the append-only `batch_consumptions` ledger, joined with its
/// source reference so callers can show "Sale INV-202604-0123" instead of
/// "sale_item_id = 47".
class BatchConsumptionRecord {
  final int id;
  final int batchId;
  final String consumptionType;

  /// `'in'` (restoration) or `'out'` (depletion).
  final String direction;

  final int quantity;
  final int unitCostCents;
  final int quantityScale;
  final String measurementType;
  final DateTime createdAt;
  final String? notes;

  /// Logical kind of the source row: `'sale'`, `'sale_return'`,
  /// `'purchase_return'`, `'inventory_adjustment'`, `'purchase_adj_return'`,
  /// `'sale_adj_return'`, or `'unknown'`.
  final String refKind;

  /// Header id for navigation (e.g. sale_id, return_id, adjustment_id).
  final int? refHeaderId;

  /// Human label, e.g. invoice / return / adjustment number.
  final String? refLabel;

  /// Original sale_item_id (when applicable) for `getBatchFlowForSale`.
  final int? saleItemId;

  const BatchConsumptionRecord({
    required this.id,
    required this.batchId,
    required this.consumptionType,
    required this.direction,
    required this.quantity,
    required this.unitCostCents,
    this.quantityScale = 1,
    this.measurementType = 'piece',
    required this.createdAt,
    required this.notes,
    required this.refKind,
    required this.refHeaderId,
    required this.refLabel,
    required this.saleItemId,
  });

  int get totalValueCents => MeasuredAmount.cents(
    unitCents: unitCostCents,
    quantity: quantity,
    quantityScale: quantityScale,
  );
}

/// One slice of the FEFO consumption that fed a single sale line: which batch
/// it came from, how many units, at which frozen unit cost.
class BatchSaleConsumed {
  final int batchId;
  final String batchNumber;
  final String? manufacturerLotNumber;
  final int quantity;
  final int unitCostCents;
  final int quantityScale;
  final String measurementType;
  final DateTime? expiryDate;

  const BatchSaleConsumed({
    required this.batchId,
    required this.batchNumber,
    this.manufacturerLotNumber,
    required this.quantity,
    required this.unitCostCents,
    this.quantityScale = 1,
    this.measurementType = 'piece',
    required this.expiryDate,
  });

  int get totalCostCents => MeasuredAmount.cents(
    unitCents: unitCostCents,
    quantity: quantity,
    quantityScale: quantityScale,
  );
}

/// Per-line reconstruction of "where did this sale's COGS come from?". Keeps
/// the snapshot stamped on `sale_items.cost_cents` alongside the breakdown so
/// the auditor can verify Σ(batch.totalCostCents) == saleItem.cogsCents.
class SaleLineBatchFlow {
  final int saleItemId;
  final int productId;
  final int? variantId;
  final String productName;
  final String? variantLabel;
  final int totalQuantity;
  final int quantityScale;
  final String measurementType;
  final int? snapshotCostCents;
  final List<BatchSaleConsumed> batches;

  const SaleLineBatchFlow({
    required this.saleItemId,
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantLabel,
    required this.totalQuantity,
    this.quantityScale = 1,
    this.measurementType = 'piece',
    required this.snapshotCostCents,
    required this.batches,
  });

  /// COGS reconstructed from the batch ledger. For FIFO/FEFO products this
  /// equals `Σ(batches.totalCostCents)`. For WAC / standard-tracked products
  /// the list is empty and this returns 0; callers fall back to
  /// `snapshotCostCents` for display.
  int get reconstructedCogsCents =>
      batches.fold<int>(0, (s, b) => s + b.totalCostCents);

  bool get isBatchTracked => batches.isNotEmpty;
}

// ─── Reference label helper (shared across queries) ──────────────────────────
//
// We keep the JOIN columns in a single COALESCE so each consumption row
// resolves to exactly one (refKind, refHeaderId, refLabel) tuple. Order of
// preference matches the FK columns in `batch_consumptions`.
const String _kRefSelect = '''
  s.id              AS sale_id,            s.invoice_number   AS sale_label,
  sr.id             AS sale_return_id,     sr.return_number   AS sale_return_label,
  pr.id             AS purchase_return_id, pr.return_number   AS purchase_return_label,
  ia.id             AS adjustment_id,      ia.adjustment_number AS adjustment_label,
  pra.id            AS purchase_adj_id,    pra.return_number  AS purchase_adj_label,
  sra.id            AS sale_adj_id,        sra.return_number  AS sale_adj_label
''';

const String _kRefJoins = '''
  LEFT JOIN sale_items                       si   ON si.id   = bc.sale_item_id
  LEFT JOIN sales                            s    ON s.id    = si.sale_id
  LEFT JOIN sale_return_items                sri  ON sri.id  = bc.sale_return_item_id
  LEFT JOIN sale_returns                     sr   ON sr.id   = sri.return_id
  LEFT JOIN purchase_return_items            pri  ON pri.id  = bc.purchase_return_item_id
  LEFT JOIN purchase_returns                 pr   ON pr.id   = pri.return_id
  LEFT JOIN inventory_adjustments            ia   ON ia.id   = bc.inventory_adjustment_id
  LEFT JOIN purchase_return_adjustment_items prai ON prai.id = bc.purchase_return_adjustment_item_id
  LEFT JOIN purchase_return_adjustments      pra  ON pra.id  = prai.return_id
  LEFT JOIN sale_return_adjustment_items     srai ON srai.id = bc.sale_return_adjustment_item_id
  LEFT JOIN sale_return_adjustments          sra  ON sra.id  = srai.return_id
''';

/// Read-only DAO for batch transparency / audit UI.
///
/// We intentionally do NOT use `@DriftAccessor` here — Drift codegen would
/// only buy us typed query builders, but every query in this file is a hand-
/// rolled `customSelect` that JOINs across 8+ tables, so the codegen is pure
/// noise. Skipping `@DriftAccessor` also means this file does not require
/// `dart run build_runner build` to compile.
class BatchAuditDao {
  final AppDatabase _db;

  BatchAuditDao(this._db);

  // ──────────────────────────────────────────────────────────────────────────
  // BATCH LISTINGS
  // ──────────────────────────────────────────────────────────────────────────

  /// FEFO-ordered list of batches for a product (optionally narrowed to a
  /// single variant). `includeDepleted=false` keeps the UI focused on batches
  /// that still hold stock — the depleted history is one tap away in the
  /// drill-down.
  ///
  /// Ordering matches `BatchService.consumeFifo` exactly so what the user
  /// sees is what the next sale will consume from. Reactive: any IN/OUT
  /// movement re-emits.
  Stream<List<BatchSummary>> watchBatchesForProduct({
    required int productId,
    int? variantId,
    bool includeDepleted = false,
  }) {
    final whereParts = <String>['pb.product_id = ?'];
    final vars = <Variable>[Variable.withInt(productId)];
    if (variantId != null) {
      whereParts.add('pb.variant_id = ?');
      vars.add(Variable.withInt(variantId));
    }
    if (!includeDepleted) {
      whereParts.add('pb.is_active = 1');
      whereParts.add('pb.remaining_quantity > 0');
    }

    final sql =
        '''
      SELECT
        pb.id, pb.batch_number, pb.manufacturer_lot_number,
        pb.product_id, pb.variant_id, pb.source,
        pb.supplier_id, pb.purchase_item_id, pb.received_date, pb.expiry_date,
        pb.received_quantity, pb.remaining_quantity, pb.unit_cost_cents,
        pb.is_active, p.measurement_type,
        sup.name      AS supplier_name,
        pc.name       AS color_name,
        sz.name       AS size_name
      FROM ${WarehouseBatchScope.primaryBatches} pb
      INNER JOIN products          p   ON p.id  = pb.product_id
      LEFT JOIN suppliers        sup ON sup.id = pb.supplier_id
      LEFT JOIN product_variants pv  ON pv.id  = pb.variant_id
      LEFT JOIN product_colors   pc  ON pc.id  = pv.color_id
      LEFT JOIN sizes            sz  ON sz.id  = pv.size_id
      WHERE ${whereParts.join(' AND ')}
      ORDER BY (pb.expiry_date IS NULL) ASC,
               pb.expiry_date           ASC,
               pb.received_date         ASC,
               pb.id                    ASC
    ''';

    return _db
        .customSelect(
          sql,
          variables: vars,
          readsFrom: {
            _db.productBatches,
            ...WarehouseBatchScope.dependencies(_db),
            _db.batchConsumptions,
            _db.products,
            _db.suppliers,
            _db.productVariants,
            _db.productColors,
            _db.sizes,
          },
        )
        .watch()
        .map((rows) => rows.map(_mapBatchSummary).toList(growable: false));
  }

  /// One-shot variant of [watchBatchesForProduct] for non-reactive callers
  /// (debug consoles, exports).
  Future<List<BatchSummary>> getBatchesForProduct({
    required int productId,
    int? variantId,
    bool includeDepleted = false,
  }) async {
    return watchBatchesForProduct(
      productId: productId,
      variantId: variantId,
      includeDepleted: includeDepleted,
    ).first;
  }

  /// Cross-product batch listing for the standalone Batch Management screen
  /// (Phase H3). Same FEFO ordering as [watchBatchesForProduct] so the user
  /// sees the same "what gets consumed next" ordering the sale path uses.
  ///
  /// Filters:
  ///   * [query] — case-insensitive LIKE against `products.name`,
  ///     `COALESCE(variant.sku, product.sku)`, the internal batch number,
  ///     and the manufacturer's lot number.
  ///   * [source] — exact match against `product_batches.source`
  ///     (`'purchase'`, `'opening'`, `'found'`, `'sale_return'`).
  ///   * [supplierId] — narrow to a single supplier.
  ///   * [expiryFilter] — bucket from [BatchExpiryFilter]. Cadence matches
  ///     `ExpiryAlertService` (Phase E) — `expired` covers expiry_date
  ///     <= start-of-today, `in30` is `0 < diff <= 30`, etc.
  ///   * [includeDepleted] — when `false` (default) only `is_active=1` and
  ///     `remaining_quantity > 0` rows are returned.
  ///
  /// All filters compose with AND. Reactive — re-emits on any IN/OUT
  /// movement, new purchase, return, or adjustment.
  Stream<List<BatchSummary>> watchAllBatches({
    String? query,
    String? source,
    int? supplierId,
    BatchExpiryFilter? expiryFilter,
    bool includeDepleted = false,
  }) {
    final whereParts = <String>[];
    final vars = <Variable>[];

    if (!includeDepleted) {
      whereParts.add('pb.is_active = 1');
      whereParts.add('pb.remaining_quantity > 0');
    }

    if (source != null && source.isNotEmpty) {
      whereParts.add('pb.source = ?');
      vars.add(Variable.withString(source));
    }

    if (supplierId != null) {
      whereParts.add('pb.supplier_id = ?');
      vars.add(Variable.withInt(supplierId));
    }

    final trimmed = query?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      // SQLite LIKE is case-insensitive for ASCII; for Arabic/non-ASCII it
      // performs byte-equality — fine for our SKUs/batch numbers; product
      // names rely on the visible-prefix UX.
      final pattern = '%${_escapeLike(trimmed)}%';
      whereParts.add(
        '('
        'p.name LIKE ? ESCAPE \'\\\' OR '
        'COALESCE(pv.sku, p.sku) LIKE ? ESCAPE \'\\\' OR '
        'pb.batch_number LIKE ? ESCAPE \'\\\' OR '
        'pb.manufacturer_lot_number LIKE ? ESCAPE \'\\\''
        ')',
      );
      vars
        ..add(Variable.withString(pattern))
        ..add(Variable.withString(pattern))
        ..add(Variable.withString(pattern))
        ..add(Variable.withString(pattern));
    }

    if (expiryFilter != null) {
      // Anchor "today" inside the SQL via a parameter so the bucket stays
      // exact across midnight crossings without needing the screen to
      // re-issue the query.
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      switch (expiryFilter) {
        case BatchExpiryFilter.none:
          whereParts.add('pb.expiry_date IS NULL');
        case BatchExpiryFilter.expired:
          whereParts.add('pb.expiry_date IS NOT NULL');
          whereParts.add('pb.expiry_date <= ?');
          vars.add(Variable.withString(startOfToday.toIso8601String()));
        case BatchExpiryFilter.in30Days:
          whereParts.add('pb.expiry_date > ?');
          whereParts.add('pb.expiry_date <= ?');
          vars
            ..add(Variable.withString(startOfToday.toIso8601String()))
            ..add(
              Variable.withString(
                startOfToday.add(const Duration(days: 30)).toIso8601String(),
              ),
            );
        case BatchExpiryFilter.in60Days:
          whereParts.add('pb.expiry_date > ?');
          whereParts.add('pb.expiry_date <= ?');
          vars
            ..add(
              Variable.withString(
                startOfToday.add(const Duration(days: 30)).toIso8601String(),
              ),
            )
            ..add(
              Variable.withString(
                startOfToday.add(const Duration(days: 60)).toIso8601String(),
              ),
            );
        case BatchExpiryFilter.in90Days:
          whereParts.add('pb.expiry_date > ?');
          whereParts.add('pb.expiry_date <= ?');
          vars
            ..add(
              Variable.withString(
                startOfToday.add(const Duration(days: 60)).toIso8601String(),
              ),
            )
            ..add(
              Variable.withString(
                startOfToday.add(const Duration(days: 90)).toIso8601String(),
              ),
            );
      }
    }

    final whereClause = whereParts.isEmpty
        ? ''
        : 'WHERE ${whereParts.join(' AND ')}';

    final sql =
        '''
      SELECT
        pb.id, pb.batch_number, pb.manufacturer_lot_number,
        pb.product_id, pb.variant_id, pb.source,
        pb.supplier_id, pb.purchase_item_id, pb.received_date, pb.expiry_date,
        pb.received_quantity, pb.remaining_quantity, pb.unit_cost_cents,
        pb.is_active, p.measurement_type,
        p.name                       AS product_name,
        COALESCE(pv.sku, p.sku)      AS product_sku,
        sup.name                     AS supplier_name,
        pc.name                      AS color_name,
        sz.name                      AS size_name
      FROM ${WarehouseBatchScope.primaryBatches} pb
      INNER JOIN products        p   ON p.id   = pb.product_id
      LEFT  JOIN suppliers       sup ON sup.id = pb.supplier_id
      LEFT  JOIN product_variants pv ON pv.id  = pb.variant_id
      LEFT  JOIN product_colors  pc  ON pc.id  = pv.color_id
      LEFT  JOIN sizes           sz  ON sz.id  = pv.size_id
      $whereClause
      ORDER BY (pb.expiry_date IS NULL) ASC,
               pb.expiry_date           ASC,
               pb.received_date         ASC,
               pb.id                    ASC
    ''';

    return _db
        .customSelect(
          sql,
          variables: vars,
          readsFrom: {
            _db.productBatches,
            ...WarehouseBatchScope.dependencies(_db),
            _db.batchConsumptions,
            _db.products,
            _db.suppliers,
            _db.productVariants,
            _db.productColors,
            _db.sizes,
          },
        )
        .watch()
        .map((rows) => rows.map(_mapBatchSummary).toList(growable: false));
  }

  /// Escape `%`, `_` and the escape character itself so user-typed search
  /// strings can't accidentally match more than they look like they should.
  static String _escapeLike(String input) {
    return input
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CONSUMPTION DRILL-DOWN
  // ──────────────────────────────────────────────────────────────────────────

  /// Every movement (IN + OUT) ever posted against [batchId], in chronological
  /// order. Each row is enriched with the human-readable reference label of
  /// its source document.
  Future<List<BatchConsumptionRecord>> getConsumptionsForBatch(
    int batchId,
  ) async {
    final rows = await _db
        .customSelect(
          '''
        SELECT
          bc.id, bc.batch_id, bc.consumption_type, bc.direction, bc.quantity,
          bc.unit_cost_cents, bc.created_at, bc.notes,
          bc.sale_item_id, bc.sale_return_item_id, bc.purchase_return_item_id,
          bc.inventory_adjustment_id,
          bc.purchase_return_adjustment_item_id,
          bc.sale_return_adjustment_item_id,
          p0.measurement_type AS measurement_type,
          $_kRefSelect
        FROM batch_consumptions bc
        INNER JOIN ${WarehouseBatchScope.primaryBatches} pb0 ON pb0.id = bc.batch_id
        INNER JOIN products p0 ON p0.id = pb0.product_id
        $_kRefJoins
        WHERE bc.batch_id = ?
        ORDER BY bc.created_at ASC, bc.id ASC
      ''',
          variables: [Variable.withInt(batchId)],
          readsFrom: {
            _db.batchConsumptions,
            _db.productBatches,
            ...WarehouseBatchScope.dependencies(_db),
            _db.products,
            _db.saleItems,
            _db.sales,
            _db.saleReturnItems,
            _db.saleReturns,
            _db.purchaseReturnItems,
            _db.purchaseReturns,
            _db.inventoryAdjustments,
            _db.purchaseReturnAdjustmentItems,
            _db.purchaseReturnAdjustments,
            _db.saleReturnAdjustmentItems,
            _db.saleReturnAdjustments,
          },
        )
        .get();

    return rows.map(_mapConsumption).toList(growable: false);
  }

  /// Reactive variant for screens that watch a batch's history while the user
  /// is staring at it (e.g. when a parallel sale completes).
  Stream<List<BatchConsumptionRecord>> watchConsumptionsForBatch(int batchId) {
    return _db
        .customSelect(
          '''
            SELECT
              bc.id, bc.batch_id, bc.consumption_type, bc.direction, bc.quantity,
              bc.unit_cost_cents, bc.created_at, bc.notes,
              bc.sale_item_id, bc.sale_return_item_id, bc.purchase_return_item_id,
              bc.inventory_adjustment_id,
              bc.purchase_return_adjustment_item_id,
              bc.sale_return_adjustment_item_id,
              p0.measurement_type AS measurement_type,
              $_kRefSelect
            FROM batch_consumptions bc
            INNER JOIN ${WarehouseBatchScope.primaryBatches} pb0 ON pb0.id = bc.batch_id
            INNER JOIN products p0 ON p0.id = pb0.product_id
            $_kRefJoins
            WHERE bc.batch_id = ?
            ORDER BY bc.created_at ASC, bc.id ASC
          ''',
          variables: [Variable.withInt(batchId)],
          readsFrom: {
            _db.batchConsumptions,
            _db.productBatches,
            ...WarehouseBatchScope.dependencies(_db),
            _db.products,
            _db.saleItems,
            _db.sales,
            _db.saleReturnItems,
            _db.saleReturns,
            _db.purchaseReturnItems,
            _db.purchaseReturns,
            _db.inventoryAdjustments,
            _db.purchaseReturnAdjustmentItems,
            _db.purchaseReturnAdjustments,
            _db.saleReturnAdjustmentItems,
            _db.saleReturnAdjustments,
          },
        )
        .watch()
        .map((rows) => rows.map(_mapConsumption).toList(growable: false));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // SALE FLOW (audit "where did COGS come from?")
  // ──────────────────────────────────────────────────────────────────────────

  /// Reconstruct, per sale line, the FEFO batches that fed COGS. WAC /
  /// standard-tracked lines emit no consumption rows — those come back with
  /// an empty `batches` list and the caller should fall back to the
  /// `snapshotCostCents` (which is `sale_items.cost_cents`).
  ///
  /// `'in'` reversal rows are NETTED: if a sale was partially returned, a
  /// later `restoreConsumptions` will have inserted matching `'in'` rows.
  /// We sum `(direction='out' qty) − (direction='in' qty)` per (saleItemId,
  /// batchId) so the report shows the *net* COGS still recognised on the
  /// sale, not the gross.
  Future<List<SaleLineBatchFlow>> getBatchFlowForSale(int saleId) async {
    // 1. Sale lines (drives the result regardless of batch tracking).
    final lineRows = await _db
        .customSelect(
          '''
        SELECT
          si.id           AS sale_item_id,
          si.product_id   AS product_id,
          si.variant_id   AS variant_id,
          si.quantity     AS quantity,
          si.quantity_scale AS quantity_scale,
          si.measurement_type AS measurement_type,
          si.cost_cents   AS cost_cents,
          p.name          AS product_name,
          pc.name         AS color_name,
          sz.name         AS size_name
        FROM sale_items si
        INNER JOIN products         p  ON p.id  = si.product_id
        LEFT  JOIN product_variants pv ON pv.id = si.variant_id
        LEFT  JOIN product_colors   pc ON pc.id = pv.color_id
        LEFT  JOIN sizes            sz ON sz.id = pv.size_id
        WHERE si.sale_id = ?
        ORDER BY si.id ASC
      ''',
          variables: [Variable.withInt(saleId)],
          readsFrom: {
            _db.saleItems,
            _db.products,
            _db.productVariants,
            _db.productColors,
            _db.sizes,
          },
        )
        .get();

    if (lineRows.isEmpty) return const [];

    // 2. Batch consumptions for ALL sale items in one round-trip.
    final saleItemIds = lineRows
        .map((r) => r.read<int>('sale_item_id'))
        .toList();
    final placeholders = List.filled(saleItemIds.length, '?').join(',');
    final consumptionRows = await _db
        .customSelect(
          '''
        SELECT
          bc.sale_item_id      AS sale_item_id,
          bc.batch_id          AS batch_id,
          bc.direction         AS direction,
          bc.quantity          AS quantity,
          bc.unit_cost_cents   AS unit_cost_cents,
          pb.batch_number      AS batch_number,
          pb.manufacturer_lot_number AS manufacturer_lot_number,
          pb.expiry_date       AS expiry_date
        FROM batch_consumptions bc
        INNER JOIN ${WarehouseBatchScope.primaryBatches} pb ON pb.id = bc.batch_id
        WHERE bc.sale_item_id IN ($placeholders)
        ORDER BY bc.id ASC
      ''',
          variables: saleItemIds.map((id) => Variable.withInt(id)).toList(),
          readsFrom: {
            _db.batchConsumptions,
            _db.productBatches,
            ...WarehouseBatchScope.dependencies(_db),
          },
        )
        .get();

    // 3. Net (out − in) per (saleItemId, batchId) preserving first-seen order.
    final perLine = <int, _LineAcc>{};
    for (final r in consumptionRows) {
      final saleItemId = r.read<int>('sale_item_id');
      final batchId = r.read<int>('batch_id');
      final acc = perLine.putIfAbsent(saleItemId, _LineAcc.new);
      final entry = acc.batches.putIfAbsent(
        batchId,
        () => _BatchAcc(
          batchId: batchId,
          batchNumber: r.read<String>('batch_number'),
          manufacturerLotNumber: r.readNullable<String>(
            'manufacturer_lot_number',
          ),
          unitCostCents: r.read<int>('unit_cost_cents'),
          expiryDate: r.readNullable<DateTime>('expiry_date'),
        ),
      );
      final qty = r.read<int>('quantity');
      if (r.read<String>('direction') == 'out') {
        entry.netQty += qty;
      } else {
        entry.netQty -= qty;
      }
    }

    // 4. Stitch the two streams.
    return lineRows
        .map((row) {
          final saleItemId = row.read<int>('sale_item_id');
          final acc = perLine[saleItemId];
          final batches = (acc?.batches.values ?? const <_BatchAcc>[])
              .where((b) => b.netQty > 0)
              .map(
                (b) => BatchSaleConsumed(
                  batchId: b.batchId,
                  batchNumber: b.batchNumber,
                  manufacturerLotNumber: b.manufacturerLotNumber,
                  quantity: b.netQty,
                  unitCostCents: b.unitCostCents,
                  quantityScale: row.read<int>('quantity_scale'),
                  measurementType: row.read<String>('measurement_type'),
                  expiryDate: b.expiryDate,
                ),
              )
              .toList(growable: false);

          return SaleLineBatchFlow(
            saleItemId: saleItemId,
            productId: row.read<int>('product_id'),
            variantId: row.readNullable<int>('variant_id'),
            productName: row.read<String>('product_name'),
            variantLabel: _composeVariantLabel(
              row.readNullable<String>('color_name'),
              row.readNullable<String>('size_name'),
            ),
            totalQuantity: row.read<int>('quantity'),
            quantityScale: row.read<int>('quantity_scale'),
            measurementType: row.read<String>('measurement_type'),
            snapshotCostCents: row.readNullable<int>('cost_cents'),
            batches: batches,
          );
        })
        .toList(growable: false);
  }

  /// Direct debug helper — every batch_consumptions row attached to a single
  /// sale line, ordered chronologically. Mirrors what `restoreConsumptions`
  /// reads when a return / void fires.
  Future<List<BatchConsumptionRecord>> getConsumptionsForSaleItem(
    int saleItemId,
  ) async {
    final rows = await _db
        .customSelect(
          '''
        SELECT
          bc.id, bc.batch_id, bc.consumption_type, bc.direction, bc.quantity,
          bc.unit_cost_cents, bc.created_at, bc.notes,
          bc.sale_item_id, bc.sale_return_item_id, bc.purchase_return_item_id,
          bc.inventory_adjustment_id,
          bc.purchase_return_adjustment_item_id,
          bc.sale_return_adjustment_item_id,
          p0.measurement_type AS measurement_type,
          $_kRefSelect
        FROM batch_consumptions bc
        INNER JOIN ${WarehouseBatchScope.primaryBatches} pb0 ON pb0.id = bc.batch_id
        INNER JOIN products p0 ON p0.id = pb0.product_id
        $_kRefJoins
        WHERE bc.sale_item_id = ?
        ORDER BY bc.id ASC
      ''',
          variables: [Variable.withInt(saleItemId)],
          readsFrom: {
            _db.batchConsumptions,
            _db.productBatches,
            ...WarehouseBatchScope.dependencies(_db),
            _db.products,
            _db.saleItems,
            _db.sales,
            _db.saleReturnItems,
            _db.saleReturns,
            _db.purchaseReturnItems,
            _db.purchaseReturns,
            _db.inventoryAdjustments,
            _db.purchaseReturnAdjustmentItems,
            _db.purchaseReturnAdjustments,
            _db.saleReturnAdjustmentItems,
            _db.saleReturnAdjustments,
          },
        )
        .get();

    return rows.map(_mapConsumption).toList(growable: false);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // ROW MAPPERS
  // ──────────────────────────────────────────────────────────────────────────

  BatchSummary _mapBatchSummary(QueryRow r) {
    // product_name / product_sku are only present in `watchAllBatches` rows.
    // Per-product variants leave them null (the screen owns the header).
    String? productName;
    String? productSku;
    try {
      productName = r.readNullable<String>('product_name');
    } catch (_) {
      /* column not selected */
    }
    try {
      productSku = r.readNullable<String>('product_sku');
    } catch (_) {
      /* column not selected */
    }

    return BatchSummary(
      batchId: r.read<int>('id'),
      batchNumber: r.read<String>('batch_number'),
      manufacturerLotNumber: r.readNullable<String>('manufacturer_lot_number'),
      productId: r.read<int>('product_id'),
      variantId: r.read<int>('variant_id'),
      productName: productName,
      productSku: productSku,
      variantLabel: _composeVariantLabel(
        r.readNullable<String>('color_name'),
        r.readNullable<String>('size_name'),
      ),
      source: r.read<String>('source'),
      supplierId: r.readNullable<int>('supplier_id'),
      supplierName: r.readNullable<String>('supplier_name'),
      purchaseItemId: r.readNullable<int>('purchase_item_id'),
      receivedDate: r.read<DateTime>('received_date'),
      expiryDate: r.readNullable<DateTime>('expiry_date'),
      receivedQuantity: r.read<int>('received_quantity'),
      remainingQuantity: r.read<int>('remaining_quantity'),
      unitCostCents: r.read<int>('unit_cost_cents'),
      quantityScale: MeasurementType.fromDb(
        r.read<String>('measurement_type'),
      ).quantityScale,
      measurementType: r.read<String>('measurement_type'),
      isActive: r.read<int>('is_active') == 1,
    );
  }

  BatchConsumptionRecord _mapConsumption(QueryRow r) {
    final saleItemId = r.readNullable<int>('sale_item_id');
    final saleReturnItemId = r.readNullable<int>('sale_return_item_id');
    final purchaseReturnItemId = r.readNullable<int>('purchase_return_item_id');
    final inventoryAdjustmentId = r.readNullable<int>(
      'inventory_adjustment_id',
    );
    final purchaseAdjItemId = r.readNullable<int>(
      'purchase_return_adjustment_item_id',
    );
    final saleAdjItemId = r.readNullable<int>('sale_return_adjustment_item_id');

    String refKind = 'unknown';
    int? refHeaderId;
    String? refLabel;

    if (saleItemId != null) {
      refKind = 'sale';
      refHeaderId = r.readNullable<int>('sale_id');
      refLabel = r.readNullable<String>('sale_label');
    } else if (saleReturnItemId != null) {
      refKind = 'sale_return';
      refHeaderId = r.readNullable<int>('sale_return_id');
      refLabel = r.readNullable<String>('sale_return_label');
    } else if (purchaseReturnItemId != null) {
      refKind = 'purchase_return';
      refHeaderId = r.readNullable<int>('purchase_return_id');
      refLabel = r.readNullable<String>('purchase_return_label');
    } else if (inventoryAdjustmentId != null) {
      refKind = 'inventory_adjustment';
      refHeaderId = r.readNullable<int>('adjustment_id');
      refLabel = r.readNullable<String>('adjustment_label');
    } else if (purchaseAdjItemId != null) {
      refKind = 'purchase_adj_return';
      refHeaderId = r.readNullable<int>('purchase_adj_id');
      refLabel = r.readNullable<String>('purchase_adj_label');
    } else if (saleAdjItemId != null) {
      refKind = 'sale_adj_return';
      refHeaderId = r.readNullable<int>('sale_adj_id');
      refLabel = r.readNullable<String>('sale_adj_label');
    }

    return BatchConsumptionRecord(
      id: r.read<int>('id'),
      batchId: r.read<int>('batch_id'),
      consumptionType: r.read<String>('consumption_type'),
      direction: r.read<String>('direction'),
      quantity: r.read<int>('quantity'),
      unitCostCents: r.read<int>('unit_cost_cents'),
      quantityScale: MeasurementType.fromDb(
        r.read<String>('measurement_type'),
      ).quantityScale,
      measurementType: r.read<String>('measurement_type'),
      createdAt: r.read<DateTime>('created_at'),
      notes: r.readNullable<String>('notes'),
      refKind: refKind,
      refHeaderId: refHeaderId,
      refLabel: refLabel,
      saleItemId: saleItemId,
    );
  }

  String? _composeVariantLabel(String? color, String? size) {
    if ((color == null || color.isEmpty) && (size == null || size.isEmpty)) {
      return null;
    }
    if (color != null && color.isNotEmpty && size != null && size.isNotEmpty) {
      return '$color / $size';
    }
    return color?.isNotEmpty == true ? color : size;
  }
}

/// Internal accumulator: keeps batches in first-seen order while we net out
/// 'in'/'out' rows. A LinkedHashMap preserves insertion order, which mirrors
/// the FEFO order in which the batches were originally consumed — the most
/// useful order for the UI.
class _LineAcc {
  final Map<int, _BatchAcc> batches = <int, _BatchAcc>{};
}

class _BatchAcc {
  final int batchId;
  final String batchNumber;
  final String? manufacturerLotNumber;
  final int unitCostCents;
  final DateTime? expiryDate;
  int netQty = 0;

  _BatchAcc({
    required this.batchId,
    required this.batchNumber,
    required this.manufacturerLotNumber,
    required this.unitCostCents,
    required this.expiryDate,
  });
}
