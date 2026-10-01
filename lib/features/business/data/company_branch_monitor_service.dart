import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'local_company_document_projection_reader.dart';

enum CompanyDocumentKind {
  purchase,
  sale,
  purchaseReturn,
  saleReturn,
  purchaseAdjustmentReturn,
  saleAdjustmentReturn,
}

class CompanyLocationStatus {
  const CompanyLocationStatus({
    required this.branchId,
    required this.branchCode,
    required this.branchName,
    required this.warehouses,
    required this.isLocal,
    required this.isEnrolled,
    required this.isOnline,
    this.lastSeenAt,
  });

  final String branchId;
  final String branchCode;
  final String branchName;
  final List<CompanyWarehouseStatus> warehouses;
  final bool isLocal;
  final bool isEnrolled;
  final bool isOnline;
  final DateTime? lastSeenAt;
}

class CompanyWarehouseStatus {
  const CompanyWarehouseStatus({
    required this.id,
    required this.branchId,
    required this.code,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String branchId;
  final String code;
  final String name;
  final bool isActive;
}

class CompanyDocumentBatchSnapshot {
  const CompanyDocumentBatchSnapshot({
    required this.number,
    required this.quantityScaled,
    this.expiryDate,
  });

  final String number;
  final int quantityScaled;
  final DateTime? expiryDate;
}

class CompanySupplierAllocationSnapshot {
  const CompanySupplierAllocationSnapshot({
    required this.name,
    required this.quantityScaled,
    required this.sourceQuality,
  });

  final String name;
  final int quantityScaled;
  final String sourceQuality;
}

class CompanyInventoryMovementSnapshot {
  const CompanyInventoryMovementSnapshot({
    required this.movementId,
    required this.branchId,
    required this.warehouseId,
    required this.productName,
    required this.quantityScaled,
    required this.quantityScale,
    required this.measurementType,
    required this.valueMinor,
    required this.currencyCode,
    required this.occurredAt,
    this.variantName,
    this.productGlobalId,
    this.variantGlobalId,
    this.categoryName,
    this.reference = '',
    this.supplierNames = const [],
  });

  final String movementId;
  final String branchId;
  final String warehouseId;
  final String productName;
  final String? variantName;
  final String? productGlobalId;
  final String? variantGlobalId;
  final String? categoryName;
  final int quantityScaled;
  final int quantityScale;
  final String measurementType;
  final int valueMinor;
  final String currencyCode;
  final DateTime occurredAt;
  final String reference;
  final List<String> supplierNames;
}

class CompanyDocumentLineSnapshot {
  const CompanyDocumentLineSnapshot({
    required this.productName,
    required this.variantName,
    required this.quantityScaled,
    required this.quantityScale,
    required this.measurementType,
    required this.unitMinor,
    required this.subtotalMinor,
    required this.discountMinor,
    required this.taxMinor,
    required this.totalMinor,
    this.reason,
    this.batches = const [],
    this.productGlobalId,
    this.variantGlobalId,
    this.categoryName,
    this.supplierNames = const [],
    this.supplierAllocations = const [],
    this.inventoryQuantityScaled,
    this.inventoryClassificationKnown = false,
    this.inventoryValueMinor = 0,
  });

  final String productName;
  final String? variantName;
  final String? productGlobalId;
  final String? variantGlobalId;
  final String? categoryName;
  final List<String> supplierNames;
  final List<CompanySupplierAllocationSnapshot> supplierAllocations;
  final int? inventoryQuantityScaled;
  final bool inventoryClassificationKnown;
  final int inventoryValueMinor;
  final int quantityScaled;
  final int quantityScale;
  final String measurementType;
  final int unitMinor;
  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int totalMinor;
  final String? reason;
  final List<CompanyDocumentBatchSnapshot> batches;
}

class CompanyDocumentSnapshot {
  const CompanyDocumentSnapshot({
    required this.documentId,
    required this.sourceDatabaseId,
    required this.branchId,
    required this.branchName,
    required this.warehouseId,
    required this.warehouseName,
    required this.kind,
    required this.number,
    required this.documentDate,
    required this.currencyCode,
    required this.totalMinor,
    required this.itemCount,
    required this.isRemote,
    required this.isVoided,
    required this.occurredAt,
    this.partyName,
    this.paymentMethod,
    this.subtotalMinor = 0,
    this.discountMinor = 0,
    this.taxMinor = 0,
    this.paidMinor = 0,
    this.notes,
    this.originalDocumentId,
    this.lines = const [],
    this.hasFinancialBreakdown = true,
    this.partyGlobalId,
    this.operatorLabel,
    this.commissionMinor = 0,
    this.commissionDataKnown = false,
  });

  final String documentId;
  final String sourceDatabaseId;
  final String branchId;
  final String branchName;
  final String warehouseId;
  final String warehouseName;
  final CompanyDocumentKind kind;
  final String number;
  final DateTime documentDate;
  final String currencyCode;
  final int totalMinor;
  final int itemCount;
  final bool isRemote;
  final bool isVoided;
  final DateTime occurredAt;
  final String? partyName;
  final String? paymentMethod;
  final int subtotalMinor;
  final int discountMinor;
  final int taxMinor;
  final int paidMinor;
  final String? notes;
  final String? originalDocumentId;
  final List<CompanyDocumentLineSnapshot> lines;
  final bool hasFinancialBreakdown;
  final String? partyGlobalId;
  final String? operatorLabel;
  final int commissionMinor;
  final bool commissionDataKnown;

  bool get isSale => kind == CompanyDocumentKind.sale;
  bool get isPurchase => kind == CompanyDocumentKind.purchase;
  bool get isReturn => !isSale && !isPurchase;

  CompanyDocumentSnapshot copyWith({bool? isVoided}) => CompanyDocumentSnapshot(
    documentId: documentId,
    sourceDatabaseId: sourceDatabaseId,
    branchId: branchId,
    branchName: branchName,
    warehouseId: warehouseId,
    warehouseName: warehouseName,
    kind: kind,
    number: number,
    documentDate: documentDate,
    currencyCode: currencyCode,
    totalMinor: totalMinor,
    itemCount: itemCount,
    isRemote: isRemote,
    isVoided: isVoided ?? this.isVoided,
    occurredAt: occurredAt,
    partyName: partyName,
    paymentMethod: paymentMethod,
    subtotalMinor: subtotalMinor,
    discountMinor: discountMinor,
    taxMinor: taxMinor,
    paidMinor: paidMinor,
    notes: notes,
    originalDocumentId: originalDocumentId,
    lines: lines,
    hasFinancialBreakdown: hasFinancialBreakdown,
    partyGlobalId: partyGlobalId,
    operatorLabel: operatorLabel,
    commissionMinor: commissionMinor,
    commissionDataKnown: commissionDataKnown,
  );
}

class CompanyBranchMonitorSnapshot {
  const CompanyBranchMonitorSnapshot({
    required this.locations,
    required this.documents,
    required this.generatedAt,
    this.inventoryMovements = const [],
  });

  final List<CompanyLocationStatus> locations;
  final List<CompanyDocumentSnapshot> documents;
  final DateTime generatedAt;
  final List<CompanyInventoryMovementSnapshot> inventoryMovements;
}

/// Read-only company projection over the immutable LAN synchronization ledger.
///
/// It never imports a remote journal entry into the coordinator's local books.
/// The same posted/voided contracts used by LAN delivery are rendered here, so
/// the future online transport can feed the same projection without cloning
/// purchase or sale business logic.
class CompanyBranchMonitorService {
  CompanyBranchMonitorService(
    this._db, {
    this.onlineWindow = const Duration(minutes: 5),
  });

  final AppDatabase _db;
  final Duration onlineWindow;

  static const _eventTypes = <String>{
    'purchase.posted.v1',
    'purchase.voided.v1',
    'purchase_return.posted.v1',
    'purchase_return.voided.v1',
    'sale.posted.v1',
    'sale.voided.v1',
    'sale_return.posted.v1',
    'sale_return.voided.v1',
    'purchase_adjustment_return.posted.v1',
    'purchase_adjustment_return.voided.v1',
    'sale_adjustment_return.posted.v1',
    'sale_adjustment_return.voided.v1',
  };

  static const _inventoryEventTypes = <String>{
    'inventory_adjustment.posted.v1',
    'warehouse_transfer.dispatched.v1',
    'warehouse_transfer.received.v1',
    'warehouse_transfer.recalled.v1',
  };

  Future<CompanyBranchMonitorSnapshot> load({DateTime? now}) async {
    final current = (now ?? DateTime.now()).toUtc();
    final local = await _db
        .customSelect(
          'SELECT database_id,organization_id,branch_id FROM sync_local_state WHERE id=1',
        )
        .getSingle();
    final databaseId = local.read<String>('database_id');
    final organizationId = local.read<String>('organization_id');
    final localBranchId = local.read<String>('branch_id');

    final branchRows = await _db
        .customSelect(
          '''SELECT b.id,b.code,b.name,b.is_active,e.status,e.remote_database_id,
      CASE WHEN c.last_seen_at IS NULL THEN r.last_seen_at
      WHEN r.last_seen_at IS NULL THEN c.last_seen_at
      WHEN c.last_seen_at >= r.last_seen_at THEN c.last_seen_at
      ELSE r.last_seen_at END AS last_seen_at
      FROM business_branches b
      LEFT JOIN lan_branch_enrollments e
        ON e.branch_id=b.id AND e.organization_id=b.organization_id
      LEFT JOIN lan_branch_sync_credentials c
        ON c.enrollment_id=e.enrollment_id AND c.status='active'
      LEFT JOIN lan_branch_recovery_credentials r
        ON r.enrollment_id=e.enrollment_id AND r.status='active'
      WHERE b.organization_id=?
      GROUP BY b.id,b.code,b.name,b.is_active,e.status,e.remote_database_id
      ORDER BY b.code,b.id''',
          variables: [Variable.withString(organizationId)],
        )
        .get();
    final warehouseRows = await _db
        .customSelect(
          '''SELECT id,branch_id,code,name,is_active FROM business_warehouses
      WHERE organization_id=? ORDER BY branch_id,code,id''',
          variables: [Variable.withString(organizationId)],
        )
        .get();
    final warehousesByBranch = <String, List<CompanyWarehouseStatus>>{};
    final warehouseNames = <String, String>{};
    for (final row in warehouseRows) {
      final warehouse = CompanyWarehouseStatus(
        id: row.read<String>('id'),
        branchId: row.read<String>('branch_id'),
        code: row.read<String>('code'),
        name: _displayName(row.read<String>('name'), row.read<String>('code')),
        isActive: row.read<int>('is_active') == 1,
      );
      warehousesByBranch
          .putIfAbsent(warehouse.branchId, () => [])
          .add(warehouse);
      warehouseNames[warehouse.id] = warehouse.name;
    }
    final branchNames = <String, String>{};
    final locations = <CompanyLocationStatus>[];
    for (final row in branchRows) {
      final id = row.read<String>('id');
      final name = _displayName(
        row.read<String>('name'),
        row.read<String>('code'),
      );
      branchNames[id] = name;
      final lastSeenText = row.readNullable<String>('last_seen_at');
      final lastSeen = lastSeenText == null
          ? null
          : DateTime.tryParse(lastSeenText)?.toUtc();
      final isLocal = id == localBranchId;
      final enrolled = row.readNullable<String>('status') == 'active';
      locations.add(
        CompanyLocationStatus(
          branchId: id,
          branchCode: row.read<String>('code'),
          branchName: name,
          warehouses: List.unmodifiable(warehousesByBranch[id] ?? const []),
          isLocal: isLocal,
          isEnrolled: enrolled,
          isOnline:
              isLocal ||
              (enrolled &&
                  lastSeen != null &&
                  current.difference(lastSeen) <= onlineWindow),
          lastSeenAt: lastSeen,
        ),
      );
    }

    final localRows = await _db
        .customSelect(
          '''SELECT event_id,source_database_id,event_type,payload_json,occurred_at
      FROM sync_outbox_events WHERE organization_id=? ORDER BY local_sequence''',
          variables: [Variable.withString(organizationId)],
        )
        .get();
    final remoteRows = await _db
        .customSelect(
          '''SELECT event_id,source_database_id,event_type,payload_json,occurred_at
      FROM sync_remote_event_projections WHERE organization_id=?
      ORDER BY source_database_id,source_sequence''',
          variables: [Variable.withString(organizationId)],
        )
        .get();

    final identityLabels = await _identityLabels();
    final productCategories = await _productCategories();
    final documents = <String, CompanyDocumentSnapshot>{};
    void consumePayload({
      required String eventType,
      required String source,
      required Map<String, Object?> payload,
      required DateTime occurredAt,
      required bool remote,
    }) {
      if (!_eventTypes.contains(eventType)) return;
      final documentId = payload['documentId']?.toString() ?? '';
      if (documentId.isEmpty) return;
      final key = '$source:$documentId';
      if (eventType.contains('.voided.')) {
        final existing = documents[key];
        if (existing != null) {
          documents[key] = existing.copyWith(isVoided: true);
        }
        return;
      }
      final kind = _kind(eventType);
      if (kind == null) return;
      final branchId = payload['branchId']?.toString() ?? '';
      final warehouseId = payload['warehouseId']?.toString() ?? '';
      documents[key] = CompanyDocumentSnapshot(
        documentId: documentId,
        sourceDatabaseId: source,
        branchId: branchId,
        branchName: branchNames[branchId] ?? branchId,
        warehouseId: warehouseId,
        warehouseName: warehouseNames[warehouseId] ?? warehouseId,
        kind: kind,
        number: _number(payload),
        documentDate: _documentDate(payload) ?? occurredAt,
        currencyCode: payload['currencyCode']?.toString() ?? '',
        totalMinor: _integer(payload['totalMinor']),
        itemCount: _integer(payload['itemCount']),
        isRemote: remote || source != databaseId,
        isVoided: payload['_isVoided'] == true,
        occurredAt: occurredAt,
        partyName: _partyName(payload, identityLabels),
        partyGlobalId:
            (payload['supplierGlobalId'] ?? payload['customerGlobalId'])
                ?.toString(),
        operatorLabel: _operatorLabel(payload),
        commissionMinor: _commissionMinor(payload),
        commissionDataKnown: payload.containsKey('commissions'),
        paymentMethod: (payload['paymentMethod'] ?? payload['refundMethod'])
            ?.toString(),
        subtotalMinor: _integer(payload['subtotalMinor']),
        discountMinor: _integer(payload['discountMinor']),
        taxMinor: _integer(payload['taxMinor']),
        paidMinor: _integer(payload['paidMinor']),
        notes: payload['notes']?.toString(),
        originalDocumentId:
            (payload['originalSaleDocumentId'] ??
                    payload['originalPurchaseDocumentId'])
                ?.toString(),
        lines: _lines(payload, kind, identityLabels, productCategories),
        hasFinancialBreakdown:
            payload.containsKey('subtotalMinor') &&
            payload.containsKey('discountMinor') &&
            payload.containsKey('taxMinor') &&
            payload.containsKey('paidMinor'),
      );
    }

    void consume(QueryRow row, bool remote) {
      final raw = jsonDecode(row.read<String>('payload_json'));
      if (raw is! Map) return;
      consumePayload(
        eventType: row.read<String>('event_type'),
        source: row.read<String>('source_database_id'),
        payload: Map<String, Object?>.from(raw),
        occurredAt:
            DateTime.tryParse(row.read<String>('occurred_at'))?.toUtc() ??
            current,
        remote: remote,
      );
    }

    for (final row in localRows) {
      consume(row, false);
    }
    for (final row in remoteRows) {
      consume(row, true);
    }
    // Local native rows are authoritative for the coordinator database. They
    // also cover documents created before the immutable sync ledger existed.
    // Applying them last updates the current void state and replaces any
    // matching local event under the same source/database document key.
    final nativeDocuments = await LocalCompanyDocumentProjectionReader(
      _db,
    ).load(organizationId: organizationId, databaseId: databaseId);
    for (final document in nativeDocuments) {
      consumePayload(
        eventType: document.eventType,
        source: document.sourceDatabaseId,
        payload: document.payload,
        occurredAt: document.occurredAt,
        remote: false,
      );
    }
    final movements = _inventoryMovements(
      [...localRows, ...remoteRows],
      identityLabels,
      productCategories,
      await _productQuantityScales(),
      {
        for (final row in warehouseRows)
          row.read<String>('id'): row.read<String>('branch_id'),
      },
      current,
    );
    final ordered = documents.values.toList()
      ..sort((a, b) => b.documentDate.compareTo(a.documentDate));
    return CompanyBranchMonitorSnapshot(
      locations: List.unmodifiable(locations),
      documents: List.unmodifiable(ordered),
      generatedAt: current,
      inventoryMovements: List.unmodifiable(movements),
    );
  }

  Future<Map<String, String>> _identityLabels() async {
    final result = <String, String>{};
    Future<void> add(String sql, String type) async {
      for (final row in await _db.customSelect(sql).get()) {
        result['$type:${row.read<String>('global_id')}'] = row.read<String>(
          'label',
        );
      }
    }

    await add(
      '''SELECT i.global_id,p.name AS label FROM sync_entity_identities i
      JOIN products p ON p.id=i.local_id WHERE i.entity_type='product' ''',
      'product',
    );
    await add('''SELECT i.global_id,
      p.name || CASE WHEN c.name IS NULL THEN '' ELSE ' • ' || c.name END ||
      CASE WHEN s.name IS NULL THEN '' ELSE ' • ' || s.name END ||
      CASE WHEN v.sku IS NULL OR v.sku='' THEN '' ELSE ' • ' || v.sku END AS label
      FROM sync_entity_identities i
      JOIN product_variants v ON v.id=i.local_id
      JOIN products p ON p.id=v.product_id
      LEFT JOIN product_colors c ON c.id=v.color_id
      LEFT JOIN sizes s ON s.id=v.size_id
      WHERE i.entity_type='product_variant' ''', 'product_variant');
    await add(
      '''SELECT i.global_id,s.name AS label FROM sync_entity_identities i
      JOIN suppliers s ON s.id=i.local_id WHERE i.entity_type='supplier' ''',
      'supplier',
    );
    await add(
      '''SELECT i.global_id,c.name AS label FROM sync_entity_identities i
      JOIN customers c ON c.id=i.local_id WHERE i.entity_type='customer' ''',
      'customer',
    );
    await add(
      "SELECT 'local:product:' || id AS global_id,name AS label FROM products",
      'product',
    );
    await add('''SELECT 'local:product_variant:' || v.id AS global_id,
      p.name || CASE WHEN c.name IS NULL THEN '' ELSE ' • ' || c.name END ||
      CASE WHEN s.name IS NULL THEN '' ELSE ' • ' || s.name END ||
      CASE WHEN v.sku IS NULL OR v.sku='' THEN '' ELSE ' • ' || v.sku END AS label
      FROM product_variants v JOIN products p ON p.id=v.product_id
      LEFT JOIN product_colors c ON c.id=v.color_id
      LEFT JOIN sizes s ON s.id=v.size_id''', 'product_variant');
    await add(
      "SELECT 'local:supplier:' || id AS global_id,name AS label FROM suppliers",
      'supplier',
    );
    await add(
      "SELECT 'local:customer:' || id AS global_id,name AS label FROM customers",
      'customer',
    );
    return result;
  }

  Future<Map<String, int>> _productQuantityScales() async {
    final result = <String, int>{};
    final rows = await _db.customSelect('''SELECT i.global_id,p.measurement_type
      FROM sync_entity_identities i
      JOIN products p ON p.id=i.local_id
      WHERE i.entity_type='product' ''').get();
    for (final row in rows) {
      result[row.read<String>('global_id')] =
          row.read<String>('measurement_type') == 'piece' ? 1 : 1000;
    }
    return result;
  }

  static List<CompanyInventoryMovementSnapshot> _inventoryMovements(
    List<QueryRow> rows,
    Map<String, String> labels,
    Map<String, String> categories,
    Map<String, int> quantityScales,
    Map<String, String> warehouseBranches,
    DateTime fallbackTime,
  ) {
    final decoded =
        <
          ({
            String eventId,
            String type,
            Map<String, Object?> payload,
            DateTime occurredAt,
          })
        >[];
    final seen = <String>{};
    for (final row in rows) {
      final type = row.read<String>('event_type');
      if (!_inventoryEventTypes.contains(type)) continue;
      final eventId = row.read<String>('event_id');
      if (!seen.add(eventId)) continue;
      final raw = jsonDecode(row.read<String>('payload_json'));
      if (raw is! Map) continue;
      decoded.add((
        eventId: eventId,
        type: type,
        payload: Map<String, Object?>.from(raw),
        occurredAt:
            DateTime.tryParse(row.read<String>('occurred_at'))?.toUtc() ??
            fallbackTime,
      ));
    }

    final dispatchAllocations = <String, Map<String, Object?>>{};
    final dispatchEvents =
        <
          ({String eventId, Map<String, Object?> payload, DateTime occurredAt})
        >[];
    for (final event in decoded) {
      if (event.type != 'warehouse_transfer.dispatched.v1') continue;
      dispatchEvents.add((
        eventId: event.eventId,
        payload: event.payload,
        occurredAt: event.occurredAt,
      ));
      final transferId = event.payload['transferId']?.toString() ?? '';
      final allocations = event.payload['allocations'];
      if (allocations is! List) continue;
      for (final raw in allocations) {
        if (raw is! Map || raw['allocationId'] == null) continue;
        dispatchAllocations['$transferId:${raw['allocationId']}'] = {
          ...Map<String, Object?>.from(raw),
          '_sourceWarehouseId': event.payload['sourceWarehouseId'],
          '_destinationWarehouseId': event.payload['destinationWarehouseId'],
          '_branchId': event.payload['branchId'],
          '_currencyCode': event.payload['currencyCode'],
        };
      }
    }

    final result = <CompanyInventoryMovementSnapshot>[];
    List<String> suppliers(Map<String, Object?> allocation) {
      final id = allocation['supplierGlobalId']?.toString();
      if (id == null || id.isEmpty) return const [];
      return [labels['supplier:$id'] ?? id];
    }

    void append({
      required String movementId,
      required String branchId,
      required String warehouseId,
      required Map<String, Object?> allocation,
      required int quantity,
      required int value,
      required String currency,
      required DateTime occurredAt,
      required String reference,
    }) {
      final productId = allocation['productGlobalId']?.toString();
      final variantId = allocation['variantGlobalId']?.toString();
      if (warehouseId.isEmpty || productId == null || quantity == 0) return;
      final scale = _integer(allocation['quantityScale']) > 0
          ? _integer(allocation['quantityScale'])
          : quantityScales[productId] ?? 1;
      result.add(
        CompanyInventoryMovementSnapshot(
          movementId: movementId,
          branchId: warehouseBranches[warehouseId] ?? branchId,
          warehouseId: warehouseId,
          productName: labels['product:$productId'] ?? productId,
          variantName: variantId == null
              ? null
              : labels['product_variant:$variantId'] ?? variantId,
          productGlobalId: productId,
          variantGlobalId: variantId,
          categoryName: categories[productId],
          quantityScaled: quantity,
          quantityScale: scale,
          measurementType:
              allocation['measurementType']?.toString() ??
              (scale == 1 ? 'piece' : 'measured'),
          valueMinor: value,
          currencyCode: currency,
          occurredAt: occurredAt,
          reference: reference,
          supplierNames: suppliers(allocation),
        ),
      );
    }

    for (final event in decoded) {
      if (event.type != 'inventory_adjustment.posted.v1') continue;
      final payload = event.payload;
      final productId = payload['productGlobalId']?.toString();
      if (productId == null) continue;
      final quantity = _integer(payload['quantityDeltaScaled']);
      final rawValue = _integer(payload['totalValueMinor']);
      final value = quantity < 0
          ? -rawValue.abs()
          : quantity > 0
          ? rawValue.abs()
          : rawValue;
      append(
        movementId: event.eventId,
        branchId: payload['branchId']?.toString() ?? '',
        warehouseId: payload['warehouseId']?.toString() ?? '',
        allocation: {
          'productGlobalId': productId,
          'variantGlobalId': payload['variantGlobalId'],
          'quantityScale': quantityScales[productId] ?? 1,
          'measurementType': quantityScales[productId] == 1
              ? 'piece'
              : 'measured',
        },
        quantity: quantity,
        value: value,
        currency: payload['currencyCode']?.toString() ?? '',
        occurredAt: event.occurredAt,
        reference: payload['adjustmentNumber']?.toString() ?? '',
      );
    }

    for (final event in dispatchEvents) {
      final payload = event.payload;
      final transferId = payload['transferId']?.toString() ?? '';
      final allocations = payload['allocations'];
      if (allocations is! List) continue;
      for (final raw in allocations) {
        if (raw is! Map) continue;
        final allocation = Map<String, Object?>.from(raw);
        append(
          movementId: '${event.eventId}:${allocation['allocationId']}:out',
          branchId: payload['branchId']?.toString() ?? '',
          warehouseId: payload['sourceWarehouseId']?.toString() ?? '',
          allocation: allocation,
          quantity: -_integer(allocation['quantityScaled']).abs(),
          value: -_integer(allocation['valueMinor']).abs(),
          currency: payload['currencyCode']?.toString() ?? '',
          occurredAt: event.occurredAt,
          reference: transferId,
        );
      }
    }

    for (final event in decoded) {
      if (event.type != 'warehouse_transfer.received.v1' &&
          event.type != 'warehouse_transfer.recalled.v1') {
        continue;
      }
      final payload = event.payload;
      final transferId = payload['transferId']?.toString() ?? '';
      final items = payload['items'];
      if (items is! List) continue;
      for (final raw in items) {
        if (raw is! Map || raw['allocationId'] == null) continue;
        final item = Map<String, Object?>.from(raw);
        final allocation =
            dispatchAllocations['$transferId:${item['allocationId']}'];
        if (allocation == null) continue;
        final received = event.type == 'warehouse_transfer.received.v1';
        final quantity = _integer(
          received ? item['acceptedQuantityScaled'] : item['quantityScaled'],
        );
        final value = _integer(
          received ? item['acceptedValueMinor'] : item['valueMinor'],
        );
        append(
          movementId:
              '${event.eventId}:${item['allocationId']}:'
              '${received ? 'in' : 'recall'}',
          branchId:
              (allocation['_branchId'] ?? payload['branchId'])?.toString() ??
              '',
          warehouseId:
              (received
                      ? allocation['_destinationWarehouseId']
                      : allocation['_sourceWarehouseId'])
                  ?.toString() ??
              '',
          allocation: allocation,
          quantity: quantity.abs(),
          value: value.abs(),
          currency:
              (allocation['_currencyCode'] ?? payload['currencyCode'])
                  ?.toString() ??
              '',
          occurredAt: event.occurredAt,
          reference: transferId,
        );
      }
    }
    result.sort((left, right) => right.occurredAt.compareTo(left.occurredAt));
    return result;
  }

  Future<Map<String, String>> _productCategories() async {
    final result = <String, String>{};
    final rows = await _db.customSelect(
      '''SELECT i.global_id,COALESCE(c.name,'') AS category_name
      FROM sync_entity_identities i
      JOIN products p ON p.id=i.local_id
      LEFT JOIN product_categories c ON c.id=p.category_id
      WHERE i.entity_type='product' ''',
    ).get();
    for (final row in rows) {
      final name = row.read<String>('category_name').trim();
      if (name.isNotEmpty) {
        result[row.read<String>('global_id')] = name;
      }
    }
    return result;
  }

  static String? _partyName(
    Map<String, Object?> payload,
    Map<String, String> labels,
  ) {
    final supplier = payload['supplierGlobalId']?.toString();
    if (supplier != null) {
      return labels['supplier:$supplier'] ??
          payload['supplierName']?.toString();
    }
    final customer = payload['customerGlobalId']?.toString();
    if (customer != null) {
      return labels['customer:$customer'] ??
          payload['customerName']?.toString();
    }
    return (payload['supplierName'] ?? payload['customerName'])?.toString();
  }

  static List<CompanyDocumentLineSnapshot> _lines(
    Map<String, Object?> payload,
    CompanyDocumentKind kind,
    Map<String, String> labels,
    Map<String, String> productCategories,
  ) {
    final raw = payload['items'];
    if (raw is! List) return const [];
    final headerSupplier = payload['supplierGlobalId']?.toString();
    return [
      for (final value in raw)
        if (value is Map)
          _line(
            Map<String, Object?>.from(value),
            kind,
            labels,
            productCategories,
            headerSupplier,
            payload['restoresSellableStock'],
          ),
    ];
  }

  static CompanyDocumentLineSnapshot _line(
    Map<String, Object?> value,
    CompanyDocumentKind kind,
    Map<String, String> labels,
    Map<String, String> productCategories,
    String? headerSupplier,
    Object? headerRestoresSellableStock,
  ) {
    final productId = value['productGlobalId']?.toString();
    final variantId = value['variantGlobalId']?.toString();
    final productName =
        value['productName']?.toString() ??
        (productId == null ? null : labels['product:$productId']) ??
        value['productSku']?.toString() ??
        productId ??
        '';
    final variantName =
        value['variantName']?.toString() ??
        value['variantSku']?.toString() ??
        (variantId == null ? null : labels['product_variant:$variantId']) ??
        variantId;
    final batches = <CompanyDocumentBatchSnapshot>[];
    final rawBatches = value['batches'];
    if (rawBatches is List) {
      for (final raw in rawBatches) {
        if (raw is! Map) continue;
        final batch = Map<String, Object?>.from(raw);
        final expiry = batch['expiryDate']?.toString();
        batches.add(
          CompanyDocumentBatchSnapshot(
            number:
                batch['batchNumber']?.toString() ??
                batch['manufacturerLotNumber']?.toString() ??
                '',
            quantityScaled: _integer(batch['quantityScaled']),
            expiryDate: expiry == null ? null : DateTime.tryParse(expiry),
          ),
        );
      }
    }
    final quantityScaled = _integer(
      value['quantityScaled'] ?? value['quantity'],
    );
    final hasTrackingFlag =
        value.containsKey('tracksInventory') ||
        value.containsKey('inventorySourceMode') ||
        value.containsKey('inventoryEffect');
    final tracksInventory =
        value['tracksInventory'] != false &&
        value['inventorySourceMode']?.toString() != 'not_tracked' &&
        value['inventoryEffect']?.toString() != 'not_tracked';
    final isSaleReturn =
        kind == CompanyDocumentKind.saleReturn ||
        kind == CompanyDocumentKind.saleAdjustmentReturn;
    final restoresSaleStock =
        !isSaleReturn ||
        (kind == CompanyDocumentKind.saleReturn
            ? headerRestoresSellableStock != false
            : value['dispositionType']?.toString() == 'restock');
    final inventoryClassificationKnown =
        hasTrackingFlag ||
        (kind == CompanyDocumentKind.saleReturn &&
            headerRestoresSellableStock != null) ||
        (kind == CompanyDocumentKind.saleAdjustmentReturn &&
            value['dispositionType'] != null);

    return CompanyDocumentLineSnapshot(
      productName: productName,
      variantName: variantName,
      quantityScaled: quantityScaled,
      inventoryQuantityScaled: tracksInventory && restoresSaleStock
          ? quantityScaled
          : 0,
      inventoryClassificationKnown: inventoryClassificationKnown,
      quantityScale: _integer(value['quantityScale']) <= 0
          ? 1
          : _integer(value['quantityScale']),
      measurementType: value['measurementType']?.toString() ?? 'piece',
      unitMinor: _firstInteger(value, const [
        'unitPriceMinor',
        'unitCostMinor',
        'unitCostAtPostMinor',
      ]),
      subtotalMinor: _integer(value['subtotalMinor']),
      discountMinor: _integer(value['discountMinor']),
      taxMinor: _integer(value['taxMinor']),
      totalMinor: _firstInteger(value, const [
        'totalMinor',
        'refundMinor',
        'inventoryValueMinor',
      ]),
      reason: value['reason']?.toString(),
      batches: List.unmodifiable(batches),
      productGlobalId: productId,
      variantGlobalId: variantId,
      categoryName:
          value['categoryName']?.toString() ??
          (productId == null ? null : productCategories[productId]),
      supplierNames: List.unmodifiable(
        _supplierNames(value, labels, headerSupplier),
      ),
      supplierAllocations: List.unmodifiable(
        _supplierAllocations(value, labels, headerSupplier),
      ),
      inventoryValueMinor:
          _firstInteger(value, const [
            'inventoryValueMinor',
            'ownedInventoryValueMinor',
          ]) +
          _consignmentObligation(value),
    );
  }

  static List<String> _supplierNames(
    Map<String, Object?> value,
    Map<String, String> labels,
    String? headerSupplier,
  ) {
    final ids = <String>{};
    void collect(Object? raw) {
      if (raw is Map) {
        for (final entry in raw.entries) {
          if (entry.key.toString() == 'supplierGlobalId' &&
              entry.value != null) {
            ids.add(entry.value.toString());
          } else {
            collect(entry.value);
          }
        }
      } else if (raw is List) {
        for (final item in raw) {
          collect(item);
        }
      }
    }

    collect(value);
    if (headerSupplier != null) ids.add(headerSupplier);
    final names =
        ids.map((id) => labels['supplier:$id'] ?? id).toList(growable: false)
          ..sort();
    return names;
  }

  static List<CompanySupplierAllocationSnapshot> _supplierAllocations(
    Map<String, Object?> value,
    Map<String, String> labels,
    String? headerSupplier,
  ) {
    final lineQuantity = _integer(value['quantityScaled'] ?? value['quantity']);
    String nameOf(String id) => labels['supplier:$id'] ?? id;

    final selected = value['selectedSupplier'];
    if (selected is Map && selected['supplierGlobalId'] != null) {
      final id = selected['supplierGlobalId'].toString();
      return [
        CompanySupplierAllocationSnapshot(
          name: nameOf(id),
          quantityScaled: lineQuantity,
          sourceQuality: 'identity',
        ),
      ];
    }

    List<CompanySupplierAllocationSnapshot> fromList(
      Object? raw,
      String quality, {
      String quantityKey = 'quantityScaled',
    }) {
      if (raw is! List) return const [];
      final quantities = <String, int>{};
      for (final item in raw) {
        if (item is! Map || item['supplierGlobalId'] == null) continue;
        final id = item['supplierGlobalId'].toString();
        final quantity = _integer(item[quantityKey]).abs();
        if (quantity <= 0) continue;
        quantities.update(
          id,
          (value) => value + quantity,
          ifAbsent: () => quantity,
        );
      }
      return [
        for (final entry in quantities.entries)
          CompanySupplierAllocationSnapshot(
            name: nameOf(entry.key),
            quantityScaled: entry.value,
            sourceQuality: quality,
          ),
      ];
    }

    for (final candidate in <(Object?, String, String)>[
      (value['consignmentAllocations'], 'consignment', 'quantityScaled'),
      (value['consignmentReversals'], 'consignment', 'signedQuantityScaled'),
      (value['batchConsumptions'], 'verified', 'quantityScaled'),
      (value['batchRestorations'], 'verified', 'quantityScaled'),
      (value['originSlices'], 'allocated', 'quantityScaled'),
    ]) {
      final found = fromList(
        candidate.$1,
        candidate.$2,
        quantityKey: candidate.$3,
      );
      if (found.isNotEmpty) {
        final allocated = found.fold<int>(
          0,
          (total, item) => total + item.quantityScaled,
        );
        if (allocated < lineQuantity) {
          found.add(
            CompanySupplierAllocationSnapshot(
              name: '',
              quantityScaled: lineQuantity - allocated,
              sourceQuality: 'unverified',
            ),
          );
        }
        return found;
      }
    }
    if (headerSupplier != null && lineQuantity > 0) {
      return [
        CompanySupplierAllocationSnapshot(
          name: nameOf(headerSupplier),
          quantityScaled: lineQuantity,
          sourceQuality: 'documented',
        ),
      ];
    }
    return const [];
  }

  static int _consignmentObligation(Map<String, Object?> value) {
    var total = 0;
    void collect(Object? raw) {
      if (raw is Map) {
        for (final entry in raw.entries) {
          if (entry.key.toString() == 'obligationMinor') {
            total += _integer(entry.value);
          } else {
            collect(entry.value);
          }
        }
      } else if (raw is List) {
        for (final item in raw) {
          collect(item);
        }
      }
    }

    collect(value['consignmentAllocations']);
    return total;
  }

  static int _commissionMinor(Map<String, Object?> payload) {
    final raw = payload['commissions'];
    if (raw is! List) return 0;
    return raw.fold<int>(0, (sum, item) {
      if (item is! Map) return sum;
      return sum + _integer(item['amountMinor']);
    });
  }

  static String? _operatorLabel(Map<String, Object?> payload) {
    final employee = payload['employee'];
    if (employee is Map) {
      final name = employee['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    String? reference(Object? raw, String prefix) {
      if (raw is! Map) return null;
      final id = raw['localId'];
      return id == null ? null : '$prefix #$id';
    }

    return reference(payload['employeeRef'], 'employee') ??
        reference(payload['actorRef'], 'user');
  }

  static int _firstInteger(Map<String, Object?> value, List<String> keys) {
    for (final key in keys) {
      if (value[key] != null) return _integer(value[key]);
    }
    return 0;
  }

  static CompanyDocumentKind? _kind(String eventType) {
    if (eventType.startsWith('purchase_adjustment_return.')) {
      return CompanyDocumentKind.purchaseAdjustmentReturn;
    }
    if (eventType.startsWith('sale_adjustment_return.')) {
      return CompanyDocumentKind.saleAdjustmentReturn;
    }
    if (eventType.startsWith('purchase_return.')) {
      return CompanyDocumentKind.purchaseReturn;
    }
    if (eventType.startsWith('sale_return.')) {
      return CompanyDocumentKind.saleReturn;
    }
    if (eventType.startsWith('purchase.')) {
      return CompanyDocumentKind.purchase;
    }
    if (eventType.startsWith('sale.')) {
      return CompanyDocumentKind.sale;
    }
    return null;
  }

  static String _number(Map<String, Object?> payload) =>
      payload['purchaseNumber']?.toString() ??
      payload['invoiceNumber']?.toString() ??
      payload['returnNumber']?.toString() ??
      payload['documentId']?.toString() ??
      '';

  static DateTime? _documentDate(Map<String, Object?> payload) {
    final value =
        payload['purchaseDate'] ?? payload['saleDate'] ?? payload['returnDate'];
    return value == null ? null : DateTime.tryParse(value.toString())?.toUtc();
  }

  static int _integer(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _displayName(String name, String code) =>
      name.trim().isEmpty ? code : name.trim();
}
