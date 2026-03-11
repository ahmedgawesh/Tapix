import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../services/daily_sales_pdf_service.dart';

/// Key used to store dismissed daily summary date in SharedPreferences.
const _kDismissedDailySummaryKey = 'dismissed_daily_summary_date';

/// Dashboard section that shows daily sales summary notification.
class DailySalesSummarySection extends StatefulWidget {
  const DailySalesSummarySection({super.key});

  @override
  State<DailySalesSummarySection> createState() => _DailySalesSummarySectionState();
}

class _DailySalesSummarySectionState extends State<DailySalesSummarySection> {
  late final AppDatabase _db;
  late final CurrencyService _cs;
  StreamSubscription<DailySalesSummary?>? _summarySub;
  DailySalesSummary? _summary;
  bool _isDismissed = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _db = sl<AppDatabase>();
    _cs = sl<CurrencyService>();
    _checkDismissed();
    _subscribeSummary();
  }

  @override
  void dispose() {
    _summarySub?.cancel();
    super.dispose();
  }

  Future<void> _checkDismissed() async {
    final prefs = sl<SharedPreferences>();
    final dismissedDate = prefs.getString(_kDismissedDailySummaryKey);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    if (dismissedDate == today) {
      if (mounted) setState(() => _isDismissed = true);
    }
  }

  void _subscribeSummary() {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    _summarySub = _db.customSelect(
      '''
      SELECT 
        COUNT(DISTINCT s.id) AS sale_count,
        COALESCE(SUM(s.total_cents), 0) AS total_sales_cents,
        COALESCE(SUM(s.subtotal_cents - s.discount_cents), 0) AS revenue_cents,
        COALESCE(SUM(
          (SELECT SUM(si.quantity * COALESCE(v.cost_cents, p.cost_cents))
           FROM sale_items si
           LEFT JOIN product_variants v ON v.id = si.variant_id
           LEFT JOIN products p ON p.id = si.product_id
           WHERE si.sale_id = s.id)
        ), 0) AS cost_cents
      FROM sales s
      WHERE s.sale_date >= ? AND s.sale_date < ?
        AND s.status != 'draft'
      ''',
      variables: [
        Variable.withDateTime(startOfDay),
        Variable.withDateTime(endOfDay),
      ],
      readsFrom: {_db.sales, _db.saleItems, _db.products, _db.productVariants},
    ).watch().map((rows) {
      if (rows.isEmpty) {
        return null;
      }
      final row = rows.first;
      final saleCount = row.read<int>('sale_count');
      if (saleCount == 0) {
        return null;
      }
      
      return DailySalesSummary(
        saleCount: saleCount,
        totalSalesCents: row.read<int>('total_sales_cents'),
        revenueCents: row.read<int>('revenue_cents'),
        costCents: row.read<int>('cost_cents'),
      );
    }).listen((summary) {
      if (mounted) {
        setState(() {
          _summary = summary;
          _loaded = true;
        });
      }
    });
  }

  Future<void> _dismiss() async {
    final prefs = sl<SharedPreferences>();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await prefs.setString(_kDismissedDailySummaryKey, today);
    if (mounted) setState(() => _isDismissed = true);
  }

  Future<void> _generateReport(BuildContext context) async {
    try {
      await DailySalesPdfService.printDailySummary(context: context);
    } catch (e, stackTrace) {
      debugPrint('Daily Sales PDF Error: $e');
      debugPrint('Stack trace: $stackTrace');
      // Don't show error if user cancelled the print dialog
      if (e.toString().contains('cancel') || e.toString().contains('Cancel')) {
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('dashboard.report_error'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppSettingsBloc, AppSettingsState>(
      builder: (context, settingsState) {
        final settings = settingsState.settings;
        
        // Check if daily sales summary is enabled
        if (!settings.dailySalesSummary) {
          return const SizedBox.shrink();
        }

        if (!_loaded || _isDismissed || _summary == null) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final profitCents = _summary!.revenueCents - _summary!.costCents;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Dismissible(
              key: const Key('daily_sales_summary'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) => _dismiss(),
              background: _buildDismissBackground(context, Alignment.centerLeft),
              secondaryBackground: _buildDismissBackground(context, Alignment.centerRight),
              child: Card(
                elevation: 0,
                color: isDark
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.green.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.green.withValues(alpha: 0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          const Icon(LucideIcons.trendingUp, size: 20, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'dashboard.daily_sales_summary'.tr(),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _generateReport(context),
                            icon: const Icon(LucideIcons.fileText, size: 16),
                            label: Text('dashboard.report'.tr()),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(LucideIcons.x, size: 18),
                            onPressed: _dismiss,
                            visualDensity: VisualDensity.compact,
                            tooltip: 'common.dismiss'.tr(),
                            color: Colors.green,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Summary stats
                      Row(
                        children: [
                          Expanded(
                            child: _StatItem(
                              icon: LucideIcons.shoppingCart,
                              label: 'dashboard.sales_count'.tr(),
                              value: '${_summary!.saleCount}',
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatItem(
                              icon: LucideIcons.dollarSign,
                              label: 'dashboard.total_sales'.tr(),
                              value: _cs.format(_summary!.totalSalesCents),
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatItem(
                              icon: LucideIcons.trendingUp,
                              label: 'dashboard.profit'.tr(),
                              value: _cs.format(profitCents),
                              color: profitCents >= 0 ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
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

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
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
        const SizedBox(height: 2),
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
    );
  }
}

class DailySalesSummary {
  final int saleCount;
  final int totalSalesCents;
  final int revenueCents;
  final int costCents;

  DailySalesSummary({
    required this.saleCount,
    required this.totalSalesCents,
    required this.revenueCents,
    required this.costCents,
  });
}
