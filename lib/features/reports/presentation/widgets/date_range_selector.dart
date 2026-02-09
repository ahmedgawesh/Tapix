import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'report_date_range.dart';

/// A reusable date range selector widget for financial reports.
/// Shows preset period chips and a custom date range picker.
class DateRangeSelector extends StatelessWidget {
  final ReportDateRange dateRange;
  final ValueChanged<ReportDateRange> onChanged;

  const DateRangeSelector({
    super.key,
    required this.dateRange,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Current range display + custom picker button
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showCustomDatePicker(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.calendar, size: 16, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '${DateFormat.yMMMd().format(dateRange.startDate)} — ${DateFormat.yMMMd().format(dateRange.endDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(LucideIcons.chevronDown, size: 14, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Preset chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _PresetChip(
                label: 'reports.date_range.today'.tr(),
                selected: dateRange.preset == ReportPeriodPreset.today,
                onTap: () => onChanged(ReportDateRange.today()),
              ),
              _PresetChip(
                label: 'reports.date_range.this_week'.tr(),
                selected: dateRange.preset == ReportPeriodPreset.thisWeek,
                onTap: () => onChanged(ReportDateRange.thisWeek()),
              ),
              _PresetChip(
                label: 'reports.date_range.this_month'.tr(),
                selected: dateRange.preset == ReportPeriodPreset.thisMonth,
                onTap: () => onChanged(ReportDateRange.thisMonth()),
              ),
              _PresetChip(
                label: 'reports.date_range.last_month'.tr(),
                selected: dateRange.preset == ReportPeriodPreset.lastMonth,
                onTap: () => onChanged(ReportDateRange.lastMonth()),
              ),
              _PresetChip(
                label: 'reports.date_range.this_quarter'.tr(),
                selected: dateRange.preset == ReportPeriodPreset.thisQuarter,
                onTap: () => onChanged(ReportDateRange.thisQuarter()),
              ),
              _PresetChip(
                label: 'reports.date_range.this_year'.tr(),
                selected: dateRange.preset == ReportPeriodPreset.thisYear,
                onTap: () => onChanged(ReportDateRange.thisYear()),
              ),
              _PresetChip(
                label: 'reports.date_range.last_year'.tr(),
                selected: dateRange.preset == ReportPeriodPreset.lastYear,
                onTap: () => onChanged(ReportDateRange.lastYear()),
              ),
              _PresetChip(
                label: 'reports.date_range.all_time'.tr(),
                selected: dateRange.preset == ReportPeriodPreset.allTime,
                onTap: () => onChanged(ReportDateRange.allTime()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showCustomDatePicker(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: dateRange.startDate,
        end: dateRange.endDate,
      ),
      helpText: 'reports.date_range.select_period'.tr(),
      saveText: 'common.save'.tr(),
      cancelText: 'common.cancel'.tr(),
    );

    if (picked != null) {
      onChanged(ReportDateRange(
        startDate: picked.start,
        endDate: DateTime(
          picked.end.year, picked.end.month, picked.end.day, 23, 59, 59,
        ),
        preset: ReportPeriodPreset.custom,
      ));
    }
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
