import '../../../reports/presentation/screens/supplier_sales_report_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'warehouse_transfer_report_screen.dart';
import 'synced_location_report_screen.dart';
import 'package:flutter/material.dart';
import '../../../../core/services/business/warehouse_read_scope.dart';
import '../../data/warehouse_setup_service.dart';
import '../../data/synced_location_report_service.dart';
import '../../../reports/presentation/widgets/warehouse_report_context.dart';
import '../../../reports/presentation/screens/customer_analysis_report_screen.dart';
import '../../../reports/presentation/screens/customer_invoices_report_screen.dart';
import '../../../reports/presentation/screens/salespeople_commission_report_screen.dart';
import '../../../reports/presentation/screens/supplier_stocktake_report_screen.dart';
import '../../../reports/presentation/screens/customer_sales_report_screen.dart';
import '../../../reports/presentation/screens/profit_report_screen.dart';
import '../../../reports/presentation/screens/supplier_invoices_report_screen.dart';
import '../../../reports/presentation/screens/sales_tax_report_screen.dart';
import '../../../reports/presentation/screens/purchase_report_screen.dart';
import '../../../reports/presentation/screens/discount_report_screen.dart';
import '../../../reports/presentation/screens/stock_movement_report_screen.dart';
import '../../../reports/presentation/screens/customer_sales_returns_reports_screen.dart';
import '../../../reports/presentation/screens/category_movement_screen.dart';
import '../../../reports/presentation/screens/inventory_reports_screen.dart';
import '../../../reports/presentation/screens/purchase_tax_report_screen.dart';
import '../../../reports/presentation/screens/product_movement_detail_screen.dart';
import '../../../reports/presentation/screens/sales_report_screen.dart';
import '../../../reports/presentation/screens/supplier_returns_report_screen.dart';
import '../../../reports/presentation/screens/product_variant_movement_screen.dart';
import '../../../reports/presentation/screens/top_customers_screen.dart';

enum _ReportAggregation { location, branch, company }

class WarehouseReportsScreen extends StatefulWidget {
  const WarehouseReportsScreen({
    super.key,
    required this.service,
    required this.warehouseId,
    this.syncedReportService,
  });
  final WarehouseSetupService service;
  final String warehouseId;
  final SyncedLocationReportService? syncedReportService;
  @override
  State<WarehouseReportsScreen> createState() => _WarehouseReportsScreenState();
}

class _WarehouseReportsScreenState extends State<WarehouseReportsScreen> {
  GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();
  List<WarehouseReportLocation> _locations = [];
  WarehouseReadScope? _scope;
  late String _selected = widget.warehouseId;
  bool _busy = true;
  bool _failed = false;
  _ReportAggregation _aggregation = _ReportAggregation.location;
  bool _showScopeControls = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failed = false;
      _scope = null;
    });
    try {
      final locations = await widget.service.reportLocations();
      if (locations.isEmpty) throw StateError('No report locations');
      if (!locations.any((location) => location.warehouse.id == _selected)) {
        _selected = locations.first.warehouse.id;
      }
      final scope = await widget.service.reportScope(_selected);
      if (mounted) {
        setState(() {
          _locations = locations;
          _scope = scope;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<WarehouseReportLocation> get _branchChoices {
    final byBranch = <String, WarehouseReportLocation>{};
    for (final location in _locations) {
      final current = byBranch[location.warehouse.branchId];
      if (current == null ||
          (!current.isBranchLocation && location.isBranchLocation)) {
        byBranch[location.warehouse.branchId] = location;
      }
    }
    return byBranch.values.toList(growable: false);
  }

  String _branchRepresentative(String branchId) {
    return _branchChoices
        .firstWhere((location) => location.warehouse.branchId == branchId)
        .warehouse
        .id;
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final location = scope == null
        ? null
        : _locations.firstWhere((item) => item.warehouse.id == _selected);
    final syncedScope = location == null
        ? null
        : switch (_aggregation) {
            _ReportAggregation.location => SyncedReportScope.location(
              branchId: location.warehouse.branchId,
              warehouseId: location.warehouse.id,
            ),
            _ReportAggregation.branch => SyncedReportScope.branch(
              location.warehouse.branchId,
            ),
            _ReportAggregation.company => const SyncedReportScope.company(),
          };
    final reportLabel = location == null
        ? ''
        : switch (_aggregation) {
            _ReportAggregation.location =>
              location.isBranchLocation
                  ? '${location.branchName} · ${'warehouse_reports.branch_location'.tr()}'
                  : '${location.branchName} · ${location.warehouse.name}',
            _ReportAggregation.branch =>
              'warehouse_reports.aggregate_branch'.tr(
                namedArgs: {'branch': location.branchName},
              ),
            _ReportAggregation.company =>
              'warehouse_reports.aggregate_company'.tr(),
          };
    return Scaffold(
      appBar: AppBar(title: Text('warehouse_reports.title'.tr())),
      body: SafeArea(
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : _failed || location == null || scope == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'warehouse_setup.unavailable'.tr(),
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: _load,
                      child: Text('warehouse_setup.retry'.tr()),
                    ),
                  ],
                ),
              )
            : WarehouseReportContext(
                scope: scope,
                name: location.isBranchLocation
                    ? location.branchName
                    : location.warehouse.name,
                code: location.warehouse.code,
                branchName: location.branchName,
                isBranchLocation: location.isBranchLocation,
                child: Column(
                  children: [
                    if (_showScopeControls)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final aggregation in _ReportAggregation.values)
                              ChoiceChip(
                                key: ValueKey(
                                  'report-scope-${aggregation.name}',
                                ),
                                selected: _aggregation == aggregation,
                                avatar: Icon(switch (aggregation) {
                                  _ReportAggregation.location =>
                                    Icons.location_on_outlined,
                                  _ReportAggregation.branch =>
                                    Icons.storefront_outlined,
                                  _ReportAggregation.company =>
                                    Icons.domain_outlined,
                                }, size: 18),
                                label: Text(
                                  'warehouse_reports.scope.${aggregation.name}'
                                      .tr(),
                                ),
                                onSelected: (selected) {
                                  if (!selected ||
                                      _aggregation == aggregation) {
                                    return;
                                  }
                                  final branchId = location.warehouse.branchId;
                                  setState(() {
                                    _aggregation = aggregation;
                                    if (aggregation ==
                                        _ReportAggregation.branch) {
                                      _selected = _branchRepresentative(
                                        branchId,
                                      );
                                    }
                                    _navigator = GlobalKey<NavigatorState>();
                                  });
                                  if (aggregation ==
                                      _ReportAggregation.branch) {
                                    _load();
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    if (_showScopeControls &&
                        _aggregation != _ReportAggregation.company)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: DropdownButtonFormField<String>(
                          initialValue: _selected,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText:
                                (_aggregation == _ReportAggregation.branch
                                        ? 'warehouse_reports.branch'
                                        : 'warehouse_reports.location')
                                    .tr(),
                            border: const OutlineInputBorder(),
                          ),
                          items:
                              (_aggregation == _ReportAggregation.branch
                                      ? _branchChoices
                                      : _locations)
                                  .map(
                                    (location) => DropdownMenuItem(
                                      value: location.warehouse.id,
                                      child: Row(
                                        children: [
                                          Icon(
                                            _aggregation ==
                                                        _ReportAggregation
                                                            .branch ||
                                                    location.isBranchLocation
                                                ? Icons.storefront_outlined
                                                : Icons.warehouse_outlined,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _aggregation ==
                                                      _ReportAggregation.branch
                                                  ? location.branchName
                                                  : location.isBranchLocation
                                                  ? '${location.branchName} · ${'warehouse_reports.branch_location'.tr()}'
                                                  : '${location.branchName} · ${location.warehouse.name} · ${location.warehouse.code}',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            if (value != null && value != _selected) {
                              _selected = value;
                              _navigator = GlobalKey<NavigatorState>();
                              _load();
                            }
                          },
                        ),
                      ),
                    Expanded(
                      child: NavigatorPopHandler<void>(
                        onPopWithResult: (_) => _navigator.currentState?.pop(),
                        child: Navigator(
                          key: _navigator,
                          onGenerateRoute: (_) => MaterialPageRoute<void>(
                            builder: (_) => _WarehouseReportList(
                              location: location,
                              allLocations: _locations,
                              syncedScope: syncedScope!,
                              reportLabel: reportLabel,
                              useNativeReports:
                                  _aggregation == _ReportAggregation.location &&
                                  location.isLocalBranch,
                              syncedReportService: widget.syncedReportService,
                              onReportVisibilityChanged: (visible) {
                                if (mounted) {
                                  setState(() => _showScopeControls = visible);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _WarehouseReportList extends StatefulWidget {
  const _WarehouseReportList({
    required this.location,
    required this.allLocations,
    required this.syncedScope,
    required this.reportLabel,
    required this.useNativeReports,
    required this.onReportVisibilityChanged,
    this.syncedReportService,
  });

  final WarehouseReportLocation location;
  final List<WarehouseReportLocation> allLocations;
  final SyncedReportScope syncedScope;
  final String reportLabel;
  final bool useNativeReports;
  final ValueChanged<bool> onReportVisibilityChanged;
  final SyncedLocationReportService? syncedReportService;

  @override
  State<_WarehouseReportList> createState() => _WarehouseReportListState();
}

class _WarehouseReportListState extends State<_WarehouseReportList> {
  String _search = '';
  static const _entries = <(String, Widget)>[
    ('reports.warehouse_transfers', WarehouseTransferReportScreen()),
    ('reports.sales_by_supplier', SupplierSalesReportScreen()),
    ('reports.customer_analysis', CustomerAnalysisReportScreen()),
    ('reports.customer_invoices_report', CustomerInvoicesReportScreen()),
    ('reports.salespeople_commission', SalespeopleCommissionReportScreen()),
    ('reports.supplier_stocktake', SupplierStocktakeReportScreen()),
    ('reports.customer_sales', CustomerSalesReportScreen()),
    (
      'reports.profit_overall',
      ProfitReportScreen(reportType: ProfitReportType.overall),
    ),
    (
      'reports.profit_by_product',
      ProfitReportScreen(reportType: ProfitReportType.byProduct),
    ),
    (
      'reports.profit_by_category',
      ProfitReportScreen(reportType: ProfitReportType.byCategory),
    ),
    (
      'reports.profit_by_customer',
      ProfitReportScreen(reportType: ProfitReportType.byCustomer),
    ),
    (
      'reports.profit_by_invoice',
      ProfitReportScreen(reportType: ProfitReportType.byInvoice),
    ),
    ('reports.supplier_invoices_report', SupplierInvoicesReportScreen()),
    ('reports.sales_tax_report', SalesTaxReportScreen()),
    (
      'reports.purchases_report',
      PurchaseReportScreen(reportType: PurchaseReportType.all),
    ),
    (
      'reports.cash_purchases',
      PurchaseReportScreen(reportType: PurchaseReportType.cash),
    ),
    (
      'reports.credit_purchases',
      PurchaseReportScreen(reportType: PurchaseReportType.credit),
    ),
    (
      'reports.card_purchases',
      PurchaseReportScreen(reportType: PurchaseReportType.card),
    ),
    (
      'reports.cheque_purchases',
      PurchaseReportScreen(reportType: PurchaseReportType.cheque),
    ),
    (
      'reports.purchases_by_product',
      PurchaseReportScreen(reportType: PurchaseReportType.byProduct),
    ),
    (
      'reports.purchases_by_category',
      PurchaseReportScreen(reportType: PurchaseReportType.byCategory),
    ),
    (
      'reports.purchases_by_supplier',
      PurchaseReportScreen(reportType: PurchaseReportType.bySupplier),
    ),
    (
      'reports.cancelled_purchases',
      PurchaseReportScreen(reportType: PurchaseReportType.cancelled),
    ),
    (
      'reports.purchase_orders',
      PurchaseReportScreen(reportType: PurchaseReportType.orders),
    ),
    (
      'reports.purchases_excel',
      PurchaseReportScreen(reportType: PurchaseReportType.excel),
    ),
    (
      'reports.purchases_excel_products',
      PurchaseReportScreen(reportType: PurchaseReportType.excelProducts),
    ),
    (
      'reports.discount_by_product',
      DiscountReportScreen(reportType: DiscountReportType.byProduct),
    ),
    (
      'reports.discount_by_category',
      DiscountReportScreen(reportType: DiscountReportType.byCategory),
    ),
    (
      'reports.discount_by_customer',
      DiscountReportScreen(reportType: DiscountReportType.byCustomer),
    ),
    (
      'reports.discount_by_invoice',
      DiscountReportScreen(reportType: DiscountReportType.byInvoice),
    ),
    ('reports.stock_movement_report', StockMovementReportScreen()),
    ('reports.customer_returns', CustomerSalesReturnsReportsScreen()),
    ('reports.category_movement_report', CategoryMovementScreen()),
    ('reports.inventory_reports', InventoryReportsScreen()),
    ('reports.purchase_tax_report', PurchaseTaxReportScreen()),
    ('reports.product_movement_detail', ProductMovementDetailScreen()),
    (
      'reports.sales_by_period',
      SalesReportScreen(reportType: SalesReportType.byPeriod),
    ),
    ('reports.cash_sales', SalesReportScreen(reportType: SalesReportType.cash)),
    (
      'reports.credit_sales',
      SalesReportScreen(reportType: SalesReportType.credit),
    ),
    ('reports.card_sales', SalesReportScreen(reportType: SalesReportType.card)),
    (
      'reports.cheque_sales',
      SalesReportScreen(reportType: SalesReportType.cheque),
    ),
    ('reports.all_sales', SalesReportScreen(reportType: SalesReportType.all)),
    (
      'reports.sales_by_product',
      SalesReportScreen(reportType: SalesReportType.byProduct),
    ),
    (
      'reports.sales_by_category',
      SalesReportScreen(reportType: SalesReportType.byCategory),
    ),
    (
      'reports.sales_by_customer',
      SalesReportScreen(reportType: SalesReportType.byCustomer),
    ),
    (
      'reports.cancelled_invoices',
      SalesReportScreen(reportType: SalesReportType.cancelled),
    ),
    (
      'reports.tax_by_product',
      SalesReportScreen(reportType: SalesReportType.taxByProduct),
    ),
    (
      'reports.tax_by_customer',
      SalesReportScreen(reportType: SalesReportType.taxByCustomer),
    ),
    (
      'reports.sales_excel',
      SalesReportScreen(reportType: SalesReportType.excel),
    ),
    (
      'reports.sales_excel_products',
      SalesReportScreen(reportType: SalesReportType.excelProducts),
    ),
    ('reports.supplier_returns_report', SupplierReturnsReportScreen()),
    ('reports.variant_movement_report', ProductVariantMovementScreen()),
    ('reports.top_customers', TopCustomersScreen()),
  ];
  @override
  Widget build(BuildContext context) {
    final entries = _entries
        .where((e) => e.$1.tr().toLowerCase().contains(_search.toLowerCase()))
        .toList();
    return Material(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: 'warehouse_reports.search'.tr(),
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _search = value),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: constraints.maxWidth >= 800
                          ? 3
                          : constraints.maxWidth >= 560
                          ? 2
                          : 1,
                      mainAxisExtent: 88,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) => Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () async {
                          final entry = entries[index];
                          final transfer =
                              entry.$1 == 'reports.warehouse_transfers';
                          final aggregateTransfer =
                              transfer &&
                              widget.syncedScope.kind !=
                                  SyncedReportScopeKind.location;
                          final transferWarehouses = widget.allLocations
                              .where(
                                (item) =>
                                    widget.syncedScope.kind ==
                                        SyncedReportScopeKind.company ||
                                    item.warehouse.branchId ==
                                        widget.syncedScope.branchId,
                              )
                              .map((item) => item.warehouse.id)
                              .toSet();
                          final destination = aggregateTransfer
                              ? WarehouseTransferReportScreen(
                                  warehouseIds: transferWarehouses,
                                  scopeLabel: widget.reportLabel,
                                )
                              : widget.useNativeReports || transfer
                              ? entry.$2
                              : SyncedLocationReportScreen(
                                  reportKey: entry.$1,
                                  scope: widget.syncedScope,
                                  locationLabel: widget.reportLabel,
                                  service: widget.syncedReportService,
                                );
                          widget.onReportVisibilityChanged(false);
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => destination,
                            ),
                          );
                          widget.onReportVisibilityChanged(true);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                Icons.analytics_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  entries[index].$1.tr(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
