import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/cheque_confirmation_dao.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/cheque_lifecycle_service.dart';
import '../../../../core/services/currency_service.dart';

/// Phase 14.0 — DB-backed cheque reminders.
///
/// Replaces the previous `SharedPreferences`-only dismissal that did not
/// survive device migration nor produce an audit trail. Reads pending
/// cheques from all six source tables and offers three actions:
///   • **Confirm cleared** — cheque cleared (money hit/left the bank).
///   • **Mark bounced** — cheque was returned. Captures a reason.
///   • **Cancel** — cheque was stopped/voided before clearance.
///
/// All actions persist to `cheque_confirmations` so a future
/// `LedgerRebuildService` pass or audit query can reproduce the lifecycle.
///
/// **Direction semantics** (matched in the UI badges):
/// - `incoming` — cheque is *receivable*, money flowing TO the user.
///   Source: `sale`, `purchase_return`, `purchase_return_adjustment`.
/// - `outgoing` — cheque is *payable*, money flowing FROM the user.
///   Source: `purchase`, `sale_return`, `sale_return_adjustment`.
class ChequeRemindersSection extends StatefulWidget {
  const ChequeRemindersSection({super.key});

  @override
  State<ChequeRemindersSection> createState() => _ChequeRemindersSectionState();
}

/// Direction of cash flow. Drives icon, colour, and action labels.
enum ChequeDirection { incoming, outgoing }

/// Phase 15.0 — distinguishes the three lifecycle outcomes for the
/// snackbar copy. Internal to the dashboard widget.
enum _ChequeIntent { cleared, bounced, cancelled }

class ChequeReminderItem {
  /// `sale` | `purchase` | `sale_return` | `purchase_return`
  /// | `sale_return_adjustment` | `purchase_return_adjustment`
  final String sourceTable;
  final int sourceId;
  final String referenceNumber;
  final DateTime dueDate;
  final int amountCents;
  final ChequeDirection direction;

  ChequeReminderItem({
    required this.sourceTable,
    required this.sourceId,
    required this.referenceNumber,
    required this.dueDate,
    required this.amountCents,
    required this.direction,
  });

  String get uniqueId => '$sourceTable|$sourceId';
}

class _ChequeRemindersSectionState extends State<ChequeRemindersSection> {
  late final AppDatabase _db;
  late final CurrencyService _currency;
  late final ChequeConfirmationDao _confirmDao;
  late final ChequeLifecycleService _lifecycle;
  StreamSubscription<List<ChequeReminderItem>>? _chequeSub;
  StreamSubscription<Map<String, ChequeConfirmation>>? _confirmSub;
  List<ChequeReminderItem> _allCheques = [];
  Map<String, ChequeConfirmation> _confirmations = {};
  bool _chequesLoaded = false;
  bool _confirmationsLoaded = false;

  @override
  void initState() {
    super.initState();
    _db = sl<AppDatabase>();
    _currency = sl<CurrencyService>();
    _confirmDao = sl<ChequeConfirmationDao>();
    _lifecycle = sl<ChequeLifecycleService>();
    _subscribeReminders();
  }

  @override
  void dispose() {
    _chequeSub?.cancel();
    _confirmSub?.cancel();
    super.dispose();
  }

  bool get _loaded => _chequesLoaded && _confirmationsLoaded;

  // ── data stream ───────────────────────────────────────────────────────

  /// UNION across all six cheque-bearing source tables. The aliases
  /// `source_table` here match the values in `ChequeSourceTables`, NOT
  /// the underlying physical table names (e.g. `sale_return_adjustment`
  /// not `sale_return_adjustments`). The DAO's natural-key column
  /// `cheque_confirmations.source_table` uses these aliases.
  void _subscribeReminders() {
    final reminderStream = _db.customSelect(
      '''
      SELECT 'sale' AS source_table, id AS source_id,
             invoice_number AS reference_number,
             due_date, total_cents AS amount_cents, 'incoming' AS direction
      FROM sales
      WHERE payment_method IN ('cheque', 'check')
        AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')

      UNION ALL

      SELECT 'purchase' AS source_table, id AS source_id,
             purchase_number AS reference_number,
             due_date, total_cents AS amount_cents, 'outgoing' AS direction
      FROM purchases
      WHERE payment_method IN ('cheque', 'check')
        AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')

      UNION ALL

      SELECT 'sale_return' AS source_table, id AS source_id,
             return_number AS reference_number,
             due_date, total_cents AS amount_cents, 'outgoing' AS direction
      FROM sale_returns
      WHERE refund_method IN ('cheque', 'check')
        AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')

      UNION ALL

      SELECT 'purchase_return' AS source_table, id AS source_id,
             return_number AS reference_number,
             due_date, total_cents AS amount_cents, 'incoming' AS direction
      FROM purchase_returns
      WHERE refund_method IN ('cheque', 'check')
        AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')

      UNION ALL

      SELECT 'sale_return_adjustment' AS source_table, id AS source_id,
             return_number AS reference_number,
             due_date, total_cents AS amount_cents, 'outgoing' AS direction
      FROM sale_return_adjustments
      WHERE refund_method IN ('cheque', 'check')
        AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')

      UNION ALL

      SELECT 'purchase_return_adjustment' AS source_table, id AS source_id,
             return_number AS reference_number,
             due_date, total_cents AS amount_cents, 'incoming' AS direction
      FROM purchase_return_adjustments
      WHERE refund_method IN ('cheque', 'check')
        AND due_date IS NOT NULL
        AND status NOT IN ('voided', 'draft')
      ''',
      readsFrom: {
        _db.sales,
        _db.purchases,
        _db.saleReturns,
        _db.purchaseReturns,
        _db.saleReturnAdjustments,
        _db.purchaseReturnAdjustments,
      },
    ).watch().map((rows) {
      final items = <ChequeReminderItem>[];
      for (final row in rows) {
        final rawDate = row.read<String?>('due_date');
        if (rawDate == null) continue;
        DateTime date;
        try {
          date = DateTime.parse(rawDate);
        } catch (_) {
          continue;
        }
        final directionStr = row.read<String>('direction');
        items.add(ChequeReminderItem(
          sourceTable: row.read<String>('source_table'),
          sourceId: row.read<int>('source_id'),
          referenceNumber: row.read<String>('reference_number'),
          dueDate: date,
          amountCents: row.read<int>('amount_cents'),
          direction: directionStr == 'incoming'
              ? ChequeDirection.incoming
              : ChequeDirection.outgoing,
        ));
      }
      return items;
    });

    _chequeSub = reminderStream.listen((cheques) {
      if (!mounted) return;
      setState(() {
        _allCheques = cheques;
        _chequesLoaded = true;
      });
    });
    _confirmSub = _confirmDao.watchAllAsMap().listen((map) {
      if (!mounted) return;
      setState(() {
        _confirmations = map;
        _confirmationsLoaded = true;
      });
    });
  }

  // ── lifecycle actions ─────────────────────────────────────────────────
  //
  // Phase 15.0 — these handlers delegate to `ChequeLifecycleService`,
  // which (a) runs each transition inside a single DB transaction and
  // (b) for `sale`/`purchase` sources also calls
  // `SaleRepository.recordPayment` / `PurchaseRepository.recordPayment`
  // (cleared) or `deletePayment` (bounce/cancel after cleared) so the
  // AP/AR balance, supplier/customer transaction ledger, and Dr/Cr Bank
  // journal entry all settle alongside the lifecycle row. Returns
  // surface a snackbar via `_showOutcomeSnackbar`.

  Future<void> _markCleared(ChequeReminderItem item) async {
    try {
      final result = await _lifecycle.markCleared(
        sourceTable: item.sourceTable,
        sourceId: item.sourceId,
      );
      _showOutcomeSnackbar(
        item: item,
        settled: result.settledAmountCents,
        reversed: null,
        isIncoming: item.direction == ChequeDirection.incoming,
        intent: _ChequeIntent.cleared,
      );
    } catch (e) {
      _showErrorSnackbar(e);
    }
  }

  Future<void> _markBounced(ChequeReminderItem item) async {
    final reason = await _promptBounceReason(context);
    if (reason == null || reason.trim().isEmpty) return;
    try {
      final result = await _lifecycle.markBounced(
        sourceTable: item.sourceTable,
        sourceId: item.sourceId,
        bounceReason: reason,
      );
      _showOutcomeSnackbar(
        item: item,
        settled: null,
        reversed: result.reversedAmountCents,
        isIncoming: item.direction == ChequeDirection.incoming,
        intent: _ChequeIntent.bounced,
      );
    } catch (e) {
      _showErrorSnackbar(e);
    }
  }

  Future<void> _cancelCheque(ChequeReminderItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('dashboard.cheque_cancel_title'.tr()),
        content: Text('dashboard.cheque_cancel_confirm'.tr(
          args: [item.referenceNumber],
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('common.confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await _lifecycle.markCancelled(
        sourceTable: item.sourceTable,
        sourceId: item.sourceId,
      );
      _showOutcomeSnackbar(
        item: item,
        settled: null,
        reversed: result.reversedAmountCents,
        isIncoming: item.direction == ChequeDirection.incoming,
        intent: _ChequeIntent.cancelled,
      );
    } catch (e) {
      _showErrorSnackbar(e);
    }
  }

  void _showOutcomeSnackbar({
    required ChequeReminderItem item,
    required int? settled,
    required int? reversed,
    required bool isIncoming,
    required _ChequeIntent intent,
  }) {
    if (!mounted) return;
    String message;
    switch (intent) {
      case _ChequeIntent.cleared:
        if (settled != null && settled > 0) {
          message = isIncoming
              ? 'dashboard.cheque_settled_in'.tr(
                  args: [_currency.format(settled)])
              : 'dashboard.cheque_settled_out'.tr(
                  args: [_currency.format(settled)]);
        } else {
          message = 'dashboard.cheque_marked_cleared'.tr();
        }
        break;
      case _ChequeIntent.bounced:
        message = (reversed != null && reversed > 0)
            ? 'dashboard.cheque_bounced_reversed'.tr(
                args: [_currency.format(reversed)])
            : 'dashboard.cheque_marked_bounced'.tr();
        break;
      case _ChequeIntent.cancelled:
        message = (reversed != null && reversed > 0)
            ? 'dashboard.cheque_cancelled_reversed'.tr(
                args: [_currency.format(reversed)])
            : 'dashboard.cheque_marked_cancelled'.tr();
        break;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showErrorSnackbar(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('dashboard.cheque_action_failed'
            .tr(args: [error.toString()])),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<String?> _promptBounceReason(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('dashboard.cheque_bounce_title'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'dashboard.cheque_bounce_reason_label'.tr(),
            hintText: 'dashboard.cheque_bounce_reason_hint'.tr(),
            border: const OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text('common.confirm'.tr()),
          ),
        ],
      ),
    );
  }

  // ── navigation ────────────────────────────────────────────────────────

  void _navigateToSource(BuildContext context, ChequeReminderItem item) {
    switch (item.sourceTable) {
      case 'sale':
        context.push('/sales/${item.sourceId}');
        break;
      case 'purchase':
        context.push('/purchases/${item.sourceId}');
        break;
      case 'sale_return':
        // The dedicated linked-return detail route is under /sales.
        context.push('/sales/returns/${item.sourceId}');
        break;
      case 'purchase_return':
        context.push('/purchases/returns/${item.sourceId}');
        break;
      case 'sale_return_adjustment':
        context.push('/sales/returns/adj/${item.sourceId}');
        break;
      case 'purchase_return_adjustment':
        context.push('/purchases/returns/adj/${item.sourceId}');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    // Surface only un-resolved cheques that are due within the next 2 days
    // or already overdue. A resolved cheque (cleared/bounced/cancelled)
    // is hidden from the reminder but its history remains in DB.
    final today = DateTime(DateTime.now().year, DateTime.now().month,
        DateTime.now().day);

    final visible = _allCheques.where((c) {
      final cf = _confirmations[c.uniqueId];
      if (cf != null &&
          ChequeConfirmationStatus.resolved.contains(cf.status)) {
        return false;
      }
      final d = DateTime(c.dueDate.year, c.dueDate.month, c.dueDate.day);
      final diff = d.difference(today).inDays;
      return diff <= 2;
    }).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

    if (visible.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: visible.map((item) {
        return _ChequeReminderCard(
          item: item,
          today: today,
          isDark: isDark,
          theme: theme,
          currency: _currency,
          onTap: () => _navigateToSource(context, item),
          onMarkCleared: () => _markCleared(item),
          onMarkBounced: () => _markBounced(item),
          onCancel: () => _cancelCheque(item),
        );
      }).toList(),
    );
  }
}

class _ChequeReminderCard extends StatelessWidget {
  final ChequeReminderItem item;
  final DateTime today;
  final bool isDark;
  final ThemeData theme;
  final CurrencyService currency;
  final VoidCallback onTap;
  final VoidCallback onMarkCleared;
  final VoidCallback onMarkBounced;
  final VoidCallback onCancel;

  const _ChequeReminderCard({
    required this.item,
    required this.today,
    required this.isDark,
    required this.theme,
    required this.currency,
    required this.onTap,
    required this.onMarkCleared,
    required this.onMarkBounced,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final rDate = DateTime(item.dueDate.year, item.dueDate.month, item.dueDate.day);
    final diff = rDate.difference(today).inDays;

    String statusLabel;
    Color statusColor;
    bool isOverdue = false;
    if (diff == 0) {
      statusLabel = 'dashboard.cheque_due_today'.tr();
      statusColor = Colors.orange;
    } else if (diff == 1) {
      statusLabel = 'dashboard.cheque_due_tomorrow'.tr();
      statusColor = Colors.amber.shade800;
    } else if (diff > 1) {
      statusLabel = 'dashboard.cheque_due_in_days'.tr(args: [diff.toString()]);
      statusColor = Colors.amber.shade800;
    } else {
      statusLabel = 'dashboard.cheque_overdue'.tr();
      statusColor = Colors.red;
      isOverdue = true;
    }

    final isIncoming = item.direction == ChequeDirection.incoming;
    final directionLabel = isIncoming
        ? 'dashboard.cheque_direction_incoming'.tr()
        : 'dashboard.cheque_direction_outgoing'.tr();
    final directionIcon =
        isIncoming ? LucideIcons.arrowDownToLine : LucideIcons.arrowUpFromLine;

    final titlePrefix = _titlePrefixFor(item.sourceTable);
    final sourceIcon = _sourceIconFor(item.sourceTable);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: isDark
          ? statusColor.withValues(alpha: 0.12)
          : statusColor.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(sourceIcon, size: 20, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$titlePrefix #${item.referenceNumber}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(directionIcon, size: 14,
                      color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    directionLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'dashboard.cheque_for'.tr(
                      args: [currency.format(item.amountCents)],
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Action row — always render but emphasis depends on overdue.
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: onMarkCleared,
                    icon: const Icon(LucideIcons.checkCircle, size: 14),
                    label: Text(isIncoming
                        ? 'dashboard.cheque_confirm_collected'.tr()
                        : 'dashboard.cheque_confirm_paid'.tr()),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      backgroundColor: isOverdue
                          ? Colors.green.withValues(alpha: 0.15)
                          : null,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onMarkBounced,
                    icon: const Icon(LucideIcons.xCircle, size: 14),
                    label: Text('dashboard.cheque_mark_bounced'.tr()),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      foregroundColor: cs.error,
                      side: BorderSide(color: cs.error.withValues(alpha: 0.4)),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: onCancel,
                    icon: const Icon(LucideIcons.ban, size: 14),
                    label: Text('dashboard.cheque_cancel'.tr()),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      foregroundColor: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _titlePrefixFor(String src) {
    switch (src) {
      case 'sale':
        return 'dashboard.cheque_sale'.tr();
      case 'purchase':
        return 'dashboard.cheque_purchase'.tr();
      case 'sale_return':
        return 'dashboard.cheque_sale_return_linked'.tr();
      case 'purchase_return':
        return 'dashboard.cheque_purchase_return_linked'.tr();
      case 'sale_return_adjustment':
        return 'dashboard.cheque_sale_return'.tr();
      case 'purchase_return_adjustment':
        return 'dashboard.cheque_purchase_return'.tr();
    }
    return src;
  }

  IconData _sourceIconFor(String src) {
    switch (src) {
      case 'sale':
        return LucideIcons.trendingUp;
      case 'purchase':
        return LucideIcons.trendingDown;
      case 'sale_return':
      case 'sale_return_adjustment':
        return LucideIcons.refreshCcw;
      case 'purchase_return':
      case 'purchase_return_adjustment':
        return LucideIcons.refreshCw;
    }
    return LucideIcons.banknote;
  }
}
