import '../widgets/warehouse_report_context.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../bloc/purchase_reports_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/report_scrollable_center.dart';
import '../../services/purchase_reports_pdf_service.dart';
import '../../services/purchase_reports_excel_service.dart';

/// The type of purchase report to display
enum PurchaseReportType {
  all,
  cash,
  credit,
  card,
  cheque,
  byProduct,
  byCategory,
  bySupplier,
  cancelled,
  orders,
  excel,
  excelProducts,
}

class PurchaseReportScreen extends StatelessWidget {
  final PurchaseReportType reportType;
  const PurchaseReportScreen({super.key, required this.reportType});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<PurchaseReportsBloc>(
        param1: WarehouseReportContext.maybeOf(context)?.scope,
      ),
      child: _PurchaseReportView(reportType: reportType),
    );
  }
}

class _PurchaseReportView extends StatefulWidget {
  final PurchaseReportType reportType;
  const _PurchaseReportView({required this.reportType});

  @override
  State<_PurchaseReportView> createState() => _PurchaseReportViewState();
}

class _PurchaseReportViewState extends State<_PurchaseReportView> {
  String _searchQuery = '';

  String _title() {
    switch (widget.reportType) {
      case PurchaseReportType.all:
        return 'reports.purchases_report'.tr();
      case PurchaseReportType.cash:
        return 'reports.cash_purchases'.tr();
      case PurchaseReportType.credit:
        return 'reports.credit_purchases'.tr();
      case PurchaseReportType.card:
        return 'reports.card_purchases'.tr();
      case PurchaseReportType.cheque:
        return 'reports.cheque_purchases'.tr();
      case PurchaseReportType.byProduct:
        return 'reports.purchases_by_product'.tr();
      case PurchaseReportType.byCategory:
        return 'reports.purchases_by_category'.tr();
      case PurchaseReportType.bySupplier:
        return 'reports.purchases_by_supplier'.tr();
      case PurchaseReportType.cancelled:
        return 'reports.cancelled_purchases'.tr();
      case PurchaseReportType.orders:
        return 'reports.purchase_orders'.tr();
      case PurchaseReportType.excel:
        return 'reports.purchases_excel'.tr();
      case PurchaseReportType.excelProducts:
        return 'reports.purchases_excel_products'.tr();
    }
  }

  bool get _hasSearch =>
      widget.reportType == PurchaseReportType.byProduct ||
      widget.reportType == PurchaseReportType.byCategory ||
      widget.reportType == PurchaseReportType.bySupplier;

  String get _searchHint {
    switch (widget.reportType) {
      case PurchaseReportType.byProduct:
        return 'reports.search_product_hint'.tr();
      case PurchaseReportType.byCategory:
        return 'reports.search_category_hint'.tr();
      case PurchaseReportType.bySupplier:
        return 'reports.search_supplier_hint'.tr();
      default:
        return '';
    }
  }

  void _onPrint(BuildContext context, PurchaseReportsData data) {
    switch (widget.reportType) {
      case PurchaseReportType.all:
        PurchaseReportsPdfService.printInvoiceList(
          context: context,
          title: _title(),
          invoices: data.allPurchases,
          data: data,
        );
      case PurchaseReportType.cash:
        PurchaseReportsPdfService.printInvoiceList(
          context: context,
          title: _title(),
          invoices: data.cashPurchases,
          data: data,
        );
      case PurchaseReportType.credit:
        PurchaseReportsPdfService.printInvoiceList(
          context: context,
          title: _title(),
          invoices: data.creditPurchases,
          data: data,
        );
      case PurchaseReportType.card:
        PurchaseReportsPdfService.printInvoiceList(
          context: context,
          title: _title(),
          invoices: data.cardPurchases,
          data: data,
        );
      case PurchaseReportType.cheque:
        PurchaseReportsPdfService.printInvoiceList(
          context: context,
          title: _title(),
          invoices: data.chequePurchases,
          data: data,
        );
      case PurchaseReportType.byProduct:
        PurchaseReportsPdfService.printByProduct(
          context: context,
          items: data.byProduct,
          data: data,
        );
      case PurchaseReportType.byCategory:
        PurchaseReportsPdfService.printByCategory(
          context: context,
          items: data.byCategory,
          data: data,
        );
      case PurchaseReportType.bySupplier:
        PurchaseReportsPdfService.printBySupplier(
          context: context,
          items: data.bySupplier,
          data: data,
        );
      case PurchaseReportType.cancelled:
        PurchaseReportsPdfService.printCancelled(
          context: context,
          items: data.cancelledInvoices,
          data: data,
        );
      case PurchaseReportType.orders:
        PurchaseReportsPdfService.printOrders(
          context: context,
          items: data.purchaseOrders,
          data: data,
        );
      default:
        break;
    }
  }

  void _onShare(BuildContext context, PurchaseReportsData data) {
    switch (widget.reportType) {
      case PurchaseReportType.all:
        PurchaseReportsPdfService.shareInvoiceList(
          context: context,
          title: _title(),
          invoices: data.allPurchases,
          data: data,
        );
      case PurchaseReportType.cash:
        PurchaseReportsPdfService.shareInvoiceList(
          context: context,
          title: _title(),
          invoices: data.cashPurchases,
          data: data,
        );
      case PurchaseReportType.credit:
        PurchaseReportsPdfService.shareInvoiceList(
          context: context,
          title: _title(),
          invoices: data.creditPurchases,
          data: data,
        );
      case PurchaseReportType.card:
        PurchaseReportsPdfService.shareInvoiceList(
          context: context,
          title: _title(),
          invoices: data.cardPurchases,
          data: data,
        );
      case PurchaseReportType.cheque:
        PurchaseReportsPdfService.shareInvoiceList(
          context: context,
          title: _title(),
          invoices: data.chequePurchases,
          data: data,
        );
      case PurchaseReportType.byProduct:
        PurchaseReportsPdfService.shareByProduct(
          context: context,
          items: data.byProduct,
          data: data,
        );
      case PurchaseReportType.byCategory:
        PurchaseReportsPdfService.shareByCategory(
          context: context,
          items: data.byCategory,
          data: data,
        );
      case PurchaseReportType.bySupplier:
        PurchaseReportsPdfService.shareBySupplier(
          context: context,
          items: data.bySupplier,
          data: data,
        );
      case PurchaseReportType.cancelled:
        PurchaseReportsPdfService.shareCancelled(
          context: context,
          items: data.cancelledInvoices,
          data: data,
        );
      case PurchaseReportType.orders:
        PurchaseReportsPdfService.shareOrders(
          context: context,
          items: data.purchaseOrders,
          data: data,
        );
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isExcel =
        widget.reportType == PurchaseReportType.excel ||
        widget.reportType == PurchaseReportType.excelProducts;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
        actions: [
          if (!isExcel)
            BlocBuilder<
              PurchaseReportsBloc,
              RealtimeState<PurchaseReportsData>
            >(
              builder: (context, state) {
                if (state is! RealtimeSuccess<PurchaseReportsData>) {
                  return const SizedBox.shrink();
                }
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
      body:
          BlocBuilder<PurchaseReportsBloc, RealtimeState<PurchaseReportsData>>(
            builder: (context, state) {
              if (state is RealtimeLoading<PurchaseReportsData>) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state is RealtimeError<PurchaseReportsData>) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        state.error.toString(),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              }

              if (state is RealtimeSuccess<PurchaseReportsData>) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: DateRangeSelector(
                        dateRange: state.data.dateRange,
                        onChanged: (range) => context
                            .read<PurchaseReportsBloc>()
                            .add(PurchaseReportsDateRangeChanged(range)),
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
                            prefixIcon: const Icon(
                              LucideIcons.search,
                              size: 18,
                            ),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(LucideIcons.x, size: 18),
                                    onPressed: () =>
                                        setState(() => _searchQuery = ''),
                                  )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onChanged: (v) => setState(
                            () => _searchQuery = v.trim().toLowerCase(),
                          ),
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

  Widget _buildSummary(BuildContext context, PurchaseReportsData data) {
    final cs = sl<CurrencyService>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    int totalCents;
    int count;
    String countLabel;

    switch (widget.reportType) {
      case PurchaseReportType.cash:
        totalCents = data.summary.cashPurchasesCents;
        count = data.cashPurchases.length;
        countLabel = 'reports.invoice_count'.tr();
      case PurchaseReportType.credit:
        totalCents = data.summary.creditPurchasesCents;
        count = data.creditPurchases.length;
        countLabel = 'reports.invoice_count'.tr();
      case PurchaseReportType.card:
        totalCents = data.summary.cardPurchasesCents;
        count = data.cardPurchases.length;
        countLabel = 'reports.invoice_count'.tr();
      case PurchaseReportType.cheque:
        totalCents = data.summary.chequePurchasesCents;
        count = data.chequePurchases.length;
        countLabel = 'reports.invoice_count'.tr();
      case PurchaseReportType.byProduct:
        totalCents = data.summary.totalPurchasesCents;
        count = data.byProduct.length;
        countLabel = 'reports.product_count'.tr();
      case PurchaseReportType.byCategory:
        totalCents = data.summary.totalPurchasesCents;
        count = data.byCategory.length;
        countLabel = 'reports.category_count'.tr();
      case PurchaseReportType.bySupplier:
        totalCents = data.summary.totalPurchasesCents;
        count = data.bySupplier.length;
        countLabel = 'reports.supplier_count'.tr();
      case PurchaseReportType.cancelled:
        totalCents = data.cancelledInvoices.fold(
          0,
          (sum, i) => sum + i.totalCents,
        );
        count = data.cancelledInvoices.length;
        countLabel = 'reports.invoice_count'.tr();
      case PurchaseReportType.orders:
        totalCents = data.purchaseOrders.fold(
          0,
          (sum, i) => sum + i.totalCents,
        );
        count = data.purchaseOrders.length;
        countLabel = 'reports.order_count'.tr();
      default:
        totalCents = data.summary.totalPurchasesCents;
        count = data.summary.invoiceCount;
        countLabel = 'reports.invoice_count'.tr();
    }

    final showNet = widget.reportType == PurchaseReportType.all;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'reports.total_purchases'.tr(),
                  value: cs.formatCents(totalCents),
                  icon: LucideIcons.shoppingBag,
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
                    label: 'reports.net_purchases'.tr(),
                    value: cs.formatCents(data.summary.netPurchasesCents),
                    icon: LucideIcons.trendingDown,
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

  Widget _buildContent(BuildContext context, PurchaseReportsData data) {
    switch (widget.reportType) {
      case PurchaseReportType.all:
        return _InvoiceListView(invoices: data.allPurchases);
      case PurchaseReportType.cash:
        return _InvoiceListView(invoices: data.cashPurchases);
      case PurchaseReportType.credit:
        return _InvoiceListView(invoices: data.creditPurchases);
      case PurchaseReportType.card:
        return _InvoiceListView(invoices: data.cardPurchases);
      case PurchaseReportType.cheque:
        return _InvoiceListView(
          invoices: data.chequePurchases,
          showChequeStatus: true,
        );
      case PurchaseReportType.byProduct:
        return _ProductListView(items: _filterProducts(data.byProduct));
      case PurchaseReportType.byCategory:
        return _CategoryListView(items: _filterCategories(data.byCategory));
      case PurchaseReportType.bySupplier:
        return _SupplierListView(items: _filterSuppliers(data.bySupplier));
      case PurchaseReportType.cancelled:
        return _CancelledListView(items: data.cancelledInvoices);
      case PurchaseReportType.orders:
        return _OrdersListView(items: data.purchaseOrders);
      case PurchaseReportType.excel:
      case PurchaseReportType.excelProducts:
        return _ExcelExportView(
          data: data,
          includeProducts:
              widget.reportType == PurchaseReportType.excelProducts,
        );
    }
  }

  List<PurchasesByProductItem> _filterProducts(
    List<PurchasesByProductItem> items,
  ) {
    if (_searchQuery.isEmpty) return items;
    return items
        .where(
          (p) =>
              p.productName.toLowerCase().contains(_searchQuery) ||
              (p.categoryName?.toLowerCase().contains(_searchQuery) ?? false),
        )
        .toList();
  }

  List<PurchasesByCategoryItem> _filterCategories(
    List<PurchasesByCategoryItem> items,
  ) {
    if (_searchQuery.isEmpty) return items;
    return items
        .where((c) => c.categoryName.toLowerCase().contains(_searchQuery))
        .toList();
  }

  List<PurchasesBySupplierItem> _filterSuppliers(
    List<PurchasesBySupplierItem> items,
  ) {
    if (_searchQuery.isEmpty) return items;
    return items
        .where((s) => s.supplierName.toLowerCase().contains(_searchQuery))
        .toList();
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
// INVOICE LIST VIEW (All, Cash, Credit, Card, Cheque)
// ═══════════════════════════════════════════════════════

class _InvoiceListView extends StatelessWidget {
  final List<PurchaseInvoiceItem> invoices;
  final bool showChequeStatus;

  const _InvoiceListView({
    required this.invoices,
    this.showChequeStatus = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (invoices.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.shoppingBag,
        message: 'reports.no_purchases_data'.tr(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showChequeStatus) ...[
            _buildChequeNotice(context, 'reports.cheque_purchases_desc'),
            const SizedBox(height: 10),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              horizontalMargin: 8,
              columns: [
                const DataColumn(label: Text('#'), numeric: true),
                DataColumn(label: Text('reports.purchase_number'.tr())),
                DataColumn(label: Text('reports.supplier'.tr())),
                DataColumn(label: Text('reports.subtotal'.tr()), numeric: true),
                DataColumn(label: Text('reports.discount'.tr()), numeric: true),
                DataColumn(label: Text('reports.tax'.tr()), numeric: true),
                DataColumn(label: Text('reports.total'.tr()), numeric: true),
                DataColumn(label: Text('reports.paid'.tr()), numeric: true),
                DataColumn(label: Text('reports.payment_method_col'.tr())),
                if (showChequeStatus)
                  DataColumn(label: Text('reports.cheque_status'.tr())),
                DataColumn(label: Text('reports.date'.tr())),
              ],
              rows: invoices.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final p = entry.value;
                return DataRow(
                  cells: [
                    DataCell(Text('$idx')),
                    DataCell(Text(p.purchaseNumber)),
                    DataCell(
                      Text(
                        p.supplierName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DataCell(Text(cs.formatCents(p.subtotalCents))),
                    DataCell(Text(cs.formatCents(p.discountCents))),
                    DataCell(Text(cs.formatCents(p.taxCents))),
                    DataCell(
                      Text(
                        cs.formatCents(p.totalCents),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    DataCell(Text(cs.formatCents(p.paidAmountCents))),
                    DataCell(Text(_paymentMethodLabel(p.paymentMethod))),
                    if (showChequeStatus)
                      DataCell(Text(_chequeStatusesLabel(p.chequeStatuses))),
                    DataCell(
                      Text(DateFormat('dd/MM/yyyy').format(p.purchaseDate)),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChequeNotice(BuildContext context, String translationKey) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 17, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              translationKey.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _chequeStatusesLabel(String? value) {
    final statuses = value
        ?.split(',')
        .map((status) => status.trim())
        .where((status) => status.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (statuses == null || statuses.isEmpty) {
      return 'reports.cheque_status_not_recorded'.tr();
    }
    return statuses.map((status) => 'cheques.status_$status'.tr()).join(' / ');
  }

  String _paymentMethodLabel(String? method) {
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
        return method ?? '-';
    }
  }
}

// ═══════════════════════════════════════════════════════
// PRODUCT LIST VIEW
// ═══════════════════════════════════════════════════════

class _ProductListView extends StatelessWidget {
  final List<PurchasesByProductItem> items;
  const _ProductListView({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (items.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.package2,
        message: 'reports.no_purchases_data'.tr(),
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
            DataColumn(
              label: Text('reports.total_purchases'.tr()),
              numeric: true,
            ),
            DataColumn(label: Text('reports.discount'.tr()), numeric: true),
            DataColumn(label: Text('reports.tax'.tr()), numeric: true),
            DataColumn(label: Text('reports.invoices'.tr()), numeric: true),
          ],
          rows: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final p = entry.value;
            return DataRow(
              cells: [
                DataCell(Text('$idx')),
                DataCell(
                  Text(
                    p.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(Text(p.categoryName ?? '-')),
                DataCell(Text('${p.totalQuantity}')),
                DataCell(
                  Text(
                    cs.formatCents(p.totalPurchasesCents),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                DataCell(Text(cs.formatCents(p.totalDiscountCents))),
                DataCell(Text(cs.formatCents(p.totalTaxCents))),
                DataCell(Text('${p.invoiceCount}')),
              ],
            );
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
  final List<PurchasesByCategoryItem> items;
  const _CategoryListView({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (items.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.folderOpen,
        message: 'reports.no_purchases_data'.tr(),
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
            DataColumn(
              label: Text('reports.product_count'.tr()),
              numeric: true,
            ),
            DataColumn(label: Text('reports.quantity'.tr()), numeric: true),
            DataColumn(
              label: Text('reports.total_purchases'.tr()),
              numeric: true,
            ),
            DataColumn(label: Text('reports.discount'.tr()), numeric: true),
            DataColumn(label: Text('reports.tax'.tr()), numeric: true),
            DataColumn(label: Text('reports.invoices'.tr()), numeric: true),
          ],
          rows: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final c = entry.value;
            return DataRow(
              cells: [
                DataCell(Text('$idx')),
                DataCell(
                  Text(
                    c.categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(Text('${c.productCount}')),
                DataCell(Text('${c.totalQuantity}')),
                DataCell(
                  Text(
                    cs.formatCents(c.totalPurchasesCents),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                DataCell(Text(cs.formatCents(c.totalDiscountCents))),
                DataCell(Text(cs.formatCents(c.totalTaxCents))),
                DataCell(Text('${c.invoiceCount}')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// SUPPLIER LIST VIEW
// ═══════════════════════════════════════════════════════

class _SupplierListView extends StatelessWidget {
  final List<PurchasesBySupplierItem> items;
  const _SupplierListView({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (items.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.truck,
        message: 'reports.no_purchases_data'.tr(),
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
            DataColumn(label: Text('reports.supplier'.tr())),
            DataColumn(
              label: Text('reports.total_purchases'.tr()),
              numeric: true,
            ),
            DataColumn(label: Text('reports.discount'.tr()), numeric: true),
            DataColumn(label: Text('reports.tax'.tr()), numeric: true),
            DataColumn(label: Text('reports.invoices'.tr()), numeric: true),
            DataColumn(label: Text('reports.quantity'.tr()), numeric: true),
            DataColumn(label: Text('reports.last_purchase'.tr())),
          ],
          rows: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final s = entry.value;
            return DataRow(
              cells: [
                DataCell(Text('$idx')),
                DataCell(
                  Text(
                    s.supplierName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(
                  Text(
                    cs.formatCents(s.totalPurchasesCents),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                DataCell(Text(cs.formatCents(s.totalDiscountCents))),
                DataCell(Text(cs.formatCents(s.totalTaxCents))),
                DataCell(Text('${s.invoiceCount}')),
                DataCell(Text('${s.totalQuantity}')),
                DataCell(
                  Text(
                    s.lastPurchaseDate != null
                        ? DateFormat('dd/MM/yyyy').format(s.lastPurchaseDate!)
                        : '-',
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// CANCELLED PURCHASES VIEW
// ═══════════════════════════════════════════════════════

class _CancelledListView extends StatelessWidget {
  final List<CancelledPurchaseItem> items;
  const _CancelledListView({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (items.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.ban,
        message: 'reports.no_cancelled_purchases'.tr(),
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
            DataColumn(label: Text('reports.purchase_number'.tr())),
            DataColumn(label: Text('reports.supplier'.tr())),
            DataColumn(label: Text('reports.total'.tr()), numeric: true),
            DataColumn(label: Text('reports.date'.tr())),
            DataColumn(label: Text('reports.notes'.tr())),
          ],
          rows: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final i = entry.value;
            return DataRow(
              cells: [
                DataCell(Text('$idx')),
                DataCell(Text(i.purchaseNumber)),
                DataCell(Text(i.supplierName)),
                DataCell(
                  Text(
                    cs.formatCents(i.totalCents),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                DataCell(Text(DateFormat('dd/MM/yyyy').format(i.purchaseDate))),
                DataCell(
                  Text(
                    i.notes ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// PURCHASE ORDERS VIEW
// ═══════════════════════════════════════════════════════

class _OrdersListView extends StatelessWidget {
  final List<PurchaseOrderItem> items;
  const _OrdersListView({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (items.isEmpty) {
      return _EmptyState(
        icon: LucideIcons.clipboardList,
        message: 'reports.no_purchase_orders'.tr(),
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
            DataColumn(label: Text('reports.purchase_number'.tr())),
            DataColumn(label: Text('reports.supplier'.tr())),
            DataColumn(label: Text('reports.total'.tr()), numeric: true),
            DataColumn(label: Text('reports.date'.tr())),
            DataColumn(label: Text('reports.due_date'.tr())),
          ],
          rows: items.asMap().entries.map((entry) {
            final idx = entry.key + 1;
            final o = entry.value;
            return DataRow(
              cells: [
                DataCell(Text('$idx')),
                DataCell(Text(o.purchaseNumber)),
                DataCell(Text(o.supplierName)),
                DataCell(
                  Text(
                    cs.formatCents(o.totalCents),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                DataCell(Text(DateFormat('dd/MM/yyyy').format(o.purchaseDate))),
                DataCell(
                  Text(
                    o.dueDate != null
                        ? DateFormat('dd/MM/yyyy').format(o.dueDate!)
                        : '-',
                  ),
                ),
              ],
            );
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
  final PurchaseReportsData data;
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
        await PurchaseReportsExcelService.exportPurchasesWithProducts(
          context: context,
          data: widget.data,
        );
      } else {
        await PurchaseReportsExcelService.exportPurchases(
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

    return ReportScrollableCenter(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.fileSpreadsheet,
              size: 64,
              color: Colors.green[700],
            ),
            const SizedBox(height: 16),
            Text(
              widget.includeProducts
                  ? 'reports.purchases_excel_products'.tr()
                  : 'reports.purchases_excel'.tr(),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'reports.purchases_excel_hint'.tr(),
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
                      label: 'reports.total_purchases'.tr(),
                      value: cs.formatCents(
                        widget.data.summary.totalPurchasesCents,
                      ),
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
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.download),
                label: Text(
                  _exporting
                      ? 'reports.exporting'.tr()
                      : 'reports.export_excel'.tr(),
                ),
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
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
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
    return ReportScrollableCenter(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
