import 'package:easy_localization/easy_localization.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/parties/party_balance_classifier.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../bloc/supplier_profile_bloc.dart';
import '../services/supplier_transaction_pdf_service.dart';
import '../../../customers/presentation/widgets/edit_transaction_dialog.dart';
import '../../../shared/widgets/unified_return_search_sheet.dart';
import '../../../../core/services/unified_return_service.dart';

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
                    _RecentTransactionsSection(supplierId: widget.supplierId, supplierName: supplier.name),
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
    var selectedDate = DateTime.now();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stfContext, setState) {
          final theme = Theme.of(stfContext);
          final colorScheme = theme.colorScheme;

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.banknote, size: 40, color: colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      'suppliers.make_payment'.tr(),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: amountController,
                      decoration: InputDecoration(
                        labelText: 'suppliers.payment_amount'.tr(),
                        prefixIcon: const Icon(LucideIcons.badgeDollarSign),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      onTap: () => selectAllText(amountController),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'suppliers.payment_date'.tr(),
                          prefixIcon: const Icon(LucideIcons.calendarDays),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                        ),
                        child: Text(
                          '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: 'suppliers.description'.tr(),
                        hintText: 'suppliers.payment_description_hint'.tr(),
                        prefixIcon: const Icon(LucideIcons.fileText),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('common.cancel'.tr()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
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

                              // Phase 3.5.3 — sign-flip lives in
                              // SupplierRepository.recordPayment.
                              final amountCents = (amount * 100).round();
                              final txId = await sl<SupplierRepository>().recordPayment(
                                supplierId: supplier.id,
                                amountCents: amountCents,
                                currencyId: supplier.currencyId,
                                description: descriptionController.text.isEmpty
                                    ? null
                                    : descriptionController.text,
                                transactionDate: selectedDate,
                              );

                              profileBloc.refresh();

                              if (mounted) {
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(content: Text('suppliers.payment_success'.tr())),
                                );
                                _showReceiptDialog(this.context, txId, supplier.name);
                              }
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('suppliers.confirm_payment'.tr()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showReceiptDialog(BuildContext context, int transactionId, String supplierName) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.checkCircle, color: Colors.green, size: 48),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        try {
                          await SupplierTransactionPdfService.printReceiptById(
                            context: context,
                            transactionId: transactionId,
                            supplierName: supplierName,
                          );
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('suppliers.print_error'.tr()),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(LucideIcons.printer),
                      label: Text(
                        'suppliers.print_receipt'.tr(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        try {
                          await SupplierTransactionPdfService.shareReceiptById(
                            context: context,
                            transactionId: transactionId,
                            supplierName: supplierName,
                          );
                        } catch (_) {
                          // Sharing is best-effort
                        }
                      },
                      icon: const Icon(LucideIcons.share2),
                      label: Text(
                        'suppliers.share_receipt'.tr(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text('common.close'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSeasonalDiscountDialog(BuildContext context, Supplier supplier) {
    final profileBloc = context.read<SupplierProfileBloc>();

    final amountController = TextEditingController();
    final descriptionController = TextEditingController();

    var selectedDiscountType = 'seasonal';
    var selectedDate = DateTime.now();

    final discountTypes = [
      'seasonal',
      'volume',
      'loyalty',
      'promotional',
      'early_payment',
      'other',
    ];

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (stfContext, setState) {
          final theme = Theme.of(stfContext);
          final colorScheme = theme.colorScheme;

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.badgePercent, size: 40, color: colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      'suppliers.seasonal_discount_title'.tr(),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      initialValue: selectedDiscountType,
                      decoration: InputDecoration(
                        labelText: 'suppliers.discount_type'.tr(),
                        prefixIcon: const Icon(LucideIcons.tag),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                      ),
                      items: discountTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text('suppliers.discount_type_$type'.tr()),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => selectedDiscountType = v);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      decoration: InputDecoration(
                        labelText: 'suppliers.discount_amount'.tr(),
                        prefixIcon: const Icon(LucideIcons.badgeDollarSign),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      autofocus: true,
                      onTap: () => selectAllText(amountController),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'suppliers.discount_date'.tr(),
                          prefixIcon: const Icon(LucideIcons.calendarDays),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                        ),
                        child: Text(
                          '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      decoration: InputDecoration(
                        labelText: 'suppliers.description'.tr(),
                        hintText: 'suppliers.seasonal_discount_hint'.tr(),
                        prefixIcon: const Icon(LucideIcons.fileText),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('common.cancel'.tr()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
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

                              // Phase 3.5.3 — discount uses repository
                              // helper so the negation rule is centralised.
                              final txId = await sl<SupplierRepository>().recordDiscount(
                                supplierId: supplier.id,
                                amountCents: amountCents,
                                currencyId: supplier.currencyId,
                                description: descriptionController.text.isEmpty
                                    ? 'suppliers.discount_type_$selectedDiscountType'.tr()
                                    : descriptionController.text,
                                discountType: selectedDiscountType,
                                transactionDate: selectedDate,
                              );

                              profileBloc.refresh();

                              if (mounted) {
                                scaffoldMessenger.showSnackBar(
                                  SnackBar(content: Text('suppliers.seasonal_discount_recorded'.tr())),
                                );
                                _showReceiptDialog(this.context, txId, supplier.name);
                              }
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('suppliers.record_discount'.tr()),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
    // Phase 3.5.2 — delegate sign interpretation to the classifier so this
    // widget cannot drift from `supplier_hub` / `customer_*` screens.
    final status = sl<PartyBalanceClassifier>().statusOf(
      balanceCents,
      PartyKind.supplier,
    );
    final isPayable = status == PartyBalanceStatus.payable;
    final isZero = status == PartyBalanceStatus.settled;
    final openingBalanceCents = supplier.openingBalanceCents.toBigInt().toInt();

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
                      color: isZero
                          ? (isDark ? const Color(0xFF64B5F6) : Colors.blue)
                          : isPayable
                              ? (isDark ? const Color(0xFFEF9A9A) : Colors.red)
                              : (isDark ? const Color(0xFFA5D6A7) : Colors.green),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isZero
                        ? 'suppliers.balance_settled'.tr()
                        : isPayable
                            ? 'suppliers.balance_payable'.tr()
                            : 'suppliers.balance_credit'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  // Show opening balance if it exists
                  if (openingBalanceCents != 0) ...[
                    const SizedBox(height: 12),
                    Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
                    const SizedBox(height: 8),
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'suppliers.opening_balance'.tr(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              currencyService.format(openingBalanceCents.abs()),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: openingBalanceCents > 0
                                    ? (isDark ? const Color(0xFFEF9A9A) : Colors.red)
                                    : (isDark ? const Color(0xFFA5D6A7) : Colors.green),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          openingBalanceCents > 0
                              ? '(${'suppliers.opening_balance_payable'.tr()})'
                              : '(${'suppliers.opening_balance_credit'.tr()})',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
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
      onTap: () {
        showUnifiedReturnSearchSheet(
          context,
          side: ReturnSide.purchase,
          partyId: supplier.id,
          partyName: supplier.name,
        );
      },
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

class _RecentTransactionsSection extends StatefulWidget {
  final int supplierId;
  final String supplierName;

  const _RecentTransactionsSection({required this.supplierId, required this.supplierName});

  @override
  State<_RecentTransactionsSection> createState() => _RecentTransactionsSectionState();
}

class _RecentTransactionsSectionState extends State<_RecentTransactionsSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyService = sl<CurrencyService>();

    return StreamBuilder<List<SupplierTransaction>>(
      stream: sl<SupplierRepository>().watchSupplierTransactions(widget.supplierId),
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
                      onPressed: () {
                        setState(() {
                          _showAll = !_showAll;
                        });
                      },
                      child: Text(_showAll ? 'common.show_less'.tr() : 'suppliers.view_all'.tr()),
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
                  ...((_showAll ? transactions : transactions.take(5)).map((tx) => _TransactionTile(
                    transaction: tx,
                    currencyService: currencyService,
                    supplierName: widget.supplierName,
                  ))),
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
  final String? supplierName;

  const _TransactionTile({
    required this.transaction,
    required this.currencyService,
    this.supplierName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amountCents = transaction.amountCents.toDouble().round();
    final isNegative = amountCents < 0;

    IconData icon;
    Color color;
    String typeLabel;
    switch (transaction.transactionType) {
      case 'payment':
        icon = LucideIcons.banknote;
        color = Colors.blue;
        typeLabel = 'suppliers.transaction_payment'.tr();
        break;
      case 'discount':
        icon = LucideIcons.badgePercent;
        color = Colors.purple;
        typeLabel = 'suppliers.transaction_discount'.tr();
        break;
      case 'purchase':
        icon = LucideIcons.shoppingCart;
        color = Colors.orange;
        typeLabel = 'suppliers.transaction_purchase'.tr();
        break;
      case 'return':
        icon = LucideIcons.arrowLeftRight;
        color = Colors.green;
        typeLabel = 'suppliers.transaction_return'.tr();
        break;
      case 'credit_note':
        icon = LucideIcons.fileText;
        color = Colors.green;
        typeLabel = 'suppliers.transaction_credit_note'.tr();
        break;
      case 'refund':
        icon = LucideIcons.arrowLeftRight;
        color = Colors.green;
        typeLabel = 'suppliers.transaction_refund'.tr();
        break;
      case 'credit_note_reversal':
        icon = LucideIcons.fileX;
        color = Colors.red;
        typeLabel = 'suppliers.transaction_credit_note_reversal'.tr();
        break;
      case 'refund_reversal':
        icon = LucideIcons.fileX;
        color = Colors.red;
        typeLabel = 'suppliers.transaction_refund_reversal'.tr();
        break;
      case 'adjustment_return':
        icon = LucideIcons.unlink;
        color = Colors.teal;
        typeLabel = 'suppliers.transaction_adj_return'.tr();
        break;
      case 'adjustment_return_reversal':
        icon = LucideIcons.unlink;
        color = Colors.red;
        typeLabel = 'suppliers.transaction_adj_return_reversal'.tr();
        break;
      default:
        icon = LucideIcons.fileText;
        color = theme.colorScheme.outline;
        typeLabel = transaction.transactionType.toUpperCase();
    }

    final canPrint = transaction.transactionType == 'payment' ||
        transaction.transactionType == 'discount';

    return InkWell(
      onTap: canPrint && supplierName != null
          ? () => _showTxReceiptOptions(context)
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
                  Row(
                    children: [
                      Text(
                        typeLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      if (transaction.transactionType == 'discount' &&
                          transaction.discountType != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'suppliers.discount_type_${transaction.discountType}'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.purple,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (transaction.transactionNumber != null)
                    Text(
                      transaction.transactionNumber!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
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
            if (canPrint) ...[
              const SizedBox(width: 4),
              Icon(LucideIcons.chevronRight, size: 14, color: theme.colorScheme.outline),
            ],
          ],
        ),
      ),
    );
  }

  void _showTxReceiptOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.pencil),
              title: Text('suppliers.edit_transaction'.tr()),
              onTap: () {
                Navigator.pop(sheetContext);
                _showEditDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.printer),
              title: Text('suppliers.print_receipt'.tr()),
              onTap: () {
                Navigator.pop(sheetContext);
                SupplierTransactionPdfService.printReceipt(
                  context: context,
                  transaction: transaction,
                  supplierName: supplierName!,
                );
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.share2),
              title: Text('suppliers.share_receipt'.tr()),
              onTap: () {
                Navigator.pop(sheetContext);
                SupplierTransactionPdfService.shareReceipt(
                  context: context,
                  transaction: transaction,
                  supplierName: supplierName!,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final absCents = transaction.amountCents.toDouble().round().abs();
    EditTransactionDialog.show(
      context: context,
      currentAmountCents: absCents,
      transactionType: transaction.transactionType,
      currentDescription: transaction.description,
      onSave: (newAmountCents, newDescription) async {
        await sl<SupplierRepository>().updateTransaction(
          transactionId: transaction.id,
          newAmountCents: newAmountCents,
          newDescription: newDescription,
        );
      },
    ).then((edited) {
      if (edited && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('suppliers.transaction_updated'.tr())),
        );
      }
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
