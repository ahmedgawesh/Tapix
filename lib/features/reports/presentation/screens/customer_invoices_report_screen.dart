import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/customer_invoices_pdf_service.dart';
import '../bloc/customer_invoices_report_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/invoice_report_widgets.dart';
import '../widgets/searchable_party_selector.dart';

class CustomerInvoicesReportScreen extends StatelessWidget {
  const CustomerInvoicesReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<CustomerInvoicesReportBloc>(),
      child: const _CustomerInvoicesReportView(),
    );
  }
}

class _CustomerInvoicesReportView extends StatelessWidget {
  const _CustomerInvoicesReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.customer_invoices_report'.tr()),
        actions: [
          BlocBuilder<CustomerInvoicesReportBloc,
              RealtimeState<CustomerInvoicesData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<CustomerInvoicesData>) {
                return const SizedBox.shrink();
              }
              if (state.data.customerId == null ||
                  state.data.invoices.isEmpty) {
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
      body: BlocBuilder<CustomerInvoicesReportBloc,
          RealtimeState<CustomerInvoicesData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<CustomerInvoicesData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<CustomerInvoicesData>) {
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

          if (state is RealtimeSuccess<CustomerInvoicesData>) {
            final data = state.data;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SearchablePartySelector(
                    labelText: 'reports.select_customer'.tr(),
                    prefixIcon: LucideIcons.user,
                    selectedId: data.customerId,
                    onChanged: (id) => context
                        .read<CustomerInvoicesReportBloc>()
                        .add(CustomerInvoicesCustomerChanged(id)),
                    options: data.customers
                        .map((c) => SearchablePartyOption(
                              id: c.id,
                              name: c.name,
                              phone: c.phone,
                              balanceCents: c.balanceCents,
                            ))
                        .toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DateRangeSelector(
                    dateRange: data.dateRange,
                    onChanged: (range) => context
                        .read<CustomerInvoicesReportBloc>()
                        .add(CustomerInvoicesDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: data.customerId == null
                      ? _buildPrompt(context)
                      : _Content(data: data),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildPrompt(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.search, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('reports.select_customer_prompt'.tr(),
              style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          Text('reports.customer_invoices_prompt_desc'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }

  Future<void> _printReport(
      BuildContext context, CustomerInvoicesData data) async {
    await CustomerInvoicesPdfService.printReport(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_customer_invoices_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, CustomerInvoicesData data) async {
    await CustomerInvoicesPdfService.shareReport(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_customer_invoices_report',
    );
  }
}

// ═══════════════════════════════════════════════════════
// CONTENT
// ═══════════════════════════════════════════════════════

class _Content extends StatelessWidget {
  final CustomerInvoicesData data;
  const _Content({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.invoices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.fileText,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('reports.no_invoices_in_period'.tr(),
                style: theme.textTheme.bodyLarge),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        InvoicePartyInfoCard(
          name: data.customerName ?? '',
          phone: data.customerPhone,
          address: data.customerAddress,
          icon: LucideIcons.user,
        ),
        const SizedBox(height: 12),
        InvoiceSummaryCardsRow(
          invoiceCount: data.invoiceCount,
          totalQuantity: data.totalQuantity,
          totalAmountCents: data.totalAmountCents,
          totalDiscountCents: data.totalDiscountCents,
          totalPaidCents: data.totalPaidCents,
          cs: cs,
        ),
        const SizedBox(height: 16),
        ...data.invoices.map((inv) => InvoiceCard(
              invoiceNumber: inv.invoiceNumber,
              referenceLabel: null,
              date: inv.date,
              items: inv.items,
              subtotalCents: inv.subtotalCents,
              discountCents: inv.discountCents,
              taxCents: inv.taxCents,
              totalCents: inv.totalCents,
              paidAmountCents: inv.paidAmountCents,
              paymentMethod: inv.paymentMethod,
              cs: cs,
            )),
      ],
    );
  }
}
