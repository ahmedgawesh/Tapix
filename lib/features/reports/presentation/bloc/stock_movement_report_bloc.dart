import '../../../../core/services/business/warehouse_read_scope.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/business/document_posting_scope.dart';
import '../../../../core/services/business/warehouse_document_scope.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class StockMovementReportEvent extends RealtimeEvent {
  const StockMovementReportEvent();
}

class StockMovementDateRangeChanged extends StockMovementReportEvent {
  final ReportDateRange dateRange;
  const StockMovementDateRangeChanged(this.dateRange);
}

class StockMovementSearchChanged extends StockMovementReportEvent {
  final String query;
  const StockMovementSearchChanged(this.query);
}

class StockMovementProductSelected extends StockMovementReportEvent {
  final int productId;
  const StockMovementProductSelected(this.productId);
}

class StockMovementProductCleared extends StockMovementReportEvent {
  const StockMovementProductCleared();
}

class StockMovementTypeFilterChanged extends StockMovementReportEvent {
  final StockMovementType? filter;
  const StockMovementTypeFilterChanged(this.filter);
}

// ==================== ENUMS ====================

enum StockMovementType {
  purchase,
  sale,
  saleReturn,
  saleReturnAdjustment,
  purchaseReturn,
  purchaseReturnAdjustment,
}

// ==================== DATA MODELS ====================

class StockMovementEntry {
  final StockMovementType type;
  final DateTime date;
  final String reference;
  final int quantity;
  final String measurementType;
  final int totalCents;
  final String? counterpartyName;

  const StockMovementEntry({
    required this.type,
    required this.date,
    required this.reference,
    required this.quantity,
    this.measurementType = 'piece',
    required this.totalCents,
    this.counterpartyName,
  });
}

class StockProductSearchResult {
  final int productId;
  final String name;
  final String? sku;
  final String? barcode;

  const StockProductSearchResult({
    required this.productId,
    required this.name,
    this.sku,
    this.barcode,
  });
}

class StockMovementSummary {
  final String measurementType;
  final int totalPurchased;
  final int totalSold;
  final int totalSaleReturned;
  final int totalSaleReturnAdj;
  final int totalPurchaseReturned;
  final int totalPurchaseReturnAdj;
  final int totalPurchaseCents;
  final int totalSalesCents;
  final int totalSaleReturnCents;
  final int totalSaleReturnAdjCents;
  final int totalPurchaseReturnCents;
  final int totalPurchaseReturnAdjCents;

  const StockMovementSummary({
    this.measurementType = 'piece',
    this.totalPurchased = 0,
    this.totalSold = 0,
    this.totalSaleReturned = 0,
    this.totalSaleReturnAdj = 0,
    this.totalPurchaseReturned = 0,
    this.totalPurchaseReturnAdj = 0,
    this.totalPurchaseCents = 0,
    this.totalSalesCents = 0,
    this.totalSaleReturnCents = 0,
    this.totalSaleReturnAdjCents = 0,
    this.totalPurchaseReturnCents = 0,
    this.totalPurchaseReturnAdjCents = 0,
  });

  int get netQuantity =>
      totalPurchased -
      totalSold +
      totalSaleReturned +
      totalSaleReturnAdj -
      totalPurchaseReturned -
      totalPurchaseReturnAdj;
}

class StockMovementReportData {
  final ReportDateRange dateRange;
  final String searchQuery;
  final int? selectedProductId;
  final String? selectedProductName;
  final StockMovementType? movementTypeFilter;
  final List<StockProductSearchResult> searchResults;
  final List<StockMovementEntry> movements;
  final StockMovementSummary summary;

  const StockMovementReportData({
    required this.dateRange,
    this.searchQuery = '',
    this.selectedProductId,
    this.selectedProductName,
    this.movementTypeFilter,
    this.searchResults = const [],
    this.movements = const [],
    this.summary = const StockMovementSummary(),
  });

  StockMovementReportData copyWith({
    ReportDateRange? dateRange,
    String? searchQuery,
    int? selectedProductId,
    String? selectedProductName,
    StockMovementType? movementTypeFilter,
    List<StockProductSearchResult>? searchResults,
    List<StockMovementEntry>? movements,
    StockMovementSummary? summary,
    bool clearProduct = false,
    bool clearFilter = false,
  }) {
    return StockMovementReportData(
      dateRange: dateRange ?? this.dateRange,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedProductId: clearProduct
          ? null
          : (selectedProductId ?? this.selectedProductId),
      selectedProductName: clearProduct
          ? null
          : (selectedProductName ?? this.selectedProductName),
      movementTypeFilter: clearFilter
          ? null
          : (movementTypeFilter ?? this.movementTypeFilter),
      searchResults: searchResults ?? this.searchResults,
      movements: movements ?? this.movements,
      summary: summary ?? this.summary,
    );
  }

  /// Returns filtered movements based on the current type filter.
  List<StockMovementEntry> get filteredMovements {
    if (movementTypeFilter == null) return movements;
    return movements.where((m) => m.type == movementTypeFilter).toList();
  }
}

// ==================== BLOC ====================

class StockMovementReportBloc
    extends RealtimeBloc<StockMovementReportData, StockMovementReportEvent> {
  final AppDatabase _db;
  final WarehouseReadScope? warehouseScope;
  ReportDateRange _dateRange;
  String _searchQuery = '';
  int? _selectedProductId;
  StockMovementType? _movementTypeFilter;

  StockMovementReportBloc(
    this._db, {
    String defaultDateRange = 'month',
    this.warehouseScope,
  }) : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
       super(const RealtimeLoading());

  @override
  Stream<StockMovementReportData> get dataStream {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.customers,
            _db.productCategories,
            _db.productVariants,
            _db.products,
            _db.purchaseItems,
            _db.purchaseReturnAdjustmentItems,
            _db.purchaseReturnAdjustments,
            _db.purchaseReturnItems,
            _db.purchaseReturns,
            _db.purchases,
            _db.saleItems,
            _db.saleReturnAdjustmentItems,
            _db.saleReturnAdjustments,
            _db.saleReturnItems,
            _db.saleReturns,
            _db.sales,
            _db.suppliers,
          },
        )
        .watch()
        .asyncMap(
          (_) => WarehouseReadScope.snapshot(_db, warehouseScope, _loadData),
        );
  }

  @override
  void registerEventHandlers() {
    on<StockMovementDateRangeChanged>(_onDateRangeChanged);
    on<StockMovementSearchChanged>(_onSearchChanged);
    on<StockMovementProductSelected>(_onProductSelected);
    on<StockMovementProductCleared>(_onProductCleared);
    on<StockMovementTypeFilterChanged>(_onTypeFilterChanged);
  }

  Future<void> _onDateRangeChanged(
    StockMovementDateRangeChanged event,
    Emitter<RealtimeState<StockMovementReportData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onSearchChanged(
    StockMovementSearchChanged event,
    Emitter<RealtimeState<StockMovementReportData>> emit,
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
    StockMovementProductSelected event,
    Emitter<RealtimeState<StockMovementReportData>> emit,
  ) async {
    _selectedProductId = event.productId;
    _searchQuery = '';
    refresh();
  }

  Future<void> _onProductCleared(
    StockMovementProductCleared event,
    Emitter<RealtimeState<StockMovementReportData>> emit,
  ) async {
    _selectedProductId = null;
    _searchQuery = '';
    refresh();
  }

  Future<void> _onTypeFilterChanged(
    StockMovementTypeFilterChanged event,
    Emitter<RealtimeState<StockMovementReportData>> emit,
  ) async {
    _movementTypeFilter = event.filter;
    final current = currentData;
    if (current != null) {
      emit(
        RealtimeSuccess(
          data: current.copyWith(
            movementTypeFilter: event.filter,
            clearFilter: event.filter == null,
          ),
        ),
      );
    }
  }

  Future<StockMovementReportData> _loadData() async {
    if (_selectedProductId == null) {
      return StockMovementReportData(
        dateRange: _dateRange,
        searchQuery: _searchQuery,
        movementTypeFilter: _movementTypeFilter,
      );
    }

    final productId = _selectedProductId!;
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    // Get product name
    final productRow = await (_db.select(
      _db.products,
    )..where((p) => p.id.equals(productId))).getSingleOrNull();
    final productName = productRow?.name ?? '';
    final measurementType = productRow?.measurementType ?? 'piece';

    final movements = <StockMovementEntry>[];

    // ── Purchases ──
    final purchaseRows = await _db
        .customSelect(
          '''
      SELECT 
        pu.purchase_date AS dt,
        pu.purchase_number AS ref,
        pi.quantity AS qty,
        pi.total_cents AS total,
        s.name AS counterparty
      FROM purchase_items pi
      INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.purchase) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchase)} pu ON pu.id = pi.purchase_id
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
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.purchaseItems,
            _db.purchases,
            _db.suppliers,
          },
        )
        .get();

    for (final row in purchaseRows) {
      movements.add(
        StockMovementEntry(
          type: StockMovementType.purchase,
          date: DateTime.parse(row.read<String>('dt')),
          reference: row.read<String>('ref'),
          quantity: row.read<int>('qty'),
          measurementType: measurementType,
          totalCents: row.read<int>('total'),
          counterpartyName: row.readNullable<String>('counterparty'),
        ),
      );
    }

    // ── Sales ──
    final saleRows = await _db
        .customSelect(
          '''
      SELECT 
        s.sale_date AS dt,
        s.invoice_number AS ref,
        si.quantity AS qty,
        si.total_cents AS total,
        c.name AS counterparty
      FROM sale_items si
      INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.sale) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.sale)} s ON s.id = si.sale_id
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
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleItems,
            _db.sales,
            _db.customers,
          },
        )
        .get();

    for (final row in saleRows) {
      movements.add(
        StockMovementEntry(
          type: StockMovementType.sale,
          date: DateTime.parse(row.read<String>('dt')),
          reference: row.read<String>('ref'),
          quantity: row.read<int>('qty'),
          measurementType: measurementType,
          totalCents: row.read<int>('total'),
          counterpartyName: row.readNullable<String>('counterparty'),
        ),
      );
    }

    // ── Sale Returns (linked) ──
    final saleReturnRows = await _db
        .customSelect(
          '''
      SELECT 
        sr.return_date AS dt,
        sr.return_number AS ref,
        sri.quantity AS qty,
        sri.refund_cents AS total,
        c.name AS counterparty
      FROM sale_return_items sri
      INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleReturn)} sr ON sr.id = sri.return_id
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
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleReturnItems,
            _db.saleReturns,
            _db.saleItems,
            _db.sales,
            _db.customers,
          },
        )
        .get();

    for (final row in saleReturnRows) {
      movements.add(
        StockMovementEntry(
          type: StockMovementType.saleReturn,
          date: DateTime.parse(row.read<String>('dt')),
          reference: row.read<String>('ref'),
          quantity: row.read<int>('qty'),
          measurementType: measurementType,
          totalCents: row.read<int>('total'),
          counterpartyName: row.readNullable<String>('counterparty'),
        ),
      );
    }

    // ── Sale Return Adjustments (unlinked) ──
    final saleAdjReturnRows = await _db
        .customSelect(
          '''
      SELECT 
        sra.return_date AS dt,
        sra.return_number AS ref,
        srai.quantity AS qty,
        srai.total_cents AS total,
        c.name AS counterparty
      FROM sale_return_adjustment_items srai
      INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.saleAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.saleAdjustment)} sra ON sra.id = srai.return_id
      LEFT JOIN customers c ON c.id = sra.customer_id
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
            ...WarehouseDocumentScope.dependencies(_db),
            _db.saleReturnAdjustmentItems,
            _db.saleReturnAdjustments,
            _db.customers,
          },
        )
        .get();

    for (final row in saleAdjReturnRows) {
      movements.add(
        StockMovementEntry(
          type: StockMovementType.saleReturnAdjustment,
          date: DateTime.parse(row.read<String>('dt')),
          reference: row.read<String>('ref'),
          quantity: row.read<int>('qty'),
          measurementType: measurementType,
          totalCents: row.read<int>('total'),
          counterpartyName: row.readNullable<String>('counterparty'),
        ),
      );
    }

    // ── Purchase Returns (linked) ──
    final purchaseReturnRows = await _db
        .customSelect(
          '''
      SELECT 
        pr.return_date AS dt,
        pr.return_number AS ref,
        pri.quantity AS qty,
        pri.refund_cents AS total,
        sup.name AS counterparty
      FROM purchase_return_items pri
      INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.purchaseReturn) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchaseReturn)} pr ON pr.id = pri.return_id
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
          readsFrom: {
            ...WarehouseDocumentScope.dependencies(_db),
            _db.purchaseReturnItems,
            _db.purchaseReturns,
            _db.purchaseItems,
            _db.purchases,
            _db.suppliers,
          },
        )
        .get();

    for (final row in purchaseReturnRows) {
      movements.add(
        StockMovementEntry(
          type: StockMovementType.purchaseReturn,
          date: DateTime.parse(row.read<String>('dt')),
          reference: row.read<String>('ref'),
          quantity: row.read<int>('qty'),
          measurementType: measurementType,
          totalCents: row.read<int>('total'),
          counterpartyName: row.readNullable<String>('counterparty'),
        ),
      );
    }

    // ── Purchase Return Adjustments (unlinked) ──
    final purchaseAdjReturnRows = await _db
        .customSelect(
          '''
      SELECT 
        pra.return_date AS dt,
        pra.return_number AS ref,
        prai.quantity AS qty,
        prai.total_cents AS total,
        sup.name AS counterparty
      FROM purchase_return_adjustment_items prai
      INNER JOIN ${warehouseScope?.documents(InventoryPostingDocument.purchaseAdjustment) ?? WarehouseDocumentScope.primaryDocuments(InventoryPostingDocument.purchaseAdjustment)} pra ON pra.id = prai.return_id
      LEFT JOIN suppliers sup ON sup.id = pra.supplier_id
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
            ...WarehouseDocumentScope.dependencies(_db),
            _db.purchaseReturnAdjustmentItems,
            _db.purchaseReturnAdjustments,
            _db.suppliers,
          },
        )
        .get();

    for (final row in purchaseAdjReturnRows) {
      movements.add(
        StockMovementEntry(
          type: StockMovementType.purchaseReturnAdjustment,
          date: DateTime.parse(row.read<String>('dt')),
          reference: row.read<String>('ref'),
          quantity: row.read<int>('qty'),
          measurementType: measurementType,
          totalCents: row.read<int>('total'),
          counterpartyName: row.readNullable<String>('counterparty'),
        ),
      );
    }

    // Sort all movements by date descending
    movements.sort((a, b) => b.date.compareTo(a.date));

    // Compute summary
    int totalPurchased = 0,
        totalSold = 0,
        totalSaleReturned = 0,
        totalSaleReturnAdj = 0,
        totalPurchaseReturned = 0,
        totalPurchaseReturnAdj = 0;
    int totalPurchaseCents = 0,
        totalSalesCents = 0,
        totalSaleReturnCents = 0,
        totalSaleReturnAdjCents = 0,
        totalPurchaseReturnCents = 0,
        totalPurchaseReturnAdjCents = 0;

    for (final m in movements) {
      switch (m.type) {
        case StockMovementType.purchase:
          totalPurchased += m.quantity;
          totalPurchaseCents += m.totalCents;
        case StockMovementType.sale:
          totalSold += m.quantity;
          totalSalesCents += m.totalCents;
        case StockMovementType.saleReturn:
          totalSaleReturned += m.quantity;
          totalSaleReturnCents += m.totalCents;
        case StockMovementType.saleReturnAdjustment:
          totalSaleReturnAdj += m.quantity;
          totalSaleReturnAdjCents += m.totalCents;
        case StockMovementType.purchaseReturn:
          totalPurchaseReturned += m.quantity;
          totalPurchaseReturnCents += m.totalCents;
        case StockMovementType.purchaseReturnAdjustment:
          totalPurchaseReturnAdj += m.quantity;
          totalPurchaseReturnAdjCents += m.totalCents;
      }
    }

    return StockMovementReportData(
      dateRange: _dateRange,
      searchQuery: _searchQuery,
      selectedProductId: productId,
      selectedProductName: productName,
      movementTypeFilter: _movementTypeFilter,
      movements: movements,
      summary: StockMovementSummary(
        measurementType: movements.isEmpty
            ? 'piece'
            : movements.first.measurementType,
        totalPurchased: totalPurchased,
        totalSold: totalSold,
        totalSaleReturned: totalSaleReturned,
        totalSaleReturnAdj: totalSaleReturnAdj,
        totalPurchaseReturned: totalPurchaseReturned,
        totalPurchaseReturnAdj: totalPurchaseReturnAdj,
        totalPurchaseCents: totalPurchaseCents,
        totalSalesCents: totalSalesCents,
        totalSaleReturnCents: totalSaleReturnCents,
        totalSaleReturnAdjCents: totalSaleReturnAdjCents,
        totalPurchaseReturnCents: totalPurchaseReturnCents,
        totalPurchaseReturnAdjCents: totalPurchaseReturnAdjCents,
      ),
    );
  }

  Future<List<StockProductSearchResult>> _searchProducts(String query) async {
    final likeQuery = '%$query%';
    final rows = await _db
        .customSelect(
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
        )
        .get();

    return rows
        .map(
          (row) => StockProductSearchResult(
            productId: row.read<int>('id'),
            name: row.read<String>('name'),
            sku: row.readNullable<String>('sku'),
            barcode: row.readNullable<String>('barcode'),
          ),
        )
        .toList();
  }
}
