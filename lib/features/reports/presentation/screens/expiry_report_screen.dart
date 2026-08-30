import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../../../../core/services/currency_service.dart';
import '../../../inventory/domain/entities/expiry_alert_item.dart';
import '../../../inventory/presentation/bloc/expiry_alerts_bloc.dart';

/// Phase E full expiry report.
///
/// Reads from the same [ExpiryAlertsBloc] that powers the dashboard widget,
/// guaranteeing identical numbers between the two surfaces. The screen adds:
///   * a filter chip row (All / Expired / ≤30 / ≤60 / ≤90 days),
///   * a sortable, scannable list grouped by bucket,
///   * a header strip with bucket counters & potential write-off value.
///
/// World-standards alignment:
///   * 30/60/90-day buckets — same cadence as Odoo, SAP B1, NetSuite, QB
///     Enterprise.
///   * Already-expired rows are highlighted (red) with the "expired N days
///     ago" hint that pharmacy POS systems display.
///   * The list is FEFO-ordered (`ORDER BY expiry_date ASC` in the service)
///     so the row at the top is the most urgent action item.
class ExpiryReportScreen extends StatelessWidget {
  const ExpiryReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ExpiryAlertsBloc>(
      create: (_) => sl<ExpiryAlertsBloc>(),
      child: const _ExpiryReportView(),
    );
  }
}

class _ExpiryReportView extends StatefulWidget {
  const _ExpiryReportView();

  @override
  State<_ExpiryReportView> createState() => _ExpiryReportViewState();
}

class _ExpiryReportViewState extends State<_ExpiryReportView> {
  /// `null` means "All buckets". Otherwise filter to that exact bucket.
  ExpiryBucket? _filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('reports.expiry_report_title'.tr())),
      body: BlocBuilder<ExpiryAlertsBloc, RealtimeState<ExpiryAlertSnapshot>>(
        builder: (context, state) {
          if (state is RealtimeLoading<ExpiryAlertSnapshot>) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is RealtimeError<ExpiryAlertSnapshot>) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  state.error.toString(),
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (state is! RealtimeSuccess<ExpiryAlertSnapshot>) {
            return const SizedBox.shrink();
          }

          final snapshot = state.data;
          final visible = _applyFilter(snapshot.items, _filter);

          return Column(
            children: [
              _Header(snapshot: snapshot),
              _FilterRow(
                value: _filter,
                summary: snapshot.summary,
                onChanged: (v) => setState(() => _filter = v),
              ),
              const Divider(height: 1),
              Expanded(
                child: visible.isEmpty
                    ? _EmptyState(filter: _filter)
                    : _AlertList(items: visible),
              ),
            ],
          );
        },
      ),
    );
  }

  static List<ExpiryAlertItem> _applyFilter(
    List<ExpiryAlertItem> items,
    ExpiryBucket? filter,
  ) {
    if (filter == null) return items;
    return items.where((i) => i.bucket == filter).toList();
  }
}

class _Header extends StatelessWidget {
  final ExpiryAlertSnapshot snapshot;

  const _Header({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'reports.expiry_report_subtitle'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (snapshot.summary.expiredCount > 0) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertOctagon, color: colorScheme.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'reports.expiry_alerts_potential_writeoff'.tr(
                        args: [
                          sl<CurrencyService>().format(
                            snapshot.summary.expiredCostCents,
                          ),
                        ],
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  final ExpiryBucket? value;
  final ExpiryAlertSummary summary;
  final ValueChanged<ExpiryBucket?> onChanged;

  const _FilterRow({
    required this.value,
    required this.summary,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _Chip(
              label: 'reports.expiry_report_filter_all'.tr(),
              count: summary.totalAlertCount,
              selected: value == null,
              onSelected: () => onChanged(null),
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'reports.expiry_report_filter_expired'.tr(),
              count: summary.expiredCount,
              selected: value == ExpiryBucket.expired,
              onSelected: () => onChanged(ExpiryBucket.expired),
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'reports.expiry_report_filter_30'.tr(),
              count: summary.in30DaysCount,
              selected: value == ExpiryBucket.in30Days,
              onSelected: () => onChanged(ExpiryBucket.in30Days),
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'reports.expiry_report_filter_60'.tr(),
              count: summary.in60DaysCount,
              selected: value == ExpiryBucket.in60Days,
              onSelected: () => onChanged(ExpiryBucket.in60Days),
            ),
            const SizedBox(width: 8),
            _Chip(
              label: 'reports.expiry_report_filter_90'.tr(),
              count: summary.in90DaysCount,
              selected: value == ExpiryBucket.in90Days,
              onSelected: () => onChanged(ExpiryBucket.in90Days),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onSelected;

  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text('$label ($count)'),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ExpiryBucket? filter;

  const _EmptyState({required this.filter});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final messageKey = filter == null
        ? 'reports.expiry_alerts_empty'
        : 'reports.expiry_report_empty_filter';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.checkCircle, size: 64, color: colorScheme.primary),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              messageKey.tr(),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertList extends StatelessWidget {
  final List<ExpiryAlertItem> items;

  const _AlertList({required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _AlertTile(item: items[i]),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final ExpiryAlertItem item;

  const _AlertTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorForBucket(item.bucket, theme);
    final dateFormat = DateFormat.yMMMd(context.locale.toString());

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.16),
        child: Icon(_iconForBucket(item.bucket), color: color, size: 20),
      ),
      title: Text(
        _composeLabel(item),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            '${'reports.expiry_report_col_batch'.tr()}: ${item.batchNumber}',
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${'reports.expiry_report_col_expiry'.tr()}: ${dateFormat.format(item.expiryDate)}  •  '
            '${'reports.expiry_report_col_qty'.tr()}: ${localizedQuantity(item.remainingQuantity, item.measurementType)}',
            style: theme.textTheme.bodySmall?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _statusFor(item),
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sl<CurrencyService>().format(item.totalCostCents),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      isThreeLine: true,
    );
  }

  static String _composeLabel(ExpiryAlertItem item) {
    final parts = <String>[item.productName];
    if (item.variantLabel.isNotEmpty) parts.add('(${item.variantLabel})');
    if (item.sku != null && item.sku!.isNotEmpty) parts.add('— ${item.sku}');
    return parts.join(' ');
  }

  static String _statusFor(ExpiryAlertItem item) {
    final d = item.daysUntilExpiry;
    if (d < 0) {
      return 'reports.expiry_report_status_expired_days'.tr(args: ['${-d}']);
    }
    if (d == 0) return 'reports.expiry_report_status_today'.tr();
    return 'reports.expiry_report_status_in_days'.tr(args: ['$d']);
  }

  static IconData _iconForBucket(ExpiryBucket bucket) {
    switch (bucket) {
      case ExpiryBucket.expired:
        return LucideIcons.alertOctagon;
      case ExpiryBucket.in30Days:
        return LucideIcons.alertTriangle;
      case ExpiryBucket.in60Days:
        return LucideIcons.calendarClock;
      case ExpiryBucket.in90Days:
        return LucideIcons.calendar;
    }
  }

  static Color _colorForBucket(ExpiryBucket bucket, ThemeData theme) {
    switch (bucket) {
      case ExpiryBucket.expired:
        return theme.colorScheme.error;
      case ExpiryBucket.in30Days:
        return Colors.orange;
      case ExpiryBucket.in60Days:
        return Colors.amber.shade700;
      case ExpiryBucket.in90Days:
        return Colors.blueGrey;
    }
  }
}
