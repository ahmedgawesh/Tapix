import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/expiry_alert_item.dart';
import '../bloc/expiry_alerts_bloc.dart';

/// Shared with `StockAlertsSection` so all dashboard alert dismissals live
/// in a single SharedPreferences entry and behave identically.
const _kDismissedNotificationsKey = 'dismissed_notifications';

String _expiryNotificationId(int batchId) => 'expiry_batch_$batchId';

/// Dashboard section for the Phase E expiry alerts.
///
/// Mirrors the visual language of `StockAlertsSection` so the two sit side-
/// by-side without UI dissonance. Both surfaces are powered by independent
/// realtime streams; this one streams from [ExpiryAlertsBloc].
///
/// Behaviour:
///   * Returns `SizedBox.shrink()` when there are zero alerts (no chrome
///     when the user has nothing to act on — same UX rule as the stock
///     alerts section).
///   * Shows three pill-shaped count badges (expired / 30d / 60d / 90d).
///     Buckets with `count == 0` are hidden so the row never shows zero
///     pills.
///   * Lists the first three rows as a preview. A "View full report" link
///     navigates to the `/reports/expiry` screen for the full table with
///     filters.
class ExpiryAlertsSection extends StatelessWidget {
  const ExpiryAlertsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ExpiryAlertsBloc>(
      create: (_) => sl<ExpiryAlertsBloc>(),
      child: const _ExpiryAlertsSectionView(),
    );
  }
}

class _ExpiryAlertsSectionView extends StatefulWidget {
  const _ExpiryAlertsSectionView();

  @override
  State<_ExpiryAlertsSectionView> createState() =>
      _ExpiryAlertsSectionViewState();
}

class _ExpiryAlertsSectionViewState extends State<_ExpiryAlertsSectionView> {
  Set<String> _dismissed = <String>{};

  @override
  void initState() {
    super.initState();
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    final prefs = sl<SharedPreferences>();
    final stored = prefs.getStringList(_kDismissedNotificationsKey) ?? const [];
    if (mounted) setState(() => _dismissed = stored.toSet());
  }

  Future<void> _dismissIds(Iterable<String> ids) async {
    final prefs = sl<SharedPreferences>();
    _dismissed.addAll(ids);
    await prefs.setStringList(
      _kDismissedNotificationsKey,
      _dismissed.toList(),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ExpiryAlertsBloc, RealtimeState<ExpiryAlertSnapshot>>(
      builder: (context, state) {
        if (state is! RealtimeSuccess<ExpiryAlertSnapshot>) {
          return const SizedBox.shrink();
        }
        final snapshot = state.data;
        if (snapshot.summary.isEmpty) {
          return const SizedBox.shrink();
        }

        // Filter out dismissed batches. New batches (different batchId)
        // surface again automatically — same UX rule as StockAlertsSection.
        final visibleItems = snapshot.items
            .where((it) => !_dismissed.contains(_expiryNotificationId(it.batchId)))
            .toList(growable: false);
        if (visibleItems.isEmpty) {
          return const SizedBox.shrink();
        }

        final visibleSummary = _summarize(visibleItems);
        final visibleSnapshot = ExpiryAlertSnapshot(
          items: visibleItems,
          summary: visibleSummary,
        );

        return _ExpiryAlertsCard(
          snapshot: visibleSnapshot,
          onDismiss: () => _dismissIds(
            visibleItems.map((it) => _expiryNotificationId(it.batchId)),
          ),
        );
      },
    );
  }

  static ExpiryAlertSummary _summarize(List<ExpiryAlertItem> items) {
    var expired = 0, d30 = 0, d60 = 0, d90 = 0, expiredCost = 0;
    for (final it in items) {
      switch (it.bucket) {
        case ExpiryBucket.expired:
          expired++;
          expiredCost += it.totalCostCents;
          break;
        case ExpiryBucket.in30Days:
          d30++;
          break;
        case ExpiryBucket.in60Days:
          d60++;
          break;
        case ExpiryBucket.in90Days:
          d90++;
          break;
      }
    }
    return ExpiryAlertSummary(
      expiredCount: expired,
      in30DaysCount: d30,
      in60DaysCount: d60,
      in90DaysCount: d90,
      expiredCostCents: expiredCost,
    );
  }
}

class _ExpiryAlertsCard extends StatelessWidget {
  final ExpiryAlertSnapshot snapshot;
  final VoidCallback onDismiss;

  const _ExpiryAlertsCard({
    required this.snapshot,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final summary = snapshot.summary;

    // Highlight color follows the worst-severity bucket present.
    final hasExpired = summary.expiredCount > 0;
    final accent = hasExpired ? colorScheme.error : Colors.orange;
    final bg = isDark
        ? accent.withValues(alpha: 0.12)
        : accent.withValues(alpha: 0.08);

    final preview = snapshot.items.take(3).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header — same language as stock_alerts_section.
          Row(
            children: [
              Icon(LucideIcons.calendarClock, size: 20, color: accent),
              const SizedBox(width: 8),
              Text(
                'reports.expiry_alerts_title'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${summary.totalAlertCount}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Dismissible(
            key: const Key('expiry_alerts_card'),
            direction: DismissDirection.horizontal,
            onDismissed: (_) => onDismiss(),
            background: _buildDismissBackground(context, Alignment.centerLeft),
            secondaryBackground:
                _buildDismissBackground(context, Alignment.centerRight),
            child: Card(
            elevation: 0,
            color: bg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: accent.withValues(alpha: 0.2)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bucket pills row.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (summary.expiredCount > 0)
                        _BucketPill(
                          label: 'reports.expiry_alerts_count_expired'
                              .tr(args: ['${summary.expiredCount}']),
                          color: colorScheme.error,
                        ),
                      if (summary.in30DaysCount > 0)
                        _BucketPill(
                          label: 'reports.expiry_alerts_count_30'
                              .tr(args: ['${summary.in30DaysCount}']),
                          color: Colors.orange,
                        ),
                      if (summary.in60DaysCount > 0)
                        _BucketPill(
                          label: 'reports.expiry_alerts_count_60'
                              .tr(args: ['${summary.in60DaysCount}']),
                          color: Colors.amber.shade700,
                        ),
                      if (summary.in90DaysCount > 0)
                        _BucketPill(
                          label: 'reports.expiry_alerts_count_90'
                              .tr(args: ['${summary.in90DaysCount}']),
                          color: Colors.blueGrey,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Potential write-off line (only when there's already-
                  // expired stock — otherwise the figure is misleading).
                  if (summary.expiredCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'reports.expiry_alerts_potential_writeoff'.tr(args: [
                          sl<CurrencyService>()
                              .format(summary.expiredCostCents),
                        ]),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                  // Preview rows.
                  ...preview.map((item) => _ExpiryAlertRow(item: item)),

                  if (snapshot.items.length > preview.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'dashboard.and_more'.tr(args: [
                          '${snapshot.items.length - preview.length}',
                        ]),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Footer link.
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => context.push('/reports/expiry'),
                      icon: const Icon(LucideIcons.fileText, size: 16),
                      label: Text('reports.expiry_alerts_view_all'.tr()),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ],
      ),
    );
  }

  Widget _buildDismissBackground(BuildContext context, Alignment alignment) {
    final theme = Theme.of(context);
    final isLeft = alignment == Alignment.centerLeft;
    return Container(
      alignment: alignment,
      padding: EdgeInsets.only(
        left: isLeft ? 20 : 0,
        right: isLeft ? 0 : 20,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(
        LucideIcons.trash2,
        color: theme.colorScheme.onErrorContainer,
      ),
    );
  }
}

class _BucketPill extends StatelessWidget {
  final String label;
  final Color color;

  const _BucketPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ExpiryAlertRow extends StatelessWidget {
  final ExpiryAlertItem item;

  const _ExpiryAlertRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorForBucket(item.bucket, theme);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(LucideIcons.package, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _composeLabel(item),
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _statusFor(item),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static String _composeLabel(ExpiryAlertItem item) {
    final parts = <String>[item.productName];
    if (item.variantLabel.isNotEmpty) parts.add('(${item.variantLabel})');
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
