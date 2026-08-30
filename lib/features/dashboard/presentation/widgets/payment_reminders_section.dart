import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../services/payment_reminders_pdf_service.dart';

/// Key used to store dismissed payment reminders date in SharedPreferences.
const _kDismissedPaymentRemindersKey = 'dismissed_payment_reminders_date';

/// Dashboard section that shows payment reminders notification.
class PaymentRemindersSection extends StatefulWidget {
  const PaymentRemindersSection({super.key});

  @override
  State<PaymentRemindersSection> createState() => _PaymentRemindersSectionState();
}

class _PaymentRemindersSectionState extends State<PaymentRemindersSection> {
  late final AppDatabase _db;
  late final CurrencyService _cs;
  StreamSubscription<PaymentReminders?>? _remindersSub;
  PaymentReminders? _reminders;
  bool _isDismissed = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _db = sl<AppDatabase>();
    _cs = sl<CurrencyService>();
    _checkDismissed();
    _subscribeReminders();
  }

  @override
  void dispose() {
    _remindersSub?.cancel();
    super.dispose();
  }

  Future<void> _checkDismissed() async {
    final prefs = sl<SharedPreferences>();
    final dismissedDate = prefs.getString(_kDismissedPaymentRemindersKey);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    if (dismissedDate == today) {
      if (mounted) setState(() => _isDismissed = true);
    }
  }

  void _subscribeReminders() {
    _remindersSub = _db.customSelect(
      '''
      SELECT 
        'customer' AS type,
        COUNT(*) AS count,
        COALESCE(SUM(balance_cents), 0) AS total_cents
      FROM customers
      WHERE balance_cents > 0
      
      UNION ALL
      
      SELECT 
        'supplier' AS type,
        COUNT(*) AS count,
        COALESCE(SUM(ABS(balance_cents)), 0) AS total_cents
      FROM suppliers
      WHERE balance_cents < 0
      ''',
      readsFrom: {_db.customers, _db.suppliers},
    ).watch().map((rows) {
      int customerCount = 0;
      int customerBalanceCents = 0;
      int supplierCount = 0;
      int supplierBalanceCents = 0;

      for (final row in rows) {
        final type = row.read<String>('type');
        final count = row.read<int>('count');
        final totalCents = row.read<int>('total_cents');

        if (type == 'customer') {
          customerCount = count;
          customerBalanceCents = totalCents;
        } else if (type == 'supplier') {
          supplierCount = count;
          supplierBalanceCents = totalCents;
        }
      }

      final totalCount = customerCount + supplierCount;
      if (totalCount == 0) {
        return null;
      }

      return PaymentReminders(
        customerCount: customerCount,
        customerBalanceCents: customerBalanceCents,
        supplierCount: supplierCount,
        supplierBalanceCents: supplierBalanceCents,
      );
    }).listen((reminders) {
      if (mounted) {
        setState(() {
          _reminders = reminders;
          _loaded = true;
        });
      }
    });
  }

  Future<void> _dismiss() async {
    final prefs = sl<SharedPreferences>();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await prefs.setString(_kDismissedPaymentRemindersKey, today);
    if (mounted) setState(() => _isDismissed = true);
  }

  Future<void> _generateReport(BuildContext context) async {
    try {
      await PaymentRemindersPdfService.printPaymentReminders(context: context);
    } catch (e) {
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
        
        // Check if payment reminders are enabled
        if (!settings.paymentReminders) {
          return const SizedBox.shrink();
        }

        if (!_loaded || _isDismissed || _reminders == null) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final totalCount = _reminders!.customerCount + _reminders!.supplierCount;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Dismissible(
              key: const Key('payment_reminders'),
              direction: DismissDirection.horizontal,
              onDismissed: (_) => _dismiss(),
              background: _buildDismissBackground(context, Alignment.centerLeft),
              secondaryBackground: _buildDismissBackground(context, Alignment.centerRight),
              child: Card(
                elevation: 0,
                color: isDark
                    ? Colors.amber.withValues(alpha: 0.12)
                    : Colors.amber.withValues(alpha: 0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          const Icon(LucideIcons.bellRing, size: 20, color: Colors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'dashboard.payment_reminders'.tr(),
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade800,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$totalCount',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.amber.shade900,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
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
                            color: Colors.amber.shade800,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Reminders details
                      if (_reminders!.customerCount > 0)
                        _ReminderItem(
                          icon: LucideIcons.userCheck,
                          label: 'dashboard.customers_owe'.tr(),
                          count: _reminders!.customerCount,
                          amount: _cs.format(_reminders!.customerBalanceCents),
                          color: Colors.green,
                        ),
                      if (_reminders!.customerCount > 0 && _reminders!.supplierCount > 0)
                        const SizedBox(height: 8),
                      if (_reminders!.supplierCount > 0)
                        _ReminderItem(
                          icon: LucideIcons.userMinus,
                          label: 'dashboard.suppliers_owed'.tr(),
                          count: _reminders!.supplierCount,
                          amount: _cs.format(_reminders!.supplierBalanceCents),
                          color: Colors.red,
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

class _ReminderItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final String amount;
  final Color color;

  const _ReminderItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$count ${'dashboard.accounts'.tr()}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            amount,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class PaymentReminders {
  final int customerCount;
  final int customerBalanceCents;
  final int supplierCount;
  final int supplierBalanceCents;

  PaymentReminders({
    required this.customerCount,
    required this.customerBalanceCents,
    required this.supplierCount,
    required this.supplierBalanceCents,
  });
}
