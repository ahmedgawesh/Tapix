import 'package:drift/drift.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/business/document_posting_scope.dart';
import '../../../../core/services/business/warehouse_document_scope.dart';
import '../../../../core/services/business/warehouse_read_scope.dart';
import '../widgets/report_date_range.dart';

class SupplierSalesFilterChanged extends RealtimeEvent {
  const SupplierSalesFilterChanged({
    required this.range,
    this.supplierId,
    this.categoryId,
    this.productId,
  });
  final ReportDateRange range;

  /// -1 is unidentified; -2 is a customer return without purchase provenance.
  final int? supplierId, categoryId, productId;
}

class SupplierSalesRow {
  SupplierSalesRow({
    required this.productId,
    required this.productName,
    required this.variantId,
    required this.variantName,
    required this.categoryId,
    required this.categoryName,
    required this.supplierId,
    required this.supplierName,
    required this.productSku,
    required this.variantSku,
    required this.quantityScale,
    required this.measurementType,
    required this.currencyCode,
    this.sourceQuality = 'verified',
    List<SupplierPurchaseInvoice>? purchaseInvoices,
    Set<String>? consignmentReceipts,
  }) : purchaseInvoices = purchaseInvoices ?? [],
       consignmentReceipts = consignmentReceipts ?? <String>{};
  final String sourceQuality;
  final int productId, variantId, categoryId, supplierId;
  final String productName,
      variantName,
      categoryName,
      supplierName,
      productSku,
      variantSku,
      currencyCode;
  final int quantityScale;
  final String measurementType;
  final List<SupplierPurchaseInvoice> purchaseInvoices;
  final Set<String> consignmentReceipts;
  int get purchaseItemId =>
      purchaseInvoices.isEmpty ? -1 : purchaseInvoices.first.purchaseItemId;
  String get purchaseNumber =>
      purchaseInvoices.map((invoice) => invoice.purchaseNumber).join(', ');
  int get purchasedQuantity =>
      purchaseInvoices.fold(0, (total, invoice) => total + invoice.quantity);
  int soldQuantity = 0, returnedQuantity = 0, salesCents = 0, returnsCents = 0;
  int taxCents = 0, discountCents = 0;
  int get netCents => salesCents - returnsCents;
}

class SupplierPurchaseInvoice {
  SupplierPurchaseInvoice({
    required this.purchaseItemId,
    required this.purchaseId,
    required this.purchaseNumber,
    required this.quantity,
  });

  final int purchaseItemId;
  final int purchaseId;
  final String purchaseNumber;
  int quantity;
}

class SupplierSalesReportData {
  const SupplierSalesReportData({
    required this.rows,
    required this.range,
    required this.suppliers,
    required this.categories,
    required this.products,
    this.supplierId,
    this.categoryId,
    this.productId,
  });
  final List<SupplierSalesRow> rows;

  final ReportDateRange range;
  final Map<int, String> suppliers, categories, products;
  final int? supplierId, categoryId, productId;
  Map<String, int> get netByCurrency {
    final totals = <String, int>{};
    for (final row in rows) {
      totals.update(
        row.currencyCode,
        (v) => v + row.netCents,
        ifAbsent: () => row.netCents,
      );
    }
    return totals;
  }
}

/// Distinguishes saved batch links from new quantity-only receipt allocations.
/// Neither a preferred vendor nor reconstructed lifetime purchases prove origin.
class SupplierSalesReportBloc
    extends RealtimeBloc<SupplierSalesReportData, SupplierSalesFilterChanged> {
  SupplierSalesReportBloc(
    this.db, {
    this.warehouseScope,
    String defaultDateRange = 'month',
  }) : _range = ReportDateRange.fromSettingsDefault(defaultDateRange),
       super(const RealtimeLoading());
  final AppDatabase db;
  final WarehouseReadScope? warehouseScope;
  ReportDateRange _range;
  int? _supplier, _category, _product;
  @override
  void registerEventHandlers() => on<SupplierSalesFilterChanged>((event, emit) {
    _range = event.range;
    _supplier = event.supplierId;
    _category = event.categoryId;
    _product = event.productId;
    refresh();
  });
  @override
  Stream<SupplierSalesReportData> get dataStream => db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          ...WarehouseDocumentScope.dependencies(db),
          db.businessWarehouseStocks,
          db.sales,
          db.saleItems,
          db.saleReturns,
          db.saleReturnItems,
          db.saleReturnAdjustments,
          db.saleReturnAdjustmentItems,
          db.products,
          db.productVariants,
          db.productColors,
          db.sizes,
          db.productCategories,
          db.purchases,
          db.purchaseItems,
          db.productBatches,
          db.batchConsumptions,
          db.consignmentReceipts,
          db.consignmentReceiptItems,
          db.consignmentInventoryLayers,
          db.consignmentSaleAllocations,
          db.consignmentObligationEvents,
          db.consignmentAdjustmentReturnEvents,
          db.supplierProductIdentities,
          db.suppliers,
          db.currencies,
        },
      )
      .watch()
      .asyncMap((_) => load());

  Future<SupplierSalesReportData>
  load() => WarehouseReadScope.snapshot(db, warehouseScope, () async {
    final range = _range,
        supplier = _supplier,
        category = _category,
        product = _product;
    final scope = warehouseScope ?? await WarehouseReadScope.resolve(db);
    String docs(InventoryPostingDocument kind) => scope.documents(kind);
    final activity = await db
        .customSelect(
          '''
      SELECT a.*, p.name AS product_name, COALESCE(p.category_id,-1) AS category_id,
        COALESCE(cat.name,'') AS category_name, COALESCE(p.sku,'') AS product_sku,
        COALESCE(v.sku,'') AS variant_sku,
        TRIM(COALESCE(color.name,'') || ' ' || COALESCE(size.name,'') || ' ' || COALESCE(v.sku,'')) AS variant_name, c.code AS currency_code
      FROM (
        SELECT 'sale' AS kind, s.id AS doc_id, si.id AS line_id, si.product_id, COALESCE(${WarehouseDocumentScope.operationalVariant('si')},0) AS variant_id,
          si.quantity, si.quantity_scale, si.measurement_type, si.total_cents AS amount, si.tax_cents AS tax,
          si.discount_cents AS discount, s.total_cents AS header_total, s.tax_cents AS header_tax,
          s.discount_cents AS header_discount, s.currency_id
        FROM sale_items si JOIN ${docs(InventoryPostingDocument.sale)} s ON s.id=si.sale_id
        WHERE s.status='completed' AND julianday(s.sale_date) BETWEEN julianday(?) AND julianday(?)
        UNION ALL
        SELECT 'return', r.id, i.id, si.product_id, COALESCE(${WarehouseDocumentScope.operationalVariant('si')},0), i.quantity, i.quantity_scale,
          i.measurement_type, i.refund_cents, i.tax_cents, i.discount_cents, r.total_cents, r.tax_cents, r.discount_cents, r.currency_id
        FROM sale_return_items i JOIN ${docs(InventoryPostingDocument.saleReturn)} r ON r.id=i.return_id
          JOIN sale_items si ON si.id=i.sale_item_id
        WHERE r.status='posted' AND julianday(r.return_date) BETWEEN julianday(?) AND julianday(?)
        UNION ALL
        SELECT 'adjustment', r.id, srai.id, srai.product_id, COALESCE(${WarehouseDocumentScope.operationalVariant('srai')},0), srai.quantity, srai.quantity_scale,
          srai.measurement_type, srai.total_cents, srai.tax_cents, srai.discount_cents, r.total_cents, r.tax_cents, r.discount_cents, r.currency_id
        FROM sale_return_adjustment_items srai JOIN ${docs(InventoryPostingDocument.saleAdjustment)} r ON r.id=srai.return_id
        WHERE r.status='posted' AND julianday(r.return_date) BETWEEN julianday(?) AND julianday(?)
      ) a JOIN products p ON p.id=a.product_id LEFT JOIN product_variants v ON v.id=a.variant_id
        LEFT JOIN product_categories cat ON cat.id=p.category_id JOIN currencies c ON c.id=a.currency_id
        LEFT JOIN product_colors color ON color.id=v.color_id LEFT JOIN sizes size ON size.id=v.size_id
      ORDER BY a.kind,a.doc_id,a.line_id
    ''',
          variables: [
            for (var i = 0; i < 3; i++) ...[
              Variable.withString(range.startDate.toUtc().toIso8601String()),
              Variable.withString(range.endDate.toUtc().toIso8601String()),
            ],
          ],
        )
        .get();
    // Reconcile line amounts to their saved document header before filtering.
    // This includes invoice discounts on old rows whose line amounts predate allocation.
    final documents = <String, List<QueryRow>>{};
    for (final line in activity) {
      documents
          .putIfAbsent(
            '${line.read<String>('kind')}:${line.read<int>('doc_id')}',
            () => [],
          )
          .add(line);
    }
    // Load sources in bounded batches, not one query per invoice line.
    final sourceRows = <String, List<QueryRow>>{};
    for (final kind in ['sale', 'return', 'adjustment']) {
      final ids = activity
          .where((r) => r.read<String>('kind') == kind)
          .map((r) => r.read<int>('line_id'))
          .toList();
      final column = kind == 'sale'
          ? 'sale_item_id'
          : kind == 'return'
          ? 'sale_return_item_id'
          : 'sale_return_adjustment_item_id';
      final type = kind == 'sale'
          ? 'sale'
          : kind == 'return'
          ? 'sale_return_reverse'
          : 'sale_adj_return_reverse';
      for (var offset = 0; offset < ids.length; offset += 400) {
        final chunk = ids.skip(offset).take(400).toList();
        final found = await db
            .customSelect(
              '''SELECT bc.$column AS source_line_id,
          pi.id AS purchase_item_id, pu.purchase_number, pu.supplier_id, sp.name AS supplier_name,
          pi.quantity AS purchased_quantity, pi.quantity_scale AS purchase_scale, SUM(bc.quantity) AS quantity,
          pi.product_id AS source_product_id, COALESCE(${WarehouseDocumentScope.operationalVariant('pi')},0) AS source_variant_id,
          pu.currency_id AS source_currency_id
          FROM batch_consumptions bc JOIN ${scope.batches} pb ON pb.id=bc.batch_id
          JOIN purchase_items pi ON pi.id=pb.purchase_item_id
          JOIN ${docs(InventoryPostingDocument.purchase)} pu ON pu.id=pi.purchase_id
          JOIN suppliers sp ON sp.id=pu.supplier_id
          WHERE bc.$column IN (${List.filled(chunk.length, '?').join(',')})
            AND bc.consumption_type=? AND bc.direction=? AND pu.status='posted'
            AND pb.supplier_id=pu.supplier_id AND pb.product_id=pi.product_id
            AND COALESCE(${WarehouseDocumentScope.operationalVariant('pb')},0)=COALESCE(${WarehouseDocumentScope.operationalVariant('pi')},0)
          GROUP BY bc.$column, pi.id ORDER BY bc.$column, pi.id''',
              variables: [
                ...chunk.map(Variable.withInt),
                Variable.withString(type),
                Variable.withString(kind == 'sale' ? 'out' : 'in'),
              ],
            )
            .get();
        for (final row in found) {
          sourceRows
              .putIfAbsent('$kind:${row.read<int>('source_line_id')}', () => [])
              .add(row);
        }
      }
    }
    // Exact consignment provenance is independent from purchase batches.
    // Sales and both return paths retain the supplier-owned receipt layer, so
    // the supplier report must consume that evidence before WAC fallbacks.
    for (final kind in ['sale', 'return', 'adjustment']) {
      final ids = activity
          .where((row) => row.read<String>('kind') == kind)
          .map((row) => row.read<int>('line_id'))
          .toList();
      for (var offset = 0; offset < ids.length; offset += 400) {
        final chunk = ids.skip(offset).take(400).toList();
        if (chunk.isEmpty) continue;
        late final String sql;
        late final List<Variable> variables;
        if (kind == 'sale') {
          sql =
              '''SELECT a.sale_item_id AS source_line_id,
            -1 AS purchase_item_id,r.receipt_number AS purchase_number,
            l.supplier_id,sp.name AS supplier_name,ri.quantity AS purchased_quantity,
            ri.quantity_scale AS purchase_scale,a.quantity,
            l.product_id AS source_product_id,l.variant_id AS source_variant_id,
            r.currency_id AS source_currency_id,'consignment' AS source_quality
            FROM consignment_sale_allocations a
            JOIN consignment_inventory_layers l ON l.id=a.layer_id
            JOIN consignment_receipt_items ri ON ri.id=l.receipt_item_id
            JOIN consignment_receipts r ON r.id=ri.receipt_id AND r.status='posted'
            JOIN suppliers sp ON sp.id=l.supplier_id
            WHERE a.sale_item_id IN (${List.filled(chunk.length, '?').join(',')})
              AND a.warehouse_id=?
            ORDER BY a.sale_item_id,a.sequence''';
          variables = [
            ...chunk.map(Variable.withInt),
            Variable.withString(scope.warehouseId),
          ];
        } else if (kind == 'return') {
          sql =
              '''SELECT e.source_item_id AS source_line_id,
            -1 AS purchase_item_id,r.receipt_number AS purchase_number,
            l.supplier_id,sp.name AS supplier_name,ri.quantity AS purchased_quantity,
            ri.quantity_scale AS purchase_scale,-e.signed_quantity AS quantity,
            l.product_id AS source_product_id,l.variant_id AS source_variant_id,
            r.currency_id AS source_currency_id,'consignment' AS source_quality
            FROM consignment_obligation_events e
            JOIN consignment_sale_allocations a ON a.id=e.allocation_id
            JOIN consignment_inventory_layers l ON l.id=a.layer_id
            JOIN consignment_receipt_items ri ON ri.id=l.receipt_item_id
            JOIN consignment_receipts r ON r.id=ri.receipt_id AND r.status='posted'
            JOIN suppliers sp ON sp.id=l.supplier_id
            WHERE e.source_table='sale_returns'
              AND e.kind='linked_return_reversal'
              AND e.source_item_id IN (${List.filled(chunk.length, '?').join(',')})
              AND a.warehouse_id=?
            ORDER BY e.source_item_id,e.id''';
          variables = [
            ...chunk.map(Variable.withInt),
            Variable.withString(scope.warehouseId),
          ];
        } else {
          sql =
              '''SELECT e.return_item_id AS source_line_id,
            -1 AS purchase_item_id,r.receipt_number AS purchase_number,
            l.supplier_id,sp.name AS supplier_name,ri.quantity AS purchased_quantity,
            ri.quantity_scale AS purchase_scale,-e.signed_quantity AS quantity,
            l.product_id AS source_product_id,l.variant_id AS source_variant_id,
            r.currency_id AS source_currency_id,'consignment' AS source_quality
            FROM consignment_adjustment_return_events e
            JOIN consignment_inventory_layers l ON l.id=e.layer_id
            JOIN consignment_receipt_items ri ON ri.id=l.receipt_item_id
            JOIN consignment_receipts r ON r.id=ri.receipt_id AND r.status='posted'
            JOIN suppliers sp ON sp.id=l.supplier_id
            WHERE e.kind='adjustment_return_reversal'
              AND e.return_item_id IN (${List.filled(chunk.length, '?').join(',')})
              AND l.warehouse_id=?
            ORDER BY e.return_item_id,e.id''';
          variables = [
            ...chunk.map(Variable.withInt),
            Variable.withString(scope.warehouseId),
          ];
        }
        final found = await db.customSelect(sql, variables: variables).get();
        for (final row in found) {
          sourceRows
              .putIfAbsent('$kind:${row.read<int>('source_line_id')}', () => [])
              .add(row);
        }
      }
    }

    // An operator-scanned supplier identity is stronger than an automatic
    // WAC/FIFO policy allocation for supplier reporting. It identifies the
    // supplier and variant without inventing a purchase invoice.
    for (final kind in ['sale', 'adjustment']) {
      final ids = activity
          .where((row) => row.read<String>('kind') == kind)
          .map((row) => row.read<int>('line_id'))
          .toList(growable: false);
      for (var offset = 0; offset < ids.length; offset += 400) {
        final chunk = ids.skip(offset).take(400).toList(growable: false);
        if (chunk.isEmpty) continue;
        final lineTable = kind == 'sale'
            ? 'sale_items'
            : 'sale_return_adjustment_items';
        final headerTable = kind == 'sale'
            ? 'sales'
            : 'sale_return_adjustments';
        final headerForeignKey = kind == 'sale' ? 'sale_id' : 'return_id';
        final found = await db.customSelect(
          '''SELECT li.id AS source_line_id,-1 AS purchase_item_id,
          '' AS purchase_number,i.supplier_id,sp.name AS supplier_name,
          0 AS purchased_quantity,li.quantity_scale AS purchase_scale,
          li.quantity,li.product_id AS source_product_id,
          i.canonical_variant_id AS source_variant_id,
          h.currency_id AS source_currency_id,'identity' AS source_quality
          FROM $lineTable li
          JOIN $headerTable h ON h.id=li.$headerForeignKey
          JOIN supplier_product_identities i ON i.id=li.supplier_identity_id
            AND i.product_id=li.product_id
          JOIN suppliers sp ON sp.id=i.supplier_id
          WHERE li.id IN (${List.filled(chunk.length, '?').join(',')})
          ORDER BY li.id''',
          variables: chunk.map(Variable.withInt).toList(growable: false),
        ).get();
        for (final row in found) {
          sourceRows['$kind:${row.read<int>('source_line_id')}'] = [row];
        }
      }
    }

    // Quantity provenance for NEW standard/WAC movements. These are explicit
    // policy allocations, never presented as verified physical lot picking.
    for (final kind in ['sale', 'return', 'adjustment']) {
      final ids = activity
          .where((r) => r.read<String>('kind') == kind)
          .map((r) => r.read<int>('line_id'))
          .toList();
      for (var offset = 0; offset < ids.length; offset += 400) {
        final chunk = ids.skip(offset).take(400).toList();
        final found = await db
            .customSelect(
              '''SELECT
          CAST(substr(e.event_key,instr(e.event_key,':')+1) AS INTEGER) AS source_line_id,
          COALESCE(pi.id,-1) AS purchase_item_id, COALESCE(pu.purchase_number,'') AS purchase_number,
          CASE WHEN pu.id IS NOT NULL THEN pu.supplier_id
            WHEN spi.id IS NOT NULL THEN spi.supplier_id
            WHEN json_extract(j.value,'\$.k')='customer_return' THEN -2 ELSE -1 END AS supplier_id,
          COALESCE(sp.name,isp.name,'') AS supplier_name,
          COALESCE(pi.quantity,0) AS purchased_quantity,
          CASE WHEN e.measurement_type='piece' THEN 1 ELSE 1000 END AS purchase_scale,
          json_extract(j.value,'\$.q') AS quantity,
          e.product_id AS source_product_id,e.variant_id AS source_variant_id,
          COALESCE(pu.currency_id,p.currency_id) AS source_currency_id,
          CASE WHEN pu.id IS NOT NULL THEN 'allocated'
            WHEN spi.id IS NOT NULL THEN 'identity'
            WHEN json_extract(j.value,'\$.k')='customer_return' THEN 'customer_return' ELSE 'unknown' END AS source_quality
          FROM inventory_origin_events e JOIN json_each(e.allocations) j
          JOIN products p ON p.id=e.product_id
          LEFT JOIN purchase_items pi ON pi.id=json_extract(j.value,'\$.p') AND pi.product_id=e.product_id
            AND COALESCE(${WarehouseDocumentScope.operationalVariant('pi')},0)=e.variant_id
            AND pi.measurement_type=e.measurement_type
          LEFT JOIN purchases pu ON pu.id=pi.purchase_id AND pu.status='posted'
          LEFT JOIN suppliers sp ON sp.id=pu.supplier_id
          LEFT JOIN supplier_product_identities spi
            ON spi.id=json_extract(j.value,'\$.i')
            AND spi.product_id=e.product_id
            AND spi.canonical_variant_id=e.variant_id
          LEFT JOIN suppliers isp ON isp.id=spi.supplier_id
          WHERE e.warehouse_id=? AND e.event_key IN (${List.filled(chunk.length, '?').join(',')})
            AND ((?='sale' AND e.delta<0) OR (?!='sale' AND e.delta>0))
          ORDER BY e.id,j.key''',
              variables: [
                Variable.withString(scope.warehouseId),
                ...chunk.map((id) => Variable.withString('$kind:$id')),
                Variable.withString(kind),
                Variable.withString(kind),
              ],
            )
            .get();
        final grouped = <String, List<QueryRow>>{};
        for (final row in found) {
          grouped
              .putIfAbsent('$kind:${row.read<int>('source_line_id')}', () => [])
              .add(row);
        }
        for (final entry in grouped.entries) {
          if (!sourceRows.containsKey(entry.key)) {
            sourceRows[entry.key] = entry.value;
          }
        }
        // Batch customer returns carry an explicit non-purchase source. Names
        // resembling SAR are deliberately not used as evidence.
        if (kind == 'sale' || kind == 'return') {
          final column = kind == 'sale'
              ? 'sale_item_id'
              : 'sale_return_item_id';
          final type = kind == 'sale' ? 'sale' : 'sale_return_reverse';
          final returns = await db
              .customSelect(
                '''SELECT bc.$column AS source_line_id,
            -1 AS purchase_item_id,'' AS purchase_number,-2 AS supplier_id,'' AS supplier_name,
            0 AS purchased_quantity, CASE WHEN p.measurement_type='piece' THEN 1 ELSE 1000 END AS purchase_scale,
            SUM(bc.quantity) AS quantity,pb.product_id AS source_product_id,
            COALESCE(${WarehouseDocumentScope.operationalVariant('pb')},0) AS source_variant_id,
            p.currency_id AS source_currency_id,'customer_return' AS source_quality
            FROM batch_consumptions bc JOIN ${scope.batches} pb ON pb.id=bc.batch_id
            JOIN products p ON p.id=pb.product_id
            WHERE bc.$column IN (${List.filled(chunk.length, '?').join(',')})
              AND bc.consumption_type=? AND bc.direction=? AND pb.source='sale_return' AND pb.purchase_item_id IS NULL
            GROUP BY bc.$column,pb.product_id,source_variant_id''',
                variables: [
                  ...chunk.map(Variable.withInt),
                  Variable.withString(type),
                  Variable.withString(kind == 'sale' ? 'out' : 'in'),
                ],
              )
              .get();
          for (final row in returns) {
            final key = '$kind:${row.read<int>('source_line_id')}';
            if (!grouped.containsKey(key)) {
              sourceRows.putIfAbsent(key, () => []).add(row);
            }
          }
        }
      }
    }
    // Load purchase summaries independently from sales consumption so one
    // product/supplier card can include every posted receipt, even when part
    // of that stock has not been sold yet.
    final purchaseRows = await db.customSelect(
      '''SELECT pi.id AS purchase_item_id, pu.id AS purchase_id,
          pu.purchase_number, pu.supplier_id, pi.product_id,
          COALESCE(${WarehouseDocumentScope.operationalVariant('pi')},0) AS variant_id,
          pi.quantity, pi.quantity_scale, pi.measurement_type,
          p.name AS product_name, COALESCE(p.sku,'') AS product_sku,
          COALESCE(p.category_id,-1) AS category_id,
          COALESCE(v.sku,'') AS variant_sku
          FROM purchase_items pi
          JOIN ${docs(InventoryPostingDocument.purchase)} pu ON pu.id=pi.purchase_id
          JOIN products p ON p.id=pi.product_id
          LEFT JOIN product_variants v
            ON v.id=COALESCE(${WarehouseDocumentScope.operationalVariant('pi')},0)
          WHERE pu.status='posted'
          ORDER BY pu.purchase_date, pu.id, pi.id''',
    ).get();
    String purchaseGroupKey({
      required int supplierId,
      required int productId,
      required int variantId,
      required int quantityScale,
      required String measurementType,
    }) => '$supplierId:$productId:$variantId:$quantityScale:$measurementType';
    final purchasesByGroup = <String, Map<int, SupplierPurchaseInvoice>>{};
    for (final purchase in purchaseRows) {
      final key = purchaseGroupKey(
        supplierId: purchase.read<int>('supplier_id'),
        productId: purchase.read<int>('product_id'),
        variantId: purchase.read<int>('variant_id'),
        quantityScale: purchase.read<int>('quantity_scale'),
        measurementType: purchase.read<String>('measurement_type'),
      );
      final byInvoice = purchasesByGroup.putIfAbsent(key, () => {});
      final purchaseId = purchase.read<int>('purchase_id');
      final quantity = purchase.read<int>('quantity');
      final existing = byInvoice[purchaseId];
      if (existing == null) {
        byInvoice[purchaseId] = SupplierPurchaseInvoice(
          purchaseItemId: purchase.read<int>('purchase_item_id'),
          purchaseId: purchaseId,
          purchaseNumber: purchase.read<String>('purchase_number'),
          quantity: quantity,
        );
      } else {
        existing.quantity += quantity;
      }
    }
    final rows = <String, SupplierSalesRow>{};
    for (final lines in documents.values) {
      List<int> amounts(String header, String field) {
        final weights = lines.map((l) => l.read<int>(field).abs()).toList();
        if (weights.every((w) => w == 0)) {
          for (var i = 0; i < weights.length; i++) {
            weights[i] = lines[i].read<int>('amount').abs();
          }
        }
        return allocateReportCents(lines.first.read<int>(header), weights);
      }

      final totals = amounts('header_total', 'amount'),
          taxes = amounts('header_tax', 'tax'),
          discounts = amounts('header_discount', 'discount');
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index], kind = line.read<String>('kind');
        final quantity = line.read<int>('quantity');
        if (quantity <= 0 || line.read<int>('quantity_scale') <= 0) {
          throw StateError('Invalid saved report quantity');
        }
        final sources =
            (sourceRows['$kind:${line.read<int>('line_id')}'] ?? <QueryRow>[])
                .where(
                  (r) =>
                      r.read<int>('source_product_id') ==
                          line.read<int>('product_id') &&
                      r.read<int>('source_variant_id') ==
                          line.read<int>('variant_id') &&
                      r.read<int>('source_currency_id') ==
                          line.read<int>('currency_id'),
                )
                .toList();
        final weights = sources.map((r) => r.read<int>('quantity')).toList();
        final linked = weights.fold<int>(0, (a, b) => a + b);
        if (linked > quantity || weights.any((q) => q <= 0)) {
          throw StateError('Inconsistent purchase source quantities');
        }
        final missing = quantity - linked;
        if (missing > 0) {
          weights.add(missing);
        }
        final lineTotals = allocateReportCents(totals[index], weights),
            lineTaxes = allocateReportCents(taxes[index], weights),
            lineDiscounts = allocateReportCents(discounts[index], weights);
        for (var part = 0; part < weights.length; part++) {
          final source = part < sources.length ? sources[part] : null;
          final supplierId =
              source?.read<int>('supplier_id') ??
              (kind == 'adjustment' ? -2 : -1);
          final quality =
              source?.readNullable<String>('source_quality') ??
              (source != null
                  ? 'verified'
                  : kind == 'adjustment'
                  ? 'customer_return'
                  : 'unknown');
          final key =
              '$supplierId:${line.read<int>('product_id')}:${line.read<int>('variant_id')}:${line.read<int>('quantity_scale')}:${line.read<String>('measurement_type')}:${line.read<int>('currency_id')}:$quality';
          final row = rows.putIfAbsent(
            key,
            () => SupplierSalesRow(
              productId: line.read<int>('product_id'),
              productName: line.read<String>('product_name'),
              productSku: line.read<String>('product_sku'),
              variantId: line.read<int>('variant_id'),
              variantName: line.read<String>('variant_name'),
              variantSku: line.read<String>('variant_sku'),
              categoryId: line.read<int>('category_id'),
              categoryName: line.read<String>('category_name'),
              sourceQuality: quality,
              supplierId: supplierId,
              supplierName: source?.read<String>('supplier_name') ?? '',
              quantityScale: line.read<int>('quantity_scale'),
              measurementType: line.read<String>('measurement_type'),
              currencyCode: line.read<String>('currency_code'),
            ),
          );
          if (source != null &&
              source.read<int>('purchase_scale') != row.quantityScale) {
            throw StateError('Source quantity scale changed');
          }
          if (quality == 'consignment' && source != null) {
            final receiptNumber = source.read<String>('purchase_number').trim();
            if (receiptNumber.isNotEmpty) {
              row.consignmentReceipts.add(receiptNumber);
            }
          }
          final sign = kind == 'sale' ? 1 : -1;
          if (sign == 1) {
            row.soldQuantity += weights[part];
            row.salesCents += lineTotals[part];
          } else {
            row.returnedQuantity += weights[part];
            row.returnsCents += lineTotals[part];
          }
          row.taxCents += sign * lineTaxes[part];
          row.discountCents += sign * lineDiscounts[part];
        }
      }
    }
    final all = rows.values.toList();
    for (final row in all.where(
      (candidate) =>
          candidate.supplierId >= 0 && candidate.sourceQuality != 'consignment',
    )) {
      final key = purchaseGroupKey(
        supplierId: row.supplierId,
        productId: row.productId,
        variantId: row.variantId,
        quantityScale: row.quantityScale,
        measurementType: row.measurementType,
      );
      row.purchaseInvoices.addAll(
        purchasesByGroup[key]?.values ?? const <SupplierPurchaseInvoice>[],
      );
    }
    final supplierRecords = await (db.select(
      db.suppliers,
    )..orderBy([(s) => OrderingTerm.asc(s.name)])).get();
    final suppliers = <int, String>{
      for (final s in supplierRecords) s.id: s.name,
      -1: '',
      -2: '',
    };
    final categories = <int, String>{
      for (final r in all) r.categoryId: r.categoryName,
    };
    final productTerms = <int, Set<String>>{};
    if (supplier != null && supplier >= 0) {
      for (final row in all.where(
        (candidate) =>
            candidate.supplierId == supplier &&
            (category == null || candidate.categoryId == category),
      )) {
        productTerms.putIfAbsent(row.productId, () => <String>{}).addAll({
          row.productName,
          if (row.productSku.trim().isNotEmpty) row.productSku.trim(),
          if (row.variantSku.trim().isNotEmpty) row.variantSku.trim(),
        });
      }
      for (final purchase in purchaseRows.where(
        (row) =>
            row.read<int>('supplier_id') == supplier &&
            (category == null || row.read<int>('category_id') == category),
      )) {
        final productId = purchase.read<int>('product_id');
        final productSku = purchase.read<String>('product_sku').trim();
        final variantSku = purchase.read<String>('variant_sku').trim();
        productTerms.putIfAbsent(productId, () => <String>{}).addAll({
          purchase.read<String>('product_name'),
          if (productSku.isNotEmpty) productSku,
          if (variantSku.isNotEmpty) variantSku,
        });
      }
    } else {
      for (final row in all.where(
        (candidate) =>
            (supplier == null || candidate.supplierId == supplier) &&
            (category == null || candidate.categoryId == category),
      )) {
        productTerms.putIfAbsent(row.productId, () => <String>{}).addAll({
          row.productName,
          if (row.productSku.trim().isNotEmpty) row.productSku.trim(),
          if (row.variantSku.trim().isNotEmpty) row.variantSku.trim(),
        });
      }
    }
    final products = <int, String>{
      for (final entry in productTerms.entries)
        entry.key: entry.value.join(' • '),
    };
    final filtered =
        all
            .where(
              (r) =>
                  (supplier == null || r.supplierId == supplier) &&
                  (category == null || r.categoryId == category) &&
                  (product == null || r.productId == product),
            )
            .toList()
          ..sort((a, b) {
            final byName = a.supplierName.compareTo(b.supplierName);
            if (byName != 0) return byName;
            final byProduct = a.productName.compareTo(b.productName);
            return byProduct != 0
                ? byProduct
                : a.variantName.compareTo(b.variantName);
          });
    return SupplierSalesReportData(
      rows: filtered,
      range: range,
      suppliers: suppliers,
      categories: categories,
      products: products,
      supplierId: supplier,
      categoryId: category,
      productId: product,
    );
  });
}

/// Integer largest-remainder allocation; no floating point loss for large money.
List<int> allocateReportCents(int amount, List<int> weights) {
  if (weights.isEmpty) {
    if (amount != 0) {
      throw StateError('Amount without lines');
    }
    return [];
  }
  final sum = weights.fold<BigInt>(BigInt.zero, (a, b) => a + BigInt.from(b));
  if (sum == BigInt.zero) {
    return [amount, ...List.filled(weights.length - 1, 0)];
  }
  final magnitude = BigInt.from(amount).abs();
  final floors = [
    for (final w in weights) (magnitude * BigInt.from(w) ~/ sum).toInt(),
  ];
  final order = List.generate(weights.length, (i) => i)
    ..sort((a, b) {
      final cmp = (magnitude * BigInt.from(weights[b]) % sum).compareTo(
        magnitude * BigInt.from(weights[a]) % sum,
      );
      return cmp != 0 ? cmp : a.compareTo(b);
    });
  final rest = amount.abs() - floors.fold<int>(0, (a, b) => a + b);
  for (var i = 0; i < rest; i++) {
    floors[order[i]]++;
  }
  return amount < 0 ? floors.map((v) => -v).toList() : floors;
}
