import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/customer_ledger_pdf_service.dart';
import '../bloc/customer_ledger_report_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/searchable_party_selector.dart';

class CustomerLedgerReportScreen extends StatelessWidget {
  const CustomerLedgerReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CustomerLedgerReportBloc>(),
      child: const _CustomerLedgerReportView(),
    );
  }
}

class _CustomerLedgerReportView extends StatelessWidget {
  const _CustomerLedgerReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.customer_ledger_report'.tr()),
        actions: [
          BlocBuilder<
            CustomerLedgerReportBloc,
            RealtimeState<CustomerLedgerData>
          >(
            builder: (context, state) {
              if (state is! RealtimeSuccess<CustomerLedgerData>) {
                return const SizedBox.shrink();
              }
              if (state.data.customerId == null) {
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
                ],
              );
            },
          ),
        ],
      ),
      body:
          BlocBuilder<
            CustomerLedgerReportBloc,
            RealtimeState<CustomerLedgerData>
          >(
            builder: (context, state) {
              if (state is RealtimeLoading<CustomerLedgerData>) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state is RealtimeError<CustomerLedgerData>) {
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

              if (state is RealtimeSuccess<CustomerLedgerData>) {
                return Column(
                  children: [
                    // Customer selector
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _CustomerSelector(
                        customers: state.data.customers,
                        selectedId: state.data.customerId,
                        onChanged: (id) => context
                            .read<CustomerLedgerReportBloc>()
                            .add(CustomerLedgerCustomerChanged(id)),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Date range selector
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DateRangeSelector(
                        dateRange: state.data.dateRange,
                        onChanged: (range) => context
                            .read<CustomerLedgerReportBloc>()
                            .add(CustomerLedgerDateRangeChanged(range)),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Content
                    Expanded(
                      child: state.data.customerId == null
                          ? _buildSelectCustomerPrompt(context)
                          : _LedgerContent(data: state.data),
                    ),
                  ],
                );
              }

              return const SizedBox.shrink();
            },
          ),
    );
  }

  Widget _buildSelectCustomerPrompt(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.search, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'reports.select_customer_prompt'.tr(),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'reports.select_customer_prompt_desc'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printReport(
    BuildContext context,
    CustomerLedgerData data,
  ) async {
    await CustomerLedgerPdfService.printLedger(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_customer_ledger_report',
    );
  }

  Future<void> _shareReport(
    BuildContext context,
    CustomerLedgerData data,
  ) async {
    await CustomerLedgerPdfService.shareLedger(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_customer_ledger_report',
    );
  }
}

// ═══════════════════════════════════════════════════════
// CUSTOMER SELECTOR
// ═══════════════════════════════════════════════════════

class _CustomerSelector extends StatelessWidget {
  final List<CustomerLedgerOption> customers;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

  const _CustomerSelector({
    required this.customers,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SearchablePartySelector(
      labelText: 'reports.select_customer_ledger'.tr(),
      prefixIcon: LucideIcons.user,
      selectedId: selectedId,
      onChanged: onChanged,
      options: customers
          .map(
            (c) => SearchablePartyOption(
              id: c.id,
              name: c.name,
              phone: c.phone,
              balanceCents: c.balanceCents,
            ),
          )
          .toList(),
    );
  }
}

// ═══════════════════════════════════════════════════════
// LEDGER CONTENT
// ═══════════════════════════════════════════════════════

class _LedgerContent extends StatelessWidget {
  final CustomerLedgerData data;

  const _LedgerContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Customer Info Card ──
          _CustomerInfoCard(data: data),
          const SizedBox(height: 16),

          // ── Summary Cards ──
          _SummaryCardsRow(data: data, cs: cs),
          const SizedBox(height: 16),

          // ── Ledger Table ──
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildLedgerTable(context, theme, colorScheme, cs),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerTable(
    BuildContext context,
    ThemeData theme,
    ColorScheme colorScheme,
    CurrencyService cs,
  ) {
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: colorScheme.onPrimaryContainer,
    );
    final groupLabelStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: colorScheme.primary,
      fontSize: 9,
    );
    final subHeaderStyle = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onPrimaryContainer,
      fontSize: 10,
    );
    final cellStyle = theme.textTheme.bodySmall;
    final boldCellStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.bold,
    );

    // Helper to build a two-line column label: category on top, sub-header below
    Widget colLabel(String category, String subHeader) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(category, style: groupLabelStyle, textAlign: TextAlign.center),
          const SizedBox(height: 2),
          Text(subHeader, style: subHeaderStyle, textAlign: TextAlign.center),
        ],
      );
    }

    return DataTable(
      headingRowHeight: 56,
      dataRowMinHeight: 36,
      dataRowMaxHeight: 44,
      columnSpacing: 12,
      horizontalMargin: 12,
      headingRowColor: WidgetStateProperty.all(
        colorScheme.primaryContainer.withValues(alpha: 0.5),
      ),
      columns: [
        // Date
        DataColumn(label: Text('reports.ledger_date'.tr(), style: headerStyle)),
        // Sale Invoices group
        DataColumn(
          label: colLabel(
            'reports.customer_ledger_sale_invoices'.tr(),
            'reports.customer_ledger_sale_number'.tr(),
          ),
        ),
        DataColumn(
          label: colLabel(
            'reports.customer_ledger_sale_invoices'.tr(),
            'reports.customer_ledger_sale_qty'.tr(),
          ),
          numeric: true,
        ),
        DataColumn(
          label: colLabel(
            'reports.customer_ledger_sale_invoices'.tr(),
            'reports.customer_ledger_sale_total'.tr(),
          ),
          numeric: true,
        ),
        // Return Invoices group
        DataColumn(
          label: colLabel(
            'reports.customer_ledger_return_invoices'.tr(),
            'reports.customer_ledger_return_number'.tr(),
          ),
        ),
        DataColumn(
          label: colLabel(
            'reports.customer_ledger_return_invoices'.tr(),
            'reports.customer_ledger_return_qty'.tr(),
          ),
          numeric: true,
        ),
        DataColumn(
          label: colLabel(
            'reports.customer_ledger_return_invoices'.tr(),
            'reports.customer_ledger_return_total'.tr(),
          ),
          numeric: true,
        ),
        // Payments group
        DataColumn(
          label: colLabel(
            'reports.ledger_payments_group'.tr(),
            'reports.ledger_payment_amount'.tr(),
          ),
          numeric: true,
        ),
        DataColumn(
          label: colLabel(
            'reports.ledger_payments_group'.tr(),
            'reports.ledger_payment_number'.tr(),
          ),
        ),
        // Discounts group
        DataColumn(
          label: colLabel(
            'reports.ledger_discounts_group'.tr(),
            'reports.ledger_discount_amount'.tr(),
          ),
          numeric: true,
        ),
        DataColumn(
          label: colLabel(
            'reports.ledger_discounts_group'.tr(),
            'reports.ledger_discount_number'.tr(),
          ),
        ),
        // Balance
        DataColumn(
          label: Text('reports.ledger_balance'.tr(), style: headerStyle),
          numeric: true,
        ),
      ],
      rows: [
        // ── Opening Balance Row ──
        DataRow(
          color: WidgetStateProperty.all(colorScheme.surfaceContainerHighest),
          cells: [
            DataCell(
              Text(
                DateFormat.yMd().format(data.dateRange.startDate),
                style: boldCellStyle,
              ),
            ),
            DataCell(
              Text('reports.opening_balance'.tr(), style: boldCellStyle),
            ),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            DataCell(
              Text(
                cs.formatCents(data.openingBalanceCents),
                style: boldCellStyle?.copyWith(
                  color: data.openingBalanceCents > 0
                      ? colorScheme.error
                      : colorScheme.primary,
                ),
              ),
            ),
          ],
        ),

        // ── Transaction Rows ──
        ...data.rows.map((row) {
          final cashRefundLabel = row.isCashRefundReversal
              ? 'reports.txn_type_refund_reversal'.tr()
              : 'reports.txn_type_refund'.tr();
          final returnLabel = row.isCashRefund
              ? '${row.returnNumber ?? '-'}\n$cashRefundLabel'
              : row.returnNumber ?? '-';
          return DataRow(
            cells: [
              // Date
              DataCell(
                Text(DateFormat.yMd().format(row.date), style: cellStyle),
              ),
              // Sale columns
              DataCell(
                Text(
                  row.saleNumber ?? '-',
                  style: cellStyle?.copyWith(
                    color: row.saleNumber != null ? colorScheme.primary : null,
                  ),
                ),
              ),
              DataCell(
                Text(
                  row.saleItemCount > 0 ? row.saleItemCount.toString() : '-',
                  style: cellStyle,
                ),
              ),
              DataCell(
                Text(
                  row.saleTotalCents != 0
                      ? cs.formatCents(row.saleTotalCents)
                      : '-',
                  style: cellStyle?.copyWith(
                    color: row.saleTotalCents != 0 ? colorScheme.error : null,
                  ),
                ),
              ),
              // Return columns
              DataCell(
                Text(
                  returnLabel,
                  style: cellStyle?.copyWith(
                    color: row.returnNumber != null
                        ? row.isCashRefund
                              ? Colors.orange.shade800
                              : Colors.green.shade700
                        : null,
                    fontWeight: row.isCashRefund ? FontWeight.w700 : null,
                  ),
                ),
              ),
              DataCell(
                Text(
                  row.returnItemCount > 0
                      ? row.returnItemCount.toString()
                      : '-',
                  style: cellStyle,
                ),
              ),
              DataCell(
                Text(
                  row.returnTotalCents != 0
                      ? cs.formatCents(row.returnTotalCents)
                      : '-',
                  style: cellStyle?.copyWith(
                    color: row.returnTotalCents != 0
                        ? row.isCashRefund
                              ? Colors.orange.shade800
                              : Colors.green.shade700
                        : null,
                  ),
                ),
              ),
              // Payment columns
              DataCell(
                Text(
                  row.paymentAmountCents != 0
                      ? cs.formatCents(row.paymentAmountCents)
                      : '-',
                  style: cellStyle?.copyWith(
                    color: row.paymentAmountCents != 0
                        ? Colors.blue.shade700
                        : null,
                  ),
                ),
              ),
              DataCell(
                Text(
                  row.paymentNumber ?? '-',
                  style: cellStyle?.copyWith(
                    color: row.paymentNumber != null
                        ? Colors.blue.shade700
                        : null,
                  ),
                ),
              ),
              // Discount columns
              DataCell(
                Text(
                  row.discountAmountCents != 0
                      ? cs.formatCents(row.discountAmountCents)
                      : '-',
                  style: cellStyle?.copyWith(
                    color: row.discountAmountCents != 0
                        ? Colors.purple.shade700
                        : null,
                  ),
                ),
              ),
              DataCell(
                Text(
                  row.discountNumber ?? '-',
                  style: cellStyle?.copyWith(
                    color: row.discountNumber != null
                        ? Colors.purple.shade700
                        : null,
                  ),
                ),
              ),
              // Balance
              DataCell(
                Text(
                  cs.formatCents(row.runningBalanceCents),
                  style: cellStyle?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: row.runningBalanceCents > 0
                        ? colorScheme.error
                        : colorScheme.primary,
                  ),
                ),
              ),
            ],
          );
        }),

        // ── Subtotals Row ──
        DataRow(
          color: WidgetStateProperty.all(
            colorScheme.secondaryContainer.withValues(alpha: 0.4),
          ),
          cells: [
            DataCell(
              Text('reports.ledger_subtotals'.tr(), style: boldCellStyle),
            ),
            const DataCell(Text('-')),
            DataCell(
              Text(
                data.totalSaleItems != 0 ? data.totalSaleItems.toString() : '-',
                style: boldCellStyle,
              ),
            ),
            DataCell(
              Text(
                cs.formatCents(data.totalSalesCents),
                style: boldCellStyle?.copyWith(color: colorScheme.error),
              ),
            ),
            const DataCell(Text('-')),
            DataCell(
              Text(
                data.totalReturnItems != 0
                    ? data.totalReturnItems.toString()
                    : '-',
                style: boldCellStyle,
              ),
            ),
            DataCell(
              Text(
                cs.formatCents(data.totalReturnsCents),
                style: boldCellStyle?.copyWith(color: Colors.green.shade700),
              ),
            ),
            DataCell(
              Text(
                cs.formatCents(data.totalPaymentsCents),
                style: boldCellStyle?.copyWith(color: Colors.blue.shade700),
              ),
            ),
            const DataCell(Text('-')),
            DataCell(
              Text(
                cs.formatCents(data.totalDiscountsCents),
                style: boldCellStyle?.copyWith(color: Colors.purple.shade700),
              ),
            ),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
          ],
        ),

        // ── Closing Balance Row ──
        DataRow(
          color: WidgetStateProperty.all(colorScheme.surfaceContainerHighest),
          cells: [
            DataCell(
              Text(
                DateFormat.yMd().format(data.dateRange.endDate),
                style: boldCellStyle,
              ),
            ),
            DataCell(
              Text('reports.closing_balance'.tr(), style: boldCellStyle),
            ),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            const DataCell(Text('-')),
            DataCell(
              Text(
                cs.formatCents(data.closingBalanceCents),
                style: boldCellStyle?.copyWith(
                  color: data.closingBalanceCents > 0
                      ? colorScheme.error
                      : colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
// CUSTOMER INFO CARD
// ═══════════════════════════════════════════════════════

class _CustomerInfoCard extends StatelessWidget {
  final CustomerLedgerData data;

  const _CustomerInfoCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: colorScheme.primaryContainer,
              child: Icon(
                LucideIcons.user,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.customerName ?? '',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (data.customerPhone != null &&
                      data.customerPhone!.isNotEmpty)
                    Text(
                      data.customerPhone!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (data.customerAddress != null &&
                      data.customerAddress!.isNotEmpty)
                    Text(
                      data.customerAddress!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

// ═══════════════════════════════════════════════════════
// SUMMARY CARDS ROW
// ═══════════════════════════════════════════════════════

class _SummaryCardsRow extends StatelessWidget {
  final CustomerLedgerData data;
  final CurrencyService cs;

  const _SummaryCardsRow({required this.data, required this.cs});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _SummaryCard(
            label: 'reports.customer_ledger_total_sales'.tr(),
            value: cs.formatCents(data.totalSalesCents),
            icon: LucideIcons.shoppingCart,
            color: Colors.red.shade600,
          ),
          const SizedBox(width: 8),
          _SummaryCard(
            label: 'reports.ledger_total_returns'.tr(),
            value: cs.formatCents(data.totalReturnsCents),
            icon: LucideIcons.arrowLeftRight,
            color: Colors.green.shade600,
          ),
          const SizedBox(width: 8),
          _SummaryCard(
            label: 'reports.ledger_total_payments'.tr(),
            value: cs.formatCents(data.totalPaymentsCents),
            icon: LucideIcons.banknote,
            color: Colors.blue.shade600,
          ),
          const SizedBox(width: 8),
          _SummaryCard(
            label: 'reports.ledger_total_discounts'.tr(),
            value: cs.formatCents(data.totalDiscountsCents),
            icon: LucideIcons.badgePercent,
            color: Colors.purple.shade600,
          ),
          const SizedBox(width: 8),
          _SummaryCard(
            label: 'reports.closing_balance'.tr(),
            value: cs.formatCents(data.closingBalanceCents),
            icon: LucideIcons.wallet,
            color: data.closingBalanceCents > 0
                ? Colors.red.shade600
                : Colors.green.shade600,
          ),
        ],
      ),
    );
  }
}

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
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
