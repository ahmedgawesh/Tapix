import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Result returned from [showDateRangeFilterSheet].
///
/// - `null` (as a function result) means the user dismissed the sheet without
///   making a change.
/// - A result with `range == null` means the user explicitly cleared the
///   filter.
/// - A result with a non-null `range` means the user picked a new range. If it
///   came from a preset, `label` carries the localized preset label; for the
///   custom calendar picker, `label` is `null` (callers should render the
///   range dates instead).
class DateRangeFilterResult {
  final DateTimeRange? range;
  final String? label;
  const DateRangeFilterResult({this.range, this.label});
}

/// Reusable date-range filter bottom sheet with presets (today, yesterday,
/// this week, this month, last month) plus a "custom" entry that opens the
/// platform date-range picker forced into calendar-only mode — this sidesteps
/// the "invalid format" validation error shown by the text-entry mode in
/// right-to-left locales.
Future<DateRangeFilterResult?> showDateRangeFilterSheet(
  BuildContext context, {
  DateTimeRange? currentRange,
  String? currentLabel,
}) async {
  final theme = Theme.of(context);
  final cs = theme.colorScheme;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final presets = <_DatePreset>[
    _DatePreset(
      label: 'sales.date_today'.tr(),
      icon: LucideIcons.calendarCheck,
      range: DateTimeRange(start: today, end: today),
    ),
    _DatePreset(
      label: 'sales.date_yesterday'.tr(),
      icon: LucideIcons.calendarMinus,
      range: DateTimeRange(
        start: today.subtract(const Duration(days: 1)),
        end: today.subtract(const Duration(days: 1)),
      ),
    ),
    _DatePreset(
      label: 'sales.date_this_week'.tr(),
      icon: LucideIcons.calendar,
      range: DateTimeRange(
        start: today.subtract(Duration(days: today.weekday - 1)),
        end: today,
      ),
    ),
    _DatePreset(
      label: 'sales.date_this_month'.tr(),
      icon: LucideIcons.calendarDays,
      range: DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: today,
      ),
    ),
    _DatePreset(
      label: 'sales.date_last_month'.tr(),
      icon: LucideIcons.calendarClock,
      range: DateTimeRange(
        start: DateTime(now.year, now.month - 1, 1),
        end: DateTime(now.year, now.month, 0),
      ),
    ),
    _DatePreset(
      label: 'sales.date_last_3_months'.tr(),
      icon: LucideIcons.calendarClock,
      range: DateTimeRange(
        start: DateTime(now.year, now.month - 3, now.day),
        end: today,
      ),
    ),
    _DatePreset(
      label: 'sales.date_last_6_months'.tr(),
      icon: LucideIcons.calendarClock,
      range: DateTimeRange(
        start: DateTime(now.year, now.month - 6, now.day),
        end: today,
      ),
    ),
    _DatePreset(
      label: 'sales.date_this_year'.tr(),
      icon: LucideIcons.calendarDays,
      range: DateTimeRange(
        start: DateTime(now.year, 1, 1),
        end: today,
      ),
    ),
    _DatePreset(
      label: 'sales.date_last_year'.tr(),
      icon: LucideIcons.calendarClock,
      range: DateTimeRange(
        start: DateTime(now.year - 1, 1, 1),
        end: DateTime(now.year - 1, 12, 31),
      ),
    ),
  ];

  return showModalBottomSheet<DateRangeFilterResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  Icon(LucideIcons.calendarRange, size: 20, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('sales.date_range'.tr(),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (currentRange != null)
                    TextButton.icon(
                      onPressed: () => Navigator.pop(
                          ctx, const DateRangeFilterResult()),
                      icon: const Icon(LucideIcons.x, size: 16),
                      label: Text('sales.date_clear'.tr()),
                      style: TextButton.styleFrom(
                        foregroundColor: cs.error,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ...presets.map((preset) {
                final isActive = currentRange != null &&
                    currentRange.start == preset.range.start &&
                    currentRange.end == preset.range.end;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: isActive
                        ? cs.primaryContainer.withValues(alpha: 0.5)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isActive
                              ? cs.primary.withValues(alpha: 0.15)
                              : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(preset.icon,
                            size: 18,
                            color: isActive
                                ? cs.primary
                                : cs.onSurfaceVariant),
                      ),
                      title: Text(preset.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                      trailing: isActive
                          ? Icon(LucideIcons.check,
                              size: 18, color: cs.primary)
                          : null,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      dense: true,
                      onTap: () => Navigator.pop(
                          ctx,
                          DateRangeFilterResult(
                              range: preset.range, label: preset.label)),
                    ),
                  ),
                );
              }),
              const Divider(height: 16),
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(LucideIcons.calendarSearch,
                        size: 18, color: cs.onSurfaceVariant),
                  ),
                  title: Text('sales.date_custom'.tr(),
                      style: theme.textTheme.bodyMedium),
                  trailing: const Icon(LucideIcons.chevronRight, size: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  dense: true,
                  onTap: () async {
                    // Use two sequential single-date pickers. Unlike
                    // `showDateRangePicker`, `showDatePicker` exposes a
                    // year-selection header the user can tap to jump
                    // straight to any year — dramatically faster for
                    // picking dates that are years in the past.
                    final firstDate = DateTime(2000);
                    final lastDate =
                        DateTime.now().add(const Duration(days: 30));
                    final start = await showDatePicker(
                      context: context,
                      firstDate: firstDate,
                      lastDate: lastDate,
                      initialDate: currentRange?.start ?? DateTime.now(),
                      helpText: 'sales.date_pick_start'.tr(),
                      initialEntryMode: DatePickerEntryMode.calendarOnly,
                    );
                    if (!ctx.mounted) return;
                    if (start == null) {
                      Navigator.pop(ctx);
                      return;
                    }
                    final end = await showDatePicker(
                      context: context,
                      firstDate: start,
                      lastDate: lastDate,
                      initialDate: currentRange?.end != null &&
                              !currentRange!.end.isBefore(start)
                          ? currentRange.end
                          : start,
                      helpText: 'sales.date_pick_end'.tr(),
                      initialEntryMode: DatePickerEntryMode.calendarOnly,
                    );
                    if (!ctx.mounted) return;
                    if (end == null) {
                      Navigator.pop(ctx);
                      return;
                    }
                    Navigator.pop(
                      ctx,
                      DateRangeFilterResult(
                        range: DateTimeRange(start: start, end: end),
                      ),
                    );
                  },
                ),
              ),
            ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _DatePreset {
  final String label;
  final IconData icon;
  final DateTimeRange range;
  const _DatePreset({
    required this.label,
    required this.icon,
    required this.range,
  });
}
