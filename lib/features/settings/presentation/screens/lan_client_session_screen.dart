import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/money/money_input_parser.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

class LanClientSessionScreen extends StatefulWidget {
  const LanClientSessionScreen({super.key});

  @override
  State<LanClientSessionScreen> createState() => _LanClientSessionScreenState();
}

class _LanClientSessionScreenState extends State<LanClientSessionScreen> {
  LanCashierShiftSnapshot? _shift;
  bool _loadingShift = true;
  bool _shiftLoadInFlight = false;
  bool _working = false;
  String? _error;

  LanNetworkService get _lan => sl<LanNetworkService>();

  UserEntity? get _user {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated ? state.user : null;
  }

  bool get _isCashier => _user?.role == UserRole.cashier;

  @override
  void initState() {
    super.initState();
    _loadShift();
  }

  Future<void> _loadShift() async {
    if (_shiftLoadInFlight) return;
    if (!_isCashier) {
      if (mounted) setState(() => _loadingShift = false);
      return;
    }
    _shiftLoadInFlight = true;
    if (mounted) {
      setState(() {
        _loadingShift = true;
        _error = null;
      });
    }
    try {
      final shift = await _lan.fetchOwnRemoteShift().timeout(
        const Duration(seconds: 12),
      );
      if (!mounted) return;
      setState(() {
        _shift = shift;
        _loadingShift = false;
        _error = null;
      });
      if (shift?.isOpen == true &&
          GoRouterState.of(context).uri.queryParameters['continue'] == 'sale') {
        context.go('/sales/new');
      }
    } on LanBusinessException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        setState(() => _loadingShift = false);
        context.read<AuthBloc>().add(const AuthLogoutRequested());
        return;
      }
      setState(() {
        _loadingShift = false;
        _error = error.message;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loadingShift = false;
        _error = 'settings.network.test_failed'.tr();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingShift = false;
        _error = 'settings.network.test_failed'.tr();
      });
    } finally {
      _shiftLoadInFlight = false;
    }
  }

  void _goBack() => context.go('/dashboard');

  Future<void> _openShift() async {
    final input = await showDialog<_ShiftCashInput>(
      context: context,
      builder: (_) => const _ShiftCashDialog(opening: true),
    );
    if (input == null) return;
    setState(() => _working = true);
    try {
      final shift = await _lan.openOwnRemoteShift(
        openingCashCents: input.cents,
        notes: input.notes,
      );
      if (!mounted) return;
      setState(() {
        _shift = shift;
        _working = false;
        _error = null;
      });
      if (GoRouterState.of(context).uri.queryParameters['continue'] == 'sale') {
        context.go('/sales/new');
      }
    } on LanBusinessException catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = 'settings.network.test_failed'.tr();
      });
    }
  }

  Future<bool> _closeShift() async {
    final shift = _shift;
    if (shift == null) return true;
    final input = await showDialog<_ShiftCashInput>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ShiftCashDialog(
        opening: false,
        expectedCents: shift.expectedCashCents,
        symbol: shift.currencySymbol,
      ),
    );
    if (input == null) return false;
    setState(() => _working = true);
    try {
      await _lan.closeOwnRemoteShift(
        countedCashCents: input.cents,
        notes: input.notes,
      );
      if (!mounted) return false;
      setState(() {
        _shift = null;
        _working = false;
        _error = null;
      });
      return true;
    } on LanBusinessException catch (error) {
      if (!mounted) return false;
      setState(() {
        _working = false;
        _error = error.message;
      });
      return false;
    } catch (_) {
      if (!mounted) return false;
      setState(() {
        _working = false;
        _error = 'settings.network.test_failed'.tr();
      });
      return false;
    }
  }

  Future<void> _switchUser() async {
    if (_isCashier && _shift != null && !await _closeShift()) return;
    if (!mounted) return;
    context.read<AuthBloc>().add(const AuthLogoutRequested());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lan = _lan.snapshot;

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.network.client_session_title'.tr()),
        leading: BackButton(onPressed: _goBack),
        actions: [
          IconButton(
            onPressed: _loadingShift || _working ? null : _loadShift,
            icon: const Icon(LucideIcons.refreshCw),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<AuthBloc, RealtimeState<UserEntity?>>(
          builder: (context, state) {
            final user = state is AuthAuthenticated ? state.user : null;
            final remote = _lan.remoteUser;
            final permissions = remote?.permissions ?? const <String>[];
            final canCreateSales = const [
              'create_sales',
              'process_sales',
              'manage_sales',
            ].any(permissions.contains);
            if (user == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final saleReady =
                canCreateSales && (!_isCashier || _shift?.isOpen == true);

            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 620),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        LucideIcons.badgeCheck,
                        size: 64,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        remote?.employeeName ?? user.username,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        user.username,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: const Icon(LucideIcons.shieldCheck),
                              title: Text('settings.network.role'.tr()),
                              subtitle: Text(
                                'settings.network.role_{}'
                                    .replaceFirst('{}', user.role.name)
                                    .tr(),
                              ),
                            ),
                            const Divider(height: 1),
                            ListTile(
                              leading: const Icon(LucideIcons.server),
                              title: Text(
                                'settings.network.master_address'.tr(),
                              ),
                              subtitle: Text(
                                '${lan.masterHost ?? ''}:${lan.port}',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_isCashier) ...[
                        const SizedBox(height: 16),
                        _CashierShiftCard(
                          shift: _shift,
                          loading: _loadingShift,
                          working: _working,
                          error: _error,
                          onRetry: _loadShift,
                          onOpen: _openShift,
                          onClose: _closeShift,
                        ),
                      ],
                      const SizedBox(height: 20),
                      Card(
                        color: saleReady
                            ? colors.tertiaryContainer
                            : colors.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(
                                saleReady
                                    ? LucideIcons.unlock
                                    : LucideIcons.lock,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  saleReady
                                      ? 'settings.network.sales_ready'.tr()
                                      : _isCashier && _shift == null
                                      ? 'settings.network.open_shift_first'.tr()
                                      : 'settings.network.no_sales_permission'
                                            .tr(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (canCreateSales)
                        FilledButton.icon(
                          onPressed: saleReady
                              ? () => context.go('/sales/new')
                              : null,
                          icon: const Icon(LucideIcons.shoppingCart),
                          label: Text('settings.network.open_sale'.tr()),
                        ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _working ? null : _switchUser,
                        icon: const Icon(LucideIcons.logOut),
                        label: Text('settings.network.switch_user'.tr()),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CashierShiftCard extends StatelessWidget {
  final LanCashierShiftSnapshot? shift;
  final bool loading;
  final bool working;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onOpen;
  final Future<bool> Function() onClose;

  const _CashierShiftCard({
    required this.shift,
    required this.loading,
    required this.working,
    required this.error,
    required this.onRetry,
    required this.onOpen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return Card(
      color: shift == null
          ? cs.surfaceContainerHigh
          : cs.primaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(shift == null ? LucideIcons.timerOff : LucideIcons.timer),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    shift == null
                        ? 'cashier_shifts.no_open_shift'.tr()
                        : shift!.cashierName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (shift != null)
                  Chip(label: Text('cashier_shifts.status_open'.tr())),
              ],
            ),
            if (shift != null) ...[
              const SizedBox(height: 10),
              Text(shift!.shiftNumber),
              Text(
                '${'cashier_shifts.sales'.tr()}: ${shift!.salesCount}  "  '
                '${'cashier_shifts.returns'.tr()}: ${shift!.returnsCount}',
              ),
              Text(
                '${'cashier_shifts.expected_cash'.tr()}: '
                '${shift!.currencySymbol}'
                '${(shift!.expectedCashCents / 100).toStringAsFixed(2)}',
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 14),
            if (error != null)
              OutlinedButton.icon(
                onPressed: working ? null : onRetry,
                icon: const Icon(LucideIcons.refreshCw),
                label: Text('common.retry'.tr()),
              )
            else if (shift == null)
              FilledButton.icon(
                onPressed: working ? null : onOpen,
                icon: const Icon(LucideIcons.play),
                label: Text('cashier_shifts.open_shift'.tr()),
              )
            else
              OutlinedButton.icon(
                onPressed: working ? null : () => onClose(),
                icon: const Icon(LucideIcons.square),
                label: Text('cashier_shifts.close_shift'.tr()),
              ),
          ],
        ),
      ),
    );
  }
}

class _ShiftCashInput {
  final int cents;
  final String? notes;

  const _ShiftCashInput(this.cents, this.notes);
}

class _ShiftCashDialog extends StatefulWidget {
  final bool opening;
  final int? expectedCents;
  final String? symbol;

  const _ShiftCashDialog({
    required this.opening,
    this.expectedCents,
    this.symbol,
  });

  @override
  State<_ShiftCashDialog> createState() => _ShiftCashDialogState();
}

class _ShiftCashDialogState extends State<_ShiftCashDialog> {
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
    if (!parsed.isValid || parsed.cents < 0) {
      setState(() => _error = 'cashier_shifts.invalid_amount'.tr());
      return;
    }
    Navigator.pop(
      context,
      _ShiftCashInput(
        parsed.cents,
        _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.opening
            ? 'cashier_shifts.open_shift'.tr()
            : 'cashier_shifts.close_shift'.tr(),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.opening && widget.expectedCents != null) ...[
              Text(
                '${'cashier_shifts.expected_cash'.tr()}: '
                '${widget.symbol ?? ''}'
                '${(widget.expectedCents! / 100).toStringAsFixed(2)}',
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: widget.opening
                    ? 'cashier_shifts.opening_cash'.tr()
                    : 'cashier_shifts.counted_cash'.tr(),
                errorText: _error,
                prefixIcon: const Icon(LucideIcons.wallet),
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
        FilledButton(onPressed: _submit, child: Text('common.confirm'.tr())),
      ],
    );
  }
}
