import '../widgets/warehouse_report_context.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../bloc/discount_reports_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../../services/discount_reports_pdf_service.dart';

enum DiscountReportType { byProduct, byCategory, byCustomer, byInvoice }

class DiscountReportScreen extends StatelessWidget {
  final DiscountReportType reportType;
  const DiscountReportScreen({super.key, required this.reportType});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<DiscountReportsBloc>(
        param1: WarehouseReportContext.maybeOf(context)?.scope,
      ),
      child: _DiscountReportView(reportType: reportType),
    );
  }
}

class _DiscountReportView extends StatefulWidget {
  final DiscountReportType reportType;
  const _DiscountReportView({required this.reportType});

  @override
  State<_DiscountReportView> createState() => _DiscountReportViewState();
}

class _DiscountReportViewState extends State<_DiscountReportView> {
  String _searchQuery = '';

  String get _title {
    switch (widget.reportType) {
      case DiscountReportType.byProduct:
        return 'reports.discount_by_product'.tr();
      case DiscountReportType.byCategory:
        return 'reports.discount_by_category'.tr();
      case DiscountReportType.byCustomer:
        return 'reports.discount_by_customer'.tr();
      case DiscountReportType.byInvoice:
        return 'reports.discount_by_invoice'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = sl<CurrencyService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          BlocBuilder<DiscountReportsBloc, RealtimeState<DiscountReportsData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<DiscountReportsData>) {
                return const SizedBox.shrink();
              }
              return Row(
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
      body: Column(
        children: [
          // Date range picker
          BlocBuilder<DiscountReportsBloc, RealtimeState<DiscountReportsData>>(
            builder: (context, state) {
              final bloc = context.read<DiscountReportsBloc>();
              return DateRangeSelector(
                dateRange: bloc.dateRange,
                onChanged: (range) =>
                    bloc.add(DiscountReportsDateRangeChanged(range)),
              );
            },
          ),
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: _searchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            ),
          ),
          // Summary cards
          BlocBuilder<DiscountReportsBloc, RealtimeState<DiscountReportsData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<DiscountReportsData>) {
                return const SizedBox.shrink();
              }
              final s = state.data.summary;
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _SummaryChip(
                      label: 'reports.total_discount'.tr(),
                      value: cs.formatCents(s.totalDiscountCents),
                    ),
                    _SummaryChip(
                      label: 'reports.discounted_invoices'.tr(),
                      value: '${s.discountedInvoiceCount}',
                    ),
                    _SummaryChip(
                      label: 'reports.avg_discount'.tr(),
                      value: '${s.averageDiscountPercent.toStringAsFixed(1)}%',
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // Data
          Expanded(
            child:
                BlocBuilder<
                  DiscountReportsBloc,
                  RealtimeState<DiscountReportsData>
                >(
                  builder: (context, state) {
                    if (state is RealtimeLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (state is RealtimeError) {
                      return Center(
                        child: Text('${(state as RealtimeError).error}'),
                      );
                    }
                    if (state is! RealtimeSuccess<DiscountReportsData>) {
                      return const SizedBox.shrink();
                    }
                    final data = state.data;
                    switch (widget.reportType) {
                      case DiscountReportType.byProduct:
                        return _buildByProductTable(data, cs);
                      case DiscountReportType.byCategory:
                        return _buildByCategoryTable(data, cs);
                      case DiscountReportType.byCustomer:
                        return _buildByCustomerTable(data, cs);
                      case DiscountReportType.byInvoice:
                        return _buildByInvoiceTable(data, cs);
                    }
                  },
                ),
          ),
        ],
      ),
    );
  }

  String get _searchHint {
    switch (widget.reportType) {
      case DiscountReportType.byProduct:
        return 'reports.search_product_hint'.tr();
      case DiscountReportType.byCategory:
        return 'reports.search_category_hint'.tr();
      case DiscountReportType.byCustomer:
        return 'reports.search_customers'.tr();
      case DiscountReportType.byInvoice:
        return 'reports.search_invoice_hint'.tr();
    }
  }

  Widget _buildByProductTable(DiscountReportsData data, CurrencyService cs) {
    final items = data.byProduct
        .where(
          (i) =>
              _searchQuery.isEmpty ||
              i.productName.toLowerCase().contains(_searchQuery) ||
              (i.categoryName?.toLowerCase().contains(_searchQuery) ?? false),
        )
        .toList();
    if (items.isEmpty) {
      return Center(child: Text('reports.no_discount_data'.tr()));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          columns: [
            const DataColumn(label: Text('#')),
            DataColumn(label: Text('reports.product'.tr())),
            DataColumn(label: Text('reports.category'.tr())),
            DataColumn(label: Text('reports.quantity'.tr()), numeric: true),
            DataColumn(
              label: Text('reports.total_sales_col'.tr()),
              numeric: true,
            ),
            DataColumn(label: Text('reports.discount'.tr()), numeric: true),
            DataColumn(label: Text('reports.discount_pct'.tr()), numeric: true),
            DataColumn(label: Text('reports.invoices'.tr()), numeric: true),
          ],
          rows: items.asMap().entries.map((e) {
            final i = e.value;
            return DataRow(
              cells: [
                DataCell(Text('${e.key + 1}')),
                DataCell(Text(i.productName)),
                DataCell(Text(i.categoryName ?? '-')),
                DataCell(Text('${i.totalQuantity}')),
                DataCell(Text(cs.formatCents(i.totalSalesCents))),
                DataCell(Text(cs.formatCents(i.totalDiscountCents))),
                DataCell(Text('${i.discountPercent.toStringAsFixed(1)}%')),
                DataCell(Text('${i.invoiceCount}')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildByCategoryTable(DiscountReportsData data, CurrencyService cs) {
    final items = data.byCategory
        .where(
          (i) =>
              _searchQuery.isEmpty ||
              i.categoryName.toLowerCase().contains(_searchQuery),
        )
        .toList();
    if (items.isEmpty) {
      return Center(child: Text('reports.no_discount_data'.tr()));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          columns: [
            const DataColumn(label: Text('#')),
            DataColumn(label: Text('reports.category'.tr())),
            DataColumn(label: Text('reports.products'.tr()), numeric: true),
            DataColumn(label: Text('reports.quantity'.tr()), numeric: true),
            DataColumn(
              label: Text('reports.total_sales_col'.tr()),
              numeric: true,
            ),
            DataColumn(label: Text('reports.discount'.tr()), numeric: true),
            DataColumn(label: Text('reports.discount_pct'.tr()), numeric: true),
            DataColumn(label: Text('reports.invoices'.tr()), numeric: true),
          ],
          rows: items.asMap().entries.map((e) {
            final i = e.value;
            return DataRow(
              cells: [
                DataCell(Text('${e.key + 1}')),
                DataCell(Text(i.categoryName)),
                DataCell(Text('${i.productCount}')),
                DataCell(Text('${i.totalQuantity}')),
                DataCell(Text(cs.formatCents(i.totalSalesCents))),
                DataCell(Text(cs.formatCents(i.totalDiscountCents))),
                DataCell(Text('${i.discountPercent.toStringAsFixed(1)}%')),
                DataCell(Text('${i.invoiceCount}')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildByCustomerTable(DiscountReportsData data, CurrencyService cs) {
    final items = data.byCustomer
        .where(
          (i) =>
              _searchQuery.isEmpty ||
              i.customerName.toLowerCase().contains(_searchQuery),
        )
        .toList();
    if (items.isEmpty) {
      return Center(child: Text('reports.no_discount_data'.tr()));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          columns: [
            const DataColumn(label: Text('#')),
            DataColumn(label: Text('reports.customer'.tr())),
            DataColumn(
              label: Text('reports.total_sales_col'.tr()),
              numeric: true,
            ),
            DataColumn(label: Text('reports.discount'.tr()), numeric: true),
            DataColumn(label: Text('reports.discount_pct'.tr()), numeric: true),
            DataColumn(label: Text('reports.invoices'.tr()), numeric: true),
          ],
          rows: items.asMap().entries.map((e) {
            final i = e.value;
            return DataRow(
              cells: [
                DataCell(Text('${e.key + 1}')),
                DataCell(Text(i.customerName)),
                DataCell(Text(cs.formatCents(i.totalSalesCents))),
                DataCell(Text(cs.formatCents(i.totalDiscountCents))),
                DataCell(Text('${i.discountPercent.toStringAsFixed(1)}%')),
                DataCell(Text('${i.invoiceCount}')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildByInvoiceTable(DiscountReportsData data, CurrencyService cs) {
    final items = data.byInvoice
        .where(
          (i) =>
              _searchQuery.isEmpty ||
              i.invoiceNumber.toLowerCase().contains(_searchQuery) ||
              (i.customerName?.toLowerCase().contains(_searchQuery) ?? false),
        )
        .toList();
    if (items.isEmpty) {
      return Center(child: Text('reports.no_discount_data'.tr()));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          columns: [
            const DataColumn(label: Text('#')),
            DataColumn(label: Text('reports.invoice_number'.tr())),
            DataColumn(label: Text('reports.customer'.tr())),
            DataColumn(label: Text('reports.subtotal'.tr()), numeric: true),
            DataColumn(label: Text('reports.discount'.tr()), numeric: true),
            DataColumn(label: Text('reports.discount_pct'.tr()), numeric: true),
            DataColumn(label: Text('reports.total'.tr()), numeric: true),
            DataColumn(label: Text('reports.date'.tr())),
          ],
          rows: items.asMap().entries.map((e) {
            final i = e.value;
            return DataRow(
              cells: [
                DataCell(Text('${e.key + 1}')),
                DataCell(Text(i.invoiceNumber)),
                DataCell(Text(i.customerName ?? '-')),
                DataCell(Text(cs.formatCents(i.subtotalCents))),
                DataCell(Text(cs.formatCents(i.discountCents))),
                DataCell(Text('${i.discountPercent.toStringAsFixed(1)}%')),
                DataCell(Text(cs.formatCents(i.totalCents))),
                DataCell(Text(DateFormat('dd/MM/yyyy').format(i.saleDate))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  void _onPrint(BuildContext context, DiscountReportsData data) {
    switch (widget.reportType) {
      case DiscountReportType.byProduct:
        DiscountReportsPdfService.printByProduct(
          context: context,
          items: data.byProduct,
          data: data,
        );
        break;
      case DiscountReportType.byCategory:
        DiscountReportsPdfService.printByCategory(
          context: context,
          items: data.byCategory,
          data: data,
        );
        break;
      case DiscountReportType.byCustomer:
        DiscountReportsPdfService.printByCustomer(
          context: context,
          items: data.byCustomer,
          data: data,
        );
        break;
      case DiscountReportType.byInvoice:
        DiscountReportsPdfService.printByInvoice(
          context: context,
          items: data.byInvoice,
          data: data,
        );
        break;
    }
  }

  void _onShare(BuildContext context, DiscountReportsData data) {
    switch (widget.reportType) {
      case DiscountReportType.byProduct:
        DiscountReportsPdfService.shareByProduct(
          context: context,
          items: data.byProduct,
          data: data,
        );
        break;
      case DiscountReportType.byCategory:
        DiscountReportsPdfService.shareByCategory(
          context: context,
          items: data.byCategory,
          data: data,
        );
        break;
      case DiscountReportType.byCustomer:
        DiscountReportsPdfService.shareByCustomer(
          context: context,
          items: data.byCustomer,
          data: data,
        );
        break;
      case DiscountReportType.byInvoice:
        DiscountReportsPdfService.shareByInvoice(
          context: context,
          items: data.byInvoice,
          data: data,
        );
        break;
    }
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value', style: const TextStyle(fontSize: 12)),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}
