import '../../../reports/presentation/screens/supplier_sales_report_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart' show BusinessWarehouse;
import '../../../../core/services/business/warehouse_read_scope.dart';
import '../../data/warehouse_setup_service.dart';
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

class WarehouseReportsScreen extends StatefulWidget {
  const WarehouseReportsScreen({
    super.key,
    required this.service,
    required this.warehouseId,
  });
  final WarehouseSetupService service;
  final String warehouseId;
  @override
  State<WarehouseReportsScreen> createState() => _WarehouseReportsScreenState();
}

class _WarehouseReportsScreenState extends State<WarehouseReportsScreen> {
  final _navigator = GlobalKey<NavigatorState>();
  List<BusinessWarehouse> _warehouses = [];
  WarehouseReadScope? _scope;
  late String _selected = widget.warehouseId;
  bool _busy = true;
  bool _failed = false;
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
      final warehouses = await widget.service.warehouses();
      if (!warehouses.any((w) => w.id == _selected)) {
        throw StateError('Warehouse access changed');
      }
      final scope = await widget.service.reportScope(_selected);
      if (mounted) {
        setState(() {
          _warehouses = warehouses;
          _scope = scope;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final warehouse = scope == null
        ? null
        : _warehouses.firstWhere((w) => w.id == _selected);
    return Scaffold(
      appBar: AppBar(title: Text('warehouse_reports.title'.tr())),
      body: SafeArea(
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : _failed || warehouse == null || scope == null
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
                name: warehouse.name,
                code: warehouse.code,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: DropdownButtonFormField<String>(
                        initialValue: _selected,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'warehouse_setup.warehouse'.tr(),
                          border: const OutlineInputBorder(),
                        ),
                        items: _warehouses
                            .map(
                              (w) => DropdownMenuItem(
                                value: w.id,
                                child: Text(
                                  '${w.name} · ${w.code}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null && value != _selected) {
                            _selected = value;
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
                            builder: (_) => const _WarehouseReportList(),
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
  const _WarehouseReportList();
  @override
  State<_WarehouseReportList> createState() => _WarehouseReportListState();
}

class _WarehouseReportListState extends State<_WarehouseReportList> {
  String _search = '';
  static const _entries = <(String, Widget)>[
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
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => entries[index].$2,
                          ),
                        ),
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
