import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/business/warehouse_read_scope.dart';

typedef AuthorizeWarehouseTransferReport =
    Future<void> Function(String warehouseId);

class WarehouseTransferSourceSlice {
  const WarehouseTransferSourceSlice({
    required this.quantity,
    required this.quality,
    this.supplierId,
    this.supplierName = '',
    this.purchaseNumber = '',
  });

  final int quantity;
  final String quality;
  final int? supplierId;
  final String supplierName;
  final String purchaseNumber;
}

class WarehouseTransferReportRow {
  const WarehouseTransferReportRow({
    required this.transferId,
    required this.status,
    required this.recalled,
    required this.dispatchedAt,
    required this.sourceWarehouseId,
    required this.sourceWarehouse,
    required this.destinationWarehouseId,
    required this.destinationWarehouse,
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.variantLabel,
    required this.code,
    required this.ownerType,
    required this.quantityScale,
    required this.measurementType,
    required this.dispatchedQuantity,
    required this.acceptedQuantity,
    required this.damagedQuantity,
    required this.lostQuantity,
    required this.recalledQuantity,
    required this.dispatchedValueCents,
    required this.acceptedValueCents,
    required this.varianceValueCents,
    required this.recalledValueCents,
    required this.currencyCode,
    required this.sources,
  });

  final String transferId;
  final String status;
  final bool recalled;
  final DateTime dispatchedAt;
  final String sourceWarehouseId;
  final String sourceWarehouse;
  final String destinationWarehouseId;
  final String destinationWarehouse;
  final int productId;
  final int variantId;
  final String productName;
  final String variantLabel;
  final String code;
  final String ownerType;
  final int quantityScale;
  final String measurementType;
  final int dispatchedQuantity;
  final int acceptedQuantity;
  final int damagedQuantity;
  final int lostQuantity;
  final int recalledQuantity;
  final int dispatchedValueCents;
  final int acceptedValueCents;
  final int varianceValueCents;
  final int recalledValueCents;
  final String currencyCode;
  final List<WarehouseTransferSourceSlice> sources;

  int get inTransitQuantity =>
      dispatchedQuantity -
      acceptedQuantity -
      damagedQuantity -
      lostQuantity -
      recalledQuantity;

  int get inTransitValueCents =>
      dispatchedValueCents -
      acceptedValueCents -
      varianceValueCents -
      recalledValueCents;
}

class WarehouseTransferReportData {
  const WarehouseTransferReportData({
    required this.warehouseId,
    required this.from,
    required this.toExclusive,
    required this.rows,
  });

  final String warehouseId;
  final DateTime from;
  final DateTime toExclusive;
  final List<WarehouseTransferReportRow> rows;

  int get transferCount => rows.map((row) => row.transferId).toSet().length;
  int get acceptedValueCents =>
      rows.fold(0, (sum, row) => sum + row.acceptedValueCents);
  int get varianceValueCents =>
      rows.fold(0, (sum, row) => sum + row.varianceValueCents);
  int get inTransitValueCents =>
      rows.fold(0, (sum, row) => sum + row.inTransitValueCents);
}

/// Read model for posted warehouse transfers. All values come from immutable
/// dispatch, receipt and recall documents. Supplier provenance is resolved from
/// the exact consignment layer, FIFO batch or WAC origin allocation captured at
/// dispatch; product preferred-supplier fields are never used as evidence.
class WarehouseTransferReportingService {
  const WarehouseTransferReportingService(
    this.db, {
    required this.authorizeWarehouse,
  });

  final AppDatabase db;
  final AuthorizeWarehouseTransferReport authorizeWarehouse;

  Future<WarehouseTransferReportData> report({
    required String warehouseId,
    required DateTime from,
    required DateTime toExclusive,
    String direction = 'all',
    String ownership = 'all',
    String status = 'all',
    int? supplierId,
    String search = '',
    int limit = 1000,
  }) => db.transaction(() async {
    if (!const {'all', 'incoming', 'outgoing'}.contains(direction)) {
      throw ArgumentError.value(direction, 'direction');
    }
    if (!const {'all', 'owned', 'consignment'}.contains(ownership)) {
      throw ArgumentError.value(ownership, 'ownership');
    }
    if (!const {
      'all',
      'in_transit',
      'partially_received',
      'completed',
      'cancelled',
      'recalled',
    }.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    final start = from.toUtc();
    final end = toExclusive.toUtc();
    if (!end.isAfter(start) || end.difference(start).inDays > 3660) {
      throw ArgumentError('Invalid transfer report period');
    }
    if (limit < 1 || limit > 5000) throw ArgumentError.value(limit, 'limit');
    await authorizeWarehouse(warehouseId);
    final scope = await WarehouseReadScope.resolve(
      db,
      warehouseId: warehouseId,
    );
    await scope.validate(db);

    final where = <String>[
      'd.sealed=1',
      '(t.source_warehouse_id=? OR t.destination_warehouse_id=?)',
      'CAST(d.dispatched_at AS TEXT)>=?',
      'CAST(d.dispatched_at AS TEXT)<?',
    ];
    final variables = <Variable<Object>>[
      Variable.withString(warehouseId),
      Variable.withString(warehouseId),
      Variable.withString(start.toIso8601String()),
      Variable.withString(end.toIso8601String()),
    ];
    if (direction == 'incoming') {
      where.add('t.destination_warehouse_id=?');
      variables.add(Variable.withString(warehouseId));
    } else if (direction == 'outgoing') {
      where.add('t.source_warehouse_id=?');
      variables.add(Variable.withString(warehouseId));
    }
    if (ownership != 'all') {
      where.add('a.owner_type=?');
      variables.add(Variable.withString(ownership));
    }
    if (status != 'all') {
      if (status == 'recalled') {
        where.add('recall.id IS NOT NULL');
      } else {
        where.add('t.status=?');
        variables.add(Variable.withString(status));
        if (status == 'cancelled') where.add('recall.id IS NULL');
      }
    }
    final term = search.trim().toLowerCase();
    variables.add(Variable.withInt(limit));

    final raw = await db.customSelect('''
      SELECT t.id AS transfer_id,t.status,CAST(d.dispatched_at AS TEXT) AS dispatched_at,
        t.source_warehouse_id,sw.name AS source_name,sw.code AS source_code,
        t.destination_warehouse_id,dw.name AS destination_name,dw.code AS destination_code,
        l.product_id,l.variant_id,p.name AS product_name,
        TRIM(COALESCE(pc.name,'')||' '||COALESCE(sz.name,'')) AS variant_label,
        COALESCE(v.sku,v.barcode,p.sku,p.barcode,'') AS code,
        a.id AS allocation_id,a.owner_type,a.quantity,a.quantity_scale,a.measurement_type,
        a.value_cents,a.source_batch_id,a.supplier_id,
        c.code AS currency_code,
        COALESCE(SUM(CASE WHEN receipt.sealed=1 THEN ri.accepted_quantity ELSE 0 END),0) AS accepted_quantity,
        COALESCE(SUM(CASE WHEN receipt.sealed=1 THEN ri.damaged_quantity ELSE 0 END),0) AS damaged_quantity,
        COALESCE(SUM(CASE WHEN receipt.sealed=1 THEN ri.lost_quantity ELSE 0 END),0) AS lost_quantity,
        COALESCE(SUM(CASE WHEN receipt.sealed=1 THEN ri.accepted_value_cents ELSE 0 END),0) AS accepted_value_cents,
        COALESCE(SUM(CASE WHEN receipt.sealed=1 THEN ri.variance_value_cents ELSE 0 END),0) AS variance_value_cents,
        COALESCE(MAX(CASE WHEN recall.sealed=1 THEN rci.quantity ELSE 0 END),0) AS recalled_quantity,
        COALESCE(MAX(CASE WHEN recall.sealed=1 THEN rci.value_cents ELSE 0 END),0) AS recalled_value_cents,
        MAX(CASE WHEN recall.sealed=1 THEN 1 ELSE 0 END) AS recalled
      FROM warehouse_transfer_allocations a
      JOIN warehouse_transfer_dispatches d ON d.id=a.dispatch_id
      JOIN warehouse_transfers t ON t.id=d.transfer_id
      JOIN warehouse_transfer_lines l ON l.id=a.line_id
      JOIN products p ON p.id=l.product_id
      JOIN product_variants v ON v.id=l.variant_id
      LEFT JOIN product_colors pc ON pc.id=v.color_id
      LEFT JOIN sizes sz ON sz.id=v.size_id
      JOIN business_warehouses sw ON sw.id=t.source_warehouse_id
      JOIN business_warehouses dw ON dw.id=t.destination_warehouse_id
      JOIN currencies c ON c.id=t.currency_id
      LEFT JOIN warehouse_transfer_receipt_items ri ON ri.allocation_id=a.id
      LEFT JOIN warehouse_transfer_receipts receipt ON receipt.id=ri.receipt_id
      LEFT JOIN warehouse_transfer_recall_items rci ON rci.allocation_id=a.id
      LEFT JOIN warehouse_transfer_recalls recall ON recall.id=rci.recall_id
      WHERE ${where.join(' AND ')}
      GROUP BY a.id
      ORDER BY d.dispatched_at DESC,t.id,a.sequence
      LIMIT ?
    ''', variables: variables).get();

    final rows = <WarehouseTransferReportRow>[];
    for (final row in raw) {
      final allocationId = row.read<String>('allocation_id');
      final ownerType = row.read<String>('owner_type');
      final sourceBatchId = row.readNullable<int>('source_batch_id');
      final directSupplier = row.readNullable<int>('supplier_id');
      final sources = await _sources(
        allocationId: allocationId,
        warehouseId: row.read<String>('source_warehouse_id'),
        ownerType: ownerType,
        quantity: row.read<int>('quantity'),
        sourceBatchId: sourceBatchId,
        directSupplierId: directSupplier,
      );
      if (supplierId != null &&
          !sources.any((source) => source.supplierId == supplierId)) {
        continue;
      }
      if (term.isNotEmpty) {
        final haystack = [
          row.read<String>('product_name'),
          row.read<String>('variant_label'),
          row.read<String>('code'),
          row.read<String>('source_name'),
          row.read<String>('source_code'),
          row.read<String>('destination_name'),
          row.read<String>('destination_code'),
          ...sources.expand(
            (source) => [source.supplierName, source.purchaseNumber],
          ),
        ].join(' ').toLowerCase();
        if (!haystack.contains(term)) continue;
      }
      rows.add(
        WarehouseTransferReportRow(
          transferId: row.read<String>('transfer_id'),
          status: row.read<String>('status'),
          recalled: row.read<int>('recalled') == 1,
          dispatchedAt: DateTime.parse(
            row.read<String>('dispatched_at'),
          ).toUtc(),
          sourceWarehouseId: row.read<String>('source_warehouse_id'),
          sourceWarehouse:
              '${row.read<String>('source_name')} · ${row.read<String>('source_code')}',
          destinationWarehouseId: row.read<String>('destination_warehouse_id'),
          destinationWarehouse:
              '${row.read<String>('destination_name')} · ${row.read<String>('destination_code')}',
          productId: row.read<int>('product_id'),
          variantId: row.read<int>('variant_id'),
          productName: row.read<String>('product_name'),
          variantLabel: row.read<String>('variant_label'),
          code: row.read<String>('code'),
          ownerType: ownerType,
          quantityScale: row.read<int>('quantity_scale'),
          measurementType: row.read<String>('measurement_type'),
          dispatchedQuantity: row.read<int>('quantity'),
          acceptedQuantity: row.read<int>('accepted_quantity'),
          damagedQuantity: row.read<int>('damaged_quantity'),
          lostQuantity: row.read<int>('lost_quantity'),
          recalledQuantity: row.read<int>('recalled_quantity'),
          dispatchedValueCents: row.read<int>('value_cents'),
          acceptedValueCents: row.read<int>('accepted_value_cents'),
          varianceValueCents: row.read<int>('variance_value_cents'),
          recalledValueCents: row.read<int>('recalled_value_cents'),
          currencyCode: row.read<String>('currency_code'),
          sources: List.unmodifiable(sources),
        ),
      );
    }
    return WarehouseTransferReportData(
      warehouseId: warehouseId,
      from: start,
      toExclusive: end,
      rows: List.unmodifiable(rows),
    );
  });

  Future<List<WarehouseTransferSourceSlice>> _sources({
    required String allocationId,
    required String warehouseId,
    required String ownerType,
    required int quantity,
    required int? sourceBatchId,
    required int? directSupplierId,
  }) async {
    if (ownerType == 'consignment' && directSupplierId != null) {
      final supplier = await (db.select(
        db.suppliers,
      )..where((row) => row.id.equals(directSupplierId))).getSingle();
      return [
        WarehouseTransferSourceSlice(
          quantity: quantity,
          quality: 'consignment',
          supplierId: supplier.id,
          supplierName: supplier.name,
        ),
      ];
    }
    if (sourceBatchId != null) {
      final batch = await db
          .customSelect(
            '''
        SELECT COALESCE(pb.supplier_id,pu.supplier_id) AS supplier_id,
          COALESCE(s.name,'') AS supplier_name,COALESCE(pu.purchase_number,'') AS purchase_number
        FROM product_batches pb
        LEFT JOIN purchase_items pi ON pi.id=pb.purchase_item_id
        LEFT JOIN purchases pu ON pu.id=pi.purchase_id AND pu.status='posted'
        LEFT JOIN suppliers s ON s.id=COALESCE(pb.supplier_id,pu.supplier_id)
        WHERE pb.id=?
      ''',
            variables: [Variable.withInt(sourceBatchId)],
          )
          .getSingle();
      final supplier = batch.readNullable<int>('supplier_id');
      return [
        WarehouseTransferSourceSlice(
          quantity: quantity,
          quality: supplier == null ? 'unknown' : 'batch',
          supplierId: supplier,
          supplierName: batch.read<String>('supplier_name'),
          purchaseNumber: batch.read<String>('purchase_number'),
        ),
      ];
    }
    final origin = await db
        .customSelect(
          '''
      SELECT CAST(json_extract(j.value,'\$.q') AS INTEGER) AS quantity,
        COALESCE(pu.supplier_id,spi.supplier_id) AS supplier_id,
        COALESCE(ps.name,isup.name,'') AS supplier_name,
        COALESCE(pu.purchase_number,'') AS purchase_number,
        CASE WHEN pu.id IS NOT NULL THEN 'allocated'
          WHEN spi.id IS NOT NULL THEN 'identity'
          WHEN json_extract(j.value,'\$.k')='customer_return' THEN 'customer_return'
          ELSE 'unknown' END AS quality
      FROM inventory_origin_events e JOIN json_each(e.allocations) j
      LEFT JOIN purchase_items pi ON pi.id=json_extract(j.value,'\$.p')
        AND pi.product_id=e.product_id
      LEFT JOIN purchases pu ON pu.id=pi.purchase_id AND pu.status='posted'
      LEFT JOIN suppliers ps ON ps.id=pu.supplier_id
      LEFT JOIN supplier_product_identities spi ON spi.id=json_extract(j.value,'\$.i')
        AND spi.product_id=e.product_id AND spi.canonical_variant_id=e.variant_id
      LEFT JOIN suppliers isup ON isup.id=spi.supplier_id
      WHERE e.warehouse_id=? AND e.event_key=? AND e.delta<0
      ORDER BY CAST(j.key AS INTEGER)
    ''',
          variables: [
            Variable.withString(warehouseId),
            Variable.withString('transfer_out:$allocationId'),
          ],
        )
        .get();
    if (origin.isEmpty) {
      return [
        WarehouseTransferSourceSlice(quantity: quantity, quality: 'unknown'),
      ];
    }
    final combined = <String, WarehouseTransferSourceSlice>{};
    for (final row in origin) {
      final supplier = row.readNullable<int>('supplier_id');
      final quality = row.read<String>('quality');
      final purchaseNumber = row.read<String>('purchase_number');
      final key = '$supplier|$quality|$purchaseNumber';
      final previous = combined[key];
      combined[key] = WarehouseTransferSourceSlice(
        quantity: (previous?.quantity ?? 0) + row.read<int>('quantity'),
        quality: quality,
        supplierId: supplier,
        supplierName: row.read<String>('supplier_name'),
        purchaseNumber: purchaseNumber,
      );
    }
    final total = combined.values.fold<int>(
      0,
      (sum, row) => sum + row.quantity,
    );
    if (total != quantity) {
      throw StateError('Transfer origin report quantity is incomplete');
    }
    return combined.values.toList(growable: false);
  }
}
