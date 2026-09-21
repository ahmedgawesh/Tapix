import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
                Icon(
                  LucideIcons.calendar,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${DateFormat('dd/MM/yyyy').format(dateRange.startDate)} — ${DateFormat('dd/MM/yyyy').format(dateRange.endDate)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  LucideIcons.chevronDown,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
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
    // Two sequential single-date pickers in calendar-only mode.
    // `showDatePicker` exposes a tap-to-select year header, making it far
    // faster to jump years back than `showDateRangePicker` (which only scrolls
    // month-by-month) — and it also avoids the "invalid format" text-entry
    // validation bug present in RTL locales.
    final firstDate = DateTime(2000);
    final lastDate = DateTime.now();

    final start = await showDatePicker(
      context: context,
      firstDate: firstDate,
      lastDate: lastDate,
      initialDate: dateRange.startDate.isAfter(lastDate)
          ? lastDate
          : dateRange.startDate,
      helpText: 'sales.date_pick_start'.tr(),
      cancelText: 'common.cancel'.tr(),
      confirmText: 'common.save'.tr(),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (start == null || !context.mounted) return;

    final end = await showDatePicker(
      context: context,
      firstDate: start,
      lastDate: lastDate,
      initialDate: dateRange.endDate.isBefore(start)
          ? start
          : dateRange.endDate.isAfter(lastDate)
          ? lastDate
          : dateRange.endDate,
      helpText: 'sales.date_pick_end'.tr(),
      cancelText: 'common.cancel'.tr(),
      confirmText: 'common.save'.tr(),
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );
    if (end == null) return;

    onChanged(
      ReportDateRange(
        startDate: start,
        endDate: ReportDateRange.endOfDay(end),
        preset: ReportPeriodPreset.custom,
      ),
    );
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
