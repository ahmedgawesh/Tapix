import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../services/supplier_returns_pdf_service.dart';
import '../bloc/supplier_returns_report_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/invoice_report_widgets.dart';
import '../widgets/searchable_party_selector.dart';

class SupplierReturnsReportScreen extends StatelessWidget {
  const SupplierReturnsReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<SupplierReturnsReportBloc>(),
      child: const _SupplierReturnsReportView(),
    );
  }
}

class _SupplierReturnsReportView extends StatelessWidget {
  const _SupplierReturnsReportView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.supplier_returns_report'.tr()),
        actions: [
          BlocBuilder<
            SupplierReturnsReportBloc,
            RealtimeState<SupplierReturnsData>
          >(
            builder: (context, state) {
              if (state is! RealtimeSuccess<SupplierReturnsData>) {
                return const SizedBox.shrink();
              }
              if (state.data.supplierId == null || state.data.returns.isEmpty) {
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
            SupplierReturnsReportBloc,
            RealtimeState<SupplierReturnsData>
          >(
            builder: (context, state) {
              if (state is RealtimeLoading<SupplierReturnsData>) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state is RealtimeError<SupplierReturnsData>) {
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

              if (state is RealtimeSuccess<SupplierReturnsData>) {
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
                            .read<SupplierReturnsReportBloc>()
                            .add(SupplierReturnsSupplierChanged(id)),
                        options: data.suppliers
                            .map(
                              (s) => SearchablePartyOption(
                                id: s.id,
                                name: s.name,
                                phone: s.phone,
                                balanceCents: s.balanceCents,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DateRangeSelector(
                        dateRange: data.dateRange,
                        onChanged: (range) => context
                            .read<SupplierReturnsReportBloc>()
                            .add(SupplierReturnsDateRangeChanged(range)),
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
          Text(
            'reports.select_supplier_prompt'.tr(),
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'reports.supplier_returns_prompt_desc'.tr(),
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
    SupplierReturnsData data,
  ) async {
    await SupplierReturnsPdfService.printReport(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'print_supplier_returns_report',
    );
  }

  Future<void> _shareReport(
    BuildContext context,
    SupplierReturnsData data,
  ) async {
    await SupplierReturnsPdfService.shareReport(context: context, data: data);
    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
      action: 'share_supplier_returns_report',
    );
  }
}

// ═══════════════════════════════════════════════════════
// CONTENT
// ═══════════════════════════════════════════════════════

class _Content extends StatelessWidget {
  final SupplierReturnsData data;
  const _Content({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    if (data.returns.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.undo2, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'reports.no_returns_in_period'.tr(),
              style: theme.textTheme.bodyLarge,
            ),
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
          invoiceCount: data.returnCount,
          totalQuantityText: localizedQuantityTotals(
            aggregateQuantityTotals(
              data.returns.expand((invoice) => invoice.items),
              quantityOf: (item) => item.quantity,
              measurementTypeOf: (item) => item.measurementType,
            ),
          ),
          totalAmountCents: data.totalAmountCents,
          totalDiscountCents: data.totalDiscountCents,
          totalPaidCents: data.totalAmountCents,
          cs: cs,
        ),
        const SizedBox(height: 12),
        _TypeBreakdown(
          linkedCount: data.linkedCount,
          adjustmentCount: data.adjustmentCount,
        ),
        const SizedBox(height: 16),
        ...data.returns.map(
          (r) => InvoiceCard(
            invoiceNumber: r.returnNumber,
            referenceLabel: _referenceLabel(r),
            date: r.date,
            items: r.items,
            subtotalCents: r.subtotalCents,
            discountCents: r.discountCents,
            taxCents: r.taxCents,
            totalCents: r.totalCents,
            paidAmountCents: r.totalCents,
            paymentMethod: r.refundMethod,
            cs: cs,
          ),
        ),
      ],
    );
  }

  String _referenceLabel(SupplierReturnInvoice r) {
    if (r.isLinked) {
      final ref = r.originalInvoiceNumber;
      if (ref == null || ref.isEmpty) {
        return 'reports.return_linked'.tr();
      }
      return '${'reports.return_linked'.tr()} · ${'reports.original_invoice'.tr()}: $ref';
    }
    return 'reports.return_adjustment'.tr();
  }
}

class _TypeBreakdown extends StatelessWidget {
  final int linkedCount;
  final int adjustmentCount;

  const _TypeBreakdown({
    required this.linkedCount,
    required this.adjustmentCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _Chip(
          icon: LucideIcons.link,
          label: 'reports.return_linked'.tr(),
          count: linkedCount,
          color: Colors.blue.shade600,
        ),
        const SizedBox(width: 8),
        _Chip(
          icon: LucideIcons.unlink,
          label: 'reports.return_adjustment'.tr(),
          count: adjustmentCount,
          color: Colors.orange.shade700,
        ),
        const Spacer(),
        Text(
          '${'reports.invoices_count'.tr()}: ${linkedCount + adjustmentCount}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _Chip({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label ($count)',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
