import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/measurement/measurement.dart';
import '../../../core/services/batch_service.dart';
import '../../../core/services/business/warehouse_batch_scope.dart';
import '../../../core/services/business/warehouse_inventory_reader.dart';
import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../../core/services/business/warehouse_transfer_preflight.dart';
import '../../../core/services/stock_service.dart';
import '../../../core/services/sync/offline_sync_event_store.dart';
import '../../../core/services/sync/sync_entity_identity_store.dart';
import '../../../core/services/sync/warehouse_transfer_sync_contract.dart';
import '../../accounting/data/repositories/accounting_repository.dart';
import '../../accounting/domain/models/journal_entry_data.dart';
import 'warehouse_transfer_repository.dart';

class WarehouseTransferDispatchResult {
  const WarehouseTransferDispatchResult({
    required this.transfer,
    required this.dispatch,
    required this.allocations,
  });

  final WarehouseTransfer transfer;
  final WarehouseTransferDispatch dispatch;
  final List<WarehouseTransferAllocation> allocations;
}

/// Atomically freezes the picked ownership layers, removes source stock and
/// moves enterprise-owned value from Inventory to Inventory in Transit.
class WarehouseTransferDispatchService {
  WarehouseTransferDispatchService(
    this.db, {
    required this.preflight,
    required this.authorize,
    AccountingRepository? accounting,
    OfflineSyncEventStore? syncEvents,
    SyncEntityIdentityStore? syncIdentities,
  }) : accounting = accounting ?? AccountingRepository(db),
       syncEvents = syncEvents ?? OfflineSyncEventStore(db),
       syncIdentities = syncIdentities ?? SyncEntityIdentityStore(db);

  final AppDatabase db;
  final WarehouseTransferPreflight preflight;
  final AuthorizeTransferDraft authorize;
  final AccountingRepository accounting;
  final OfflineSyncEventStore syncEvents;
  final SyncEntityIdentityStore syncIdentities;

  static String _key(String input) {
    final key = input.trim().toLowerCase();
    if (!RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    ).hasMatch(key)) {
      throw ArgumentError('A stable UUID dispatch key is required');
    }
    return key;
  }

  static String _hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  Future<int> _actor(WarehouseTransfer transfer) async {
    final actor = await authorize(
      TransferDraftAction.dispatch,
      transfer.sourceWarehouseId,
      transfer.destinationWarehouseId,
    );
    final active =
        await (db.select(db.users)
              ..where((u) => u.id.equals(actor) & u.isActive.equals(1)))
            .getSingleOrNull();
    if (active == null) {
      throw StateError('Transfer dispatch requires an active user');
    }
    return actor;
  }

  Future<WarehouseTransferDispatchResult> _result(
    WarehouseTransfer transfer,
    WarehouseTransferDispatch dispatch,
  ) async {
    if (!dispatch.sealed) {
      throw StateError('Transfer dispatch is incomplete');
    }
    final allocations =
        await (db.select(db.warehouseTransferAllocations)
              ..where((a) => a.dispatchId.equals(dispatch.id))
              ..orderBy([(a) => OrderingTerm.asc(a.sequence)]))
            .get();
    if (allocations.length != dispatch.allocationCount) {
      throw StateError('Transfer allocation count changed');
    }
    return WarehouseTransferDispatchResult(
      transfer: transfer,
      dispatch: dispatch,
      allocations: List.unmodifiable(allocations),
    );
  }

  Future<WarehouseTransferDispatchResult> dispatch({
    required String transferId,
    required String requestKey,
    DateTime? dispatchedAt,
  }) => syncEvents.transaction((sync) async {
    final key = _key(requestKey);
    var transfer = await (db.select(
      db.warehouseTransfers,
    )..where((t) => t.id.equals(transferId))).getSingle();
    final actor = await _actor(transfer);
    final hash = _hash({
      'version': 1,
      'kind': 'warehouse_transfer_dispatch',
      'transfer': transfer.id,
      'actor': actor,
    });

    final replay = await (db.select(
      db.warehouseTransferDispatches,
    )..where((d) => d.requestKey.equals(key))).getSingleOrNull();
    if (replay != null) {
      if (replay.transferId != transfer.id || replay.requestHash != hash) {
        throw StateError('Dispatch request key belongs to another operation');
      }
      final replayed = await _result(transfer, replay);
      await _appendSyncEvent(sync, replayed);
      return replayed;
    }
    final existing = await (db.select(
      db.warehouseTransferDispatches,
    )..where((d) => d.transferId.equals(transfer.id))).getSingleOrNull();
    if (existing != null) {
      throw StateError('Transfer was already dispatched with another key');
    }
    if (!transfer.sealed || transfer.status != 'draft') {
      throw StateError('Only a sealed draft can be dispatched');
    }

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

    final lines =
        await (db.select(db.warehouseTransferLines)
              ..where((l) => l.transferId.equals(transfer.id))
              ..orderBy([(l) => OrderingTerm.asc(l.variantId)]))
            .get();
    if (lines.length != transfer.lineCount) {
      throw StateError('Transfer line count changed');
    }

    final preview = await preflight.preview(
      source: source,
      destination: destination,
      lines: [
        for (final line in lines)
          WarehouseTransferRequestLine(
            productId: line.productId,
            variantId: line.variantId,
            quantity: line.quantity,
          ),
      ],
    );
    if (preview.currencyId != transfer.currencyId) {
      throw StateError('Transfer currency changed');
    }
    for (final line in lines) {
      final current = preview.lines.singleWhere(
        (item) => item.variantId == line.variantId,
      );
      if (current.quantityScale != line.quantityScale ||
          current.measurementType != line.measurementType ||
          current.request.quantity != line.quantity) {
        throw StateError('Transfer units changed; review the draft again');
      }
    }

    final plans = <_DispatchAllocationPlan>[];
    for (final line in lines) {
      plans.addAll(await _planLine(line, source));
    }
    if (plans.isEmpty || plans.length > 5000) {
      throw StateError('Transfer dispatch allocation count is invalid');
    }
    final ownedValue = plans
        .where((plan) => !plan.isConsignment)
        .fold<int>(0, (sum, plan) => sum + plan.valueCents);
    final moment = (dispatchedAt ?? DateTime.now()).toUtc();

    final dispatchId = await db
        .into(db.warehouseTransferDispatches)
        .insert(
          WarehouseTransferDispatchesCompanion.insert(
            transferId: transfer.id,
            requestKey: key,
            requestHash: hash,
            actorId: actor,
            allocationCount: plans.length,
            ownedValueCents: ownedValue,
            dispatchedAt: moment,
          ),
        );

    for (var index = 0; index < plans.length; index++) {
      final plan = plans[index];
      await db
          .into(db.warehouseTransferAllocations)
          .insert(
            WarehouseTransferAllocationsCompanion.insert(
              id: plan.id,
              dispatchId: dispatchId,
              lineId: plan.line.id,
              sequence: index + 1,
              ownerType: plan.isConsignment ? 'consignment' : 'owned',
              quantity: plan.quantity,
              quantityScale: plan.line.quantityScale,
              measurementType: plan.line.measurementType,
              unitCostCents: plan.unitCostCents,
              valueCents: plan.valueCents,
              sourceBatchId: Value(plan.sourceBatchId),
              sourceConsignmentLayerId: Value(plan.consignmentLayer?.id),
              supplierId: Value(plan.consignmentLayer?.supplierId),
              agreementId: Value(plan.consignmentLayer?.agreementId),
              manufacturerLotNumber: Value(plan.manufacturerLotNumber),
              expiryDate: Value(plan.expiryDate),
            ),
          );
    }

    final touchedProducts = <int>{};
    final trackedProducts = <int>{};
    for (final plan in plans) {
      await _removeSource(plan, source);
      touchedProducts.add(plan.line.productId);
      if (plan.tracked) trackedProducts.add(plan.line.productId);
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
      final inventory = await (db.select(
        db.accounts,
      )..where((a) => a.accountCode.equals('1200'))).getSingleOrNull();
      final inTransit = await (db.select(
        db.accounts,
      )..where((a) => a.accountCode.equals('1210'))).getSingleOrNull();
      if (inventory == null || inTransit == null) {
        throw StateError('Required transfer inventory accounts are missing');
      }
      journalId = await accounting.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Warehouse transfer dispatch ${transfer.id}',
          debitAccountId: inTransit.id,
          creditAccountId: inventory.id,
          amountCents: ownedValue,
          currencyId: transfer.currencyId,
          entryDate: moment,
          entryType: 'warehouse_transfer_dispatch',
          sourceTable: 'warehouse_transfer_dispatches',
          sourceId: dispatchId,
        ),
        userId: actor,
      );
    }

    await (db.update(
      db.warehouseTransferDispatches,
    )..where((d) => d.id.equals(dispatchId))).write(
      WarehouseTransferDispatchesCompanion(
        journalEntryId: Value(journalId),
        sealed: const Value(true),
      ),
    );
    await db
        .into(db.warehouseTransferEvents)
        .insert(
          WarehouseTransferEventsCompanion.insert(
            id: const Uuid().v4(),
            transferId: transfer.id,
            kind: 'dispatched',
            requestKey: key,
            requestHash: hash,
            actorId: actor,
          ),
        );
    final changed =
        await (db.update(db.warehouseTransfers)..where(
              (t) => t.id.equals(transfer.id) & t.status.equals('draft'),
            ))
            .write(
              const WarehouseTransfersCompanion(status: Value('in_transit')),
            );
    if (changed != 1) {
      throw StateError('Transfer state changed during dispatch');
    }

    transfer = await (db.select(
      db.warehouseTransfers,
    )..where((t) => t.id.equals(transfer.id))).getSingle();
    final dispatch = await (db.select(
      db.warehouseTransferDispatches,
    )..where((d) => d.id.equals(dispatchId))).getSingle();
    final result = await _result(transfer, dispatch);
    await _appendSyncEvent(sync, result);
    return result;
  });

  Future<void> _appendSyncEvent(
    OfflineSyncTransaction sync,
    WarehouseTransferDispatchResult result,
  ) async {
    if (!await sync.isWriterRecordingEnabled()) return;
    final payload =
        await WarehouseTransferSyncContractBuilder(
          db,
          syncIdentities,
        ).buildDispatch(
          transfer: result.transfer,
          dispatch: result.dispatch,
          allocations: result.allocations,
        );
    await sync.appendOnce(
      producerKey: 'warehouse_transfer:${result.transfer.id}:dispatched',
      eventType: 'warehouse_transfer.dispatched.v1',
      aggregateType: 'warehouse_transfer',
      aggregateId: result.transfer.id,
      payload: payload,
      contractVersion: 1,
      occurredAt: result.dispatch.dispatchedAt,
    );
  }

  Future<List<_DispatchAllocationPlan>> _planLine(
    WarehouseTransferLine line,
    WarehouseOperationScope source,
  ) async {
    final product = await (db.select(
      db.products,
    )..where((p) => p.id.equals(line.productId))).getSingle();
    final tracked =
        product.costingMethod == 'fifo' ||
        product.inventoryTrackingType == 'batch' ||
        product.inventoryTrackingType == 'batch_expiry';
    return tracked
        ? _planTrackedLine(line, source)
        : _planStandardLine(line, source);
  }

  Future<List<_DispatchAllocationPlan>> _planStandardLine(
    WarehouseTransferLine line,
    WarehouseOperationScope source,
  ) async {
    final stock = await db
        .customSelect(
          'SELECT quantity,supplier_owned_quantity,unit_cost_cents '
          'FROM business_warehouse_stocks WHERE warehouse_id=? AND variant_id=?',
          variables: [
            Variable.withString(source.warehouseId),
            Variable.withInt(line.variantId),
          ],
        )
        .getSingle();
    var remaining = line.quantity;
    final enterpriseAvailable =
        stock.read<int>('quantity') -
        stock.read<int>('supplier_owned_quantity');
    final enterpriseTake = math.min(remaining, enterpriseAvailable);
    final result = <_DispatchAllocationPlan>[];
    if (enterpriseTake > 0) {
      final cost = stock.read<int>('unit_cost_cents');
      final before = MeasuredAmount.cents(
        unitCents: cost,
        quantity: enterpriseAvailable,
        quantityScale: line.quantityScale,
      );
      final after = MeasuredAmount.cents(
        unitCents: cost,
        quantity: enterpriseAvailable - enterpriseTake,
        quantityScale: line.quantityScale,
      );
      result.add(
        _DispatchAllocationPlan(
          id: const Uuid().v4(),
          line: line,
          quantity: enterpriseTake,
          unitCostCents: cost,
          valueCents: before - after,
          tracked: false,
        ),
      );
      remaining -= enterpriseTake;
    }
    if (remaining == 0) return result;

    final layers =
        await (db.select(db.consignmentInventoryLayers)
              ..where(
                (layer) =>
                    layer.warehouseId.equals(source.warehouseId) &
                    layer.productId.equals(line.productId) &
                    layer.variantId.equals(line.variantId) &
                    layer.status.equals('open') &
                    layer.remainingQuantity.isBiggerThanValue(0),
              )
              ..orderBy([
                (layer) => OrderingTerm.asc(layer.receivedAt),
                (layer) => OrderingTerm.asc(layer.id),
              ]))
            .get();
    for (final layer in layers) {
      if (remaining == 0) break;
      final take = math.min(remaining, layer.remainingQuantity);
      result.add(
        _DispatchAllocationPlan(
          id: const Uuid().v4(),
          line: line,
          quantity: take,
          unitCostCents: layer.unitCostCents ?? 0,
          valueCents: 0,
          tracked: false,
          consignmentLayer: layer,
          sourceOriginReference: 'consignment_receipt:${layer.receiptItemId}',
        ),
      );
      remaining -= take;
    }
    if (remaining != 0) {
      throw StateError('Transfer source ownership is insufficient');
    }
    return result;
  }

  Future<List<_DispatchAllocationPlan>> _planTrackedLine(
    WarehouseTransferLine line,
    WarehouseOperationScope source,
  ) async {
    final rows = await db
        .customSelect(
          '''SELECT pb.id,pb.remaining_quantity,pb.unit_cost_cents,
                    pb.manufacturer_lot_number,pb.expiry_date,
                    l.id AS layer_id
             FROM product_batches pb
             LEFT JOIN consignment_inventory_layers l
               ON l.batch_id=pb.id AND l.warehouse_id=? AND l.status='open'
             WHERE pb.product_id=? AND pb.variant_id=? AND pb.is_active=1
               AND pb.remaining_quantity>0
               AND ${WarehouseBatchScope.operationPredicate('pb')}
             ORDER BY (pb.expiry_date IS NULL),pb.expiry_date,pb.received_date,pb.id''',
          variables: [
            Variable.withString(source.warehouseId),
            Variable.withInt(line.productId),
            Variable.withInt(line.variantId),
            ...WarehouseBatchScope.operationVariables(source),
          ],
        )
        .get();
    var remaining = line.quantity;
    final result = <_DispatchAllocationPlan>[];
    for (final row in rows) {
      if (remaining == 0) break;
      final available = row.read<int>('remaining_quantity');
      final take = math.min(remaining, available);
      final layerId = row.readNullable<String>('layer_id');
      final layer = layerId == null
          ? null
          : await (db.select(
              db.consignmentInventoryLayers,
            )..where((item) => item.id.equals(layerId))).getSingle();
      if (layer != null && layer.remainingQuantity != available) {
        throw StateError('Consignment batch and ownership layer differ');
      }
      final cost = row.read<int>('unit_cost_cents');
      final value = layer == null
          ? MeasuredAmount.cents(
                  unitCents: cost,
                  quantity: available,
                  quantityScale: line.quantityScale,
                ) -
                MeasuredAmount.cents(
                  unitCents: cost,
                  quantity: available - take,
                  quantityScale: line.quantityScale,
                )
          : 0;
      result.add(
        _DispatchAllocationPlan(
          id: const Uuid().v4(),
          line: line,
          quantity: take,
          unitCostCents: cost,
          valueCents: value,
          tracked: true,
          sourceBatchId: row.read<int>('id'),
          consignmentLayer: layer,
          manufacturerLotNumber: row.readNullable<String>(
            'manufacturer_lot_number',
          ),
          expiryDate: row.readNullable<DateTime>('expiry_date'),
        ),
      );
      remaining -= take;
    }
    if (remaining != 0) {
      throw StateError('Tracked transfer source is insufficient');
    }
    return result;
  }

  Future<void> _removeSource(
    _DispatchAllocationPlan plan,
    WarehouseOperationScope source,
  ) async {
    final layer = plan.consignmentLayer;
    if (layer != null) {
      final layerChanged = await db.customUpdate(
        'UPDATE consignment_inventory_layers SET '
        'remaining_quantity=remaining_quantity-?,'
        "status=CASE WHEN remaining_quantity-?=0 THEN 'exhausted' ELSE 'open' END,"
        'updated_at=? WHERE id=? AND status=? AND remaining_quantity>=?',
        variables: [
          Variable.withInt(plan.quantity),
          Variable.withInt(plan.quantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(layer.id),
          Variable.withString('open'),
          Variable.withInt(plan.quantity),
        ],
        updates: {db.consignmentInventoryLayers},
      );
      if (layerChanged != 1) {
        throw StateError('Consignment transfer source changed');
      }
      final ownershipChanged = await db.customUpdate(
        'UPDATE business_warehouse_stocks SET '
        'supplier_owned_quantity=supplier_owned_quantity-?,updated_at=? '
        'WHERE warehouse_id=? AND variant_id=? '
        'AND supplier_owned_quantity>=?',
        variables: [
          Variable.withInt(plan.quantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(source.warehouseId),
          Variable.withInt(plan.line.variantId),
          Variable.withInt(plan.quantity),
        ],
        updates: {db.businessWarehouseStocks},
      );
      if (ownershipChanged != 1) {
        throw StateError('Supplier-owned transfer balance changed');
      }
    }

    await StockService.adjustStock(
      db.productDao,
      productId: plan.line.productId,
      variantId: plan.line.variantId,
      quantity: plan.quantity,
      direction: StockDirection.decrease,
      scope: source,
      origin: InventoryOriginIntent.keyed(
        'transfer_out',
        'transfer_out:${plan.id}',
        requiredSourceReference: plan.sourceOriginReference,
        excludedSourceKind: layer == null && !plan.tracked
            ? 'consignment_receipt'
            : null,
      ),
    );

    if (plan.sourceBatchId != null) {
      final consumed = await BatchService.consumeFifo(
        db.productDao,
        productId: plan.line.productId,
        variantId: plan.line.variantId,
        quantity: plan.quantity,
        consumptionType: 'warehouse_transfer_dispatch',
        requiredBatchId: plan.sourceBatchId,
        requiredSupplierId: layer?.supplierId,
        transferAllocationId: plan.id,
        notes: 'Transfer allocation ${plan.id}',
        scope: source,
      );
      if (consumed.length != 1 ||
          consumed.single.quantity != plan.quantity ||
          consumed.single.batchId != plan.sourceBatchId) {
        throw StateError('Transfer batch consumption is incomplete');
      }
    }
  }
}

class _DispatchAllocationPlan {
  const _DispatchAllocationPlan({
    required this.id,
    required this.line,
    required this.quantity,
    required this.unitCostCents,
    required this.valueCents,
    required this.tracked,
    this.sourceBatchId,
    this.consignmentLayer,
    this.sourceOriginReference,
    this.manufacturerLotNumber,
    this.expiryDate,
  });

  final String id;
  final WarehouseTransferLine line;
  final int quantity;
  final int unitCostCents;
  final int valueCents;
  final bool tracked;
  final int? sourceBatchId;
  final ConsignmentInventoryLayer? consignmentLayer;
  final String? sourceOriginReference;
  final String? manufacturerLotNumber;
  final DateTime? expiryDate;

  bool get isConsignment => consignmentLayer != null;
}
