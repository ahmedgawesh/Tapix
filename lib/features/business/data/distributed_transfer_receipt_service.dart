import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/measurement/measurement.dart';
import '../../../core/services/batch_service.dart';
import '../../../core/services/business/warehouse_inventory_reader.dart';
import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../../core/services/inventory/supplier_product_identity_service.dart';
import '../../../core/services/inventory/wac_movement_service.dart';
import '../../../core/services/stock_service.dart';
import '../../../core/services/sync/offline_sync_event_store.dart';
import '../../../core/services/sync/sync_entity_identity_store.dart';
import '../../accounting/data/repositories/accounting_repository.dart';
import '../../accounting/domain/models/journal_entry_data.dart';
import '../../consignment/data/consignment_agreement_service.dart';
import '../../consignment/data/consignment_custody_service.dart';
import '../../consignment/data/consignment_receipt_service.dart';

class DistributedTransferReceiptItemRequest {
  const DistributedTransferReceiptItemRequest({
    required this.allocationId,
    this.acceptedQuantity = 0,
    this.damagedQuantity = 0,
    this.lostQuantity = 0,
    this.varianceResponsibility,
    this.liabilityUnitCents,
  });

  final String allocationId;
  final int acceptedQuantity;
  final int damagedQuantity;
  final int lostQuantity;
  final String? varianceResponsibility;
  final int? liabilityUnitCents;

  int get totalQuantity => acceptedQuantity + damagedQuantity + lostQuantity;
}

class DistributedTransferPendingAllocation {
  const DistributedTransferPendingAllocation({
    required this.allocationId,
    required this.productName,
    required this.code,
    required this.ownerType,
    required this.quantityScale,
    required this.measurementType,
    required this.remainingQuantity,
  });

  final String allocationId;
  final String productName;
  final String code;
  final String ownerType;
  final int quantityScale;
  final String measurementType;
  final int remainingQuantity;
}

class DistributedTransferReceiptResult {
  const DistributedTransferReceiptResult({
    required this.receiptId,
    required this.transferId,
    required this.completed,
    required this.acceptedOwnedValueMinor,
    required this.varianceOwnedValueMinor,
  });

  final String receiptId;
  final String transferId;
  final bool completed;
  final int acceptedOwnedValueMinor;
  final int varianceOwnedValueMinor;
}

class DistributedInboundDocument {
  const DistributedInboundDocument({
    required this.transferId,
    required this.sourceWarehouseId,
    required this.destinationWarehouseId,
    required this.status,
    required this.lineCount,
  });

  final String transferId;
  final String sourceWarehouseId;
  final String destinationWarehouseId;
  final String status;
  final int lineCount;
}

/// Posts the destination-owned half of a transfer whose dispatch was authored
/// by another branch database. The dispatch remains immutable evidence; this
/// service is the only operation that may increase destination stock.
class DistributedTransferReceiptService {
  DistributedTransferReceiptService(
    this.db, {
    required this.authorizeWarehouse,
    AccountingRepository? accounting,
    OfflineSyncEventStore? syncEvents,
    SyncEntityIdentityStore? syncIdentities,
    this.consignmentAgreements,
    this.consignmentReceipts,
    this.consignmentCustody,
  }) : accounting = accounting ?? AccountingRepository(db),
       syncEvents = syncEvents ?? OfflineSyncEventStore(db),
       syncIdentities = syncIdentities ?? SyncEntityIdentityStore(db);

  final AppDatabase db;
  final Future<int> Function(String warehouseId) authorizeWarehouse;
  final AccountingRepository accounting;
  final OfflineSyncEventStore syncEvents;
  final SyncEntityIdentityStore syncIdentities;
  final ConsignmentAgreementService? consignmentAgreements;
  final ConsignmentReceiptService? consignmentReceipts;
  final ConsignmentCustodyService? consignmentCustody;

  static String _uuidKey(String value, String name) {
    final result = value.trim().toLowerCase();
    if (!Uuid.isValidUUID(fromString: result)) {
      throw ArgumentError.value(value, name, 'A stable UUID is required');
    }
    return result;
  }

  static String _hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  static int _valueAt(_Allocation allocation, int quantity) =>
      MeasuredAmount.cents(
        unitCents: allocation.unitCostMinor,
        quantity: quantity,
        quantityScale: allocation.quantityScale,
      );

  Future<bool> owns(String transferId) async =>
      await db
          .customSelect(
            'SELECT 1 AS found FROM distributed_transfer_inbound_dispatches '
            'WHERE transfer_id=?',
            variables: [Variable.withString(transferId)],
          )
          .getSingleOrNull() !=
      null;

  Future<List<DistributedInboundDocument>> documents(
    Set<String> statuses, {
    int limit = 100,
  }) async {
    const valid = {
      'in_transit',
      'partially_received',
      'completed',
      'recalled',
      'conflict',
    };
    if (statuses.isEmpty ||
        !valid.containsAll(statuses) ||
        limit < 1 ||
        limit > 500) {
      throw ArgumentError('Invalid distributed inbound filter');
    }
    final lifecycle = <String>{
      for (final status in statuses)
        switch (status) {
          'in_transit' => 'awaiting_receipt',
          _ => status,
        },
    };
    final marks = List.filled(lifecycle.length, '?').join(',');
    final rows = await db
        .customSelect(
          'SELECT transfer_id,source_warehouse_id,destination_warehouse_id,'
          'lifecycle_state,allocation_count '
          'FROM distributed_transfer_inbound_dispatches '
          'WHERE lifecycle_state IN ($marks) ORDER BY dispatched_at DESC LIMIT ?',
          variables: [
            ...lifecycle.map(Variable.withString),
            Variable.withInt(limit),
          ],
        )
        .get();
    return List.unmodifiable(
      rows.map(
        (row) => DistributedInboundDocument(
          transferId: row.read<String>('transfer_id'),
          sourceWarehouseId: row.read<String>('source_warehouse_id'),
          destinationWarehouseId: row.read<String>('destination_warehouse_id'),
          status: row.read<String>('lifecycle_state') == 'awaiting_receipt'
              ? 'in_transit'
              : row.read<String>('lifecycle_state'),
          lineCount: row.read<int>('allocation_count'),
        ),
      ),
    );
  }

  Future<List<DistributedTransferPendingAllocation>> pending(
    String transferId,
  ) => db.transaction(() async {
    final dispatch = await _dispatch(_uuidKey(transferId, 'transferId'));
    await authorizeWarehouse(dispatch.destinationWarehouseId);
    if (dispatch.catalogueState != 'ready' ||
        !const {
          'awaiting_receipt',
          'partially_received',
        }.contains(dispatch.lifecycleState)) {
      return const [];
    }
    final allocations = await _allocations(dispatch.transferId);
    final result = <DistributedTransferPendingAllocation>[];
    for (final allocation in allocations) {
      final consumed = await _consumed(allocation.id);
      final remaining = allocation.quantity - consumed;
      if (remaining <= 0) continue;
      final local = await _localProduct(allocation);
      result.add(
        DistributedTransferPendingAllocation(
          allocationId: allocation.id,
          productName: local.name,
          code: local.code,
          ownerType: allocation.ownerType,
          quantityScale: allocation.quantityScale,
          measurementType: allocation.measurementType,
          remainingQuantity: remaining,
        ),
      );
    }
    return List.unmodifiable(result);
  });

  Future<DistributedTransferReceiptResult> receive({
    required String transferId,
    required String requestKey,
    required List<DistributedTransferReceiptItemRequest> items,
    String notes = '',
    DateTime? receivedAt,
  }) => syncEvents.transaction((sync) async {
    final transfer = _uuidKey(transferId, 'transferId');
    final key = _uuidKey(requestKey, 'requestKey');
    final reason = notes.trim();
    if (reason.length > 500 || items.isEmpty || items.length > 5000) {
      throw ArgumentError('Invalid distributed transfer receipt');
    }
    final ids = <String>{};
    for (final item in items) {
      _uuidKey(item.allocationId, 'allocationId');
      if (item.acceptedQuantity < 0 ||
          item.damagedQuantity < 0 ||
          item.lostQuantity < 0 ||
          item.totalQuantity <= 0 ||
          !ids.add(item.allocationId)) {
        throw ArgumentError('Invalid or duplicate receipt allocation');
      }
      final hasVariance = item.damagedQuantity > 0 || item.lostQuantity > 0;
      if (hasVariance &&
          item.varianceResponsibility != null &&
          !const {
            'supplier',
            'company',
          }.contains(item.varianceResponsibility)) {
        throw ArgumentError('Invalid variance responsibility');
      }
      if (item.liabilityUnitCents != null && item.liabilityUnitCents! <= 0) {
        throw ArgumentError('Invalid variance liability cost');
      }
    }
    if (items.any(
          (item) => item.damagedQuantity > 0 || item.lostQuantity > 0,
        ) &&
        reason.isEmpty) {
      throw ArgumentError('A reason is required for damaged or lost stock');
    }

    final dispatch = await _dispatch(transfer);
    final actor = await authorizeWarehouse(dispatch.destinationWarehouseId);
    final normalized = [...items]
      ..sort((a, b) => a.allocationId.compareTo(b.allocationId));
    final requestHash = _hash({
      'version': 1,
      'kind': 'distributed_transfer_receipt',
      'transferId': transfer,
      'actorId': actor,
      'notes': reason,
      'items': [
        for (final item in normalized)
          {
            'allocationId': item.allocationId,
            'accepted': item.acceptedQuantity,
            'damaged': item.damagedQuantity,
            'lost': item.lostQuantity,
            'varianceResponsibility': item.varianceResponsibility,
            'liabilityUnitCents': item.liabilityUnitCents,
          },
      ],
    });
    final replay = await db
        .customSelect(
          'SELECT * FROM distributed_transfer_inbound_receipts WHERE request_key=?',
          variables: [Variable.withString(key)],
        )
        .getSingleOrNull();
    if (replay != null) {
      if (replay.read<String>('transfer_id') != transfer ||
          replay.read<String>('request_hash') != requestHash ||
          replay.read<int>('sealed') != 1) {
        throw StateError('Receipt request key belongs to another operation');
      }
      return _resultFromRow(replay, dispatch.lifecycleState == 'completed');
    }
    if (dispatch.catalogueState != 'ready') {
      throw StateError('Transfer catalogue is not ready');
    }
    if (!const {
      'awaiting_receipt',
      'partially_received',
    }.contains(dispatch.lifecycleState)) {
      throw StateError('Only a pending distributed transfer can be received');
    }

    final allocationMap = {
      for (final allocation in await _allocations(transfer))
        allocation.id: allocation,
    };
    final plans = <_ReceiptPlan>[];
    for (final request in normalized) {
      final allocation = allocationMap[request.allocationId];
      if (allocation == null) {
        throw StateError('Allocation does not belong to this transfer');
      }
      if (allocation.ownerType == 'consignment' &&
          (allocation.consignmentTerms == null ||
              allocation.supplierGlobalId == null)) {
        throw StateError('distributed_consignment_terms_required');
      }
      if (allocation.ownerType == 'consignment' &&
          (request.damagedQuantity > 0 || request.lostQuantity > 0) &&
          request.varianceResponsibility == null) {
        throw StateError('distributed_consignment_variance_responsibility');
      }
      final consumed = await _consumed(allocation.id);
      if (consumed + request.totalQuantity > allocation.quantity) {
        throw StateError('Receipt quantity exceeds dispatched quantity');
      }
      final acceptedEnd = consumed + request.acceptedQuantity;
      final totalEnd = consumed + request.totalQuantity;
      final local = await _localProduct(allocation);
      plans.add(
        _ReceiptPlan(
          request: request,
          allocation: allocation,
          local: local,
          previouslyConsumed: consumed,
          acceptedValueMinor: allocation.ownerType == 'owned'
              ? _valueAt(allocation, acceptedEnd) -
                    _valueAt(allocation, consumed)
              : 0,
          varianceValueMinor: allocation.ownerType == 'owned'
              ? _valueAt(allocation, totalEnd) -
                    _valueAt(allocation, acceptedEnd)
              : 0,
        ),
      );
    }

    final acceptedValue = plans.fold<int>(
      0,
      (sum, plan) => sum + plan.acceptedValueMinor,
    );
    final varianceValue = plans.fold<int>(
      0,
      (sum, plan) => sum + plan.varianceValueMinor,
    );
    final moment = (receivedAt ?? DateTime.now()).toUtc();
    final receiptId = const Uuid().v4();
    final receiptRowId = await db.customInsert(
      '''INSERT INTO distributed_transfer_inbound_receipts(
        receipt_id,transfer_id,request_key,request_hash,actor_id,item_count,
        accepted_owned_value_minor,variance_owned_value_minor,notes,received_at)
        VALUES(?,?,?,?,?,?,?,?,?,?)''',
      variables: [
        Variable.withString(receiptId),
        Variable.withString(transfer),
        Variable.withString(key),
        Variable.withString(requestHash),
        Variable.withInt(actor),
        Variable.withInt(plans.length),
        Variable.withInt(acceptedValue),
        Variable.withInt(varianceValue),
        Variable.withString(reason),
        Variable.withString(moment.toIso8601String()),
      ],
    );

    final destination = await WarehouseOperationScope.resolve(
      db,
      warehouseId: dispatch.destinationWarehouseId,
    );
    // A shared catalogue item may reach a secondary warehouse for the first
    // time through this transfer. Create its zero balance atomically here so
    // receipt does not depend on a separate manual warehouse-initialization
    // screen. The actual quantity and WAC/batch mutation still happens below.
    for (final plan in plans) {
      await db.customStatement(
        'INSERT INTO business_warehouse_stocks('
        'warehouse_id,variant_id,quantity,supplier_owned_quantity,'
        'unit_cost_cents) SELECT ?,?,0,0,0 WHERE NOT EXISTS('
        'SELECT 1 FROM business_warehouse_stocks WHERE warehouse_id=? '
        'AND variant_id=?)',
        [
          destination.warehouseId,
          plan.local.variantId,
          destination.warehouseId,
          plan.local.variantId,
        ],
      );
    }

    final touchedProducts = <int>{};
    final trackedProducts = <int>{};
    final eventItems = <Map<String, Object?>>[];
    for (final plan in plans) {
      final itemId = const Uuid().v4();
      int? batchId;
      final accepted = plan.request.acceptedQuantity;
      Map<String, Object?>? consignmentDestination;
      if (accepted > 0 ||
          (plan.allocation.ownerType == 'consignment' &&
              plan.request.totalQuantity > 0)) {
        if (plan.allocation.ownerType == 'consignment') {
          consignmentDestination = await _receiveConsignment(
            dispatch: dispatch,
            plan: plan,
            quantity: plan.request.totalQuantity,
            actorId: actor,
            destination: destination,
            receivedAt: moment,
            receiptId: receiptId,
          );
          batchId = consignmentDestination['batchId'] as int?;
          await _resolveConsignmentVariance(
            plan: plan,
            destination: consignmentDestination,
            receivedAt: moment,
            receiptId: receiptId,
            notes: reason,
          );
        } else {
          final tracked =
              plan.local.costingMethod == 'fifo' ||
              plan.local.trackingType != 'standard';
          final wac = !tracked
              ? await WacMovementService.capture(
                  db.productDao,
                  productId: plan.local.productId,
                  variantId: plan.local.variantId,
                  scope: destination,
                )
              : null;
          final origins = !tracked
              ? await _localOriginSlices(plan, accepted, receiptId: receiptId)
              : const <Map<String, dynamic>>[];
          await StockService.adjustStock(
            db.productDao,
            productId: plan.local.productId,
            variantId: plan.local.variantId,
            quantity: accepted,
            direction: StockDirection.increase,
            scope: destination,
            origin: InventoryOriginIntent.keyed(
              'distributed_transfer_in',
              'distributed_transfer_in:$itemId',
              reference: 'remote_transfer_out:${plan.allocation.id}',
              referenceWarehouse: dispatch.sourceWarehouseId,
              inboundLayers: origins,
            ),
          );
          if (wac != null) {
            await WacMovementService.applyInbound(
              db.productDao,
              snapshot: wac,
              addedQty: accepted,
              inboundUnitCostCents: plan.allocation.unitCostMinor,
            );
          }
          if (tracked) {
            final supplierId = await _localSupplierId(
              plan.allocation.supplierGlobalId,
            );
            batchId = await BatchService.createBatchFromDistributedTransfer(
              db.productDao,
              productId: plan.local.productId,
              variantId: plan.local.variantId,
              transferAllocationId: plan.allocation.id,
              supplierId: supplierId,
              quantity: accepted,
              unitCostCents: plan.allocation.unitCostMinor,
              receivedDate: moment,
              expiryDate: plan.allocation.expiryDate,
              manufacturerLotNumber: plan.allocation.manufacturerLotNumber,
              scope: destination,
            );
            trackedProducts.add(plan.local.productId);
          }
          touchedProducts.add(plan.local.productId);
        }
      }
      await db.customStatement(
        '''INSERT INTO distributed_transfer_inbound_receipt_items(
          item_id,receipt_id,allocation_id,accepted_quantity,damaged_quantity,
          lost_quantity,accepted_value_minor,variance_value_minor,
          destination_batch_id) VALUES(?,?,?,?,?,?,?,?,?)''',
        [
          itemId,
          receiptId,
          plan.allocation.id,
          accepted,
          plan.request.damagedQuantity,
          plan.request.lostQuantity,
          plan.acceptedValueMinor,
          plan.varianceValueMinor,
          batchId,
        ],
      );
      Map<String, Object?>? destinationBatch;
      if (batchId != null) {
        final sourceBatch = plan.allocation.sourceBatch;
        await db.customStatement(
          '''INSERT INTO distributed_transfer_batch_links(
            destination_batch_id,allocation_id,receipt_item_id,
            source_batch_global_id,source_batch_database_id)
            VALUES(?,?,?,?,?)''',
          [
            batchId,
            plan.allocation.id,
            itemId,
            sourceBatch?['globalId'],
            sourceBatch?['originDatabaseId'],
          ],
        );
        final identity = await syncIdentities.getOrCreateLocal(
          entityType: 'product_batch',
          localId: batchId,
        );
        destinationBatch = {
          'globalId': identity.globalId,
          'originDatabaseId': identity.originDatabaseId,
        };
      }
      eventItems.add({
        'allocationId': plan.allocation.id,
        'acceptedQuantityScaled': accepted,
        'damagedQuantityScaled': plan.request.damagedQuantity,
        'lostQuantityScaled': plan.request.lostQuantity,
        'varianceResponsibility': plan.request.varianceResponsibility,
        'liabilityUnitCents': plan.request.liabilityUnitCents,
        'acceptedValueMinor': plan.acceptedValueMinor,
        'varianceValueMinor': plan.varianceValueMinor,
        'destinationBatch': ?destinationBatch,
        'destinationConsignment': ?consignmentDestination,
      });
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
    final clearedValue = acceptedValue + varianceValue;
    if (clearedValue > 0) {
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
      final currency = await (db.select(
        db.currencies,
      )..where((row) => row.code.equals(dispatch.currencyCode))).getSingle();
      journalId = await accounting.createJournalEntry(
        entryData: JournalEntryData(
          description: 'Distributed warehouse transfer receipt $transfer',
          entryDate: moment,
          entryType: 'warehouse_transfer_receipt',
          sourceTable: 'distributed_transfer_inbound_receipts',
          sourceId: receiptRowId,
          autoPost: true,
          lines: [
            if (acceptedValue > 0)
              JournalEntryLineData(
                accountId: accounts['1200']!.id,
                debitCents: acceptedValue,
                creditCents: 0,
                currencyId: currency.id,
              ),
            if (varianceValue > 0)
              JournalEntryLineData(
                accountId: accounts['5800']!.id,
                debitCents: varianceValue,
                creditCents: 0,
                currencyId: currency.id,
              ),
            JournalEntryLineData(
              accountId: accounts['1210']!.id,
              debitCents: 0,
              creditCents: clearedValue,
              currencyId: currency.id,
            ),
          ],
        ),
        userId: actor,
      );
    }
    await db.customStatement(
      'UPDATE distributed_transfer_inbound_receipts '
      'SET journal_entry_id=?,sealed=1 WHERE receipt_id=? AND sealed=0',
      [journalId, receiptId],
    );

    final outstanding = await db
        .customSelect(
          '''SELECT 1 AS pending FROM distributed_transfer_inbound_allocations a
          WHERE a.transfer_id=? AND a.quantity_scaled>COALESCE((
            SELECT SUM(i.accepted_quantity+i.damaged_quantity+i.lost_quantity)
            FROM distributed_transfer_inbound_receipt_items i
            JOIN distributed_transfer_inbound_receipts r ON r.receipt_id=i.receipt_id
            WHERE i.allocation_id=a.allocation_id AND r.sealed=1),0) LIMIT 1''',
          variables: [Variable.withString(transfer)],
        )
        .getSingleOrNull();
    final completed = outstanding == null;
    await db.customStatement(
      'UPDATE distributed_transfer_inbound_dispatches SET lifecycle_state=?, '
      'updated_at=CURRENT_TIMESTAMP WHERE transfer_id=?',
      [completed ? 'completed' : 'partially_received', transfer],
    );

    final payload = <String, Object?>{
      'contract': 'warehouse_transfer.received',
      'contractVersion': 1,
      'transferId': transfer,
      'requestKey': key,
      'organizationId': dispatch.organizationId,
      'branchId': destination.branchId,
      'sourceDatabaseId': destination.databaseId,
      'sourceWarehouseId': dispatch.sourceWarehouseId,
      'destinationWarehouseId': dispatch.destinationWarehouseId,
      'currencyCode': dispatch.currencyCode,
      'receivedAt': moment.toIso8601String(),
      'actorRef': {'databaseId': destination.databaseId, 'localId': actor},
      'acceptedOwnedValueMinor': acceptedValue,
      'varianceOwnedValueMinor': varianceValue,
      'destinationInventoryDeltaMinor': acceptedValue,
      'completedTransfer': completed,
      'notes': reason,
      'itemCount': eventItems.length,
      'items': eventItems,
    };
    await sync.appendOnce(
      producerKey: 'distributed_transfer:$transfer:receipt:$key',
      eventType: 'warehouse_transfer.received.v1',
      aggregateType: 'warehouse_transfer',
      aggregateId: transfer,
      payload: payload,
      contractVersion: 1,
      occurredAt: moment,
    );
    return DistributedTransferReceiptResult(
      receiptId: receiptId,
      transferId: transfer,
      completed: completed,
      acceptedOwnedValueMinor: acceptedValue,
      varianceOwnedValueMinor: varianceValue,
    );
  });

  Future<List<Map<String, dynamic>>> _localOriginSlices(
    _ReceiptPlan plan,
    int accepted, {
    required String receiptId,
  }) async {
    final decoded = plan.allocation.originSlices;
    if (decoded == null || decoded.isEmpty) {
      final supplierId = await _localSupplierId(
        plan.allocation.supplierGlobalId,
      );
      final identity = await _optionalSupplierIdentity(
        supplierId: supplierId,
        productId: plan.local.productId,
        variantId: plan.local.variantId,
      );
      return [
        {
          'q': accepted,
          'k': 'branch_transfer',
          'r': 'distributed_transfer:$receiptId',
          's': ?supplierId,
          if (identity != null) 'i': identity.id,
        },
      ];
    }
    var skip = plan.previouslyConsumed;
    var remaining = accepted;
    final result = <Map<String, dynamic>>[];
    for (final raw in decoded) {
      if (raw is! Map) throw StateError('Invalid transfer origin slice');
      final slice = Map<String, Object?>.from(raw);
      final quantity = slice['quantityScaled'];
      if (quantity is! int || quantity <= 0) {
        throw StateError('Invalid transfer origin quantity');
      }
      if (skip >= quantity) {
        skip -= quantity;
        continue;
      }
      final available = quantity - skip;
      skip = 0;
      final take = remaining < available ? remaining : available;
      if (take <= 0) break;
      final supplierId = await _localSupplierId(
        slice['supplierGlobalId']?.toString(),
      );
      final identity = await _optionalSupplierIdentity(
        supplierId: supplierId,
        productId: plan.local.productId,
        variantId: plan.local.variantId,
      );
      result.add({
        'q': take,
        'k': 'branch_transfer',
        'r':
            slice['sourceReference']?.toString() ??
            'distributed_transfer:$receiptId',
        's': ?supplierId,
        if (identity != null) 'i': identity.id,
      });
      remaining -= take;
    }
    if (remaining != 0) {
      throw StateError('Distributed transfer origin is incomplete');
    }
    return result;
  }

  /// A supplier-specific barcode is optional. Receiving must preserve the
  /// documented supplier even when that supplier has no code configured.
  /// Reuse an issued identity when it exists and issue a new one only when the
  /// supplier explicitly has a product-code namespace.
  Future<SupplierProductIdentity?> _optionalSupplierIdentity({
    required int? supplierId,
    required int productId,
    required int variantId,
  }) async {
    if (supplierId == null) return null;
    final identities = SupplierProductIdentityService(db);
    final existing = await identities.findForVariant(
      supplierId: supplierId,
      canonicalVariantId: variantId,
    );
    if (existing != null) return existing;
    final supplier = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingleOrNull();
    if (supplier?.productCode?.trim().isEmpty ?? true) return null;
    return identities.ensureIssued(
      supplierId: supplierId,
      productId: productId,
      variantId: variantId,
    );
  }

  Future<Map<String, Object?>> _receiveConsignment({
    required _Dispatch dispatch,
    required _ReceiptPlan plan,
    required int quantity,
    required int actorId,
    required WarehouseOperationScope destination,
    required DateTime receivedAt,
    required String receiptId,
  }) async {
    final agreements = consignmentAgreements;
    final receipts = consignmentReceipts;
    if (agreements == null || receipts == null) {
      throw StateError('distributed_consignment_services_unavailable');
    }
    final allocation = plan.allocation;
    final supplierId = await _localSupplierId(allocation.supplierGlobalId);
    if (supplierId == null) {
      throw StateError('distributed_consignment_supplier_not_mapped');
    }
    final currencyId =
        await (db.select(db.currencies)
              ..where((row) => row.code.equals(dispatch.currencyCode)))
            .map((r) => r.id)
            .getSingle();
    final agreementId = await _ensureConsignmentAgreement(
      dispatch: dispatch,
      allocation: allocation,
      supplierId: supplierId,
      currencyId: currencyId,
      receivedAt: receivedAt,
    );
    final keySeed =
        '${dispatch.transferId}:${allocation.id}:${plan.previouslyConsumed}:$receiptId';
    final draftKey = const Uuid().v5(
      Namespace.url.value,
      'tapix-distributed-consignment-receipt:$keySeed',
    );
    final postKey = const Uuid().v5(
      Namespace.url.value,
      'tapix-distributed-consignment-post:$keySeed',
    );
    final receipt = await receipts.createDraft(
      requestKey: draftKey,
      receiptNumber:
          'BTR-${dispatch.transferId.substring(0, 8)}-${allocation.id.substring(0, 8)}-${plan.previouslyConsumed}',
      warehouseId: destination.warehouseId,
      supplierId: supplierId,
      agreementId: agreementId,
      currencyId: currencyId,
      receivedAt: receivedAt,
      notes: 'Distributed branch custody transfer ${dispatch.transferId}',
      lines: [
        ConsignmentReceiptLineInput(
          productId: plan.local.productId,
          variantId: plan.local.variantId,
          quantity: quantity,
          manufacturerLotNumber: allocation.manufacturerLotNumber,
          expiryDate: allocation.expiryDate,
        ),
      ],
    );
    await receipts.post(receiptId: receipt.id, requestKey: postKey);
    final row = await db
        .customSelect(
          '''SELECT i.id AS receipt_item_id,l.id AS layer_id,l.batch_id
          FROM consignment_receipt_items i
          JOIN consignment_inventory_layers l ON l.receipt_item_id=i.id
          WHERE i.receipt_id=?''',
          variables: [Variable.withString(receipt.id)],
        )
        .getSingle();
    final sourceLayerId = allocation.sourceConsignmentLayerId;
    if (sourceLayerId == null) {
      throw StateError('distributed_consignment_source_layer_missing');
    }
    await db.customStatement(
      '''INSERT INTO distributed_consignment_layer_links(
        allocation_id,receipt_item_id,layer_id,receipt_id,source_database_id,
        source_layer_id) VALUES(?,?,?,?,?,?)''',
      [
        allocation.id,
        row.read<String>('receipt_item_id'),
        row.read<String>('layer_id'),
        receipt.id,
        dispatch.sourceDatabaseId,
        sourceLayerId,
      ],
    );
    return {
      'agreementId': agreementId,
      'receiptId': receipt.id,
      'receiptItemId': row.read<String>('receipt_item_id'),
      'layerId': row.read<String>('layer_id'),
      'batchId': row.readNullable<int>('batch_id'),
      'sourceLayerId': sourceLayerId,
      'sourceDatabaseId': dispatch.sourceDatabaseId,
      'actorId': actorId,
    };
  }

  Future<void> _resolveConsignmentVariance({
    required _ReceiptPlan plan,
    required Map<String, Object?> destination,
    required DateTime receivedAt,
    required String receiptId,
    required String notes,
  }) async {
    final damaged = plan.request.damagedQuantity;
    final lost = plan.request.lostQuantity;
    if (damaged == 0 && lost == 0) return;
    final custody = consignmentCustody;
    final responsibility = plan.request.varianceResponsibility;
    if (custody == null || responsibility == null) {
      throw StateError('distributed_consignment_variance_responsibility');
    }
    final layerId = destination['layerId']?.toString();
    final agreementId = destination['agreementId']?.toString();
    if (layerId == null || agreementId == null) {
      throw StateError('distributed_consignment_destination_invalid');
    }
    final layer = await db
        .customSelect(
          '''SELECT l.warehouse_id,l.supplier_id,a.currency_id
      FROM consignment_inventory_layers l
      JOIN consignment_agreements a ON a.id=l.agreement_id
      WHERE l.id=? AND l.agreement_id=?''',
          variables: [
            Variable.withString(layerId),
            Variable.withString(agreementId),
          ],
        )
        .getSingle();
    Future<void> postVariance(String type, int quantity) async {
      if (quantity <= 0) return;
      final seed = '$receiptId:${plan.allocation.id}:$type';
      final draftKey = const Uuid().v5(
        Namespace.url.value,
        'tapix-distributed-consignment-variance-draft:$seed',
      );
      final postKey = const Uuid().v5(
        Namespace.url.value,
        'tapix-distributed-consignment-variance-post:$seed',
      );
      final document = await custody.createDraft(
        requestKey: draftKey,
        documentNumber:
            'BTV-${type == 'damage' ? 'D' : 'L'}-${receiptId.substring(0, 8)}-${plan.allocation.id.substring(0, 8)}',
        documentType: type,
        responsibility: responsibility,
        warehouseId: layer.read<String>('warehouse_id'),
        supplierId: layer.read<int>('supplier_id'),
        agreementId: agreementId,
        currencyId: layer.read<int>('currency_id'),
        occurredAt: receivedAt,
        reason: notes,
        notes: 'Distributed transfer variance ${plan.allocation.id}',
        lines: [
          ConsignmentCustodyLineInput(
            layerId: layerId,
            quantity: quantity,
            liabilityUnitCents: plan.request.liabilityUnitCents,
          ),
        ],
      );
      await custody.post(documentId: document.id, requestKey: postKey);
    }

    await postVariance('damage', damaged);
    await postVariance('loss', lost);
  }

  Future<String> _ensureConsignmentAgreement({
    required _Dispatch dispatch,
    required _Allocation allocation,
    required int supplierId,
    required int currencyId,
    required DateTime receivedAt,
  }) async {
    final snapshot = allocation.consignmentTerms!;
    final sourceAgreementId = snapshot['sourceAgreementId']?.toString();
    if (sourceAgreementId == null ||
        sourceAgreementId != allocation.consignmentAgreementId ||
        !Uuid.isValidUUID(fromString: sourceAgreementId)) {
      throw StateError('distributed_consignment_agreement_identity_invalid');
    }
    final termsHash = _hash(snapshot);
    final prior = await db
        .customSelect(
          'SELECT local_agreement_id,terms_hash '
          'FROM distributed_consignment_agreement_mirrors '
          'WHERE source_database_id=? AND source_agreement_id=?',
          variables: [
            Variable.withString(dispatch.sourceDatabaseId),
            Variable.withString(sourceAgreementId),
          ],
        )
        .getSingleOrNull();
    if (prior != null) {
      if (prior.read<String>('terms_hash') != termsHash) {
        throw StateError('distributed_consignment_agreement_hash_conflict');
      }
      return prior.read<String>('local_agreement_id');
    }
    final active =
        await (db.select(db.consignmentAgreements)..where(
              (row) =>
                  row.branchId.equals(dispatch.destinationBranchId) &
                  row.supplierId.equals(supplierId) &
                  row.currencyId.equals(currencyId) &
                  row.status.equals('active'),
            ))
            .getSingleOrNull();
    if (active != null) {
      throw StateError('distributed_consignment_agreement_conflict');
    }
    final rawTerms = snapshot['terms'];
    if (rawTerms is! List || rawTerms.isEmpty || rawTerms.length > 500) {
      throw StateError('distributed_consignment_terms_invalid');
    }
    final terms = <ConsignmentAgreementTermInput>[];
    for (final raw in rawTerms) {
      if (raw is! Map) {
        throw StateError('distributed_consignment_terms_invalid');
      }
      final term = Map<String, Object?>.from(raw);
      final productId = await _localIdentityId(
        'product',
        term['productGlobalId']?.toString(),
      );
      final variantGlobal = term['variantGlobalId']?.toString();
      final variantId = variantGlobal == null
          ? null
          : await _localIdentityId('product_variant', variantGlobal);
      final basis = term['settlementBasis']?.toString();
      if (basis == 'fixed_unit_cost') {
        final cost = term['unitCostMinor'];
        if (cost is! int || cost < 0) {
          throw StateError('distributed_consignment_terms_invalid');
        }
        terms.add(
          ConsignmentAgreementTermInput.fixedCost(
            productId: productId,
            variantId: variantId,
            amountCents: cost,
          ),
        );
      } else if (basis == 'net_sales_percentage') {
        final share = term['supplierShareBps'];
        if (share is! int || share < 0 || share > 10000) {
          throw StateError('distributed_consignment_terms_invalid');
        }
        terms.add(
          ConsignmentAgreementTermInput.salesPercentage(
            productId: productId,
            variantId: variantId,
            shareBps: share,
            includeLineDiscount: term['includeLineDiscount'] == true,
            includeInvoiceDiscount: term['includeInvoiceDiscount'] == true,
            includeSalesTax: term['includeSalesTax'] == true,
          ),
        );
      } else {
        throw StateError('distributed_consignment_terms_invalid');
      }
    }
    final effectiveRaw = snapshot['effectiveFrom']?.toString();
    final parsedEffective = DateTime.tryParse(effectiveRaw ?? '')?.toUtc();
    if (parsedEffective == null) {
      throw StateError('distributed_consignment_terms_invalid');
    }
    final agreement = await consignmentAgreements!.createDraft(
      supplierId: supplierId,
      currencyId: currencyId,
      agreementNumber:
          'BTR-${dispatch.sourceDatabaseId.substring(0, 8)}-${sourceAgreementId.substring(0, 8)}',
      effectiveFrom: parsedEffective.isAfter(receivedAt)
          ? receivedAt
          : parsedEffective,
      settlementFrequency:
          snapshot['settlementFrequency']?.toString() ?? 'monthly',
      paymentTermsDays: snapshot['paymentTermsDays'] is int
          ? snapshot['paymentTermsDays']! as int
          : 0,
      settlementTaxRateBps: snapshot['settlementTaxRateBps'] is int
          ? snapshot['settlementTaxRateBps']! as int
          : 0,
      settlementTaxInclusive: snapshot['settlementTaxInclusive'] == true,
      notes: 'Mirrored custody terms from branch ${dispatch.sourceBranchId}',
      terms: terms,
    );
    await consignmentAgreements!.activate(agreement.id);
    await db.customStatement(
      '''INSERT INTO distributed_consignment_agreement_mirrors(
        source_database_id,source_agreement_id,local_agreement_id,terms_hash)
        VALUES(?,?,?,?)''',
      [dispatch.sourceDatabaseId, sourceAgreementId, agreement.id, termsHash],
    );
    return agreement.id;
  }

  Future<int> _localIdentityId(String type, String? globalId) async {
    if (globalId == null || !Uuid.isValidUUID(fromString: globalId)) {
      throw StateError('distributed_consignment_catalogue_identity_missing');
    }
    final id = await db
        .customSelect(
          'SELECT local_id FROM sync_entity_identities '
          'WHERE entity_type=? AND global_id=?',
          variables: [Variable.withString(type), Variable.withString(globalId)],
        )
        .map((row) => row.read<int>('local_id'))
        .getSingleOrNull();
    if (id == null) {
      throw StateError('distributed_consignment_catalogue_identity_missing');
    }
    return id;
  }

  Future<int?> _localSupplierId(String? globalId) async {
    if (globalId == null) return null;
    return db
        .customSelect(
          "SELECT local_id FROM sync_entity_identities WHERE entity_type='supplier' AND global_id=?",
          variables: [Variable.withString(globalId)],
        )
        .map((row) => row.read<int>('local_id'))
        .getSingleOrNull();
  }

  Future<int> _consumed(String allocationId) => db
      .customSelect(
        '''SELECT COALESCE(SUM(i.accepted_quantity+i.damaged_quantity+i.lost_quantity),0) AS quantity
        FROM distributed_transfer_inbound_receipt_items i
        JOIN distributed_transfer_inbound_receipts r ON r.receipt_id=i.receipt_id
        WHERE i.allocation_id=? AND r.sealed=1''',
        variables: [Variable.withString(allocationId)],
      )
      .map((row) => row.read<int>('quantity'))
      .getSingle();

  Future<_Dispatch> _dispatch(String transferId) => db
      .customSelect(
        'SELECT * FROM distributed_transfer_inbound_dispatches WHERE transfer_id=?',
        variables: [Variable.withString(transferId)],
      )
      .map(_Dispatch.fromRow)
      .getSingle();

  Future<List<_Allocation>> _allocations(String transferId) => db
      .customSelect(
        'SELECT * FROM distributed_transfer_inbound_allocations '
        'WHERE transfer_id=? ORDER BY sequence',
        variables: [Variable.withString(transferId)],
      )
      .map(_Allocation.fromRow)
      .get();

  Future<_LocalProduct> _localProduct(_Allocation allocation) async {
    final row = await db
        .customSelect(
          '''SELECT p.id AS product_id,v.id AS variant_id,p.name,
          COALESCE(v.sku,v.barcode,p.sku,p.barcode,'') AS code,
          p.costing_method,p.inventory_tracking_type
          FROM sync_entity_identities pi
          JOIN products p ON pi.entity_type='product' AND pi.local_id=p.id
          JOIN sync_entity_identities vi ON vi.entity_type='product_variant'
          JOIN product_variants v ON vi.local_id=v.id AND v.product_id=p.id
          WHERE pi.global_id=? AND vi.global_id=?''',
          variables: [
            Variable.withString(allocation.productGlobalId),
            Variable.withString(allocation.variantGlobalId),
          ],
        )
        .getSingle();
    return _LocalProduct(
      productId: row.read<int>('product_id'),
      variantId: row.read<int>('variant_id'),
      name: row.read<String>('name'),
      code: row.read<String>('code'),
      costingMethod: row.read<String>('costing_method'),
      trackingType: row.read<String>('inventory_tracking_type'),
    );
  }

  DistributedTransferReceiptResult _resultFromRow(
    QueryRow row,
    bool completed,
  ) => DistributedTransferReceiptResult(
    receiptId: row.read<String>('receipt_id'),
    transferId: row.read<String>('transfer_id'),
    completed: completed,
    acceptedOwnedValueMinor: row.read<int>('accepted_owned_value_minor'),
    varianceOwnedValueMinor: row.read<int>('variance_owned_value_minor'),
  );
}

class _Dispatch {
  const _Dispatch({
    required this.transferId,
    required this.organizationId,
    required this.sourceDatabaseId,
    required this.sourceBranchId,
    required this.destinationBranchId,
    required this.sourceWarehouseId,
    required this.destinationWarehouseId,
    required this.currencyCode,
    required this.catalogueState,
    required this.lifecycleState,
  });

  final String transferId;
  final String organizationId;
  final String sourceDatabaseId;
  final String sourceBranchId;
  final String destinationBranchId;
  final String sourceWarehouseId;
  final String destinationWarehouseId;
  final String currencyCode;
  final String catalogueState;
  final String lifecycleState;

  factory _Dispatch.fromRow(QueryRow row) => _Dispatch(
    transferId: row.read<String>('transfer_id'),
    organizationId: row.read<String>('organization_id'),
    sourceDatabaseId: row.read<String>('source_database_id'),
    sourceBranchId: row.read<String>('source_branch_id'),
    destinationBranchId: row.read<String>('destination_branch_id'),
    sourceWarehouseId: row.read<String>('source_warehouse_id'),
    destinationWarehouseId: row.read<String>('destination_warehouse_id'),
    currencyCode: row.read<String>('currency_code'),
    catalogueState: row.read<String>('catalogue_state'),
    lifecycleState: row.read<String>('lifecycle_state'),
  );
}

class _Allocation {
  const _Allocation({
    required this.id,
    required this.productGlobalId,
    required this.variantGlobalId,
    required this.ownerType,
    required this.quantity,
    required this.quantityScale,
    required this.measurementType,
    required this.unitCostMinor,
    required this.supplierGlobalId,
    required this.sourceBatch,
    required this.originSlices,
    required this.consignmentTerms,
    required this.consignmentAgreementId,
    required this.sourceConsignmentLayerId,
    required this.manufacturerLotNumber,
    required this.expiryDate,
  });

  final String id;
  final String productGlobalId;
  final String variantGlobalId;
  final String ownerType;
  final int quantity;
  final int quantityScale;
  final String measurementType;
  final int unitCostMinor;
  final String? supplierGlobalId;
  final Map<String, Object?>? sourceBatch;
  final List<Object?>? originSlices;
  final Map<String, Object?>? consignmentTerms;
  final String? consignmentAgreementId;
  final String? sourceConsignmentLayerId;
  final String? manufacturerLotNumber;
  final DateTime? expiryDate;

  factory _Allocation.fromRow(QueryRow row) {
    final batch = row.readNullable<String>('source_batch_json');
    final origins = row.readNullable<String>('origin_slices_json');
    final terms = row.readNullable<String>('consignment_terms_json');
    return _Allocation(
      id: row.read<String>('allocation_id'),
      productGlobalId: row.read<String>('product_global_id'),
      variantGlobalId: row.read<String>('variant_global_id'),
      ownerType: row.read<String>('owner_type'),
      quantity: row.read<int>('quantity_scaled'),
      quantityScale: row.read<int>('quantity_scale'),
      measurementType: row.read<String>('measurement_type'),
      unitCostMinor: row.read<int>('unit_cost_minor'),
      supplierGlobalId: row.readNullable<String>('supplier_global_id'),
      sourceBatch: batch == null
          ? null
          : Map<String, Object?>.from(jsonDecode(batch) as Map),
      originSlices: origins == null
          ? null
          : List<Object?>.from(jsonDecode(origins) as List),
      consignmentTerms: terms == null
          ? null
          : Map<String, Object?>.from(jsonDecode(terms) as Map),
      consignmentAgreementId: row.readNullable<String>(
        'consignment_agreement_id',
      ),
      sourceConsignmentLayerId: row.readNullable<String>(
        'source_consignment_layer_id',
      ),
      manufacturerLotNumber: row.readNullable<String>(
        'manufacturer_lot_number',
      ),
      expiryDate: DateTime.tryParse(
        row.readNullable<String>('expiry_date') ?? '',
      )?.toUtc(),
    );
  }
}

class _LocalProduct {
  const _LocalProduct({
    required this.productId,
    required this.variantId,
    required this.name,
    required this.code,
    required this.costingMethod,
    required this.trackingType,
  });

  final int productId;
  final int variantId;
  final String name;
  final String code;
  final String costingMethod;
  final String trackingType;
}

class _ReceiptPlan {
  const _ReceiptPlan({
    required this.request,
    required this.allocation,
    required this.local,
    required this.previouslyConsumed,
    required this.acceptedValueMinor,
    required this.varianceValueMinor,
  });

  final DistributedTransferReceiptItemRequest request;
  final _Allocation allocation;
  final _LocalProduct local;
  final int previouslyConsumed;
  final int acceptedValueMinor;
  final int varianceValueMinor;
}
