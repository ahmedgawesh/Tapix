import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class CategoryMovementEvent extends RealtimeEvent {
  const CategoryMovementEvent();
}

class CategoryMovementDateRangeChanged extends CategoryMovementEvent {
  final ReportDateRange dateRange;
  const CategoryMovementDateRangeChanged(this.dateRange);
}

class CategoryMovementSearchChanged extends CategoryMovementEvent {
  final String query;
  const CategoryMovementSearchChanged(this.query);
}

class CategoryMovementCategorySelected extends CategoryMovementEvent {
  final int categoryId;
  const CategoryMovementCategorySelected(this.categoryId);
}

class CategoryMovementCategoryCleared extends CategoryMovementEvent {
  const CategoryMovementCategoryCleared();
}

class CategoryMovementSortChanged extends CategoryMovementEvent {
  final CategoryMovementSort sort;
  const CategoryMovementSortChanged(this.sort);
}

// ==================== ENUMS ====================

enum CatMovementType { purchase, sale, saleReturn, purchaseReturn }

enum CategoryMovementSort { name, mostActive, netMovement }

// ==================== DATA MODELS ====================

class CatMovementEntry {
  final CatMovementType type;
  final DateTime date;
  final String reference;
  final int quantity;
  final int totalCents;
  final String? counterpartyName;
  final String productName;
  final bool hasVariants;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;
  final String? variantSku;

  const CatMovementEntry({
    required this.type,
    required this.date,
    required this.reference,
    required this.quantity,
    required this.totalCents,
    required this.productName,
    this.counterpartyName,
    this.hasVariants = false,
    this.colorName,
    this.colorHex,
    this.sizeName,
    this.variantSku,
  });

  String get variantLabel {
    final parts = <String>[];
    if (colorName != null && colorName!.isNotEmpty) parts.add(colorName!);
    if (sizeName != null && sizeName!.isNotEmpty) parts.add(sizeName!);
    if (parts.isEmpty && variantSku != null) return variantSku!;
    return parts.isEmpty ? '' : parts.join(' / ');
  }
}

class CategorySearchResult {
  final int categoryId;
  final String name;
  final int productCount;

  const CategorySearchResult({
    required this.categoryId,
    required this.name,
    this.productCount = 0,
  });
}

class CategoryProductSummary {
  final int productId;
  final String productName;
  final bool hasVariants;
  final int purchasedQty;
  final int soldQty;
  final int saleReturnedQty;
  final int purchaseReturnedQty;
  final int purchaseCents;
  final int salesCents;
  final int saleReturnCents;
  final int purchaseReturnCents;
  final List<CatVariantSummary> variants;

  const CategoryProductSummary({
    required this.productId,
    required this.productName,
    this.hasVariants = false,
    this.purchasedQty = 0,
    this.soldQty = 0,
    this.saleReturnedQty = 0,
    this.purchaseReturnedQty = 0,
    this.purchaseCents = 0,
    this.salesCents = 0,
    this.saleReturnCents = 0,
    this.purchaseReturnCents = 0,
    this.variants = const [],
  });

  int get netQty => purchasedQty - soldQty + saleReturnedQty - purchaseReturnedQty;
  int get totalActivity => purchasedQty + soldQty + saleReturnedQty + purchaseReturnedQty;
}

class CatVariantSummary {
  final String label;
  final String? colorHex;
  final int purchasedQty;
  final int soldQty;
  final int saleReturnedQty;
  final int purchaseReturnedQty;

  const CatVariantSummary({
    required this.label,
    this.colorHex,
    this.purchasedQty = 0,
    this.soldQty = 0,
    this.saleReturnedQty = 0,
    this.purchaseReturnedQty = 0,
  });

  int get netQty => purchasedQty - soldQty + saleReturnedQty - purchaseReturnedQty;
}

class CategoryMovementTotals {
  final int totalPurchased;
  final int totalSold;
  final int totalSaleReturned;
  final int totalPurchaseReturned;
  final int totalPurchaseCents;
  final int totalSalesCents;
  final int totalSaleReturnCents;
  final int totalPurchaseReturnCents;
  final int productCount;

  const CategoryMovementTotals({
    this.totalPurchased = 0,
    this.totalSold = 0,
    this.totalSaleReturned = 0,
    this.totalPurchaseReturned = 0,
    this.totalPurchaseCents = 0,
    this.totalSalesCents = 0,
    this.totalSaleReturnCents = 0,
    this.totalPurchaseReturnCents = 0,
    this.productCount = 0,
  });

  int get netQuantity => totalPurchased - totalSold + totalSaleReturned - totalPurchaseReturned;
}

class CategoryMovementData {
  final ReportDateRange dateRange;
  final String searchQuery;
  final int? selectedCategoryId;
  final String? selectedCategoryName;
  final CategoryMovementSort sort;
  final List<CategorySearchResult> searchResults;
  final List<CategoryProductSummary> productSummaries;
  final List<CatMovementEntry> movements;
  final CategoryMovementTotals totals;

  const CategoryMovementData({
    required this.dateRange,
    this.searchQuery = '',
    this.selectedCategoryId,
    this.selectedCategoryName,
    this.sort = CategoryMovementSort.mostActive,
    this.searchResults = const [],
    this.productSummaries = const [],
    this.movements = const [],
    this.totals = const CategoryMovementTotals(),
  });

  CategoryMovementData copyWith({
    ReportDateRange? dateRange,
    String? searchQuery,
    int? selectedCategoryId,
    String? selectedCategoryName,
    CategoryMovementSort? sort,
    List<CategorySearchResult>? searchResults,
    List<CategoryProductSummary>? productSummaries,
    List<CatMovementEntry>? movements,
    CategoryMovementTotals? totals,
    bool clearCategory = false,
  }) {
    return CategoryMovementData(
      dateRange: dateRange ?? this.dateRange,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategoryId: clearCategory ? null : (selectedCategoryId ?? this.selectedCategoryId),
      selectedCategoryName: clearCategory ? null : (selectedCategoryName ?? this.selectedCategoryName),
      sort: sort ?? this.sort,
      searchResults: searchResults ?? this.searchResults,
      productSummaries: productSummaries ?? this.productSummaries,
      movements: movements ?? this.movements,
      totals: totals ?? this.totals,
    );
  }
}

// ==================== BLOC ====================

class CategoryMovementBloc
    extends RealtimeBloc<CategoryMovementData, CategoryMovementEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  String _searchQuery = '';
  int? _selectedCategoryId;
  CategoryMovementSort _sort = CategoryMovementSort.mostActive;

  CategoryMovementBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  @override
  Stream<CategoryMovementData> get dataStream {
    return _db.select(_db.sales).watch().asyncMap((_) => _loadData());
  }

  @override
  void registerEventHandlers() {
    on<CategoryMovementDateRangeChanged>(_onDateRangeChanged);
    on<CategoryMovementSearchChanged>(_onSearchChanged);
    on<CategoryMovementCategorySelected>(_onCategorySelected);
    on<CategoryMovementCategoryCleared>(_onCategoryCleared);
    on<CategoryMovementSortChanged>(_onSortChanged);
  }

  Future<void> _onDateRangeChanged(
    CategoryMovementDateRangeChanged event,
    Emitter<RealtimeState<CategoryMovementData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onSearchChanged(
    CategoryMovementSearchChanged event,
    Emitter<RealtimeState<CategoryMovementData>> emit,
  ) async {
    _searchQuery = event.query;
    if (event.query.trim().isEmpty) {
      final current = currentData;
      if (current != null) {
        emit(RealtimeSuccess(data: current.copyWith(
          searchQuery: '',
          searchResults: [],
        )));
      }
      return;
    }

    final results = await _searchCategories(event.query.trim());
    final current = currentData;
    if (current != null) {
      emit(RealtimeSuccess(data: current.copyWith(
        searchQuery: event.query,
        searchResults: results,
      )));
    }
  }

  Future<void> _onCategorySelected(
    CategoryMovementCategorySelected event,
    Emitter<RealtimeState<CategoryMovementData>> emit,
  ) async {
    _selectedCategoryId = event.categoryId;
    _searchQuery = '';
    refresh();
  }

  Future<void> _onCategoryCleared(
    CategoryMovementCategoryCleared event,
    Emitter<RealtimeState<CategoryMovementData>> emit,
  ) async {
    _selectedCategoryId = null;
    _searchQuery = '';
    refresh();
  }

  Future<void> _onSortChanged(
    CategoryMovementSortChanged event,
    Emitter<RealtimeState<CategoryMovementData>> emit,
  ) async {
    _sort = event.sort;
    refresh();
  }

  Future<CategoryMovementData> _loadData() async {
    if (_selectedCategoryId == null) {
      return CategoryMovementData(
        dateRange: _dateRange,
        searchQuery: _searchQuery,
        sort: _sort,
      );
    }

    final categoryId = _selectedCategoryId!;
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    // Get category name
    final catRow = await (_db.select(_db.productCategories)
          ..where((c) => c.id.equals(categoryId)))
        .getSingleOrNull();
    final categoryName = catRow?.name ?? '';

    // Get all active products in this category
    final productRows = await _db.customSelect(
      '''
      SELECT p.id, p.name, p.has_variants
      FROM products p
      WHERE p.category_id = ? AND p.is_active = 1
      ORDER BY p.name
      ''',
      variables: [Variable.withInt(categoryId)],
      readsFrom: {_db.products},
    ).get();

    final allMovements = <CatMovementEntry>[];
    final productSummaryMap = <int, _ProductAccumulator>{};

    // Initialize accumulators for all products
    for (final pRow in productRows) {
      final pid = pRow.read<int>('id');
      productSummaryMap[pid] = _ProductAccumulator(
        productId: pid,
        productName: pRow.read<String>('name'),
        hasVariants: pRow.read<bool>('has_variants'),
      );
    }

    if (productRows.isEmpty) {
      return CategoryMovementData(
        dateRange: _dateRange,
        searchQuery: _searchQuery,
        selectedCategoryId: categoryId,
        selectedCategoryName: categoryName,
        sort: _sort,
        productSummaries: [],
        movements: [],
        totals: const CategoryMovementTotals(),
      );
    }

    final productIds = productRows.map((r) => r.read<int>('id')).toList();
    final placeholders = productIds.map((_) => '?').join(',');

    // ── Purchases ──
    final purchaseRows = await _db.customSelect(
      '''
      SELECT 
        pu.purchase_date AS dt,
        pu.purchase_number AS ref,
        pi.quantity AS qty,
        pi.total_cents AS total,
        pi.product_id AS pid,
        sup.name AS counterparty,
        p.name AS product_name,
        p.has_variants AS has_variants,
        pco.name AS color_name,
        pco.hex_code AS color_hex,
        sz.name AS size_name,
        pv.sku AS variant_sku,
        pi.variant_id AS vid
      FROM purchase_items pi
      INNER JOIN purchases pu ON pu.id = pi.purchase_id
      INNER JOIN products p ON p.id = pi.product_id
      LEFT JOIN suppliers sup ON sup.id = pu.supplier_id
      LEFT JOIN product_variants pv ON pv.id = pi.variant_id
      LEFT JOIN product_colors pco ON pco.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE pi.product_id IN ($placeholders)
        AND pu.status != 'voided'
        AND pu.purchase_date >= ? AND pu.purchase_date <= ?
      ORDER BY pu.purchase_date DESC
      ''',
      variables: [
        ...productIds.map(Variable.withInt),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.purchaseItems, _db.purchases, _db.products, _db.suppliers, _db.productVariants, _db.productColors, _db.sizes},
    ).get();

    for (final row in purchaseRows) {
      final pid = row.read<int>('pid');
      final entry = CatMovementEntry(
        type: CatMovementType.purchase,
        date: DateTime.parse(row.read<String>('dt')),
        reference: row.read<String>('ref'),
        quantity: row.read<int>('qty'),
        totalCents: row.read<int>('total'),
        productName: row.read<String>('product_name'),
        counterpartyName: row.readNullable<String>('counterparty'),
        hasVariants: row.read<bool>('has_variants'),
        colorName: row.readNullable<String>('color_name'),
        colorHex: row.readNullable<String>('color_hex'),
        sizeName: row.readNullable<String>('size_name'),
        variantSku: row.readNullable<String>('variant_sku'),
      );
      allMovements.add(entry);
      productSummaryMap[pid]?.addEntry(entry);
    }

    // ── Sales ──
    final saleRows = await _db.customSelect(
      '''
      SELECT 
        s.sale_date AS dt,
        s.invoice_number AS ref,
        si.quantity AS qty,
        si.total_cents AS total,
        si.product_id AS pid,
        c.name AS counterparty,
        p.name AS product_name,
        p.has_variants AS has_variants,
        pco.name AS color_name,
        pco.hex_code AS color_hex,
        sz.name AS size_name,
        pv.sku AS variant_sku,
        si.variant_id AS vid
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      INNER JOIN products p ON p.id = si.product_id
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN product_variants pv ON pv.id = si.variant_id
      LEFT JOIN product_colors pco ON pco.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE si.product_id IN ($placeholders)
        AND s.status != 'voided'
        AND s.sale_date >= ? AND s.sale_date <= ?
      ORDER BY s.sale_date DESC
      ''',
      variables: [
        ...productIds.map(Variable.withInt),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.saleItems, _db.sales, _db.products, _db.customers, _db.productVariants, _db.productColors, _db.sizes},
    ).get();

    for (final row in saleRows) {
      final pid = row.read<int>('pid');
      final entry = CatMovementEntry(
        type: CatMovementType.sale,
        date: DateTime.parse(row.read<String>('dt')),
        reference: row.read<String>('ref'),
        quantity: row.read<int>('qty'),
        totalCents: row.read<int>('total'),
        productName: row.read<String>('product_name'),
        counterpartyName: row.readNullable<String>('counterparty'),
        hasVariants: row.read<bool>('has_variants'),
        colorName: row.readNullable<String>('color_name'),
        colorHex: row.readNullable<String>('color_hex'),
        sizeName: row.readNullable<String>('size_name'),
        variantSku: row.readNullable<String>('variant_sku'),
      );
      allMovements.add(entry);
      productSummaryMap[pid]?.addEntry(entry);
    }

    // ── Sale Returns ──
    final saleReturnRows = await _db.customSelect(
      '''
      SELECT 
        sr.return_date AS dt,
        sr.return_number AS ref,
        sri.quantity AS qty,
        sri.refund_cents AS total,
        si.product_id AS pid,
        c.name AS counterparty,
        p.name AS product_name,
        p.has_variants AS has_variants,
        pco.name AS color_name,
        pco.hex_code AS color_hex,
        sz.name AS size_name,
        pv.sku AS variant_sku,
        si.variant_id AS vid
      FROM sale_return_items sri
      INNER JOIN sale_returns sr ON sr.id = sri.return_id
      INNER JOIN sale_items si ON si.id = sri.sale_item_id
      INNER JOIN sales s ON s.id = sr.sale_id
      INNER JOIN products p ON p.id = si.product_id
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN product_variants pv ON pv.id = si.variant_id
      LEFT JOIN product_colors pco ON pco.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE si.product_id IN ($placeholders)
        AND sr.status = 'posted'
        AND sr.return_date >= ? AND sr.return_date <= ?
      ORDER BY sr.return_date DESC
      ''',
      variables: [
        ...productIds.map(Variable.withInt),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.saleReturnItems, _db.saleReturns, _db.saleItems, _db.sales, _db.products, _db.customers, _db.productVariants, _db.productColors, _db.sizes},
    ).get();

    for (final row in saleReturnRows) {
      final pid = row.read<int>('pid');
      final entry = CatMovementEntry(
        type: CatMovementType.saleReturn,
        date: DateTime.parse(row.read<String>('dt')),
        reference: row.read<String>('ref'),
        quantity: row.read<int>('qty'),
        totalCents: row.read<int>('total'),
        productName: row.read<String>('product_name'),
        counterpartyName: row.readNullable<String>('counterparty'),
        hasVariants: row.read<bool>('has_variants'),
        colorName: row.readNullable<String>('color_name'),
        colorHex: row.readNullable<String>('color_hex'),
        sizeName: row.readNullable<String>('size_name'),
        variantSku: row.readNullable<String>('variant_sku'),
      );
      allMovements.add(entry);
      productSummaryMap[pid]?.addEntry(entry);
    }

    // ── Sale Adjustment Returns (unlinked) ──
    final saleAdjReturnRows = await _db.customSelect(
      '''
      SELECT 
        sra.return_date AS dt,
        sra.return_number AS ref,
        srai.quantity AS qty,
        srai.total_cents AS total,
        srai.product_id AS pid,
        c.name AS counterparty,
        p.name AS product_name,
        p.has_variants AS has_variants,
        pco.name AS color_name,
        pco.hex_code AS color_hex,
        sz.name AS size_name,
        pv.sku AS variant_sku,
        srai.variant_id AS vid
      FROM sale_return_adjustment_items srai
      INNER JOIN sale_return_adjustments sra ON sra.id = srai.return_id
      INNER JOIN products p ON p.id = srai.product_id
      LEFT JOIN customers c ON c.id = sra.customer_id
      LEFT JOIN product_variants pv ON pv.id = srai.variant_id
      LEFT JOIN product_colors pco ON pco.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE srai.product_id IN ($placeholders)
        AND sra.status = 'posted'
        AND sra.return_date >= ? AND sra.return_date <= ?
      ORDER BY sra.return_date DESC
      ''',
      variables: [
        ...productIds.map(Variable.withInt),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.saleReturnAdjustmentItems, _db.saleReturnAdjustments, _db.products, _db.customers, _db.productVariants, _db.productColors, _db.sizes},
    ).get();

    for (final row in saleAdjReturnRows) {
      final pid = row.read<int>('pid');
      final entry = CatMovementEntry(
        type: CatMovementType.saleReturn,
        date: DateTime.parse(row.read<String>('dt')),
        reference: row.read<String>('ref'),
        quantity: row.read<int>('qty'),
        totalCents: row.read<int>('total'),
        productName: row.read<String>('product_name'),
        counterpartyName: row.readNullable<String>('counterparty'),
        hasVariants: row.read<bool>('has_variants'),
        colorName: row.readNullable<String>('color_name'),
        colorHex: row.readNullable<String>('color_hex'),
        sizeName: row.readNullable<String>('size_name'),
        variantSku: row.readNullable<String>('variant_sku'),
      );
      allMovements.add(entry);
      productSummaryMap[pid]?.addEntry(entry);
    }

    // ── Purchase Returns ──
    final purchaseReturnRows = await _db.customSelect(
      '''
      SELECT 
        pr.return_date AS dt,
        pr.return_number AS ref,
        pri.quantity AS qty,
        pri.refund_cents AS total,
        pi.product_id AS pid,
        sup.name AS counterparty,
        p.name AS product_name,
        p.has_variants AS has_variants,
        pco.name AS color_name,
        pco.hex_code AS color_hex,
        sz.name AS size_name,
        pv.sku AS variant_sku,
        pi.variant_id AS vid
      FROM purchase_return_items pri
      INNER JOIN purchase_returns pr ON pr.id = pri.return_id
      INNER JOIN purchase_items pi ON pi.id = pri.purchase_item_id
      INNER JOIN purchases pu ON pu.id = pr.purchase_id
      INNER JOIN products p ON p.id = pi.product_id
      LEFT JOIN suppliers sup ON sup.id = pu.supplier_id
      LEFT JOIN product_variants pv ON pv.id = pi.variant_id
      LEFT JOIN product_colors pco ON pco.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE pi.product_id IN ($placeholders)
        AND pr.status = 'posted'
        AND pr.return_date >= ? AND pr.return_date <= ?
      ORDER BY pr.return_date DESC
      ''',
      variables: [
        ...productIds.map(Variable.withInt),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.purchaseReturnItems, _db.purchaseReturns, _db.purchaseItems, _db.purchases, _db.products, _db.suppliers, _db.productVariants, _db.productColors, _db.sizes},
    ).get();

    for (final row in purchaseReturnRows) {
      final pid = row.read<int>('pid');
      final entry = CatMovementEntry(
        type: CatMovementType.purchaseReturn,
        date: DateTime.parse(row.read<String>('dt')),
        reference: row.read<String>('ref'),
        quantity: row.read<int>('qty'),
        totalCents: row.read<int>('total'),
        productName: row.read<String>('product_name'),
        counterpartyName: row.readNullable<String>('counterparty'),
        hasVariants: row.read<bool>('has_variants'),
        colorName: row.readNullable<String>('color_name'),
        colorHex: row.readNullable<String>('color_hex'),
        sizeName: row.readNullable<String>('size_name'),
        variantSku: row.readNullable<String>('variant_sku'),
      );
      allMovements.add(entry);
      productSummaryMap[pid]?.addEntry(entry);
    }

    // ── Purchase Adjustment Returns (unlinked) ──
    final purchaseAdjReturnRows = await _db.customSelect(
      '''
      SELECT 
        pra.return_date AS dt,
        pra.return_number AS ref,
        prai.quantity AS qty,
        prai.total_cents AS total,
        prai.product_id AS pid,
        sup.name AS counterparty,
        p.name AS product_name,
        p.has_variants AS has_variants,
        pco.name AS color_name,
        pco.hex_code AS color_hex,
        sz.name AS size_name,
        pv.sku AS variant_sku,
        prai.variant_id AS vid
      FROM purchase_return_adjustment_items prai
      INNER JOIN purchase_return_adjustments pra ON pra.id = prai.return_id
      INNER JOIN products p ON p.id = prai.product_id
      LEFT JOIN suppliers sup ON sup.id = pra.supplier_id
      LEFT JOIN product_variants pv ON pv.id = prai.variant_id
      LEFT JOIN product_colors pco ON pco.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE prai.product_id IN ($placeholders)
        AND pra.status = 'posted'
        AND pra.return_date >= ? AND pra.return_date <= ?
      ORDER BY pra.return_date DESC
      ''',
      variables: [
        ...productIds.map(Variable.withInt),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.purchaseReturnAdjustmentItems, _db.purchaseReturnAdjustments, _db.products, _db.suppliers, _db.productVariants, _db.productColors, _db.sizes},
    ).get();

    for (final row in purchaseAdjReturnRows) {
      final pid = row.read<int>('pid');
      final entry = CatMovementEntry(
        type: CatMovementType.purchaseReturn,
        date: DateTime.parse(row.read<String>('dt')),
        reference: row.read<String>('ref'),
        quantity: row.read<int>('qty'),
        totalCents: row.read<int>('total'),
        productName: row.read<String>('product_name'),
        counterpartyName: row.readNullable<String>('counterparty'),
        hasVariants: row.read<bool>('has_variants'),
        colorName: row.readNullable<String>('color_name'),
        colorHex: row.readNullable<String>('color_hex'),
        sizeName: row.readNullable<String>('size_name'),
        variantSku: row.readNullable<String>('variant_sku'),
      );
      allMovements.add(entry);
      productSummaryMap[pid]?.addEntry(entry);
    }

    // Sort movements by date descending
    allMovements.sort((a, b) => b.date.compareTo(a.date));

    // Build product summaries
    final productSummaries = productSummaryMap.values
        .where((a) => a.totalActivity > 0)
        .map((a) => a.toSummary())
        .toList();

    // Sort product summaries
    switch (_sort) {
      case CategoryMovementSort.name:
        productSummaries.sort((a, b) => a.productName.compareTo(b.productName));
      case CategoryMovementSort.mostActive:
        productSummaries.sort((a, b) => b.totalActivity.compareTo(a.totalActivity));
      case CategoryMovementSort.netMovement:
        productSummaries.sort((a, b) => b.netQty.abs().compareTo(a.netQty.abs()));
    }

    // Compute totals
    int totalPurchased = 0, totalSold = 0, totalSaleReturned = 0, totalPurchaseReturned = 0;
    int totalPurchaseCents = 0, totalSalesCents = 0, totalSaleReturnCents = 0, totalPurchaseReturnCents = 0;

    for (final m in allMovements) {
      switch (m.type) {
        case CatMovementType.purchase:
          totalPurchased += m.quantity;
          totalPurchaseCents += m.totalCents;
        case CatMovementType.sale:
          totalSold += m.quantity;
          totalSalesCents += m.totalCents;
        case CatMovementType.saleReturn:
          totalSaleReturned += m.quantity;
          totalSaleReturnCents += m.totalCents;
        case CatMovementType.purchaseReturn:
          totalPurchaseReturned += m.quantity;
          totalPurchaseReturnCents += m.totalCents;
      }
    }

    return CategoryMovementData(
      dateRange: _dateRange,
      searchQuery: _searchQuery,
      selectedCategoryId: categoryId,
      selectedCategoryName: categoryName,
      sort: _sort,
      productSummaries: productSummaries,
      movements: allMovements,
      totals: CategoryMovementTotals(
        totalPurchased: totalPurchased,
        totalSold: totalSold,
        totalSaleReturned: totalSaleReturned,
        totalPurchaseReturned: totalPurchaseReturned,
        totalPurchaseCents: totalPurchaseCents,
        totalSalesCents: totalSalesCents,
        totalSaleReturnCents: totalSaleReturnCents,
        totalPurchaseReturnCents: totalPurchaseReturnCents,
        productCount: productSummaries.length,
      ),
    );
  }

  Future<List<CategorySearchResult>> _searchCategories(String query) async {
    final likeQuery = '%$query%';
    final rows = await _db.customSelect(
      '''
      SELECT 
        pc.id,
        pc.name,
        COUNT(p.id) AS product_count
      FROM product_categories pc
      LEFT JOIN products p ON p.category_id = pc.id AND p.is_active = 1
      WHERE pc.is_active = 1
        AND pc.name LIKE ?
      GROUP BY pc.id, pc.name
      ORDER BY pc.name
      LIMIT 20
      ''',
      variables: [Variable.withString(likeQuery)],
      readsFrom: {_db.productCategories, _db.products},
    ).get();

    return rows.map((row) => CategorySearchResult(
      categoryId: row.read<int>('id'),
      name: row.read<String>('name'),
      productCount: row.read<int>('product_count'),
    )).toList();
  }
}

// ==================== INTERNAL ACCUMULATOR ====================

class _ProductAccumulator {
  final int productId;
  final String productName;
  final bool hasVariants;
  int purchasedQty = 0;
  int soldQty = 0;
  int saleReturnedQty = 0;
  int purchaseReturnedQty = 0;
  int purchaseCents = 0;
  int salesCents = 0;
  int saleReturnCents = 0;
  int purchaseReturnCents = 0;
  final Map<String, _VariantAccumulator> _variants = {};

  _ProductAccumulator({
    required this.productId,
    required this.productName,
    required this.hasVariants,
  });

  int get totalActivity => purchasedQty + soldQty + saleReturnedQty + purchaseReturnedQty;

  void addEntry(CatMovementEntry entry) {
    switch (entry.type) {
      case CatMovementType.purchase:
        purchasedQty += entry.quantity;
        purchaseCents += entry.totalCents;
      case CatMovementType.sale:
        soldQty += entry.quantity;
        salesCents += entry.totalCents;
      case CatMovementType.saleReturn:
        saleReturnedQty += entry.quantity;
        saleReturnCents += entry.totalCents;
      case CatMovementType.purchaseReturn:
        purchaseReturnedQty += entry.quantity;
        purchaseReturnCents += entry.totalCents;
    }

    // Track variant-level breakdown
    if (hasVariants) {
      final vLabel = entry.variantLabel;
      final key = vLabel.isEmpty ? '—' : vLabel;
      final va = _variants.putIfAbsent(key, () => _VariantAccumulator(
        label: key,
        colorHex: entry.colorHex,
      ));
      switch (entry.type) {
        case CatMovementType.purchase:
          va.purchasedQty += entry.quantity;
        case CatMovementType.sale:
          va.soldQty += entry.quantity;
        case CatMovementType.saleReturn:
          va.saleReturnedQty += entry.quantity;
        case CatMovementType.purchaseReturn:
          va.purchaseReturnedQty += entry.quantity;
      }
    }
  }

  CategoryProductSummary toSummary() {
    return CategoryProductSummary(
      productId: productId,
      productName: productName,
      hasVariants: hasVariants,
      purchasedQty: purchasedQty,
      soldQty: soldQty,
      saleReturnedQty: saleReturnedQty,
      purchaseReturnedQty: purchaseReturnedQty,
      purchaseCents: purchaseCents,
      salesCents: salesCents,
      saleReturnCents: saleReturnCents,
      purchaseReturnCents: purchaseReturnCents,
      variants: _variants.values.map((v) => CatVariantSummary(
        label: v.label,
        colorHex: v.colorHex,
        purchasedQty: v.purchasedQty,
        soldQty: v.soldQty,
        saleReturnedQty: v.saleReturnedQty,
        purchaseReturnedQty: v.purchaseReturnedQty,
      )).toList()
        ..sort((a, b) => (b.purchasedQty + b.soldQty).compareTo(a.purchasedQty + a.soldQty)),
    );
  }
}

class _VariantAccumulator {
  final String label;
  final String? colorHex;
  int purchasedQty = 0;
  int soldQty = 0;
  int saleReturnedQty = 0;
  int purchaseReturnedQty = 0;

  _VariantAccumulator({required this.label, this.colorHex});
}
