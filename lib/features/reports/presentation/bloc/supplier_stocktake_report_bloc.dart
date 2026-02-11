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
}

// ==================== DATA MODELS ====================

class SupplierStocktakeProductItem {
  final int productId;
  final String productName;
  final String? sku;
  final int variantId;
  final String? colorName;
  final String? sizeName;
  final int purchasedQuantity;
  final int soldQuantity;
  final int remainingQuantity;
  final int costCents;
  final int remainingValueCents;

  const SupplierStocktakeProductItem({
    required this.productId,
    required this.productName,
    this.sku,
    required this.variantId,
    this.colorName,
    this.sizeName,
    required this.purchasedQuantity,
    required this.soldQuantity,
    required this.remainingQuantity,
    required this.costCents,
    required this.remainingValueCents,
  });

  String get variantLabel {
    final parts = <String>[];
    if (colorName != null && colorName!.isNotEmpty) parts.add(colorName!);
    if (sizeName != null && sizeName!.isNotEmpty) parts.add(sizeName!);
    return parts.join(' / ');
  }
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
  final int totalRemainingQuantity;
  final int totalRemainingValueCents;
  final int totalProducts;
  final int totalVariants;
  final ReportDateRange dateRange;
  final SupplierStocktakeSortType sort;

  const SupplierStocktakeReportData({
    this.supplierId,
    this.supplierName,
    this.supplierPhone,
    this.suppliers = const [],
    this.products = const [],
    this.totalPurchasedQuantity = 0,
    this.totalSoldQuantity = 0,
    this.totalRemainingQuantity = 0,
    this.totalRemainingValueCents = 0,
    this.totalProducts = 0,
    this.totalVariants = 0,
    required this.dateRange,
    this.sort = SupplierStocktakeSortType.valueDesc,
  });

  SupplierStocktakeReportData copyWith({
    int? supplierId,
    String? supplierName,
    String? supplierPhone,
    List<SupplierOption>? suppliers,
    List<SupplierStocktakeProductItem>? products,
    int? totalPurchasedQuantity,
    int? totalSoldQuantity,
    int? totalRemainingQuantity,
    int? totalRemainingValueCents,
    int? totalProducts,
    int? totalVariants,
    ReportDateRange? dateRange,
    SupplierStocktakeSortType? sort,
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
      totalRemainingQuantity:
          totalRemainingQuantity ?? this.totalRemainingQuantity,
      totalRemainingValueCents:
          totalRemainingValueCents ?? this.totalRemainingValueCents,
      totalProducts: totalProducts ?? this.totalProducts,
      totalVariants: totalVariants ?? this.totalVariants,
      dateRange: dateRange ?? this.dateRange,
      sort: sort ?? this.sort,
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
    }
    return list;
  }

  /// Loads supplier stocktake data:
  /// 1. All suppliers for the dropdown
  /// 2. If a supplier is selected: products linked via purchase invoices in date range
  ///    with purchased qty, sold qty, remaining stock, and stock value
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

    if (_supplierId == null) {
      return SupplierStocktakeReportData(
        dateRange: _dateRange,
        suppliers: suppliers,
      );
    }

    // Load supplier info
    final supplierInfoRows = await _db.customSelect(
      '''
      SELECT s.name, s.phone
      FROM suppliers s
      WHERE s.id = ?
      ''',
      variables: [Variable.withInt(_supplierId!)],
      readsFrom: {_db.suppliers},
    ).get();

    if (supplierInfoRows.isEmpty) {
      return SupplierStocktakeReportData(
        dateRange: _dateRange,
        suppliers: suppliers,
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

    // Get all product variants purchased from this supplier in the date range
    // via purchase_items → purchases (where supplier_id matches and date in range)
    final purchasedRows = await _db.customSelect(
      '''
      SELECT 
        p.id AS product_id,
        p.name AS product_name,
        p.sku AS product_sku,
        COALESCE(pi.variant_id, pv_default.id) AS variant_id,
        pc.name AS color_name,
        sz.name AS size_name,
        SUM(pi.quantity) AS purchased_qty,
        COALESCE(pi.variant_id, pv_default.id) AS resolved_variant_id,
        COALESCE(
          CASE WHEN pi.variant_id IS NOT NULL THEN pv.cost_cents ELSE pv_default.cost_cents END,
          p.cost_cents
        ) AS cost_cents,
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
      LEFT JOIN product_colors pc ON COALESCE(pv.color_id, pv_default.color_id) = pc.id
      LEFT JOIN sizes sz ON COALESCE(pv.size_id, pv_default.size_id) = sz.id
      WHERE pu.supplier_id = ?
        AND pu.status = 'posted'
        AND pu.purchase_date >= ?
        AND pu.purchase_date <= ?
      GROUP BY p.id, COALESCE(pi.variant_id, pv_default.id)
      ORDER BY p.name, pc.name, sz.name
      ''',
      variables: [
        Variable.withInt(_supplierId!),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {
        _db.purchaseItems,
        _db.purchases,
        _db.products,
        _db.productVariants,
        _db.productColors,
        _db.sizes,
      },
    ).get();

    // For each purchased product/variant, get sold qty in the same date range
    final products = <SupplierStocktakeProductItem>[];
    int totalPurchased = 0;
    int totalSold = 0;
    int totalRemaining = 0;
    int totalRemainingValue = 0;
    final uniqueProductIds = <int>{};

    for (final row in purchasedRows) {
      final productId = row.read<int>('product_id');
      final variantId = row.readNullable<int>('variant_id');
      final purchasedQty = row.read<int>('purchased_qty');
      final costCents = row.read<int>('cost_cents');
      final currentStock = row.read<int>('current_stock');

      // Get sold quantity for this product/variant in the date range
      int soldQty = 0;
      if (variantId != null) {
        final soldRows = await _db.customSelect(
          '''
          SELECT COALESCE(SUM(si.quantity), 0) AS sold_qty
          FROM sale_items si
          JOIN sales sa ON si.sale_id = sa.id
          WHERE si.product_id = ?
            AND si.variant_id = ?
            AND sa.status IN ('completed', 'posted')
            AND sa.sale_date >= ?
            AND sa.sale_date <= ?
          ''',
          variables: [
            Variable.withInt(productId),
            Variable.withInt(variantId),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {_db.saleItems, _db.sales},
        ).get();
        if (soldRows.isNotEmpty) {
          soldQty = soldRows.first.read<int>('sold_qty');
        }
      } else {
        final soldRows = await _db.customSelect(
          '''
          SELECT COALESCE(SUM(si.quantity), 0) AS sold_qty
          FROM sale_items si
          JOIN sales sa ON si.sale_id = sa.id
          WHERE si.product_id = ?
            AND sa.status IN ('completed', 'posted')
            AND sa.sale_date >= ?
            AND sa.sale_date <= ?
          ''',
          variables: [
            Variable.withInt(productId),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {_db.saleItems, _db.sales},
        ).get();
        if (soldRows.isNotEmpty) {
          soldQty = soldRows.first.read<int>('sold_qty');
        }
      }

      // remaining = current stock (real-time from DB)
      final remainingValueCents = currentStock * costCents;

      uniqueProductIds.add(productId);
      totalPurchased += purchasedQty;
      totalSold += soldQty;
      totalRemaining += currentStock;
      totalRemainingValue += remainingValueCents;

      products.add(SupplierStocktakeProductItem(
        productId: productId,
        productName: row.read<String>('product_name'),
        sku: row.readNullable<String>('product_sku'),
        variantId: variantId ?? 0,
        colorName: row.readNullable<String>('color_name'),
        sizeName: row.readNullable<String>('size_name'),
        purchasedQuantity: purchasedQty,
        soldQuantity: soldQty,
        remainingQuantity: currentStock,
        costCents: costCents,
        remainingValueCents: remainingValueCents,
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
      totalRemainingQuantity: totalRemaining,
      totalRemainingValueCents: totalRemainingValue,
      totalProducts: uniqueProductIds.length,
      totalVariants: products.length,
      dateRange: _dateRange,
      sort: _sort,
    );
  }
}
