import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
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

class SupplierStocktakeCategoryFilterChanged extends SupplierStocktakeReportEvent {
  final int? categoryId;
  final String? categoryName;
  const SupplierStocktakeCategoryFilterChanged(this.categoryId, this.categoryName);
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
  final int balanceCents;

  const SupplierOption({
    required this.id,
    required this.name,
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
      filterCategoryId: filterCategoryId != null ? filterCategoryId() : this.filterCategoryId,
      filterCategoryName: filterCategoryName != null ? filterCategoryName() : this.filterCategoryName,
      availableCategories: availableCategories ?? this.availableCategories,
    );
  }
}

// ==================== BLOC ====================

class SupplierStocktakeReportBloc extends RealtimeBloc<
    SupplierStocktakeReportData, SupplierStocktakeReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  SupplierStocktakeSortType _sort = SupplierStocktakeSortType.valueDesc;
  int? _supplierId;
  String _searchQuery = '';
  int? _filterCategoryId;
  String? _filterCategoryName;

  SupplierStocktakeReportBloc(this._db) : super(const RealtimeLoading());

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
    // Watch purchases and sales for real-time changes
    return _db.select(_db.purchaseItems).watch().asyncMap((_) async {
      return _loadStocktakeData();
    });
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
      emit(RealtimeSuccess<SupplierStocktakeReportData>(
        data: current.copyWith(
          products: sorted,
          sort: event.sort,
        ),
      ));
    }
  }

  List<SupplierStocktakeProductItem> _applySortToProducts(
    List<SupplierStocktakeProductItem> items,
    SupplierStocktakeSortType sort,
  ) {
    final list = List<SupplierStocktakeProductItem>.from(items);
    switch (sort) {
      case SupplierStocktakeSortType.valueDesc:
        list.sort((a, b) =>
            b.remainingValueCents.compareTo(a.remainingValueCents));
      case SupplierStocktakeSortType.valueAsc:
        list.sort((a, b) =>
            a.remainingValueCents.compareTo(b.remainingValueCents));
      case SupplierStocktakeSortType.nameAsc:
        list.sort((a, b) => a.productName.compareTo(b.productName));
      case SupplierStocktakeSortType.nameDesc:
        list.sort((a, b) => b.productName.compareTo(a.productName));
      case SupplierStocktakeSortType.stockDesc:
        list.sort((a, b) =>
            b.remainingQuantity.compareTo(a.remainingQuantity));
      case SupplierStocktakeSortType.stockAsc:
        list.sort((a, b) =>
            a.remainingQuantity.compareTo(b.remainingQuantity));
      case SupplierStocktakeSortType.soldDesc:
        list.sort((a, b) => b.soldQuantity.compareTo(a.soldQuantity));
      case SupplierStocktakeSortType.purchasedDesc:
        list.sort(
            (a, b) => b.purchasedQuantity.compareTo(a.purchasedQuantity));
      case SupplierStocktakeSortType.profitDesc:
        list.sort((a, b) => b.profitCents.compareTo(a.profitCents));
    }
    return list;
  }

  /// Loads supplier stocktake data with returns, profit, search, and category filter
  Future<SupplierStocktakeReportData> _loadStocktakeData() async {
    // Load supplier list for the selector
    final supplierRows = await _db.customSelect(
      '''
      SELECT s.id, s.name, s.balance_cents
      FROM suppliers s
      WHERE s.is_active = 1
      ORDER BY s.name ASC
      ''',
      readsFrom: {_db.suppliers},
    ).get();

    final suppliers = supplierRows
        .map((row) => SupplierOption(
              id: row.read<int>('id'),
              name: row.read<String>('name'),
              balanceCents: row.read<int>('balance_cents'),
            ))
        .toList();

    // Load available categories
    final catRows = await _db.customSelect(
      'SELECT id, name FROM product_categories WHERE is_active = 1 ORDER BY name',
      readsFrom: {_db.productCategories},
    ).get();
    final categories = catRows
        .map((r) => SupplierStocktakeCategoryOption(
              id: r.read<int>('id'),
              name: r.read<String>('name'),
            ))
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
    final supplierInfoRows = await _db.customSelect(
      'SELECT s.name, s.phone FROM suppliers s WHERE s.id = ?',
      variables: [Variable.withInt(_supplierId!)],
      readsFrom: {_db.suppliers},
    ).get();

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
      23, 59, 59,
    ).toIso8601String();

    // Build dynamic WHERE for search + category
    final extraWhere = StringBuffer();
    final extraVars = <Variable<Object>>[];

    if (_searchQuery.isNotEmpty) {
      extraWhere.write(' AND (p.name LIKE ? OR COALESCE(pv.sku, p.sku) LIKE ?)');
      extraVars.add(Variable<String>('%$_searchQuery%'));
      extraVars.add(Variable<String>('%$_searchQuery%'));
    }
    if (_filterCategoryId != null) {
      extraWhere.write(' AND p.category_id = ?');
      extraVars.add(Variable<int>(_filterCategoryId!));
    }

    // Get all product variants purchased from this supplier in the date range
    final purchasedRows = await _db.customSelect(
      '''
      SELECT 
        p.id AS product_id,
        p.name AS product_name,
        COALESCE(pv.sku, p.sku) AS product_sku,
        cat.name AS category_name,
        COALESCE(pi.variant_id, pv_default.id) AS variant_id,
        pc.name AS color_name,
        sz.name AS size_name,
        SUM(pi.quantity) AS purchased_qty,
        COALESCE(
          CASE WHEN pi.variant_id IS NOT NULL THEN pv.cost_cents ELSE pv_default.cost_cents END,
          p.cost_cents
        ) AS cost_cents,
        COALESCE(
          CASE WHEN pi.variant_id IS NOT NULL THEN pv.price_cents ELSE pv_default.price_cents END,
          p.price_cents
        ) AS price_cents,
        COALESCE(
          CASE WHEN pi.variant_id IS NOT NULL THEN pv.stock_quantity ELSE pv_default.stock_quantity END,
          0
        ) AS current_stock
      FROM purchase_items pi
      JOIN purchases pu ON pi.purchase_id = pu.id
      JOIN products p ON pi.product_id = p.id
      LEFT JOIN product_variants pv ON pi.variant_id = pv.id
      LEFT JOIN product_variants pv_default 
        ON pv_default.product_id = p.id AND pi.variant_id IS NULL
        AND pv_default.id = (
          SELECT MIN(pv2.id) FROM product_variants pv2 
          WHERE pv2.product_id = p.id AND pv2.is_active = 1
        )
      LEFT JOIN product_categories cat ON cat.id = p.category_id
      LEFT JOIN product_colors pc ON COALESCE(pv.color_id, pv_default.color_id) = pc.id
      LEFT JOIN sizes sz ON COALESCE(pv.size_id, pv_default.size_id) = sz.id
      WHERE pu.supplier_id = ?
        AND pu.status = 'posted'
        AND pu.purchase_date >= ?
        AND pu.purchase_date <= ?
        $extraWhere
      GROUP BY p.id, COALESCE(pi.variant_id, pv_default.id)
      ORDER BY p.name, pc.name, sz.name
      ''',
      variables: [
        Variable.withInt(_supplierId!),
        Variable.withString(startIso),
        Variable.withString(endIso),
        ...extraVars,
      ],
      readsFrom: {
        _db.purchaseItems,
        _db.purchases,
        _db.products,
        _db.productVariants,
        _db.productCategories,
        _db.productColors,
        _db.sizes,
      },
    ).get();

    // For each purchased product/variant, get sold qty + returns in the same date range
    final products = <SupplierStocktakeProductItem>[];
    int totalPurchased = 0;
    int totalSold = 0;
    int totalSaleReturned = 0;
    int totalPurchaseReturned = 0;
    int totalRemaining = 0;
    int totalRemainingValue = 0;
    int totalProfit = 0;
    final uniqueProductIds = <int>{};

    for (final row in purchasedRows) {
      final productId = row.read<int>('product_id');
      final variantId = row.readNullable<int>('variant_id');
      final purchasedQty = row.read<int>('purchased_qty');
      final costCents = row.read<int>('cost_cents');
      final priceCents = row.read<int>('price_cents');
      final currentStock = row.read<int>('current_stock');

      // Get sold quantity
      int soldQty = 0;
      if (variantId != null) {
        final soldRows = await _db.customSelect(
          '''
          SELECT COALESCE(SUM(si.quantity), 0) AS sold_qty
          FROM sale_items si
          JOIN sales sa ON si.sale_id = sa.id
          WHERE si.product_id = ? AND si.variant_id = ?
            AND sa.status IN ('completed', 'posted')
            AND sa.sale_date >= ? AND sa.sale_date <= ?
          ''',
          variables: [
            Variable.withInt(productId),
            Variable.withInt(variantId),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {_db.saleItems, _db.sales},
        ).get();
        if (soldRows.isNotEmpty) soldQty = soldRows.first.read<int>('sold_qty');
      } else {
        final soldRows = await _db.customSelect(
          '''
          SELECT COALESCE(SUM(si.quantity), 0) AS sold_qty
          FROM sale_items si
          JOIN sales sa ON si.sale_id = sa.id
          WHERE si.product_id = ?
            AND sa.status IN ('completed', 'posted')
            AND sa.sale_date >= ? AND sa.sale_date <= ?
          ''',
          variables: [
            Variable.withInt(productId),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {_db.saleItems, _db.sales},
        ).get();
        if (soldRows.isNotEmpty) soldQty = soldRows.first.read<int>('sold_qty');
      }

      // Get sale returned quantity
      int saleReturnedQty = 0;
      {
        final variantClause = variantId != null
            ? 'AND si.variant_id = ?'
            : '';
        final vars = [
          Variable.withInt(productId),
          if (variantId != null) Variable.withInt(variantId),
          Variable.withString(startIso),
          Variable.withString(endIso),
        ];
        final retRows = await _db.customSelect(
          '''
          SELECT COALESCE(SUM(sri.quantity), 0) AS ret_qty
          FROM sale_return_items sri
          JOIN sale_items si ON si.id = sri.sale_item_id
          JOIN sale_returns sr ON sr.id = sri.return_id AND sr.status = 'posted'
          WHERE si.product_id = ? $variantClause
            AND sr.return_date >= ? AND sr.return_date <= ?
          ''',
          variables: vars,
          readsFrom: {_db.saleReturnItems, _db.saleItems, _db.saleReturns},
        ).get();
        if (retRows.isNotEmpty) saleReturnedQty = retRows.first.read<int>('ret_qty');
      }

      // Get purchase returned quantity
      int purchaseReturnedQty = 0;
      {
        final variantClause = variantId != null
            ? 'AND pi2.variant_id = ?'
            : '';
        final vars = [
          Variable.withInt(productId),
          if (variantId != null) Variable.withInt(variantId),
          Variable.withString(startIso),
          Variable.withString(endIso),
        ];
        final retRows = await _db.customSelect(
          '''
          SELECT COALESCE(SUM(pri.quantity), 0) AS ret_qty
          FROM purchase_return_items pri
          JOIN purchase_items pi2 ON pi2.id = pri.purchase_item_id
          JOIN purchase_returns pr ON pr.id = pri.return_id AND pr.status = 'posted'
          WHERE pi2.product_id = ? $variantClause
            AND pr.return_date >= ? AND pr.return_date <= ?
          ''',
          variables: vars,
          readsFrom: {_db.purchaseReturnItems, _db.purchaseItems, _db.purchaseReturns},
        ).get();
        if (retRows.isNotEmpty) purchaseReturnedQty = retRows.first.read<int>('ret_qty');
      }

      final remainingValueCents = currentStock * costCents;
      // Profit = (netSold * salePrice) - (netSold * costPrice)
      final netSold = soldQty - saleReturnedQty;
      final profitCents = netSold > 0 ? (netSold * priceCents) - (netSold * costCents) : 0;

      uniqueProductIds.add(productId);
      totalPurchased += purchasedQty;
      totalSold += soldQty;
      totalSaleReturned += saleReturnedQty;
      totalPurchaseReturned += purchaseReturnedQty;
      totalRemaining += currentStock;
      totalRemainingValue += remainingValueCents;
      totalProfit += profitCents;

      products.add(SupplierStocktakeProductItem(
        productId: productId,
        productName: row.read<String>('product_name'),
        sku: row.readNullable<String>('product_sku'),
        variantId: variantId ?? 0,
        colorName: row.readNullable<String>('color_name'),
        sizeName: row.readNullable<String>('size_name'),
        categoryName: row.readNullable<String>('category_name'),
        purchasedQuantity: purchasedQty,
        soldQuantity: soldQty,
        saleReturnedQuantity: saleReturnedQty,
        purchaseReturnedQuantity: purchaseReturnedQty,
        remainingQuantity: currentStock,
        costCents: costCents,
        priceCents: priceCents,
        remainingValueCents: remainingValueCents,
        profitCents: profitCents,
      ));
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
