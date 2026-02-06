import 'package:easy_localization/easy_localization.dart';
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
  @override
  Widget build(BuildContext context) {
    final currencyService = sl<CurrencyService>();

    return BlocProvider(
      create: (context) => SupplierProfileBloc(sl<SupplierRepository>())
        ..add(SupplierProfileLoadRequested(widget.supplierId)),
      child: BlocBuilder<SupplierProfileBloc, RealtimeState<Supplier?>>(
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

          final balanceCents = supplier.balanceCents.toDouble().round();

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
                      onPurchasePressed: () => context.push('/purchases/new'),
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
    final balanceCents = supplier.balanceCents.toDouble().round();

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

              // Update balance
              final currentBalance = supplier.balanceCents.toDouble().round();
              await sl<SupplierRepository>().updateSupplierBalance(
                supplier.id,
                currentBalance - amountCents,
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
                          ? (isDark ? Colors.amber.shade300 : Colors.amber.shade700)
                          : Colors.green,
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
  final VoidCallback onPurchasePressed;

  const _QuickActionsSection({
    required this.supplier,
    required this.onPaymentPressed,
    required this.onPurchasePressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final paymentBtn = _QuickActionButton(
      icon: LucideIcons.banknote,
      label: 'suppliers.payment'.tr(),
      color: isDark ? Colors.blue.shade300 : Colors.blue.shade600,
      backgroundColor: isDark ? Colors.blue.shade900.withValues(alpha: 0.3) : Colors.blue.shade50,
      onTap: onPaymentPressed,
    );

    final purchaseBtn = _QuickActionButton(
      icon: LucideIcons.shoppingCart,
      label: 'suppliers.new_purchase'.tr(),
      color: isDark ? Colors.orange.shade300 : Colors.orange.shade600,
      backgroundColor: isDark ? Colors.orange.shade900.withValues(alpha: 0.3) : Colors.orange.shade50,
      onTap: onPurchasePressed,
    );

    final returnBtn = _QuickActionButton(
      icon: LucideIcons.arrowLeftRight,
      label: 'suppliers.return_items'.tr(),
      color: isDark ? Colors.green.shade300 : Colors.green.shade600,
      backgroundColor: isDark ? Colors.green.shade900.withValues(alpha: 0.3) : Colors.green.shade50,
      onTap: () {},
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
      borderRadius: BorderRadius.circular(12),
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
