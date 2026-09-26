import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../database/migrations/consignment_return_liability.dart';
import '../../measurement/measurement.dart';
import '../business/warehouse_operation_scope.dart';
import '../journal_entry_service.dart';

class ConsignmentAdjustmentReturnPlan {
  const ConsignmentAdjustmentReturnPlan({
    required this.layer,
    required this.obligationCents,
    required this.restoresStock,
  });

  final ConsignmentInventoryLayer layer;
  final int obligationCents;
  final bool restoresStock;
}

/// Handles a standalone sale return only when the operator selected an exact
/// consignment custody layer. A null source remains unresolved and is never
/// attributed from a preferred supplier, last purchase, or product card.
class ConsignmentAdjustmentReturnService {
  ConsignmentAdjustmentReturnService._();

  static Future<ConsignmentAdjustmentReturnPlan?> prepare(
    DatabaseAccessor<AppDatabase> dao, {
    required SaleReturnAdjustment item,
    required SaleReturnAdjustmentItem returnItem,
    required int? resolvedVariantId,
    required WarehouseOperationScope scope,
  }) async {
    final layerId = returnItem.consignmentLayerId;
    if (layerId == null) return null;
    final db = dao.attachedDatabase;
    final layer = await (db.select(
      db.consignmentInventoryLayers,
    )..where((row) => row.id.equals(layerId))).getSingleOrNull();
    if (layer == null ||
        layer.warehouseId != scope.warehouseId ||
        layer.productId != returnItem.productId ||
        (resolvedVariantId != null && layer.variantId != resolvedVariantId) ||
        layer.quantityScale != returnItem.quantityScale ||
        layer.measurementType != returnItem.measurementType ||
        layer.status == 'voided' ||
        layer.remainingQuantity + returnItem.quantity >
            layer.receivedQuantity) {
      throw StateError('Invalid consignment source for adjustment return.');
    }
    final product = await (db.select(
      db.products,
    )..where((row) => row.id.equals(returnItem.productId))).getSingle();
    final requiresBatch =
        product.costingMethod == 'fifo' ||
        product.inventoryTrackingType == 'batch' ||
        product.inventoryTrackingType == 'batch_expiry';
    if (requiresBatch != (layer.batchId != null)) {
      throw StateError(
        'Consignment source does not match the product tracking policy.',
      );
    }
    final agreement = await (db.select(
      db.consignmentAgreements,
    )..where((row) => row.id.equals(layer.agreementId))).getSingle();
    if (agreement.currencyId != item.currencyId) {
      throw StateError('Consignment return currency differs from agreement.');
    }
    final itemDiscount = returnItem.itemDiscountAtPostCents?.toBigInt().toInt();
    final invoiceDiscount = returnItem.invoiceDiscountAtPostCents
        ?.toBigInt()
        .toInt();
    if (itemDiscount == null ||
        invoiceDiscount == null ||
        itemDiscount + invoiceDiscount !=
            returnItem.discountCents.toBigInt().toInt()) {
      throw StateError(
        'Consignment adjustment return requires discount snapshots.',
      );
    }
    final subtotal = MeasuredAmount.cents(
      unitCents: returnItem.unitPriceCents.toBigInt().toInt(),
      quantity: returnItem.quantity,
      quantityScale: returnItem.quantityScale,
    );
    final base =
        subtotal -
        (layer.includeLineDiscount ? itemDiscount : 0) -
        (layer.includeInvoiceDiscount ? invoiceDiscount : 0) +
        (layer.includeSalesTax ? returnItem.taxCents.toBigInt().toInt() : 0);
    if (base < 0) {
      throw StateError('Negative consignment adjustment settlement base.');
    }
    final restoresStock = returnItem.dispositionType == 'restock';
    final responsibility = restoresStock
        ? ConsignmentReturnLiabilityResponsibility.supplier
        : await ConsignmentReturnLiabilityStore.requireResolved(
            dao,
            sourceTable: 'sale_return_adjustments',
            sourceId: item.id,
            sourceItemId: returnItem.id,
          );
    final calculatedObligation = layer.settlementBasis == 'fixed_unit_cost'
        ? MeasuredAmount.cents(
            unitCents: layer.unitCostCents!,
            quantity: returnItem.quantity,
            quantityScale: returnItem.quantityScale,
          )
        : _basisPoints(base, layer.supplierShareBps!);
    return ConsignmentAdjustmentReturnPlan(
      layer: layer,
      obligationCents:
          responsibility ==
              ConsignmentReturnLiabilityResponsibility.supplier
          ? calculatedObligation
          : 0,
      restoresStock: restoresStock,
    );
  }

  static Future<void> postAfterStock(
    DatabaseAccessor<AppDatabase> dao, {
    required SaleReturnAdjustment returnData,
    required SaleReturnAdjustmentItem item,
    required ConsignmentAdjustmentReturnPlan plan,
    required int? resolvedVariantId,
    required WarehouseOperationScope scope,
    required JournalEntryService journal,
    int? userId,
  }) async {
    final db = dao.attachedDatabase;
    final now = DateTime.now().toUtc();
    if (plan.restoresStock) {
      final layerChanged = await db.customUpdate(
        'UPDATE consignment_inventory_layers SET '
        'remaining_quantity=remaining_quantity+?,status=?,updated_at=? '
        'WHERE id=? AND remaining_quantity+?<=received_quantity',
        variables: [
          Variable.withInt(item.quantity),
          Variable.withString('open'),
          Variable.withString(now.toIso8601String()),
          Variable.withString(plan.layer.id),
          Variable.withInt(item.quantity),
        ],
        updates: {db.consignmentInventoryLayers},
      );
      if (layerChanged != 1) {
        throw StateError('Consignment layer cannot accept adjustment return.');
      }
      final stockChanged = await db.customUpdate(
        'UPDATE business_warehouse_stocks SET '
        'supplier_owned_quantity=supplier_owned_quantity+?,updated_at=? '
        'WHERE warehouse_id=? AND variant_id=? '
        'AND supplier_owned_quantity+?<=quantity',
        variables: [
          Variable.withInt(item.quantity),
          Variable.withString(now.toIso8601String()),
          Variable.withString(scope.warehouseId),
          Variable.withInt(plan.layer.variantId),
          Variable.withInt(item.quantity),
        ],
        updates: {db.businessWarehouseStocks},
      );
      if (stockChanged != 1) {
        throw StateError(
          'Supplier ownership cannot be restored by adjustment.',
        );
      }
    }

    final batchId = plan.layer.batchId;
    if (plan.restoresStock && batchId != null) {
      final batch = await (db.select(
        db.productBatches,
      )..where((row) => row.id.equals(batchId))).getSingle();
      if (batch.productId != item.productId ||
          batch.variantId != plan.layer.variantId ||
          batch.remainingQuantity + item.quantity > batch.receivedQuantity) {
        throw StateError('Consignment batch cannot accept adjustment return.');
      }
      final batchChanged = await db.customUpdate(
        'UPDATE product_batches SET remaining_quantity=remaining_quantity+?,'
        'updated_at=? WHERE id=? AND remaining_quantity+?<=received_quantity',
        variables: [
          Variable.withInt(item.quantity),
          Variable.withString(now.toIso8601String()),
          Variable.withInt(batchId),
          Variable.withInt(item.quantity),
        ],
        updates: {db.productBatches},
      );
      if (batchChanged != 1) {
        throw StateError('Consignment batch changed during adjustment return.');
      }
      await db.customInsert(
        'INSERT INTO batch_consumptions('
        'batch_id,consumption_type,direction,quantity,unit_cost_cents,'
        'sale_return_adjustment_item_id,created_at) VALUES(?,?,?,?,?,?,?)',
        variables: [
          Variable.withInt(batchId),
          Variable.withString('sale_adj_return_consignment_reverse'),
          Variable.withString('in'),
          Variable.withInt(item.quantity),
          Variable.withInt(batch.unitCostCents.toBigInt().toInt()),
          Variable.withInt(item.id),
          Variable.withString(now.toIso8601String()),
        ],
        updates: {db.batchConsumptions},
      );
      await (db.update(
        db.saleReturnAdjustmentItems,
      )..where((row) => row.id.equals(item.id))).write(
        SaleReturnAdjustmentItemsCompanion(returnBatchId: Value(batchId)),
      );
    }

    final eventId = await db
        .into(db.consignmentAdjustmentReturnEvents)
        .insert(
          ConsignmentAdjustmentReturnEventsCompanion.insert(
            layerId: plan.layer.id,
            supplierId: plan.layer.supplierId,
            agreementId: plan.layer.agreementId,
            currencyId: returnData.currencyId,
            kind: 'adjustment_return_reversal',
            signedQuantity: -item.quantity,
            signedAmountCents: -plan.obligationCents,
            restoresStock: Value(plan.restoresStock),
            returnId: returnData.id,
            returnItemId: item.id,
            requestKey:
                'sale_adj_return:${returnData.id}:item:${item.id}:layer:${plan.layer.id}',
            occurredAt: returnData.returnDate.toUtc(),
          ),
        );
    if (plan.obligationCents > 0) {
      final journalId = await journal.recordConsignmentObligationJournalEntry(
        obligationEventId: eventId,
        signedAmountCents: -plan.obligationCents,
        currencyId: returnData.currencyId,
        entryDate: returnData.returnDate,
        description:
            'Consignment adjustment return #${returnData.id} - supplier #${plan.layer.supplierId}',
        sourceTable: 'consignment_adjustment_return_events',
        userId: userId,
      );
      await _linkJournal(db, eventId, journalId);
    }
  }

  /// Removes custody before the physical quantity is deducted and re-accrues
  /// the exact amount reversed by the posted standalone return.
  static Future<int> prepareVoidBeforeStock(
    DatabaseAccessor<AppDatabase> dao, {
    required SaleReturnAdjustment returnData,
    required SaleReturnAdjustmentItem item,
    required int? resolvedVariantId,
    required WarehouseOperationScope scope,
    required JournalEntryService journal,
    int? userId,
  }) async {
    if (item.consignmentLayerId == null) return 0;
    final db = dao.attachedDatabase;
    final reversal =
        await (db.select(db.consignmentAdjustmentReturnEvents)..where(
              (row) =>
                  row.returnItemId.equals(item.id) &
                  row.kind.equals('adjustment_return_reversal'),
            ))
            .getSingle();
    final duplicate =
        await (db.select(db.consignmentAdjustmentReturnEvents)..where(
              (row) =>
                  row.returnItemId.equals(item.id) &
                  row.kind.equals('adjustment_return_void_reaccrual'),
            ))
            .getSingleOrNull();
    if (duplicate != null) {
      throw StateError('Consignment adjustment return was already reversed.');
    }
    final amount = -reversal.signedAmountCents;
    if (reversal.layerId != item.consignmentLayerId ||
        reversal.signedQuantity != -item.quantity ||
        amount < 0) {
      throw StateError('Invalid consignment adjustment-return history.');
    }
    final layer = await (db.select(
      db.consignmentInventoryLayers,
    )..where((row) => row.id.equals(reversal.layerId))).getSingle();
    if (layer.productId != item.productId ||
        (resolvedVariantId != null && layer.variantId != resolvedVariantId)) {
      throw StateError('Consignment adjustment-return source changed.');
    }
    if (reversal.restoresStock) {
      final layerChanged = await db.customUpdate(
        'UPDATE consignment_inventory_layers SET '
        'remaining_quantity=remaining_quantity-?,'
        "status=CASE WHEN remaining_quantity-?=0 THEN 'exhausted' ELSE 'open' END,"
        'updated_at=? WHERE id=? AND warehouse_id=? '
        'AND variant_id=? AND remaining_quantity>=?',
        variables: [
          Variable.withInt(item.quantity),
          Variable.withInt(item.quantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(reversal.layerId),
          Variable.withString(scope.warehouseId),
          Variable.withInt(layer.variantId),
          Variable.withInt(item.quantity),
        ],
        updates: {db.consignmentInventoryLayers},
      );
      if (layerChanged != 1) {
        throw StateError('Consignment source is unavailable for return void.');
      }
      final stockChanged = await db.customUpdate(
        'UPDATE business_warehouse_stocks SET '
        'supplier_owned_quantity=supplier_owned_quantity-?,updated_at=? '
        'WHERE warehouse_id=? AND variant_id=? '
        'AND supplier_owned_quantity>=?',
        variables: [
          Variable.withInt(item.quantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(scope.warehouseId),
          Variable.withInt(layer.variantId),
          Variable.withInt(item.quantity),
        ],
        updates: {db.businessWarehouseStocks},
      );
      if (stockChanged != 1) {
        throw StateError('Supplier ownership is unavailable for return void.');
      }
    }
    final eventId = await db
        .into(db.consignmentAdjustmentReturnEvents)
        .insert(
          ConsignmentAdjustmentReturnEventsCompanion.insert(
            layerId: reversal.layerId,
            supplierId: reversal.supplierId,
            agreementId: reversal.agreementId,
            currencyId: reversal.currencyId,
            kind: 'adjustment_return_void_reaccrual',
            signedQuantity: item.quantity,
            signedAmountCents: amount,
            restoresStock: Value(reversal.restoresStock),
            returnId: returnData.id,
            returnItemId: item.id,
            requestKey:
                'sale_adj_return_void:${returnData.id}:item:${item.id}:layer:${reversal.layerId}',
            occurredAt: DateTime.now().toUtc(),
          ),
        );
    if (amount > 0) {
      final journalId = await journal.recordConsignmentObligationJournalEntry(
        obligationEventId: eventId,
        signedAmountCents: amount,
        currencyId: reversal.currencyId,
        entryDate: DateTime.now(),
        description:
            'Consignment adjustment return void #${returnData.id} - supplier #${reversal.supplierId}',
        sourceTable: 'consignment_adjustment_return_events',
        userId: userId,
      );
      await _linkJournal(db, eventId, journalId);
    }
    return item.quantity;
  }

  static Future<void> _linkJournal(
    AppDatabase db,
    int eventId,
    int journalId,
  ) async {
    final changed =
        await (db.update(db.consignmentAdjustmentReturnEvents)..where(
              (row) => row.id.equals(eventId) & row.journalEntryId.isNull(),
            ))
            .write(
              ConsignmentAdjustmentReturnEventsCompanion(
                journalEntryId: Value(journalId),
              ),
            );
    if (changed != 1) {
      throw StateError('Consignment adjustment journal link changed.');
    }
  }

  static int _basisPoints(int cents, int basisPoints) =>
      ((BigInt.from(cents) * BigInt.from(basisPoints) + BigInt.from(5000)) ~/
              BigInt.from(10000))
          .toInt();
}
