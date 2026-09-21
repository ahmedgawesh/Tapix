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

  /// -1 denotes a source which cannot be proven from the saved batch ledger.
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
    required this.purchaseItemId,
    required this.purchaseNumber,
    required this.purchasedQuantity,
    required this.quantityScale,
    required this.measurementType,
    required this.currencyCode,
  });
  final int productId, variantId, categoryId, supplierId, purchaseItemId;
  final String productName,
      variantName,
      categoryName,
      supplierName,
      purchaseNumber,
      currencyCode;
  final int purchasedQuantity, quantityScale;
  final String measurementType;
  int soldQuantity = 0, returnedQuantity = 0, salesCents = 0, returnsCents = 0;
  int taxCents = 0, discountCents = 0;
  int get netCents => salesCents - returnsCents;
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

/// Uses saved consumption → batch → purchase-item links only. Neither the
/// product's current supplier nor proportional lifetime purchases prove origin.
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
        COALESCE(cat.name,'') AS category_name, TRIM(COALESCE(color.name,'') || ' ' || COALESCE(size.name,'') || ' ' || COALESCE(v.sku,'')) AS variant_name, c.code AS currency_code
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
          final purchaseId = source?.read<int>('purchase_item_id') ?? -1;
          final key =
              '$purchaseId:${line.read<int>('product_id')}:${line.read<int>('variant_id')}:${line.read<int>('quantity_scale')}:${line.read<String>('measurement_type')}:${line.read<int>('currency_id')}';
          final row = rows.putIfAbsent(
            key,
            () => SupplierSalesRow(
              productId: line.read<int>('product_id'),
              productName: line.read<String>('product_name'),
              variantId: line.read<int>('variant_id'),
              variantName: line.read<String>('variant_name'),
              categoryId: line.read<int>('category_id'),
              categoryName: line.read<String>('category_name'),
              supplierId: source?.read<int>('supplier_id') ?? -1,
              supplierName: source?.read<String>('supplier_name') ?? '',
              purchaseItemId: purchaseId,
              purchaseNumber: source?.read<String>('purchase_number') ?? '',
              purchasedQuantity: source == null
                  ? 0
                  : source.read<int>('purchased_quantity'),
              quantityScale: line.read<int>('quantity_scale'),
              measurementType: line.read<String>('measurement_type'),
              currencyCode: line.read<String>('currency_code'),
            ),
          );
          if (source != null &&
              source.read<int>('purchase_scale') != row.quantityScale) {
            throw StateError('Source quantity scale changed');
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
    final supplierRecords = await (db.select(
      db.suppliers,
    )..orderBy([(s) => OrderingTerm.asc(s.name)])).get();
    final suppliers = <int, String>{
      for (final s in supplierRecords) s.id: s.name,
      -1: '',
    };
    final categories = <int, String>{
      for (final r in all) r.categoryId: r.categoryName,
    };
    final products = <int, String>{
      for (final r in all.where(
        (r) => category == null || r.categoryId == category,
      ))
        r.productId: r.productName,
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
            return byName != 0
                ? byName
                : a.productName.compareTo(b.productName);
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
