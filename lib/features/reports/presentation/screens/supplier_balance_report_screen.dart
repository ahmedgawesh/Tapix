import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/supplier_balance_excel_service.dart';
import '../../services/supplier_balance_pdf_service.dart';
import '../bloc/supplier_balance_report_bloc.dart';
import '../widgets/date_range_selector.dart';

class SupplierBalanceReportScreen extends StatelessWidget {
  const SupplierBalanceReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SupplierBalanceReportBloc>(),
      child: const _SupplierBalanceReportView(),
    );
  }
}

class _SupplierBalanceReportView extends StatefulWidget {
  const _SupplierBalanceReportView();

  @override
  State<_SupplierBalanceReportView> createState() =>
      _SupplierBalanceReportViewState();
}

class _SupplierBalanceReportViewState
    extends State<_SupplierBalanceReportView> {
  final _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'reports.search_supplier'.tr(),
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                style: theme.textTheme.titleMedium,
                onChanged: (value) {
                  context
                      .read<SupplierBalanceReportBloc>()
                      .add(SupplierBalanceReportSearchChanged(value));
                },
              )
            : Text('reports.supplier_balance'.tr()),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? LucideIcons.x : LucideIcons.search),
            tooltip: _showSearch ? 'common.close'.tr() : 'common.search'.tr(),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  context
                      .read<SupplierBalanceReportBloc>()
                      .add(const SupplierBalanceReportSearchChanged(''));
                }
              });
            },
          ),
          BlocBuilder<SupplierBalanceReportBloc,
              RealtimeState<SupplierBalanceReportData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<SupplierBalanceReportData>) {
                return const SizedBox.shrink();
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(LucideIcons.printer),
                    tooltip: 'common.print'.tr(),
                    onPressed: () => _printReport(context, state.data),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.share2),
                    tooltip: 'common.share'.tr(),
                    onPressed: () => _shareReport(context, state.data),
                  ),
                  IconButton(
                    icon: const Icon(LucideIcons.fileSpreadsheet),
                    tooltip: 'Excel',
                    onPressed: () => _exportReportExcel(context, state.data),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<SupplierBalanceReportBloc,
          RealtimeState<SupplierBalanceReportData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<SupplierBalanceReportData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<SupplierBalanceReportData>) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(state.error.toString(),
                      style: theme.textTheme.bodyLarge),
                ],
              ),
            );
          }

          if (state is RealtimeSuccess<SupplierBalanceReportData>) {
            return Column(
              children: [
                // Date range selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<SupplierBalanceReportBloc>()
                        .add(SupplierBalanceReportDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 12),

                // Summary cards
                _buildSummarySection(context, state.data),
                const SizedBox(height: 12),

                // Supplier list
                Expanded(
                  child: _SupplierBalanceList(data: state.data),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSummarySection(
      BuildContext context, SupplierBalanceReportData data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();
    final summary = data.summary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Main summary cards - Payables vs Receivables
          Row(
            children: [
              Expanded(
                child: _SummaryCard(
                  label: 'reports.total_payables'.tr(),
                  value: cs.formatCents(summary.totalPayablesCents),
                  subtitle: 'reports.suppliers_count'
                      .tr(args: ['${summary.suppliersWithPayable}']),
                  icon: LucideIcons.arrowUpRight,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryCard(
                  label: 'reports.total_receivables'.tr(),
                  value: cs.formatCents(summary.totalReceivablesCents),
                  subtitle: 'reports.suppliers_count'
                      .tr(args: ['${summary.suppliersWithReceivable}']),
                  icon: LucideIcons.arrowDownLeft,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Net balance card
          _SummaryCard(
            label: 'reports.net_balance'.tr(),
            value: cs.formatCents(summary.netBalanceCents),
            subtitle: summary.netBalanceCents > 0
                ? 'reports.net_payable'.tr()
                : summary.netBalanceCents < 0
                    ? 'reports.net_receivable'.tr()
                    : 'reports.balanced'.tr(),
            icon: LucideIcons.scale,
            color: summary.netBalanceCents > 0
                ? colorScheme.error
                : summary.netBalanceCents < 0
                    ? colorScheme.primary
                    : colorScheme.tertiary,
            isFullWidth: true,
          ),
          const SizedBox(height: 8),

          // Detailed breakdown - Opening balances
          _DetailedSummaryRow(
            items: [
              _DetailItem(
                label: 'reports.opening_debit'.tr(),
                value: cs.formatCents(summary.openingDebitCents),
                color: colorScheme.error,
              ),
              _DetailItem(
                label: 'reports.opening_credit'.tr(),
                value: cs.formatCents(summary.openingCreditCents),
                color: colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Detailed breakdown - Transactions
          _DetailedSummaryRow(
            items: [
              _DetailItem(
                label: 'reports.total_purchases'.tr(),
                value: cs.formatCents(summary.totalPurchasesCents),
                color: colorScheme.error,
              ),
              _DetailItem(
                label: 'reports.total_payments'.tr(),
                value: cs.formatCents(summary.totalPaymentsCents),
                color: colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Detailed breakdown - Returns & Discounts
          _DetailedSummaryRow(
            items: [
              _DetailItem(
                label: 'reports.total_returns'.tr(),
                value: cs.formatCents(summary.totalReturnsCents),
                color: colorScheme.tertiary,
              ),
              _DetailItem(
                label: 'reports.total_discounts'.tr(),
                value: cs.formatCents(summary.totalDiscountsCents),
                color: colorScheme.tertiary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _printReport(
      BuildContext context, SupplierBalanceReportData data) async {
    await SupplierBalancePdfService.printSupplierBalanceReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_supplier_balance_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, SupplierBalanceReportData data) async {
    await SupplierBalancePdfService.shareSupplierBalanceReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_supplier_balance_report',
    );
  }

  Future<void> _exportReportExcel(
      BuildContext context, SupplierBalanceReportData data) async {
    try {
      await SupplierBalanceExcelService.shareSupplierBalanceReport(
        context: context,
        data: data,
      );
      sl<AuditLogService>().log(
        entityType: 'report',
        entityId: 0,
        action: 'export_supplier_balance_excel',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('reports.export_error'.tr())),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════
// SUMMARY CARD
// ═══════════════════════════════════════════════════════

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final bool isFullWidth;

  const _SummaryCard({
    required this.label,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
    this.isFullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment:
              isFullWidth ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: isFullWidth ? MainAxisSize.min : MainAxisSize.max,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// DETAILED SUMMARY ROW
// ═══════════════════════════════════════════════════════

class _DetailItem {
  final String label;
  final String value;
  final Color color;

  const _DetailItem({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _DetailedSummaryRow extends StatelessWidget {
  final List<_DetailItem> items;

  const _DetailedSummaryRow({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: items.map((item) {
            return Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    item.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: item.color,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// SUPPLIER BALANCE LIST
// ═══════════════════════════════════════════════════════

class _SupplierBalanceList extends StatelessWidget {
  final SupplierBalanceReportData data;
  const _SupplierBalanceList({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suppliers = data.filteredSuppliers;

    if (suppliers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.truck,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              data.searchQuery.isNotEmpty
                  ? 'reports.no_search_results'.tr()
                  : 'reports.no_supplier_balances'.tr(),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              data.searchQuery.isNotEmpty
                  ? 'reports.try_different_search'.tr()
                  : 'reports.no_supplier_balances_desc'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: suppliers.length,
      itemBuilder: (context, index) {
        final item = suppliers[index];
        return _SupplierBalanceCard(item: item);
      },
    );
  }
}

// ═══════════════════════════════════════════════════════
// SUPPLIER BALANCE CARD
// ═══════════════════════════════════════════════════════

class _SupplierBalanceCard extends StatelessWidget {
  final SupplierBalanceItem item;

  const _SupplierBalanceCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    final balanceColor = item.isPayable
        ? colorScheme.error
        : item.isReceivable
            ? colorScheme.primary
            : colorScheme.tertiary;
    final balanceLabel = item.isPayable
        ? 'reports.payable'.tr()
        : item.isReceivable
            ? 'reports.receivable'.tr()
            : 'reports.settled'.tr();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _showSupplierDetails(context, item),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: name + balance badge
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.supplierName,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.phone != null && item.phone!.isNotEmpty)
                          Text(
                            item.phone!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Chip(
                    label: Text(
                      balanceLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: balanceColor,
                      ),
                    ),
                    backgroundColor: balanceColor.withValues(alpha: 0.1),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide.none,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Balance metrics - 2x2 grid
              Row(
                children: [
                  Expanded(
                    child: _MetricItem(
                      label: 'reports.total_debits'.tr(),
                      value: cs.formatCents(item.totalDebitCents),
                      valueColor:
                          item.totalDebitCents > 0 ? colorScheme.error : null,
                    ),
                  ),
                  Expanded(
                    child: _MetricItem(
                      label: 'reports.total_credits'.tr(),
                      value: cs.formatCents(item.totalCreditCents),
                      valueColor:
                          item.totalCreditCents > 0 ? colorScheme.primary : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: _MetricItem(
                      label: 'reports.net_balance'.tr(),
                      value: cs.formatCents(item.netBalanceCents),
                      valueColor: balanceColor,
                    ),
                  ),
                  Expanded(
                    child: _MetricItem(
                      label: 'reports.transactions'.tr(),
                      value: item.transactionCount.toString(),
                    ),
                  ),
                ],
              ),

              if (item.lastTransactionAt != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${'reports.last_transaction'.tr()}: ${DateFormat.yMMMd().format(item.lastTransactionAt!)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showSupplierDetails(BuildContext context, SupplierBalanceItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: scrollController,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Supplier name
                  Text(
                    item.supplierName,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (item.phone != null || item.email != null) ...[
                    const SizedBox(height: 4),
                    if (item.phone != null)
                      Text(item.phone!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          )),
                    if (item.email != null)
                      Text(item.email!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          )),
                  ],
                  const SizedBox(height: 16),

                  // Net balance highlight
                  Card(
                    color: (item.isPayable ? colorScheme.error : colorScheme.primary)
                        .withValues(alpha: 0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            'reports.net_balance'.tr(),
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cs.formatCents(item.netBalanceCents),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: item.isPayable
                                  ? colorScheme.error
                                  : colorScheme.primary,
                            ),
                          ),
                          Text(
                            item.isPayable
                                ? 'reports.payable'.tr()
                                : item.isReceivable
                                    ? 'reports.receivable'.tr()
                                    : 'reports.settled'.tr(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Detailed breakdown
                  Text(
                    'reports.balance_breakdown'.tr(),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  _DetailRow(
                    label: 'reports.opening_balance'.tr(),
                    value: cs.formatCents(item.openingBalanceCents),
                    color: item.openingBalanceCents > 0
                        ? colorScheme.error
                        : item.openingBalanceCents < 0
                            ? colorScheme.primary
                            : null,
                  ),
                  _DetailRow(
                    label: 'reports.total_purchases'.tr(),
                    value: '+ ${cs.formatCents(item.totalPurchasesCents)}',
                    color: colorScheme.error,
                  ),
                  _DetailRow(
                    label: 'reports.total_payments'.tr(),
                    value: '- ${cs.formatCents(item.totalPaymentsCents)}',
                    color: colorScheme.primary,
                  ),
                  _DetailRow(
                    label: 'reports.total_returns'.tr(),
                    value: '- ${cs.formatCents(item.totalReturnsCents)}',
                    color: colorScheme.tertiary,
                  ),
                  _DetailRow(
                    label: 'reports.total_discounts'.tr(),
                    value: '- ${cs.formatCents(item.totalDiscountsCents)}',
                    color: colorScheme.tertiary,
                  ),
                  const Divider(),
                  _DetailRow(
                    label: 'reports.net_balance'.tr(),
                    value: cs.formatCents(item.netBalanceCents),
                    color: item.isPayable
                        ? colorScheme.error
                        : item.isReceivable
                            ? colorScheme.primary
                            : null,
                    isBold: true,
                  ),

                  const SizedBox(height: 24),

                  // Export buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _exportSupplierPdf(context, item);
                          },
                          icon: const Icon(LucideIcons.fileText),
                          label: const Text('PDF'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _exportSupplierExcel(context, item);
                          },
                          icon: const Icon(LucideIcons.fileSpreadsheet),
                          label: const Text('Excel'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _exportSupplierPdf(BuildContext context, SupplierBalanceItem item) async {
    try {
      await SupplierBalancePdfService.printSingleSupplierReport(
        context: context,
        item: item,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('reports.export_error'.tr())),
        );
      }
    }
  }

  Future<void> _exportSupplierExcel(BuildContext context, SupplierBalanceItem item) async {
    try {
      await SupplierBalanceExcelService.shareSupplierDetail(
        context: context,
        item: item,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('reports.export_error'.tr())),
        );
      }
    }
  }
}

// ═══════════════════════════════════════════════════════
// DETAIL ROW (for bottom sheet)
// ═══════════════════════════════════════════════════════

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool isBold;

  const _DetailRow({
    required this.label,
    required this.value,
    this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: isBold
                ? theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold)
                : theme.textTheme.bodyMedium,
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// METRIC ITEM
// ═══════════════════════════════════════════════════════

class _MetricItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MetricItem({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        Text(value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            )),
      ],
    );
  }
}
