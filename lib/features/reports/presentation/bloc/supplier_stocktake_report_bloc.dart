import '../../../../core/services/business/warehouse_read_scope.dart';
import '../../../../core/services/business/document_posting_scope.dart';
import '../../../../core/services/business/warehouse_document_scope.dart';
import '../../../../core/services/business/warehouse_batch_scope.dart';
import '../../../../core/services/business/warehouse_stock_scope.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/measurement/measurement.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SupplierStocktakeReportEvent extends RealtimeEvent {
  const SupplierStocktakeReportEvent();
}

class SupplierStocktakeReportDateRangeChanged
    extends SupplierStocktakeReportEvent {
  final ReportDateRange dateRange;
  const SupplierStocktakeReportDateRangeChanged(this.dateRange);
}

class SupplierStocktakeReportSupplierChanged
    extends SupplierStocktakeReportEvent {
  final int? supplierId;
  const SupplierStocktakeReportSupplierChanged(this.supplierId);
}

class SupplierStocktakeReportSortChanged extends SupplierStocktakeReportEvent {
  final SupplierStocktakeSortType sort;
  const SupplierStocktakeReportSortChanged(this.sort);
}

class SupplierStocktakeSearchChanged extends SupplierStocktakeReportEvent {
  final String query;
  const SupplierStocktakeSearchChanged(this.query);
}

class SupplierStocktakeCategoryFilterChanged
    extends SupplierStocktakeReportEvent {
  final int? categoryId;
  final String? categoryName;
  const SupplierStocktakeCategoryFilterChanged(
    this.categoryId,
    this.categoryName,
  );
}

// ==================== ENUMS ====================

enum SupplierStocktakeSortType {
  valueDesc,
  valueAsc,
  nameAsc,
  nameDesc,
  stockDesc,
  stockAsc,
  soldDesc,
  purchasedDesc,
  profitDesc,
}

typedef _VariantKey = ({int productId, int variantId});

class _VariantMeta {
  final int productId;
  final int variantId;
  final String productName;
  final String? sku;
  final String? colorName;
  final String? sizeName;
  final String? categoryName;
  final int currentStock;
  final int currentCostCents;
  final int currentPriceCents;
  final int quantityScale;
  final String measurementType;
  final bool usesBatchCosting;

  const _VariantMeta({
    required this.productId,
    required this.variantId,
    required this.productName,
    required this.sku,
    required this.colorName,
    required this.sizeName,
    required this.categoryName,
    required this.currentStock,
    required this.currentCostCents,
    required this.currentPriceCents,
    required this.quantityScale,
    required this.measurementType,
    required this.usesBatchCosting,
  });
}

class _SupplierVariantMetrics {
  int purchasedQuantity = 0;
  int soldQuantity = 0;
  int saleReturnedQuantity = 0;
  int purchaseReturnedQuantity = 0;
  int remainingQuantity = 0;
  int remainingValueCents = 0;
  int netRevenueCents = 0;
  int netCogsCents = 0;
}

class _FifoActivityLine {
  final String kind;
  final _VariantKey key;
  final int netRevenueCents;
  final Map<int, int> quantityBySource = <int, int>{};
  final Map<int, int> costBySource = <int, int>{};

  _FifoActivityLine({
    required this.kind,
    required this.key,
    required this.netRevenueCents,
  });
}

const int _unassignedSupplierSource = -1;

/// Allocates an integer total without ever creating units/cents through
/// rounding. The largest-remainder method guarantees that the sum of all
/// source allocations equals [total]. A source id of -1 represents opening
/// stock or other inventory that cannot honestly be attributed to a supplier.
int _allocateLargestRemainder(
  int total,
  Map<int, int> sourceWeights,
  int supplierId,
) {
  if (total == 0) return 0;
  final weights = Map<int, int>.fromEntries(
    sourceWeights.entries.where((entry) => entry.value > 0),
  );
  if (weights.isEmpty || !weights.containsKey(supplierId)) return 0;

  final sign = total < 0 ? -1 : 1;
  final magnitude = total.abs();
  final denominator = weights.values.fold<int>(0, (a, b) => a + b);
  final allocations = <int, int>{};
  final remainders = <({int sourceId, int remainder})>[];
  var allocated = 0;

  for (final entry in weights.entries) {
    final numerator = magnitude * entry.value;
    final floorShare = numerator ~/ denominator;
    allocations[entry.key] = floorShare;
    allocated += floorShare;
    remainders.add((sourceId: entry.key, remainder: numerator % denominator));
  }

  remainders.sort((a, b) {
    final byRemainder = b.remainder.compareTo(a.remainder);
    return byRemainder != 0 ? byRemainder : a.sourceId.compareTo(b.sourceId);
  });
  var unitsLeft = magnitude - allocated;
  for (var i = 0; i < unitsLeft; i++) {
    final source = remainders[i % remainders.length].sourceId;
    allocations[source] = (allocations[source] ?? 0) + 1;
  }
  return sign * (allocations[supplierId] ?? 0);
}

// ==================== DATA MODELS ====================

class SupplierStocktakeProductItem {
  final int productId;
  final String productName;
  final String? sku;
  final int variantId;
  final String? colorName;
  final String? sizeName;
  final String? categoryName;
  final int purchasedQuantity;
  final int soldQuantity;
  final int saleReturnedQuantity;
  final int purchaseReturnedQuantity;
  final int remainingQuantity;
  final String measurementType;
  final int costCents;
  final int priceCents;
  final int remainingValueCents;
  final int profitCents;

  const SupplierStocktakeProductItem({
    required this.productId,
    required this.productName,
    this.sku,
    required this.variantId,
    this.colorName,
    this.sizeName,
    this.categoryName,
    required this.purchasedQuantity,
    required this.soldQuantity,
    this.saleReturnedQuantity = 0,
    this.purchaseReturnedQuantity = 0,
    required this.remainingQuantity,
    this.measurementType = 'piece',
    required this.costCents,
    this.priceCents = 0,
    required this.remainingValueCents,
    this.profitCents = 0,
  });

  String get variantLabel {
    final parts = <String>[];
    if (colorName != null && colorName!.isNotEmpty) parts.add(colorName!);
    if (sizeName != null && sizeName!.isNotEmpty) parts.add(sizeName!);
    return parts.join(' / ');
  }

  /// Net sold = sold - sale returns
  int get netSoldQuantity => soldQuantity - saleReturnedQuantity;

  /// Net purchased = purchased - purchase returns
  int get netPurchasedQuantity => purchasedQuantity - purchaseReturnedQuantity;
}

class SupplierStocktakeCategoryOption {
  final int id;
  final String name;
  const SupplierStocktakeCategoryOption({required this.id, required this.name});
}

class SupplierOption {
  final int id;
  final String name;
  final String? phone;
  final int balanceCents;

  const SupplierOption({
    required this.id,
    required this.name,
    this.phone,
    required this.balanceCents,
  });
}

class SupplierStocktakeReportData {
  final int? supplierId;
  final String? supplierName;
  final String? supplierPhone;
  final List<SupplierOption> suppliers;
  final List<SupplierStocktakeProductItem> products;
  final int totalPurchasedQuantity;
  final int totalSoldQuantity;
  final int totalSaleReturnedQuantity;
  final int totalPurchaseReturnedQuantity;
  final int totalRemainingQuantity;
  final int totalRemainingValueCents;
  final int totalProfitCents;
  final int totalProducts;
  final int totalVariants;
  final ReportDateRange dateRange;
  final SupplierStocktakeSortType sort;
  // Search & filter
  final String searchQuery;
  final int? filterCategoryId;
  final String? filterCategoryName;
  final List<SupplierStocktakeCategoryOption> availableCategories;

  const SupplierStocktakeReportData({
    this.supplierId,
    this.supplierName,
    this.supplierPhone,
    this.suppliers = const [],
    this.products = const [],
    this.totalPurchasedQuantity = 0,
    this.totalSoldQuantity = 0,
    this.totalSaleReturnedQuantity = 0,
    this.totalPurchaseReturnedQuantity = 0,
    this.totalRemainingQuantity = 0,
    this.totalRemainingValueCents = 0,
    this.totalProfitCents = 0,
    this.totalProducts = 0,
    this.totalVariants = 0,
    required this.dateRange,
    this.sort = SupplierStocktakeSortType.valueDesc,
    this.searchQuery = '',
    this.filterCategoryId,
    this.filterCategoryName,
    this.availableCategories = const [],
  });

  SupplierStocktakeReportData copyWith({
    int? supplierId,
    String? supplierName,
    String? supplierPhone,
    List<SupplierOption>? suppliers,
    List<SupplierStocktakeProductItem>? products,
    int? totalPurchasedQuantity,
    int? totalSoldQuantity,
    int? totalSaleReturnedQuantity,
    int? totalPurchaseReturnedQuantity,
    int? totalRemainingQuantity,
    int? totalRemainingValueCents,
    int? totalProfitCents,
    int? totalProducts,
    int? totalVariants,
    ReportDateRange? dateRange,
    SupplierStocktakeSortType? sort,
    String? searchQuery,
    int? Function()? filterCategoryId,
    String? Function()? filterCategoryName,
    List<SupplierStocktakeCategoryOption>? availableCategories,
  }) {
    return SupplierStocktakeReportData(
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      supplierPhone: supplierPhone ?? this.supplierPhone,
      suppliers: suppliers ?? this.suppliers,
      products: products ?? this.products,
      totalPurchasedQuantity:
          totalPurchasedQuantity ?? this.totalPurchasedQuantity,
      totalSoldQuantity: totalSoldQuantity ?? this.totalSoldQuantity,
      totalSaleReturnedQuantity:
          totalSaleReturnedQuantity ?? this.totalSaleReturnedQuantity,
      totalPurchaseReturnedQuantity:
          totalPurchaseReturnedQuantity ?? this.totalPurchaseReturnedQuantity,
      totalRemainingQuantity:
          totalRemainingQuantity ?? this.totalRemainingQuantity,
      totalRemainingValueCents:
          totalRemainingValueCents ?? this.totalRemainingValueCents,
      totalProfitCents: totalProfitCents ?? this.totalProfitCents,
      totalProducts: totalProducts ?? this.totalProducts,
      totalVariants: totalVariants ?? this.totalVariants,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
      searchQuery: searchQuery ?? this.searchQuery,
      filterCategoryId: filterCategoryId != null
          ? filterCategoryId()
          : this.filterCategoryId,
      filterCategoryName: filterCategoryName != null
          ? filterCategoryName()
          : this.filterCategoryName,
      availableCategories: availableCategories ?? this.availableCategories,
    );
  }
}

// ==================== BLOC ====================

class SupplierStocktakeReportBloc
    extends
        RealtimeBloc<
          SupplierStocktakeReportData,
          SupplierStocktakeReportEvent
        > {
  final AppDatabase _db;
  final WarehouseReadScope? warehouseScope;
  ReportDateRange _dateRange;
  SupplierStocktakeSortType _sort = SupplierStocktakeSortType.valueDesc;
  int? _supplierId;
  String _searchQuery = '';
  int? _filterCategoryId;
  String? _filterCategoryName;

  SupplierStocktakeReportBloc(
    this._db, {
    String defaultDateRange = 'month',
    this.warehouseScope,
  }) : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
       super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;
  int? get supplierId => _supplierId;

  @override
  Stream<SupplierStocktakeReportData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<SupplierStocktakeReportDateRangeChanged>(_onDateRangeChanged);
    on<SupplierStocktakeReportSupplierChanged>(_onSupplierChanged);
    on<SupplierStocktakeReportSortChanged>(_onSortChanged);
    on<SupplierStocktakeSearchChanged>(_onSearchChanged);
    on<SupplierStocktakeCategoryFilterChanged>(_onCategoryFilterChanged);
  }

  Stream<SupplierStocktakeReportData> _buildCombinedStream() {
    // Every table below can change either the supplier attribution, the
    // current valuation, or the period activity shown by the report.
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            _db.suppliers,
            _db.products,
            _db.productVariants,
            _db.productCategories,
            _db.productColors,
            _db.sizes,
            _db.productBatches,
            ...WarehouseBatchScope.dependencies(_db),
            ...WarehouseDocumentScope.dependencies(_db),
            ...WarehouseStockScope.dependencies(_db),
            _db.batchConsumptions,
            _db.purchases,
            _db.purchaseItems,
            _db.purchaseReturns,
            _db.purchaseReturnItems,
            _db.purchaseReturnAdjustments,
            _db.purchaseReturnAdjustmentItems,
            _db.sales,
            _db.saleItems,
            _db.saleReturns,
            _db.saleReturnItems,
            _db.saleReturnAdjustments,
            _db.saleReturnAdjustmentItems,
          },
        )
        .watch()
        .asyncMap(
          (_) => WarehouseReadScope.snapshot(_db, warehouseScope, () async {
            return _loadStocktakeData();
          }),
        );
  }

  Future<void> _onDateRangeChanged(
    SupplierStocktakeReportDateRangeChanged event,
    Emitter<RealtimeState<SupplierStocktakeReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onSupplierChanged(
    SupplierStocktakeReportSupplierChanged event,
    Emitter<RealtimeState<SupplierStocktakeReportData>> emit,
  ) async {
    _supplierId = event.supplierId;
    refresh();
  }

  Future<void> _onSearchChanged(
    SupplierStocktakeSearchChanged event,
    Emitter<RealtimeState<SupplierStocktakeReportData>> emit,
  ) async {
    _searchQuery = event.query;
    refresh();
  }

  Future<void> _onCategoryFilterChanged(
    SupplierStocktakeCategoryFilterChanged event,
    Emitter<RealtimeState<SupplierStocktakeReportData>> emit,
  ) async {
    _filterCategoryId = event.categoryId;
    _filterCategoryName = event.categoryName;
    refresh();
  }

  void _onSortChanged(
    SupplierStocktakeReportSortChanged event,
    Emitter<RealtimeState<SupplierStocktakeReportData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToProducts(current.products, event.sort);
      emit(
        RealtimeSuccess<SupplierStocktakeReportData>(
          data: current.copyWith(products: sorted, sort: event.sort),
        ),
      );
    }
  }

  List<SupplierStocktakeProductItem> _applySortToProducts(
    List<SupplierStocktakeProductItem> items,
    SupplierStocktakeSortType sort,
  ) {
    final list = List<SupplierStocktakeProductItem>.from(items);
    switch (sort) {
      case SupplierStocktakeSortType.valueDesc:
        list.sort(
          (a, b) => b.remainingValueCents.compareTo(a.remainingValueCents),
        );
      case SupplierStocktakeSortType.valueAsc:
        list.sort(
          (a, b) => a.remainingValueCents.compareTo(b.remainingValueCents),
        );
      case SupplierStocktakeSortType.nameAsc:
        list.sort((a, b) => a.productName.compareTo(b.productName));
      case SupplierStocktakeSortType.nameDesc:
        list.sort((a, b) => b.productName.compareTo(a.productName));
      case SupplierStocktakeSortType.stockDesc:
        list.sort((a, b) => b.remainingQuantity.compareTo(a.remainingQuantity));
      case SupplierStocktakeSortType.stockAsc:
        list.sort((a, b) => a.remainingQuantity.compareTo(b.remainingQuantity));
      case SupplierStocktakeSortType.soldDesc:
        list.sort((a, b) => b.soldQuantity.compareTo(a.soldQuantity));
      case SupplierStocktakeSortType.purchasedDesc:
        list.sort((a, b) => b.purchasedQuantity.compareTo(a.purchasedQuantity));
      case SupplierStocktakeSortType.profitDesc:
        list.sort((a, b) => b.profitCents.compareTo(a.profitCents));
    }
    return list;
  }

  /// Loads supplier stocktake data with returns, profit, search, and category filter
  Future<SupplierStocktakeReportData> _loadStocktakeData() async {
    // Load supplier list for the selector
    final supplierRows = await _db
        .customSelect(
          '''
      SELECT s.id, s.name, s.phone, s.balance_cents
      FROM suppliers s
      WHERE s.is_active = 1
      ORDER BY s.name ASC
      ''',
          readsFrom: {_db.suppliers},
        )
        .get();

    final suppliers = supplierRows
        .map(
          (row) => SupplierOption(
            id: row.read<int>('id'),
            name: row.read<String>('name'),
            phone: row.readNullable<String>('phone'),
            balanceCents: row.read<int>('balance_cents'),
          ),
        )
        .toList();

    // Load available categories
    final catRows = await _db
        .customSelect(
          'SELECT id, name FROM product_categories WHERE is_active = 1 ORDER BY name',
          readsFrom: {_db.productCategories},
        )
        .get();
    final categories = catRows
        .map(
          (r) => SupplierStocktakeCategoryOption(
            id: r.read<int>('id'),
            name: r.read<String>('name'),
          ),
        )
        .toList();

    if (_supplierId == null) {
      return SupplierStocktakeReportData(
        dateRange: _dateRange,
        suppliers: suppliers,
        searchQuery: _searchQuery,
        filterCategoryId: _filterCategoryId,
        filterCategoryName: _filterCategoryName,
        availableCategories: categories,
      );
    }

    // Load supplier info
    final supplierInfoRows = await _db
        .customSelect(
          'SELECT s.name, s.phone FROM suppliers s WHERE s.id = ?',
          variables: [Variable.withInt(_supplierId!)],
          readsFrom: {_db.suppliers},
        )
        .get();

    if (supplierInfoRows.isEmpty) {
      return SupplierStocktakeReportData(
        dateRange: _dateRange,
        suppliers: suppliers,
        availableCategories: categories,
      );
    }

    final sInfo = supplierInfoRows.first;
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = DateTime(
      _dateRange.endDate.year,
      _dateRange.endDate.month,
      _dateRange.endDate.day,
      23,
      59,
      59,
    ).toIso8601String();

    // Build dynamic WHERE for search + category
    final extraWhere = StringBuffer();
    final extraVars = <Variable<Object>>[];

    if (_searchQuery.isNotEmpty) {
      extraWhere.write(
        ' AND (p.name LIKE ? OR COALESCE(pv.sku, p.sku) LIKE ?)',
      );
      extraVars.add(Variable<String>('%$_searchQuery%'));
      extraVars.add(Variable<String>('%$_searchQuery%'));
    }
    if (_filterCategoryId != null) {
      extraWhere.write(' AND p.category_id = ?');
      extraVars.add(Variable<int>(_filterCategoryId!));
    }

    String resolvedVariant(String alias) =>
        'COALESCE(${WarehouseDocumentScope.operationalVariant(alias)}, 0)';

    final metaRows = await _db
        .customSelect(
          '''
      SELECT p.id AS product_id, COALESCE(pv.id, 0) AS variant_id,
             p.name AS product_name, COALESCE(pv.sku, p.sku) AS product_sku,
             pc.name AS color_name, sz.name AS size_name,
             cat.name AS category_name,
             CASE WHEN pv.id IS NULL THEN COALESCE(p.stock_quantity, 0) ELSE ws.quantity END AS current_stock,
             CASE WHEN pv.id IS NULL THEN COALESCE(p.cost_cents, 0) ELSE ws.unit_cost_cents END AS current_cost,
             COALESCE(pv.price_cents, p.price_cents, 0) AS current_price,
             p.measurement_type AS measurement_type,
             CASE WHEN p.measurement_type = 'piece' THEN 1 ELSE 1000 END AS quantity_scale,
             CASE WHEN p.inventory_tracking_type IN ('batch', 'batch_expiry')
                        OR p.costing_method = 'fifo'
                  THEN 1 ELSE 0 END AS uses_batch_costing
      FROM products p
      LEFT JOIN product_variants pv
        ON pv.product_id = p.id AND pv.is_active = 1
      LEFT JOIN ${warehouseScope?.stocks ?? WarehouseStockScope.primaryStocks} ws ON ws.variant_id = pv.id
      LEFT JOIN product_categories cat ON cat.id = p.category_id
      LEFT JOIN product_colors pc ON pc.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE p.is_active = 1 AND p.track_inventory = 1
        ${warehouseScope != null && !warehouseScope!.isPrimary ? 'AND ws.variant_id IS NOT NULL' : ''}
        $extraWhere
      ORDER BY p.name, pc.name, sz.name
      ''',
          variables: extraVars,
          readsFrom: {
            _db.products,
            _db.productVariants,
            _db.productCategories,
            _db.productColors,
            _db.sizes,
            ...WarehouseStockScope.dependencies(_db),
          },
        )
        .get();

    final metadata = <_VariantKey, _VariantMeta>{};
    for (final row in metaRows) {
      final key = (
        productId: row.read<int>('product_id'),
        variantId: row.read<int>('variant_id'),
      );
      metadata[key] = _VariantMeta(
        productId: key.productId,
        variantId: key.variantId,
        productName: row.read<String>('product_name'),
        sku: row.readNullable<String>('product_sku'),
        colorName: row.readNullable<String>('color_name'),
        sizeName: row.readNullable<String>('size_name'),
        categoryName: row.readNullable<String>('category_name'),
        currentStock: row.read<int>('current_stock'),
        currentCostCents: row.read<int>('current_cost'),
        currentPriceCents: row.read<int>('current_price'),
        quantityScale: row.read<int>('quantity_scale'),
        measurementType: row.read<String>('measurement_type'),
        usesBatchCosting: row.read<int>('uses_batch_costing') == 1,
      );
    }

    final metrics = <_VariantKey, _SupplierVariantMetrics>{};
    _SupplierVariantMetrics metricsFor(_VariantKey key) =>
        metrics.putIfAbsent(key, _SupplierVariantMetrics.new);

    // Period purchases and both purchase-return types are supplier-specific
    // facts, so no allocation is needed for these columns.
    final purchaseActivityRows = await _db
        .customSelect(
          '''
      SELECT kind, product_id, variant_id, SUM(quantity) AS quantity
      FROM (
        SELECT 'purchase' AS kind, pi.product_id AS product_id,
               ${resolvedVariant('pi')} AS variant_id, pi.quantity AS quantity
        FROM purchase_items pi
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.purchase) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchase)} pu ON pu.id = pi.purchase_id
        WHERE pu.status = 'posted' AND pu.supplier_id = ?
          AND pu.purchase_date >= ? AND pu.purchase_date <= ?
        UNION ALL
        SELECT 'return' AS kind, pi.product_id AS product_id,
               ${resolvedVariant('pi')} AS variant_id, pri.quantity AS quantity
        FROM purchase_return_items pri
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.purchaseReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchaseReturn)} pr ON pr.id = pri.return_id
        INNER JOIN purchase_items pi ON pi.id = pri.purchase_item_id
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.purchase) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchase)} pu ON pu.id = pi.purchase_id
        WHERE pr.status = 'posted' AND pu.supplier_id = ?
          AND pr.return_date >= ? AND pr.return_date <= ?
        UNION ALL
        SELECT 'return' AS kind, prai.product_id AS product_id,
               ${resolvedVariant('prai')} AS variant_id, prai.quantity AS quantity
        FROM purchase_return_adjustment_items prai
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.purchaseAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchaseAdjustment)} pra ON pra.id = prai.return_id
        WHERE pra.status = 'posted' AND pra.supplier_id = ?
          AND pra.return_date >= ? AND pra.return_date <= ?
      ) activity
      GROUP BY kind, product_id, variant_id
      ''',
          variables: [
            Variable.withInt(_supplierId!),
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withInt(_supplierId!),
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withInt(_supplierId!),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.purchases,
            _db.purchaseItems,
            _db.purchaseReturns,
            _db.purchaseReturnItems,
            _db.purchaseReturnAdjustments,
            _db.purchaseReturnAdjustmentItems,
          },
        )
        .get();
    for (final row in purchaseActivityRows) {
      final key = (
        productId: row.read<int>('product_id'),
        variantId: row.read<int>('variant_id'),
      );
      final item = metricsFor(key);
      final quantity = row.read<int>('quantity');
      if (row.read<String>('kind') == 'purchase') {
        item.purchasedQuantity += quantity;
      } else {
        item.purchaseReturnedQuantity += quantity;
      }
    }

    // WAC has no physical supplier-owned layers after costs are blended.
    // Build lifetime net-purchase weights for every supplier, then allocate
    // integer quantities/cents with a total-preserving largest remainder.
    final sourceRows = await _db
        .customSelect(
          '''
      SELECT supplier_id, product_id, variant_id, SUM(quantity_delta) AS weight
      FROM (
        SELECT pu.supplier_id AS supplier_id, pi.product_id AS product_id,
               ${resolvedVariant('pi')} AS variant_id, pi.quantity AS quantity_delta
        FROM purchase_items pi
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.purchase) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchase)} pu ON pu.id = pi.purchase_id
        WHERE pu.status = 'posted'
        UNION ALL
        SELECT pu.supplier_id AS supplier_id, pi.product_id AS product_id,
               ${resolvedVariant('pi')} AS variant_id, -pri.quantity AS quantity_delta
        FROM purchase_return_items pri
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.purchaseReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchaseReturn)} pr ON pr.id = pri.return_id
        INNER JOIN purchase_items pi ON pi.id = pri.purchase_item_id
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.purchase) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchase)} pu ON pu.id = pi.purchase_id
        WHERE pr.status = 'posted'
        UNION ALL
        SELECT pra.supplier_id AS supplier_id, prai.product_id AS product_id,
               ${resolvedVariant('prai')} AS variant_id, -prai.quantity AS quantity_delta
        FROM purchase_return_adjustment_items prai
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.purchaseAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchaseAdjustment)} pra ON pra.id = prai.return_id
        WHERE pra.status = 'posted'
      ) source_movements
      GROUP BY supplier_id, product_id, variant_id
      ''',
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.purchases,
            _db.purchaseItems,
            _db.purchaseReturns,
            _db.purchaseReturnItems,
            _db.purchaseReturnAdjustments,
            _db.purchaseReturnAdjustmentItems,
          },
        )
        .get();
    final sourceWeights = <_VariantKey, Map<int, int>>{};
    for (final row in sourceRows) {
      final key = (
        productId: row.read<int>('product_id'),
        variantId: row.read<int>('variant_id'),
      );
      final weight = row.read<int>('weight');
      if (weight > 0) {
        sourceWeights.putIfAbsent(
          key,
          () => <int, int>{},
        )[row.read<int>('supplier_id')] = weight;
      }
    }

    final unassignedRows = await _db
        .customSelect(
          '''
      SELECT pb.product_id AS product_id,
             COALESCE(pb.variant_id, (SELECT MIN(pv0.id)
               FROM product_variants pv0 WHERE pv0.product_id = pb.product_id
               AND pv0.is_active = 1), 0) AS variant_id,
             SUM(pb.received_quantity) AS weight
      FROM ${warehouseScope?.batches ?? WarehouseBatchScope.primaryBatches} pb
      WHERE pb.is_active = 1 AND pb.supplier_id IS NULL
        AND pb.source != 'purchase'
      GROUP BY pb.product_id, COALESCE(pb.variant_id, 0)
      ''',
          readsFrom: {
            _db.productBatches,
            ...WarehouseBatchScope.dependencies(_db),
            ...WarehouseDocumentScope.dependencies(_db),
            _db.productVariants,
          },
        )
        .get();
    final unassignedWeights = <_VariantKey, int>{};
    for (final row in unassignedRows) {
      final key = (
        productId: row.read<int>('product_id'),
        variantId: row.read<int>('variant_id'),
      );
      unassignedWeights[key] =
          (unassignedWeights[key] ?? 0) + row.read<int>('weight');
    }

    Map<int, int> weightsFor(
      _VariantKey key, {
      bool coverCurrentStock = false,
    }) {
      final result = Map<int, int>.from(sourceWeights[key] ?? const {});
      final unassigned = unassignedWeights[key] ?? 0;
      if (unassigned > 0) result[_unassignedSupplierSource] = unassigned;
      if (coverCurrentStock) {
        final stock = metadata[key]?.currentStock ?? 0;
        final known = result.values.fold<int>(0, (a, b) => a + b);
        if (stock > known) {
          result[_unassignedSupplierSource] =
              (result[_unassignedSupplierSource] ?? 0) + stock - known;
        }
      }
      return result;
    }

    // Exact FIFO/batch balance: only the selected supplier's currently
    // remaining layers are counted. No current global stock is duplicated.
    final fifoBalanceRows = await _db
        .customSelect(
          '''
      SELECT pb.product_id AS product_id,
             COALESCE(pb.variant_id, (SELECT MIN(pv0.id)
               FROM product_variants pv0 WHERE pv0.product_id = pb.product_id
               AND pv0.is_active = 1), 0) AS variant_id,
             SUM(pb.remaining_quantity) AS remaining_qty,
             SUM(CAST(ROUND(
               1.0 * pb.remaining_quantity * pb.unit_cost_cents /
               CASE WHEN p.measurement_type = 'piece' THEN 1 ELSE 1000 END
             ) AS INTEGER)) AS remaining_value
      FROM ${warehouseScope?.batches ?? WarehouseBatchScope.primaryBatches} pb
      INNER JOIN products p ON p.id = pb.product_id
      WHERE pb.is_active = 1 AND pb.remaining_quantity != 0
        AND pb.supplier_id = ?
      GROUP BY pb.product_id, COALESCE(pb.variant_id, 0)
      ''',
          variables: [Variable.withInt(_supplierId!)],
          readsFrom: {
            _db.productBatches,
            ...WarehouseBatchScope.dependencies(_db),
            ...WarehouseDocumentScope.dependencies(_db),
            _db.productVariants,
            _db.products,
          },
        )
        .get();
    for (final row in fifoBalanceRows) {
      final key = (
        productId: row.read<int>('product_id'),
        variantId: row.read<int>('variant_id'),
      );
      if (metadata[key]?.usesBatchCosting != true) continue;
      final item = metricsFor(key);
      item.remainingQuantity = row.read<int>('remaining_qty');
      item.remainingValueCents = row.read<int>('remaining_value');
    }

    for (final entry in metadata.entries) {
      if (entry.value.usesBatchCosting) continue;
      final weights = weightsFor(entry.key, coverCurrentStock: true);
      final allocatedStock = _allocateLargestRemainder(
        entry.value.currentStock,
        weights,
        _supplierId!,
      );
      final item = metricsFor(entry.key);
      item.remainingQuantity = allocatedStock;
      item.remainingValueCents = MeasuredAmount.cents(
        unitCents: entry.value.currentCostCents,
        quantity: allocatedStock,
        quantityScale: entry.value.quantityScale,
      );
    }

    // Period WAC activity uses frozen posted costs and net-of-tax revenue.
    // Each measure is allocated independently with the same historical source
    // weights, so totals remain conservative even for one-unit stock/sales.
    final wacActivityRows = await _db
        .customSelect(
          '''
      SELECT product_id, variant_id,
             SUM(sold_qty) AS sold_qty,
             SUM(returned_qty) AS returned_qty,
             SUM(net_revenue) AS net_revenue,
             SUM(net_cogs) AS net_cogs
      FROM (
        SELECT si.product_id AS product_id, ${resolvedVariant('si')} AS variant_id,
               si.quantity AS sold_qty, 0 AS returned_qty,
               (si.total_cents - si.tax_cents) AS net_revenue,
               CAST(ROUND(1.0 * si.quantity * COALESCE(si.cost_cents, pv.cost_cents, p.cost_cents, 0)
                          / si.quantity_scale) AS INTEGER) AS net_cogs
        FROM sale_items si
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.sale) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.sale)} sa ON sa.id = si.sale_id
        INNER JOIN products p ON p.id = si.product_id AND p.track_inventory = 1
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        WHERE sa.status = 'completed' AND sa.sale_date >= ? AND sa.sale_date <= ?
        UNION ALL
        SELECT si.product_id AS product_id, ${resolvedVariant('si')} AS variant_id,
               0 AS sold_qty, sri.quantity AS returned_qty,
               -(sri.refund_cents - sri.tax_cents) AS net_revenue,
               -CAST(ROUND(1.0 * sri.quantity * COALESCE(sri.unit_cost_at_post_cents,
                                         si.cost_cents, pv.cost_cents,
                                         p.cost_cents, 0) / sri.quantity_scale) AS INTEGER) AS net_cogs
        FROM sale_return_items sri
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleReturn)} sr ON sr.id = sri.return_id
        INNER JOIN sale_items si ON si.id = sri.sale_item_id
        INNER JOIN products p ON p.id = si.product_id AND p.track_inventory = 1
        LEFT JOIN product_variants pv ON pv.id = si.variant_id
        WHERE sr.status = 'posted' AND sr.return_date >= ? AND sr.return_date <= ?
        UNION ALL
        SELECT srai.product_id AS product_id, ${resolvedVariant('srai')} AS variant_id,
               0 AS sold_qty, srai.quantity AS returned_qty,
               -(srai.total_cents - srai.tax_cents) AS net_revenue,
               -CAST(ROUND(1.0 * srai.quantity * COALESCE(srai.unit_cost_at_post_cents,
                                          srai.unit_cost_cents, 0) / srai.quantity_scale) AS INTEGER) AS net_cogs
        FROM sale_return_adjustment_items srai
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra ON sra.id = srai.return_id
        INNER JOIN products p ON p.id = srai.product_id AND p.track_inventory = 1
        WHERE sra.status = 'posted' AND sra.return_date >= ? AND sra.return_date <= ?
      ) activity
      GROUP BY product_id, variant_id
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.sales,
            _db.saleItems,
            _db.saleReturns,
            _db.saleReturnItems,
            _db.saleReturnAdjustments,
            _db.saleReturnAdjustmentItems,
            _db.products,
            _db.productVariants,
          },
        )
        .get();
    for (final row in wacActivityRows) {
      final key = (
        productId: row.read<int>('product_id'),
        variantId: row.read<int>('variant_id'),
      );
      if (metadata[key]?.usesBatchCosting != false) continue;
      final weights = weightsFor(key);
      final item = metricsFor(key);
      item.soldQuantity += _allocateLargestRemainder(
        row.read<int>('sold_qty'),
        weights,
        _supplierId!,
      );
      item.saleReturnedQuantity += _allocateLargestRemainder(
        row.read<int>('returned_qty'),
        weights,
        _supplierId!,
      );
      item.netRevenueCents += _allocateLargestRemainder(
        row.read<int>('net_revenue'),
        weights,
        _supplierId!,
      );
      item.netCogsCents += _allocateLargestRemainder(
        row.read<int>('net_cogs'),
        weights,
        _supplierId!,
      );
    }

    // FIFO sales and linked returns are attributable to the exact supplier
    // layer consumed/restored. Revenue is split per document line while the
    // cost is read exactly from batch_consumptions.
    final fifoActivityRows = await _db
        .customSelect(
          '''
      SELECT kind, line_id, product_id, variant_id, source_id,
             SUM(source_qty) AS source_qty, SUM(source_cost) AS source_cost,
             net_revenue
      FROM (
        SELECT 'sale' AS kind, si.id AS line_id, si.product_id AS product_id,
               ${resolvedVariant('si')} AS variant_id,
               COALESCE(pb.supplier_id, -1) AS source_id,
               bc.quantity AS source_qty,
               CAST(ROUND(1.0 * bc.quantity * bc.unit_cost_cents / si.quantity_scale) AS INTEGER) AS source_cost,
               (si.total_cents - si.tax_cents) AS net_revenue
        FROM batch_consumptions bc
        INNER JOIN ${warehouseScope?.batches ?? WarehouseBatchScope.primaryBatches} pb ON pb.id = bc.batch_id
        INNER JOIN sale_items si ON si.id = bc.sale_item_id
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.sale) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.sale)} sa ON sa.id = si.sale_id
        WHERE bc.direction = 'out' AND bc.consumption_type = 'sale'
          AND sa.status = 'completed' AND sa.sale_date >= ? AND sa.sale_date <= ?
        UNION ALL
        SELECT 'linked_return' AS kind, sri.id AS line_id, si.product_id AS product_id,
               ${resolvedVariant('si')} AS variant_id,
               COALESCE(pb.supplier_id, -1) AS source_id,
               bc.quantity AS source_qty,
               CAST(ROUND(1.0 * bc.quantity * bc.unit_cost_cents / sri.quantity_scale) AS INTEGER) AS source_cost,
               -(sri.refund_cents - sri.tax_cents) AS net_revenue
        FROM batch_consumptions bc
        INNER JOIN ${warehouseScope?.batches ?? WarehouseBatchScope.primaryBatches} pb ON pb.id = bc.batch_id
        INNER JOIN sale_return_items sri ON sri.id = bc.sale_return_item_id
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleReturn)} sr ON sr.id = sri.return_id
        INNER JOIN sale_items si ON si.id = sri.sale_item_id
        WHERE bc.direction = 'in' AND bc.consumption_type = 'sale_return_reverse'
          AND sr.status = 'posted' AND sr.return_date >= ? AND sr.return_date <= ?
        UNION ALL
        SELECT 'adjustment_return' AS kind, srai.id AS line_id, srai.product_id AS product_id,
               ${resolvedVariant('srai')} AS variant_id,
               COALESCE(pb.supplier_id, -1) AS source_id,
               bc.quantity AS source_qty,
               CAST(ROUND(1.0 * bc.quantity * bc.unit_cost_cents / srai.quantity_scale) AS INTEGER) AS source_cost,
               -(srai.total_cents - srai.tax_cents) AS net_revenue
        FROM batch_consumptions bc
        INNER JOIN ${warehouseScope?.batches ?? WarehouseBatchScope.primaryBatches} pb ON pb.id = bc.batch_id
        INNER JOIN sale_return_adjustment_items srai
          ON srai.id = bc.sale_return_adjustment_item_id
        INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra ON sra.id = srai.return_id
        WHERE bc.direction = 'in'
          AND bc.consumption_type = 'sale_adj_return_reverse'
          AND sra.status = 'posted' AND sra.return_date >= ? AND sra.return_date <= ?
      ) lines
      GROUP BY kind, line_id, product_id, variant_id, source_id, net_revenue
      ''',
          variables: [
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            _db.batchConsumptions,
            _db.productBatches,
            ...WarehouseBatchScope.dependencies(_db),
            ...WarehouseDocumentScope.dependencies(_db),
            _db.sales,
            _db.saleItems,
            _db.saleReturns,
            _db.saleReturnItems,
            _db.saleReturnAdjustments,
            _db.saleReturnAdjustmentItems,
          },
        )
        .get();
    final fifoLines = <String, _FifoActivityLine>{};
    for (final row in fifoActivityRows) {
      final kind = row.read<String>('kind');
      final lineKey = '$kind:${row.read<int>('line_id')}';
      final key = (
        productId: row.read<int>('product_id'),
        variantId: row.read<int>('variant_id'),
      );
      if (metadata[key]?.usesBatchCosting != true) continue;
      final line = fifoLines.putIfAbsent(
        lineKey,
        () => _FifoActivityLine(
          kind: kind,
          key: key,
          netRevenueCents: row.read<int>('net_revenue'),
        ),
      );
      final sourceId = row.read<int>('source_id');
      line.quantityBySource[sourceId] =
          (line.quantityBySource[sourceId] ?? 0) + row.read<int>('source_qty');
      line.costBySource[sourceId] =
          (line.costBySource[sourceId] ?? 0) + row.read<int>('source_cost');
    }
    for (final line in fifoLines.values) {
      final item = metricsFor(line.key);
      final supplierQty = line.quantityBySource[_supplierId!] ?? 0;
      if (line.kind == 'sale') {
        item.soldQuantity += supplierQty;
        item.netCogsCents += line.costBySource[_supplierId!] ?? 0;
      } else {
        item.saleReturnedQuantity += supplierQty;
        item.netCogsCents -= line.costBySource[_supplierId!] ?? 0;
      }
      item.netRevenueCents += _allocateLargestRemainder(
        line.netRevenueCents,
        line.quantityBySource,
        _supplierId!,
      );
    }

    final products = <SupplierStocktakeProductItem>[];
    var totalPurchased = 0;
    var totalSold = 0;
    var totalSaleReturned = 0;
    var totalPurchaseReturned = 0;
    var totalRemaining = 0;
    var totalRemainingValue = 0;
    var totalProfit = 0;
    final uniqueProductIds = <int>{};

    for (final entry in metadata.entries) {
      final item = metrics[entry.key];
      if (item == null) continue;
      final hasData =
          item.purchasedQuantity != 0 ||
          item.soldQuantity != 0 ||
          item.saleReturnedQuantity != 0 ||
          item.purchaseReturnedQuantity != 0 ||
          item.remainingQuantity != 0 ||
          item.remainingValueCents != 0 ||
          item.netRevenueCents != 0 ||
          item.netCogsCents != 0;
      if (!hasData) continue;

      final meta = entry.value;
      final profitCents = item.netRevenueCents - item.netCogsCents;
      final displayedCost = item.remainingQuantity == 0
          ? meta.currentCostCents
          : MeasuredAmount.unitCentsFromTotal(
              totalCents: item.remainingValueCents,
              quantity: item.remainingQuantity,
              quantityScale: meta.quantityScale,
            );
      uniqueProductIds.add(meta.productId);
      totalPurchased += item.purchasedQuantity;
      totalSold += item.soldQuantity;
      totalSaleReturned += item.saleReturnedQuantity;
      totalPurchaseReturned += item.purchaseReturnedQuantity;
      totalRemaining += item.remainingQuantity;
      totalRemainingValue += item.remainingValueCents;
      totalProfit += profitCents;

      products.add(
        SupplierStocktakeProductItem(
          productId: meta.productId,
          productName: meta.productName,
          sku: meta.sku,
          variantId: meta.variantId,
          colorName: meta.colorName,
          sizeName: meta.sizeName,
          categoryName: meta.categoryName,
          purchasedQuantity: item.purchasedQuantity,
          soldQuantity: item.soldQuantity,
          saleReturnedQuantity: item.saleReturnedQuantity,
          purchaseReturnedQuantity: item.purchaseReturnedQuantity,
          remainingQuantity: item.remainingQuantity,
          measurementType: meta.measurementType,
          costCents: displayedCost,
          priceCents: meta.currentPriceCents,
          remainingValueCents: item.remainingValueCents,
          profitCents: profitCents,
        ),
      );
    }

    final sorted = _applySortToProducts(products, _sort);

    return SupplierStocktakeReportData(
      supplierId: _supplierId,
      supplierName: sInfo.read<String>('name'),
      supplierPhone: sInfo.readNullable<String>('phone'),
      suppliers: suppliers,
      products: sorted,
      totalPurchasedQuantity: totalPurchased,
      totalSoldQuantity: totalSold,
      totalSaleReturnedQuantity: totalSaleReturned,
      totalPurchaseReturnedQuantity: totalPurchaseReturned,
      totalRemainingQuantity: totalRemaining,
      totalRemainingValueCents: totalRemainingValue,
      totalProfitCents: totalProfit,
      totalProducts: uniqueProductIds.length,
      totalVariants: products.length,
      dateRange: _dateRange,
      sort: _sort,
      searchQuery: _searchQuery,
      filterCategoryId: _filterCategoryId,
      filterCategoryName: _filterCategoryName,
      availableCategories: categories,
    );
  }
}
