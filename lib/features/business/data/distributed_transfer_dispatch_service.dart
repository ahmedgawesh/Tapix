import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/measurement/measurement.dart';
import '../../../core/services/batch_service.dart';
import '../../../core/services/business/branch_currency_policy_store.dart';
import '../../../core/services/business/warehouse_batch_scope.dart';
import '../../../core/services/business/warehouse_inventory_reader.dart';
import '../../../core/services/business/warehouse_operation_scope.dart';
import '../../../core/services/inventory/wac_movement_service.dart';
import '../../../core/services/stock_service.dart';
import '../../../core/services/sync/offline_sync_event_store.dart';
import '../../../core/services/sync/sync_entity_identity_store.dart';
import '../../accounting/data/repositories/accounting_repository.dart';
import '../../accounting/domain/models/journal_entry_data.dart';

class DistributedTransferLineInput {
  const DistributedTransferLineInput({
    required this.productId,
    required this.variantId,
    required this.quantity,
    this.ownedQuantity,
    this.consignmentQuantity,
  });
  final int productId, variantId, quantity;
  final int? ownedQuantity, consignmentQuantity;
}

class DistributedTransferLocation {
  const DistributedTransferLocation({
    required this.warehouseId,
    required this.warehouseCode,
    required this.warehouseName,
    required this.branchId,
    required this.branchCode,
    required this.branchName,
    required this.databaseId,
    required this.locationKind,
  });
  final String warehouseId, warehouseCode, warehouseName;
  final String branchId, branchCode, branchName, databaseId, locationKind;
}

class DistributedOutboundDocument {
  const DistributedOutboundDocument({
    required this.transferId,
    required this.sourceWarehouseId,
    required this.destinationWarehouseId,
    required this.status,
    required this.lineCount,
    required this.notes,
  });
  final String transferId, sourceWarehouseId, destinationWarehouseId, status;
  final int lineCount;
  final String notes;
  bool get recalled => status == 'recalled';
}

/// Posts the source half of a transfer addressed to another branch database.
/// Remote directory rows are routing identities and never become local stock.
class DistributedTransferDispatchService {
  DistributedTransferDispatchService(
    this.db, {
    required this.authorize,
    AccountingRepository? accounting,
    OfflineSyncEventStore? syncEvents,
    SyncEntityIdentityStore? identities,
    this.uuid = const Uuid(),
  }) : accounting = accounting ?? AccountingRepository(db),
       syncEvents = syncEvents ?? OfflineSyncEventStore(db),
       identities = identities ?? SyncEntityIdentityStore(db);

  final AppDatabase db;
  final Future<int> Function(String, String) authorize;
  final AccountingRepository accounting;
  final OfflineSyncEventStore syncEvents;
  final SyncEntityIdentityStore identities;
  final Uuid uuid;

  static String _key(String value, String name) {
    final result = value.trim().toLowerCase();
    if (!Uuid.isValidUUID(fromString: result)) {
      throw ArgumentError.value(value, name, 'A stable UUID is required');
    }
    return result;
  }

  static String _hash(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  Future<List<DistributedTransferLocation>> remoteLocations() async {
    final local = await WarehouseOperationScope.resolve(db);
    final rows = await db
        .customSelect(
          '''SELECT w.warehouse_id,w.code AS warehouse_code,w.name AS warehouse_name,
      w.location_kind,b.branch_id,b.code AS branch_code,b.name AS branch_name,
      b.writer_database_id
      FROM sync_warehouse_directory w JOIN sync_branch_directory b
        ON b.branch_id=w.branch_id
      WHERE w.organization_id=? AND w.is_active=1 AND b.is_active=1
        AND b.writer_database_id IS NOT NULL
        AND b.writer_database_id<>? AND b.branch_id<>?
      ORDER BY b.name,w.name''',
          variables: [
            Variable.withString(local.organizationId),
            Variable.withString(local.databaseId),
            Variable.withString(local.branchId),
          ],
        )
        .get();
    return List.unmodifiable(
      rows.map(
        (r) => DistributedTransferLocation(
          warehouseId: r.read<String>('warehouse_id'),
          warehouseCode: r.read<String>('warehouse_code'),
          warehouseName: r.read<String>('warehouse_name'),
          branchId: r.read<String>('branch_id'),
          branchCode: r.read<String>('branch_code'),
          branchName: r.read<String>('branch_name'),
          databaseId: r.read<String>('writer_database_id'),
          locationKind: r.read<String>('location_kind'),
        ),
      ),
    );
  }

  Future<bool> owns(String id) async =>
      await db
          .customSelect(
            'SELECT 1 AS found FROM distributed_transfer_outbound_documents WHERE transfer_id=?',
            variables: [Variable.withString(id)],
          )
          .getSingleOrNull() !=
      null;

  Future<List<DistributedOutboundDocument>> list(
    Set<String> statuses, {
    int limit = 100,
  }) async {
    const valid = {
      'draft',
      'in_transit',
      'recall_pending',
      'partially_received',
      'completed',
      'cancelled',
      'recalled',
      'conflict',
    };
    if (statuses.isEmpty ||
        !valid.containsAll(statuses) ||
        limit < 1 ||
        limit > 500) {
      throw ArgumentError('Invalid distributed transfer filter');
    }
    final marks = List.filled(statuses.length, '?').join(',');
    final rows = await db
        .customSelect(
          '''SELECT * FROM (
            SELECT d.*,
              CASE
                WHEN r.status='pending' THEN 'recall_pending'
                WHEN r.status='rejected' AND d.status='in_transit' THEN 'conflict'
                ELSE d.status
              END AS effective_status
            FROM distributed_transfer_outbound_documents d
            LEFT JOIN distributed_transfer_outbound_recall_requests r
              ON r.transfer_id=d.transfer_id
          ) WHERE effective_status IN ($marks)
          ORDER BY created_at DESC LIMIT ?''',
          variables: [
            ...statuses.map(Variable.withString),
            Variable.withInt(limit),
          ],
        )
        .get();
    return List.unmodifiable(
      rows.map((row) => _document(row, effective: true)),
    );
  }

  Future<DistributedOutboundDocument> create({
    required String requestKey,
    required String sourceWarehouseId,
    required String destinationWarehouseId,
    required List<DistributedTransferLineInput> lines,
    String notes = '',
  }) => db.transaction(() async {
    final key = _key(requestKey, 'requestKey');
    final sourceId = _key(sourceWarehouseId, 'sourceWarehouseId');
    final targetId = _key(destinationWarehouseId, 'destinationWarehouseId');
    final cleanNotes = notes.trim();
    if (sourceId == targetId ||
        lines.isEmpty ||
        lines.length > 500 ||
        cleanNotes.length > 500) {
      throw ArgumentError('Invalid distributed transfer intent');
    }
    final actor = await authorize(sourceId, targetId);
    final source = await WarehouseOperationScope.resolve(
      db,
      warehouseId: sourceId,
    );
    final target = await _target(targetId, source);
    final currency = await BranchCurrencyPolicyStore(db).read();
    if (currency == null) throw StateError('Bind operating currency first');
    await BranchCurrencyPolicyStore(
      db,
    ).requireCurrency(currency.id, requireBinding: true);

    final ordered = [...lines]
      ..sort((a, b) => a.variantId.compareTo(b.variantId));
    final seen = <int>{};
    final verified = <_Line>[];
    for (final input in ordered) {
      final explicit =
          input.ownedQuantity != null || input.consignmentQuantity != null;
      if (!seen.add(input.variantId) ||
          input.quantity <= 0 ||
          input.quantity > 9007199254740991 ||
          explicit &&
              (input.ownedQuantity == null ||
                  input.consignmentQuantity == null ||
                  input.ownedQuantity! < 0 ||
                  input.consignmentQuantity! < 0 ||
                  input.ownedQuantity! + input.consignmentQuantity! !=
                      input.quantity)) {
        throw ArgumentError('Invalid transfer line');
      }
      final row = await db
          .customSelect(
            '''SELECT p.currency_id,p.measurement_type,p.track_inventory,
        p.is_active AS product_active,v.is_active AS variant_active,
        s.quantity,s.supplier_owned_quantity
        FROM products p JOIN product_variants v ON v.product_id=p.id
        JOIN business_warehouse_stocks s
          ON s.variant_id=v.id AND s.warehouse_id=?
        WHERE p.id=? AND v.id=?''',
            variables: [
              Variable.withString(sourceId),
              Variable.withInt(input.productId),
              Variable.withInt(input.variantId),
            ],
          )
          .getSingleOrNull();
      if (row == null ||
          row.read<int>('product_active') != 1 ||
          row.read<int>('variant_active') != 1 ||
          row.read<int>('track_inventory') != 1 ||
          row.readNullable<int>('currency_id') != currency.id ||
          row.read<int>('quantity') < input.quantity) {
        throw StateError('Transfer source stock is unavailable');
      }
      final supplierOwned = row.read<int>('supplier_owned_quantity');
      final total = row.read<int>('quantity');
      if (supplierOwned < 0 ||
          supplierOwned > total ||
          explicit &&
              (input.ownedQuantity! > total - supplierOwned ||
                  input.consignmentQuantity! > supplierOwned)) {
        throw StateError('Selected ownership balance is unavailable');
      }
      final measurement = row.read<String>('measurement_type');
      verified.add(
        _Line(
          id: uuid.v4(),
          productId: input.productId,
          variantId: input.variantId,
          quantity: input.quantity,
          scale: measurement == 'piece' ? 1 : 1000,
          measurement: measurement,
          owned: input.ownedQuantity,
          consignment: input.consignmentQuantity,
        ),
      );
    }
    final requestHash = _hash({
      'version': 1,
      'organization': source.organizationId,
      'sourceDatabase': source.databaseId,
      'sourceBranch': source.branchId,
      'sourceWarehouse': sourceId,
      'destinationDatabase': target.databaseId,
      'destinationBranch': target.branchId,
      'destinationWarehouse': targetId,
      'currency': currency.code,
      'actor': actor,
      'notes': cleanNotes,
      'lines': [
        for (final l in verified)
          [
            l.productId,
            l.variantId,
            l.quantity,
            l.scale,
            l.measurement,
            l.owned,
            l.consignment,
          ],
      ],
    });
    final replay = await db
        .customSelect(
          'SELECT * FROM distributed_transfer_outbound_documents WHERE request_key=?',
          variables: [Variable.withString(key)],
        )
        .getSingleOrNull();
    if (replay != null) {
      if (replay.read<String>('request_hash') != requestHash) {
        throw StateError('Transfer request key belongs to another operation');
      }
      return _document(replay);
    }

    final id = uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await db.customStatement(
      '''INSERT INTO distributed_transfer_outbound_documents(
      transfer_id,organization_id,source_database_id,source_branch_id,
      source_warehouse_id,destination_database_id,destination_branch_id,
      destination_warehouse_id,currency_id,currency_code,created_by,
      request_key,request_hash,notes,line_count,status,created_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'draft',?,?)''',
      [
        id,
        source.organizationId,
        source.databaseId,
        source.branchId,
        sourceId,
        target.databaseId,
        target.branchId,
        targetId,
        currency.id,
        currency.code,
        actor,
        key,
        requestHash,
        cleanNotes,
        verified.length,
        now,
        now,
      ],
    );
    for (final l in verified) {
      await db.customStatement(
        '''INSERT INTO distributed_transfer_outbound_lines(
        line_id,transfer_id,product_id,variant_id,quantity_scaled,
        quantity_scale,measurement_type,requested_owned_quantity,
        requested_consignment_quantity) VALUES(?,?,?,?,?,?,?,?,?)''',
        [
          l.id,
          id,
          l.productId,
          l.variantId,
          l.quantity,
          l.scale,
          l.measurement,
          l.owned,
          l.consignment,
        ],
      );
    }
    return _document(await _header(id));
  });

  Future<void> cancel({
    required String transferId,
    required String requestKey,
    required String reason,
  }) => db.transaction(() async {
    final id = _key(transferId, 'transferId');
    _key(requestKey, 'requestKey');
    if (reason.trim().isEmpty || reason.trim().length > 500) {
      throw ArgumentError('A cancellation reason is required');
    }
    final h = await _header(id);
    await authorize(
      h.read<String>('source_warehouse_id'),
      h.read<String>('destination_warehouse_id'),
    );
    if (h.read<String>('status') == 'cancelled') return;
    if (h.read<String>('status') != 'draft') {
      throw StateError('Only a draft transfer can be cancelled');
    }
    final changed = await db.customUpdate(
      "UPDATE distributed_transfer_outbound_documents SET status='cancelled',"
      "updated_at=? WHERE transfer_id=? AND status='draft'",
      variables: [
        Variable.withString(DateTime.now().toUtc().toIso8601String()),
        Variable.withString(id),
      ],
    );
    if (changed != 1) throw StateError('Transfer state changed');
  });

  Future<void> dispatch({
    required String transferId,
    required String requestKey,
    DateTime? dispatchedAt,
  }) => syncEvents.transaction((sync) async {
    final id = _key(transferId, 'transferId');
    final key = _key(requestKey, 'requestKey');
    final h = await _header(id);
    final actor = await authorize(
      h.read<String>('source_warehouse_id'),
      h.read<String>('destination_warehouse_id'),
    );
    final requestHash = _hash({
      'version': 1,
      'kind': 'distributed_transfer_dispatch',
      'transfer': id,
      'actor': actor,
    });
    final replay = await db
        .customSelect(
          'SELECT sealed,payload_json,dispatched_at,request_hash '
          'FROM distributed_transfer_outbound_dispatches WHERE request_key=?',
          variables: [Variable.withString(key)],
        )
        .getSingleOrNull();
    if (replay != null) {
      if (replay.read<int>('sealed') != 1 ||
          replay.read<String>('request_hash') != requestHash) {
        throw StateError('Dispatch request key belongs to another operation');
      }
      return _appendDispatch(
        sync,
        id,
        Map<String, Object?>.from(
          jsonDecode(replay.read<String>('payload_json')) as Map,
        ),
        DateTime.parse(replay.read<String>('dispatched_at')).toUtc(),
      );
    }
    if (h.read<String>('status') != 'draft') {
      throw StateError('Only a draft transfer can be dispatched');
    }
    final source = await WarehouseOperationScope.resolve(
      db,
      warehouseId: h.read<String>('source_warehouse_id'),
    );
    await _target(
      h.read<String>('destination_warehouse_id'),
      source,
      expectedDatabase: h.read<String>('destination_database_id'),
    );
    final lines = await _lines(id);
    if (lines.length != h.read<int>('line_count')) {
      throw StateError('Transfer line count changed');
    }
    final terms = <String, Map<String, Object?>>{};
    final plans = <_Plan>[];
    for (final line in lines) {
      plans.addAll(await _plan(line, source, terms));
    }
    if (plans.isEmpty || plans.length > 5000) {
      throw StateError('Invalid transfer allocation count');
    }
    final ownedValue = plans
        .where((p) => !p.isConsignment)
        .fold<int>(0, (n, p) => n + p.value);
    final at = (dispatchedAt ?? DateTime.now()).toUtc();
    final dispatchId = await db.customInsert(
      '''INSERT INTO distributed_transfer_outbound_dispatches(
      transfer_id,request_key,request_hash,actor_id,allocation_count,
      owned_value_minor,payload_json,payload_hash,dispatched_at)
      VALUES(?,?,?,?,?,?,'{}',?,?)''',
      variables: [
        Variable.withString(id),
        Variable.withString(key),
        Variable.withString(requestHash),
        Variable.withInt(actor),
        Variable.withInt(plans.length),
        Variable.withInt(ownedValue),
        Variable.withString('0' * 64),
        Variable.withString(at.toIso8601String()),
      ],
    );
    final payloadAllocations = <Map<String, Object?>>[];
    final touched = <int>{}, tracked = <int>{};
    for (var i = 0; i < plans.length; i++) {
      final p = plans[i];
      final consumptionId = await _remove(p, source);
      final origins = p.isConsignment || p.tracked
          ? const <Map<String, Object?>>[]
          : await _originSlices(p, source);
      await db.customStatement(
        '''INSERT INTO distributed_transfer_outbound_allocations(
        allocation_id,dispatch_id,line_id,sequence,owner_type,
        quantity_scaled,quantity_scale,measurement_type,unit_cost_minor,
        value_minor,source_batch_id,source_consignment_layer_id,supplier_id,
        agreement_id,manufacturer_lot_number,expiry_date,origin_slices_json,
        consignment_terms_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
        [
          p.id,
          dispatchId,
          p.line.id,
          i + 1,
          p.isConsignment ? 'consignment' : 'owned',
          p.quantity,
          p.line.scale,
          p.line.measurement,
          p.unitCost,
          p.value,
          p.batchId,
          p.layer?.id,
          p.supplierId,
          p.layer?.agreementId,
          p.lot,
          p.expiry?.toIso8601String(),
          origins.isEmpty ? null : jsonEncode(origins),
          p.terms == null ? null : jsonEncode(p.terms),
        ],
      );
      if (consumptionId != null) {
        await db.customStatement(
          'INSERT INTO distributed_transfer_outbound_batch_links'
          '(allocation_id,consumption_id) VALUES(?,?)',
          [p.id, consumptionId],
        );
      }
      payloadAllocations.add(await _eventAllocation(p, i + 1, origins));
      touched.add(p.line.productId);
      if (p.tracked) tracked.add(p.line.productId);
    }
    for (final productId in touched) {
      await StockService.syncProductStockFromVariants(
        db.productDao,
        productId: productId,
        scope: source,
      );
      if (tracked.contains(productId)) {
        await WarehouseInventoryReader.assertBatches(
          db.productDao,
          scope: source,
          productId: productId,
        );
      }
    }
    int? journalId;
    if (ownedValue > 0) {
      final accounts = await _accounts({'1200', '1210'});
      journalId = await accounting.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Distributed warehouse transfer dispatch $id',
          debitAccountId: accounts['1210']!.id,
          creditAccountId: accounts['1200']!.id,
          amountCents: ownedValue,
          currencyId: h.read<int>('currency_id'),
          entryDate: at,
          entryType: 'warehouse_transfer_dispatch',
          sourceTable: 'distributed_transfer_outbound_dispatches',
          sourceId: dispatchId,
        ),
        userId: actor,
      );
    }
    final payload = <String, Object?>{
      'contract': 'warehouse_transfer.dispatched',
      'contractVersion': 1,
      'transferId': id,
      'requestKey': key,
      'organizationId': h.read<String>('organization_id'),
      'branchId': h.read<String>('source_branch_id'),
      'sourceDatabaseId': h.read<String>('source_database_id'),
      'sourceWarehouseId': h.read<String>('source_warehouse_id'),
      'destinationWarehouseId': h.read<String>('destination_warehouse_id'),
      'currencyCode': h.read<String>('currency_code'),
      'dispatchedAt': at.toIso8601String(),
      'actorRef': {
        'databaseId': h.read<String>('source_database_id'),
        'localId': actor,
      },
      'ownedValueMinor': ownedValue,
      'allocationCount': payloadAllocations.length,
      'allocations': payloadAllocations,
    };
    await db.customStatement(
      'UPDATE distributed_transfer_outbound_dispatches SET '
      'journal_entry_id=?,payload_json=?,payload_hash=?,sealed=1 '
      'WHERE dispatch_id=? AND sealed=0',
      [journalId, jsonEncode(payload), _hash(payload), dispatchId],
    );
    final changed = await db.customUpdate(
      "UPDATE distributed_transfer_outbound_documents SET status='in_transit',"
      "updated_at=? WHERE transfer_id=? AND status='draft'",
      variables: [
        Variable.withString(at.toIso8601String()),
        Variable.withString(id),
      ],
    );
    if (changed != 1) throw StateError('Transfer state changed');
    await _appendDispatch(sync, id, payload, at);
  });

  Future<void> recall({
    required String transferId,
    required String requestKey,
    required String reason,
  }) => syncEvents.transaction((sync) async {
    final id = _key(transferId, 'transferId');
    final key = _key(requestKey, 'requestKey');
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 500) {
      throw ArgumentError('A recall reason is required');
    }
    final h = await _header(id);
    final actor = await authorize(
      h.read<String>('source_warehouse_id'),
      h.read<String>('destination_warehouse_id'),
    );
    final requestHash = _hash({
      'version': 1,
      'kind': 'distributed_transfer_recall_request',
      'transfer': id,
      'actor': actor,
      'reason': cleanReason,
    });
    final replay = await db
        .customSelect(
          'SELECT request_hash FROM distributed_transfer_outbound_recall_requests '
          'WHERE request_key=?',
          variables: [Variable.withString(key)],
        )
        .getSingleOrNull();
    if (replay != null) {
      if (replay.read<String>('request_hash') != requestHash) {
        throw StateError('Recall request key belongs to another operation');
      }
      return;
    }
    final prior = await db
        .customSelect(
          'SELECT status FROM distributed_transfer_outbound_recall_requests '
          'WHERE transfer_id=?',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (prior != null) {
      throw StateError(
        prior.read<String>('status') == 'pending'
            ? 'distributed_recall_pending'
            : 'distributed_recall_rejected',
      );
    }
    if (h.read<String>('status') != 'in_transit') {
      throw StateError('Only an unreceived transfer can be recalled');
    }
    final evidence = await db
        .customSelect(
          '''SELECT 1 AS found FROM distributed_outbound_source_receipt_items i
      JOIN distributed_transfer_outbound_allocations a
        ON a.allocation_id=i.allocation_id
      JOIN distributed_transfer_outbound_dispatches d
        ON d.dispatch_id=a.dispatch_id
      WHERE d.transfer_id=? LIMIT 1''',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (evidence != null) {
      throw StateError('A remotely received transfer cannot be recalled');
    }
    final at = DateTime.now().toUtc();
    final requestId = uuid.v4();
    await db.customStatement(
      '''INSERT INTO distributed_transfer_outbound_recall_requests(
      request_id,transfer_id,request_key,request_hash,actor_id,reason,requested_at)
      VALUES(?,?,?,?,?,?,?)''',
      [
        requestId,
        id,
        key,
        requestHash,
        actor,
        cleanReason,
        at.toIso8601String(),
      ],
    );
    if (!await sync.isWriterRecordingEnabled()) {
      throw StateError('Distributed recall requires an active LAN writer');
    }
    await sync.appendOnce(
      producerKey: 'warehouse_transfer:$id:recall_requested',
      eventType: 'warehouse_transfer.recall_requested.v1',
      aggregateType: 'warehouse_transfer',
      aggregateId: id,
      occurredAt: at,
      payload: {
        'contract': 'warehouse_transfer.recall_requested',
        'contractVersion': 1,
        'transferId': id,
        'requestId': requestId,
        'requestKey': key,
        'organizationId': h.read<String>('organization_id'),
        'branchId': h.read<String>('source_branch_id'),
        'sourceDatabaseId': h.read<String>('source_database_id'),
        'sourceWarehouseId': h.read<String>('source_warehouse_id'),
        'destinationDatabaseId': h.read<String>('destination_database_id'),
        'destinationBranchId': h.read<String>('destination_branch_id'),
        'destinationWarehouseId': h.read<String>('destination_warehouse_id'),
        'requestedAt': at.toIso8601String(),
        'reason': cleanReason,
      },
    );
  });

  Future<void> applyRecallResolution(
    SyncEventEnvelope response,
  ) => db.transaction(() async {
    final payload = response.payload;
    final id = _key(payload['transferId']?.toString() ?? '', 'transferId');
    final requestId = _key(payload['requestId']?.toString() ?? '', 'requestId');
    final accepted = payload['accepted'];
    final resolvedAt = DateTime.tryParse(
      payload['resolvedAt']?.toString() ?? '',
    )?.toUtc();
    if (response.aggregateType != 'warehouse_transfer' ||
        response.aggregateId != id ||
        response.eventType != 'warehouse_transfer.recall_resolved.v1' ||
        response.contractVersion != 1 ||
        payload['contract'] != 'warehouse_transfer.recall_resolved' ||
        payload['contractVersion'] != 1 ||
        resolvedAt == null ||
        accepted is! bool) {
      throw StateError('Invalid distributed recall response');
    }
    final h = await _header(id);
    if (response.sourceDatabaseId !=
            h.read<String>('destination_database_id') ||
        response.branchId != h.read<String>('destination_branch_id') ||
        response.organizationId != h.read<String>('organization_id') ||
        payload['organizationId'] != h.read<String>('organization_id') ||
        payload['sourceDatabaseId'] != response.sourceDatabaseId ||
        payload['branchId'] != response.branchId ||
        payload['originalSourceDatabaseId'] !=
            h.read<String>('source_database_id') ||
        payload['sourceWarehouseId'] != h.read<String>('source_warehouse_id') ||
        payload['destinationWarehouseId'] !=
            h.read<String>('destination_warehouse_id')) {
      throw StateError('Distributed recall response source mismatch');
    }
    final request = await db
        .customSelect(
          'SELECT * FROM distributed_transfer_outbound_recall_requests '
          "WHERE request_id=? AND transfer_id=? AND status='pending'",
          variables: [Variable.withString(requestId), Variable.withString(id)],
        )
        .getSingleOrNull();
    if (request == null) return;
    final resolutionTime = resolvedAt.toIso8601String();
    if (!accepted) {
      await db.customStatement(
        "UPDATE distributed_transfer_outbound_recall_requests SET status='rejected',response_event_id=?,resolved_at=? WHERE request_id=? AND status='pending'",
        [response.eventId, resolutionTime, requestId],
      );
      return;
    }
    await _finalizeAcceptedRecall(response: response, request: request, h: h);
  });

  Future<void> _finalizeAcceptedRecall({
    required SyncEventEnvelope response,
    required QueryRow request,
    required QueryRow h,
  }) => db.transaction(() async {
    final id = request.read<String>('transfer_id');
    final key = request.read<String>('request_key');
    final cleanReason = request.read<String>('reason');
    final actor = request.read<int>('actor_id');
    final requestHash = request.read<String>('request_hash');
    if (h.read<String>('status') != 'in_transit') {
      throw StateError('Only an unreceived transfer can be recalled');
    }
    final evidence = await db
        .customSelect(
          '''SELECT 1 AS found FROM distributed_outbound_source_receipt_items i
      JOIN distributed_transfer_outbound_allocations a
        ON a.allocation_id=i.allocation_id
      JOIN distributed_transfer_outbound_dispatches d
        ON d.dispatch_id=a.dispatch_id
      WHERE d.transfer_id=? LIMIT 1''',
          variables: [Variable.withString(id)],
        )
        .getSingleOrNull();
    if (evidence != null) {
      throw StateError('A remotely received transfer cannot be recalled');
    }
    final source = await WarehouseOperationScope.resolve(
      db,
      warehouseId: h.read<String>('source_warehouse_id'),
    );
    final allocations = await _allocationRows(id);
    final at = response.occurredAt.toUtc();
    final recallId = uuid.v4();
    final rowId = await db.customInsert(
      '''INSERT INTO distributed_transfer_outbound_recalls(
      recall_id,transfer_id,request_key,request_hash,actor_id,reason,recalled_at)
      VALUES(?,?,?,?,?,?,?)''',
      variables: [
        Variable.withString(recallId),
        Variable.withString(id),
        Variable.withString(key),
        Variable.withString(requestHash),
        Variable.withInt(actor),
        Variable.withString(cleanReason),
        Variable.withString(at.toIso8601String()),
      ],
    );
    var ownedValue = 0;
    final touched = <int>{}, tracked = <int>{};
    for (final row in allocations) {
      final line = _Line.fromRow(row);
      final allocationId = row.read<String>('allocation_id');
      final quantity = row.read<int>('quantity_scaled');
      final owner = row.read<String>('owner_type');
      final batchId = row.readNullable<int>('source_batch_id');
      final wac = owner == 'owned' && batchId == null
          ? await WacMovementService.capture(
              db.productDao,
              productId: line.productId,
              variantId: line.variantId,
              scope: source,
            )
          : null;
      await StockService.adjustStock(
        db.productDao,
        productId: line.productId,
        variantId: line.variantId,
        quantity: quantity,
        direction: StockDirection.increase,
        scope: source,
        origin: InventoryOriginIntent.keyed(
          'transfer_recall',
          'distributed_transfer_recall:$allocationId',
          reference: 'distributed_transfer_out:$allocationId',
          referenceWarehouse: source.warehouseId,
        ),
      );
      if (wac != null) {
        await WacMovementService.applyInbound(
          db.productDao,
          snapshot: wac,
          addedQty: quantity,
          inboundUnitCostCents: row.read<int>('unit_cost_minor'),
        );
      }
      if (owner == 'consignment') {
        final layerChanged = await db.customUpdate(
          'UPDATE consignment_inventory_layers SET '
          "remaining_quantity=remaining_quantity+?,status='open',updated_at=? "
          'WHERE id=? AND remaining_quantity+?<=received_quantity',
          variables: [
            Variable.withInt(quantity),
            Variable.withString(at.toIso8601String()),
            Variable.withString(
              row.read<String>('source_consignment_layer_id'),
            ),
            Variable.withInt(quantity),
          ],
          updates: {db.consignmentInventoryLayers},
        );
        final ownershipChanged = await db.customUpdate(
          'UPDATE business_warehouse_stocks SET '
          'supplier_owned_quantity=supplier_owned_quantity+?,updated_at=? '
          'WHERE warehouse_id=? AND variant_id=? '
          'AND supplier_owned_quantity+?<=quantity',
          variables: [
            Variable.withInt(quantity),
            Variable.withString(at.toIso8601String()),
            Variable.withString(source.warehouseId),
            Variable.withInt(line.variantId),
            Variable.withInt(quantity),
          ],
          updates: {db.businessWarehouseStocks},
        );
        if (layerChanged != 1 || ownershipChanged != 1) {
          throw StateError('Consignment recall evidence changed');
        }
      } else {
        ownedValue += row.read<int>('value_minor');
      }
      if (batchId != null) {
        final link = await db
            .customSelect(
              'SELECT consumption_id FROM distributed_transfer_outbound_batch_links '
              'WHERE allocation_id=?',
              variables: [Variable.withString(allocationId)],
            )
            .getSingle();
        await BatchService.restoreDistributedTransferConsumption(
          db.productDao,
          consumptionId: link.read<int>('consumption_id'),
          expectedBatchId: batchId,
          expectedQuantity: quantity,
          allocationId: allocationId,
          scope: source,
        );
        tracked.add(line.productId);
      }
      touched.add(line.productId);
    }
    for (final productId in touched) {
      await StockService.syncProductStockFromVariants(
        db.productDao,
        productId: productId,
        scope: source,
      );
      if (tracked.contains(productId)) {
        await WarehouseInventoryReader.assertBatches(
          db.productDao,
          scope: source,
          productId: productId,
        );
      }
    }
    int? journalId;
    if (ownedValue > 0) {
      final accounts = await _accounts({'1200', '1210'});
      journalId = await accounting.createJournalEntry(
        entryData: JournalEntryData.simple(
          description: 'Distributed warehouse transfer recall $id',
          debitAccountId: accounts['1200']!.id,
          creditAccountId: accounts['1210']!.id,
          amountCents: ownedValue,
          currencyId: h.read<int>('currency_id'),
          entryDate: at,
          entryType: 'warehouse_transfer_recall',
          sourceTable: 'distributed_transfer_outbound_recalls',
          sourceId: rowId,
        ),
        userId: actor,
      );
    }
    await db.customStatement(
      'UPDATE distributed_transfer_outbound_recalls SET '
      'journal_entry_id=?,sealed=1 WHERE recall_id=? AND sealed=0',
      [journalId, recallId],
    );
    final documentChanged = await db.customUpdate(
      "UPDATE distributed_transfer_outbound_documents SET status='recalled',"
      "updated_at=? WHERE transfer_id=? AND status='in_transit'",
      variables: [
        Variable.withString(at.toIso8601String()),
        Variable.withString(id),
      ],
      updates: const {},
    );
    final requestChanged = await db.customUpdate(
      "UPDATE distributed_transfer_outbound_recall_requests SET status='accepted',response_event_id=?,resolved_at=? WHERE request_id=? AND status='pending'",
      variables: [
        Variable.withString(response.eventId),
        Variable.withString(at.toIso8601String()),
        Variable.withString(request.read<String>('request_id')),
      ],
      updates: const {},
    );
    if (documentChanged != 1 || requestChanged != 1) {
      throw StateError('Distributed recall state changed during confirmation');
    }
  });

  Future<Map<String, Account>> _accounts(Set<String> codes) async {
    final result = {
      for (final a in await (db.select(
        db.accounts,
      )..where((r) => r.accountCode.isIn(codes))).get())
        a.accountCode: a,
    };
    if (!result.keys.toSet().containsAll(codes)) {
      throw StateError('Required transfer inventory accounts are missing');
    }
    return result;
  }

  Future<void> _appendDispatch(
    OfflineSyncTransaction sync,
    String id,
    Map<String, Object?> payload,
    DateTime at,
  ) async {
    if (!await sync.isWriterRecordingEnabled()) {
      throw StateError('Distributed transfer requires an enrolled branch');
    }
    await sync.appendOnce(
      producerKey: 'warehouse_transfer:$id:dispatched',
      eventType: 'warehouse_transfer.dispatched.v1',
      aggregateType: 'warehouse_transfer',
      aggregateId: id,
      occurredAt: at,
      payload: payload,
    );
  }

  Future<_Destination> _target(
    String warehouseId,
    WarehouseOperationScope source, {
    String? expectedDatabase,
  }) async {
    final row = await db
        .customSelect(
          '''SELECT w.organization_id,w.branch_id,b.writer_database_id
      FROM sync_warehouse_directory w JOIN sync_branch_directory b
        ON b.branch_id=w.branch_id
      WHERE w.warehouse_id=? AND w.is_active=1 AND b.is_active=1''',
          variables: [Variable.withString(warehouseId)],
        )
        .getSingleOrNull();
    final database = row?.readNullable<String>('writer_database_id');
    if (row == null ||
        row.read<String>('organization_id') != source.organizationId ||
        row.read<String>('branch_id') == source.branchId ||
        database == null ||
        database == source.databaseId ||
        expectedDatabase != null && expectedDatabase != database) {
      throw StateError('Distributed transfer destination is unavailable');
    }
    return _Destination(database, row.read<String>('branch_id'));
  }

  Future<QueryRow> _header(String id) => db
      .customSelect(
        'SELECT * FROM distributed_transfer_outbound_documents WHERE transfer_id=?',
        variables: [Variable.withString(id)],
      )
      .getSingle();

  Future<List<_Line>> _lines(String id) => db
      .customSelect(
        'SELECT * FROM distributed_transfer_outbound_lines '
        'WHERE transfer_id=? ORDER BY variant_id',
        variables: [Variable.withString(id)],
      )
      .map(_Line.fromRow)
      .get();

  Future<List<QueryRow>> _allocationRows(String id) => db
      .customSelect(
        '''SELECT a.*,l.product_id,l.variant_id,l.quantity_scale,l.measurement_type,
        l.requested_owned_quantity,l.requested_consignment_quantity
    FROM distributed_transfer_outbound_allocations a
    JOIN distributed_transfer_outbound_dispatches d
      ON d.dispatch_id=a.dispatch_id AND d.sealed=1
    JOIN distributed_transfer_outbound_lines l ON l.line_id=a.line_id
    WHERE d.transfer_id=? ORDER BY a.sequence''',
        variables: [Variable.withString(id)],
      )
      .get();

  DistributedOutboundDocument _document(QueryRow r, {bool effective = false}) =>
      DistributedOutboundDocument(
        transferId: r.read<String>('transfer_id'),
        sourceWarehouseId: r.read<String>('source_warehouse_id'),
        destinationWarehouseId: r.read<String>('destination_warehouse_id'),
        status: r.read<String>(effective ? 'effective_status' : 'status'),
        lineCount: r.read<int>('line_count'),
        notes: r.read<String>('notes'),
      );

  Future<List<_Plan>> _plan(
    _Line line,
    WarehouseOperationScope source,
    Map<String, Map<String, Object?>> terms,
  ) async {
    final p = await (db.select(
      db.products,
    )..where((r) => r.id.equals(line.productId))).getSingle();
    final tracked =
        p.costingMethod == 'fifo' || p.inventoryTrackingType != 'standard';
    return tracked
        ? _planTracked(line, source, terms)
        : _planStandard(line, source, terms);
  }

  Future<List<_Plan>> _planStandard(
    _Line line,
    WarehouseOperationScope source,
    Map<String, Map<String, Object?>> terms,
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
    final explicit = line.owned != null;
    if (explicit != (line.consignment != null)) {
      throw StateError('Transfer ownership intent is incomplete');
    }
    final consignmentAvailable = stock.read<int>('supplier_owned_quantity');
    final ownedAvailable = stock.read<int>('quantity') - consignmentAvailable;
    final owned = explicit
        ? line.owned!
        : math.min(line.quantity, ownedAvailable);
    var consignment = explicit ? line.consignment! : line.quantity - owned;
    if (owned > ownedAvailable || consignment > consignmentAvailable) {
      throw StateError('Transfer source ownership is insufficient');
    }
    final result = <_Plan>[];
    if (owned > 0) {
      final cost = stock.read<int>('unit_cost_cents');
      result.add(
        _Plan(
          id: uuid.v4(),
          line: line,
          quantity: owned,
          unitCost: cost,
          value:
              MeasuredAmount.cents(
                unitCents: cost,
                quantity: ownedAvailable,
                quantityScale: line.scale,
              ) -
              MeasuredAmount.cents(
                unitCents: cost,
                quantity: ownedAvailable - owned,
                quantityScale: line.scale,
              ),
          tracked: false,
        ),
      );
    }
    if (consignment == 0) return result;
    final layers =
        await (db.select(db.consignmentInventoryLayers)
              ..where(
                (l) =>
                    l.warehouseId.equals(source.warehouseId) &
                    l.productId.equals(line.productId) &
                    l.variantId.equals(line.variantId) &
                    l.status.equals('open') &
                    l.remainingQuantity.isBiggerThanValue(0),
              )
              ..orderBy([
                (l) => OrderingTerm.asc(l.receivedAt),
                (l) => OrderingTerm.asc(l.id),
              ]))
            .get();
    for (final layer in layers) {
      if (consignment == 0) break;
      final take = math.min(consignment, layer.remainingQuantity);
      final snapshot = terms[layer.agreementId] ??= await _consignmentTerms(
        layer.agreementId,
      );
      result.add(
        _Plan(
          id: uuid.v4(),
          line: line,
          quantity: take,
          unitCost: layer.unitCostCents ?? 0,
          value: 0,
          tracked: false,
          layer: layer,
          supplierId: layer.supplierId,
          terms: snapshot,
          sourceReference: 'consignment_receipt:${layer.receiptItemId}',
        ),
      );
      consignment -= take;
    }
    if (consignment != 0) {
      throw StateError('Consignment source layers are insufficient');
    }
    return result;
  }

  Future<List<_Plan>> _planTracked(
    _Line line,
    WarehouseOperationScope source,
    Map<String, Map<String, Object?>> terms,
  ) async {
    final rows = await db
        .customSelect(
          '''SELECT b.id,b.remaining_quantity,b.unit_cost_cents,b.supplier_id,
      b.manufacturer_lot_number,b.expiry_date,l.id AS layer_id
      FROM product_batches b LEFT JOIN consignment_inventory_layers l
        ON l.batch_id=b.id AND l.warehouse_id=? AND l.status='open'
      WHERE b.product_id=? AND b.variant_id=? AND b.is_active=1
        AND b.remaining_quantity>0
        AND ${WarehouseBatchScope.operationPredicate('b')}
      ORDER BY (b.expiry_date IS NULL),b.expiry_date,b.received_date,b.id''',
          variables: [
            Variable.withString(source.warehouseId),
            Variable.withInt(line.productId),
            Variable.withInt(line.variantId),
            ...WarehouseBatchScope.operationVariables(source),
          ],
        )
        .get();
    final explicit = line.owned != null;
    if (explicit != (line.consignment != null)) {
      throw StateError('Transfer ownership intent is incomplete');
    }
    var owned = explicit ? line.owned! : 0;
    var consignment = explicit ? line.consignment! : 0;
    var remainder = explicit ? 0 : line.quantity;
    final result = <_Plan>[];
    for (final r in rows) {
      if ((explicit && owned == 0 && consignment == 0) ||
          (!explicit && remainder == 0)) {
        break;
      }
      final layerId = r.readNullable<String>('layer_id');
      final wanted = explicit
          ? (layerId == null ? owned : consignment)
          : remainder;
      if (wanted == 0) continue;
      final available = r.read<int>('remaining_quantity');
      final take = math.min(wanted, available);
      final layer = layerId == null
          ? null
          : await (db.select(
              db.consignmentInventoryLayers,
            )..where((l) => l.id.equals(layerId))).getSingle();
      if (layer != null && layer.remainingQuantity != available) {
        throw StateError('Consignment batch and ownership layer differ');
      }
      final cost = r.read<int>('unit_cost_cents');
      final snapshot = layer == null
          ? null
          : terms[layer.agreementId] ??= await _consignmentTerms(
              layer.agreementId,
            );
      result.add(
        _Plan(
          id: uuid.v4(),
          line: line,
          quantity: take,
          unitCost: cost,
          value: layer == null
              ? MeasuredAmount.cents(
                      unitCents: cost,
                      quantity: available,
                      quantityScale: line.scale,
                    ) -
                    MeasuredAmount.cents(
                      unitCents: cost,
                      quantity: available - take,
                      quantityScale: line.scale,
                    )
              : 0,
          tracked: true,
          batchId: r.read<int>('id'),
          layer: layer,
          supplierId: layer?.supplierId ?? r.readNullable<int>('supplier_id'),
          terms: snapshot,
          lot: r.readNullable<String>('manufacturer_lot_number'),
          expiry: r.readNullable<DateTime>('expiry_date'),
        ),
      );
      if (explicit) {
        if (layer == null) {
          owned -= take;
        } else {
          consignment -= take;
        }
      } else {
        remainder -= take;
      }
    }
    if (explicit ? owned != 0 || consignment != 0 : remainder != 0) {
      throw StateError('Tracked transfer source is insufficient');
    }
    return result;
  }

  Future<int?> _remove(_Plan p, WarehouseOperationScope source) async {
    if (p.layer != null) {
      final layerChanged = await db.customUpdate(
        'UPDATE consignment_inventory_layers SET '
        'remaining_quantity=remaining_quantity-?,'
        "status=CASE WHEN remaining_quantity-?=0 THEN 'exhausted' ELSE 'open' END,"
        "updated_at=? WHERE id=? AND status='open' AND remaining_quantity>=?",
        variables: [
          Variable.withInt(p.quantity),
          Variable.withInt(p.quantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(p.layer!.id),
          Variable.withInt(p.quantity),
        ],
        updates: {db.consignmentInventoryLayers},
      );
      final stockChanged = await db.customUpdate(
        'UPDATE business_warehouse_stocks SET '
        'supplier_owned_quantity=supplier_owned_quantity-?,updated_at=? '
        'WHERE warehouse_id=? AND variant_id=? AND supplier_owned_quantity>=?',
        variables: [
          Variable.withInt(p.quantity),
          Variable.withString(DateTime.now().toUtc().toIso8601String()),
          Variable.withString(source.warehouseId),
          Variable.withInt(p.line.variantId),
          Variable.withInt(p.quantity),
        ],
        updates: {db.businessWarehouseStocks},
      );
      if (layerChanged != 1 || stockChanged != 1) {
        throw StateError('Consignment transfer source changed');
      }
    }
    await StockService.adjustStock(
      db.productDao,
      productId: p.line.productId,
      variantId: p.line.variantId,
      quantity: p.quantity,
      direction: StockDirection.decrease,
      scope: source,
      origin: InventoryOriginIntent.keyed(
        'transfer_out',
        'distributed_transfer_out:${p.id}',
        requiredSourceReference: p.sourceReference,
        excludedSourceKind: p.layer == null && !p.tracked
            ? 'consignment_receipt'
            : null,
      ),
    );
    if (p.batchId == null) return null;
    final consumed = await BatchService.consumeFifo(
      db.productDao,
      productId: p.line.productId,
      variantId: p.line.variantId,
      quantity: p.quantity,
      consumptionType: 'distributed_transfer_dispatch',
      requiredBatchId: p.batchId,
      requiredSupplierId: p.layer?.supplierId,
      notes: 'Distributed transfer allocation ${p.id}',
      scope: source,
    );
    if (consumed.length != 1 ||
        consumed.single.quantity != p.quantity ||
        consumed.single.batchId != p.batchId) {
      throw StateError('Distributed batch consumption is incomplete');
    }
    return consumed.single.consumptionId;
  }

  Future<List<Map<String, Object?>>> _originSlices(
    _Plan p,
    WarehouseOperationScope source,
  ) async {
    final row = await db
        .customSelect(
          'SELECT delta,allocations FROM inventory_origin_events '
          'WHERE warehouse_id=? AND variant_id=? AND event_key=?',
          variables: [
            Variable.withString(source.warehouseId),
            Variable.withInt(p.line.variantId),
            Variable.withString('distributed_transfer_out:${p.id}'),
          ],
        )
        .getSingle();
    final raw = jsonDecode(row.read<String>('allocations'));
    if (row.read<int>('delta') != -p.quantity || raw is! List) {
      throw StateError('Distributed WAC origin is invalid');
    }
    final result = <Map<String, Object?>>[];
    var total = 0;
    for (final value in raw) {
      if (value is! Map) throw StateError('Invalid WAC origin slice');
      final layer = Map<String, Object?>.from(value);
      final quantity = layer['q'];
      if (quantity is! int || quantity <= 0) {
        throw StateError('Invalid WAC origin quantity');
      }
      total += quantity;
      final supplierId = await _originSupplier(
        layer['p'] is int ? layer['p'] as int : null,
        layer['i'] is int ? layer['i'] as int : null,
        layer['s'] is int ? layer['s'] as int : null,
      );
      final global = supplierId == null
          ? null
          : (await identities.getOrCreateLocal(
              entityType: 'supplier',
              localId: supplierId,
            )).globalId;
      result.add({
        'quantityScaled': quantity,
        'originKind': layer['k']?.toString() ?? 'unknown',
        'supplierGlobalId': ?global,
        if (layer['p'] is int)
          'purchaseLineRef': {
            'databaseId': source.databaseId,
            'localId': layer['p'],
          },
        if (layer['r'] != null) 'sourceReference': layer['r'].toString(),
        'sourceQuality': global == null ? 'unverified' : 'documented',
      });
    }
    if (total != p.quantity) throw StateError('WAC origin quantity changed');
    return result;
  }

  Future<int?> _originSupplier(
    int? purchaseItem,
    int? identityId,
    int? directSupplierId,
  ) async {
    if (identityId != null) {
      final row = await db
          .customSelect(
            'SELECT supplier_id FROM supplier_product_identities WHERE id=?',
            variables: [Variable.withInt(identityId)],
          )
          .getSingleOrNull();
      if (row != null) {
        final supplierId = row.read<int>('supplier_id');
        if (directSupplierId != null && directSupplierId != supplierId) {
          throw StateError('Distributed transfer supplier origin conflicts');
        }
        return supplierId;
      }
    }
    if (purchaseItem == null) return directSupplierId;
    final purchaseSupplier = await db
        .customSelect(
          'SELECT p.supplier_id FROM purchase_items i '
          'JOIN purchases p ON p.id=i.purchase_id WHERE i.id=?',
          variables: [Variable.withInt(purchaseItem)],
        )
        .map((r) => r.read<int>('supplier_id'))
        .getSingleOrNull();
    if (directSupplierId != null &&
        purchaseSupplier != null &&
        directSupplierId != purchaseSupplier) {
      throw StateError('Distributed transfer supplier origin conflicts');
    }
    return directSupplierId ?? purchaseSupplier;
  }

  Future<Map<String, Object?>> _eventAllocation(
    _Plan p,
    int sequence,
    List<Map<String, Object?>> origins,
  ) async {
    final product = await identities.getOrCreateLocal(
      entityType: 'product',
      localId: p.line.productId,
    );
    final variant = await identities.getOrCreateLocal(
      entityType: 'product_variant',
      localId: p.line.variantId,
    );
    String? supplierGlobal;
    if (p.supplierId != null) {
      supplierGlobal = (await identities.getOrCreateLocal(
        entityType: 'supplier',
        localId: p.supplierId!,
      )).globalId;
    } else {
      final suppliers = origins
          .map((e) => e['supplierGlobalId']?.toString())
          .whereType<String>()
          .toSet();
      if (suppliers.length == 1) supplierGlobal = suppliers.single;
    }
    Map<String, Object?>? batch;
    if (p.batchId != null) {
      final identity = await identities.getOrCreateLocal(
        entityType: 'product_batch',
        localId: p.batchId!,
      );
      batch = {
        'globalId': identity.globalId,
        'originDatabaseId': identity.originDatabaseId,
      };
    }
    return {
      'allocationId': p.id,
      'lineId': p.line.id,
      'sequence': sequence,
      'productGlobalId': product.globalId,
      'variantGlobalId': variant.globalId,
      'ownerType': p.isConsignment ? 'consignment' : 'owned',
      'quantityScaled': p.quantity,
      'quantityScale': p.line.scale,
      'measurementType': p.line.measurement,
      'unitCostMinor': p.unitCost,
      'valueMinor': p.value,
      'supplierGlobalId': ?supplierGlobal,
      if (p.layer != null) 'consignmentAgreementId': p.layer!.agreementId,
      if (p.layer != null) 'sourceConsignmentLayerId': p.layer!.id,
      if (p.terms != null) 'consignmentTerms': p.terms,
      'sourceBatch': ?batch,
      if (p.lot != null) 'manufacturerLotNumber': p.lot,
      if (p.expiry != null) 'expiryDate': p.expiry!.toUtc().toIso8601String(),
      if (origins.isNotEmpty) 'originSlices': origins,
    };
  }

  Future<Map<String, Object?>> _consignmentTerms(String id) async {
    final a = await (db.select(
      db.consignmentAgreements,
    )..where((r) => r.id.equals(id))).getSingle();
    final supplier = (await identities.getOrCreateLocal(
      entityType: 'supplier',
      localId: a.supplierId,
    )).globalId;
    final rows = await (db.select(
      db.consignmentAgreementItems,
    )..where((r) => r.agreementId.equals(id))).get();
    final terms = <Map<String, Object?>>[];
    for (final item in rows) {
      final product = await identities.getOrCreateLocal(
        entityType: 'product',
        localId: item.productId,
      );
      final variant = item.variantId == null
          ? null
          : await identities.getOrCreateLocal(
              entityType: 'product_variant',
              localId: item.variantId!,
            );
      terms.add({
        'productGlobalId': product.globalId,
        'variantGlobalId': variant?.globalId,
        'settlementBasis': item.settlementBasis,
        'unitCostMinor': item.unitCostCents,
        'supplierShareBps': item.supplierShareBps,
        'includeLineDiscount': item.includeLineDiscount,
        'includeInvoiceDiscount': item.includeInvoiceDiscount,
        'includeSalesTax': item.includeSalesTax,
      });
    }
    return {
      'sourceAgreementId': a.id,
      'agreementKey': a.agreementKey,
      'revision': a.revision,
      'agreementNumber': a.agreementNumber,
      'supplierGlobalId': supplier,
      'settlementFrequency': a.settlementFrequency,
      'paymentTermsDays': a.paymentTermsDays,
      'settlementTaxRateBps': a.settlementTaxRateBps,
      'settlementTaxInclusive': a.settlementTaxInclusive,
      'effectiveFrom': a.effectiveFrom.toUtc().toIso8601String(),
      if (a.effectiveTo != null)
        'effectiveTo': a.effectiveTo!.toUtc().toIso8601String(),
      'terms': terms,
    };
  }
}

class _Destination {
  const _Destination(this.databaseId, this.branchId);
  final String databaseId, branchId;
}

class _Line {
  const _Line({
    required this.id,
    required this.productId,
    required this.variantId,
    required this.quantity,
    required this.scale,
    required this.measurement,
    this.owned,
    this.consignment,
  });
  final String id, measurement;
  final int productId, variantId, quantity, scale;
  final int? owned, consignment;

  factory _Line.fromRow(QueryRow r) => _Line(
    id: r.readNullable<String>('line_id') ?? '',
    productId: r.read<int>('product_id'),
    variantId: r.read<int>('variant_id'),
    quantity: r.readNullable<int>('quantity_scaled') ?? 0,
    scale: r.read<int>('quantity_scale'),
    measurement: r.read<String>('measurement_type'),
    owned: r.readNullable<int>('requested_owned_quantity'),
    consignment: r.readNullable<int>('requested_consignment_quantity'),
  );
}

class _Plan {
  const _Plan({
    required this.id,
    required this.line,
    required this.quantity,
    required this.unitCost,
    required this.value,
    required this.tracked,
    this.batchId,
    this.layer,
    this.supplierId,
    this.terms,
    this.sourceReference,
    this.lot,
    this.expiry,
  });
  final String id;
  final _Line line;
  final int quantity, unitCost, value;
  final bool tracked;
  final int? batchId, supplierId;
  final ConsignmentInventoryLayer? layer;
  final Map<String, Object?>? terms;
  final String? sourceReference, lot;
  final DateTime? expiry;
  bool get isConsignment => layer != null;
}
