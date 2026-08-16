import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../bloc/accounting_periods_bloc.dart';

class AccountingPeriodsScreen extends StatelessWidget {
  const AccountingPeriodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AccountingPeriodsBloc>(),
      child: const _PeriodsView(),
    );
  }
}

class _PeriodsView extends StatelessWidget {
  const _PeriodsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('financial_management.accounting_periods'.tr()),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'financial_management.create_period'.tr(),
            onPressed: () => _showCreatePeriodDialog(context),
          ),
        ],
      ),
      body: BlocConsumer<AccountingPeriodsBloc, RealtimeState<AccountingPeriodsData>>(
        listener: (context, state) {
          if (state is RealtimeError<AccountingPeriodsData>) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  state.error
                      .toString()
                      .replaceFirst('Bad state: ', '')
                      .tr(),
                ),
                backgroundColor: colorScheme.error,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is RealtimeLoading<AccountingPeriodsData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeSuccess<AccountingPeriodsData>) {
            final periods = state.data.periods;
            if (periods.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.calendarX, size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                    const SizedBox(height: 16),
                    Text(
                      'financial_management.no_periods'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'financial_management.no_periods_hint'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => _showCreatePeriodDialog(context),
                      icon: const Icon(LucideIcons.plus),
                      label: Text('financial_management.create_period'.tr()),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: periods.length,
              itemBuilder: (context, index) {
                final period = periods[index];
                return _PeriodCard(period: period);
              },
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  void _showCreatePeriodDialog(BuildContext context) {
    final nameController = TextEditingController();
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 365));

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text('financial_management.create_period'.tr()),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'financial_management.period_name'.tr(),
                        hintText: 'financial_management.period_name_hint'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(LucideIcons.calendarRange),
                      title: Text('financial_management.start_date'.tr()),
                      subtitle: Text(DateFormat.yMMMd().format(startDate)),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setState(() {
                            startDate = picked;
                            if (endDate.isBefore(startDate)) {
                              endDate = startDate;
                            }
                          });
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(LucideIcons.calendarCheck),
                      title: Text('financial_management.end_date'.tr()),
                      subtitle: Text(DateFormat.yMMMd().format(endDate)),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: endDate,
                          firstDate: startDate,
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) setState(() => endDate = picked);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('common.cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    context.read<AccountingPeriodsBloc>().add(
                      PeriodCreateRequested(
                        name: name,
                        startDate: startDate,
                        endDate: endDate,
                      ),
                    );
                    Navigator.pop(dialogContext);
                  },
                  child: Text('common.create'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PeriodCard extends StatelessWidget {
  final AccountingPeriod period;
  const _PeriodCard({required this.period});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isClosed = period.isClosed;

    final statusColor = isClosed ? Colors.green : colorScheme.tertiary;
    final statusIcon = isClosed ? LucideIcons.lock : LucideIcons.unlock;
    final statusLabel = isClosed
        ? 'financial_management.period_closed'.tr()
        : 'financial_management.period_open'.tr();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(LucideIcons.calendar, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    period.periodName,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Date range
            Row(
              children: [
                Icon(LucideIcons.calendarRange, size: 14, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '${DateFormat.yMMMd().format(period.startDate)} — ${DateFormat.yMMMd().format(period.endDate)}',
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),

            if (isClosed && period.closedAt != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(LucideIcons.checkCircle, size: 14, color: Colors.green),
                  const SizedBox(width: 6),
                  Text(
                    'financial_management.closed_on'.tr(
                      args: [DateFormat.yMMMd().add_jm().format(period.closedAt!)],
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.green),
                  ),
                ],
              ),
            ],

            // Actions
            if (!isClosed) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _showCloseConfirmation(context, period),
                    icon: Icon(LucideIcons.lock, size: 16, color: colorScheme.error),
                    label: Text(
                      'financial_management.close_period'.tr(),
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCloseConfirmation(BuildContext context, AccountingPeriod period) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(LucideIcons.alertTriangle, color: colorScheme.error, size: 32),
          title: Text('financial_management.close_period_confirm_title'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'financial_management.close_period_confirm_body'.tr(
                  args: [period.periodName],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'financial_management.close_period_warning'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'financial_management.close_period_effects'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
              onPressed: () {
                context.read<AccountingPeriodsBloc>().add(
                  PeriodCloseRequested(periodId: period.id),
                );
                Navigator.pop(dialogContext);
              },
              child: Text('financial_management.close_period'.tr()),
            ),
          ],
        );
      },
    );
  }
}
