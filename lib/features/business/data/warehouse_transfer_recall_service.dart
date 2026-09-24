import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/measurement/measurement.dart';
import '../../../core/services/batch_service.dart';
import '../../../core/services/business/warehouse_inventory_reader.dart';
import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../../core/services/inventory/wac_movement_service.dart';
import '../../../core/services/stock_service.dart';
import '../../accounting/data/repositories/accounting_repository.dart';
import '../../accounting/domain/models/journal_entry_data.dart';
import 'warehouse_transfer_repository.dart';

class WarehouseTransferRecallResult {
  const WarehouseTransferRecallResult({
    required this.transfer,
    required this.recall,
    required this.items,
  });

  final WarehouseTransfer transfer;
  final WarehouseTransferRecall recall;
  final List<WarehouseTransferRecallItem> items;
}

/// Closes a dispatched transfer by returning every still-in-transit quantity
/// to its original source. Posted receipts remain immutable and untouched.
class WarehouseTransferRecallService {
  WarehouseTransferRecallService(
    this.db, {
    required this.authorize,
    AccountingRepository? accounting,
  }) : accounting = accounting ?? AccountingRepository(db);

  final AppDatabase db;
  final AuthorizeTransferDraft authorize;
  final AccountingRepository accounting;

  static String _key(String input) {
    final key = input.trim().toLowerCase();
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(key)) {
      throw ArgumentError('A stable UUID recall key is required');
    }
    return key;
  }

  static String _hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  static int _valueAt(WarehouseTransferAllocation allocation, int quantity) =>
      allocation.ownerType == 'consignment'
      ? 0
      : MeasuredAmount.cents(
          unitCents: allocation.unitCostCents,
          quantity: quantity,
          quantityScale: allocation.quantityScale,
        );

  Future<int> _actor(WarehouseTransfer transfer) async {
    final actor = await authorize(
      TransferDraftAction.recall,
      transfer.sourceWarehouseId,
      transfer.destinationWarehouseId,
    );
    final active =
        await (db.select(db.users)
              ..where((row) => row.id.equals(actor) & row.isActive.equals(1)))
            .getSingleOrNull();
    if (active == null) {
      throw StateError('Transfer recall requires an active user');
    }
    return actor;
  }

  Future<WarehouseTransferRecallResult> _result(
    WarehouseTransfer transfer,
    WarehouseTransferRecall recall,
  ) async {
    if (!recall.sealed || transfer.status != 'cancelled') {
      throw StateError('Transfer recall is incomplete');
    }
    final items =
        await (db.select(db.warehouseTransferRecallItems)
              ..where((row) => row.recallId.equals(recall.id))
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    if (items.length != recall.itemCount) {
      throw StateError('Transfer recall item count changed');
    }
    return WarehouseTransferRecallResult(
      transfer: transfer,
      recall: recall,
      items: List.unmodifiable(items),
    );
  }

  Future<WarehouseTransferRecallResult> recall({
    required String transferId,
    required String requestKey,
    required String reason,
    DateTime? recalledAt,
  }) => db.transaction(() async {
    final key = _key(requestKey);
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty || normalizedReason.length > 500) {
      throw ArgumentError(
        'A recall reason of up to 500 characters is required',
      );
    }
    var transfer = await (db.select(
      db.warehouseTransfers,
    )..where((row) => row.id.equals(transferId))).getSingle();
    final actor = await _actor(transfer);
    final hash = _hash({
      'version': 1,
      'kind': 'warehouse_transfer_recall',
      'transfer': transfer.id,
      'actor': actor,
      'reason': normalizedReason,
    });
    final replay = await (db.select(
      db.warehouseTransferRecalls,
    )..where((row) => row.requestKey.equals(key))).getSingleOrNull();
    if (replay != null) {
      if (replay.transferId != transfer.id || replay.requestHash != hash) {
        throw StateError('Recall request key belongs to another operation');
      }
      return _result(transfer, replay);
    }
    if (!transfer.sealed ||
        !const {'in_transit', 'partially_received'}.contains(transfer.status)) {
      throw StateError('Only an in-transit transfer can be recalled');
    }
    final dispatch =
        await (db.select(db.warehouseTransferDispatches)..where(
              (row) =>
                  row.transferId.equals(transfer.id) & row.sealed.equals(true),
            ))
            .getSingle();
    final source = await WarehouseOperationScope.resolve(
      db,
      warehouseId: transfer.sourceWarehouseId,
    );
    final destination = await WarehouseOperationScope.resolve(
      db,
      warehouseId: transfer.destinationWarehouseId,
    );
    if (source.organizationId != transfer.organizationId ||
        source.branchId != transfer.branchId ||
        source.databaseId != transfer.databaseId ||
        destination.organizationId != transfer.organizationId ||
        destination.branchId != transfer.branchId ||
        destination.databaseId != transfer.databaseId) {
      throw StateError('Transfer warehouse binding changed');
    }

    final allocations =
        await (db.select(db.warehouseTransferAllocations)
              ..where((row) => row.dispatchId.equals(dispatch.id))
              ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
            .get();
    final plans = <_RecallPlan>[];
    for (final allocation in allocations) {
      final consumed = await db
          .customSelect(
            '''SELECT COALESCE(SUM(i.accepted_quantity+i.damaged_quantity+i.lost_quantity),0) AS quantity
        FROM warehouse_transfer_receipt_items i
        JOIN warehouse_transfer_receipts r ON r.id=i.receipt_id
        WHERE i.allocation_id=? AND r.sealed=1''',
            variables: [Variable.withString(allocation.id)],
          )
          .getSingle();
      final remaining = allocation.quantity - consumed.read<int>('quantity');
      if (remaining <= 0) continue;
      final line = await (db.select(
        db.warehouseTransferLines,
      )..where((row) => row.id.equals(allocation.lineId))).getSingle();
      final product = await (db.select(
        db.products,
      )..where((row) => row.id.equals(line.productId))).getSingle();
      final tracked =
          product.costingMethod == 'fifo' ||
          const {
            'batch',
            'batch_expiry',
          }.contains(product.inventoryTrackingType);
      if (tracked && allocation.sourceBatchId == null) {
        throw StateError('Tracked recall is missing its source batch');
      }
      ConsignmentInventoryLayer? layer;
      if (allocation.sourceConsignmentLayerId != null) {
        layer =
            await (db.select(db.consignmentInventoryLayers)..where(
                  (row) => row.id.equals(allocation.sourceConsignmentLayerId!),
                ))
                .getSingle();
      }
      plans.add(
        _RecallPlan(
          allocation: allocation,
          line: line,
          quantity: remaining,
          valueCents: _valueAt(allocation, remaining),
          tracked: tracked,
          sourceLayer: layer,
        ),
      );
    }
    if (plans.isEmpty) {
      throw StateError('No in-transit quantity remains to recall');
    }
    final ownedValue = plans.fold<int>(0, (sum, row) => sum + row.valueCents);
    final moment = (recalledAt ?? DateTime.now()).toUtc();
    final recallId = await db
        .into(db.warehouseTransferRecalls)
        .insert(
          WarehouseTransferRecallsCompanion.insert(
            transferId: transfer.id,
            requestKey: key,
            requestHash: hash,
            actorId: actor,
            itemCount: plans.length,
            ownedValueCents: ownedValue,
            reason: normalizedReason,
            recalledAt: moment,
          ),
        );

    final touchedProducts = <int>{};
    final trackedProducts = <int>{};
    for (final plan in plans) {
      await db
          .into(db.warehouseTransferRecallItems)
          .insert(
            WarehouseTransferRecallItemsCompanion.insert(
              recallId: recallId,
              allocationId: plan.allocation.id,
              quantity: plan.quantity,
              valueCents: plan.valueCents,
            ),
          );
      final wac = plan.allocation.ownerType == 'owned' && !plan.tracked
          ? await WacMovementService.capture(
              db.productDao,
              productId: plan.line.productId,
              variantId: plan.line.variantId,
              scope: source,
            )
          : null;
      await StockService.adjustStock(
        db.productDao,
        productId: plan.line.productId,
        variantId: plan.line.variantId,
        quantity: plan.quantity,
        direction: StockDirection.increase,
        scope: source,
        origin: InventoryOriginIntent.keyed(
          'transfer_recall',
          'transfer_recall:$recallId:${plan.allocation.id}',
          reference: 'transfer_out:${plan.allocation.id}',
          referenceWarehouse: source.warehouseId,
        ),
      );
      if (wac != null) {
        await WacMovementService.applyInbound(
          db.productDao,
          snapshot: wac,
          addedQty: plan.quantity,
          inboundUnitCostCents: plan.allocation.unitCostCents,
        );
      }
      final layer = plan.sourceLayer;
      if (layer != null) {
        final changed = await db.customUpdate(
          'UPDATE consignment_inventory_layers SET '
          'remaining_quantity=remaining_quantity+?,status=?,updated_at=? '
          'WHERE id=? AND remaining_quantity+?<=received_quantity',
          variables: [
            Variable.withInt(plan.quantity),
            const Variable<String>('open'),
            Variable.withString(moment.toIso8601String()),
            Variable.withString(layer.id),
            Variable.withInt(plan.quantity),
          ],
          updates: {db.consignmentInventoryLayers},
        );
        if (changed != 1) {
          throw StateError('Consignment source layer cannot accept the recall');
        }
        final ownershipChanged = await db.customUpdate(
          'UPDATE business_warehouse_stocks SET '
          'supplier_owned_quantity=supplier_owned_quantity+?,updated_at=? '
          'WHERE warehouse_id=? AND variant_id=?',
          variables: [
            Variable.withInt(plan.quantity),
            Variable.withString(moment.toIso8601String()),
            Variable.withString(source.warehouseId),
            Variable.withInt(plan.line.variantId),
          ],
          updates: {db.businessWarehouseStocks},
        );
        if (ownershipChanged != 1) {
          throw StateError('Supplier-owned source balance is missing');
        }
      }
      if (plan.tracked) {
        await BatchService.restoreTransferAllocation(
          db.productDao,
          transferAllocationId: plan.allocation.id,
          expectedBatchId: plan.allocation.sourceBatchId!,
          expectedQuantity: plan.quantity,
          scope: source,
        );
        trackedProducts.add(plan.line.productId);
      }
      touchedProducts.add(plan.line.productId);
    }
    for (final productId in touchedProducts) {
      await StockService.syncProductStockFromVariants(
        db.productDao,
        productId: productId,
        scope: source,
      );
      if (trackedProducts.contains(productId)) {
        await WarehouseInventoryReader.assertBatches(
          db.productDao,
          scope: source,
          productId: productId,
        );
      }
    }

    int? journalId;
    if (ownedValue > 0) {
      final accounts = {
        for (final account in await (db.select(
          db.accounts,
        )..where((row) => row.accountCode.isIn(const ['1200', '1210']))).get())
          account.accountCode: account,
      };
      if (!accounts.keys.toSet().containsAll({'1200', '1210'})) {
        throw StateError('Required transfer recall accounts are missing');
      }
      journalId = await accounting.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Warehouse transfer recall ${transfer.id}',
          debitAccountId: accounts['1200']!.id,
          creditAccountId: accounts['1210']!.id,
          amountCents: ownedValue,
          currencyId: transfer.currencyId,
          entryDate: moment,
          entryType: 'warehouse_transfer_recall',
          sourceTable: 'warehouse_transfer_recalls',
          sourceId: recallId,
        ),
        userId: actor,
      );
    }
    await (db.update(
      db.warehouseTransferRecalls,
    )..where((row) => row.id.equals(recallId))).write(
      WarehouseTransferRecallsCompanion(
        journalEntryId: Value(journalId),
        sealed: const Value(true),
      ),
    );
    final changed =
        await (db.update(db.warehouseTransfers)..where(
              (row) =>
                  row.id.equals(transfer.id) &
                  row.status.isIn(const ['in_transit', 'partially_received']),
            ))
            .write(
              const WarehouseTransfersCompanion(status: Value('cancelled')),
            );
    if (changed != 1) throw StateError('Transfer state changed during recall');

    transfer = await (db.select(
      db.warehouseTransfers,
    )..where((row) => row.id.equals(transfer.id))).getSingle();
    final recall = await (db.select(
      db.warehouseTransferRecalls,
    )..where((row) => row.id.equals(recallId))).getSingle();
    return _result(transfer, recall);
  });
}

class _RecallPlan {
  const _RecallPlan({
    required this.allocation,
    required this.line,
    required this.quantity,
    required this.valueCents,
    required this.tracked,
    required this.sourceLayer,
  });

  final WarehouseTransferAllocation allocation;
  final WarehouseTransferLine line;
  final int quantity;
  final int valueCents;
  final bool tracked;
  final ConsignmentInventoryLayer? sourceLayer;
}
