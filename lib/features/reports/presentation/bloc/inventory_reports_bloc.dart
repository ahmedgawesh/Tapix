import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class InventoryReportsEvent extends RealtimeEvent {
  const InventoryReportsEvent();
}

class InventoryReportsDateRangeChanged extends InventoryReportsEvent {
  final ReportDateRange dateRange;
  const InventoryReportsDateRangeChanged(this.dateRange);
}

class InventoryReportsSortChanged extends InventoryReportsEvent {
  final StockValuationSort sort;
  const InventoryReportsSortChanged(this.sort);
}

class InventoryReportsPriceTypeChanged extends InventoryReportsEvent {
  final PriceDisplayType priceType;
  const InventoryReportsPriceTypeChanged(this.priceType);
}

// ==================== ENUMS ====================

enum StockValuationSort { nameAsc, nameDesc, valueDesc, valueAsc, stockDesc, stockAsc }

enum PriceDisplayType { cost, sale, wholesale }

// ==================== DATA MODELS ====================

class StockValuationItem {
  final int productId;
  final String productName;
  final String? sku;
  final String? categoryName;
  final String? colorName;
  final String? sizeName;
  final int variantCount;
  final int totalStock;
  final int costCents;
  final int priceCents;
  final int wholesalePriceCents;
  final int valuationCents;

  const StockValuationItem({
    required this.productId,
    required this.productName,
    this.sku,
    this.categoryName,
    this.colorName,
    this.sizeName,
    required this.variantCount,
    required this.totalStock,
    required this.costCents,
    required this.priceCents,
    required this.wholesalePriceCents,
    required this.valuationCents,
  });

  int priceByType(PriceDisplayType type) {
    switch (type) {
      case PriceDisplayType.cost:
        return costCents;
      case PriceDisplayType.sale:
        return priceCents;
      case PriceDisplayType.wholesale:
        return wholesalePriceCents;
    }
  }

  int valuationByType(PriceDisplayType type) {
    return totalStock * priceByType(type);
  }

  String get variantLabel {
    final parts = <String>[];
    if (colorName != null) parts.add(colorName!);
    if (sizeName != null) parts.add(sizeName!);
    return parts.join(' / ');
  }
}

class LowStockItem {
  final int productId;
  final String productName;
  final String? sku;
  final String? categoryName;
  final String? colorName;
  final String? sizeName;
  final int currentStock;
  final int reorderLevel;
  final int deficit;

  const LowStockItem({
    required this.productId,
    required this.productName,
    this.sku,
    this.categoryName,
    this.colorName,
    this.sizeName,
    required this.currentStock,
    required this.reorderLevel,
    required this.deficit,
  });

  String get variantLabel {
    final parts = <String>[];
    if (colorName != null) parts.add(colorName!);
    if (sizeName != null) parts.add(sizeName!);
    return parts.join(' / ');
  }
}

class ProductMovementItem {
  final int productId;
  final String productName;
  final String? sku;
  final String? colorName;
  final String? sizeName;
  final int purchasedQty;
  final int soldQty;
  final int returnedQty;
  final int netMovement;

  const ProductMovementItem({
    required this.productId,
    required this.productName,
    this.sku,
    this.colorName,
    this.sizeName,
    required this.purchasedQty,
    required this.soldQty,
    required this.returnedQty,
    required this.netMovement,
  });

  String get variantLabel {
    final parts = <String>[];
    if (colorName != null) parts.add(colorName!);
    if (sizeName != null) parts.add(sizeName!);
    return parts.join(' / ');
  }
}

class InventoryReportsData {
  final List<StockValuationItem> stockValuation;
  final int totalValuationCents;
  final int totalStockUnits;
  final List<LowStockItem> lowStockItems;
  final List<ProductMovementItem> productMovement;
  final ReportDateRange dateRange;
  final StockValuationSort sort;
  final PriceDisplayType priceType;

  const InventoryReportsData({
    this.stockValuation = const [],
    this.totalValuationCents = 0,
    this.totalStockUnits = 0,
    this.lowStockItems = const [],
    this.productMovement = const [],
    required this.dateRange,
    this.sort = StockValuationSort.valueDesc,
    this.priceType = PriceDisplayType.cost,
  });

  InventoryReportsData copyWith({
    List<StockValuationItem>? stockValuation,
    int? totalValuationCents,
    int? totalStockUnits,
    List<LowStockItem>? lowStockItems,
    List<ProductMovementItem>? productMovement,
    ReportDateRange? dateRange,
    StockValuationSort? sort,
    PriceDisplayType? priceType,
  }) {
    return InventoryReportsData(
      stockValuation: stockValuation ?? this.stockValuation,
      totalValuationCents: totalValuationCents ?? this.totalValuationCents,
      totalStockUnits: totalStockUnits ?? this.totalStockUnits,
      lowStockItems: lowStockItems ?? this.lowStockItems,
      productMovement: productMovement ?? this.productMovement,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
      priceType: priceType ?? this.priceType,
    );
  }
}

// ==================== BLOC ====================

class InventoryReportsBloc
    extends RealtimeBloc<InventoryReportsData, InventoryReportsEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  StockValuationSort _sort = StockValuationSort.valueDesc;
  PriceDisplayType _priceType = PriceDisplayType.cost;

  InventoryReportsBloc(this._db) : super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<InventoryReportsData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<InventoryReportsDateRangeChanged>(_onDateRangeChanged);
    on<InventoryReportsSortChanged>(_onSortChanged);
    on<InventoryReportsPriceTypeChanged>(_onPriceTypeChanged);
  }

  Stream<InventoryReportsData> _buildCombinedStream() {
    // Watch product_variants for real-time stock changes
    // This triggers whenever any variant is inserted/updated/deleted
    return _db.select(_db.productVariants).watch().asyncMap((_) async {
      final stockValuation = await _loadStockValuation();
      final lowStock = await _loadLowStock();
      final movement = await _loadProductMovement();

      int totalVal = 0;
      int totalUnits = 0;
      for (final item in stockValuation) {
        totalVal += item.valuationCents;
        totalUnits += item.totalStock;
      }

      final sorted = _applySortToValuation(stockValuation, _sort);

      return InventoryReportsData(
        stockValuation: sorted,
        totalValuationCents: totalVal,
        totalStockUnits: totalUnits,
        lowStockItems: lowStock,
        productMovement: movement,
        dateRange: _dateRange,
        sort: _sort,
        priceType: _priceType,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    InventoryReportsDateRangeChanged event,
    Emitter<RealtimeState<InventoryReportsData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSortChanged(
    InventoryReportsSortChanged event,
    Emitter<RealtimeState<InventoryReportsData>> emit,
  ) {
    _sort = event.sort;
    final current = currentData;
    if (current != null) {
      final sorted = _applySortToValuation(current.stockValuation, event.sort);
      emit(RealtimeSuccess<InventoryReportsData>(
        data: current.copyWith(
          stockValuation: sorted,
          sort: event.sort,
        ),
      ));
    }
  }

  void _onPriceTypeChanged(
    InventoryReportsPriceTypeChanged event,
    Emitter<RealtimeState<InventoryReportsData>> emit,
  ) {
    _priceType = event.priceType;
    final current = currentData;
    if (current != null) {
      emit(RealtimeSuccess<InventoryReportsData>(
        data: current.copyWith(priceType: event.priceType),
      ));
    }
  }

  List<StockValuationItem> _applySortToValuation(
    List<StockValuationItem> items,
    StockValuationSort sort,
  ) {
    final list = List<StockValuationItem>.from(items);
    switch (sort) {
      case StockValuationSort.nameAsc:
        list.sort((a, b) => a.productName.compareTo(b.productName));
      case StockValuationSort.nameDesc:
        list.sort((a, b) => b.productName.compareTo(a.productName));
      case StockValuationSort.valueDesc:
        list.sort((a, b) => b.valuationCents.compareTo(a.valuationCents));
      case StockValuationSort.valueAsc:
        list.sort((a, b) => a.valuationCents.compareTo(b.valuationCents));
      case StockValuationSort.stockDesc:
        list.sort((a, b) => b.totalStock.compareTo(a.totalStock));
      case StockValuationSort.stockAsc:
        list.sort((a, b) => a.totalStock.compareTo(b.totalStock));
    }
    return list;
  }

  Future<List<StockValuationItem>> _loadStockValuation() async {
    final rows = await _db.customSelect(
      '''
      SELECT 
        p.id AS product_id,
        p.name AS product_name,
        COALESCE(v.sku, p.sku) AS variant_sku,
        c.name AS category_name,
        pc.name AS color_name,
        sz.name AS size_name,
        1 AS variant_count,
        COALESCE(v.stock_quantity, p.stock_quantity) AS total_stock,
        COALESCE(v.cost_cents, p.cost_cents) AS cost_cents,
        COALESCE(v.price_cents, p.price_cents) AS price_cents,
        COALESCE(v.wholesale_price_cents, p.wholesale_price_cents, 0) AS wholesale_price_cents,
        COALESCE(v.stock_quantity * v.cost_cents, p.stock_quantity * p.cost_cents) AS valuation_cents
      FROM products p
      LEFT JOIN product_variants v ON v.product_id = p.id AND v.is_active = 1
      LEFT JOIN product_categories c ON c.id = p.category_id
      LEFT JOIN product_colors pc ON pc.id = v.color_id
      LEFT JOIN sizes sz ON sz.id = v.size_id
      WHERE p.is_active = 1
      ORDER BY valuation_cents DESC
      ''',
      readsFrom: {_db.products, _db.productVariants, _db.productCategories, _db.productColors, _db.sizes},
    ).get();

    return rows.map((row) {
      return StockValuationItem(
        productId: row.read<int>('product_id'),
        productName: row.read<String>('product_name'),
        sku: row.readNullable<String>('variant_sku'),
        categoryName: row.readNullable<String>('category_name'),
        colorName: row.readNullable<String>('color_name'),
        sizeName: row.readNullable<String>('size_name'),
        variantCount: row.read<int>('variant_count'),
        totalStock: row.read<int>('total_stock'),
        costCents: row.read<int>('cost_cents'),
        priceCents: row.read<int>('price_cents'),
        wholesalePriceCents: row.read<int>('wholesale_price_cents'),
        valuationCents: row.read<int>('valuation_cents'),
      );
    }).toList();
  }

  Future<List<LowStockItem>> _loadLowStock() async {
    final rows = await _db.customSelect(
      '''
      SELECT 
        p.id AS product_id,
        p.name AS product_name,
        COALESCE(v.sku, p.sku) AS variant_sku,
        c.name AS category_name,
        pc.name AS color_name,
        sz.name AS size_name,
        COALESCE(SUM(v.stock_quantity), p.stock_quantity) AS current_stock,
        p.min_quantity AS reorder_level
      FROM products p
      LEFT JOIN product_variants v ON v.product_id = p.id AND v.is_active = 1
      LEFT JOIN product_categories c ON c.id = p.category_id
      LEFT JOIN product_colors pc ON pc.id = v.color_id
      LEFT JOIN sizes sz ON sz.id = v.size_id
      WHERE p.is_active = 1
        AND p.track_inventory = 1
        AND p.min_quantity > 0
      GROUP BY p.id
      HAVING current_stock <= reorder_level
      ORDER BY (reorder_level - current_stock) DESC
      ''',
      readsFrom: {_db.products, _db.productVariants, _db.productCategories, _db.productColors, _db.sizes},
    ).get();

    return rows.map((row) {
      final currentStock = row.read<int>('current_stock');
      final reorderLevel = row.read<int>('reorder_level');
      return LowStockItem(
        productId: row.read<int>('product_id'),
        productName: row.read<String>('product_name'),
        sku: row.readNullable<String>('variant_sku'),
        categoryName: row.readNullable<String>('category_name'),
        colorName: row.readNullable<String>('color_name'),
        sizeName: row.readNullable<String>('size_name'),
        currentStock: currentStock,
        reorderLevel: reorderLevel,
        deficit: reorderLevel - currentStock,
      );
    }).toList();
  }

  Future<List<ProductMovementItem>> _loadProductMovement() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    final rows = await _db.customSelect(
      '''
      SELECT 
        p.id AS product_id,
        p.name AS product_name,
        p.sku AS product_sku,
        pc.name AS color_name,
        sz.name AS size_name,
        COALESCE(purchased.qty, 0) AS purchased_qty,
        COALESCE(sold.qty, 0) AS sold_qty,
        COALESCE(returned_s.qty, 0) + COALESCE(returned_p.qty, 0) AS returned_qty
      FROM products p
      LEFT JOIN product_variants pv ON pv.product_id = p.id AND pv.is_active = 1
      LEFT JOIN product_colors pc ON pc.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      LEFT JOIN (
        SELECT pi.product_id, SUM(pi.quantity) AS qty
        FROM purchase_items pi
        INNER JOIN purchases pu ON pu.id = pi.purchase_id AND pu.status != 'voided'
        WHERE pu.purchase_date >= ? AND pu.purchase_date <= ?
        GROUP BY pi.product_id
      ) purchased ON purchased.product_id = p.id
      LEFT JOIN (
        SELECT si.product_id, SUM(si.quantity) AS qty
        FROM sale_items si
        INNER JOIN sales s ON s.id = si.sale_id AND s.status != 'voided'
        WHERE s.sale_date >= ? AND s.sale_date <= ?
        GROUP BY si.product_id
      ) sold ON sold.product_id = p.id
      LEFT JOIN (
        SELECT si.product_id, SUM(sri.quantity) AS qty
        FROM sale_return_items sri
        INNER JOIN sale_items si ON si.id = sri.sale_item_id
        INNER JOIN sale_returns sr ON sr.id = sri.return_id AND sr.status = 'posted'
        WHERE sr.return_date >= ? AND sr.return_date <= ?
        GROUP BY si.product_id
      ) returned_s ON returned_s.product_id = p.id
      LEFT JOIN (
        SELECT pi.product_id, SUM(pri.quantity) AS qty
        FROM purchase_return_items pri
        INNER JOIN purchase_items pi ON pi.id = pri.purchase_item_id
        INNER JOIN purchase_returns pr ON pr.id = pri.return_id AND pr.status = 'posted'
        WHERE pr.return_date >= ? AND pr.return_date <= ?
        GROUP BY pi.product_id
      ) returned_p ON returned_p.product_id = p.id
      WHERE p.is_active = 1
        AND (COALESCE(purchased.qty, 0) + COALESCE(sold.qty, 0) + 
             COALESCE(returned_s.qty, 0) + COALESCE(returned_p.qty, 0)) > 0
      ORDER BY (COALESCE(sold.qty, 0)) DESC
      ''',
      variables: [
        Variable<String>(startIso), Variable<String>(endIso),
        Variable<String>(startIso), Variable<String>(endIso),
        Variable<String>(startIso), Variable<String>(endIso),
        Variable<String>(startIso), Variable<String>(endIso),
      ],
      readsFrom: {
        _db.products,
        _db.productVariants,
        _db.productColors,
        _db.sizes,
        _db.purchaseItems,
        _db.purchases,
        _db.saleItems,
        _db.sales,
        _db.saleReturnItems,
        _db.saleReturns,
        _db.purchaseReturnItems,
        _db.purchaseReturns,
      },
    ).get();

    return rows.map((row) {
      final purchased = row.read<int>('purchased_qty');
      final sold = row.read<int>('sold_qty');
      final returned = row.read<int>('returned_qty');
      return ProductMovementItem(
        productId: row.read<int>('product_id'),
        productName: row.read<String>('product_name'),
        sku: row.readNullable<String>('product_sku'),
        colorName: row.readNullable<String>('color_name'),
        sizeName: row.readNullable<String>('size_name'),
        purchasedQty: purchased,
        soldQty: sold,
        returnedQty: returned,
        netMovement: purchased - sold + returned,
      );
    }).toList();
  }
}
