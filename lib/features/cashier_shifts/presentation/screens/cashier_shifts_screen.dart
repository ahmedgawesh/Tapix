import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/money/money_input_parser.dart';
import '../../../../core/services/cashier_shift_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../../auth/auth.dart';

class CashierShiftsScreen extends StatefulWidget {
  const CashierShiftsScreen({super.key});

  @override
  State<CashierShiftsScreen> createState() => _CashierShiftsScreenState();
}

class _CashierShiftsScreenState extends State<CashierShiftsScreen> {
  final _service = sl<CashierShiftService>();
  bool _loading = true;
  Object? _error;
  CashierShiftView? _current;
  CashierShiftSummary? _summary;
  List<CashierShiftView> _history = const [];
  StreamSubscription<void>? _subscription;

  UserEntity? get _user {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated ? state.user : null;
  }

  bool get _canViewAll {
    final role = _user?.role;
    return role == UserRole.owner ||
        role == UserRole.manager ||
        role == UserRole.accountant;
  }

  bool get _canOperate => _user?.role != UserRole.accountant;

  @override
  void initState() {
    super.initState();
    _subscription = _service.watchChanges().listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final user = _user;
    if (user == null) return;
    if (mounted) setState(() => _loading = true);
    try {
      final current = await _service.getOpenShiftForUser(user.id);
      final history = await _service.getShiftHistory(
        userId: _canViewAll ? null : user.id,
      );
      final summary = current == null
          ? null
          : await _service.getSummary(current.shift.id);
      if (!mounted) return;
      setState(() {
        _current = current;
        _summary = summary;
        _history = history;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _openShift() async {
    final user = _user;
    if (user == null) return;
    final result = await showDialog<_OpenShiftResult>(
      context: context,
      builder: (_) => const _OpenShiftDialog(),
    );
    if (result == null) return;
    try {
      await _service.openShift(
        userId: user.id,
        openingCashCents: result.openingCashCents,
        currencyCode: sl<CurrencyService>().currencyCode,
        notes: result.notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('cashier_shifts.open_success'.tr())),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  Future<void> _closeCurrent() async {
    final user = _user;
    final current = _current;
    final summary = _summary;
    if (user == null || current == null || summary == null) return;
    final result = await showDialog<_CloseShiftResult>(
      context: context,
      builder: (_) => _CloseShiftDialog(
        expectedCents: summary.expectedCashCents,
        symbol: current.currencySymbol,
      ),
    );
    if (result == null) return;
    try {
      await _service.closeShift(
        shiftId: current.shift.id,
        closedByUserId: user.id,
        countedClosingCashCents: result.countedCashCents,
        notes: result.notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('cashier_shifts.close_success'.tr())),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_localizedShiftError(error)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('cashier_shifts.title'.tr()),
        actions: [
          IconButton(
            onPressed: _load,
            tooltip: 'common.refresh'.tr(),
            icon: const Icon(LucideIcons.refreshCw),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _history.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    _ErrorCard(message: _localizedShiftError(_error!)),
                  Text(
                    'cashier_shifts.current_shift'.tr(),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_current == null)
                    _NoOpenShiftCard(
                      canOperate: _canOperate,
                      onOpen: _openShift,
                    )
                  else
                    _CurrentShiftCard(
                      view: _current!,
                      summary: _summary,
                      canClose: _canOperate,
                      onDetails: () =>
                          context.push('/cashier-shifts/${_current!.shift.id}'),
                      onClose: _closeCurrent,
                    ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _canViewAll
                              ? 'cashier_shifts.all_history'.tr()
                              : 'cashier_shifts.my_history'.tr(),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        '${_history.length}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_history.isEmpty)
                    _EmptyHistoryCard()
                  else
                    ..._history.map(
                      (view) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ShiftHistoryCard(
                          view: view,
                          onTap: () =>
                              context.push('/cashier-shifts/${view.shift.id}'),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      floatingActionButton: _current == null && _canOperate
          ? FloatingActionButton.extended(
              onPressed: _openShift,
              icon: const Icon(LucideIcons.play),
              label: Text('cashier_shifts.open_shift'.tr()),
            )
          : null,
    );
  }
}

class CashierShiftDetailScreen extends StatefulWidget {
  final int shiftId;

  const CashierShiftDetailScreen({super.key, required this.shiftId});

  @override
  State<CashierShiftDetailScreen> createState() =>
      _CashierShiftDetailScreenState();
}

class _CashierShiftDetailScreenState extends State<CashierShiftDetailScreen> {
  final _service = sl<CashierShiftService>();
  bool _loading = true;
  CashierShiftView? _view;
  CashierShiftSummary? _summary;
  List<ShiftTransactionView> _transactions = const [];
  Object? _error;

  UserEntity? get _user {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated ? state.user : null;
  }

  bool get _canClose {
    final user = _user;
    final view = _view;
    if (user == null || view == null || view.shift.status != 'open') {
      return false;
    }
    return user.id == view.shift.cashierUserId ||
        user.role == UserRole.owner ||
        user.role == UserRole.manager;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final view = await _service.getShift(widget.shiftId);
      if (view == null) throw StateError('cashier_shift_not_found');
      final user = _user;
      final canViewAll =
          user?.role == UserRole.owner ||
          user?.role == UserRole.manager ||
          user?.role == UserRole.accountant;
      if (user == null ||
          (!canViewAll && view.shift.cashierUserId != user.id)) {
        throw StateError('cashier_shift_access_denied');
      }
      final values = await Future.wait<Object>([
        _service.getSummary(widget.shiftId),
        _service.getTransactions(widget.shiftId),
      ]);
      if (!mounted) return;
      setState(() {
        _view = view;
        _summary = values[0] as CashierShiftSummary;
        _transactions = values[1] as List<ShiftTransactionView>;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _close() async {
    final user = _user;
    final view = _view;
    final summary = _summary;
    if (user == null || view == null || summary == null) return;
    final result = await showDialog<_CloseShiftResult>(
      context: context,
      builder: (_) => _CloseShiftDialog(
        expectedCents: summary.expectedCashCents,
        symbol: view.currencySymbol,
      ),
    );
    if (result == null) return;
    try {
      await _service.closeShift(
        shiftId: view.shift.id,
        closedByUserId: user.id,
        countedClosingCashCents: result.countedCashCents,
        notes: result.notes,
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_localizedShiftError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(
        title: Text(view?.shift.shiftNumber ?? 'cashier_shifts.details'.tr()),
        actions: [
          if (_canClose)
            TextButton.icon(
              onPressed: _close,
              icon: const Icon(LucideIcons.square),
              label: Text('cashier_shifts.close_shift'.tr()),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || view == null || summary == null
          ? Center(child: _ErrorCard(message: _localizedShiftError(_error!)))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ShiftHeaderCard(view: view),
                  const SizedBox(height: 12),
                  _SummarySection(
                    summary: summary,
                    symbol: view.currencySymbol,
                    currencyCode: view.currencyCode,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'cashier_shifts.payment_breakdown'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (summary.paymentBreakdown.isEmpty)
                    Text('cashier_shifts.no_payments'.tr())
                  else
                    ...summary.paymentBreakdown.map(
                      (item) => Card(
                        child: ListTile(
                          leading: const Icon(LucideIcons.walletCards),
                          title: Text(_paymentMethod(item.method)),
                          subtitle: Text(
                            '${'cashier_shifts.received'.tr()}: '
                            '${_money(item.receivedCents, view.currencySymbol)}  •  '
                            '${'cashier_shifts.refunded'.tr()}: '
                            '${_money(item.refundedCents, view.currencySymbol)}',
                          ),
                          trailing: Text(
                            _money(item.netCents, view.currencySymbol),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    '${'cashier_shifts.transactions'.tr()} '
                    '(${_transactions.length})',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_transactions.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text('cashier_shifts.no_transactions'.tr()),
                        ),
                      ),
                    )
                  else
                    ..._transactions.map(
                      (tx) => _TransactionCard(transaction: tx),
                    ),
                ],
              ),
            ),
    );
  }
}

class _NoOpenShiftCard extends StatelessWidget {
  final bool canOperate;
  final VoidCallback onOpen;

  const _NoOpenShiftCard({required this.canOperate, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(LucideIcons.timerOff, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'cashier_shifts.no_open_shift'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'cashier_shifts.no_open_shift_desc'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            if (canOperate) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(LucideIcons.play),
                label: Text('cashier_shifts.open_shift'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CurrentShiftCard extends StatelessWidget {
  final CashierShiftView view;
  final CashierShiftSummary? summary;
  final bool canClose;
  final VoidCallback onDetails;
  final VoidCallback onClose;

  const _CurrentShiftCard({
    required this.view,
    required this.summary,
    required this.canClose,
    required this.onDetails,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer.withAlpha(90),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  child: const Icon(LucideIcons.user),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        view.cashierName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(view.shift.shiftNumber),
                    ],
                  ),
                ),
                Chip(label: Text('cashier_shifts.status_open'.tr())),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${'cashier_shifts.started_at'.tr()}: '
              '${_dateTime(view.shift.openedAt)}',
            ),
            Text(
              '${'cashier_shifts.duration'.tr()}: '
              '${_duration(view.shift.openedAt, DateTime.now())}',
            ),
            if (summary != null) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniMetric(
                    label: 'cashier_shifts.sales'.tr(),
                    value: '${summary!.salesCount}',
                  ),
                  _MiniMetric(
                    label: 'cashier_shifts.returns'.tr(),
                    value: '${summary!.returnsCount}',
                  ),
                  _MiniMetric(
                    label: 'cashier_shifts.expected_cash'.tr(),
                    value: _money(
                      summary!.expectedCashCents,
                      view.currencySymbol,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDetails,
                    icon: const Icon(LucideIcons.list),
                    label: Text('cashier_shifts.view_details'.tr()),
                  ),
                ),
                if (canClose) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onClose,
                      icon: const Icon(LucideIcons.square),
                      label: Text('cashier_shifts.close_shift'.tr()),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShiftHistoryCard extends StatelessWidget {
  final CashierShiftView view;
  final VoidCallback onTap;

  const _ShiftHistoryCard({required this.view, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isOpen = view.shift.status == 'open';
    final color = isOpen ? Colors.green : Theme.of(context).colorScheme.outline;
    final end = view.shift.closedAt ?? DateTime.now();
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Icon(isOpen ? LucideIcons.timer : LucideIcons.history),
        ),
        title: Text(
          view.cashierName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${view.shift.shiftNumber}\n'
          '${_dateTime(view.shift.openedAt)}  •  '
          '${_duration(view.shift.openedAt, end)}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              isOpen
                  ? 'cashier_shifts.status_open'.tr()
                  : 'cashier_shifts.status_closed'.tr(),
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            if (!isOpen && view.shift.cashVarianceCents != null)
              Text(
                '${'cashier_shifts.variance'.tr()}: '
                '${_money(view.shift.cashVarianceCents!.toBigInt().toInt(), view.currencySymbol)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _ShiftHeaderCard extends StatelessWidget {
  final CashierShiftView view;

  const _ShiftHeaderCard({required this.view});

  @override
  Widget build(BuildContext context) {
    final end = view.shift.closedAt ?? DateTime.now();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _LabelValue(
              label: 'cashier_shifts.cashier'.tr(),
              value: view.cashierName,
            ),
            _LabelValue(
              label: 'cashier_shifts.status'.tr(),
              value: view.shift.status == 'open'
                  ? 'cashier_shifts.status_open'.tr()
                  : 'cashier_shifts.status_closed'.tr(),
            ),
            _LabelValue(
              label: 'cashier_shifts.started_at'.tr(),
              value: _dateTime(view.shift.openedAt),
            ),
            if (view.shift.closedAt != null)
              _LabelValue(
                label: 'cashier_shifts.closed_at'.tr(),
                value: _dateTime(view.shift.closedAt!),
              ),
            _LabelValue(
              label: 'cashier_shifts.duration'.tr(),
              value: _duration(view.shift.openedAt, end),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  final CashierShiftSummary summary;
  final String symbol;
  final String currencyCode;

  const _SummarySection({
    required this.summary,
    required this.symbol,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = <({String label, String value, IconData icon})>[
      (
        label: 'cashier_shifts.gross_sales'.tr(),
        value: _money(summary.grossSalesCents, symbol),
        icon: LucideIcons.shoppingCart,
      ),
      (
        label: 'cashier_shifts.total_returns'.tr(),
        value: _money(summary.returnsCents, symbol),
        icon: LucideIcons.undo2,
      ),
      (
        label: 'cashier_shifts.net_sales'.tr(),
        value: _money(summary.netSalesCents, symbol),
        icon: LucideIcons.trendingUp,
      ),
      (
        label: 'cashier_shifts.opening_cash'.tr(),
        value: _money(summary.openingCashCents, symbol),
        icon: LucideIcons.wallet,
      ),
      (
        label: 'cashier_shifts.cash_received'.tr(),
        value: _money(summary.cashReceivedCents, symbol),
        icon: LucideIcons.arrowDownCircle,
      ),
      (
        label: 'cashier_shifts.cash_refunded'.tr(),
        value: _money(summary.cashRefundedCents, symbol),
        icon: LucideIcons.arrowUpCircle,
      ),
      (
        label: 'cashier_shifts.expected_cash'.tr(),
        value: _money(summary.expectedCashCents, symbol),
        icon: LucideIcons.calculator,
      ),
      if (summary.countedCashCents != null)
        (
          label: 'cashier_shifts.counted_cash'.tr(),
          value: _money(summary.countedCashCents!, symbol),
          icon: LucideIcons.badgeCheck,
        ),
      if (summary.varianceCents != null)
        (
          label: 'cashier_shifts.variance'.tr(),
          value: _money(summary.varianceCents!, symbol),
          icon: LucideIcons.scale,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${'cashier_shifts.summary'.tr()} ($currencyCode)',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 700
                ? (constraints.maxWidth - 24) / 3
                : (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metrics
                  .map(
                    (metric) => SizedBox(
                      width: width,
                      child: _MetricCard(
                        label: metric.label,
                        value: metric.value,
                        icon: metric.icon,
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        if (summary.foreignCurrencyTransactions > 0) ...[
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(LucideIcons.info),
              title: Text(
                'cashier_shifts.foreign_currency_notice'.tr(
                  args: ['${summary.foreignCurrencyTransactions}'],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final ShiftTransactionView transaction;

  const _TransactionCard({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isRefund =
        transaction.kind == ShiftTransactionKind.linkedReturn ||
        transaction.kind == ShiftTransactionKind.adjustmentReturn;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(switch (transaction.kind) {
            ShiftTransactionKind.sale => LucideIcons.shoppingCart,
            ShiftTransactionKind.linkedReturn => LucideIcons.undo2,
            ShiftTransactionKind.adjustmentReturn => LucideIcons.refreshCcw,
            ShiftTransactionKind.payment => LucideIcons.banknote,
          }),
        ),
        title: Text(
          '${_transactionKind(transaction.kind)} • '
          '${transaction.documentNumber}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${_dateTime(transaction.occurredAt)}  •  '
          '${_paymentMethod(transaction.paymentMethod)}  •  '
          '${transaction.currencyCode}',
        ),
        trailing: Text(
          '${isRefund ? '-' : ''}'
          '${_money(transaction.amountCents, transaction.currencySymbol)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isRefund
                ? Theme.of(context).colorScheme.error
                : Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;

  const _MiniMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;

  const _LabelValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;

  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(LucideIcons.alertTriangle),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _EmptyHistoryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('cashier_shifts.no_history'.tr())),
      ),
    );
  }
}

class _OpenShiftResult {
  final int openingCashCents;
  final String? notes;

  const _OpenShiftResult(this.openingCashCents, this.notes);
}

class _CloseShiftResult {
  final int countedCashCents;
  final String? notes;

  const _CloseShiftResult(this.countedCashCents, this.notes);
}

class _OpenShiftDialog extends StatefulWidget {
  const _OpenShiftDialog();

  @override
  State<_OpenShiftDialog> createState() => _OpenShiftDialogState();
}

class _OpenShiftDialogState extends State<_OpenShiftDialog> {
  final _amount = TextEditingController(text: '0');
  final _notes = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = sl<MoneyInputParser>().parse(_amount.text);
    if (!parsed.isValid) {
      setState(() => _error = 'cashier_shifts.invalid_amount'.tr());
      return;
    }
    Navigator.pop(context, _OpenShiftResult(parsed.cents, _notes.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('cashier_shifts.open_shift'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'cashier_shifts.opening_cash'.tr(),
                prefixIcon: const Icon(LucideIcons.wallet),
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'cashier_shifts.notes_optional'.tr(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text('cashier_shifts.open_shift'.tr()),
        ),
      ],
    );
  }
}

class _CloseShiftDialog extends StatefulWidget {
  final int expectedCents;
  final String symbol;

  const _CloseShiftDialog({required this.expectedCents, required this.symbol});

  @override
  State<_CloseShiftDialog> createState() => _CloseShiftDialogState();
}

class _CloseShiftDialogState extends State<_CloseShiftDialog> {
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = sl<MoneyInputParser>().parse(_amount.text);
    if (!parsed.isValid) {
      setState(() => _error = 'cashier_shifts.invalid_amount'.tr());
      return;
    }
    Navigator.pop(context, _CloseShiftResult(parsed.cents, _notes.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('cashier_shifts.close_shift'.tr()),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('cashier_shifts.count_cash_instruction'.tr()),
            const SizedBox(height: 12),
            _LabelValue(
              label: 'cashier_shifts.expected_cash'.tr(),
              value: _money(widget.expectedCents, widget.symbol),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'cashier_shifts.counted_cash'.tr(),
                prefixIcon: const Icon(LucideIcons.calculator),
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'cashier_shifts.closing_notes_optional'.tr(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text('cashier_shifts.confirm_close'.tr()),
        ),
      ],
    );
  }
}

String _localizedShiftError(Object error) {
  final text = error.toString();
  if (text.contains('cashier_shift_already_open')) {
    return 'cashier_shifts.error_already_open'.tr();
  }
  if (text.contains('cashier_shift_no_currency')) {
    return 'cashier_shifts.error_no_currency'.tr();
  }
  if (text.contains('cashier_shift_not_found')) {
    return 'cashier_shifts.error_not_found'.tr();
  }
  if (text.contains('cashier_shift_closed')) {
    return 'cashier_shifts.error_closed'.tr();
  }
  if (text.contains('cashier_shift_access_denied')) {
    return 'cashier_shifts.error_access_denied'.tr();
  }
  return 'cashier_shifts.error_generic'.tr(args: [text]);
}

String _money(int cents, String symbol) {
  final value = cents / 100;
  return '$symbol${NumberFormat('#,##0.00').format(value)}';
}

String _dateTime(DateTime date) => DateFormat.yMMMd().add_jm().format(date);

String _duration(DateTime start, DateTime end) {
  final value = end.difference(start);
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}';
}

String _paymentMethod(String method) {
  final key = 'cashier_shifts.payment_$method';
  final translated = key.tr();
  return translated == key ? method : translated;
}

String _transactionKind(ShiftTransactionKind kind) => switch (kind) {
  ShiftTransactionKind.sale => 'cashier_shifts.kind_sale'.tr(),
  ShiftTransactionKind.linkedReturn => 'cashier_shifts.kind_linked_return'.tr(),
  ShiftTransactionKind.adjustmentReturn =>
    'cashier_shifts.kind_adjustment_return'.tr(),
  ShiftTransactionKind.payment => 'cashier_shifts.kind_payment'.tr(),
};
