import 'package:easy_localization/easy_localization.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../bloc/supplier_profile_bloc.dart';

/// Supplier profile screen with balance, actions, and transactions
class SupplierProfileScreen extends StatefulWidget {
  final int supplierId;

  const SupplierProfileScreen({super.key, required this.supplierId});

  @override
  State<SupplierProfileScreen> createState() => _SupplierProfileScreenState();
}

class _SupplierProfileScreenState extends State<SupplierProfileScreen> {
  var _didBackfillAccounting = false;

  Future<void> _backfillAccountingIfNeeded() async {
    if (_didBackfillAccounting) return;
    _didBackfillAccounting = true;

    final db = sl<AppDatabase>();
    final rows = await db.customSelect(
      'SELECT id FROM purchases WHERE supplier_id = ? AND status = ?',
      variables: [
        Variable.withInt(widget.supplierId),
        const Variable<String>('posted'),
      ],
    ).get();

    for (final r in rows) {
      final purchaseId = r.read<int>('id');
      await db.purchaseDao.ensureSupplierAccountingForPostedPurchase(purchaseId);
    }
  }

  Future<int> _getNetPostedPurchasesSubtotalCents({
    required int supplierId,
    required DateTime start,
    required DateTime end,
  }) async {
    final db = sl<AppDatabase>();

    final purchasesRow = await db.customSelect(
      'SELECT COALESCE(SUM(p.subtotal_cents), 0) AS total '
      'FROM purchases p '
      'WHERE p.supplier_id = ? '
      'AND p.status = ? '
      'AND p.purchase_date >= ? '
      'AND p.purchase_date <= ?',
      variables: [
        Variable.withInt(supplierId),
        const Variable<String>('posted'),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
    ).getSingle();

    final returnsRow = await db.customSelect(
      'SELECT COALESCE(SUM(pr.subtotal_cents), 0) AS total '
      'FROM purchase_returns pr '
      'JOIN purchases p ON p.id = pr.purchase_id '
      'WHERE p.supplier_id = ? '
      'AND pr.status = ? '
      'AND pr.return_date >= ? '
      'AND pr.return_date <= ?',
      variables: [
        Variable.withInt(supplierId),
        const Variable<String>('posted'),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
    ).getSingle();

    final purchasesSubtotal = purchasesRow.read<int>('total');
    final returnsSubtotal = returnsRow.read<int>('total');
    final net = purchasesSubtotal - returnsSubtotal;
    return net < 0 ? 0 : net;
  }

  @override
  Widget build(BuildContext context) {
    final currencyService = sl<CurrencyService>();

    return BlocProvider(
      create: (context) => SupplierProfileBloc(sl<SupplierRepository>())
        ..add(SupplierProfileLoadRequested(widget.supplierId)),
      child: BlocConsumer<SupplierProfileBloc, RealtimeState<Supplier?>>(
        listener: (context, state) async {
          if (state is RealtimeSuccess<Supplier?> && state.data != null) {
            if (!_didBackfillAccounting) {
              final bloc = context.read<SupplierProfileBloc>();
              await _backfillAccountingIfNeeded();
              if (!mounted) return;
              bloc.refresh();
            }
          }
        },
        builder: (context, state) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;

          if (state is RealtimeLoading<Supplier?>) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          if (state is RealtimeError<Supplier?>) {
            return Scaffold(
              appBar: AppBar(),
              body: Center(child: Text('common.error'.tr())),
            );
          }

          final supplier = state is RealtimeSuccess<Supplier?> ? state.data : null;
          if (supplier == null) {
            return Scaffold(
              appBar: AppBar(),
              body: Center(child: Text('suppliers.empty'.tr())),
            );
          }

          final balanceCents = supplier.balanceCents.toBigInt().toInt();

          return Scaffold(
            appBar: AppBar(
              title: Text(supplier.name),
              actions: [
                IconButton(
                  icon: const Icon(LucideIcons.pencil),
                  onPressed: () => context.push('/suppliers/${widget.supplierId}/edit'),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'delete':
                        _showDeleteConfirmation(context, supplier);
                        break;
                      case 'toggle_active':
                        _toggleActive(context, supplier);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'toggle_active',
                      child: Row(
                        children: [
                          Icon(
                            supplier.isActive
                                ? LucideIcons.circleOff
                                : LucideIcons.checkCircle,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            supplier.isActive
                                ? 'suppliers.deactivate'.tr()
                                : 'suppliers.activate'.tr(),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(LucideIcons.trash2, color: colorScheme.error),
                          const SizedBox(width: 8),
                          Text(
                            'suppliers.delete'.tr(),
                            style: TextStyle(color: colorScheme.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            body: SafeArea(
              child: RefreshIndicator(
                onRefresh: () async {
                  context.read<SupplierProfileBloc>().refresh();
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _ProfileHeaderCard(
                      supplier: supplier,
                      balanceCents: balanceCents,
                      currencyService: currencyService,
                    ),
                    const SizedBox(height: 16),
                    _QuickActionsSection(
                      supplier: supplier,
                      onPaymentPressed: () => _showPaymentDialog(context, supplier),
                      onSeasonalDiscountPressed: () => _showSeasonalDiscountDialog(context, supplier),
                    ),
                    const SizedBox(height: 16),
                    _UpcomingDueDatesSection(
                      supplierId: widget.supplierId,
                      currencyService: currencyService,
                    ),
                    const SizedBox(height: 16),
                    _ContactInformationSection(supplier: supplier),
                    const SizedBox(height: 16),
                    _RecentTransactionsSection(supplierId: widget.supplierId),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Supplier supplier) {
    final balanceCents = supplier.balanceCents.toBigInt().toInt();

    if (balanceCents != 0) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('suppliers.delete_not_allowed_title'.tr()),
          content: Text('suppliers.delete_not_allowed_message'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('common.close'.tr()),
            ),
          ],
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('suppliers.delete_confirm_title'.tr()),
        content: Text('suppliers.delete_confirm_message'.tr(args: [supplier.name])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              final router = GoRouter.of(context);
              navigator.pop();
              await sl<SupplierRepository>().deleteSupplier(supplier.id);
              if (mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('suppliers.deleted_success'.tr())),
                );
                router.pop();
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
  }

  void _toggleActive(BuildContext context, Supplier supplier) async {
    final updatedSupplier = supplier.copyWith(
      isActive: !supplier.isActive,
      updatedAt: DateTime.now(),
    );
    await sl<SupplierRepository>().updateSupplier(updatedSupplier);
  }

  void _showPaymentDialog(BuildContext context, Supplier supplier) {
    final profileBloc = context.read<SupplierProfileBloc>();
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('suppliers.make_payment'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              decoration: InputDecoration(
                labelText: 'suppliers.payment_amount'.tr(),
                prefixIcon: const Icon(LucideIcons.banknote),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              onTap: () {
                if (amountController.text == '0.00' || amountController.text.isEmpty) {
                  amountController.clear();
                }
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: InputDecoration(
                labelText: 'suppliers.description'.tr(),
                hintText: 'suppliers.payment_description_hint'.tr(),
                prefixIcon: const Icon(LucideIcons.fileText),
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
            onPressed: () async {
              final scaffoldMessenger = ScaffoldMessenger.of(dialogContext);
              final navigator = Navigator.of(dialogContext);
              final amount = double.tryParse(amountController.text);
              if (amount == null || amount <= 0) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('suppliers.amount_invalid'.tr())),
                );
                return;
              }

              navigator.pop();

              final amountCents = (amount * 100).round();
              await sl<SupplierRepository>().recordTransaction(
                supplierId: supplier.id,
                transactionType: 'payment',
                amountCents: -amountCents,
                currencyId: supplier.currencyId,
                description: descriptionController.text.isEmpty
                    ? null
                    : descriptionController.text,
              );

              profileBloc.refresh();

              if (mounted) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('suppliers.payment_success'.tr())),
                );
              }
            },
            child: Text('suppliers.confirm_payment'.tr()),
          ),
        ],
      ),
    );
  }

  void _showSeasonalDiscountDialog(BuildContext context, Supplier supplier) {
    final profileBloc = context.read<SupplierProfileBloc>();
    final currencyService = sl<CurrencyService>();

    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1);

    final amountController = TextEditingController();
    final percentController = TextEditingController();
    final descriptionController = TextEditingController();

    var updating = false;
    var selectedMode = 'fixed';
    var periodMode = 'month';
    DateTime startDate = firstOfMonth;
    DateTime endDate = now;

    var baseFuture = _getNetPostedPurchasesSubtotalCents(
      supplierId: supplier.id,
      start: startDate,
      end: endDate,
    );

    void reloadBase() {
      baseFuture = _getNetPostedPurchasesSubtotalCents(
        supplierId: supplier.id,
        start: startDate,
        end: endDate,
      );
    }

    void updateFromPercent(int baseCents) {
      if (updating) return;
      updating = true;

      final pct = double.tryParse(percentController.text);
      if (pct == null || pct < 0) {
        updating = false;
        return;
      }

      final base = baseCents.abs();
      if (base == 0) {
        amountController.text = '0.00';
        updating = false;
        return;
      }

      final amountCents = ((base * pct) / 100).round();
      amountController.text = (amountCents / 100).toStringAsFixed(2);
      updating = false;
    }

    void updateFromAmount(int baseCents) {
      if (updating) return;
      updating = true;

      final amount = double.tryParse(amountController.text);
      if (amount == null || amount < 0) {
        updating = false;
        return;
      }

      final base = baseCents.abs();
      if (base == 0) {
        percentController.text = '0';
        updating = false;
        return;
      }

      final amountCents = (amount * 100).round();
      final pct = (amountCents / base) * 100;
      percentController.text = pct.toStringAsFixed(pct >= 10 ? 1 : 2);
      updating = false;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return FutureBuilder<int>(
            future: baseFuture,
            builder: (context, snapshot) {
              final baseCents = snapshot.data ?? 0;

              return AlertDialog(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('suppliers.seasonal_discount_title'.tr()),
                    const SizedBox(height: 6),
                    Text(
                      'suppliers.discount_base_hint'.tr(args: [currencyService.format(baseCents)]),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'month',
                          label: Text('suppliers.period_this_month'.tr()),
                          icon: const Icon(LucideIcons.calendarDays),
                        ),
                        ButtonSegment(
                          value: 'last30',
                          label: Text('suppliers.period_last_30_days'.tr()),
                          icon: const Icon(LucideIcons.calendarClock),
                        ),
                        ButtonSegment(
                          value: 'custom',
                          label: Text('suppliers.period_custom'.tr()),
                          icon: const Icon(LucideIcons.calendarRange),
                        ),
                      ],
                      selected: {periodMode},
                      onSelectionChanged: (v) async {
                        setState(() {
                          periodMode = v.first;
                          final n = DateTime.now();
                          if (periodMode == 'month') {
                            startDate = DateTime(n.year, n.month, 1);
                            endDate = n;
                          } else if (periodMode == 'last30') {
                            startDate = n.subtract(const Duration(days: 30));
                            endDate = n;
                          }
                          reloadBase();
                          updateFromAmount(baseCents);
                        });
                      },
                    ),
                    if (periodMode == 'custom') ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: dialogContext,
                                  initialDate: startDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked == null) return;
                                setState(() {
                                  startDate = DateTime(picked.year, picked.month, picked.day);
                                  if (startDate.isAfter(endDate)) {
                                    endDate = startDate;
                                  }
                                  reloadBase();
                                });
                              },
                              icon: const Icon(LucideIcons.calendar),
                              label: Text('suppliers.start_date'.tr()),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: dialogContext,
                                  initialDate: endDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked == null) return;
                                setState(() {
                                  endDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
                                  if (endDate.isBefore(startDate)) {
                                    startDate = DateTime(picked.year, picked.month, picked.day);
                                  }
                                  reloadBase();
                                });
                              },
                              icon: const Icon(LucideIcons.calendar),
                              label: Text('suppliers.end_date'.tr()),
                            ),
                          ),
                        ],
                      ),
                    ],
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'fixed',
                          label: Text('suppliers.discount_fixed'.tr()),
                          icon: const Icon(LucideIcons.badgeDollarSign),
                        ),
                        ButtonSegment(
                          value: 'percent',
                          label: Text('suppliers.discount_percent'.tr()),
                          icon: const Icon(LucideIcons.percent),
                        ),
                      ],
                      selected: {selectedMode},
                      onSelectionChanged: (v) {
                        setState(() {
                          selectedMode = v.first;
                          if (selectedMode == 'percent') {
                            updateFromAmount(baseCents);
                          } else {
                            updateFromPercent(baseCents);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: amountController,
                            decoration: InputDecoration(
                              labelText: 'suppliers.discount_amount'.tr(),
                              prefixIcon: const Icon(LucideIcons.badgeDollarSign),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            autofocus: selectedMode == 'fixed',
                            enabled: true,
                            onChanged: (_) {
                              if (selectedMode == 'percent') return;
                              updateFromAmount(baseCents);
                            },
                            onTap: () {
                              if (amountController.text == '0.00' || amountController.text.isEmpty) {
                                amountController.clear();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: percentController,
                            decoration: InputDecoration(
                              labelText: 'suppliers.discount_percent'.tr(),
                              prefixIcon: const Icon(LucideIcons.percent),
                              suffixText: '%',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            autofocus: selectedMode == 'percent',
                            enabled: baseCents != 0,
                            onChanged: (_) {
                              if (selectedMode == 'fixed') return;
                              updateFromPercent(baseCents);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: 'suppliers.description'.tr(),
                        hintText: 'suppliers.seasonal_discount_hint'.tr(),
                        prefixIcon: const Icon(LucideIcons.fileText),
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
                    onPressed: () async {
                      final scaffoldMessenger = ScaffoldMessenger.of(dialogContext);
                      final navigator = Navigator.of(dialogContext);

                      final amount = double.tryParse(amountController.text);
                      if (amount == null || amount <= 0) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(content: Text('suppliers.amount_invalid'.tr())),
                        );
                        return;
                      }

                      if (baseCents <= 0) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(content: Text('suppliers.discount_base_zero'.tr())),
                        );
                        return;
                      }

                      navigator.pop();

                      final amountCents = (amount * 100).round();

                      await sl<SupplierRepository>().recordTransaction(
                        supplierId: supplier.id,
                        transactionType: 'discount',
                        amountCents: -amountCents,
                        currencyId: supplier.currencyId,
                        description: descriptionController.text.isEmpty
                            ? 'suppliers.seasonal_discount'.tr()
                            : descriptionController.text,
                      );

                      profileBloc.refresh();

                      if (mounted) {
                        scaffoldMessenger.showSnackBar(
                          SnackBar(content: Text('suppliers.seasonal_discount_recorded'.tr())),
                        );
                      }
                    },
                    child: Text('suppliers.record_discount'.tr()),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  final Supplier supplier;
  final int balanceCents;
  final CurrencyService currencyService;

  const _ProfileHeaderCard({
    required this.supplier,
    required this.balanceCents,
    required this.currencyService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final isPayable = balanceCents > 0;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  colorScheme.primaryContainer.withValues(alpha: 0.3),
                  colorScheme.surfaceContainerHighest,
                ]
              : [
                  colorScheme.primaryContainer.withValues(alpha: 0.4),
                  colorScheme.surface,
                ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Avatar
            CircleAvatar(
              radius: 40,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.15),
              child: Text(
                supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Name
            Text(
              supplier.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Balance section inside the header card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? colorScheme.surface.withValues(alpha: 0.5)
                    : colorScheme.surface.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Text(
                    'suppliers.current_balance'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    currencyService.format(balanceCents),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isPayable
                          ? (isDark ? const Color(0xFF90CAF9) : colorScheme.primary)
                          : (isDark ? const Color(0xFFEF9A9A) : colorScheme.error),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isPayable
                        ? 'suppliers.balance_payable'.tr()
                        : 'suppliers.balance_credit'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionsSection extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback onPaymentPressed;
  final VoidCallback onSeasonalDiscountPressed;

  const _QuickActionsSection({
    required this.supplier,
    required this.onPaymentPressed,
    required this.onSeasonalDiscountPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    final paymentBtn = _QuickActionButton(
      icon: LucideIcons.banknote,
      label: 'suppliers.payment'.tr(),
      color: isDark ? const Color(0xFF90CAF9) : colorScheme.primary,
      backgroundColor: isDark
          ? colorScheme.primaryContainer.withValues(alpha: 0.22)
          : colorScheme.primaryContainer.withValues(alpha: 0.45),
      onTap: onPaymentPressed,
    );

    final purchaseBtn = _QuickActionButton(
      icon: LucideIcons.badgePercent,
      label: 'suppliers.seasonal_discount'.tr(),
      color: isDark ? const Color(0xFFFFCC80) : colorScheme.secondary,
      backgroundColor: isDark
          ? colorScheme.secondaryContainer.withValues(alpha: 0.22)
          : colorScheme.secondaryContainer.withValues(alpha: 0.45),
      onTap: onSeasonalDiscountPressed,
    );

    final returnBtn = _QuickActionButton(
      icon: LucideIcons.undo2,
      label: 'suppliers.return_items'.tr(),
      color: isDark ? const Color(0xFF80CBC4) : colorScheme.tertiary,
      backgroundColor: isDark
          ? colorScheme.tertiaryContainer.withValues(alpha: 0.22)
          : colorScheme.tertiaryContainer.withValues(alpha: 0.45),
      onTap: () => context.push('/purchases/returns'),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;

        if (!isNarrow) {
          return Row(
            children: [
              Expanded(child: paymentBtn),
              const SizedBox(width: 12),
              Expanded(child: purchaseBtn),
              const SizedBox(width: 12),
              Expanded(child: returnBtn),
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: paymentBtn),
                const SizedBox(width: 12),
                Expanded(child: purchaseBtn),
              ],
            ),
            const SizedBox(height: 12),
            returnBtn,
          ],
        );
      },
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingDueDatesSection extends StatelessWidget {
  final int supplierId;
  final CurrencyService currencyService;

  const _UpcomingDueDatesSection({
    required this.supplierId,
    required this.currencyService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final db = sl<AppDatabase>();

    return StreamBuilder<List<Purchase>>(
      stream: db.purchaseDao.watchUpcomingDuePurchases(supplierId),
      builder: (context, snapshot) {
        final purchases = snapshot.data ?? [];
        if (purchases.isEmpty) return const SizedBox.shrink();

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Icon(LucideIcons.calendarClock, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'suppliers.upcoming_due_dates'.tr(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${purchases.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ...purchases.map((p) {
                final dueDate = p.dueDate!;
                final dueDateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
                final daysUntilDue = dueDateOnly.difference(today).inDays;
                final isOverdue = daysUntilDue < 0;
                final isDueToday = daysUntilDue == 0;
                final isDueSoon = daysUntilDue > 0 && daysUntilDue <= 7;

                final totalCents = p.totalCents.toBigInt().toInt();
                final paidCents = p.paidAmountCents.toBigInt().toInt();
                final remainingCents = totalCents - paidCents;

                final isCheque = p.paymentMethod == 'cheque';

                final Color statusColor;
                final String statusText;
                final IconData statusIcon;

                if (isOverdue) {
                  statusColor = cs.error;
                  statusText = 'suppliers.overdue_days'.tr(args: ['${-daysUntilDue}']);
                  statusIcon = LucideIcons.alertTriangle;
                } else if (isDueToday) {
                  statusColor = const Color(0xFFFF9800);
                  statusText = 'suppliers.due_today'.tr();
                  statusIcon = LucideIcons.clock;
                } else if (isDueSoon) {
                  statusColor = const Color(0xFFFF9800);
                  statusText = 'suppliers.due_in_days'.tr(args: ['$daysUntilDue']);
                  statusIcon = LucideIcons.clock;
                } else {
                  statusColor = cs.onSurfaceVariant;
                  statusText = 'suppliers.due_in_days'.tr(args: ['$daysUntilDue']);
                  statusIcon = LucideIcons.calendar;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isOverdue
                          ? cs.errorContainer.withValues(alpha: 0.15)
                          : isDueSoon || isDueToday
                              ? const Color(0xFFFF9800).withValues(alpha: 0.08)
                              : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isOverdue
                            ? cs.error.withValues(alpha: 0.3)
                            : isDueSoon || isDueToday
                                ? const Color(0xFFFF9800).withValues(alpha: 0.3)
                                : cs.outlineVariant.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isCheque ? LucideIcons.fileText : LucideIcons.receipt,
                              size: 14,
                              color: cs.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                p.purchaseNumber,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isCheque)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cs.secondaryContainer.withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'suppliers.cheque'.tr(),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.secondary,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(statusIcon, size: 12, color: statusColor),
                            const SizedBox(width: 4),
                            Text(
                              '${dueDate.year}-${dueDate.month.toString().padLeft(2, '0')}-${dueDate.day.toString().padLeft(2, '0')}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusText,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: statusColor,
                                fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              currencyService.format(remainingCents),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isOverdue ? cs.error : cs.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

class _ContactInformationSection extends StatelessWidget {
  final Supplier supplier;

  const _ContactInformationSection({required this.supplier});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Hide section if all contact info is null
    if (supplier.email == null && supplier.phone == null && supplier.address == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'suppliers.contact_info'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (supplier.email != null)
              _ContactRow(
                icon: LucideIcons.mail,
                iconColor: Colors.blue,
                label: 'suppliers.email'.tr(),
                value: supplier.email!,
              ),
            if (supplier.phone != null)
              _ContactRow(
                icon: LucideIcons.phone,
                iconColor: Colors.green,
                label: 'suppliers.phone'.tr(),
                value: supplier.phone!,
              ),
            if (supplier.address != null)
              _ContactRow(
                icon: LucideIcons.mapPin,
                iconColor: Colors.orange,
                label: 'suppliers.address'.tr(),
                value: supplier.address!,
              ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String value;

  const _ContactRow({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor ?? theme.colorScheme.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTransactionsSection extends StatelessWidget {
  final int supplierId;

  const _RecentTransactionsSection({required this.supplierId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyService = sl<CurrencyService>();

    return StreamBuilder<List<SupplierTransaction>>(
      stream: sl<SupplierRepository>().watchSupplierTransactions(supplierId),
      builder: (context, snapshot) {
        final transactions = snapshot.data ?? [];

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'suppliers.recent_transactions'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: Text('suppliers.view_all'.tr()),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (transactions.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(
                            LucideIcons.fileText,
                            size: 48,
                            color: theme.colorScheme.outline.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'suppliers.no_transactions'.tr(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...transactions.take(5).map((tx) => _TransactionTile(
                    transaction: tx,
                    currencyService: currencyService,
                  )),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final SupplierTransaction transaction;
  final CurrencyService currencyService;

  const _TransactionTile({
    required this.transaction,
    required this.currencyService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountCents = transaction.amountCents.toDouble().round();
    final isNegative = amountCents < 0;

    IconData icon;
    Color color;
    switch (transaction.transactionType) {
      case 'payment':
        icon = LucideIcons.banknote;
        color = Colors.blue;
        break;
      case 'discount':
        icon = LucideIcons.badgePercent;
        color = Colors.purple;
        break;
      case 'purchase':
        icon = LucideIcons.shoppingCart;
        color = Colors.orange;
        break;
      case 'return':
        icon = LucideIcons.arrowLeftRight;
        color = Colors.green;
        break;
      default:
        icon = LucideIcons.fileText;
        color = theme.colorScheme.outline;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.1),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.transactionType.toUpperCase(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                if (transaction.description != null)
                  Text(
                    transaction.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currencyService.format(amountCents.abs()),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isNegative ? Colors.green : Colors.red,
                ),
              ),
              Text(
                _formatDate(transaction.transactionDate),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
