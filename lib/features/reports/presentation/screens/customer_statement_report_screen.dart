import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/customer_statement_pdf_service.dart';
import '../bloc/customer_statement_report_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/searchable_party_selector.dart';

class CustomerStatementReportScreen extends StatelessWidget {
  const CustomerStatementReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CustomerStatementReportBloc>(),
      child: const _CustomerStatementReportView(),
    );
  }
}

class _CustomerStatementReportView extends StatelessWidget {
  const _CustomerStatementReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.customer_statement_report'.tr()),
        actions: [
          BlocBuilder<CustomerStatementReportBloc,
              RealtimeState<CustomerStatementData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<CustomerStatementData>) {
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
      body: BlocBuilder<CustomerStatementReportBloc,
          RealtimeState<CustomerStatementData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<CustomerStatementData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<CustomerStatementData>) {
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

          if (state is RealtimeSuccess<CustomerStatementData>) {
            return Column(
              children: [
                // Customer selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _CustomerSelector(
                    customers: state.data.customers,
                    selectedId: state.data.customerId,
                    onChanged: (id) => context
                        .read<CustomerStatementReportBloc>()
                        .add(CustomerStatementReportCustomerChanged(id)),
                  ),
                ),
                const SizedBox(height: 8),

                // Date range selector
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<CustomerStatementReportBloc>()
                        .add(CustomerStatementReportDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 8),

                // Content
                Expanded(
                  child: state.data.customerId == null
                      ? _buildSelectCustomerPrompt(context)
                      : _StatementContent(data: state.data),
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
          Icon(LucideIcons.search,
              size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('reports.select_customer_prompt'.tr(),
              style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          Text('reports.select_customer_prompt_desc'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }

  Future<void> _printReport(
      BuildContext context, CustomerStatementData data) async {
    await CustomerStatementPdfService.printCustomerStatement(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_customer_statement_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, CustomerStatementData data) async {
    await CustomerStatementPdfService.shareCustomerStatement(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_customer_statement_report',
    );
  }
}

// ═══════════════════════════════════════════════════════
// CUSTOMER SELECTOR
// ═══════════════════════════════════════════════════════

class _CustomerSelector extends StatelessWidget {
  final List<CustomerOption> customers;
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
      labelText: 'reports.select_customer'.tr(),
      prefixIcon: LucideIcons.user,
      selectedId: selectedId,
      onChanged: onChanged,
      options: customers
          .map((c) => SearchablePartyOption(
                id: c.id,
                name: c.name,
                phone: c.phone,
                balanceCents: c.balanceCents,
              ))
          .toList(),
    );
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
// STATEMENT CONTENT
// ═══════════════════════════════════════════════════════

class _StatementContent extends StatelessWidget {
  final CustomerStatementData data;
  const _StatementContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Customer info card
        _buildCustomerInfoCard(context),
        const SizedBox(height: 12),

        // Summary cards
        _buildSummaryCards(context, cs),
        const SizedBox(height: 12),

        // Balance summary card
        _buildBalanceSummary(context, cs),
        const SizedBox(height: 16),

        // Transaction list header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('reports.statement_transactions'.tr(),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(
              'reports.customer_count'
                  .tr(args: ['${data.transactionCount}']),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Transaction table
        if (data.transactions.isEmpty)
          _buildEmptyTransactions(context)
        else
          _buildTransactionTable(context, cs),

        const SizedBox(height: 8),

        // Closing balance footer
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'reports.closing_balance'.tr(),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  cs.formatCents(data.closingBalanceCents),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: data.closingBalanceCents > 0
                        ? colorScheme.error
                        : colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerInfoCard(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.user, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    data.customerName ?? '',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (data.customerSegment != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      data.customerSegment!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            if (data.customerPhone != null &&
                data.customerPhone!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(LucideIcons.phone,
                      size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(data.customerPhone!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      )),
                ],
              ),
            ],
            if (data.customerEmail != null &&
                data.customerEmail!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(LucideIcons.mail,
                      size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(data.customerEmail!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
            if (data.customerAddress != null &&
                data.customerAddress!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(LucideIcons.mapPin,
                      size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(data.customerAddress!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context, CurrencyService cs) {
    final colorScheme = Theme.of(context).colorScheme;

    final cards = [
      _SummaryCard(
        label: 'reports.opening_balance'.tr(),
        value: cs.formatCents(data.openingBalanceCents),
        icon: LucideIcons.arrowRightCircle,
        color: colorScheme.primary,
      ),
      _SummaryCard(
        label: 'reports.total_debits'.tr(),
        value: cs.formatCents(data.totalDebitsCents),
        icon: LucideIcons.arrowUpCircle,
        color: data.totalDebitsCents > 0
            ? colorScheme.error
            : colorScheme.primary,
      ),
      _SummaryCard(
        label: 'reports.total_credits'.tr(),
        value: cs.formatCents(data.totalCreditsCents),
        icon: LucideIcons.arrowDownCircle,
        color: colorScheme.tertiary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        if (isWide) {
          return Row(
            children: cards
                .map((c) => Expanded(
                        child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: c,
                    )))
                .toList(),
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: cards[0],
                )),
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: cards[1],
                )),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: cards[2]),
          ],
        );
      },
    );
  }

  Widget _buildBalanceSummary(BuildContext context, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('reports.balance_summary'.tr(),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _BalanceSummaryRow(
              label: 'reports.opening_balance'.tr(),
              value: cs.formatCents(data.openingBalanceCents),
              color: colorScheme.onSurface,
            ),
            _BalanceSummaryRow(
              label: 'reports.total_debits'.tr(),
              value: '+ ${cs.formatCents(data.totalDebitsCents)}',
              color: colorScheme.error,
            ),
            _BalanceSummaryRow(
              label: 'reports.total_credits'.tr(),
              value: '- ${cs.formatCents(data.totalCreditsCents)}',
              color: colorScheme.tertiary,
            ),
            const Divider(),
            _BalanceSummaryRow(
              label: 'reports.closing_balance'.tr(),
              value: cs.formatCents(data.closingBalanceCents),
              color: data.closingBalanceCents > 0
                  ? colorScheme.error
                  : colorScheme.primary,
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTransactions(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.fileText,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('reports.no_transactions_in_period'.tr(),
                style: theme.textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTable(BuildContext context, CurrencyService cs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        horizontalMargin: 8,
        columns: [
          DataColumn(label: Text('reports.date'.tr())),
          DataColumn(label: Text('reports.type'.tr())),
          DataColumn(label: Text('reports.description'.tr())),
          DataColumn(
            label: Text('reports.debit'.tr()),
            numeric: true,
          ),
          DataColumn(
            label: Text('reports.credit'.tr()),
            numeric: true,
          ),
          DataColumn(
            label: Text('reports.balance'.tr()),
            numeric: true,
          ),
        ],
        rows: [
          // Opening balance row
          DataRow(
            color: WidgetStateProperty.all(
                colorScheme.surfaceContainerHighest),
            cells: [
              DataCell(Text(
                DateFormat.yMd().format(data.dateRange.startDate),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              )),
              DataCell(Text(
                'reports.opening_balance'.tr(),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              )),
              const DataCell(Text('-')),
              const DataCell(Text('-')),
              const DataCell(Text('-')),
              DataCell(Text(
                cs.formatCents(data.openingBalanceCents),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              )),
            ],
          ),
          // Transaction rows
          ...data.transactions.map((txn) {
            final isDebit = txn.amountCents > 0;
            return DataRow(cells: [
              DataCell(Text(
                DateFormat.yMd().format(txn.date),
                style: theme.textTheme.bodySmall,
              )),
              DataCell(Text(
                _localizeTransactionType(txn.type),
                style: theme.textTheme.bodySmall,
              )),
              DataCell(
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: Text(
                    txn.description ?? '-',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(Text(
                isDebit ? cs.formatCents(txn.amountCents) : '-',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              )),
              DataCell(Text(
                !isDebit ? cs.formatCents(txn.amountCents.abs()) : '-',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.tertiary,
                ),
              )),
              DataCell(Text(
                cs.formatCents(txn.runningBalanceCents),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: txn.runningBalanceCents > 0
                      ? colorScheme.error
                      : colorScheme.primary,
                ),
              )),
            ]);
          }),
          // Closing balance row
          DataRow(
            color: WidgetStateProperty.all(
                colorScheme.surfaceContainerHighest),
            cells: [
              DataCell(Text(
                DateFormat.yMd().format(data.dateRange.endDate),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              )),
              DataCell(Text(
                'reports.closing_balance'.tr(),
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              )),
              const DataCell(Text('-')),
              DataCell(Text(
                cs.formatCents(data.totalDebitsCents),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.error,
                ),
              )),
              DataCell(Text(
                cs.formatCents(data.totalCreditsCents),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.tertiary,
                ),
              )),
              DataCell(Text(
                cs.formatCents(data.closingBalanceCents),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: data.closingBalanceCents > 0
                      ? colorScheme.error
                      : colorScheme.primary,
                ),
              )),
            ],
          ),
        ],
      ),
    );
  }

  String _localizeTransactionType(String type) {
    switch (type) {
      case 'sale':
        return 'reports.txn_type_sale'.tr();
      case 'payment':
        return 'reports.txn_type_payment'.tr();
      case 'return':
        return 'reports.txn_type_return'.tr();
      case 'refund':
        return 'reports.txn_type_refund'.tr();
      case 'adjustment':
        return 'reports.txn_type_adjustment'.tr();
      case 'credit_note':
        return 'reports.txn_type_credit_note'.tr();
      case 'opening_balance':
        return 'reports.txn_type_opening_balance'.tr();
      default:
        return type;
    }
  }
}

// ═══════════════════════════════════════════════════════
// BALANCE SUMMARY ROW
// ═══════════════════════════════════════════════════════

class _BalanceSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isBold;

  const _BalanceSummaryRow({
    required this.label,
    required this.value,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = isBold
        ? Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(fontWeight: FontWeight.bold, color: color)
        : Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
