import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../measurement/measurement.dart';

import '../../database/app_database.dart';
import '../../database/daos/inventory_adjustment_dao.dart';
import '../batch_service.dart';
import '../journal_entry_service.dart';
import '../price_history_service.dart';
import '../stock_service.dart';
import 'costing_strategy.dart';
import 'product_cost_service.dart';

/// Classification of a manual inventory adjustment. Every type has a FIXED
/// double-entry rule and is non-substitutable — the service will never
/// silently "pick" the type for the caller.
enum InventoryAdjustmentType {
  /// Loss of on-hand stock (theft / damage / expiry / count shortage).
  /// Debits Inventory Shrinkage (5800), credits Inventory (1200).
  shrinkage,

  /// Surplus discovered on physical count (found stock / data correction).
  /// Debits Inventory (1200), credits Inventory Gain (4200).
  gain,

  /// Pure unit-cost change without any physical quantity movement.
  /// Direction determined by sign of `deltaValueCents`.
  revaluation,

  /// Initial stock recorded when creating a new product / variant with a
  /// non-zero opening quantity. Posted against the dedicated
  /// Opening Balance Equity account (3100) — NOT Inventory Gain (4200) —
  /// so financial statements do not falsely inflate "other income" with
  /// starting-inventory entries. Mirrors QuickBooks / Xero behaviour.
  ///
  /// Debits Inventory (1200), credits Opening Balance Equity (3100).
  openingBalance;

  String get wireName => switch (this) {
    InventoryAdjustmentType.shrinkage => 'shrinkage',
    InventoryAdjustmentType.gain => 'gain',
    InventoryAdjustmentType.revaluation => 'revaluation',
    InventoryAdjustmentType.openingBalance => 'opening_balance',
  };
}

/// Result of a successful adjustment — returned so UI / tests can render it
/// without re-reading from the DB.
class InventoryAdjustmentResult {
  final int adjustmentId;
  final String adjustmentNumber;
  final int journalEntryId;
  final int totalValueCents;

  const InventoryAdjustmentResult({
    required this.adjustmentId,
    required this.adjustmentNumber,
    required this.journalEntryId,
    required this.totalValueCents,
  });
}

/// Thrown when a caller attempts an adjustment that would violate inventory
/// or accounting invariants. NEVER caught inside the service — it propagates
/// so the transaction rolls back.
class InventoryAdjustmentException implements Exception {
  final String message;
  const InventoryAdjustmentException(this.message);
  @override
  String toString() => 'InventoryAdjustmentException: $message';
}

/// Transactional, accounting-safe, audit-trailing inventory adjustment.
///
/// Guarantees for every call to [adjust]:
///   1. A non-empty `reason` is required (loudly rejected otherwise).
///   2. Stock ledger (products / product_variants) and General Ledger
///      (journal_entries + journal_entry_lines) are updated in the SAME
///      transaction — either both succeed or both roll back.
///   3. Exactly one `inventory_adjustments` row is written, linked to the
///      posted journal entry by `journal_entry_id` (single source of truth).
///   4. The costing method used is stamped onto the row, so a future FIFO
///      rollout will never retroactively change historical values.
///
/// This is the ONLY sanctioned entry point for manual stock changes.
/// Call sites that used to poke `product_variants.stock_quantity` directly
/// (e.g. +/- buttons on the variants screen) MUST route through this
/// service. Bypasses are a P0 accounting bug.
class InventoryAdjustmentService {
  final AppDatabase _db;
  final InventoryAdjustmentDao _dao;
  final JournalEntryService _journal;
  final CostingStrategy _costing;

  InventoryAdjustmentService({
    required AppDatabase db,
    required InventoryAdjustmentDao dao,
    required JournalEntryService journal,
    CostingStrategy? costing,
  }) : _db = db,
       _dao = dao,
       _journal = journal,
       _costing = costing ?? const WeightedAverageCostingStrategy();

  /// Perform an inventory adjustment. Returns the created adjustment + its
  /// posted journal entry id.
  ///
  /// [quantityDelta]  Signed. Required for [InventoryAdjustmentType.shrinkage]
  ///                  (negative) and [InventoryAdjustmentType.gain] (positive).
  ///                  Ignored (must be 0) for revaluation.
  /// [newUnitCostCents]  Required ONLY for revaluation. The caller supplies
  ///                     the new unit cost; the service reads the old cost
  ///                     and on-hand qty to compute delta value.
  /// [reason]         MANDATORY non-empty human-readable reason — never null,
  ///                  never blank. Stored on both the journal entry and the
  ///                  adjustment row for audit.
  Future<InventoryAdjustmentResult> adjust({
    required int productId,
    int? variantId,
    required InventoryAdjustmentType type,
    int quantityDelta = 0,
    int? newUnitCostCents,
    required String reason,
    String? notes,
    required int currencyId,
    int? userId,
  }) async {
    // ── Input validation — fail loudly, no silent corrections ──
    final trimmedReason = reason.trim();
    if (trimmedReason.isEmpty) {
      throw const InventoryAdjustmentException(
        'reason is mandatory for every inventory adjustment and must be non-empty',
      );
    }
    if (productId <= 0) {
      throw const InventoryAdjustmentException('productId must be > 0');
    }
    if (variantId != null && variantId <= 0) {
      throw const InventoryAdjustmentException(
        'variantId must be > 0 when provided',
      );
    }
    if (currencyId <= 0) {
      throw const InventoryAdjustmentException('currencyId must be > 0');
    }

    switch (type) {
      case InventoryAdjustmentType.shrinkage:
        if (quantityDelta >= 0) {
          throw const InventoryAdjustmentException(
            'shrinkage requires a negative quantityDelta',
          );
        }
        if (newUnitCostCents != null) {
          throw const InventoryAdjustmentException(
            'shrinkage must not specify newUnitCostCents',
          );
        }
      case InventoryAdjustmentType.gain:
        if (quantityDelta <= 0) {
          throw const InventoryAdjustmentException(
            'gain requires a positive quantityDelta',
          );
        }
        if (newUnitCostCents != null) {
          throw const InventoryAdjustmentException(
            'gain must not specify newUnitCostCents',
          );
        }
      case InventoryAdjustmentType.revaluation:
        if (quantityDelta != 0) {
          throw const InventoryAdjustmentException(
            'revaluation must have quantityDelta == 0 (no physical movement)',
          );
        }
        if (newUnitCostCents == null || newUnitCostCents < 0) {
          throw const InventoryAdjustmentException(
            'revaluation requires a non-negative newUnitCostCents',
          );
        }
      case InventoryAdjustmentType.openingBalance:
        if (quantityDelta <= 0) {
          throw const InventoryAdjustmentException(
            'openingBalance requires a positive quantityDelta',
          );
        }
        if (newUnitCostCents != null) {
          throw const InventoryAdjustmentException(
            'openingBalance must not specify newUnitCostCents',
          );
        }
    }

    // Everything below runs in a single DB transaction.
    return _db.transaction<InventoryAdjustmentResult>(() async {
      final now = DateTime.now();
      final adjustmentNumber = await _dao.generateAdjustmentNumber();

      // Hard-stop adjustments on non-tracked products — they have no
      // inventory ledger so the operation would silently disconnect the
      // GL leg (Inventory account 1200) from a non-existent stock change.
      // This mirrors how purchase/sale posting now skip stock writes for
      // these products: every sanctioned stock-touching call site honours
      // the same flag.
      final tracksRow = await _db
          .customSelect(
            'SELECT track_inventory FROM products WHERE id = ?',
            variables: [Variable.withInt(productId)],
          )
          .getSingleOrNull();
      final tracks = (tracksRow?.read<int>('track_inventory') ?? 1) != 0;
      if (!tracks) {
        throw InventoryAdjustmentException(
          'Cannot adjust inventory for product #$productId: '
          'track_inventory is disabled. Enable inventory tracking on the '
          'product first if this item should carry on-hand stock.',
        );
      }

      final int oldUnitCost = await _costing.unitCostCents(
        dao: _dao,
        productId: productId,
        variantId: variantId,
      );
      final int onHand = await _costing.onHandQuantity(
        dao: _dao,
        productId: productId,
        variantId: variantId,
      );

      // Refuse to drive stock below zero. Shrinkage on a zero-stock SKU is
      // almost certainly a data-entry mistake; surface it to the user.
      if (type == InventoryAdjustmentType.shrinkage &&
          onHand + quantityDelta < 0) {
        throw InventoryAdjustmentException(
          'Cannot shrink below zero: onHand=$onHand, delta=$quantityDelta '
          '(product=$productId, variant=${variantId ?? "default"})',
        );
      }

      // ── Compute values, effective unit cost, signed deltaValue ──
      final int effectiveUnitCost = switch (type) {
        InventoryAdjustmentType.revaluation => newUnitCostCents!,
        _ => oldUnitCost,
      };
      final productRow = await _dao
          .customSelect(
            'SELECT measurement_type FROM products WHERE id = ?',
            variables: [Variable.withInt(productId)],
          )
          .getSingleOrNull();
      final quantityScale = MeasurementType.fromDb(
        productRow?.read<String?>('measurement_type'),
      ).quantityScale;

      int quantityValue(int unitCents, int quantity) => MeasuredAmount.cents(
        unitCents: unitCents,
        quantity: quantity.abs(),
        quantityScale: quantityScale,
      );

      final int totalValueCents = switch (type) {
        InventoryAdjustmentType.shrinkage => quantityValue(
          oldUnitCost,
          quantityDelta,
        ),
        InventoryAdjustmentType.gain => quantityValue(
          oldUnitCost,
          quantityDelta,
        ),
        InventoryAdjustmentType.revaluation => MeasuredAmount.cents(
          unitCents: newUnitCostCents! - oldUnitCost,
          quantity: onHand,
          quantityScale: quantityScale,
        ),
        InventoryAdjustmentType.openingBalance => quantityValue(
          oldUnitCost,
          quantityDelta,
        ),
      };

      if (type != InventoryAdjustmentType.revaluation && totalValueCents <= 0) {
        throw InventoryAdjustmentException(
          'Adjustment value must be positive for ${type.wireName} '
          '(computed=$totalValueCents, qty=$quantityDelta, cost=$oldUnitCost). '
          'Refusing to post a zero-value journal entry.',
        );
      }

      if (type == InventoryAdjustmentType.revaluation && totalValueCents == 0) {
        throw const InventoryAdjustmentException(
          'Revaluation produced zero delta (same cost × same qty). '
          'Nothing to post.',
        );
      }

      // ── 1. Insert adjustment row (journal_entry_id filled in below) ──
      final adjustmentId = await _dao.insertAdjustment(
        InventoryAdjustmentsCompanion.insert(
          adjustmentNumber: adjustmentNumber,
          productId: productId,
          variantId: Value(variantId),
          adjustmentType: type.wireName,
          quantityDelta: quantityDelta,
          unitCostCents: Decimal.fromInt(effectiveUnitCost),
          totalValueCents: Decimal.fromInt(totalValueCents),
          previousUnitCostCents: type == InventoryAdjustmentType.revaluation
              ? Value(Decimal.fromInt(oldUnitCost))
              : const Value.absent(),
          reason: trimmedReason,
          notes: Value(notes),
          currencyId: currencyId,
          userId: Value(userId),
          costingMethod: Value(_costing.method.wireName),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      // ── 2. Mutate physical stock (only for shrinkage / gain) ──
      if (quantityDelta != 0) {
        await StockService.adjustStock(
          _dao,
          productId: productId,
          variantId: variantId,
          quantity: quantityDelta.abs(),
          direction: quantityDelta > 0
              ? StockDirection.increase
              : StockDirection.decrease,
        );
        await StockService.syncProductStockFromVariants(
          _dao,
          productId: productId,
        );
      }

      // ── 2b. FIFO batch sync (only for products that need batch-level books).
      //
      // Phase B+: gated on `inventory_tracking_type` (the per-product knob in
      // the two-layer architecture), with a fallback to the legacy
      // `costing_method` column for rows that pre-date migration v10048.
      //
      // Mirrors the physical stock change onto the batch ledger so the
      // invariant Σ(batch.remaining) == product_variants.stock_quantity
      // continues to hold for FIFO products. WAC products skip this branch:
      // their batches are not the source of COGS truth and `cost_cents` on
      // the SKU row is. Revaluation never touches `remaining_quantity`
      // because per-batch unit costs are FROZEN — the new cost takes effect
      // on subsequent purchases / opening batches only.
      final fifoRow = await _db
          .customSelect(
            'SELECT inventory_tracking_type, costing_method '
            'FROM products WHERE id = ?',
            variables: [Variable.withInt(productId)],
          )
          .getSingleOrNull();
      final tracking = fifoRow?.read<String?>('inventory_tracking_type');
      final bool isFifo =
          (tracking == 'batch' || tracking == 'batch_expiry') ||
          (fifoRow?.read<String?>('costing_method') ?? 'wac') == 'fifo';
      if (isFifo && quantityDelta != 0) {
        switch (type) {
          case InventoryAdjustmentType.shrinkage:
            await BatchService.consumeFifo(
              _dao,
              productId: productId,
              variantId: variantId,
              quantity: quantityDelta.abs(),
              consumptionType: 'inventory_shrinkage',
              inventoryAdjustmentId: adjustmentId,
              notes: trimmedReason,
            );
          case InventoryAdjustmentType.gain:
            await BatchService.createOpeningBatch(
              _dao,
              productId: productId,
              variantId: variantId,
              quantity: quantityDelta.abs(),
              unitCostCents: oldUnitCost,
              source: 'found',
            );
          case InventoryAdjustmentType.openingBalance:
            await BatchService.createOpeningBatch(
              _dao,
              productId: productId,
              variantId: variantId,
              quantity: quantityDelta.abs(),
              unitCostCents: oldUnitCost,
              source: 'opening',
            );
          case InventoryAdjustmentType.revaluation:
            // Unreachable: revaluation has quantityDelta == 0 (gated above).
            break;
        }

        // I4 (Invariant I1): assert Σ(batch.remaining) == variant.stock_quantity
        // for the product whose batch ledger was just mutated. Catches any
        // silent desync BEFORE the transaction commits — turns Phase A's
        // documented invariant into an enforced one.
        await BatchService.assertInvariantForProduct(
          _dao,
          productId: productId,
        );
      }

      // ── 3. For revaluation, persist the new unit cost on the SKU row ──
      // Funnels through ProductCostService — the SINGLE sanctioned writer
      // for `cost_cents`. Previously this branch wrote raw `UPDATE` SQL
      // that bypassed every other call site, which is exactly the kind of
      // scattered cost-mutation we are now consolidating.
      if (type == InventoryAdjustmentType.revaluation) {
        if (variantId != null) {
          await ProductCostService.setVariantCost(
            _dao,
            variantId: variantId,
            newCostCents: newUnitCostCents!,
          );
          // Re-aggregate the parent so the product-edit screen reflects
          // the revaluation as a true weighted average across variants.
          // Cost-only sync — stock/price are unaffected by revaluation.
          await ProductCostService.syncProductFromVariants(
            _dao,
            productId: productId,
            syncStock: false,
            syncPrice: false,
          );
        } else {
          // Non-variant product: write to both rows so reads from either
          // place observe the same cost (matches the post-purchase
          // contract). `mirrorToDefaultVariant: true` is the default.
          await ProductCostService.setProductCost(
            _dao,
            productId: productId,
            newCostCents: newUnitCostCents!,
          );
        }

        // Centralized price-history audit — revaluation can ONLY move cost,
        // while retail/wholesale stay put. Persist their real unchanged
        // values rather than synthetic zeroes so every history row remains a
        // complete, independently-readable snapshot.
        final priceRow = variantId == null
            ? await _dao
                  .customSelect(
                    'SELECT price_cents, wholesale_price_cents '
                    'FROM products WHERE id = ?',
                    variables: [Variable.withInt(productId)],
                  )
                  .getSingle()
            : await _dao
                  .customSelect(
                    'SELECT price_cents, wholesale_price_cents '
                    'FROM product_variants WHERE id = ?',
                    variables: [Variable.withInt(variantId)],
                  )
                  .getSingle();
        final unchangedPrice = priceRow.read<int>('price_cents');
        final unchangedWholesale = priceRow.readNullable<int>(
          'wholesale_price_cents',
        );
        await PriceHistoryService.recordIfChanged(
          _dao,
          productId: productId,
          variantId: variantId,
          oldCostCents: oldUnitCost,
          newCostCents: newUnitCostCents,
          oldPriceCents: unchangedPrice,
          newPriceCents: unchangedPrice,
          oldWholesalePriceCents: unchangedWholesale,
          newWholesalePriceCents: unchangedWholesale,
          userId: userId,
          changeReason: 'inventory_revaluation:#$adjustmentId',
        );
      }

      // ── 4. Post the corresponding journal entry ──
      final int journalEntryId = switch (type) {
        InventoryAdjustmentType.shrinkage =>
          await _journal.recordInventoryShrinkageJournalEntry(
            adjustmentId: adjustmentId,
            valueCents: totalValueCents,
            currencyId: currencyId,
            reason: trimmedReason,
            userId: userId,
          ),
        InventoryAdjustmentType.gain =>
          await _journal.recordInventoryGainJournalEntry(
            adjustmentId: adjustmentId,
            valueCents: totalValueCents,
            currencyId: currencyId,
            reason: trimmedReason,
            userId: userId,
          ),
        InventoryAdjustmentType.revaluation =>
          await _journal.recordInventoryRevaluationJournalEntry(
            adjustmentId: adjustmentId,
            deltaValueCents: totalValueCents,
            currencyId: currencyId,
            reason: trimmedReason,
            userId: userId,
          ),
        InventoryAdjustmentType.openingBalance =>
          await _journal.recordInventoryOpeningBalanceJournalEntry(
            adjustmentId: adjustmentId,
            valueCents: totalValueCents,
            currencyId: currencyId,
            reason: trimmedReason,
            userId: userId,
          ),
      };

      // ── 5. Link journal entry id back onto the adjustment row ──
      await _dao.linkJournalEntry(
        adjustmentId: adjustmentId,
        journalEntryId: journalEntryId,
      );

      developer.log(
        'InventoryAdjustment #$adjustmentId posted: '
        'type=${type.wireName} qty=$quantityDelta value=$totalValueCents '
        'journal=$journalEntryId reason="$trimmedReason"',
        name: 'InventoryAdjustmentService',
      );

      return InventoryAdjustmentResult(
        adjustmentId: adjustmentId,
        adjustmentNumber: adjustmentNumber,
        journalEntryId: journalEntryId,
        totalValueCents: totalValueCents,
      );
    });
  }

  /// Convenience wrapper for UI call-sites that do not carry currency in
  /// their state. Resolves `currency_id` from the `products` row and then
  /// delegates to [adjust].
  ///
  /// This is the recommended entry point for in-app screens (e.g. the
  /// manual Inventory Adjustment dialog) because it guarantees the
  /// adjustment is booked in the product's own currency, matching how
  /// purchases/sales already post.
  Future<InventoryAdjustmentResult> adjustForProduct({
    required int productId,
    int? variantId,
    required InventoryAdjustmentType type,
    int quantityDelta = 0,
    int? newUnitCostCents,
    required String reason,
    String? notes,
    int? userId,
  }) async {
    final row = await _db
        .customSelect(
          'SELECT currency_id FROM products WHERE id = ?',
          variables: [Variable.withInt(productId)],
        )
        .getSingleOrNull();
    final currencyId = row?.readNullable<int>('currency_id') ?? 1;
    return adjust(
      productId: productId,
      variantId: variantId,
      type: type,
      quantityDelta: quantityDelta,
      newUnitCostCents: newUnitCostCents,
      reason: reason,
      notes: notes,
      currencyId: currencyId,
      userId: userId,
    );
  }

  /// Convenience wrapper used by product/variant creation code paths.
  ///
  /// If [quantity] is zero or negative, returns `null` and no side-effects
  /// occur (callers are expected to skip the accounting leg in that case).
  ///
  /// Otherwise posts a full opening-balance adjustment:
  ///   * increments on-hand stock from 0 by [quantity]
  ///   * Dr 1200 Inventory / Cr 3100 Opening Balance Equity for qty × cost
  ///   * writes an `inventory_adjustments` row with type = `opening_balance`
  ///
  /// The product's `currency_id` is read from the `products` row so callers
  /// do not have to plumb currency through creation forms.
  Future<InventoryAdjustmentResult?> recordOpeningBalance({
    required int productId,
    int? variantId,
    required int quantity,
    int? userId,
    String reason = 'Opening balance',
    String? notes,
  }) async {
    if (quantity <= 0) return null;

    final row = await _db
        .customSelect(
          'SELECT currency_id FROM products WHERE id = ?',
          variables: [Variable.withInt(productId)],
        )
        .getSingleOrNull();
    final currencyId = row?.readNullable<int>('currency_id') ?? 1;

    return adjust(
      productId: productId,
      variantId: variantId,
      type: InventoryAdjustmentType.openingBalance,
      quantityDelta: quantity,
      reason: reason,
      notes: notes,
      currencyId: currencyId,
      userId: userId,
    );
  }
}
