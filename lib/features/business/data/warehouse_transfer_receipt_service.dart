import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

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

class WarehouseTransferReceiptRequestItem {
  const WarehouseTransferReceiptRequestItem({
    required this.allocationId,
    this.acceptedQuantity = 0,
    this.damagedQuantity = 0,
    this.lostQuantity = 0,
  });

  final String allocationId;
  final int acceptedQuantity;
  final int damagedQuantity;
  final int lostQuantity;

  int get totalQuantity => acceptedQuantity + damagedQuantity + lostQuantity;
}

class WarehouseTransferPendingAllocation {
  const WarehouseTransferPendingAllocation({
    required this.allocation,
    required this.line,
    required this.remainingQuantity,
    required this.productName,
    required this.code,
  });

  final WarehouseTransferAllocation allocation;
  final WarehouseTransferLine line;
  final int remainingQuantity;
  final String productName;
  final String code;
}

class WarehouseTransferReceiptResult {
  const WarehouseTransferReceiptResult({
    required this.transfer,
    required this.receipt,
    required this.items,
  });

  final WarehouseTransfer transfer;
  final WarehouseTransferReceipt receipt;
  final List<WarehouseTransferReceiptItem> items;
}

/// Posts one full or partial transfer receipt atomically.
///
/// Accepted enterprise-owned stock debits Inventory (1200), while damaged or
/// lost enterprise stock debits Inventory Shrinkage (5800). Both clear the
/// exact frozen dispatch value from Inventory in Transit (1210). Supplier-owned
/// consignment stock carries zero enterprise GL value and retains its agreement,
/// receipt and custody-layer chain at the destination.
class WarehouseTransferReceiptService {
  WarehouseTransferReceiptService(
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
      throw ArgumentError('A stable UUID receipt key is required');
    }
    return key;
  }

  static String _hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  static int _valueAt(WarehouseTransferAllocation allocation, int quantity) =>
      MeasuredAmount.cents(
        unitCents: allocation.unitCostCents,
        quantity: quantity,
        quantityScale: allocation.quantityScale,
      );

  Future<int> _actor(WarehouseTransfer transfer) async {
    final actor = await authorize(
      TransferDraftAction.receive,
      transfer.sourceWarehouseId,
      transfer.destinationWarehouseId,
    );
    final active =
        await (db.select(
              db.users,
            )..where((user) => user.id.equals(actor) & user.isActive.equals(1)))
            .getSingleOrNull();
    if (active == null) {
      throw StateError('Transfer receipt requires an active user');
    }
    return actor;
  }

  Future<WarehouseTransferReceiptResult> _result(
    WarehouseTransfer transfer,
    WarehouseTransferReceipt receipt,
  ) async {
    if (!receipt.sealed) {
      throw StateError('Transfer receipt is incomplete');
    }
    final items =
        await (db.select(db.warehouseTransferReceiptItems)
              ..where((item) => item.receiptId.equals(receipt.id))
              ..orderBy([(item) => OrderingTerm.asc(item.id)]))
            .get();
    if (items.length != receipt.itemCount) {
      throw StateError('Transfer receipt item count changed');
    }
    return WarehouseTransferReceiptResult(
      transfer: transfer,
      receipt: receipt,
      items: List.unmodifiable(items),
    );
  }

  Future<List<WarehouseTransferPendingAllocation>> pending(
    String transferId,
  ) => db.transaction(() async {
    final transfer = await (db.select(
      db.warehouseTransfers,
    )..where((row) => row.id.equals(transferId))).getSingle();
    await _actor(transfer);
    if (!transfer.sealed ||
        !const {'in_transit', 'partially_received'}.contains(transfer.status)) {
      throw StateError('Only an in-transit transfer can be received');
    }
    final dispatch =
        await (db.select(db.warehouseTransferDispatches)..where(
              (row) =>
                  row.transferId.equals(transfer.id) & row.sealed.equals(true),
            ))
            .getSingle();
    final allocations =
        await (db.select(db.warehouseTransferAllocations)
              ..where((row) => row.dispatchId.equals(dispatch.id))
              ..orderBy([(row) => OrderingTerm.asc(row.sequence)]))
            .get();
    final result = <WarehouseTransferPendingAllocation>[];
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
      final label = await db
          .customSelect(
            '''SELECT p.name,COALESCE(v.sku,v.barcode,p.sku,p.barcode,'') AS code
        FROM product_variants v JOIN products p ON p.id=v.product_id
        WHERE v.id=? AND p.id=?''',
            variables: [
              Variable.withInt(line.variantId),
              Variable.withInt(line.productId),
            ],
          )
          .getSingle();
      result.add(
        WarehouseTransferPendingAllocation(
          allocation: allocation,
          line: line,
          remainingQuantity: remaining,
          productName: label.read<String>('name'),
          code: label.read<String>('code'),
        ),
      );
    }
    return List.unmodifiable(result);
  });

  Future<WarehouseTransferReceiptResult> receive({
    required String transferId,
    required String requestKey,
    required List<WarehouseTransferReceiptRequestItem> items,
    String notes = '',
    DateTime? receivedAt,
  }) => db.transaction(() async {
    final key = _key(requestKey);
    final trimmedNotes = notes.trim();
    if (trimmedNotes.length > 500) {
      throw ArgumentError.value(notes, 'notes', 'Maximum length is 500');
    }
    if (items.isEmpty || items.length > 5000) {
      throw ArgumentError.value(items.length, 'items');
    }
    final allocationIds = <String>{};
    for (final item in items) {
      if (item.allocationId.length != 36 ||
          item.acceptedQuantity < 0 ||
          item.damagedQuantity < 0 ||
          item.lostQuantity < 0 ||
          item.totalQuantity <= 0 ||
          !allocationIds.add(item.allocationId)) {
        throw ArgumentError('Invalid or duplicate transfer receipt item');
      }
    }
    if (items.any(
          (item) => item.damagedQuantity > 0 || item.lostQuantity > 0,
        ) &&
        trimmedNotes.isEmpty) {
      throw ArgumentError('A reason is required for damaged or lost stock');
    }

    var transfer = await (db.select(
      db.warehouseTransfers,
    )..where((row) => row.id.equals(transferId))).getSingle();
    final actor = await _actor(transfer);
    final normalizedItems = [...items]
      ..sort((left, right) => left.allocationId.compareTo(right.allocationId));
    final hash = _hash({
      'version': 1,
      'kind': 'warehouse_transfer_receipt',
      'transfer': transfer.id,
      'actor': actor,
      'notes': trimmedNotes,
      'items': [
        for (final item in normalizedItems)
          {
            'allocation': item.allocationId,
            'accepted': item.acceptedQuantity,
            'damaged': item.damagedQuantity,
            'lost': item.lostQuantity,
          },
      ],
    });

    final replay = await (db.select(
      db.warehouseTransferReceipts,
    )..where((receipt) => receipt.requestKey.equals(key))).getSingleOrNull();
    if (replay != null) {
      if (replay.transferId != transfer.id || replay.requestHash != hash) {
        throw StateError('Receipt request key belongs to another operation');
      }
      return _result(transfer, replay);
    }
    if (!transfer.sealed ||
        !const {'in_transit', 'partially_received'}.contains(transfer.status)) {
      throw StateError('Only an in-transit transfer can be received');
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

    final plans = <_ReceiptPlan>[];
    for (final request in normalizedItems) {
      final allocation =
          await (db.select(db.warehouseTransferAllocations)..where(
                (row) =>
                    row.id.equals(request.allocationId) &
                    row.dispatchId.equals(dispatch.id),
              ))
              .getSingleOrNull();
      if (allocation == null) {
        throw StateError('Receipt allocation does not belong to the transfer');
      }
      final consumedRow = await db
          .customSelect(
            '''SELECT COALESCE(SUM(i.accepted_quantity+i.damaged_quantity+i.lost_quantity),0) AS quantity
               FROM warehouse_transfer_receipt_items i
               JOIN warehouse_transfer_receipts r ON r.id=i.receipt_id
               WHERE i.allocation_id=? AND r.sealed=1''',
            variables: [Variable.withString(allocation.id)],
          )
          .getSingle();
      final previouslyConsumed = consumedRow.read<int>('quantity');
      if (previouslyConsumed < 0 ||
          previouslyConsumed + request.totalQuantity > allocation.quantity) {
        throw StateError('Receipt quantity exceeds the dispatched allocation');
      }
      final line = await (db.select(
        db.warehouseTransferLines,
      )..where((row) => row.id.equals(allocation.lineId))).getSingle();
      final product = await (db.select(
        db.products,
      )..where((row) => row.id.equals(line.productId))).getSingle();
      final tracked =
          product.costingMethod == 'fifo' ||
          product.inventoryTrackingType == 'batch' ||
          product.inventoryTrackingType == 'batch_expiry';
      ProductBatch? sourceBatch;
      if (tracked) {
        final batchId = allocation.sourceBatchId;
        if (batchId == null) {
          throw StateError('Tracked allocation lost its source batch');
        }
        sourceBatch = await (db.select(
          db.productBatches,
        )..where((batch) => batch.id.equals(batchId))).getSingle();
      }
      ConsignmentInventoryLayer? sourceLayer;
      if (allocation.ownerType == 'consignment') {
        final layerId = allocation.sourceConsignmentLayerId;
        if (layerId == null) {
          throw StateError('Consignment allocation lost its source layer');
        }
        sourceLayer = await (db.select(
          db.consignmentInventoryLayers,
        )..where((layer) => layer.id.equals(layerId))).getSingle();
      }

      final acceptedEnd = previouslyConsumed + request.acceptedQuantity;
      final totalEnd = previouslyConsumed + request.totalQuantity;
      final acceptedValue = allocation.ownerType == 'owned'
          ? _valueAt(allocation, acceptedEnd) -
                _valueAt(allocation, previouslyConsumed)
          : 0;
      final varianceValue = allocation.ownerType == 'owned'
          ? _valueAt(allocation, totalEnd) - _valueAt(allocation, acceptedEnd)
          : 0;
      plans.add(
        _ReceiptPlan(
          request: request,
          allocation: allocation,
          line: line,
          tracked: tracked,
          sourceBatch: sourceBatch,
          sourceLayer: sourceLayer,
          acceptedValueCents: acceptedValue,
          varianceValueCents: varianceValue,
        ),
      );
    }

    final acceptedOwnedValue = plans.fold<int>(
      0,
      (total, plan) => total + plan.acceptedValueCents,
    );
    final varianceOwnedValue = plans.fold<int>(
      0,
      (total, plan) => total + plan.varianceValueCents,
    );
    final moment = (receivedAt ?? DateTime.now()).toUtc();
    final receiptId = await db
        .into(db.warehouseTransferReceipts)
        .insert(
          WarehouseTransferReceiptsCompanion.insert(
            transferId: transfer.id,
            requestKey: key,
            requestHash: hash,
            actorId: actor,
            itemCount: plans.length,
            acceptedOwnedValueCents: acceptedOwnedValue,
            varianceOwnedValueCents: varianceOwnedValue,
            destinationInventoryDeltaCents: acceptedOwnedValue,
            notes: Value(trimmedNotes),
            receivedAt: moment,
          ),
        );

    final touchedProducts = <int>{};
    final trackedProducts = <int>{};
    for (final plan in plans) {
      int? destinationBatchId;
      String? destinationLayerId;
      final accepted = plan.request.acceptedQuantity;
      if (accepted > 0) {
        final wac = plan.allocation.ownerType == 'owned' && !plan.tracked
            ? await WacMovementService.capture(
                db.productDao,
                productId: plan.line.productId,
                variantId: plan.line.variantId,
                scope: destination,
              )
            : null;
        await StockService.adjustStock(
          db.productDao,
          productId: plan.line.productId,
          variantId: plan.line.variantId,
          quantity: accepted,
          direction: StockDirection.increase,
          scope: destination,
          origin: InventoryOriginIntent.keyed(
            'transfer_in',
            'transfer_in:$receiptId:${plan.allocation.id}',
            reference: 'transfer_out:${plan.allocation.id}',
            referenceWarehouse: source.warehouseId,
          ),
        );
        if (wac != null) {
          await WacMovementService.applyInbound(
            db.productDao,
            snapshot: wac,
            addedQty: accepted,
            inboundUnitCostCents: plan.allocation.unitCostCents,
          );
        }
        if (plan.allocation.ownerType == 'consignment') {
          final changed = await db.customUpdate(
            'UPDATE business_warehouse_stocks SET '
            'supplier_owned_quantity=supplier_owned_quantity+?,updated_at=? '
            'WHERE warehouse_id=? AND variant_id=?',
            variables: [
              Variable.withInt(accepted),
              Variable.withString(moment.toIso8601String()),
              Variable.withString(destination.warehouseId),
              Variable.withInt(plan.line.variantId),
            ],
            updates: {db.businessWarehouseStocks},
          );
          if (changed != 1) {
            throw StateError('Destination supplier-owned balance is missing');
          }
        }
        if (plan.tracked) {
          destinationBatchId = await BatchService.createBatchFromTransfer(
            db.productDao,
            productId: plan.line.productId,
            variantId: plan.line.variantId,
            transferAllocationId: plan.allocation.id,
            originBatch: plan.sourceBatch!,
            receiptId: receiptId,
            quantity: accepted,
            unitCostCents: plan.allocation.unitCostCents,
            receivedDate: moment,
            scope: destination,
          );
          trackedProducts.add(plan.line.productId);
        }
        final sourceLayer = plan.sourceLayer;
        if (sourceLayer != null) {
          destinationLayerId = const Uuid().v4();
          await db
              .into(db.consignmentInventoryLayers)
              .insert(
                ConsignmentInventoryLayersCompanion.insert(
                  id: destinationLayerId,
                  receiptItemId: sourceLayer.receiptItemId,
                  originLayerId: Value(sourceLayer.id),
                  transferAllocationId: Value(plan.allocation.id),
                  warehouseId: destination.warehouseId,
                  supplierId: sourceLayer.supplierId,
                  agreementId: sourceLayer.agreementId,
                  productId: sourceLayer.productId,
                  variantId: sourceLayer.variantId,
                  batchId: Value(destinationBatchId),
                  receivedQuantity: accepted,
                  remainingQuantity: accepted,
                  quantityScale: sourceLayer.quantityScale,
                  measurementType: sourceLayer.measurementType,
                  settlementBasis: sourceLayer.settlementBasis,
                  unitCostCents: Value(sourceLayer.unitCostCents),
                  supplierShareBps: Value(sourceLayer.supplierShareBps),
                  includeLineDiscount: sourceLayer.includeLineDiscount,
                  includeInvoiceDiscount: sourceLayer.includeInvoiceDiscount,
                  includeSalesTax: sourceLayer.includeSalesTax,
                  receivedAt: moment,
                ),
              );
        }
        touchedProducts.add(plan.line.productId);
      }

      await db
          .into(db.warehouseTransferReceiptItems)
          .insert(
            WarehouseTransferReceiptItemsCompanion.insert(
              receiptId: receiptId,
              allocationId: plan.allocation.id,
              acceptedQuantity: Value(accepted),
              damagedQuantity: Value(plan.request.damagedQuantity),
              lostQuantity: Value(plan.request.lostQuantity),
              acceptedValueCents: Value(plan.acceptedValueCents),
              varianceValueCents: Value(plan.varianceValueCents),
              destinationBatchId: Value(destinationBatchId),
              destinationConsignmentLayerId: Value(destinationLayerId),
            ),
          );
    }

    for (final productId in touchedProducts) {
      await StockService.syncProductStockFromVariants(
        db.productDao,
        productId: productId,
        scope: destination,
      );
      if (trackedProducts.contains(productId)) {
        await WarehouseInventoryReader.assertBatches(
          db.productDao,
          scope: destination,
          productId: productId,
        );
      }
    }

    int? journalId;
    final clearedOwnedValue = acceptedOwnedValue + varianceOwnedValue;
    if (clearedOwnedValue > 0) {
      final accounts = {
        for (final account
            in await (db.select(db.accounts)..where(
                  (row) => row.accountCode.isIn(const ['1200', '1210', '5800']),
                ))
                .get())
          account.accountCode: account,
      };
      if (!accounts.keys.toSet().containsAll({'1200', '1210', '5800'})) {
        throw StateError('Required transfer receipt accounts are missing');
      }
      journalId = await accounting.createJournalEntry(
        entryData: JournalEntryData(
          description: 'Warehouse transfer receipt ${transfer.id}',
          entryDate: moment,
          entryType: 'warehouse_transfer_receipt',
          sourceTable: 'warehouse_transfer_receipts',
          sourceId: receiptId,
          autoPost: true,
          lines: [
            if (acceptedOwnedValue > 0)
              JournalEntryLineData(
                accountId: accounts['1200']!.id,
                debitCents: acceptedOwnedValue,
                creditCents: 0,
                currencyId: transfer.currencyId,
              ),
            if (varianceOwnedValue > 0)
              JournalEntryLineData(
                accountId: accounts['5800']!.id,
                debitCents: varianceOwnedValue,
                creditCents: 0,
                currencyId: transfer.currencyId,
              ),
            JournalEntryLineData(
              accountId: accounts['1210']!.id,
              debitCents: 0,
              creditCents: clearedOwnedValue,
              currencyId: transfer.currencyId,
            ),
          ],
        ),
        userId: actor,
      );
    }

    await (db.update(
      db.warehouseTransferReceipts,
    )..where((receipt) => receipt.id.equals(receiptId))).write(
      WarehouseTransferReceiptsCompanion(
        journalEntryId: Value(journalId),
        sealed: const Value(true),
      ),
    );

    final outstanding = await db
        .customSelect(
          '''SELECT 1 AS pending FROM warehouse_transfer_allocations a
             WHERE a.dispatch_id=? AND a.quantity>COALESCE((
               SELECT SUM(i.accepted_quantity+i.damaged_quantity+i.lost_quantity)
               FROM warehouse_transfer_receipt_items i
               JOIN warehouse_transfer_receipts r ON r.id=i.receipt_id
               WHERE i.allocation_id=a.id AND r.sealed=1
             ),0) LIMIT 1''',
          variables: [Variable.withInt(dispatch.id)],
        )
        .getSingleOrNull();
    if (outstanding == null) {
      await db
          .into(db.warehouseTransferEvents)
          .insert(
            WarehouseTransferEventsCompanion.insert(
              id: const Uuid().v4(),
              transferId: transfer.id,
              kind: 'completed',
              requestKey: key,
              requestHash: hash,
              actorId: actor,
            ),
          );
      final changed =
          await (db.update(db.warehouseTransfers)..where(
                (row) =>
                    row.id.equals(transfer.id) &
                    row.status.isIn(const ['in_transit', 'partially_received']),
              ))
              .write(
                const WarehouseTransfersCompanion(status: Value('completed')),
              );
      if (changed != 1) {
        throw StateError('Transfer state changed during receipt');
      }
    } else if (transfer.status == 'in_transit') {
      final changed =
          await (db.update(db.warehouseTransfers)..where(
                (row) =>
                    row.id.equals(transfer.id) &
                    row.status.equals('in_transit'),
              ))
              .write(
                const WarehouseTransfersCompanion(
                  status: Value('partially_received'),
                ),
              );
      if (changed != 1) {
        throw StateError('Transfer state changed during partial receipt');
      }
    }

    transfer = await (db.select(
      db.warehouseTransfers,
    )..where((row) => row.id.equals(transfer.id))).getSingle();
    final receipt = await (db.select(
      db.warehouseTransferReceipts,
    )..where((row) => row.id.equals(receiptId))).getSingle();
    return _result(transfer, receipt);
  });
}

class _ReceiptPlan {
  const _ReceiptPlan({
    required this.request,
    required this.allocation,
    required this.line,
    required this.tracked,
    required this.sourceBatch,
    required this.sourceLayer,
    required this.acceptedValueCents,
    required this.varianceValueCents,
  });

  final WarehouseTransferReceiptRequestItem request;
  final WarehouseTransferAllocation allocation;
  final WarehouseTransferLine line;
  final bool tracked;
  final ProductBatch? sourceBatch;
  final ConsignmentInventoryLayer? sourceLayer;
  final int acceptedValueCents;
  final int varianceValueCents;
}
