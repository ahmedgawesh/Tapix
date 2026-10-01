import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../database/app_database.dart';
import '../../measurement/measurement.dart';
import 'branch_catalogue_sync_service.dart';
import 'branch_location_directory_sync_service.dart';
import 'offline_sync_event_store.dart';
import 'sync_entity_identity_store.dart';

/// Turns immutable company events into local operational work without posting
/// foreign accounting entries. A dispatch addressed to this database becomes
/// a pending inbound document; stock changes only through the later receipt
/// transaction owned by this branch.
class BranchOperationalProjectionService {
  BranchOperationalProjectionService(
    this._db, {
    BranchCatalogueSyncService? catalogue,
    BranchLocationDirectorySyncService? locations,
    OfflineSyncEventStore? events,
    Future<void> Function(SyncEventEnvelope event)? recallResolutionHandler,
  }) : _catalogue =
           catalogue ??
           BranchCatalogueSyncService(
             _db,
             OfflineSyncEventStore(_db),
             SyncEntityIdentityStore(_db),
           ),
       _locations =
           locations ??
           BranchLocationDirectorySyncService(_db, OfflineSyncEventStore(_db)),
       _events = events ?? OfflineSyncEventStore(_db),
       _recallResolutionHandler = recallResolutionHandler;

  final AppDatabase _db;
  final BranchCatalogueSyncService _catalogue;
  final BranchLocationDirectorySyncService _locations;
  final OfflineSyncEventStore _events;
  final Future<void> Function(SyncEventEnvelope event)?
  _recallResolutionHandler;

  Future<void> apply(SyncEventEnvelope event) async {
    switch (event.eventType) {
      case BranchCatalogueSyncService.eventType:
        await _catalogue.applyPage(event);
        await refreshCatalogueReadiness();
      case BranchLocationDirectorySyncService.eventType:
        await _locations.applyPage(event);
      case BranchCatalogueSyncService.customerProfileEventType:
        await _catalogue.applyCustomerProfile(event);
      case 'warehouse_transfer.dispatched.v1':
        await _applyDispatch(event);
      case 'warehouse_transfer.received.v1':
        await _applyRemoteReceipt(event);
      case 'warehouse_transfer.recalled.v1':
        await _applyRecall(event);
      case 'warehouse_transfer.recall_requested.v1':
        await _applyRecallRequest(event);
      case 'warehouse_transfer.recall_resolved.v1':
        await _applyRecallResolution(event);
    }
  }

  Future<void> _applyRecallRequest(SyncEventEnvelope event) async {
    final payload = event.payload;
    _requireContract(
      event,
      payload,
      expected: 'warehouse_transfer.recall_requested',
    );
    final transferId = _uuid(payload, 'transferId');
    final requestId = _uuid(payload, 'requestId');
    final organizationId = _uuid(payload, 'organizationId');
    final sourceDatabaseId = _uuid(payload, 'sourceDatabaseId');
    final sourceWarehouseId = _uuid(payload, 'sourceWarehouseId');
    final destinationDatabaseId = _uuid(payload, 'destinationDatabaseId');
    final destinationBranchId = _uuid(payload, 'destinationBranchId');
    final destinationWarehouseId = _uuid(payload, 'destinationWarehouseId');
    if (event.aggregateType != 'warehouse_transfer' ||
        event.aggregateId != transferId ||
        event.organizationId != organizationId ||
        event.sourceDatabaseId != sourceDatabaseId) {
      throw const OfflineSyncException(
        'distributed_recall_request_identity_mismatch',
        'The recall request identity is invalid.',
      );
    }
    _uuid(payload, 'requestKey');
    _date(payload, 'requestedAt');
    _text(payload, 'reason', max: 500);
    final target = await _localTarget(
      organizationId: organizationId,
      warehouseId: destinationWarehouseId,
    );
    if (target == null) return;
    if (target.databaseId != destinationDatabaseId ||
        target.branchId != destinationBranchId) {
      throw const OfflineSyncException(
        'distributed_recall_destination_mismatch',
        'The recall request is addressed to another destination.',
      );
    }
    final changed = await _db.customUpdate(
      "UPDATE distributed_transfer_inbound_dispatches SET lifecycle_state='recalled',updated_at=CURRENT_TIMESTAMP WHERE transfer_id=? AND source_database_id=? AND lifecycle_state='awaiting_receipt' AND NOT EXISTS(SELECT 1 FROM distributed_transfer_inbound_receipts r WHERE r.transfer_id=? AND r.sealed=1)",
      variables: [
        Variable.withString(transferId),
        Variable.withString(sourceDatabaseId),
        Variable.withString(transferId),
      ],
      updates: const {},
    );
    final accepted = changed == 1;
    final at = DateTime.now().toUtc();
    await _events.transaction((sync) async {
      if (!await sync.isWriterRecordingEnabled()) {
        throw const OfflineSyncException(
          'distributed_recall_destination_not_recording',
          'The destination writer cannot confirm this recall.',
        );
      }
      await sync.appendOnce(
        producerKey:
            'warehouse_transfer:$transferId:recall_resolution:$requestId',
        eventType: 'warehouse_transfer.recall_resolved.v1',
        aggregateType: 'warehouse_transfer',
        aggregateId: transferId,
        occurredAt: at,
        payload: {
          'contract': 'warehouse_transfer.recall_resolved',
          'contractVersion': 1,
          'transferId': transferId,
          'requestId': requestId,
          'organizationId': organizationId,
          'branchId': target.branchId,
          'sourceDatabaseId': target.databaseId,
          'originalSourceDatabaseId': sourceDatabaseId,
          'sourceWarehouseId': sourceWarehouseId,
          'destinationWarehouseId': destinationWarehouseId,
          'accepted': accepted,
          'resolvedAt': at.toIso8601String(),
          'reason': accepted
              ? 'destination_confirmed_unreceived'
              : 'destination_already_received',
        },
      );
    });
  }

  Future<void> _applyRecallResolution(SyncEventEnvelope event) async {
    final payload = event.payload;
    _requireContract(
      event,
      payload,
      expected: 'warehouse_transfer.recall_resolved',
    );
    final transferId = _uuid(payload, 'transferId');
    final organizationId = _uuid(payload, 'organizationId');
    final originalSourceDatabaseId = _uuid(payload, 'originalSourceDatabaseId');
    final sourceWarehouseId = _uuid(payload, 'sourceWarehouseId');
    if (event.aggregateType != 'warehouse_transfer' ||
        event.aggregateId != transferId ||
        event.organizationId != organizationId ||
        payload['accepted'] is! bool) {
      throw const OfflineSyncException(
        'distributed_recall_resolution_identity_mismatch',
        'The recall response identity is invalid.',
      );
    }
    _uuid(payload, 'requestId');
    _date(payload, 'resolvedAt');
    final local = await _localTarget(
      organizationId: organizationId,
      warehouseId: sourceWarehouseId,
    );
    if (local == null || local.databaseId != originalSourceDatabaseId) return;
    final handler = _recallResolutionHandler;
    if (handler == null) {
      throw const OfflineSyncException(
        'distributed_recall_resolution_handler_missing',
        'The source cannot apply the recall response.',
      );
    }
    await handler(event);
  }

  Future<void> _applyDispatch(SyncEventEnvelope event) async {
    final payload = event.payload;
    _requireContract(event, payload, expected: 'warehouse_transfer.dispatched');
    final transferId = _uuid(payload, 'transferId');
    if (event.aggregateType != 'warehouse_transfer' ||
        event.aggregateId != transferId) {
      throw const OfflineSyncException(
        'distributed_transfer_identity_mismatch',
        'The transfer event and payload identities do not match.',
      );
    }
    final organizationId = _uuid(payload, 'organizationId');
    final sourceDatabaseId = _uuid(payload, 'sourceDatabaseId');
    final sourceBranchId = _uuid(payload, 'branchId');
    final sourceWarehouseId = _uuid(payload, 'sourceWarehouseId');
    final destinationWarehouseId = _uuid(payload, 'destinationWarehouseId');
    if (organizationId != event.organizationId ||
        sourceDatabaseId != event.sourceDatabaseId ||
        sourceBranchId != event.branchId) {
      throw const OfflineSyncException(
        'distributed_transfer_source_mismatch',
        'The transfer source does not match its signed event envelope.',
      );
    }

    final target = await _localTarget(
      organizationId: organizationId,
      warehouseId: destinationWarehouseId,
    );
    if (target == null) return;
    if (sourceDatabaseId == target.databaseId ||
        sourceWarehouseId == destinationWarehouseId) {
      throw const OfflineSyncException(
        'invalid_distributed_transfer_route',
        'A distributed transfer must cross database and warehouse boundaries.',
      );
    }

    final currencyCode = _text(payload, 'currencyCode', max: 3).toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currencyCode) ||
        await _currencyExists(currencyCode) == false) {
      throw const OfflineSyncException(
        'distributed_transfer_currency_mismatch',
        'The transfer currency is unavailable at the destination branch.',
      );
    }
    final dispatchedAt = _date(payload, 'dispatchedAt');
    final allocationCount = _positiveInt(payload, 'allocationCount', max: 5000);
    final ownedValue = _nonNegativeInt(payload, 'ownedValueMinor');
    final rawAllocations = payload['allocations'];
    if (rawAllocations is! List ||
        rawAllocations.length != allocationCount ||
        rawAllocations.isEmpty) {
      throw const OfflineSyncException(
        'distributed_transfer_allocation_mismatch',
        'The transfer allocation count does not match its payload.',
      );
    }

    final allocations = <_InboundAllocation>[];
    final sequences = <int>{};
    var calculatedOwnedValue = 0;
    var catalogueReady = true;
    for (final raw in rawAllocations) {
      if (raw is! Map) {
        throw const OfflineSyncException(
          'invalid_distributed_transfer_allocation',
          'A transfer allocation has an invalid structure.',
        );
      }
      final allocation = _InboundAllocation.parse(
        Map<String, Object?>.from(raw),
      );
      if (!sequences.add(allocation.sequence)) {
        throw const OfflineSyncException(
          'duplicate_distributed_transfer_sequence',
          'A transfer allocation sequence is duplicated.',
        );
      }
      if (allocation.ownerType == 'owned') {
        calculatedOwnedValue += allocation.valueMinor;
      }
      catalogueReady = catalogueReady && await _catalogueIsMapped(allocation);
      allocations.add(allocation);
    }
    allocations.sort((left, right) => left.sequence.compareTo(right.sequence));
    for (var index = 0; index < allocations.length; index++) {
      if (allocations[index].sequence != index + 1) {
        throw const OfflineSyncException(
          'invalid_distributed_transfer_sequence',
          'Transfer allocation sequences must be contiguous.',
        );
      }
    }
    if (calculatedOwnedValue != ownedValue) {
      throw const OfflineSyncException(
        'distributed_transfer_value_mismatch',
        'The transfer owned value does not match its allocations.',
      );
    }

    await _db.customStatement(
      '''INSERT INTO distributed_transfer_inbound_dispatches(
        transfer_id,dispatch_event_id,organization_id,source_database_id,
        source_branch_id,source_warehouse_id,destination_branch_id,
        destination_warehouse_id,currency_code,dispatched_at,
        allocation_count,owned_value_minor,payload_json,payload_hash,
        catalogue_state)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
      [
        transferId,
        event.eventId,
        organizationId,
        sourceDatabaseId,
        sourceBranchId,
        sourceWarehouseId,
        target.branchId,
        destinationWarehouseId,
        currencyCode,
        dispatchedAt.toIso8601String(),
        allocationCount,
        ownedValue,
        jsonEncode(payload),
        event.eventHash,
        catalogueReady ? 'ready' : 'awaiting_catalogue',
      ],
    );
    for (final allocation in allocations) {
      await _db.customStatement(
        '''INSERT INTO distributed_transfer_inbound_allocations(
          allocation_id,transfer_id,sequence,product_global_id,
          variant_global_id,owner_type,quantity_scaled,quantity_scale,
          measurement_type,unit_cost_minor,value_minor,supplier_global_id,
          consignment_agreement_id,source_consignment_layer_id,
          source_batch_json,origin_slices_json,manufacturer_lot_number,
          expiry_date,consignment_terms_json)
          VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
        [
          allocation.id,
          transferId,
          allocation.sequence,
          allocation.productGlobalId,
          allocation.variantGlobalId,
          allocation.ownerType,
          allocation.quantity,
          allocation.scale,
          allocation.measurementType,
          allocation.unitCostMinor,
          allocation.valueMinor,
          allocation.supplierGlobalId,
          allocation.agreementId,
          allocation.sourceConsignmentLayerId,
          allocation.sourceBatch == null
              ? null
              : jsonEncode(allocation.sourceBatch),
          allocation.originSlices == null
              ? null
              : jsonEncode(allocation.originSlices),
          allocation.manufacturerLotNumber,
          allocation.expiryDate?.toIso8601String(),
          allocation.consignmentTerms == null
              ? null
              : jsonEncode(allocation.consignmentTerms),
        ],
      );
    }
  }

  Future<void> _applyRemoteReceipt(SyncEventEnvelope event) async {
    final payload = event.payload;
    _requireContract(event, payload, expected: 'warehouse_transfer.received');
    final transferId = _uuid(payload, 'transferId');
    final organizationId = _uuid(payload, 'organizationId');
    final receiptDatabaseId = _uuid(payload, 'sourceDatabaseId');
    final receiptBranchId = _uuid(payload, 'branchId');
    final sourceWarehouseId = _uuid(payload, 'sourceWarehouseId');
    final destinationWarehouseId = _uuid(payload, 'destinationWarehouseId');
    if (event.aggregateId != transferId ||
        event.aggregateType != 'warehouse_transfer' ||
        organizationId != event.organizationId ||
        receiptDatabaseId != event.sourceDatabaseId ||
        receiptBranchId != event.branchId) {
      throw const OfflineSyncException(
        'distributed_transfer_receipt_identity_mismatch',
        'The receipt event does not match its transfer.',
      );
    }
    final local = await _localTarget(
      organizationId: organizationId,
      warehouseId: sourceWarehouseId,
    );
    if (local == null) return;
    final localTransfer = await _db
        .customSelect(
          '''SELECT t.destination_warehouse_id,t.status,c.code AS currency_code
          FROM warehouse_transfers t
          JOIN currencies c ON c.id=t.currency_id
          WHERE t.id=? AND t.organization_id=? AND t.database_id=?
            AND t.source_warehouse_id=? AND t.sealed=1''',
          variables: [
            Variable.withString(transferId),
            Variable.withString(organizationId),
            Variable.withString(local.databaseId),
            Variable.withString(sourceWarehouseId),
          ],
        )
        .getSingleOrNull();
    final distributedTransfer = localTransfer == null
        ? await _db
              .customSelect(
                '''SELECT destination_warehouse_id,destination_database_id,
                destination_branch_id,status,currency_code
                FROM distributed_transfer_outbound_documents
                WHERE transfer_id=? AND organization_id=?
                  AND source_database_id=? AND source_warehouse_id=?''',
                variables: [
                  Variable.withString(transferId),
                  Variable.withString(organizationId),
                  Variable.withString(local.databaseId),
                  Variable.withString(sourceWarehouseId),
                ],
              )
              .getSingleOrNull()
        : null;
    final transfer = localTransfer ?? distributedTransfer;
    final distributed = distributedTransfer != null;
    if (transfer == null ||
        transfer.read<String>('destination_warehouse_id') !=
            destinationWarehouseId ||
        distributed &&
            (transfer.read<String>('destination_database_id') !=
                    receiptDatabaseId ||
                transfer.read<String>('destination_branch_id') !=
                    receiptBranchId) ||
        !const {
          'in_transit',
          'partially_received',
        }.contains(transfer.read<String>('status'))) {
      throw const OfflineSyncException(
        'distributed_transfer_source_document_mismatch',
        'The receipt does not match an open source transfer.',
      );
    }
    final currencyCode = _text(payload, 'currencyCode', max: 3).toUpperCase();
    if (currencyCode != transfer.read<String>('currency_code')) {
      throw const OfflineSyncException(
        'distributed_transfer_currency_mismatch',
        'The receipt currency does not match its source transfer.',
      );
    }
    _uuid(payload, 'requestKey');
    _date(payload, 'receivedAt');
    final acceptedHeader = _nonNegativeInt(payload, 'acceptedOwnedValueMinor');
    final varianceHeader = _nonNegativeInt(payload, 'varianceOwnedValueMinor');
    final destinationDelta = _nonNegativeInt(
      payload,
      'destinationInventoryDeltaMinor',
    );
    final completed = payload['completedTransfer'];
    final itemCount = _positiveInt(payload, 'itemCount', max: 5000);
    final rawItems = payload['items'];
    if (completed is! bool ||
        rawItems is! List ||
        rawItems.length != itemCount ||
        rawItems.isEmpty ||
        destinationDelta != acceptedHeader) {
      throw const OfflineSyncException(
        'invalid_distributed_transfer_receipt',
        'The receipt header is inconsistent.',
      );
    }
    final allocationRows = await _db
        .customSelect(
          distributed
              ? '''SELECT a.allocation_id AS id,a.quantity_scaled AS quantity,
                a.quantity_scale,a.unit_cost_minor AS unit_cost_cents,a.owner_type
                FROM distributed_transfer_outbound_allocations a
                JOIN distributed_transfer_outbound_dispatches d
                  ON d.dispatch_id=a.dispatch_id AND d.sealed=1
                WHERE d.transfer_id=?'''
              : '''SELECT a.id,a.quantity,a.quantity_scale,a.unit_cost_cents,a.owner_type
                FROM warehouse_transfer_allocations a
                JOIN warehouse_transfer_dispatches d ON d.id=a.dispatch_id
                WHERE d.transfer_id=? AND d.sealed=1''',
          variables: [Variable.withString(transferId)],
        )
        .get();
    final allocations = {
      for (final row in allocationRows) row.read<String>('id'): row,
    };
    final receiptEvidenceTable = distributed
        ? 'distributed_outbound_source_receipt_items'
        : 'distributed_transfer_source_receipt_items';
    final parsed = <_RemoteReceiptItem>[];
    final seen = <String>{};
    var acceptedTotal = 0;
    var varianceTotal = 0;
    for (final raw in rawItems) {
      if (raw is! Map) {
        throw const OfflineSyncException(
          'invalid_distributed_transfer_receipt_item',
          'A receipt item has an invalid structure.',
        );
      }
      final item = Map<String, Object?>.from(raw);
      final allocationId = _uuid(item, 'allocationId');
      final allocation = allocations[allocationId];
      if (allocation == null || !seen.add(allocationId)) {
        throw const OfflineSyncException(
          'invalid_distributed_transfer_receipt_item',
          'A receipt allocation is missing or duplicated.',
        );
      }
      final accepted = _nonNegativeInt(item, 'acceptedQuantityScaled');
      final damaged = _nonNegativeInt(item, 'damagedQuantityScaled');
      final lost = _nonNegativeInt(item, 'lostQuantityScaled');
      final total = accepted + damaged + lost;
      if (total <= 0) {
        throw const OfflineSyncException(
          'invalid_distributed_transfer_receipt_item',
          'A receipt item must consume a positive quantity.',
        );
      }
      final consumed = await _db
          .customSelect(
            '''SELECT COALESCE(SUM(accepted_quantity+damaged_quantity+lost_quantity),0) AS quantity
            FROM $receiptEvidenceTable WHERE allocation_id=?''',
            variables: [Variable.withString(allocationId)],
          )
          .map((row) => row.read<int>('quantity'))
          .getSingle();
      final allocationQuantity = allocation.read<int>('quantity');
      if (consumed + total > allocationQuantity) {
        throw const OfflineSyncException(
          'distributed_transfer_receipt_quantity_exceeded',
          'The receipt exceeds its dispatched allocation.',
        );
      }
      final unitCost = allocation.read<int>('unit_cost_cents');
      final scale = allocation.read<int>('quantity_scale');
      int valueAt(int quantity) => MeasuredAmount.cents(
        unitCents: unitCost,
        quantity: quantity,
        quantityScale: scale,
      );
      final expectedAccepted = allocation.read<String>('owner_type') == 'owned'
          ? valueAt(consumed + accepted) - valueAt(consumed)
          : 0;
      final expectedVariance = allocation.read<String>('owner_type') == 'owned'
          ? valueAt(consumed + total) - valueAt(consumed + accepted)
          : 0;
      final acceptedValue = _nonNegativeInt(item, 'acceptedValueMinor');
      final varianceValue = _nonNegativeInt(item, 'varianceValueMinor');
      if (acceptedValue != expectedAccepted ||
          varianceValue != expectedVariance) {
        throw const OfflineSyncException(
          'distributed_transfer_receipt_value_mismatch',
          'A receipt item value does not match the frozen dispatch cost.',
        );
      }
      final destinationBatch = item['destinationBatch'];
      if (destinationBatch != null) {
        if (destinationBatch is! Map) {
          throw const OfflineSyncException(
            'invalid_distributed_transfer_destination_batch',
            'The destination batch identity is invalid.',
          );
        }
        final batch = Map<String, Object?>.from(destinationBatch);
        _uuid(batch, 'globalId');
        if (_uuid(batch, 'originDatabaseId') != event.sourceDatabaseId) {
          throw const OfflineSyncException(
            'invalid_distributed_transfer_destination_batch',
            'The destination batch belongs to another database.',
          );
        }
      }
      acceptedTotal += acceptedValue;
      varianceTotal += varianceValue;
      parsed.add(
        _RemoteReceiptItem(
          allocationId: allocationId,
          accepted: accepted,
          damaged: damaged,
          lost: lost,
          acceptedValue: acceptedValue,
          varianceValue: varianceValue,
        ),
      );
    }
    if (acceptedTotal != acceptedHeader || varianceTotal != varianceHeader) {
      throw const OfflineSyncException(
        'distributed_transfer_receipt_value_mismatch',
        'The receipt totals do not match its items.',
      );
    }
    var hasOutstanding = false;
    for (final allocation in allocations.values) {
      final current = await _db
          .customSelect(
            '''SELECT COALESCE(SUM(accepted_quantity+damaged_quantity+lost_quantity),0) AS quantity
            FROM $receiptEvidenceTable WHERE allocation_id=?''',
            variables: [Variable.withString(allocation.read<String>('id'))],
          )
          .map((row) => row.read<int>('quantity'))
          .getSingle();
      final incoming = parsed
          .where((item) => item.allocationId == allocation.read<String>('id'))
          .fold<int>(0, (sum, item) => sum + item.total);
      if (current + incoming < allocation.read<int>('quantity')) {
        hasOutstanding = true;
      }
    }
    if (completed == hasOutstanding) {
      throw const OfflineSyncException(
        'distributed_transfer_completion_mismatch',
        'The receipt completion flag does not match the allocation balances.',
      );
    }
    await _insertRemoteEvent(event, transferId, sourceWarehouseId);
    for (final item in parsed) {
      await _db.customStatement(
        '''INSERT INTO $receiptEvidenceTable(
          event_id,allocation_id,accepted_quantity,damaged_quantity,
          lost_quantity,accepted_value_minor,variance_value_minor)
          VALUES(?,?,?,?,?,?,?)''',
        [
          event.eventId,
          item.allocationId,
          item.accepted,
          item.damaged,
          item.lost,
          item.acceptedValue,
          item.varianceValue,
        ],
      );
    }
    if (distributed) {
      await _db.customStatement(
        'UPDATE distributed_transfer_outbound_documents SET status=?, '
        'updated_at=CURRENT_TIMESTAMP WHERE transfer_id=?',
        [completed ? 'completed' : 'partially_received', transferId],
      );
    }
  }

  Future<void> _applyRecall(SyncEventEnvelope event) async {
    final payload = event.payload;
    _requireContract(event, payload, expected: 'warehouse_transfer.recalled');
    final transferId = _uuid(payload, 'transferId');
    final organizationId = _uuid(payload, 'organizationId');
    final destinationWarehouseId = _uuid(payload, 'destinationWarehouseId');
    if (event.aggregateId != transferId ||
        event.aggregateType != 'warehouse_transfer' ||
        organizationId != event.organizationId) {
      throw const OfflineSyncException(
        'distributed_transfer_recall_identity_mismatch',
        'The recall event does not match its transfer.',
      );
    }
    final local = await _localTarget(
      organizationId: organizationId,
      warehouseId: destinationWarehouseId,
    );
    if (local == null) return;
    final inbound = await _db
        .customSelect(
          'SELECT lifecycle_state FROM distributed_transfer_inbound_dispatches '
          'WHERE transfer_id=? AND source_database_id=?',
          variables: [
            Variable.withString(transferId),
            Variable.withString(event.sourceDatabaseId),
          ],
        )
        .getSingleOrNull();
    if (inbound == null) {
      throw const OfflineSyncException(
        'distributed_transfer_dispatch_missing',
        'The recalled dispatch has not reached this branch.',
      );
    }
    final state = inbound.read<String>('lifecycle_state');
    if (state == 'awaiting_receipt') {
      await _db.customStatement(
        "UPDATE distributed_transfer_inbound_dispatches SET lifecycle_state='recalled',updated_at=CURRENT_TIMESTAMP WHERE transfer_id=?",
        [transferId],
      );
      return;
    }
    if (state != 'recalled') {
      await _db.customStatement(
        "UPDATE distributed_transfer_inbound_dispatches SET lifecycle_state='conflict',updated_at=CURRENT_TIMESTAMP WHERE transfer_id=?",
        [transferId],
      );
    }
  }

  Future<void> _insertRemoteEvent(
    SyncEventEnvelope event,
    String transferId,
    String localWarehouseId,
  ) => _db.customStatement(
    '''INSERT INTO distributed_transfer_remote_events(
      event_id,transfer_id,event_type,source_database_id,source_branch_id,
      local_warehouse_id,payload_json,payload_hash,occurred_at)
      VALUES(?,?,?,?,?,?,?,?,?)''',
    [
      event.eventId,
      transferId,
      event.eventType,
      event.sourceDatabaseId,
      event.branchId,
      localWarehouseId,
      jsonEncode(event.payload),
      event.eventHash,
      event.occurredAt.toIso8601String(),
    ],
  );

  /// Rechecks documents parked before their catalogue page arrived.
  Future<int> refreshCatalogueReadiness() async {
    final transfers = await _db
        .customSelect(
          "SELECT transfer_id FROM distributed_transfer_inbound_dispatches WHERE catalogue_state='awaiting_catalogue'",
        )
        .get();
    var changed = 0;
    for (final transfer in transfers) {
      final transferId = transfer.read<String>('transfer_id');
      final rows = await _db
          .customSelect(
            'SELECT product_global_id,variant_global_id,owner_type,'
            'supplier_global_id FROM distributed_transfer_inbound_allocations '
            'WHERE transfer_id=?',
            variables: [Variable.withString(transferId)],
          )
          .get();
      var ready = rows.isNotEmpty;
      for (final row in rows) {
        ready =
            ready &&
            await _globalIdentityExists(
              'product',
              row.read<String>('product_global_id'),
            ) &&
            await _globalIdentityExists(
              'product_variant',
              row.read<String>('variant_global_id'),
            );
        if (row.readNullable<String>('supplier_global_id') != null) {
          ready =
              ready &&
              await _globalIdentityExists(
                'supplier',
                row.read<String>('supplier_global_id'),
              );
        }
      }
      if (ready) {
        await _db.customStatement(
          "UPDATE distributed_transfer_inbound_dispatches SET catalogue_state='ready',updated_at=CURRENT_TIMESTAMP WHERE transfer_id=? AND catalogue_state='awaiting_catalogue'",
          [transferId],
        );
        changed++;
      }
    }
    return changed;
  }

  Future<bool> _catalogueIsMapped(_InboundAllocation allocation) async {
    if (!await _globalIdentityExists('product', allocation.productGlobalId) ||
        !await _globalIdentityExists(
          'product_variant',
          allocation.variantGlobalId,
        )) {
      return false;
    }
    return allocation.supplierGlobalId == null ||
        await _globalIdentityExists('supplier', allocation.supplierGlobalId!);
  }

  Future<bool> _globalIdentityExists(String type, String globalId) async =>
      await _db
          .customSelect(
            'SELECT 1 AS found FROM sync_entity_identities '
            'WHERE entity_type=? AND global_id=?',
            variables: [
              Variable.withString(type),
              Variable.withString(globalId),
            ],
          )
          .getSingleOrNull() !=
      null;

  Future<bool> _currencyExists(String code) async =>
      await _db
          .customSelect(
            'SELECT 1 AS found FROM currencies WHERE code=?',
            variables: [Variable.withString(code)],
          )
          .getSingleOrNull() !=
      null;

  Future<_LocalTarget?> _localTarget({
    required String organizationId,
    required String warehouseId,
  }) async {
    final row = await _db
        .customSelect(
          '''SELECT c.database_id,c.branch_id
          FROM business_contexts c
          JOIN business_warehouses w
            ON w.id=? AND w.organization_id=c.organization_id
             AND w.branch_id=c.branch_id AND w.is_active=1
          WHERE c.id=1 AND c.organization_id=?''',
          variables: [
            Variable.withString(warehouseId),
            Variable.withString(organizationId),
          ],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : _LocalTarget(
            databaseId: row.read<String>('database_id'),
            branchId: row.read<String>('branch_id'),
          );
  }

  void _requireContract(
    SyncEventEnvelope event,
    Map<String, Object?> payload, {
    required String expected,
  }) {
    if (event.contractVersion != 1 ||
        payload['contractVersion'] != 1 ||
        payload['contract'] != expected) {
      throw const OfflineSyncException(
        'invalid_distributed_transfer_contract',
        'The distributed transfer contract is invalid.',
      );
    }
  }

  static String _uuid(Map<String, Object?> map, String key) {
    final value = map[key]?.toString() ?? '';
    if (!Uuid.isValidUUID(fromString: value)) {
      throw OfflineSyncException(
        'invalid_distributed_transfer_field',
        'The distributed transfer field $key is invalid.',
      );
    }
    return value.toLowerCase();
  }

  static String _text(Map<String, Object?> map, String key, {int max = 500}) {
    final value = map[key]?.toString() ?? '';
    if (value.isEmpty || value.length > max) {
      throw OfflineSyncException(
        'invalid_distributed_transfer_field',
        'The distributed transfer field $key is invalid.',
      );
    }
    return value;
  }

  static int _positiveInt(
    Map<String, Object?> map,
    String key, {
    int max = 9007199254740991,
  }) {
    final value = map[key];
    if (value is! int || value <= 0 || value > max) {
      throw OfflineSyncException(
        'invalid_distributed_transfer_field',
        'The distributed transfer field $key is invalid.',
      );
    }
    return value;
  }

  static int _nonNegativeInt(Map<String, Object?> map, String key) {
    final value = map[key];
    if (value is! int || value < 0 || value > 9007199254740991) {
      throw OfflineSyncException(
        'invalid_distributed_transfer_field',
        'The distributed transfer field $key is invalid.',
      );
    }
    return value;
  }

  static DateTime _date(Map<String, Object?> map, String key) {
    final value = DateTime.tryParse(map[key]?.toString() ?? '')?.toUtc();
    if (value == null) {
      throw OfflineSyncException(
        'invalid_distributed_transfer_field',
        'The distributed transfer field $key is invalid.',
      );
    }
    return value;
  }
}

class _InboundAllocation {
  const _InboundAllocation({
    required this.id,
    required this.sequence,
    required this.productGlobalId,
    required this.variantGlobalId,
    required this.ownerType,
    required this.quantity,
    required this.scale,
    required this.measurementType,
    required this.unitCostMinor,
    required this.valueMinor,
    this.supplierGlobalId,
    this.agreementId,
    this.sourceConsignmentLayerId,
    this.sourceBatch,
    this.originSlices,
    this.consignmentTerms,
    this.manufacturerLotNumber,
    this.expiryDate,
  });

  final String id;
  final int sequence;
  final String productGlobalId;
  final String variantGlobalId;
  final String ownerType;
  final int quantity;
  final int scale;
  final String measurementType;
  final int unitCostMinor;
  final int valueMinor;
  final String? supplierGlobalId;
  final String? agreementId;
  final String? sourceConsignmentLayerId;
  final Map<String, Object?>? sourceBatch;
  final List<Object?>? originSlices;
  final Map<String, Object?>? consignmentTerms;
  final String? manufacturerLotNumber;
  final DateTime? expiryDate;

  factory _InboundAllocation.parse(Map<String, Object?> map) {
    final id = BranchOperationalProjectionService._uuid(map, 'allocationId');
    final product = BranchOperationalProjectionService._uuid(
      map,
      'productGlobalId',
    );
    final variant = BranchOperationalProjectionService._uuid(
      map,
      'variantGlobalId',
    );
    final sequence = BranchOperationalProjectionService._positiveInt(
      map,
      'sequence',
      max: 5000,
    );
    final owner = map['ownerType']?.toString() ?? '';
    final quantity = BranchOperationalProjectionService._positiveInt(
      map,
      'quantityScaled',
    );
    final scale = BranchOperationalProjectionService._positiveInt(
      map,
      'quantityScale',
      max: 1000,
    );
    final measurement = map['measurementType']?.toString() ?? '';
    if (!{'owned', 'consignment'}.contains(owner) ||
        !{1, 1000}.contains(scale) ||
        !{'piece', 'weight', 'length', 'volume'}.contains(measurement) ||
        (measurement == 'piece') != (scale == 1)) {
      throw const OfflineSyncException(
        'invalid_distributed_transfer_allocation',
        'A transfer allocation has invalid ownership or measurement data.',
      );
    }
    final unitCost = BranchOperationalProjectionService._nonNegativeInt(
      map,
      'unitCostMinor',
    );
    final value = BranchOperationalProjectionService._nonNegativeInt(
      map,
      'valueMinor',
    );
    final supplier = map['supplierGlobalId'] == null
        ? null
        : BranchOperationalProjectionService._uuid(map, 'supplierGlobalId');
    final agreement = map['consignmentAgreementId']?.toString();
    final layer = map['sourceConsignmentLayerId']?.toString();
    if ((owner == 'owned' && (agreement != null || layer != null)) ||
        (owner == 'consignment' &&
            (supplier == null ||
                agreement == null ||
                agreement.isEmpty ||
                layer == null ||
                layer.isEmpty ||
                value != 0))) {
      throw const OfflineSyncException(
        'invalid_distributed_transfer_ownership',
        'A transfer allocation has inconsistent ownership evidence.',
      );
    }
    final batch = map['sourceBatch'];
    final origins = map['originSlices'];
    final terms = map['consignmentTerms'];
    if (batch != null && batch is! Map ||
        origins != null && origins is! List ||
        terms != null && terms is! Map ||
        owner == 'consignment' && terms == null ||
        owner == 'owned' && terms != null) {
      throw const OfflineSyncException(
        'invalid_distributed_transfer_origin',
        'A transfer allocation has invalid origin evidence.',
      );
    }
    final lot = map['manufacturerLotNumber']?.toString();
    final expiryRaw = map['expiryDate']?.toString();
    final expiry = expiryRaw == null
        ? null
        : DateTime.tryParse(expiryRaw)?.toUtc();
    if (expiryRaw != null && expiry == null ||
        lot != null && lot.length > 100) {
      throw const OfflineSyncException(
        'invalid_distributed_transfer_batch',
        'A transfer allocation has invalid batch evidence.',
      );
    }
    return _InboundAllocation(
      id: id,
      sequence: sequence,
      productGlobalId: product,
      variantGlobalId: variant,
      ownerType: owner,
      quantity: quantity,
      scale: scale,
      measurementType: measurement,
      unitCostMinor: unitCost,
      valueMinor: value,
      supplierGlobalId: supplier,
      agreementId: agreement,
      sourceConsignmentLayerId: layer,
      sourceBatch: batch == null
          ? null
          : Map<String, Object?>.from(batch as Map),
      originSlices: origins == null
          ? null
          : List<Object?>.from(origins as List),
      consignmentTerms: terms == null
          ? null
          : Map<String, Object?>.from(terms as Map),
      manufacturerLotNumber: lot,
      expiryDate: expiry,
    );
  }
}

class _LocalTarget {
  const _LocalTarget({required this.databaseId, required this.branchId});

  final String databaseId;
  final String branchId;
}

class _RemoteReceiptItem {
  const _RemoteReceiptItem({
    required this.allocationId,
    required this.accepted,
    required this.damaged,
    required this.lost,
    required this.acceptedValue,
    required this.varianceValue,
  });

  final String allocationId;
  final int accepted;
  final int damaged;
  final int lost;
  final int acceptedValue;
  final int varianceValue;

  int get total => accepted + damaged + lost;
}
