import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// A read-only event-shaped view of documents owned by the current database.
///
/// The company monitor normally consumes immutable synchronization events. Some
/// historical and imported local documents predate that ledger, so they still
/// need a canonical projection when a company or branch report includes the
/// coordinator's own books. This reader never writes identities or events.
class LocalCompanyDocumentProjection {
  const LocalCompanyDocumentProjection({
    required this.eventType,
    required this.sourceDatabaseId,
    required this.payload,
    required this.occurredAt,
  });

  final String eventType;
  final String sourceDatabaseId;
  final Map<String, Object?> payload;
  final DateTime occurredAt;
}

class LocalCompanyDocumentProjectionReader {
  const LocalCompanyDocumentProjectionReader(this._db);

  final AppDatabase _db;

  Future<List<LocalCompanyDocumentProjection>> load({
    required String organizationId,
    required String databaseId,
  }) async {
    final headers = await _db
        .customSelect(
          '''WITH local_locations AS (
        SELECT * FROM business_document_locations
        WHERE organization_id=? AND origin_database_id=?
      )
      SELECT 'purchase' AS document_kind,'purchase.posted.v1' AS event_type,
        'purchases' AS source_table,p.id AS source_id,l.document_id,
        l.branch_id,l.warehouse_id,p.purchase_number AS document_number,
        p.purchase_date AS document_date,p.created_at AS occurred_at,
        c.code AS currency_code,s.name AS party_name,
        COALESCE(si.global_id,'local:supplier:' || s.id) AS party_global_id,
        p.payment_method,p.subtotal_cents AS subtotal_minor,
        p.discount_cents AS discount_minor,p.tax_cents AS tax_minor,
        p.total_cents AS total_minor,p.paid_amount_cents AS paid_minor,
        p.notes,NULL AS original_document_id,p.status,
        NULL AS restores_sellable_stock,NULL AS employee_name,
        0 AS commission_minor,0 AS commission_known
      FROM purchases p JOIN local_locations l
        ON l.source_table='purchases' AND l.source_id=p.id
      JOIN currencies c ON c.id=p.currency_id
      JOIN suppliers s ON s.id=p.supplier_id
      LEFT JOIN sync_entity_identities si
        ON si.entity_type='supplier' AND si.local_id=s.id
      WHERE p.status IN ('posted','voided')
      UNION ALL
      SELECT 'sale','sale.posted.v1','sales',s.id,l.document_id,
        l.branch_id,l.warehouse_id,s.invoice_number,s.sale_date,s.created_at,
        c.code,cu.name,
        CASE WHEN cu.id IS NULL THEN NULL
          ELSE COALESCE(ci.global_id,'local:customer:' || cu.id) END,
        s.payment_method,s.subtotal_cents,s.discount_cents,s.tax_cents,
        s.total_cents,s.paid_amount_cents,s.notes,NULL,s.status,
        NULL,e.name,
        COALESCE((SELECT SUM(cm.commission_amount_cents) FROM commissions cm
          WHERE cm.sale_id=s.id AND cm.sale_return_id IS NULL
            AND cm.sale_return_adjustment_id IS NULL),0),1
      FROM sales s JOIN local_locations l
        ON l.source_table='sales' AND l.source_id=s.id
      JOIN currencies c ON c.id=s.currency_id
      LEFT JOIN customers cu ON cu.id=s.customer_id
      LEFT JOIN sync_entity_identities ci
        ON ci.entity_type='customer' AND ci.local_id=cu.id
      LEFT JOIN employees e ON e.id=s.employee_id
      WHERE s.status IN ('completed','posted','voided')
      UNION ALL
      SELECT 'purchase_return','purchase_return.posted.v1',
        'purchase_returns',r.id,l.document_id,l.branch_id,l.warehouse_id,
        r.return_number,r.return_date,r.created_at,c.code,s.name,
        COALESCE(si.global_id,'local:supplier:' || s.id),r.refund_method,
        r.subtotal_cents,r.discount_cents,r.tax_cents,r.total_cents,0,
        r.reason,source_location.document_id,r.status,
        NULL,NULL,0,0
      FROM purchase_returns r JOIN local_locations l
        ON l.source_table='purchase_returns' AND l.source_id=r.id
      JOIN purchases p ON p.id=r.purchase_id
      JOIN suppliers s ON s.id=p.supplier_id
      JOIN currencies c ON c.id=r.currency_id
      LEFT JOIN sync_entity_identities si
        ON si.entity_type='supplier' AND si.local_id=s.id
      LEFT JOIN business_document_locations source_location
        ON source_location.source_table='purchases'
          AND source_location.source_id=r.purchase_id
      WHERE r.status IN ('posted','voided')
      UNION ALL
      SELECT 'sale_return','sale_return.posted.v1','sale_returns',
        r.id,l.document_id,l.branch_id,l.warehouse_id,r.return_number,
        r.return_date,r.created_at,c.code,cu.name,
        CASE WHEN cu.id IS NULL THEN NULL
          ELSE COALESCE(ci.global_id,'local:customer:' || cu.id) END,
        r.refund_method,r.subtotal_cents,r.discount_cents,r.tax_cents,
        r.total_cents,0,r.reason,source_location.document_id,r.status,
        CASE WHEN r.disposition_type IN ('write_off','damaged','scrap')
          THEN 0 ELSE 1 END,e.name,
        COALESCE((SELECT SUM(cm.commission_amount_cents) FROM commissions cm
          WHERE cm.sale_return_id=r.id),0),1
      FROM sale_returns r JOIN local_locations l
        ON l.source_table='sale_returns' AND l.source_id=r.id
      JOIN sales s ON s.id=r.sale_id
      JOIN currencies c ON c.id=r.currency_id
      LEFT JOIN customers cu ON cu.id=s.customer_id
      LEFT JOIN sync_entity_identities ci
        ON ci.entity_type='customer' AND ci.local_id=cu.id
      LEFT JOIN employees e ON e.id=s.employee_id
      LEFT JOIN business_document_locations source_location
        ON source_location.source_table='sales'
          AND source_location.source_id=r.sale_id
      WHERE r.status IN ('posted','voided')
      UNION ALL
      SELECT 'purchase_adjustment_return',
        'purchase_adjustment_return.posted.v1',
        'purchase_return_adjustments',r.id,l.document_id,
        l.branch_id,l.warehouse_id,r.return_number,r.return_date,r.created_at,
        c.code,s.name,COALESCE(si.global_id,'local:supplier:' || s.id),
        r.refund_method,r.subtotal_cents,r.discount_cents,r.tax_cents,
        r.total_cents,0,r.notes,NULL,r.status,NULL,NULL,0,0
      FROM purchase_return_adjustments r JOIN local_locations l
        ON l.source_table='purchase_return_adjustments' AND l.source_id=r.id
      JOIN currencies c ON c.id=r.currency_id
      JOIN suppliers s ON s.id=r.supplier_id
      LEFT JOIN sync_entity_identities si
        ON si.entity_type='supplier' AND si.local_id=s.id
      WHERE r.status IN ('posted','voided')
      UNION ALL
      SELECT 'sale_adjustment_return','sale_adjustment_return.posted.v1',
        'sale_return_adjustments',r.id,l.document_id,l.branch_id,l.warehouse_id,
        r.return_number,r.return_date,r.created_at,c.code,cu.name,
        CASE WHEN cu.id IS NULL THEN NULL
          ELSE COALESCE(ci.global_id,'local:customer:' || cu.id) END,
        r.refund_method,r.subtotal_cents,r.discount_cents,r.tax_cents,
        r.total_cents,0,r.notes,NULL,r.status,NULL,e.name,
        COALESCE((SELECT SUM(cm.commission_amount_cents) FROM commissions cm
          WHERE cm.sale_return_adjustment_id=r.id),0),1
      FROM sale_return_adjustments r JOIN local_locations l
        ON l.source_table='sale_return_adjustments' AND l.source_id=r.id
      JOIN currencies c ON c.id=r.currency_id
      LEFT JOIN customers cu ON cu.id=r.customer_id
      LEFT JOIN sync_entity_identities ci
        ON ci.entity_type='customer' AND ci.local_id=cu.id
      LEFT JOIN employees e ON e.id=r.employee_id
      WHERE r.status IN ('posted','voided')''',
          variables: [
            Variable.withString(organizationId),
            Variable.withString(databaseId),
          ],
        )
        .get();

    final lines = <String, List<Map<String, Object?>>>{};
    for (final specification in _lineSpecifications) {
      final rows = await _db.customSelect(specification.sql).get();
      for (final row in rows) {
        final key =
            '${specification.sourceTable}:${row.read<int>('source_id')}';
        lines.putIfAbsent(key, () => []).add(_linePayload(row));
      }
    }
    await _attachPurchaseBatches(lines);
    await _attachSaleSources(lines);

    return [
      for (final row in headers)
        _projection(
          row,
          databaseId,
          lines['${row.read<String>('source_table')}:'
                  '${row.read<int>('source_id')}'] ??
              const [],
        ),
    ];
  }

  LocalCompanyDocumentProjection _projection(
    QueryRow row,
    String databaseId,
    List<Map<String, Object?>> items,
  ) {
    final documentDate = _date(row.read<String>('document_date'));
    final occurredAt = _date(row.read<String>('occurred_at'));
    final employeeName = row.readNullable<String>('employee_name');
    final partyName = row.readNullable<String>('party_name');
    final partyGlobalId = row.readNullable<String>('party_global_id');
    final originalDocumentId = row.readNullable<String>('original_document_id');
    final restoresStock = row.readNullable<int>('restores_sellable_stock');
    final purchaseSide = row
        .read<String>('document_kind')
        .startsWith('purchase');
    final commissionKnown = row.read<int>('commission_known') == 1;
    final commissionMinor = row.read<int>('commission_minor');
    final payload = <String, Object?>{
      'documentId': row.read<String>('document_id'),
      'branchId': row.read<String>('branch_id'),
      'warehouseId': row.read<String>('warehouse_id'),
      'currencyCode': row.read<String>('currency_code'),
      'paymentMethod': row.readNullable<String>('payment_method'),
      'subtotalMinor': row.read<int>('subtotal_minor'),
      'discountMinor': row.read<int>('discount_minor'),
      'taxMinor': row.read<int>('tax_minor'),
      'totalMinor': row.read<int>('total_minor'),
      'paidMinor': row.read<int>('paid_minor'),
      'notes': row.readNullable<String>('notes'),
      'itemCount': items.length,
      'items': items,
      '_isVoided': row.read<String>('status') == 'voided',
      if (commissionKnown)
        'commissions': [
          if (commissionMinor != 0) {'amountMinor': commissionMinor},
        ],
    };
    if (partyName != null) {
      payload[purchaseSide ? 'supplierName' : 'customerName'] = partyName;
    }
    if (partyGlobalId != null) {
      payload[purchaseSide ? 'supplierGlobalId' : 'customerGlobalId'] =
          partyGlobalId;
    }
    if (originalDocumentId != null) {
      payload[purchaseSide
              ? 'originalPurchaseDocumentId'
              : 'originalSaleDocumentId'] =
          originalDocumentId;
    }
    if (restoresStock != null) {
      payload['restoresSellableStock'] = restoresStock == 1;
    }
    if (employeeName != null) {
      payload['employee'] = {'name': employeeName};
    }
    final kind = row.read<String>('document_kind');
    final number = row.read<String>('document_number');
    if (kind == 'purchase') {
      payload['purchaseNumber'] = number;
      payload['purchaseDate'] = documentDate.toIso8601String();
    } else if (kind == 'sale') {
      payload['invoiceNumber'] = number;
      payload['saleDate'] = documentDate.toIso8601String();
    } else {
      payload['returnNumber'] = number;
      payload['returnDate'] = documentDate.toIso8601String();
    }
    return LocalCompanyDocumentProjection(
      eventType: row.read<String>('event_type'),
      sourceDatabaseId: databaseId,
      payload: payload,
      occurredAt: occurredAt,
    );
  }

  static Map<String, Object?> _linePayload(QueryRow row) {
    final variant = row.readNullable<String>('variant_name');
    return <String, Object?>{
      'lineRef': {'localId': row.read<int>('line_id')},
      'productGlobalId': row.read<String>('product_global_id'),
      'productName': row.read<String>('product_name'),
      'productSku': row.readNullable<String>('product_sku'),
      'variantGlobalId': row.readNullable<String>('variant_global_id'),
      'variantName': variant,
      'variantSku': variant,
      'categoryName': row.readNullable<String>('category_name'),
      'quantityScaled': row.read<int>('quantity_scaled'),
      'quantityScale': row.read<int>('quantity_scale'),
      'measurementType': row.read<String>('measurement_type'),
      'tracksInventory': row.read<int>('tracks_inventory') == 1,
      'unitPriceMinor': row.read<int>('unit_minor'),
      'unitCostMinor': row.read<int>('unit_minor'),
      'subtotalMinor': row.read<int>('subtotal_minor'),
      'discountMinor': row.read<int>('discount_minor'),
      'taxMinor': row.read<int>('tax_minor'),
      'totalMinor': row.read<int>('total_minor'),
      'inventoryValueMinor': row.read<int>('inventory_value_minor'),
      'ownedInventoryValueMinor': row.read<int>('inventory_value_minor'),
      'reason': row.readNullable<String>('reason'),
      'dispositionType': row.readNullable<String>('disposition_type'),
      '_sourceLineId': row.read<int>('source_line_id'),
      if (row.readNullable<String>('supplier_global_id') case final id?)
        'selectedSupplier': {'supplierGlobalId': id},
    };
  }

  Future<void> _attachPurchaseBatches(
    Map<String, List<Map<String, Object?>>> lines,
  ) async {
    final batches = await _db.customSelect(
      '''SELECT b.purchase_item_id,b.batch_number,b.manufacturer_lot_number,
        b.received_quantity,b.expiry_date
      FROM product_batches b WHERE b.purchase_item_id IS NOT NULL
      ORDER BY b.purchase_item_id,b.id''',
    ).get();
    final byLine = <int, List<Map<String, Object?>>>{};
    for (final row in batches) {
      byLine.putIfAbsent(row.read<int>('purchase_item_id'), () => []).add({
        'batchNumber': row.read<String>('batch_number'),
        'manufacturerLotNumber': row.readNullable<String>(
          'manufacturer_lot_number',
        ),
        'quantityScaled': row.read<int>('received_quantity'),
        'expiryDate': row.readNullable<String>('expiry_date'),
      });
    }
    for (final entry in lines.entries) {
      if (!entry.key.startsWith('purchases:')) continue;
      for (final line in entry.value) {
        final batches = byLine[line['_sourceLineId']];
        if (batches != null) line['batches'] = batches;
      }
    }
  }

  Future<void> _attachSaleSources(
    Map<String, List<Map<String, Object?>>> lines,
  ) async {
    final batchRows = await _db.customSelect(
      '''SELECT bc.sale_item_id,bc.quantity,b.supplier_id,
        COALESCE(si.global_id,'local:supplier:' || b.supplier_id)
          AS supplier_global_id
      FROM batch_consumptions bc
      JOIN product_batches b ON b.id=bc.batch_id
      LEFT JOIN sync_entity_identities si
        ON si.entity_type='supplier' AND si.local_id=b.supplier_id
      WHERE bc.sale_item_id IS NOT NULL AND bc.direction='out'
        AND bc.consumption_type='sale' ORDER BY bc.id''',
    ).get();
    final batchSources = <int, List<Map<String, Object?>>>{};
    for (final row in batchRows) {
      final source = <String, Object?>{
        'quantityScaled': row.read<int>('quantity'),
      };
      final supplierId = row.readNullable<String>('supplier_global_id');
      if (supplierId != null) source['supplierGlobalId'] = supplierId;
      batchSources
          .putIfAbsent(row.read<int>('sale_item_id'), () => [])
          .add(source);
    }

    final consignmentRows = await _db.customSelect(
      '''SELECT a.sale_item_id,a.quantity,a.obligation_cents,
        COALESCE(si.global_id,'local:supplier:' || a.supplier_id)
          AS supplier_global_id
      FROM consignment_sale_allocations a
      LEFT JOIN sync_entity_identities si
        ON si.entity_type='supplier' AND si.local_id=a.supplier_id
      ORDER BY a.sale_item_id,a.sequence''',
    ).get();
    final consignment = <int, List<Map<String, Object?>>>{};
    for (final row in consignmentRows) {
      consignment.putIfAbsent(row.read<int>('sale_item_id'), () => []).add({
        'quantityScaled': row.read<int>('quantity'),
        'obligationMinor': row.read<int>('obligation_cents'),
        'supplierGlobalId': row.read<String>('supplier_global_id'),
      });
    }

    final originRows = await _db.customSelect(
      '''SELECT event_key,allocations FROM inventory_origin_events
          WHERE event_key LIKE 'sale:%' ''',
    ).get();
    final originSources = <int, List<Map<String, Object?>>>{};
    for (final row in originRows) {
      final id = int.tryParse(row.read<String>('event_key').split(':').last);
      final decoded = jsonDecode(row.read<String>('allocations'));
      if (id == null || decoded is! List) continue;
      final values = <Map<String, Object?>>[];
      for (final raw in decoded) {
        if (raw is! Map) continue;
        final item = Map<String, Object?>.from(raw);
        final quantity = item['q'];
        if (quantity is! int || quantity <= 0) continue;
        final supplierId = item['s'];
        values.add({
          'quantityScaled': quantity,
          if (supplierId is int)
            'supplierGlobalId': 'local:supplier:$supplierId',
        });
      }
      if (values.isNotEmpty) originSources[id] = values;
    }

    for (final entry in lines.entries) {
      if (!entry.key.startsWith('sales:') &&
          !entry.key.startsWith('sale_returns:') &&
          !entry.key.startsWith('sale_return_adjustments:')) {
        continue;
      }
      for (final line in entry.value) {
        final sourceId = line['_sourceLineId'];
        if (sourceId is! int) continue;
        if (batchSources[sourceId] case final values?) {
          line['batchConsumptions'] = values;
        } else if (originSources[sourceId] case final values?) {
          line['originSlices'] = values;
        }
        if (consignment[sourceId] case final values?) {
          line['consignmentAllocations'] = values;
        }
      }
    }
  }

  static DateTime _date(String value) =>
      (DateTime.tryParse(value) ?? DateTime.fromMillisecondsSinceEpoch(0))
          .toUtc();
}

class _LineSpecification {
  const _LineSpecification(this.sourceTable, this.sql);

  final String sourceTable;
  final String sql;
}

const _lineSpecifications = <_LineSpecification>[
  _LineSpecification(
    'purchases',
    '''SELECT i.purchase_id AS source_id,i.id AS line_id,i.id AS source_line_id,
      COALESCE(pi.global_id,'local:product:' || p.id) AS product_global_id,
      p.name AS product_name,p.sku AS product_sku,
      CASE WHEN v.id IS NULL THEN NULL
        ELSE COALESCE(vi.global_id,'local:product_variant:' || v.id) END
        AS variant_global_id,
      v.sku AS variant_name,pc.name AS category_name,i.quantity AS quantity_scaled,
      i.quantity_scale,i.measurement_type,p.track_inventory AS tracks_inventory,
      i.unit_cost_cents AS unit_minor,i.subtotal_cents AS subtotal_minor,
      i.discount_cents AS discount_minor,i.tax_cents AS tax_minor,
      i.total_cents AS total_minor,
      COALESCE(i.inventory_value_at_post_cents,
        CAST(i.unit_cost_cents * i.quantity / i.quantity_scale AS INTEGER),0)
        AS inventory_value_minor,NULL AS reason,NULL AS disposition_type,
      NULL AS supplier_global_id
    FROM purchase_items i JOIN products p ON p.id=i.product_id
    LEFT JOIN product_variants v ON v.id=i.variant_id
    LEFT JOIN product_categories pc ON pc.id=p.category_id
    LEFT JOIN sync_entity_identities pi
      ON pi.entity_type='product' AND pi.local_id=p.id
    LEFT JOIN sync_entity_identities vi
      ON vi.entity_type='product_variant' AND vi.local_id=v.id
    ORDER BY i.purchase_id,i.id''',
  ),
  _LineSpecification(
    'sales',
    '''SELECT i.sale_id AS source_id,i.id AS line_id,i.id AS source_line_id,
      COALESCE(pi.global_id,'local:product:' || p.id) AS product_global_id,
      p.name AS product_name,p.sku AS product_sku,
      CASE WHEN v.id IS NULL THEN NULL
        ELSE COALESCE(vi.global_id,'local:product_variant:' || v.id) END
        AS variant_global_id,
      v.sku AS variant_name,pc.name AS category_name,i.quantity AS quantity_scaled,
      i.quantity_scale,i.measurement_type,p.track_inventory AS tracks_inventory,
      i.unit_price_cents AS unit_minor,i.subtotal_cents AS subtotal_minor,
      i.discount_cents AS discount_minor,i.tax_cents AS tax_minor,
      i.total_cents AS total_minor,
      COALESCE(i.inventory_value_at_post_cents,
        CAST(COALESCE(i.cost_cents,0) * i.quantity / i.quantity_scale AS INTEGER),0)
        AS inventory_value_minor,NULL AS reason,NULL AS disposition_type,
      CASE WHEN spi.supplier_id IS NULL THEN NULL
        ELSE COALESCE(sui.global_id,'local:supplier:' || spi.supplier_id) END
        AS supplier_global_id
    FROM sale_items i JOIN products p ON p.id=i.product_id
    LEFT JOIN product_variants v ON v.id=i.variant_id
    LEFT JOIN product_categories pc ON pc.id=p.category_id
    LEFT JOIN supplier_product_identities spi ON spi.id=i.supplier_identity_id
    LEFT JOIN sync_entity_identities sui
      ON sui.entity_type='supplier' AND sui.local_id=spi.supplier_id
    LEFT JOIN sync_entity_identities pi
      ON pi.entity_type='product' AND pi.local_id=p.id
    LEFT JOIN sync_entity_identities vi
      ON vi.entity_type='product_variant' AND vi.local_id=v.id
    ORDER BY i.sale_id,i.id''',
  ),
  _LineSpecification(
    'purchase_returns',
    '''SELECT i.return_id AS source_id,i.id AS line_id,pi.id AS source_line_id,
      COALESCE(pgi.global_id,'local:product:' || p.id) AS product_global_id,
      p.name AS product_name,p.sku AS product_sku,
      CASE WHEN v.id IS NULL THEN NULL
        ELSE COALESCE(vi.global_id,'local:product_variant:' || v.id) END
        AS variant_global_id,
      v.sku AS variant_name,pc.name AS category_name,i.quantity AS quantity_scaled,
      i.quantity_scale,i.measurement_type,p.track_inventory AS tracks_inventory,
      COALESCE(i.unit_cost_at_post_cents,pi.unit_cost_cents) AS unit_minor,
      i.subtotal_cents AS subtotal_minor,i.discount_cents AS discount_minor,
      i.tax_cents AS tax_minor,i.refund_cents AS total_minor,
      COALESCE(i.inventory_value_at_post_cents,
        CAST(COALESCE(i.unit_cost_at_post_cents,pi.unit_cost_cents) *
          i.quantity / i.quantity_scale AS INTEGER),0) AS inventory_value_minor,
      i.reason,NULL AS disposition_type,NULL AS supplier_global_id
    FROM purchase_return_items i JOIN purchase_items pi ON pi.id=i.purchase_item_id
    JOIN products p ON p.id=pi.product_id
    LEFT JOIN product_variants v ON v.id=pi.variant_id
    LEFT JOIN product_categories pc ON pc.id=p.category_id
    LEFT JOIN sync_entity_identities pgi
      ON pgi.entity_type='product' AND pgi.local_id=p.id
    LEFT JOIN sync_entity_identities vi
      ON vi.entity_type='product_variant' AND vi.local_id=v.id
    ORDER BY i.return_id,i.id''',
  ),
  _LineSpecification(
    'sale_returns',
    '''SELECT i.return_id AS source_id,i.id AS line_id,si.id AS source_line_id,
      COALESCE(pgi.global_id,'local:product:' || p.id) AS product_global_id,
      p.name AS product_name,p.sku AS product_sku,
      CASE WHEN v.id IS NULL THEN NULL
        ELSE COALESCE(vi.global_id,'local:product_variant:' || v.id) END
        AS variant_global_id,
      v.sku AS variant_name,pc.name AS category_name,i.quantity AS quantity_scaled,
      i.quantity_scale,i.measurement_type,p.track_inventory AS tracks_inventory,
      COALESCE(i.unit_cost_at_post_cents,si.unit_price_cents) AS unit_minor,
      i.subtotal_cents AS subtotal_minor,i.discount_cents AS discount_minor,
      i.tax_cents AS tax_minor,i.refund_cents AS total_minor,
      COALESCE(i.inventory_value_at_post_cents,
        CAST(COALESCE(i.unit_cost_at_post_cents,si.cost_cents,0) *
          i.quantity / i.quantity_scale AS INTEGER),0) AS inventory_value_minor,
      i.reason,NULL AS disposition_type,
      CASE WHEN spi.supplier_id IS NULL THEN NULL
        ELSE COALESCE(sui.global_id,'local:supplier:' || spi.supplier_id) END
        AS supplier_global_id
    FROM sale_return_items i JOIN sale_items si ON si.id=i.sale_item_id
    JOIN products p ON p.id=si.product_id
    LEFT JOIN product_variants v ON v.id=si.variant_id
    LEFT JOIN product_categories pc ON pc.id=p.category_id
    LEFT JOIN supplier_product_identities spi ON spi.id=si.supplier_identity_id
    LEFT JOIN sync_entity_identities sui
      ON sui.entity_type='supplier' AND sui.local_id=spi.supplier_id
    LEFT JOIN sync_entity_identities pgi
      ON pgi.entity_type='product' AND pgi.local_id=p.id
    LEFT JOIN sync_entity_identities vi
      ON vi.entity_type='product_variant' AND vi.local_id=v.id
    ORDER BY i.return_id,i.id''',
  ),
  _LineSpecification(
    'purchase_return_adjustments',
    '''SELECT i.return_id AS source_id,i.id AS line_id,i.id AS source_line_id,
      COALESCE(pgi.global_id,'local:product:' || p.id) AS product_global_id,
      p.name AS product_name,p.sku AS product_sku,
      CASE WHEN v.id IS NULL THEN NULL
        ELSE COALESCE(vi.global_id,'local:product_variant:' || v.id) END
        AS variant_global_id,
      v.sku AS variant_name,pc.name AS category_name,i.quantity AS quantity_scaled,
      i.quantity_scale,i.measurement_type,p.track_inventory AS tracks_inventory,
      i.unit_price_cents AS unit_minor,
      i.total_cents+i.discount_cents-i.tax_cents AS subtotal_minor,
      i.discount_cents AS discount_minor,i.tax_cents AS tax_minor,
      i.total_cents AS total_minor,
      COALESCE(i.inventory_value_at_post_cents,
        CAST(COALESCE(i.unit_cost_at_post_cents,i.unit_cost_cents) *
          i.quantity / i.quantity_scale AS INTEGER),0) AS inventory_value_minor,
      i.reason,i.disposition_type,NULL AS supplier_global_id
    FROM purchase_return_adjustment_items i JOIN products p ON p.id=i.product_id
    LEFT JOIN product_variants v ON v.id=i.variant_id
    LEFT JOIN product_categories pc ON pc.id=p.category_id
    LEFT JOIN sync_entity_identities pgi
      ON pgi.entity_type='product' AND pgi.local_id=p.id
    LEFT JOIN sync_entity_identities vi
      ON vi.entity_type='product_variant' AND vi.local_id=v.id
    ORDER BY i.return_id,i.id''',
  ),
  _LineSpecification(
    'sale_return_adjustments',
    '''SELECT i.return_id AS source_id,i.id AS line_id,i.id AS source_line_id,
      COALESCE(pgi.global_id,'local:product:' || p.id) AS product_global_id,
      p.name AS product_name,p.sku AS product_sku,
      CASE WHEN v.id IS NULL THEN NULL
        ELSE COALESCE(vi.global_id,'local:product_variant:' || v.id) END
        AS variant_global_id,
      v.sku AS variant_name,pc.name AS category_name,i.quantity AS quantity_scaled,
      i.quantity_scale,i.measurement_type,p.track_inventory AS tracks_inventory,
      i.unit_price_cents AS unit_minor,
      i.total_cents+i.discount_cents-i.tax_cents AS subtotal_minor,
      i.discount_cents AS discount_minor,i.tax_cents AS tax_minor,
      i.total_cents AS total_minor,
      COALESCE(i.inventory_value_at_post_cents,
        CAST(COALESCE(i.unit_cost_at_post_cents,i.unit_cost_cents) *
          i.quantity / i.quantity_scale AS INTEGER),0) AS inventory_value_minor,
      i.reason,i.disposition_type,
      CASE WHEN spi.supplier_id IS NULL THEN NULL
        ELSE COALESCE(sui.global_id,'local:supplier:' || spi.supplier_id) END
        AS supplier_global_id
    FROM sale_return_adjustment_items i JOIN products p ON p.id=i.product_id
    LEFT JOIN product_variants v ON v.id=i.variant_id
    LEFT JOIN product_categories pc ON pc.id=p.category_id
    LEFT JOIN supplier_product_identities spi ON spi.id=i.supplier_identity_id
    LEFT JOIN sync_entity_identities sui
      ON sui.entity_type='supplier' AND sui.local_id=spi.supplier_id
    LEFT JOIN sync_entity_identities pgi
      ON pgi.entity_type='product' AND pgi.local_id=p.id
    LEFT JOIN sync_entity_identities vi
      ON vi.entity_type='product_variant' AND vi.local_id=v.id
    ORDER BY i.return_id,i.id''',
  ),
];
