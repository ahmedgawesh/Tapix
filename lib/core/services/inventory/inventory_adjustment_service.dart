import '../business/warehouse_inventory_reader.dart';
import '../business/warehouse_batch_scope.dart';
import '../business/branch_currency_policy_store.dart';
import '../business/warehouse_operation_scope.dart';
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
    WarehouseOperationScope? scope,
    int? batchId,
    DateTime? expiryDate,
    String? manufacturerLotNumber,
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

    if (batchId != null &&
        (batchId <= 0 || type != InventoryAdjustmentType.shrinkage)) {
      throw const InventoryAdjustmentException(
        'A selected batch is only valid for shrinkage.',
      );
    }
    if ((expiryDate != null || manufacturerLotNumber != null) &&
        type != InventoryAdjustmentType.gain &&
        type != InventoryAdjustmentType.openingBalance) {
      throw const InventoryAdjustmentException(
        'New batch metadata requires an opening or gain.',
      );
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
      final operationScope =
          scope ?? await WarehouseOperationScope.resolve(_db);
      await operationScope.validate(_db);
      final now = DateTime.now();

      // A generic stock adjustment cannot prove whether a counted, damaged or
      // revalued unit belongs to the business or to a consignment supplier.
      // Require the source-aware custody workflow whenever this SKU currently
      // contains supplier-owned stock. This prevents revaluation, shrinkage or
      // gains from silently changing supplier custody or Inventory Asset.
      final custody = await _db
          .customSelect(
            'SELECT COALESCE(SUM(s.supplier_owned_quantity),0) AS quantity '
            'FROM business_warehouse_stocks s '
            'JOIN product_variants v ON v.id=s.variant_id '
            'WHERE s.warehouse_id=? AND v.product_id=? '
            'AND (? IS NULL OR v.id=?)',
            variables: [
              Variable.withString(operationScope.warehouseId),
              Variable.withInt(productId),
              Variable<int>(variantId),
              Variable<int>(variantId),
            ],
          )
          .getSingle();
      if (custody.read<int>('quantity') > 0) {
        throw const InventoryAdjustmentException(
          'This stock contains supplier-owned units. Use a source-aware '
          'consignment custody adjustment.',
        );
      }

      final adjustmentNumber = await _dao.generateAdjustmentNumber();

      // Hard-stop adjustments on non-tracked products — they have no
      // inventory ledger so the operation would silently disconnect the
      // GL leg (Inventory account 1200) from a non-existent stock change.
      // This mirrors how purchase/sale posting now skip stock writes for
      // these products: every sanctioned stock-touching call site honours
      // the same flag.
      final tracksRow = await _db
          .customSelect(
            'SELECT track_inventory, currency_id, costing_method, inventory_tracking_type FROM products WHERE id = ?',
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

      final usesFifoCost = tracksRow?.read<String>('costing_method') == 'fifo';

      if (!operationScope.isPrimary) {
        await BranchCurrencyPolicyStore(_db).requireCurrency(currencyId);
        final method = tracksRow?.read<String>('costing_method');
        final tracking = tracksRow?.read<String>('inventory_tracking_type');
        if ((method != 'wac' && method != 'fifo') ||
            !const {'standard', 'batch', 'batch_expiry'}.contains(tracking)) {
          throw const InventoryAdjustmentException(
            'Additional-warehouse adjustments require supported WAC or FIFO stock.',
          );
        }
        if (tracking == 'batch_expiry' &&
            (type == InventoryAdjustmentType.gain ||
                type == InventoryAdjustmentType.openingBalance) &&
            expiryDate == null) {
          throw const InventoryAdjustmentException(
            'An expiry date is required for this batch.',
          );
        }
        if (tracking != 'standard' &&
            type == InventoryAdjustmentType.shrinkage &&
            batchId == null) {
          throw const InventoryAdjustmentException(
            'Select the physical batch being adjusted.',
          );
        }
        if (tracksRow?.readNullable<int>('currency_id') != currencyId) {
          throw const InventoryAdjustmentException(
            'Adjustment currency must match the product currency.',
          );
        }
        final currency =
            await (_db.select(_db.currencies)..where(
                  (c) => c.id.equals(currencyId) & c.isActive.equals(true),
                ))
                .getSingleOrNull();
        if (currency == null) {
          throw const InventoryAdjustmentException(
            'Adjustment currency is inactive or missing.',
          );
        }
      }

      final trackingType = tracksRow?.read<String>('inventory_tracking_type');
      if (!usesFifoCost &&
          trackingType == 'standard' &&
          (batchId != null ||
              expiryDate != null ||
              manufacturerLotNumber != null)) {
        throw const InventoryAdjustmentException(
          'This product does not use a batch ledger.',
        );
      }

      final int oldUnitCost = await _costing.unitCostCents(
        dao: _dao,
        scope: operationScope,
        productId: productId,
        variantId: variantId,
      );
      final int onHand = await _costing.onHandQuantity(
        dao: _dao,
        scope: operationScope,
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

      int totalValueCents = !operationScope.isPrimary && !usesFifoCost
          ? (type == InventoryAdjustmentType.revaluation
                ? MeasuredAmount.cents(
                        unitCents: newUnitCostCents!,
                        quantity: onHand,
                        quantityScale: quantityScale,
                      ) -
                      MeasuredAmount.cents(
                        unitCents: oldUnitCost,
                        quantity: onHand,
                        quantityScale: quantityScale,
                      )
                : (MeasuredAmount.cents(
                            unitCents: oldUnitCost,
                            quantity: onHand + quantityDelta,
                            quantityScale: quantityScale,
                          ) -
                          MeasuredAmount.cents(
                            unitCents: oldUnitCost,
                            quantity: onHand,
                            quantityScale: quantityScale,
                          ))
                      .abs())
          : switch (type) {
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

      if (type == InventoryAdjustmentType.revaluation) {
        if (onHand <= 0) {
          throw const InventoryAdjustmentException(
            'Revaluation requires positive on-hand stock.',
          );
        }
        if (!usesFifoCost) {
          totalValueCents =
              quantityValue(newUnitCostCents!, onHand) -
              quantityValue(oldUnitCost, onHand);
        }
      }

      final revaluationLayers = <ProductBatch>[];
      if (usesFifoCost && type == InventoryAdjustmentType.revaluation) {
        final stock = await WarehouseInventoryReader.read(
          _dao,
          operationScope,
          productId,
          variantId,
        );
        if (stock.quantity <= 0) {
          throw const InventoryAdjustmentException(
            'FIFO revaluation requires positive on-hand stock.',
          );
        }
        await BatchService.assertInvariant(
          _dao,
          scope: operationScope,
          productId: productId,
          variantId: stock.variantId,
        );
        final rows = await _db
            .customSelect(
              'SELECT pb.* FROM product_batches pb WHERE pb.product_id = ? AND pb.variant_id = ? '
              'AND pb.is_active = 1 AND pb.remaining_quantity > 0 '
              'AND ${WarehouseBatchScope.operationPredicate('pb')} ORDER BY pb.id',
              variables: [
                Variable.withInt(productId),
                Variable.withInt(stock.variantId),
                ...WarehouseBatchScope.operationVariables(operationScope),
              ],
            )
            .get();
        revaluationLayers.addAll(
          rows.map((r) => _db.productBatches.map(r.data)),
        );
        totalValueCents = revaluationLayers.fold<int>(
          0,
          (sum, layer) =>
              sum +
              quantityValue(newUnitCostCents!, layer.remainingQuantity) -
              quantityValue(
                layer.unitCostCents.toBigInt().toInt(),
                layer.remainingQuantity,
              ),
        );
      }

      if (!(usesFifoCost && type == InventoryAdjustmentType.shrinkage) &&
          type != InventoryAdjustmentType.revaluation &&
          totalValueCents <= 0) {
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
          warehouseId: Value(operationScope.warehouseId),
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
          costingMethod: Value(
            usesFifoCost ? 'fifo' : _costing.method.wireName,
          ),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      if (revaluationLayers.isNotEmpty) {
        for (final layer in revaluationLayers) {
          await BatchService.revalueRemainingBatch(
            _dao,
            scope: operationScope,
            batch: layer,
            newUnitCostCents: newUnitCostCents!,
            adjustmentId: adjustmentId,
            adjustmentNumber: adjustmentNumber,
            quantityScale: quantityScale,
          );
        }
        await BatchService.assertInvariant(
          _dao,
          scope: operationScope,
          productId: productId,
          variantId: variantId,
        );
      }

      // ── 2. Mutate physical stock (only for shrinkage / gain) ──
      if (quantityDelta != 0) {
        await StockService.adjustStock(
          _dao,
          scope: operationScope,
          productId: productId,
          variantId: variantId,
          quantity: quantityDelta.abs(),
          direction: quantityDelta > 0
              ? StockDirection.increase
              : StockDirection.decrease,
        );
        await StockService.syncProductStockFromVariants(
          _dao,
          scope: operationScope,
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
      // the SKU row is. FIFO revaluations have already moved the remaining
      // quantity into separately audited layers above.
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
            final consumed = await BatchService.consumeFifo(
              _dao,
              scope: operationScope,
              productId: productId,
              variantId: variantId,
              quantity: quantityDelta.abs(),
              consumptionType: 'inventory_shrinkage',
              requiredBatchId: batchId,
              inventoryAdjustmentId: adjustmentId,
              notes: trimmedReason,
            );
            if (usesFifoCost) {
              // Use each layer's rounded before/after value, rather than
              // rounding the consumed fraction independently. This keeps GL
              // inventory equal to the remaining batch valuation.
              totalValueCents = 0;
              for (final layer in consumed) {
                final batch = await (_db.select(
                  _db.productBatches,
                )..where((b) => b.id.equals(layer.batchId))).getSingle();
                totalValueCents +=
                    quantityValue(
                      layer.unitCostCents,
                      batch.remainingQuantity + layer.quantity,
                    ) -
                    quantityValue(layer.unitCostCents, batch.remainingQuantity);
              }
              if (totalValueCents <= 0) {
                throw const InventoryAdjustmentException(
                  'FIFO shrinkage requires a positive consumed layer value.',
                );
              }
              await (_db.update(
                _db.inventoryAdjustments,
              )..where((a) => a.id.equals(adjustmentId))).write(
                InventoryAdjustmentsCompanion(
                  // Rounded weighted unit cost is descriptive; the exact
                  // layer total remains the authoritative posting amount.
                  unitCostCents: Value(
                    Decimal.fromInt(
                      ((BigInt.from(totalValueCents) *
                                      BigInt.from(quantityScale) +
                                  BigInt.from(quantityDelta.abs() ~/ 2)) ~/
                              BigInt.from(quantityDelta.abs()))
                          .toInt(),
                    ),
                  ),
                  totalValueCents: Value(Decimal.fromInt(totalValueCents)),
                ),
              );
            }
          case InventoryAdjustmentType.gain:
            await BatchService.createOpeningBatch(
              _dao,
              scope: operationScope,
              productId: productId,
              variantId: variantId,
              quantity: quantityDelta.abs(),
              unitCostCents: oldUnitCost,
              source: 'found',
              expiryDate: expiryDate,
              manufacturerLotNumber: manufacturerLotNumber,
            );
          case InventoryAdjustmentType.openingBalance:
            await BatchService.createOpeningBatch(
              _dao,
              scope: operationScope,
              productId: productId,
              variantId: variantId,
              quantity: quantityDelta.abs(),
              unitCostCents: oldUnitCost,
              source: 'opening',
              expiryDate: expiryDate,
              manufacturerLotNumber: manufacturerLotNumber,
            );
          case InventoryAdjustmentType.revaluation:
            // Unreachable: revaluation has quantityDelta == 0 (gated above).
            break;
        }

        // I4 (Invariant I1): assert Σ(batch.remaining) == variant.stock_quantity
        // for the product whose batch ledger was just mutated. Catches any
        // silent desync BEFORE the transaction commits — turns Phase A's
        // documented invariant into an enforced one.
        if (operationScope.isPrimary) {
          await BatchService.assertInvariantForProduct(
            _dao,
            scope: operationScope,
            productId: productId,
          );
        } else {
          // Only this variant moved. Other variants may not yet have been
          // initialized in the additional warehouse.
          await BatchService.assertInvariant(
            _dao,
            scope: operationScope,
            productId: productId,
            variantId: variantId,
          );
        }
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
            scope: operationScope,
            variantId: variantId,
            newCostCents: newUnitCostCents!,
          );
          // Re-aggregate the parent so the product-edit screen reflects
          // the revaluation as a true weighted average across variants.
          // Cost-only sync — stock/price are unaffected by revaluation.
          await ProductCostService.syncProductFromVariants(
            _dao,
            scope: operationScope,
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
            scope: operationScope,
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
        if (operationScope.isPrimary) {
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
    WarehouseOperationScope? scope,
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
      scope: scope,
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
    WarehouseOperationScope? scope,
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
      scope: scope,
    );
  }
}
