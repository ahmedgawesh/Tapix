import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class ProductVariantMovementEvent extends RealtimeEvent {
  const ProductVariantMovementEvent();
}

class VariantMovementDateRangeChanged extends ProductVariantMovementEvent {
  final ReportDateRange dateRange;
  const VariantMovementDateRangeChanged(this.dateRange);
}

class VariantMovementSearchChanged extends ProductVariantMovementEvent {
  final String query;
  const VariantMovementSearchChanged(this.query);
}

class VariantMovementProductSelected extends ProductVariantMovementEvent {
  final int productId;
  const VariantMovementProductSelected(this.productId);
}

class VariantMovementProductCleared extends ProductVariantMovementEvent {
  const VariantMovementProductCleared();
}

class VariantMovementGroupByChanged extends ProductVariantMovementEvent {
  final VariantGroupBy groupBy;
  const VariantMovementGroupByChanged(this.groupBy);
}

// ==================== ENUMS ====================

enum VariantMovementType { purchase, sale, saleReturn, purchaseReturn }

enum VariantGroupBy { variant, category, color, size }

// ==================== DATA MODELS ====================

class VariantMovementEntry {
  final VariantMovementType type;
  final DateTime date;
  final String reference;
  final int quantity;
  final String measurementType;
  final int totalCents;
  final String? counterpartyName;
  final int? variantId;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;
  final String? variantSku;

  const VariantMovementEntry({
    required this.type,
    required this.date,
    required this.reference,
    required this.quantity,
    this.measurementType = 'piece',
    required this.totalCents,
    this.counterpartyName,
    this.variantId,
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

class VariantSearchResult {
  final int productId;
  final String name;
  final String? sku;
  final String? barcode;
  final bool hasVariants;
  final String? categoryName;

  const VariantSearchResult({
    required this.productId,
    required this.name,
    this.sku,
    this.barcode,
    this.hasVariants = false,
    this.categoryName,
  });
}

class VariantSummaryItem {
  final String measurementType;
  final String label;
  final String? colorHex;
  final int purchasedQty;
  final int soldQty;
  final int saleReturnedQty;
  final int purchaseReturnedQty;
  final int purchaseCents;
  final int salesCents;
  final int saleReturnCents;
  final int purchaseReturnCents;

  const VariantSummaryItem({
    required this.label,
    this.measurementType = 'piece',
    this.colorHex,
    this.purchasedQty = 0,
    this.soldQty = 0,
    this.saleReturnedQty = 0,
    this.purchaseReturnedQty = 0,
    this.purchaseCents = 0,
    this.salesCents = 0,
    this.saleReturnCents = 0,
    this.purchaseReturnCents = 0,
  });

  int get netQty =>
      purchasedQty - soldQty + saleReturnedQty - purchaseReturnedQty;
  int get totalMovements =>
      purchasedQty + soldQty + saleReturnedQty + purchaseReturnedQty;
}

class VariantMovementTotals {
  final String measurementType;
  final int totalPurchased;
  final int totalSold;
  final int totalSaleReturned;
  final int totalPurchaseReturned;
  final int totalPurchaseCents;
  final int totalSalesCents;
  final int totalSaleReturnCents;
  final int totalPurchaseReturnCents;

  const VariantMovementTotals({
    this.measurementType = 'piece',
    this.totalPurchased = 0,
    this.totalSold = 0,
    this.totalSaleReturned = 0,
    this.totalPurchaseReturned = 0,
    this.totalPurchaseCents = 0,
    this.totalSalesCents = 0,
    this.totalSaleReturnCents = 0,
    this.totalPurchaseReturnCents = 0,
  });

  int get netQuantity =>
      totalPurchased - totalSold + totalSaleReturned - totalPurchaseReturned;
}

class ProductVariantMovementData {
  final ReportDateRange dateRange;
  final String searchQuery;
  final int? selectedProductId;
  final String? selectedProductName;
  final String? selectedProductCategory;
  final bool selectedProductHasVariants;
  final VariantGroupBy groupBy;
  final List<VariantSearchResult> searchResults;
  final List<VariantMovementEntry> movements;
  final List<VariantSummaryItem> variantSummaries;
  final VariantMovementTotals totals;

  const ProductVariantMovementData({
    required this.dateRange,
    this.searchQuery = '',
    this.selectedProductId,
    this.selectedProductName,
    this.selectedProductCategory,
    this.selectedProductHasVariants = false,
    this.groupBy = VariantGroupBy.variant,
    this.searchResults = const [],
    this.movements = const [],
    this.variantSummaries = const [],
    this.totals = const VariantMovementTotals(),
  });

  ProductVariantMovementData copyWith({
    ReportDateRange? dateRange,
    String? searchQuery,
    int? selectedProductId,
    String? selectedProductName,
    String? selectedProductCategory,
    bool? selectedProductHasVariants,
    VariantGroupBy? groupBy,
    List<VariantSearchResult>? searchResults,
    List<VariantMovementEntry>? movements,
    List<VariantSummaryItem>? variantSummaries,
    VariantMovementTotals? totals,
    bool clearProduct = false,
  }) {
    return ProductVariantMovementData(
      dateRange: dateRange ?? this.dateRange,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedProductId: clearProduct
          ? null
          : (selectedProductId ?? this.selectedProductId),
      selectedProductName: clearProduct
          ? null
          : (selectedProductName ?? this.selectedProductName),
      selectedProductCategory: clearProduct
          ? null
          : (selectedProductCategory ?? this.selectedProductCategory),
      selectedProductHasVariants: clearProduct
          ? false
          : (selectedProductHasVariants ?? this.selectedProductHasVariants),
      groupBy: groupBy ?? this.groupBy,
      searchResults: searchResults ?? this.searchResults,
      movements: movements ?? this.movements,
      variantSummaries: variantSummaries ?? this.variantSummaries,
      totals: totals ?? this.totals,
    );
  }
}

// ==================== BLOC ====================

class ProductVariantMovementBloc
    extends
        RealtimeBloc<ProductVariantMovementData, ProductVariantMovementEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  String _searchQuery = '';
  int? _selectedProductId;
  VariantGroupBy _groupBy = VariantGroupBy.variant;

  ProductVariantMovementBloc(this._db, {String defaultDateRange = 'month'})
    : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
      super(const RealtimeLoading());

  @override
  Stream<ProductVariantMovementData> get dataStream {
    return _db.select(_db.sales).watch().asyncMap((_) => _loadData());
  }

  @override
  void registerEventHandlers() {
    on<VariantMovementDateRangeChanged>(_onDateRangeChanged);
    on<VariantMovementSearchChanged>(_onSearchChanged);
    on<VariantMovementProductSelected>(_onProductSelected);
    on<VariantMovementProductCleared>(_onProductCleared);
    on<VariantMovementGroupByChanged>(_onGroupByChanged);
  }

  Future<void> _onDateRangeChanged(
    VariantMovementDateRangeChanged event,
    Emitter<RealtimeState<ProductVariantMovementData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onSearchChanged(
    VariantMovementSearchChanged event,
    Emitter<RealtimeState<ProductVariantMovementData>> emit,
  ) async {
    _searchQuery = event.query;
    if (event.query.trim().isEmpty) {
      final current = currentData;
      if (current != null) {
        emit(
          RealtimeSuccess(
            data: current.copyWith(searchQuery: '', searchResults: []),
          ),
        );
      }
      return;
    }

    final results = await _searchProducts(event.query.trim());
    final current = currentData;
    if (current != null) {
      emit(
        RealtimeSuccess(
          data: current.copyWith(
            searchQuery: event.query,
            searchResults: results,
          ),
        ),
      );
    }
  }

  Future<void> _onProductSelected(
    VariantMovementProductSelected event,
    Emitter<RealtimeState<ProductVariantMovementData>> emit,
  ) async {
    _selectedProductId = event.productId;
    _searchQuery = '';
    refresh();
  }

  Future<void> _onProductCleared(
    VariantMovementProductCleared event,
    Emitter<RealtimeState<ProductVariantMovementData>> emit,
  ) async {
    _selectedProductId = null;
    _searchQuery = '';
    refresh();
  }

  Future<void> _onGroupByChanged(
    VariantMovementGroupByChanged event,
    Emitter<RealtimeState<ProductVariantMovementData>> emit,
  ) async {
    _groupBy = event.groupBy;
    refresh();
  }

  Future<ProductVariantMovementData> _loadData() async {
    if (_selectedProductId == null) {
      return ProductVariantMovementData(
        dateRange: _dateRange,
        searchQuery: _searchQuery,
        groupBy: _groupBy,
      );
    }

    final productId = _selectedProductId!;
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    // Get product info
    final productRow = await _db
        .customSelect(
          '''
      SELECT p.name, p.has_variants, p.measurement_type, pc.name AS category_name
      FROM products p
      LEFT JOIN product_categories pc ON pc.id = p.category_id
      WHERE p.id = ?
      ''',
          variables: [Variable.withInt(productId)],
          readsFrom: {_db.products, _db.productCategories},
        )
        .getSingleOrNull();

    final productName = productRow?.read<String>('name') ?? '';
    final hasVariants = (productRow?.read<bool>('has_variants') ?? false);
    final categoryName = productRow?.readNullable<String>('category_name');
    final measurementType =
        productRow?.read<String>('measurement_type') ?? 'piece';

    final movements = <VariantMovementEntry>[];

    // ── Purchases (with variant details) ──
    final purchaseRows = await _db
        .customSelect(
          '''
      SELECT 
        pu.purchase_date AS dt,
        pu.purchase_number AS ref,
        pi.quantity AS qty,
        pi.total_cents AS total,
        sup.name AS counterparty,
        pi.variant_id AS vid,
        pco.name AS color_name,
        pco.hex_code AS color_hex,
        sz.name AS size_name,
        pv.sku AS variant_sku
      FROM purchase_items pi
      INNER JOIN purchases pu ON pu.id = pi.purchase_id
      LEFT JOIN suppliers sup ON sup.id = pu.supplier_id
      LEFT JOIN product_variants pv ON pv.id = pi.variant_id
      LEFT JOIN product_colors pco ON pco.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE pi.product_id = ?
        AND pu.status != 'voided'
        AND pu.purchase_date >= ? AND pu.purchase_date <= ?
      ORDER BY pu.purchase_date DESC
      ''',
          variables: [
            Variable.withInt(productId),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            _db.purchaseItems,
            _db.purchases,
            _db.suppliers,
            _db.productVariants,
            _db.productColors,
            _db.sizes,
          },
        )
        .get();

    for (final row in purchaseRows) {
      movements.add(
        VariantMovementEntry(
          type: VariantMovementType.purchase,
          date: DateTime.parse(row.read<String>('dt')),
          reference: row.read<String>('ref'),
          quantity: row.read<int>('qty'),
          measurementType: measurementType,
          totalCents: row.read<int>('total'),
          counterpartyName: row.readNullable<String>('counterparty'),
          variantId: row.readNullable<int>('vid'),
          colorName: row.readNullable<String>('color_name'),
          colorHex: row.readNullable<String>('color_hex'),
          sizeName: row.readNullable<String>('size_name'),
          variantSku: row.readNullable<String>('variant_sku'),
        ),
      );
    }

    // ── Sales (with variant details) ──
    final saleRows = await _db
        .customSelect(
          '''
      SELECT 
        s.sale_date AS dt,
        s.invoice_number AS ref,
        si.quantity AS qty,
        si.total_cents AS total,
        c.name AS counterparty,
        si.variant_id AS vid,
        pco.name AS color_name,
        pco.hex_code AS color_hex,
        sz.name AS size_name,
        pv.sku AS variant_sku
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN product_variants pv ON pv.id = si.variant_id
      LEFT JOIN product_colors pco ON pco.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE si.product_id = ?
        AND s.status != 'voided'
        AND s.sale_date >= ? AND s.sale_date <= ?
      ORDER BY s.sale_date DESC
      ''',
          variables: [
            Variable.withInt(productId),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            _db.saleItems,
            _db.sales,
            _db.customers,
            _db.productVariants,
            _db.productColors,
            _db.sizes,
          },
        )
        .get();

    for (final row in saleRows) {
      movements.add(
        VariantMovementEntry(
          type: VariantMovementType.sale,
          date: DateTime.parse(row.read<String>('dt')),
          reference: row.read<String>('ref'),
          quantity: row.read<int>('qty'),
          measurementType: measurementType,
          totalCents: row.read<int>('total'),
          counterpartyName: row.readNullable<String>('counterparty'),
          variantId: row.readNullable<int>('vid'),
          colorName: row.readNullable<String>('color_name'),
          colorHex: row.readNullable<String>('color_hex'),
          sizeName: row.readNullable<String>('size_name'),
          variantSku: row.readNullable<String>('variant_sku'),
        ),
      );
    }

    // ── Sale Returns (with variant details) ──
    final saleReturnRows = await _db
        .customSelect(
          '''
      SELECT 
        sr.return_date AS dt,
        sr.return_number AS ref,
        sri.quantity AS qty,
        sri.refund_cents AS total,
        c.name AS counterparty,
        si.variant_id AS vid,
        pco.name AS color_name,
        pco.hex_code AS color_hex,
        sz.name AS size_name,
        pv.sku AS variant_sku
      FROM sale_return_items sri
      INNER JOIN sale_returns sr ON sr.id = sri.return_id
      INNER JOIN sale_items si ON si.id = sri.sale_item_id
      INNER JOIN sales s ON s.id = sr.sale_id
      LEFT JOIN customers c ON c.id = s.customer_id
      LEFT JOIN product_variants pv ON pv.id = si.variant_id
      LEFT JOIN product_colors pco ON pco.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE si.product_id = ?
        AND sr.status = 'posted'
        AND sr.return_date >= ? AND sr.return_date <= ?
      ORDER BY sr.return_date DESC
      ''',
          variables: [
            Variable.withInt(productId),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            _db.saleReturnItems,
            _db.saleReturns,
            _db.saleItems,
            _db.sales,
            _db.customers,
            _db.productVariants,
            _db.productColors,
            _db.sizes,
          },
        )
        .get();

    for (final row in saleReturnRows) {
      movements.add(
        VariantMovementEntry(
          type: VariantMovementType.saleReturn,
          date: DateTime.parse(row.read<String>('dt')),
          reference: row.read<String>('ref'),
          quantity: row.read<int>('qty'),
          measurementType: measurementType,
          totalCents: row.read<int>('total'),
          counterpartyName: row.readNullable<String>('counterparty'),
          variantId: row.readNullable<int>('vid'),
          colorName: row.readNullable<String>('color_name'),
          colorHex: row.readNullable<String>('color_hex'),
          sizeName: row.readNullable<String>('size_name'),
          variantSku: row.readNullable<String>('variant_sku'),
        ),
      );
    }

    // ── Sale Adjustment Returns (unlinked, with variant details) ──
    final saleAdjReturnRows = await _db
        .customSelect(
          '''
      SELECT 
        sra.return_date AS dt,
        sra.return_number AS ref,
        srai.quantity AS qty,
        srai.total_cents AS total,
        c.name AS counterparty,
        srai.variant_id AS vid,
        pco.name AS color_name,
        pco.hex_code AS color_hex,
        sz.name AS size_name,
        pv.sku AS variant_sku
      FROM sale_return_adjustment_items srai
      INNER JOIN sale_return_adjustments sra ON sra.id = srai.return_id
      LEFT JOIN customers c ON c.id = sra.customer_id
      LEFT JOIN product_variants pv ON pv.id = srai.variant_id
      LEFT JOIN product_colors pco ON pco.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE srai.product_id = ?
        AND sra.status = 'posted'
        AND sra.return_date >= ? AND sra.return_date <= ?
      ORDER BY sra.return_date DESC
      ''',
          variables: [
            Variable.withInt(productId),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            _db.saleReturnAdjustmentItems,
            _db.saleReturnAdjustments,
            _db.customers,
            _db.productVariants,
            _db.productColors,
            _db.sizes,
          },
        )
        .get();

    for (final row in saleAdjReturnRows) {
      movements.add(
        VariantMovementEntry(
          type: VariantMovementType.saleReturn,
          date: DateTime.parse(row.read<String>('dt')),
          reference: row.read<String>('ref'),
          quantity: row.read<int>('qty'),
          measurementType: measurementType,
          totalCents: row.read<int>('total'),
          counterpartyName: row.readNullable<String>('counterparty'),
          variantId: row.readNullable<int>('vid'),
          colorName: row.readNullable<String>('color_name'),
          colorHex: row.readNullable<String>('color_hex'),
          sizeName: row.readNullable<String>('size_name'),
          variantSku: row.readNullable<String>('variant_sku'),
        ),
      );
    }

    // ── Purchase Returns (with variant details) ──
    final purchaseReturnRows = await _db
        .customSelect(
          '''
      SELECT 
        pr.return_date AS dt,
        pr.return_number AS ref,
        pri.quantity AS qty,
        pri.refund_cents AS total,
        sup.name AS counterparty,
        pi.variant_id AS vid,
        pco.name AS color_name,
        pco.hex_code AS color_hex,
        sz.name AS size_name,
        pv.sku AS variant_sku
      FROM purchase_return_items pri
      INNER JOIN purchase_returns pr ON pr.id = pri.return_id
      INNER JOIN purchase_items pi ON pi.id = pri.purchase_item_id
      INNER JOIN purchases pu ON pu.id = pr.purchase_id
      LEFT JOIN suppliers sup ON sup.id = pu.supplier_id
      LEFT JOIN product_variants pv ON pv.id = pi.variant_id
      LEFT JOIN product_colors pco ON pco.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE pi.product_id = ?
        AND pr.status = 'posted'
        AND pr.return_date >= ? AND pr.return_date <= ?
      ORDER BY pr.return_date DESC
      ''',
          variables: [
            Variable.withInt(productId),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            _db.purchaseReturnItems,
            _db.purchaseReturns,
            _db.purchaseItems,
            _db.purchases,
            _db.suppliers,
            _db.productVariants,
            _db.productColors,
            _db.sizes,
          },
        )
        .get();

    for (final row in purchaseReturnRows) {
      movements.add(
        VariantMovementEntry(
          type: VariantMovementType.purchaseReturn,
          date: DateTime.parse(row.read<String>('dt')),
          reference: row.read<String>('ref'),
          quantity: row.read<int>('qty'),
          measurementType: measurementType,
          totalCents: row.read<int>('total'),
          counterpartyName: row.readNullable<String>('counterparty'),
          variantId: row.readNullable<int>('vid'),
          colorName: row.readNullable<String>('color_name'),
          colorHex: row.readNullable<String>('color_hex'),
          sizeName: row.readNullable<String>('size_name'),
          variantSku: row.readNullable<String>('variant_sku'),
        ),
      );
    }

    // ── Purchase Adjustment Returns (unlinked, with variant details) ──
    final purchaseAdjReturnRows = await _db
        .customSelect(
          '''
      SELECT 
        pra.return_date AS dt,
        pra.return_number AS ref,
        prai.quantity AS qty,
        prai.total_cents AS total,
        sup.name AS counterparty,
        prai.variant_id AS vid,
        pco.name AS color_name,
        pco.hex_code AS color_hex,
        sz.name AS size_name,
        pv.sku AS variant_sku
      FROM purchase_return_adjustment_items prai
      INNER JOIN purchase_return_adjustments pra ON pra.id = prai.return_id
      LEFT JOIN suppliers sup ON sup.id = pra.supplier_id
      LEFT JOIN product_variants pv ON pv.id = prai.variant_id
      LEFT JOIN product_colors pco ON pco.id = pv.color_id
      LEFT JOIN sizes sz ON sz.id = pv.size_id
      WHERE prai.product_id = ?
        AND pra.status = 'posted'
        AND pra.return_date >= ? AND pra.return_date <= ?
      ORDER BY pra.return_date DESC
      ''',
          variables: [
            Variable.withInt(productId),
            Variable.withString(startIso),
            Variable.withString(endIso),
          ],
          readsFrom: {
            _db.purchaseReturnAdjustmentItems,
            _db.purchaseReturnAdjustments,
            _db.suppliers,
            _db.productVariants,
            _db.productColors,
            _db.sizes,
          },
        )
        .get();

    for (final row in purchaseAdjReturnRows) {
      movements.add(
        VariantMovementEntry(
          type: VariantMovementType.purchaseReturn,
          date: DateTime.parse(row.read<String>('dt')),
          reference: row.read<String>('ref'),
          quantity: row.read<int>('qty'),
          measurementType: measurementType,
          totalCents: row.read<int>('total'),
          counterpartyName: row.readNullable<String>('counterparty'),
          variantId: row.readNullable<int>('vid'),
          colorName: row.readNullable<String>('color_name'),
          colorHex: row.readNullable<String>('color_hex'),
          sizeName: row.readNullable<String>('size_name'),
          variantSku: row.readNullable<String>('variant_sku'),
        ),
      );
    }

    // Sort all movements by date descending
    movements.sort((a, b) => b.date.compareTo(a.date));

    // Build variant summaries based on groupBy
    final variantSummaries = _buildSummaries(movements, _groupBy);

    // Compute totals
    int totalPurchased = 0,
        totalSold = 0,
        totalSaleReturned = 0,
        totalPurchaseReturned = 0;
    int totalPurchaseCents = 0,
        totalSalesCents = 0,
        totalSaleReturnCents = 0,
        totalPurchaseReturnCents = 0;

    for (final m in movements) {
      switch (m.type) {
        case VariantMovementType.purchase:
          totalPurchased += m.quantity;
          totalPurchaseCents += m.totalCents;
        case VariantMovementType.sale:
          totalSold += m.quantity;
          totalSalesCents += m.totalCents;
        case VariantMovementType.saleReturn:
          totalSaleReturned += m.quantity;
          totalSaleReturnCents += m.totalCents;
        case VariantMovementType.purchaseReturn:
          totalPurchaseReturned += m.quantity;
          totalPurchaseReturnCents += m.totalCents;
      }
    }

    return ProductVariantMovementData(
      dateRange: _dateRange,
      searchQuery: _searchQuery,
      selectedProductId: productId,
      selectedProductName: productName,
      selectedProductCategory: categoryName,
      selectedProductHasVariants: hasVariants,
      groupBy: _groupBy,
      movements: movements,
      variantSummaries: variantSummaries,
      totals: VariantMovementTotals(
        measurementType: movements.isEmpty
            ? 'piece'
            : movements.first.measurementType,
        totalPurchased: totalPurchased,
        totalSold: totalSold,
        totalSaleReturned: totalSaleReturned,
        totalPurchaseReturned: totalPurchaseReturned,
        totalPurchaseCents: totalPurchaseCents,
        totalSalesCents: totalSalesCents,
        totalSaleReturnCents: totalSaleReturnCents,
        totalPurchaseReturnCents: totalPurchaseReturnCents,
      ),
    );
  }

  List<VariantSummaryItem> _buildSummaries(
    List<VariantMovementEntry> movements,
    VariantGroupBy groupBy,
  ) {
    final map = <String, _SummaryAccumulator>{};

    for (final m in movements) {
      final key = _groupKey(m, groupBy);
      final hex = groupBy == VariantGroupBy.color ? m.colorHex : null;
      final acc = map.putIfAbsent(
        key,
        () => _SummaryAccumulator(label: key, colorHex: hex),
      );

      switch (m.type) {
        case VariantMovementType.purchase:
          acc.purchasedQty += m.quantity;
          acc.purchaseCents += m.totalCents;
        case VariantMovementType.sale:
          acc.soldQty += m.quantity;
          acc.salesCents += m.totalCents;
        case VariantMovementType.saleReturn:
          acc.saleReturnedQty += m.quantity;
          acc.saleReturnCents += m.totalCents;
        case VariantMovementType.purchaseReturn:
          acc.purchaseReturnedQty += m.quantity;
          acc.purchaseReturnCents += m.totalCents;
      }
    }

    final items = map.values
        .map(
          (a) => VariantSummaryItem(
            label: a.label,
            measurementType: movements.isEmpty
                ? 'piece'
                : movements.first.measurementType,
            colorHex: a.colorHex,
            purchasedQty: a.purchasedQty,
            soldQty: a.soldQty,
            saleReturnedQty: a.saleReturnedQty,
            purchaseReturnedQty: a.purchaseReturnedQty,
            purchaseCents: a.purchaseCents,
            salesCents: a.salesCents,
            saleReturnCents: a.saleReturnCents,
            purchaseReturnCents: a.purchaseReturnCents,
          ),
        )
        .toList();

    // Sort by total movements descending
    items.sort((a, b) => b.totalMovements.compareTo(a.totalMovements));
    return items;
  }

  String _groupKey(VariantMovementEntry m, VariantGroupBy groupBy) {
    switch (groupBy) {
      case VariantGroupBy.variant:
        final label = m.variantLabel;
        return label.isEmpty ? '—' : label;
      case VariantGroupBy.color:
        return (m.colorName != null && m.colorName!.isNotEmpty)
            ? m.colorName!
            : '—';
      case VariantGroupBy.size:
        return (m.sizeName != null && m.sizeName!.isNotEmpty)
            ? m.sizeName!
            : '—';
      case VariantGroupBy.category:
        // Category is product-level, same for all entries
        return '—';
    }
  }

  Future<List<VariantSearchResult>> _searchProducts(String query) async {
    final likeQuery = '%$query%';
    final rows = await _db
        .customSelect(
          '''
      SELECT DISTINCT p.id, p.name, p.sku, p.barcode, p.has_variants,
             pc.name AS category_name
      FROM products p
      LEFT JOIN product_variants v ON v.product_id = p.id
      LEFT JOIN product_categories pc ON pc.id = p.category_id
      WHERE p.is_active = 1
        AND (
          p.name LIKE ?
          OR p.sku LIKE ?
          OR p.barcode LIKE ?
          OR v.sku LIKE ?
          OR v.barcode LIKE ?
          OR pc.name LIKE ?
        )
      ORDER BY p.name
      LIMIT 20
      ''',
          variables: [
            Variable.withString(likeQuery),
            Variable.withString(likeQuery),
            Variable.withString(likeQuery),
            Variable.withString(likeQuery),
            Variable.withString(likeQuery),
            Variable.withString(likeQuery),
          ],
          readsFrom: {_db.products, _db.productVariants, _db.productCategories},
        )
        .get();

    return rows
        .map(
          (row) => VariantSearchResult(
            productId: row.read<int>('id'),
            name: row.read<String>('name'),
            sku: row.readNullable<String>('sku'),
            barcode: row.readNullable<String>('barcode'),
            hasVariants: row.read<bool>('has_variants'),
            categoryName: row.readNullable<String>('category_name'),
          ),
        )
        .toList();
  }
}

class _SummaryAccumulator {
  final String label;
  final String? colorHex;
  int purchasedQty = 0;
  int soldQty = 0;
  int saleReturnedQty = 0;
  int purchaseReturnedQty = 0;
  int purchaseCents = 0;
  int salesCents = 0;
  int saleReturnCents = 0;
  int purchaseReturnCents = 0;

  _SummaryAccumulator({required this.label, this.colorHex});
}
