import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'logging_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// BATCH SERVICE
// ══════════════════════════════════════════════════════════════════════════════

/// Result of a single FIFO consumption — used by callers to compute COGS and
/// to feed `restoreConsumptions` for symmetric reversals.
class BatchConsumptionResult {
  final int batchId;
  final int consumptionId;
  final int quantity;
  final int unitCostCents;

  const BatchConsumptionResult({
    required this.batchId,
    required this.consumptionId,
    required this.quantity,
    required this.unitCostCents,
  });

  int get totalCostCents => quantity * unitCostCents;
}

/// Static service that manages `ProductBatches` + `BatchConsumptions` under
/// FIFO costing. The single source of truth for "how a sale/return/adjustment
/// physically depletes or restores specific lots".
///
/// Mirrors `StockService` in style: pure-static, takes a
/// `DatabaseAccessor<AppDatabase>` so it composes inside any DAO transaction.
///
/// Invariants enforced by this service:
///   1. `batch.unit_cost_cents` is FROZEN — only inventory revaluation may
///      rewrite it (and that path lives in InventoryAdjustmentDao).
///   2. `batch.remaining_quantity` is mutated *only* through this service.
///   3. Σ(remaining where product_id=P, variant_id=V, is_active=1)
///      == product_variants.stock_quantity (asserted by [assertInvariant]).
///   4. Reversals (`restoreConsumptions`) write a mirrored 'in' direction
///      row carrying the *original* `unit_cost_cents`, never the current
///      product cost — preserves COGS truth across revaluations.
class BatchService {
  BatchService._();

  static const String _tag = 'BatchService';

  // ────────────────────────────────────────────────────────────────────────
  // BATCH CREATION
  // ────────────────────────────────────────────────────────────────────────

  /// Create a new batch sourced from a posted purchase line.
  ///
  /// `unit_cost_cents` is FROZEN to the per-unit cost of the purchase line.
  /// Returns the new `product_batches.id`.
  static Future<int> createBatchFromPurchase(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    int? variantId,
    required int purchaseItemId,
    int? supplierId,
    required int quantity,
    required int unitCostCents,
    DateTime? receivedDate,
    DateTime? expiryDate,
  }) async {
    assert(quantity > 0, 'Batch quantity must be positive');
    final resolvedVariantId =
        await _resolveVariantId(dao, productId: productId, variantId: variantId);
    final batchNumber = 'BATCH-${_yyyymm()}-PI$purchaseItemId';
    return _insertBatch(
      dao,
      productId: productId,
      variantId: resolvedVariantId,
      batchNumber: batchNumber,
      purchaseItemId: purchaseItemId,
      supplierId: supplierId,
      source: 'purchase',
      receivedDate: receivedDate ?? DateTime.now(),
      expiryDate: expiryDate,
      receivedQuantity: quantity,
      unitCostCents: unitCostCents,
    );
  }

  /// Create a non-purchase batch — used for:
  ///   - 'opening'     opening stock at FIFO activation
  ///   - 'found'       inventory_adjustment.gain (count surplus)
  ///   - 'sale_return' sale-adjustment-return (no original invoice)
  ///
  /// [documentReference] — when supplied (the unlinked sale-adjustment-return
  /// path passes the return's `SAR-YYYYMM-NNNN` number), the generated
  /// `batch_number` is derived from it so the batch is directly traceable to
  /// its source return AND can never collide with a *linked* sale-return
  /// document number (which uses the `SR-YYYYMM-NNNN` scheme). Without it the
  /// batch falls back to a generated prefix (`OPEN` / `FOUND` / `SAR`).
  static Future<int> createOpeningBatch(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    int? variantId,
    int? supplierId,
    required int quantity,
    required int unitCostCents,
    required String source,
    DateTime? receivedDate,
    DateTime? expiryDate,
    String? documentReference,
  }) async {
    assert(quantity > 0, 'Batch quantity must be positive');
    assert(
      source == 'opening' || source == 'found' || source == 'sale_return',
      'Invalid opening batch source: $source',
    );
    final resolvedVariantId =
        await _resolveVariantId(dao, productId: productId, variantId: variantId);
    final ts = DateTime.now().microsecondsSinceEpoch;
    // Prefer the source document number so the batch reads as e.g.
    // `SAR-202607-0001-V19-…` in the Batch Management report — unambiguously
    // an *unlinked* sale return, never mistaken for a linked `SR-…` document.
    final String batchNumber;
    final ref = documentReference?.trim();
    if (ref != null && ref.isNotEmpty) {
      batchNumber = '$ref-V$resolvedVariantId-$ts';
    } else {
      final prefix = source == 'opening'
          ? 'OPEN'
          : source == 'found'
              ? 'FOUND'
              : 'SAR';
      batchNumber = '$prefix-${_yyyymm()}-V$resolvedVariantId-$ts';
    }
    return _insertBatch(
      dao,
      productId: productId,
      variantId: resolvedVariantId,
      batchNumber: batchNumber,
      purchaseItemId: null,
      supplierId: supplierId,
      source: source,
      receivedDate: receivedDate ?? DateTime.now(),
      expiryDate: expiryDate,
      receivedQuantity: quantity,
      unitCostCents: unitCostCents,
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // FIFO CONSUMPTION
  // ────────────────────────────────────────────────────────────────────────

  /// Consume [quantity] units from the oldest batches first.
  ///
  /// Ordering: `expiry_date ASC NULLS LAST, received_date ASC, id ASC` — the
  /// classical FIFO rule with expiring lots prioritised. Each batch is
  /// updated with optimistic locking so concurrent consumers cannot
  /// over-deduct: the UPDATE asserts `remaining_quantity >= take`.
  ///
  /// Throws [BatchInsufficientStockException] if the active batches do not
  /// cover the requested quantity. Callers should pre-validate stock
  /// (SaleDao.postSale already does) — this is the safety net.
  ///
  /// Returns the list of consumption rows in the order they were inserted,
  /// each carrying the FROZEN unit cost so the caller can compute COGS as
  /// `Σ result.totalCostCents`.
  static Future<List<BatchConsumptionResult>> consumeFifo(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    int? variantId,
    required int quantity,
    required String consumptionType,
    int? saleItemId,
    int? saleReturnItemId,
    int? purchaseReturnItemId,
    int? inventoryAdjustmentId,
    int? purchaseReturnAdjustmentItemId,
    int? saleReturnAdjustmentItemId,
    String? notes,
  }) async {
    assert(quantity > 0, 'Consumption quantity must be positive');
    final resolvedVariantId =
        await _resolveVariantId(dao, productId: productId, variantId: variantId);

    LoggingService.debug(
      'consumeFifo: product=$productId variant=$resolvedVariantId qty=$quantity '
      'type=$consumptionType',
      tag: _tag,
    );

    int remaining = quantity;
    final results = <BatchConsumptionResult>[];
    // Re-query each iteration so we always see the freshest remaining_quantity.
    while (remaining > 0) {
      final batchRow = await dao.customSelect(
        'SELECT id, remaining_quantity, unit_cost_cents '
        '  FROM product_batches '
        ' WHERE product_id = ? AND variant_id = ? '
        '   AND is_active = 1 AND remaining_quantity > 0 '
        ' ORDER BY (expiry_date IS NULL) ASC, expiry_date ASC, '
        '          received_date ASC, id ASC '
        ' LIMIT 1',
        variables: [
          Variable.withInt(productId),
          Variable.withInt(resolvedVariantId),
        ],
      ).getSingleOrNull();

      if (batchRow == null) {
        throw BatchInsufficientStockException(
          productId: productId,
          variantId: resolvedVariantId,
          requested: quantity,
          shortfall: remaining,
        );
      }

      final batchId = batchRow.read<int>('id');
      final batchRemaining = batchRow.read<int>('remaining_quantity');
      final unitCost = batchRow.read<int>('unit_cost_cents');
      final take = batchRemaining < remaining ? batchRemaining : remaining;

      // Optimistic lock: only succeed if the batch still holds at least [take].
      final updated = await dao.customUpdate(
        'UPDATE product_batches SET remaining_quantity = remaining_quantity - ?, '
        '       updated_at = ? '
        ' WHERE id = ? AND remaining_quantity >= ?',
        variables: [
          Variable.withInt(take),
          Variable.withString(DateTime.now().toIso8601String()),
          Variable.withInt(batchId),
          Variable.withInt(take),
        ],
        updates: {dao.attachedDatabase.productBatches},
        updateKind: UpdateKind.update,
      );

      if (updated == 0) {
        // Race lost — another transaction depleted this batch. Retry loop.
        continue;
      }

      final consumptionId = await _insertConsumption(
        dao,
        batchId: batchId,
        consumptionType: consumptionType,
        direction: 'out',
        quantity: take,
        unitCostCents: unitCost,
        saleItemId: saleItemId,
        saleReturnItemId: saleReturnItemId,
        purchaseReturnItemId: purchaseReturnItemId,
        inventoryAdjustmentId: inventoryAdjustmentId,
        purchaseReturnAdjustmentItemId: purchaseReturnAdjustmentItemId,
        saleReturnAdjustmentItemId: saleReturnAdjustmentItemId,
        notes: notes,
      );

      results.add(BatchConsumptionResult(
        batchId: batchId,
        consumptionId: consumptionId,
        quantity: take,
        unitCostCents: unitCost,
      ));

      remaining -= take;
    }

    return results;
  }

  // ────────────────────────────────────────────────────────────────────────
  // RESTORATION (REVERSALS)
  // ────────────────────────────────────────────────────────────────────────

  /// Reverse a previous consumption identified by at least ONE *source* FK.
  ///
  /// Two FK kinds exist on `batch_consumptions`:
  ///
  ///   * **Source-of-`out`** FKs — tagged by [consumeFifo] when the `out`
  ///     row was first written. These identify *which historical
  ///     consumption is being reversed* and are valid WHERE filters:
  ///       - `saleItemId`                       (sale `out` rows)
  ///       - `purchaseReturnItemId`             (purchase-return `out` rows)
  ///       - `purchaseReturnAdjustmentItemId`   (purchase-adj-return `out`)
  ///       - `inventoryAdjustmentId`            (shrinkage `out` rows)
  ///       - `saleReturnAdjustmentItemId`       (sale-adj-return-void `out`)
  ///
  ///   * **Reversal-context** FK — *never* present on an `out` row by
  ///     design. Only stamped on the new `in` row so a later "void the
  ///     reversal" path can find the rows it created. Filtering by this
  ///     in the WHERE clause would return zero matches:
  ///       - `saleReturnItemId`
  ///
  ///   The bug fixed here (May 2026): the old implementation ANDed
  ///   `sale_return_item_id = ?` into the WHERE clause whenever the caller
  ///   passed it. Posting a sale return then matched **0** source `out`
  ///   rows (they all carry `sale_return_item_id IS NULL`), so the batch
  ///   ledger was never restored even though `StockService.adjustStock`
  ///   incremented `product_variants.stock_quantity`. The cross-table
  ///   invariant `Σ(batch.remaining) == stock_quantity` then aborted the
  ///   transaction. See `test/core/services/batch_service_sale_return_restore_test.dart`.
  ///
  /// For every matched `out` row, inserts a mirrored `in` row at the
  /// *original* `unit_cost_cents` and increments `batch.remaining_quantity`.
  ///
  /// Returns the total quantity restored. Returns 0 if no matching
  /// consumption was found (e.g. legacy WAC sale).
  static Future<int> restoreConsumptions(
    DatabaseAccessor<AppDatabase> dao, {
    required String reverseConsumptionType,
    int? saleItemId,
    int? saleReturnItemId,
    int? purchaseReturnItemId,
    int? inventoryAdjustmentId,
    int? purchaseReturnAdjustmentItemId,
    int? saleReturnAdjustmentItemId,
    int? upToQuantity,
    String? notes,
  }) async {
    // Only "source-of-`out`" FKs are valid WHERE filters. The
    // reversal-context FK (`saleReturnItemId`) is stamped on the new `in`
    // row but excluded from the filter — `out` rows never carry it.
    final filters = <String>[];
    final vars = <Variable>[];
    if (saleItemId != null) {
      filters.add('sale_item_id = ?');
      vars.add(Variable.withInt(saleItemId));
    }
    if (purchaseReturnItemId != null) {
      filters.add('purchase_return_item_id = ?');
      vars.add(Variable.withInt(purchaseReturnItemId));
    }
    if (inventoryAdjustmentId != null) {
      filters.add('inventory_adjustment_id = ?');
      vars.add(Variable.withInt(inventoryAdjustmentId));
    }
    if (purchaseReturnAdjustmentItemId != null) {
      filters.add('purchase_return_adjustment_item_id = ?');
      vars.add(Variable.withInt(purchaseReturnAdjustmentItemId));
    }
    if (saleReturnAdjustmentItemId != null) {
      filters.add('sale_return_adjustment_item_id = ?');
      vars.add(Variable.withInt(saleReturnAdjustmentItemId));
    }
    if (filters.isEmpty) {
      throw ArgumentError(
        'restoreConsumptions: at least one source-of-`out` FK must be '
        'provided (saleItemId, purchaseReturnItemId, '
        'purchaseReturnAdjustmentItemId, inventoryAdjustmentId, or '
        'saleReturnAdjustmentItemId). `saleReturnItemId` is a '
        'reversal-context tag only and cannot be used in isolation.',
      );
    }

    // Fetch every 'out' row matching the source so we can mirror them.
    final rows = await dao.customSelect(
      'SELECT id, batch_id, quantity, unit_cost_cents '
      '  FROM batch_consumptions '
      ' WHERE direction = ? AND ${filters.join(' AND ')} '
      ' ORDER BY id ASC',
      variables: [Variable.withString('out'), ...vars],
    ).get();

    int restored = 0;
    int budget = upToQuantity ?? 1 << 30;

    for (final r in rows) {
      if (budget <= 0) break;
      final batchId = r.read<int>('batch_id');
      final originalQty = r.read<int>('quantity');
      final unitCost = r.read<int>('unit_cost_cents');
      final restoreQty = originalQty <= budget ? originalQty : budget;
      budget -= restoreQty;

      await dao.customUpdate(
        'UPDATE product_batches '
        '   SET remaining_quantity = remaining_quantity + ?, '
        '       updated_at = ? '
        ' WHERE id = ?',
        variables: [
          Variable.withInt(restoreQty),
          Variable.withString(DateTime.now().toIso8601String()),
          Variable.withInt(batchId),
        ],
        updates: {dao.attachedDatabase.productBatches},
        updateKind: UpdateKind.update,
      );

      await _insertConsumption(
        dao,
        batchId: batchId,
        consumptionType: reverseConsumptionType,
        direction: 'in',
        quantity: restoreQty,
        unitCostCents: unitCost,
        saleItemId: saleItemId,
        saleReturnItemId: saleReturnItemId,
        purchaseReturnItemId: purchaseReturnItemId,
        inventoryAdjustmentId: inventoryAdjustmentId,
        purchaseReturnAdjustmentItemId: purchaseReturnAdjustmentItemId,
        saleReturnAdjustmentItemId: saleReturnAdjustmentItemId,
        notes: notes,
      );

      restored += restoreQty;
    }

    LoggingService.debug(
      'restoreConsumptions: type=$reverseConsumptionType restored=$restored '
      'matched ${rows.length} rows',
      tag: _tag,
    );
    return restored;
  }

  // ────────────────────────────────────────────────────────────────────────
  // EXPIRY MUTATION (Invariant I7)
  // ────────────────────────────────────────────────────────────────────────

  /// Update the `expiry_date` of an existing batch.
  ///
  /// Invariant I7 — *expiry-date freeze after first consumption*:
  /// once any `'out'` row exists in `batch_consumptions` for this batch,
  /// its `expiry_date` is FROZEN. Any later change would silently re-order
  /// historical FEFO consumptions in audit views and could turn a sale
  /// posted yesterday under one expiry into a sale that "should" have
  /// drawn from a different batch — breaking traceability.
  ///
  /// Allowed:
  /// * Correct a typo before the batch sees any sale / shrinkage / return.
  /// * Re-date a freshly received purchase line.
  ///
  /// Refused (throws [BatchExpiryLockedException]):
  /// * The batch already has at least one `direction = 'out'` consumption.
  ///   Caller must instead create a corrective inventory adjustment.
  ///
  /// The batch must exist and be active. Inactive (voided) batches reject
  /// the call as well — there's no business need to retro-edit them.
  static Future<void> updateExpiryDate(
    DatabaseAccessor<AppDatabase> dao, {
    required int batchId,
    required DateTime? newExpiry,
  }) async {
    final batchRow = await dao.customSelect(
      'SELECT id, is_active, expiry_date FROM product_batches WHERE id = ?',
      variables: [Variable.withInt(batchId)],
    ).getSingleOrNull();
    if (batchRow == null) {
      throw StateError(
        'BatchService.updateExpiryDate: batch=$batchId not found.',
      );
    }
    final isActive = batchRow.read<int>('is_active') == 1;
    if (!isActive) {
      throw BatchExpiryLockedException(
        batchId: batchId,
        reason: 'inactive',
      );
    }

    final outCountRow = await dao.customSelect(
      'SELECT COUNT(*) AS c FROM batch_consumptions '
      ' WHERE batch_id = ? AND direction = \'out\'',
      variables: [Variable.withInt(batchId)],
    ).getSingle();
    final outCount = outCountRow.read<int>('c');
    if (outCount > 0) {
      throw BatchExpiryLockedException(
        batchId: batchId,
        reason: 'has_consumptions',
        consumptionCount: outCount,
      );
    }

    await dao.customUpdate(
      'UPDATE product_batches '
      '   SET expiry_date = ?, updated_at = ? '
      ' WHERE id = ?',
      variables: [
        newExpiry == null
            ? const Variable<String>(null)
            : Variable.withString(newExpiry.toIso8601String()),
        Variable.withString(DateTime.now().toIso8601String()),
        Variable.withInt(batchId),
      ],
      updates: {dao.attachedDatabase.productBatches},
      updateKind: UpdateKind.update,
    );

    LoggingService.debug(
      'updateExpiryDate: batch=$batchId newExpiry=$newExpiry',
      tag: _tag,
    );
  }

  // ────────────────────────────────────────────────────────────────────────
  // INVARIANT GUARD
  // ────────────────────────────────────────────────────────────────────────

  /// Verify Σ(remaining_quantity) for the (product, variant) pair equals
  /// the variant's `stock_quantity`. Throws [StateError] when violated.
  ///
  /// Should be called at the end of any FIFO-mutating transaction so that
  /// a desync is caught immediately rather than poisoning later reports.
  static Future<void> assertInvariant(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    int? variantId,
  }) async {
    final resolvedVariantId =
        await _resolveVariantId(dao, productId: productId, variantId: variantId);

    final batchSumRow = await dao.customSelect(
      'SELECT COALESCE(SUM(remaining_quantity), 0) AS total '
      '  FROM product_batches '
      ' WHERE product_id = ? AND variant_id = ? AND is_active = 1',
      variables: [
        Variable.withInt(productId),
        Variable.withInt(resolvedVariantId),
      ],
    ).getSingle();
    final batchTotal = batchSumRow.read<int>('total');

    final variantRow = await dao.customSelect(
      'SELECT stock_quantity FROM product_variants WHERE id = ?',
      variables: [Variable.withInt(resolvedVariantId)],
    ).getSingleOrNull();
    final stockQty = variantRow?.read<int>('stock_quantity') ?? 0;

    if (batchTotal != stockQty) {
      throw StateError(
        'BatchService.assertInvariant: product=$productId variant=$resolvedVariantId '
        'Σ(batch.remaining)=$batchTotal but product_variants.stock_quantity=$stockQty. '
        'Refuse to leave the transaction in a desynchronised state.',
      );
    }
  }

  /// Convenience: assert invariant for every variant of a product.
  static Future<void> assertInvariantForProduct(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
  }) async {
    final variantRows = await dao.customSelect(
      'SELECT id FROM product_variants WHERE product_id = ? AND is_active = 1',
      variables: [Variable.withInt(productId)],
    ).get();
    for (final r in variantRows) {
      await assertInvariant(
        dao,
        productId: productId,
        variantId: r.read<int>('id'),
      );
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ────────────────────────────────────────────────────────────────────────

  /// Resolve a `null` variantId to the product's default variant
  /// (color_id IS NULL AND size_id IS NULL). Throws if no default exists —
  /// callers must always operate on a real variant for FIFO to be sound.
  static Future<int> _resolveVariantId(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    required int? variantId,
  }) async {
    if (variantId != null) return variantId;
    final row = await dao.customSelect(
      'SELECT id FROM product_variants '
      ' WHERE product_id = ? AND color_id IS NULL AND size_id IS NULL '
      ' ORDER BY id ASC LIMIT 1',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();
    if (row == null) {
      // Fall back to ANY variant (the only one for non-variant products that
      // somehow lost their default; we bail out if the product has none at all).
      final any = await dao.customSelect(
        'SELECT id FROM product_variants '
        ' WHERE product_id = ? AND is_active = 1 '
        ' ORDER BY id ASC LIMIT 1',
        variables: [Variable.withInt(productId)],
      ).getSingleOrNull();
      if (any == null) {
        throw StateError(
          'BatchService: product=$productId has no active variant — cannot '
          'attach a batch. Ensure the product has at least one variant '
          '(default for non-variant products).',
        );
      }
      return any.read<int>('id');
    }
    return row.read<int>('id');
  }

  static Future<int> _insertBatch(
    DatabaseAccessor<AppDatabase> dao, {
    required int productId,
    required int variantId,
    required String batchNumber,
    required int? purchaseItemId,
    required int? supplierId,
    required String source,
    required DateTime receivedDate,
    required DateTime? expiryDate,
    required int receivedQuantity,
    required int unitCostCents,
  }) async {
    final now = DateTime.now().toIso8601String();
    await dao.customInsert(
      'INSERT INTO product_batches '
      '(product_id, variant_id, batch_number, purchase_item_id, supplier_id, '
      ' source, received_date, expiry_date, received_quantity, '
      ' remaining_quantity, unit_cost_cents, is_active, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)',
      variables: [
        Variable.withInt(productId),
        Variable.withInt(variantId),
        Variable.withString(batchNumber),
        if (purchaseItemId != null)
          Variable.withInt(purchaseItemId)
        else
          const Variable<int>(null),
        if (supplierId != null)
          Variable.withInt(supplierId)
        else
          const Variable<int>(null),
        Variable.withString(source),
        Variable.withString(receivedDate.toIso8601String()),
        if (expiryDate != null)
          Variable.withString(expiryDate.toIso8601String())
        else
          const Variable<String>(null),
        Variable.withInt(receivedQuantity),
        Variable.withInt(receivedQuantity),
        Variable.withInt(unitCostCents),
        Variable.withString(now),
        Variable.withString(now),
      ],
      updates: {dao.attachedDatabase.productBatches},
    );
    final idRow = await dao
        .customSelect('SELECT last_insert_rowid() AS id')
        .getSingle();
    return idRow.read<int>('id');
  }

  static Future<int> _insertConsumption(
    DatabaseAccessor<AppDatabase> dao, {
    required int batchId,
    required String consumptionType,
    required String direction,
    required int quantity,
    required int unitCostCents,
    int? saleItemId,
    int? saleReturnItemId,
    int? purchaseReturnItemId,
    int? inventoryAdjustmentId,
    int? purchaseReturnAdjustmentItemId,
    int? saleReturnAdjustmentItemId,
    String? notes,
  }) async {
    await dao.customInsert(
      'INSERT INTO batch_consumptions '
      '(batch_id, consumption_type, direction, quantity, unit_cost_cents, '
      ' sale_item_id, sale_return_item_id, purchase_return_item_id, '
      ' inventory_adjustment_id, purchase_return_adjustment_item_id, '
      ' sale_return_adjustment_item_id, notes, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable.withInt(batchId),
        Variable.withString(consumptionType),
        Variable.withString(direction),
        Variable.withInt(quantity),
        Variable.withInt(unitCostCents),
        _intOrNull(saleItemId),
        _intOrNull(saleReturnItemId),
        _intOrNull(purchaseReturnItemId),
        _intOrNull(inventoryAdjustmentId),
        _intOrNull(purchaseReturnAdjustmentItemId),
        _intOrNull(saleReturnAdjustmentItemId),
        notes != null ? Variable.withString(notes) : const Variable<String>(null),
        Variable.withString(DateTime.now().toIso8601String()),
      ],
      updates: {dao.attachedDatabase.batchConsumptions},
    );
    final idRow = await dao
        .customSelect('SELECT last_insert_rowid() AS id')
        .getSingle();
    return idRow.read<int>('id');
  }

  static Variable _intOrNull(int? v) =>
      v == null ? const Variable<int>(null) : Variable.withInt(v);

  static String _yyyymm() {
    final n = DateTime.now();
    final y = n.year.toString().padLeft(4, '0');
    final m = n.month.toString().padLeft(2, '0');
    return '$y$m';
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// EXCEPTIONS
// ══════════════════════════════════════════════════════════════════════════════

/// Raised by [BatchService.consumeFifo] when active batches do not cover the
/// requested quantity. FIFO products are *not* allowed to go negative — callers
/// must validate stock or handle this exception explicitly.
class BatchInsufficientStockException implements Exception {
  final int productId;
  final int variantId;
  final int requested;
  final int shortfall;

  const BatchInsufficientStockException({
    required this.productId,
    required this.variantId,
    required this.requested,
    required this.shortfall,
  });

  @override
  String toString() =>
      'BatchInsufficientStockException(product=$productId variant=$variantId '
      'requested=$requested shortfall=$shortfall)';
}

/// Raised by [BatchService.updateExpiryDate] when the requested edit is
/// refused by Invariant I7 — *expiry-date freeze after first consumption*.
///
/// `reason` is one of:
///   - `'has_consumptions'` — the batch already has at least one `'out'`
///     row in `batch_consumptions` (a sale, shrinkage, or purchase return
///     drew from this lot). [consumptionCount] tells how many.
///   - `'inactive'` — the batch was voided (`is_active = 0`). Re-dating
///     a voided lot is meaningless; correct via inventory adjustment.
class BatchExpiryLockedException implements Exception {
  final int batchId;
  final String reason;
  final int consumptionCount;

  const BatchExpiryLockedException({
    required this.batchId,
    required this.reason,
    this.consumptionCount = 0,
  });

  @override
  String toString() => 'BatchExpiryLockedException(batch=$batchId '
      'reason=$reason consumptionCount=$consumptionCount): expiry_date is '
      'frozen after first consumption (Invariant I7). Use inventory '
      'adjustment to correct historical lots.';
}
