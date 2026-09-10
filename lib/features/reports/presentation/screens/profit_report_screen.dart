import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../bloc/profit_reports_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../../services/profit_reports_pdf_service.dart';

enum ProfitReportType { overall, byProduct, byCategory, byCustomer, byInvoice }

class ProfitReportScreen extends StatelessWidget {
  final ProfitReportType reportType;
  const ProfitReportScreen({super.key, required this.reportType});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<ProfitReportsBloc>(),
      child: _ProfitReportView(reportType: reportType),
    );
  }
}

class _ProfitReportView extends StatefulWidget {
  final ProfitReportType reportType;
  const _ProfitReportView({required this.reportType});

  @override
  State<_ProfitReportView> createState() => _ProfitReportViewState();
}

class _ProfitReportViewState extends State<_ProfitReportView> {
  String _searchQuery = '';

  String get _title {
    switch (widget.reportType) {
      case ProfitReportType.overall:
        return 'reports.profit_overall'.tr();
      case ProfitReportType.byProduct:
        return 'reports.profit_by_product'.tr();
      case ProfitReportType.byCategory:
        return 'reports.profit_by_category'.tr();
      case ProfitReportType.byCustomer:
        return 'reports.profit_by_customer'.tr();
      case ProfitReportType.byInvoice:
        return 'reports.profit_by_invoice'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = sl<CurrencyService>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          BlocBuilder<ProfitReportsBloc, RealtimeState<ProfitReportsData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<ProfitReportsData>) {
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
          BlocBuilder<ProfitReportsBloc, RealtimeState<ProfitReportsData>>(
            builder: (context, state) {
              final bloc = context.read<ProfitReportsBloc>();
              return DateRangeSelector(
                dateRange: bloc.dateRange,
                onChanged: (range) =>
                    bloc.add(ProfitReportsDateRangeChanged(range)),
              );
            },
          ),
          // Search bar (not for overall)
          if (widget.reportType != ProfitReportType.overall)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: _searchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) =>
                    setState(() => _searchQuery = v.toLowerCase()),
              ),
            ),
          // Summary cards
          BlocBuilder<ProfitReportsBloc, RealtimeState<ProfitReportsData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<ProfitReportsData>) {
                return const SizedBox.shrink();
              }
              final s = state.data.summary;
              final profitColor = s.totalProfitCents >= 0
                  ? Colors.green
                  : Colors.red;
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
                      label: 'reports.revenue'.tr(),
                      value: cs.formatCents(s.totalRevenueCents),
                    ),
                    _SummaryChip(
                      label: 'reports.cost'.tr(),
                      value: cs.formatCents(s.totalCostCents),
                    ),
                    _SummaryChip(
                      label: 'reports.profit'.tr(),
                      value: cs.formatCents(s.totalProfitCents),
                      color: profitColor,
                    ),
                    _SummaryChip(
                      label: 'reports.margin'.tr(),
                      value: '${s.profitMarginPercent.toStringAsFixed(1)}%',
                      color: profitColor,
                    ),
                    _SummaryChip(
                      label: 'reports.invoices'.tr(),
                      value: '${s.invoiceCount}',
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
                  ProfitReportsBloc,
                  RealtimeState<ProfitReportsData>
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
                    if (state is! RealtimeSuccess<ProfitReportsData>) {
                      return const SizedBox.shrink();
                    }
                    final data = state.data;
                    switch (widget.reportType) {
                      case ProfitReportType.overall:
                        return _buildOverallView(data, cs);
                      case ProfitReportType.byProduct:
                        return _buildByProductTable(data, cs);
                      case ProfitReportType.byCategory:
                        return _buildByCategoryTable(data, cs);
                      case ProfitReportType.byCustomer:
                        return _buildByCustomerTable(data, cs);
                      case ProfitReportType.byInvoice:
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
      case ProfitReportType.overall:
        return '';
      case ProfitReportType.byProduct:
        return 'reports.search_product_hint'.tr();
      case ProfitReportType.byCategory:
        return 'reports.search_category_hint'.tr();
      case ProfitReportType.byCustomer:
        return 'reports.search_customers'.tr();
      case ProfitReportType.byInvoice:
        return 'reports.search_invoice_hint'.tr();
    }
  }

  Widget _buildOverallView(ProfitReportsData data, CurrencyService cs) {
    final s = data.summary;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OverviewCard(
            title: 'reports.revenue'.tr(),
            value: cs.formatCents(s.totalRevenueCents),
            icon: LucideIcons.dollarSign,
            color: Colors.blue,
          ),
          const SizedBox(height: 12),
          _OverviewCard(
            title: 'reports.cost'.tr(),
            value: cs.formatCents(s.totalCostCents),
            icon: LucideIcons.shoppingCart,
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          _OverviewCard(
            title: 'reports.gross_profit'.tr(),
            value: cs.formatCents(s.totalProfitCents),
            icon: LucideIcons.trendingUp,
            color: s.totalProfitCents >= 0 ? Colors.green : Colors.red,
          ),
          const SizedBox(height: 12),
          _OverviewCard(
            title: 'reports.profit_margin'.tr(),
            value: '${s.profitMarginPercent.toStringAsFixed(1)}%',
            icon: LucideIcons.percent,
            color: s.profitMarginPercent >= 0 ? Colors.green : Colors.red,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _OverviewCard(
                  title: 'reports.total_discount'.tr(),
                  value: cs.formatCents(s.totalDiscountCents),
                  icon: LucideIcons.tag,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OverviewCard(
                  title: 'reports.total_tax'.tr(),
                  value: cs.formatCents(s.totalTaxCents),
                  icon: LucideIcons.receipt,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _OverviewCard(
                  title: 'reports.invoices'.tr(),
                  value: '${s.invoiceCount}',
                  icon: LucideIcons.fileText,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OverviewCard(
                  title: 'reports.products'.tr(),
                  value: '${s.productCount}',
                  icon: LucideIcons.package2,
                  color: Colors.brown,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildByProductTable(ProfitReportsData data, CurrencyService cs) {
    final items = data.byProduct
        .where(
          (i) =>
              _searchQuery.isEmpty ||
              i.productName.toLowerCase().contains(_searchQuery) ||
              (i.categoryName?.toLowerCase().contains(_searchQuery) ?? false),
        )
        .toList();
    if (items.isEmpty) {
      return Center(child: Text('reports.no_profit_data'.tr()));
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
            DataColumn(label: Text('reports.revenue'.tr()), numeric: true),
            DataColumn(label: Text('reports.cost'.tr()), numeric: true),
            DataColumn(label: Text('reports.profit'.tr()), numeric: true),
            DataColumn(label: Text('reports.margin'.tr()), numeric: true),
          ],
          rows: items.asMap().entries.map((e) {
            final i = e.value;
            final profitColor = i.totalProfitCents >= 0
                ? Colors.green
                : Colors.red;
            return DataRow(
              cells: [
                DataCell(Text('${e.key + 1}')),
                DataCell(Text(i.productName)),
                DataCell(Text(i.categoryName ?? '-')),
                DataCell(Text('${i.totalQuantity}')),
                DataCell(Text(cs.formatCents(i.totalRevenueCents))),
                DataCell(Text(cs.formatCents(i.totalCostCents))),
                DataCell(
                  Text(
                    cs.formatCents(i.totalProfitCents),
                    style: TextStyle(color: profitColor),
                  ),
                ),
                DataCell(
                  Text(
                    '${i.profitMarginPercent.toStringAsFixed(1)}%',
                    style: TextStyle(color: profitColor),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildByCategoryTable(ProfitReportsData data, CurrencyService cs) {
    final items = data.byCategory
        .where(
          (i) =>
              _searchQuery.isEmpty ||
              i.categoryName.toLowerCase().contains(_searchQuery),
        )
        .toList();
    if (items.isEmpty) {
      return Center(child: Text('reports.no_profit_data'.tr()));
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
            DataColumn(label: Text('reports.revenue'.tr()), numeric: true),
            DataColumn(label: Text('reports.cost'.tr()), numeric: true),
            DataColumn(label: Text('reports.profit'.tr()), numeric: true),
            DataColumn(label: Text('reports.margin'.tr()), numeric: true),
          ],
          rows: items.asMap().entries.map((e) {
            final i = e.value;
            final profitColor = i.totalProfitCents >= 0
                ? Colors.green
                : Colors.red;
            return DataRow(
              cells: [
                DataCell(Text('${e.key + 1}')),
                DataCell(Text(i.categoryName)),
                DataCell(Text('${i.productCount}')),
                DataCell(Text('${i.totalQuantity}')),
                DataCell(Text(cs.formatCents(i.totalRevenueCents))),
                DataCell(Text(cs.formatCents(i.totalCostCents))),
                DataCell(
                  Text(
                    cs.formatCents(i.totalProfitCents),
                    style: TextStyle(color: profitColor),
                  ),
                ),
                DataCell(
                  Text(
                    '${i.profitMarginPercent.toStringAsFixed(1)}%',
                    style: TextStyle(color: profitColor),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildByCustomerTable(ProfitReportsData data, CurrencyService cs) {
    final items = data.byCustomer
        .where(
          (i) =>
              _searchQuery.isEmpty ||
              i.customerName.toLowerCase().contains(_searchQuery),
        )
        .toList();
    if (items.isEmpty) {
      return Center(child: Text('reports.no_profit_data'.tr()));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          columns: [
            const DataColumn(label: Text('#')),
            DataColumn(label: Text('reports.customer'.tr())),
            DataColumn(label: Text('reports.revenue'.tr()), numeric: true),
            DataColumn(label: Text('reports.cost'.tr()), numeric: true),
            DataColumn(label: Text('reports.profit'.tr()), numeric: true),
            DataColumn(label: Text('reports.margin'.tr()), numeric: true),
            DataColumn(label: Text('reports.invoices'.tr()), numeric: true),
          ],
          rows: items.asMap().entries.map((e) {
            final i = e.value;
            final profitColor = i.totalProfitCents >= 0
                ? Colors.green
                : Colors.red;
            return DataRow(
              cells: [
                DataCell(Text('${e.key + 1}')),
                DataCell(Text(i.customerName)),
                DataCell(Text(cs.formatCents(i.totalRevenueCents))),
                DataCell(Text(cs.formatCents(i.totalCostCents))),
                DataCell(
                  Text(
                    cs.formatCents(i.totalProfitCents),
                    style: TextStyle(color: profitColor),
                  ),
                ),
                DataCell(
                  Text(
                    '${i.profitMarginPercent.toStringAsFixed(1)}%',
                    style: TextStyle(color: profitColor),
                  ),
                ),
                DataCell(Text('${i.invoiceCount}')),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildByInvoiceTable(ProfitReportsData data, CurrencyService cs) {
    final items = data.byInvoice
        .where(
          (i) =>
              _searchQuery.isEmpty ||
              i.invoiceNumber.toLowerCase().contains(_searchQuery) ||
              (i.customerName?.toLowerCase().contains(_searchQuery) ?? false),
        )
        .toList();
    if (items.isEmpty) {
      return Center(child: Text('reports.no_profit_data'.tr()));
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
            DataColumn(label: Text('reports.revenue'.tr()), numeric: true),
            DataColumn(label: Text('reports.cost'.tr()), numeric: true),
            DataColumn(label: Text('reports.profit'.tr()), numeric: true),
            DataColumn(label: Text('reports.margin'.tr()), numeric: true),
            DataColumn(label: Text('reports.date'.tr())),
          ],
          rows: items.asMap().entries.map((e) {
            final i = e.value;
            final profitColor = i.profitCents >= 0 ? Colors.green : Colors.red;
            return DataRow(
              cells: [
                DataCell(Text('${e.key + 1}')),
                DataCell(Text(i.invoiceNumber)),
                DataCell(Text(i.customerName ?? '-')),
                DataCell(Text(cs.formatCents(i.revenueCents))),
                DataCell(Text(cs.formatCents(i.costCents))),
                DataCell(
                  Text(
                    cs.formatCents(i.profitCents),
                    style: TextStyle(color: profitColor),
                  ),
                ),
                DataCell(
                  Text(
                    '${i.profitMarginPercent.toStringAsFixed(1)}%',
                    style: TextStyle(color: profitColor),
                  ),
                ),
                DataCell(Text(DateFormat('dd/MM/yyyy').format(i.saleDate))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  void _onPrint(BuildContext context, ProfitReportsData data) {
    switch (widget.reportType) {
      case ProfitReportType.overall:
        ProfitReportsPdfService.printOverall(context: context, data: data);
        break;
      case ProfitReportType.byProduct:
        ProfitReportsPdfService.printByProduct(
          context: context,
          items: data.byProduct,
          data: data,
        );
        break;
      case ProfitReportType.byCategory:
        ProfitReportsPdfService.printByCategory(
          context: context,
          items: data.byCategory,
          data: data,
        );
        break;
      case ProfitReportType.byCustomer:
        ProfitReportsPdfService.printByCustomer(
          context: context,
          items: data.byCustomer,
          data: data,
        );
        break;
      case ProfitReportType.byInvoice:
        ProfitReportsPdfService.printByInvoice(
          context: context,
          items: data.byInvoice,
          data: data,
        );
        break;
    }
  }

  void _onShare(BuildContext context, ProfitReportsData data) {
    switch (widget.reportType) {
      case ProfitReportType.overall:
        ProfitReportsPdfService.shareOverall(context: context, data: data);
        break;
      case ProfitReportType.byProduct:
        ProfitReportsPdfService.shareByProduct(
          context: context,
          items: data.byProduct,
          data: data,
        );
        break;
      case ProfitReportType.byCategory:
        ProfitReportsPdfService.shareByCategory(
          context: context,
          items: data.byCategory,
          data: data,
        );
        break;
      case ProfitReportType.byCustomer:
        ProfitReportsPdfService.shareByCustomer(
          context: context,
          items: data.byCustomer,
          data: data,
        );
        break;
      case ProfitReportType.byInvoice:
        ProfitReportsPdfService.shareByInvoice(
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
  final Color? color;
  const _SummaryChip({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(
        '$label: $value',
        style: TextStyle(fontSize: 12, color: color),
      ),
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}

class _OverviewCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _OverviewCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
