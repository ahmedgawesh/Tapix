import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/supplier_invoices_pdf_service.dart';
import '../bloc/supplier_invoices_report_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/invoice_report_widgets.dart';
import '../widgets/searchable_party_selector.dart';

class SupplierInvoicesReportScreen extends StatelessWidget {
  const SupplierInvoicesReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SupplierInvoicesReportBloc>(),
      child: const _SupplierInvoicesReportView(),
    );
  }
}

class _SupplierInvoicesReportView extends StatelessWidget {
  const _SupplierInvoicesReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.supplier_invoices_report'.tr()),
        actions: [
          BlocBuilder<SupplierInvoicesReportBloc,
              RealtimeState<SupplierInvoicesData>>(
            builder: (context, state) {
              if (state is! RealtimeSuccess<SupplierInvoicesData>) {
                return const SizedBox.shrink();
              }
              if (state.data.supplierId == null ||
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
      body: BlocBuilder<SupplierInvoicesReportBloc,
          RealtimeState<SupplierInvoicesData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<SupplierInvoicesData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<SupplierInvoicesData>) {
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

          if (state is RealtimeSuccess<SupplierInvoicesData>) {
            final data = state.data;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SearchablePartySelector(
                    labelText: 'reports.select_supplier'.tr(),
                    prefixIcon: LucideIcons.truck,
                    selectedId: data.supplierId,
                    onChanged: (id) => context
                        .read<SupplierInvoicesReportBloc>()
                        .add(SupplierInvoicesSupplierChanged(id)),
                    options: data.suppliers
                        .map((s) => SearchablePartyOption(
                              id: s.id,
                              name: s.name,
                              phone: s.phone,
                              balanceCents: s.balanceCents,
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
                        .read<SupplierInvoicesReportBloc>()
                        .add(SupplierInvoicesDateRangeChanged(range)),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: data.supplierId == null
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
          Text('reports.select_supplier_prompt'.tr(),
              style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          Text('reports.supplier_invoices_prompt_desc'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }

  Future<void> _printReport(
      BuildContext context, SupplierInvoicesData data) async {
    await SupplierInvoicesPdfService.printReport(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_supplier_invoices_report',
    );
  }

  Future<void> _shareReport(
      BuildContext context, SupplierInvoicesData data) async {
    await SupplierInvoicesPdfService.shareReport(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_supplier_invoices_report',
    );
  }
}

// ═══════════════════════════════════════════════════════
// CONTENT
// ═══════════════════════════════════════════════════════

class _Content extends StatelessWidget {
  final SupplierInvoicesData data;
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
          name: data.supplierName ?? '',
          phone: data.supplierPhone,
          address: data.supplierAddress,
          icon: LucideIcons.truck,
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
              referenceLabel: inv.supplierInvoiceRef == null
                  ? null
                  : '${'reports.supplier_invoice_ref'.tr()}: ${inv.supplierInvoiceRef}',
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
