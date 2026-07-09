import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../bloc/sales_reports_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../../services/sales_reports_pdf_service.dart';
import '../../services/sales_reports_excel_service.dart';

/// The type of sales report to display
enum SalesReportType {
  byPeriod,
  cash,
  credit,
  card,
  cheque,
  all,
  byProduct,
  byCategory,
  byCustomer,
  cancelled,
  taxByProduct,
  taxByCustomer,
  excel,
  excelProducts,
}

class SalesReportScreen extends StatelessWidget {
  final SalesReportType reportType;
  const SalesReportScreen({super.key, required this.reportType});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SalesReportsBloc>(),
      child: _SalesReportView(reportType: reportType),
    );
  }
}

class _SalesReportView extends StatefulWidget {
  final SalesReportType reportType;
  const _SalesReportView({required this.reportType});

  @override
  State<_SalesReportView> createState() => _SalesReportViewState();
}

class _SalesReportViewState extends State<_SalesReportView> {
  String _searchQuery = '';

  String _title() {
    switch (widget.reportType) {
      case SalesReportType.byPeriod:
        return 'reports.sales_by_period'.tr();
      case SalesReportType.cash:
        return 'reports.cash_sales'.tr();
      case SalesReportType.credit:
        return 'reports.credit_sales'.tr();
      case SalesReportType.card:
        return 'reports.card_sales'.tr();
      case SalesReportType.cheque:
        return 'reports.cheque_sales'.tr();
      case SalesReportType.all:
        return 'reports.all_sales'.tr();
      case SalesReportType.byProduct:
        return 'reports.sales_by_product'.tr();
      case SalesReportType.byCategory:
        return 'reports.sales_by_category'.tr();
      case SalesReportType.byCustomer:
        return 'reports.sales_by_customer'.tr();
      case SalesReportType.cancelled:
        return 'reports.cancelled_invoices'.tr();
      case SalesReportType.taxByProduct:
        return 'reports.tax_by_product'.tr();
      case SalesReportType.taxByCustomer:
        return 'reports.tax_by_customer'.tr();
      case SalesReportType.excel:
        return 'reports.sales_excel'.tr();
      case SalesReportType.excelProducts:
        return 'reports.sales_excel_products'.tr();
    }
  }

  bool get _hasSearch =>
      widget.reportType == SalesReportType.byProduct ||
      widget.reportType == SalesReportType.byCategory ||
      widget.reportType == SalesReportType.byCustomer ||
      widget.reportType == SalesReportType.taxByProduct ||
      widget.reportType == SalesReportType.taxByCustomer;

  String get _searchHint {
    switch (widget.reportType) {
      case SalesReportType.byProduct:
      case SalesReportType.taxByProduct:
        return 'reports.search_product_hint'.tr();
      case SalesReportType.byCategory:
        return 'reports.search_category_hint'.tr();
      case SalesReportType.byCustomer:
      case SalesReportType.taxByCustomer:
        return 'reports.search_customers'.tr();
      default:
        return '';
    }
  }

  void _onPrint(BuildContext context, SalesReportsData data) {
    switch (widget.reportType) {
      case SalesReportType.byPeriod:
      case SalesReportType.all:
        SalesReportsPdfService.printInvoiceList(context: context, title: _title(), invoices: data.allSales, data: data);
      case SalesReportType.cash:
        SalesReportsPdfService.printInvoiceList(context: context, title: _title(), invoices: data.cashSales, data: data);
      case SalesReportType.credit:
        SalesReportsPdfService.printInvoiceList(context: context, title: _title(), invoices: data.creditSales, data: data);
      case SalesReportType.card:
        SalesReportsPdfService.printInvoiceList(context: context, title: _title(), invoices: data.cardSales, data: data);
      case SalesReportType.cheque:
        SalesReportsPdfService.printInvoiceList(context: context, title: _title(), invoices: data.chequeSales, data: data);
      case SalesReportType.byProduct:
        SalesReportsPdfService.printByProduct(context: context, items: data.byProduct, data: data);
      case SalesReportType.byCategory:
        SalesReportsPdfService.printByCategory(context: context, items: data.byCategory, data: data);
      case SalesReportType.byCustomer:
        SalesReportsPdfService.printByCustomer(context: context, items: data.byCustomer, data: data);
      case SalesReportType.cancelled:
        SalesReportsPdfService.printCancelled(context: context, items: data.cancelledInvoices, data: data);
      case SalesReportType.taxByProduct:
        SalesReportsPdfService.printTaxByProduct(context: context, items: data.taxByProduct, data: data);
      case SalesReportType.taxByCustomer:
        SalesReportsPdfService.printTaxByCustomer(context: context, items: data.taxByCustomer, data: data);
      default:
        break;
    }
  }

  void _onShare(BuildContext context, SalesReportsData data) {
    switch (widget.reportType) {
      case SalesReportType.byPeriod:
      case SalesReportType.all:
        SalesReportsPdfService.shareInvoiceList(context: context, title: _title(), invoices: data.allSales, data: data);
      case SalesReportType.cash:
        SalesReportsPdfService.shareInvoiceList(context: context, title: _title(), invoices: data.cashSales, data: data);
      case SalesReportType.credit:
        SalesReportsPdfService.shareInvoiceList(context: context, title: _title(), invoices: data.creditSales, data: data);
      case SalesReportType.card:
        SalesReportsPdfService.shareInvoiceList(context: context, title: _title(), invoices: data.cardSales, data: data);
      case SalesReportType.cheque:
        SalesReportsPdfService.shareInvoiceList(context: context, title: _title(), invoices: data.chequeSales, data: data);
      case SalesReportType.byProduct:
        SalesReportsPdfService.shareByProduct(context: context, items: data.byProduct, data: data);
      case SalesReportType.byCategory:
        SalesReportsPdfService.shareByCategory(context: context, items: data.byCategory, data: data);
      case SalesReportType.byCustomer:
        SalesReportsPdfService.shareByCustomer(context: context, items: data.byCustomer, data: data);
      case SalesReportType.cancelled:
        SalesReportsPdfService.shareCancelled(context: context, items: data.cancelledInvoices, data: data);
      case SalesReportType.taxByProduct:
        SalesReportsPdfService.shareTaxByProduct(context: context, items: data.taxByProduct, data: data);
      case SalesReportType.taxByCustomer:
        SalesReportsPdfService.shareTaxByCustomer(context: context, items: data.taxByCustomer, data: data);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isExcel = widget.reportType == SalesReportType.excel || widget.reportType == SalesReportType.excelProducts;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
        actions: [
          if (!isExcel)
            BlocBuilder<SalesReportsBloc, RealtimeState<SalesReportsData>>(
              builder: (context, state) {
                if (state is! RealtimeSuccess<SalesReportsData>) return const SizedBox.shrink();
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.printer),
                      tooltip: 'reports.print'.tr(),
                      onPressed: () => _onPrint(context, state.data),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.share2),
                      tooltip: 'reports.share'.tr(),
                      onPressed: () => _onShare(context, state.data),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
      body: BlocBuilder<SalesReportsBloc, RealtimeState<SalesReportsData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<SalesReportsData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<SalesReportsData>) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(state.error.toString(), style: theme.textTheme.bodyLarge),
                ],
              ),
            );
          }

          if (state is RealtimeSuccess<SalesReportsData>) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<SalesReportsBloc>()
                        .add(SalesReportsDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 8),
                _buildSummary(context, state.data),
                if (_hasSearch) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: _searchHint,
                        prefixIcon: const Icon(LucideIcons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(LucideIcons.x, size: 18),
                                onPressed: () => setState(() => _searchQuery = ''),
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(child: _buildContent(context, state.data)),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSummary(BuildContext context, SalesReportsData data) {
    final cs = sl<CurrencyService>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    int totalCents;
    int count;
    String countLabel;

    switch (widget.reportType) {
      case SalesReportType.cash:
        totalCents = data.summary.cashSalesCents;
        count = data.cashSales.length;
        countLabel = 'reports.invoice_count'.tr();
      case SalesReportType.credit:
        totalCents = data.summary.creditSalesCents;
        count = data.creditSales.length;
        countLabel = 'reports.invoice_count'.tr();
      case SalesReportType.card:
        totalCents = data.summary.cardSalesCents;
        count = data.cardSales.length;
        countLabel = 'reports.invoice_count'.tr();
      case SalesReportType.cheque:
        totalCents = data.summary.chequeSalesCents;
        count = data.chequeSales.length;
        countLabel = 'reports.invoice_count'.tr();
      case SalesReportType.byProduct:
        totalCents = data.summary.totalSalesCents;
        count = data.byProduct.length;
        countLabel = 'reports.product_count'.tr();
      case SalesReportType.byCategory:
        totalCents = data.summary.totalSalesCents;
        count = data.byCategory.length;
        countLabel = 'reports.category_count'.tr();
      case SalesReportType.byCustomer:
        totalCents = data.summary.totalSalesCents;
        count = data.byCustomer.length;
        countLabel = 'reports.unique_customers'.tr();
      case SalesReportType.cancelled:
        totalCents = data.cancelledInvoices.fold(0, (sum, i) => sum + i.totalCents);
        count = data.cancelledInvoices.length;
        countLabel = 'reports.invoice_count'.tr();
      case SalesReportType.taxByProduct:
        totalCents = data.taxByProduct.fold(0, (sum, i) => sum + i.totalTaxCents);
        count = data.taxByProduct.length;
        countLabel = 'reports.product_count'.tr();
      case SalesReportType.taxByCustomer:
        totalCents = data.taxByCustomer.fold(0, (sum, i) => sum + i.totalTaxCents);
        count = data.taxByCustomer.length;
        countLabel = 'reports.unique_customers'.tr();
      default:
        totalCents = data.summary.totalSalesCents;
        count = data.summary.invoiceCount;
        countLabel = 'reports.invoice_count'.tr();
    }

    final showNet = widget.reportType == SalesReportType.byPeriod ||
        widget.reportType == SalesReportType.all;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: widget.reportType == SalesReportType.taxByProduct ||
                          widget.reportType == SalesReportType.taxByCustomer
                      ? 'reports.total_tax'.tr()
                      : 'reports.total_sales'.tr(),
                  value: cs.formatCents(totalCents),
                  icon: LucideIcons.shoppingCart,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  label: countLabel,
                  value: count.toString(),
                  icon: LucideIcons.receipt,
                  color: colorScheme.tertiary,
                ),
              ),
              if (showNet) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(
                    label: 'reports.total_discount'.tr(),
                    value: cs.formatCents(data.summary.totalDiscountCents),
                    icon: LucideIcons.percent,
                    color: colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
          if (showNet) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    label: 'reports.total_returns_period'.tr(),
                    value: cs.formatCents(data.summary.totalReturnsCents),
                    icon: LucideIcons.undo2,
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(
                    label: 'reports.net_sales'.tr(),
                    value: cs.formatCents(data.summary.netSalesCents),
                    icon: LucideIcons.trendingUp,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, SalesReportsData data) {
    switch (widget.reportType) {
      case SalesReportType.byPeriod:
      case SalesReportType.all:
        return _InvoiceListView(invoices: data.allSales);
      case SalesReportType.cash:
        return _InvoiceListView(invoices: data.cashSales);
      case SalesReportType.credit:
        return _InvoiceListView(invoices: data.creditSales);
      case SalesReportType.card:
        return _InvoiceListView(invoices: data.cardSales);
      case SalesReportType.cheque:
        return _InvoiceListView(invoices: data.chequeSales);
      case SalesReportType.byProduct:
        return _ProductListView(items: _filterProducts(data.byProduct));
      case SalesReportType.byCategory:
        return _CategoryListView(items: _filterCategories(data.byCategory));
      case SalesReportType.byCustomer:
        return _CustomerListView(items: _filterCustomers(data.byCustomer));
      case SalesReportType.cancelled:
        return _CancelledListView(items: data.cancelledInvoices);
      case SalesReportType.taxByProduct:
        return _TaxByProductView(items: _filterTaxProducts(data.taxByProduct));
      case SalesReportType.taxByCustomer:
        return _TaxByCustomerView(items: _filterTaxCustomers(data.taxByCustomer));
      case SalesReportType.excel:
      case SalesReportType.excelProducts:
        return _ExcelExportView(
          data: data,
          includeProducts: widget.reportType == SalesReportType.excelProducts,
        );
    }
  }

  List<SalesByProductItem> _filterProducts(List<SalesByProductItem> items) {
    if (_searchQuery.isEmpty) return items;
    return items.where((p) =>
        p.productName.toLowerCase().contains(_searchQuery) ||
        (p.categoryName?.toLowerCase().contains(_searchQuery) ?? false)).toList();
  }

  List<SalesByCategoryItem> _filterCategories(List<SalesByCategoryItem> items) {
    if (_searchQuery.isEmpty) return items;
    return items.where((c) => c.categoryName.toLowerCase().contains(_searchQuery)).toList();
  }

  List<SalesByCustomerItem> _filterCustomers(List<SalesByCustomerItem> items) {
    if (_searchQuery.isEmpty) return items;
    return items.where((c) => c.customerName.toLowerCase().contains(_searchQuery)).toList();
  }

  List<TaxByProductItem> _filterTaxProducts(List<TaxByProductItem> items) {
    if (_searchQuery.isEmpty) return items;
    return items.where((t) => t.productName.toLowerCase().contains(_searchQuery)).toList();
  }

  List<TaxByCustomerItem> _filterTaxCustomers(List<TaxByCustomerItem> items) {
    if (_searchQuery.isEmpty) return items;
    return items.where((t) => t.customerName.toLowerCase().contains(_searchQuery)).toList();
  }
}

// ═══════════════════════════════════════════════════════
// SUMMARY CARD
// ═══════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// INVOICE LIST VIEW (Period, Cash, Credit, Card, Cheque, All)
// ═══════════════════════════════════════════════════════

class _InvoiceListView extends StatelessWidget {
  final List<SaleInvoiceItem> invoices;
  const _InvoiceListView({required this.invoices});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (invoices.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.shoppingCart,
        message: 'reports.no_sales_data'.tr(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 8,
          columns: [
            const DataColumn(label: Text('#'), numeric: true),
            DataColumn(label: Text('reports.invoice_number'.tr())),
            DataColumn(label: Text('reports.customer'.tr())),
            DataColumn(label: Text('reports.subtotal'.tr()), numeric: true),
            DataColumn(label: Text('reports.discount'.tr()), numeric: true),
            DataColumn(label: Text('reports.tax'.tr()), numeric: true),
            DataColumn(label: Text('reports.total'.tr()), numeric: true),
            DataColumn(label: Text('reports.paid'.tr()), numeric: true),
            DataColumn(label: Text('reports.payment_method_col'.tr())),
            DataColumn(label: Text('reports.date'.tr())),
          ],
          rows: invoices.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final s = entry.value;
            return DataRow(cells: [
              DataCell(Text('$idx')),
              DataCell(Text(s.invoiceNumber)),
              DataCell(Text(s.customerName ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis)),
              DataCell(Text(cs.formatCents(s.subtotalCents))),
              DataCell(Text(cs.formatCents(s.discountCents))),
              DataCell(Text(cs.formatCents(s.taxCents))),
              DataCell(Text(
                cs.formatCents(s.totalCents),
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              )),
              DataCell(Text(cs.formatCents(s.paidAmountCents))),
              DataCell(Text(_paymentMethodLabel(s.paymentMethod))),
              DataCell(Text(DateFormat.yMd().format(s.saleDate))),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  String _paymentMethodLabel(String method) {
    switch (method) {
      case 'cash':
        return 'sales.payment_cash'.tr();
      case 'credit':
        return 'sales.payment_credit'.tr();
      case 'card':
        return 'sales.payment_card'.tr();
      case 'cheque':
        return 'sales.payment_cheque'.tr();
      default:
        return method;
    }
  }
}

// ═══════════════════════════════════════════════════════
// PRODUCT LIST VIEW
// ═══════════════════════════════════════════════════════

class _ProductListView extends StatelessWidget {
  final List<SalesByProductItem> items;
  const _ProductListView({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (items.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.package2,
        message: 'reports.no_sales_data'.tr(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 8,
          columns: [
            const DataColumn(label: Text('#'), numeric: true),
            DataColumn(label: Text('reports.product'.tr())),
            DataColumn(label: Text('reports.category'.tr())),
            DataColumn(label: Text('reports.quantity'.tr()), numeric: true),
            DataColumn(label: Text('reports.total_sales'.tr()), numeric: true),
            DataColumn(label: Text('reports.discount'.tr()), numeric: true),
            DataColumn(label: Text('reports.tax'.tr()), numeric: true),
            DataColumn(label: Text('reports.invoices'.tr()), numeric: true),
          ],
          rows: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final p = entry.value;
            return DataRow(cells: [
              DataCell(Text('$idx')),
              DataCell(Text(p.productName, maxLines: 1, overflow: TextOverflow.ellipsis)),
              DataCell(Text(p.categoryName ?? '-')),
              DataCell(Text('${p.totalQuantity}')),
              DataCell(Text(
                cs.formatCents(p.totalSalesCents),
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              )),
              DataCell(Text(cs.formatCents(p.totalDiscountCents))),
              DataCell(Text(cs.formatCents(p.totalTaxCents))),
              DataCell(Text('${p.invoiceCount}')),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CATEGORY LIST VIEW
// ═══════════════════════════════════════════════════════

class _CategoryListView extends StatelessWidget {
  final List<SalesByCategoryItem> items;
  const _CategoryListView({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (items.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.folderOpen,
        message: 'reports.no_sales_data'.tr(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 8,
          columns: [
            const DataColumn(label: Text('#'), numeric: true),
            DataColumn(label: Text('reports.category'.tr())),
            DataColumn(label: Text('reports.product_count'.tr()), numeric: true),
            DataColumn(label: Text('reports.quantity'.tr()), numeric: true),
            DataColumn(label: Text('reports.total_sales'.tr()), numeric: true),
            DataColumn(label: Text('reports.discount'.tr()), numeric: true),
            DataColumn(label: Text('reports.tax'.tr()), numeric: true),
            DataColumn(label: Text('reports.invoices'.tr()), numeric: true),
          ],
          rows: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final c = entry.value;
            return DataRow(cells: [
              DataCell(Text('$idx')),
              DataCell(Text(c.categoryName, maxLines: 1, overflow: TextOverflow.ellipsis)),
              DataCell(Text('${c.productCount}')),
              DataCell(Text('${c.totalQuantity}')),
              DataCell(Text(
                cs.formatCents(c.totalSalesCents),
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              )),
              DataCell(Text(cs.formatCents(c.totalDiscountCents))),
              DataCell(Text(cs.formatCents(c.totalTaxCents))),
              DataCell(Text('${c.invoiceCount}')),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CUSTOMER LIST VIEW
// ═══════════════════════════════════════════════════════

class _CustomerListView extends StatelessWidget {
  final List<SalesByCustomerItem> items;
  const _CustomerListView({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (items.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.users,
        message: 'reports.no_sales_data'.tr(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 8,
          columns: [
            const DataColumn(label: Text('#'), numeric: true),
            DataColumn(label: Text('reports.customer'.tr())),
            DataColumn(label: Text('reports.total_sales'.tr()), numeric: true),
            DataColumn(label: Text('reports.discount'.tr()), numeric: true),
            DataColumn(label: Text('reports.tax'.tr()), numeric: true),
            DataColumn(label: Text('reports.invoices'.tr()), numeric: true),
            DataColumn(label: Text('reports.quantity'.tr()), numeric: true),
            DataColumn(label: Text('reports.last_sale'.tr())),
          ],
          rows: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final c = entry.value;
            return DataRow(cells: [
              DataCell(Text('$idx')),
              DataCell(Text(c.customerName, maxLines: 1, overflow: TextOverflow.ellipsis)),
              DataCell(Text(
                cs.formatCents(c.totalSalesCents),
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              )),
              DataCell(Text(cs.formatCents(c.totalDiscountCents))),
              DataCell(Text(cs.formatCents(c.totalTaxCents))),
              DataCell(Text('${c.invoiceCount}')),
              DataCell(Text('${c.totalQuantity}')),
              DataCell(Text(
                c.lastSaleDate != null ? DateFormat.yMd().format(c.lastSaleDate!) : '-',
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CANCELLED INVOICES VIEW
// ═══════════════════════════════════════════════════════

class _CancelledListView extends StatelessWidget {
  final List<CancelledInvoiceItem> items;
  const _CancelledListView({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (items.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.ban,
        message: 'reports.no_cancelled_invoices'.tr(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 8,
          columns: [
            const DataColumn(label: Text('#'), numeric: true),
            DataColumn(label: Text('reports.invoice_number'.tr())),
            DataColumn(label: Text('reports.customer'.tr())),
            DataColumn(label: Text('reports.total'.tr()), numeric: true),
            DataColumn(label: Text('reports.date'.tr())),
            DataColumn(label: Text('reports.notes'.tr())),
          ],
          rows: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final i = entry.value;
            return DataRow(cells: [
              DataCell(Text('$idx')),
              DataCell(Text(i.invoiceNumber)),
              DataCell(Text(i.customerName ?? '-')),
              DataCell(Text(
                cs.formatCents(i.totalCents),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.error,
                ),
              )),
              DataCell(Text(DateFormat.yMd().format(i.saleDate))),
              DataCell(Text(i.notes ?? '-', maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// TAX BY PRODUCT VIEW
// ═══════════════════════════════════════════════════════

class _TaxByProductView extends StatelessWidget {
  final List<TaxByProductItem> items;
  const _TaxByProductView({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (items.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.receipt,
        message: 'reports.no_tax_data'.tr(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 8,
          columns: [
            const DataColumn(label: Text('#'), numeric: true),
            DataColumn(label: Text('reports.product'.tr())),
            DataColumn(label: Text('reports.total_sales'.tr()), numeric: true),
            DataColumn(label: Text('reports.tax_rate'.tr()), numeric: true),
            DataColumn(label: Text('reports.total_tax'.tr()), numeric: true),
            DataColumn(label: Text('reports.quantity'.tr()), numeric: true),
          ],
          rows: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final t = entry.value;
            return DataRow(cells: [
              DataCell(Text('$idx')),
              DataCell(Text(t.productName, maxLines: 1, overflow: TextOverflow.ellipsis)),
              DataCell(Text(cs.formatCents(t.totalSalesCents))),
              DataCell(Text('${(t.taxRateBps / 100).toStringAsFixed(1)}%')),
              DataCell(Text(
                cs.formatCents(t.totalTaxCents),
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              )),
              DataCell(Text('${t.totalQuantity}')),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// TAX BY CUSTOMER VIEW
// ═══════════════════════════════════════════════════════

class _TaxByCustomerView extends StatelessWidget {
  final List<TaxByCustomerItem> items;
  const _TaxByCustomerView({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (items.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.userCheck,
        message: 'reports.no_tax_data'.tr(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 8,
          columns: [
            const DataColumn(label: Text('#'), numeric: true),
            DataColumn(label: Text('reports.customer'.tr())),
            DataColumn(label: Text('reports.total_sales'.tr()), numeric: true),
            DataColumn(label: Text('reports.total_tax'.tr()), numeric: true),
            DataColumn(label: Text('reports.invoices'.tr()), numeric: true),
          ],
          rows: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final t = entry.value;
            return DataRow(cells: [
              DataCell(Text('$idx')),
              DataCell(Text(t.customerName, maxLines: 1, overflow: TextOverflow.ellipsis)),
              DataCell(Text(cs.formatCents(t.totalSalesCents))),
              DataCell(Text(
                cs.formatCents(t.totalTaxCents),
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              )),
              DataCell(Text('${t.invoiceCount}')),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// EXCEL EXPORT VIEW
// ═══════════════════════════════════════════════════════

class _ExcelExportView extends StatefulWidget {
  final SalesReportsData data;
  final bool includeProducts;
  const _ExcelExportView({required this.data, required this.includeProducts});

  @override
  State<_ExcelExportView> createState() => _ExcelExportViewState();
}

class _ExcelExportViewState extends State<_ExcelExportView> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      if (widget.includeProducts) {
        await SalesReportsExcelService.exportSalesWithProducts(
          context: context,
          data: widget.data,
        );
      } else {
        await SalesReportsExcelService.exportSales(
          context: context,
          data: widget.data,
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.fileSpreadsheet, size: 64, color: Colors.green[700]),
            const SizedBox(height: 16),
            Text(
              widget.includeProducts
                  ? 'reports.sales_excel_products'.tr()
                  : 'reports.sales_excel'.tr(),
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'reports.sales_excel_hint'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _ExcelStat(
                      label: 'reports.total_sales'.tr(),
                      value: cs.formatCents(widget.data.summary.totalSalesCents),
                    ),
                    _ExcelStat(
                      label: 'reports.invoice_count'.tr(),
                      value: '${widget.data.summary.invoiceCount}',
                    ),
                    if (widget.includeProducts)
                      _ExcelStat(
                        label: 'reports.product_count'.tr(),
                        value: '${widget.data.byProduct.length}',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 220,
              child: FilledButton.icon(
                onPressed: _exporting ? null : _export,
                icon: _exporting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.download),
                label: Text(_exporting ? 'reports.exporting'.tr() : 'reports.export_excel'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExcelStat extends StatelessWidget {
  final String label;
  final String value;
  const _ExcelStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// EMPTY STATE
// ═══════════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(message, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
