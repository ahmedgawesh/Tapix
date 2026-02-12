import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class ProductMovementDetailEvent extends RealtimeEvent {
  const ProductMovementDetailEvent();
}

class ProductMovementDetailDateRangeChanged extends ProductMovementDetailEvent {
  final ReportDateRange dateRange;
  const ProductMovementDetailDateRangeChanged(this.dateRange);
}

class ProductMovementDetailSearchChanged extends ProductMovementDetailEvent {
  final String query;
  const ProductMovementDetailSearchChanged(this.query);
}

class ProductMovementDetailProductSelected extends ProductMovementDetailEvent {
  final int productId;
  const ProductMovementDetailProductSelected(this.productId);
}

class ProductMovementDetailProductCleared extends ProductMovementDetailEvent {
  const ProductMovementDetailProductCleared();
}

// ==================== ENUMS ====================

enum MovementType { purchase, sale, saleReturn, purchaseReturn }

// ==================== DATA MODELS ====================

class MovementEntry {
  final MovementType type;
  final DateTime date;
  final String reference;
  final int quantity;
  final int totalCents;
  final String? counterpartyName;

  const MovementEntry({
    required this.type,
    required this.date,
    required this.reference,
    required this.quantity,
    required this.totalCents,
    this.counterpartyName,
  });
}

class ProductSearchResult {
  final int productId;
  final String name;
  final String? sku;
  final String? barcode;

  const ProductSearchResult({
    required this.productId,
    required this.name,
    this.sku,
    this.barcode,
  });
}

class ProductMovementSummary {
  final int totalPurchased;
  final int totalSold;
  final int totalSaleReturned;
  final int totalPurchaseReturned;
  final int totalPurchaseCents;
  final int totalSalesCents;
  final int totalSaleReturnCents;
  final int totalPurchaseReturnCents;

  const ProductMovementSummary({
    this.totalPurchased = 0,
    this.totalSold = 0,
    this.totalSaleReturned = 0,
    this.totalPurchaseReturned = 0,
    this.totalPurchaseCents = 0,
    this.totalSalesCents = 0,
    this.totalSaleReturnCents = 0,
    this.totalPurchaseReturnCents = 0,
  });

  int get netQuantity => totalPurchased - totalSold + totalSaleReturned - totalPurchaseReturned;
}

class ProductMovementDetailData {
  final ReportDateRange dateRange;
  final String searchQuery;
  final int? selectedProductId;
  final String? selectedProductName;
  final List<ProductSearchResult> searchResults;
  final List<MovementEntry> movements;
  final ProductMovementSummary summary;

  const ProductMovementDetailData({
    required this.dateRange,
    this.searchQuery = '',
    this.selectedProductId,
    this.selectedProductName,
    this.searchResults = const [],
    this.movements = const [],
    this.summary = const ProductMovementSummary(),
  });

  ProductMovementDetailData copyWith({
    ReportDateRange? dateRange,
    String? searchQuery,
    int? selectedProductId,
    String? selectedProductName,
    List<ProductSearchResult>? searchResults,
    List<MovementEntry>? movements,
    ProductMovementSummary? summary,
    bool clearProduct = false,
  }) {
    return ProductMovementDetailData(
      dateRange: dateRange ?? this.dateRange,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedProductId: clearProduct ? null : (selectedProductId ?? this.selectedProductId),
      selectedProductName: clearProduct ? null : (selectedProductName ?? this.selectedProductName),
      searchResults: searchResults ?? this.searchResults,
      movements: movements ?? this.movements,
      summary: summary ?? this.summary,
    );
  }
}

// ==================== BLOC ====================

class ProductMovementDetailBloc
    extends RealtimeBloc<ProductMovementDetailData, ProductMovementDetailEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  String _searchQuery = '';
  int? _selectedProductId;

  ProductMovementDetailBloc(this._db) : super(const RealtimeLoading());

  @override
  Stream<ProductMovementDetailData> get dataStream {
    // Watch sales table as trigger for real-time updates
    return _db.select(_db.sales).watch().asyncMap((_) => _loadData());
  }

  @override
  void registerEventHandlers() {
    on<ProductMovementDetailDateRangeChanged>(_onDateRangeChanged);
    on<ProductMovementDetailSearchChanged>(_onSearchChanged);
    on<ProductMovementDetailProductSelected>(_onProductSelected);
    on<ProductMovementDetailProductCleared>(_onProductCleared);
  }

  Future<void> _onDateRangeChanged(
    ProductMovementDetailDateRangeChanged event,
    Emitter<RealtimeState<ProductMovementDetailData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onSearchChanged(
    ProductMovementDetailSearchChanged event,
    Emitter<RealtimeState<ProductMovementDetailData>> emit,
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

    final results = await _searchProducts(event.query.trim());
    final current = currentData;
    if (current != null) {
      emit(RealtimeSuccess(data: current.copyWith(
        searchQuery: event.query,
        searchResults: results,
      )));
    }
  }

  Future<void> _onProductSelected(
    ProductMovementDetailProductSelected event,
    Emitter<RealtimeState<ProductMovementDetailData>> emit,
  ) async {
    _selectedProductId = event.productId;
    _searchQuery = '';
    refresh();
  }

  Future<void> _onProductCleared(
    ProductMovementDetailProductCleared event,
    Emitter<RealtimeState<ProductMovementDetailData>> emit,
  ) async {
    _selectedProductId = null;
    _searchQuery = '';
    refresh();
  }

  Future<ProductMovementDetailData> _loadData() async {
    if (_selectedProductId == null) {
      return ProductMovementDetailData(
        dateRange: _dateRange,
        searchQuery: _searchQuery,
      );
    }

    final productId = _selectedProductId!;
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    // Get product name
    final productRow = await (_db.select(_db.products)
          ..where((p) => p.id.equals(productId)))
        .getSingleOrNull();
    final productName = productRow?.name ?? '';

    final movements = <MovementEntry>[];

    // ── Purchases ──
    final purchaseRows = await _db.customSelect(
      '''
      SELECT 
        pu.purchase_date AS dt,
        pu.purchase_number AS ref,
        pi.quantity AS qty,
        pi.total_cents AS total,
        s.name AS counterparty
      FROM purchase_items pi
      INNER JOIN purchases pu ON pu.id = pi.purchase_id
      LEFT JOIN suppliers s ON s.id = pu.supplier_id
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
      readsFrom: {_db.purchaseItems, _db.purchases, _db.suppliers},
    ).get();

    for (final row in purchaseRows) {
      movements.add(MovementEntry(
        type: MovementType.purchase,
        date: DateTime.parse(row.read<String>('dt')),
        reference: row.read<String>('ref'),
        quantity: row.read<int>('qty'),
        totalCents: row.read<int>('total'),
        counterpartyName: row.readNullable<String>('counterparty'),
      ));
    }

    // ── Sales ──
    final saleRows = await _db.customSelect(
      '''
      SELECT 
        s.sale_date AS dt,
        s.invoice_number AS ref,
        si.quantity AS qty,
        si.total_cents AS total,
        c.name AS counterparty
      FROM sale_items si
      INNER JOIN sales s ON s.id = si.sale_id
      LEFT JOIN customers c ON c.id = s.customer_id
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
      readsFrom: {_db.saleItems, _db.sales, _db.customers},
    ).get();

    for (final row in saleRows) {
      movements.add(MovementEntry(
        type: MovementType.sale,
        date: DateTime.parse(row.read<String>('dt')),
        reference: row.read<String>('ref'),
        quantity: row.read<int>('qty'),
        totalCents: row.read<int>('total'),
        counterpartyName: row.readNullable<String>('counterparty'),
      ));
    }

    // ── Sale Returns ──
    final saleReturnRows = await _db.customSelect(
      '''
      SELECT 
        sr.return_date AS dt,
        sr.return_number AS ref,
        sri.quantity AS qty,
        sri.refund_cents AS total,
        c.name AS counterparty
      FROM sale_return_items sri
      INNER JOIN sale_returns sr ON sr.id = sri.return_id
      INNER JOIN sale_items si ON si.id = sri.sale_item_id
      INNER JOIN sales s ON s.id = sr.sale_id
      LEFT JOIN customers c ON c.id = s.customer_id
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
      readsFrom: {_db.saleReturnItems, _db.saleReturns, _db.saleItems, _db.sales, _db.customers},
    ).get();

    for (final row in saleReturnRows) {
      movements.add(MovementEntry(
        type: MovementType.saleReturn,
        date: DateTime.parse(row.read<String>('dt')),
        reference: row.read<String>('ref'),
        quantity: row.read<int>('qty'),
        totalCents: row.read<int>('total'),
        counterpartyName: row.readNullable<String>('counterparty'),
      ));
    }

    // ── Purchase Returns ──
    final purchaseReturnRows = await _db.customSelect(
      '''
      SELECT 
        pr.return_date AS dt,
        pr.return_number AS ref,
        pri.quantity AS qty,
        pri.refund_cents AS total,
        sup.name AS counterparty
      FROM purchase_return_items pri
      INNER JOIN purchase_returns pr ON pr.id = pri.return_id
      INNER JOIN purchase_items pi ON pi.id = pri.purchase_item_id
      INNER JOIN purchases pu ON pu.id = pr.purchase_id
      LEFT JOIN suppliers sup ON sup.id = pu.supplier_id
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
      readsFrom: {_db.purchaseReturnItems, _db.purchaseReturns, _db.purchaseItems, _db.purchases, _db.suppliers},
    ).get();

    for (final row in purchaseReturnRows) {
      movements.add(MovementEntry(
        type: MovementType.purchaseReturn,
        date: DateTime.parse(row.read<String>('dt')),
        reference: row.read<String>('ref'),
        quantity: row.read<int>('qty'),
        totalCents: row.read<int>('total'),
        counterpartyName: row.readNullable<String>('counterparty'),
      ));
    }

    // Sort all movements by date descending
    movements.sort((a, b) => b.date.compareTo(a.date));

    // Compute summary
    int totalPurchased = 0, totalSold = 0, totalSaleReturned = 0, totalPurchaseReturned = 0;
    int totalPurchaseCents = 0, totalSalesCents = 0, totalSaleReturnCents = 0, totalPurchaseReturnCents = 0;

    for (final m in movements) {
      switch (m.type) {
        case MovementType.purchase:
          totalPurchased += m.quantity;
          totalPurchaseCents += m.totalCents;
        case MovementType.sale:
          totalSold += m.quantity;
          totalSalesCents += m.totalCents;
        case MovementType.saleReturn:
          totalSaleReturned += m.quantity;
          totalSaleReturnCents += m.totalCents;
        case MovementType.purchaseReturn:
          totalPurchaseReturned += m.quantity;
          totalPurchaseReturnCents += m.totalCents;
      }
    }

    return ProductMovementDetailData(
      dateRange: _dateRange,
      searchQuery: _searchQuery,
      selectedProductId: productId,
      selectedProductName: productName,
      movements: movements,
      summary: ProductMovementSummary(
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

  Future<List<ProductSearchResult>> _searchProducts(String query) async {
    final likeQuery = '%$query%';
    final rows = await _db.customSelect(
      '''
      SELECT DISTINCT p.id, p.name, p.sku, p.barcode
      FROM products p
      LEFT JOIN product_variants v ON v.product_id = p.id
      WHERE p.is_active = 1
        AND (
          p.name LIKE ?
          OR p.sku LIKE ?
          OR p.barcode LIKE ?
          OR v.sku LIKE ?
          OR v.barcode LIKE ?
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
      ],
      readsFrom: {_db.products, _db.productVariants},
    ).get();

    return rows.map((row) => ProductSearchResult(
      productId: row.read<int>('id'),
      name: row.read<String>('name'),
      sku: row.readNullable<String>('sku'),
      barcode: row.readNullable<String>('barcode'),
    )).toList();
  }
}
