import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/customer_payment_pdf_service.dart';
import '../bloc/customer_payment_reports_bloc.dart';
import '../widgets/date_range_selector.dart';

class CustomerPaymentReportsScreen extends StatelessWidget {
  const CustomerPaymentReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CustomerPaymentReportsBloc>(),
      child: const _CustomerPaymentReportsView(),
    );
  }
}

class _CustomerPaymentReportsView extends StatelessWidget {
  const _CustomerPaymentReportsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.customer_payments'.tr()),
        actions: [
          BlocBuilder<CustomerPaymentReportsBloc,
              RealtimeState<CustomerPaymentReportsData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<CustomerPaymentReportsData>) {
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
      body: BlocBuilder<CustomerPaymentReportsBloc,
          RealtimeState<CustomerPaymentReportsData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<CustomerPaymentReportsData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<CustomerPaymentReportsData>) {
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

          if (state is RealtimeSuccess<CustomerPaymentReportsData>) {
            return Column(
              children: [
                // Date range selector
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: DateRangeSelector(
                    dateRange: state.data.dateRange,
                    onChanged: (range) => context
                        .read<CustomerPaymentReportsBloc>()
                        .add(CustomerPaymentReportsDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 8),

                // Summary cards
                _buildSummaryCards(context, state.data),
                const SizedBox(height: 8),

                // Content
                Expanded(
                  child: _PaymentReportContent(data: state.data),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildSummaryCards(
      BuildContext context, CustomerPaymentReportsData data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          final cards = [
            _SummaryCard(
              label: 'reports.total_payments'.tr(),
              value: cs.formatCents(data.totalAmountCents),
              icon: LucideIcons.banknote,
              color: colorScheme.primary,
            ),
            _SummaryCard(
              label: 'reports.payment_count'.tr(),
              value: data.transactionCount.toString(),
              icon: LucideIcons.receipt,
              color: colorScheme.tertiary,
            ),
            _SummaryCard(
              label: 'reports.paying_customers'.tr(),
              value: data.uniqueCustomerCount.toString(),
              icon: LucideIcons.users,
              color: colorScheme.secondary,
            ),
          ];

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
      ),
    );
  }

  Future<void> _printReport(
      BuildContext context, CustomerPaymentReportsData data) async {
    await CustomerPaymentPdfService.printCustomerPaymentReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_customer_payment_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, CustomerPaymentReportsData data) async {
    await CustomerPaymentPdfService.shareCustomerPaymentReport(
      context: context,
      data: data,
    );
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_customer_payment_report',
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
// PAYMENT REPORT CONTENT
// ═══════════════════════════════════════════════════════

class _PaymentReportContent extends StatelessWidget {
  final CustomerPaymentReportsData data;
  const _PaymentReportContent({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.methodSummaries.isEmpty && data.details.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.banknote,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('reports.no_payment_data'.tr(),
                style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text('reports.no_payment_data_desc'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Payment method breakdown
        if (data.methodSummaries.isNotEmpty) ...[
          Text('reports.payment_method_breakdown'.tr(),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...data.methodSummaries.map((summary) => _PaymentMethodCard(
                summary: summary,
                isSelected: data.methodFilter == summary.method,
                onTap: () {
                  final bloc = context.read<CustomerPaymentReportsBloc>();
                  if (data.methodFilter == summary.method) {
                    bloc.add(
                        const CustomerPaymentReportsMethodFilterChanged(null));
                  } else {
                    bloc.add(CustomerPaymentReportsMethodFilterChanged(
                        summary.method));
                  }
                },
              )),
          const SizedBox(height: 8),
          // Totals row
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'reports.grand_total'.tr(),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    cs.formatCents(data.totalAmountCents),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Payment details table
        if (data.details.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('reports.payment_details'.tr(),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              if (data.methodFilter != null)
                TextButton.icon(
                  onPressed: () => context
                      .read<CustomerPaymentReportsBloc>()
                      .add(const CustomerPaymentReportsMethodFilterChanged(
                          null)),
                  icon: const Icon(LucideIcons.x, size: 14),
                  label: Text('reports.clear_filter'.tr()),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              horizontalMargin: 8,
              columns: [
                DataColumn(label: Text('reports.date'.tr())),
                DataColumn(label: Text('reports.customer'.tr())),
                DataColumn(label: Text('reports.type'.tr())),
                DataColumn(
                    label: Text('reports.amount'.tr()), numeric: true),
                DataColumn(label: Text('reports.description_col'.tr())),
              ],
              rows: data.details.map((detail) {
                return DataRow(cells: [
                  DataCell(Text(
                    DateFormat.yMd().format(detail.transactionDate),
                    style: theme.textTheme.bodySmall,
                  )),
                  DataCell(Text(
                    detail.customerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )),
                  DataCell(Text(
                    _transactionTypeLabel(detail.transactionType),
                    style: theme.textTheme.bodySmall,
                  )),
                  DataCell(Text(
                    cs.formatCents(detail.amountCents.abs()),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: detail.amountCents < 0
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  )),
                  DataCell(Text(
                    detail.description ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )),
                ]);
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  String _transactionTypeLabel(String type) {
    switch (type) {
      case 'payment':
        return 'reports.payment_type_payment'.tr();
      case 'receipt':
        return 'reports.payment_type_receipt'.tr();
      case 'settlement':
        return 'reports.payment_type_settlement'.tr();
      default:
        return type;
    }
  }
}

// ═══════════════════════════════════════════════════════
// PAYMENT METHOD CARD
// ═══════════════════════════════════════════════════════

class _PaymentMethodCard extends StatelessWidget {
  final PaymentMethodSummary summary;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodCard({
    required this.summary,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    final methodColor = _methodColor(summary.method, colorScheme);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: methodColor, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Method icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: methodColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _methodIcon(summary.method),
                  size: 20,
                  color: methodColor,
                ),
              ),
              const SizedBox(width: 12),
              // Method name and count
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _methodLabel(summary.method),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'reports.transaction_count'
                          .tr(args: ['${summary.transactionCount}']),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Amount and percentage
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    cs.formatCents(summary.amountCents),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: methodColor,
                    ),
                  ),
                  Text(
                    '${summary.percentage.toStringAsFixed(1)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _methodIcon(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return LucideIcons.banknote;
      case 'card':
        return LucideIcons.creditCard;
      case 'bank':
      case 'bank_transfer':
        return LucideIcons.building2;
      case 'credit':
      case 'pay_later':
        return LucideIcons.clock;
      case 'payment':
        return LucideIcons.wallet;
      case 'receipt':
        return LucideIcons.receipt;
      case 'settlement':
        return LucideIcons.checkCircle;
      default:
        return LucideIcons.circleDollarSign;
    }
  }

  Color _methodColor(String method, ColorScheme colorScheme) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Colors.green;
      case 'card':
        return colorScheme.primary;
      case 'bank':
      case 'bank_transfer':
        return colorScheme.tertiary;
      case 'credit':
      case 'pay_later':
        return Colors.orange;
      case 'payment':
        return Colors.green;
      case 'receipt':
        return colorScheme.primary;
      case 'settlement':
        return colorScheme.tertiary;
      default:
        return colorScheme.secondary;
    }
  }

  String _methodLabel(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'reports.method_cash'.tr();
      case 'card':
        return 'reports.method_card'.tr();
      case 'bank':
      case 'bank_transfer':
        return 'reports.method_bank'.tr();
      case 'credit':
      case 'pay_later':
        return 'reports.method_credit'.tr();
      case 'payment':
        return 'reports.payment_type_payment'.tr();
      case 'receipt':
        return 'reports.payment_type_receipt'.tr();
      case 'settlement':
        return 'reports.payment_type_settlement'.tr();
      default:
        return method;
    }
  }
}
