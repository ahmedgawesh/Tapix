import 'package:easy_localization/easy_localization.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/theme/colors.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/compliance/customer_credit_note_service.dart';
import '../../../../core/services/parties/party_balance_classifier.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../../../core/di/injection_container.dart';
import '../../../sales/domain/repositories/sale_repository.dart';
import '../../../sales/domain/entities/sale_entity.dart';
import '../../domain/repositories/customer_repository.dart';
import '../../domain/repositories/loyalty_repository.dart';
import '../bloc/customer_loyalty_bloc.dart';
import '../bloc/customer_profile_bloc.dart';
import '../services/customer_transaction_pdf_service.dart';
import '../widgets/edit_transaction_dialog.dart';
import '../../../shared/widgets/unified_return_search_sheet.dart';
import '../../../../core/services/unified_return_service.dart';

/// Customer profile screen with 360° view
class CustomerProfileScreen extends StatefulWidget {
  final int customerId;

  const CustomerProfileScreen({super.key, required this.customerId});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _OutstandingChequesSection extends StatelessWidget {
  final int customerId;

  const _OutstandingChequesSection({required this.customerId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final currencyService = sl<CurrencyService>();

    return StreamBuilder<List<SaleEntity>>(
      stream: sl<SaleRepository>().watchCustomerSales(customerId),
      builder: (context, snapshot) {
        final sales = snapshot.data ?? const <SaleEntity>[];
        final chequeSales = sales
            .where((s) =>
                s.isCompleted &&
                s.paymentMethod == 'cheque' &&
                s.dueDate != null &&
                s.remainingCents > Decimal.zero)
            .toList();

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event_note_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'customers.outstanding_cheques'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else if (chequeSales.isEmpty)
                  Text(
                    'customers.no_outstanding_cheques'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  )
                else
                  ...chequeSales.take(5).map((s) {
                    final dueDate = s.dueDate;
                    final isOverdue = dueDate != null && DateTime.now().isAfter(dueDate);
                    final remainingCents = s.remainingCents.toBigInt().toInt();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () => context.push('/sales/${s.id}'),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (isOverdue ? cs.error : cs.primary).withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: (isOverdue ? cs.error : cs.primary).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.payments_outlined,
                                color: isOverdue ? cs.error : cs.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'customers.cheque_for_invoice'.tr(args: [s.invoiceNumber]),
                                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    if (dueDate != null)
                                      Text(
                                        'customers.cheque_due_on'.tr(args: [DateFormat.yMMMd().format(dueDate)]),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    currencyService.format(remainingCents),
                                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    (isOverdue
                                            ? 'customers.cheque_overdue'
                                            : 'customers.cheque_pending')
                                        .tr(),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: isOverdue ? cs.error : cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Surfaces the customer's store-credit notes (issued by credit-refund
/// adjustment returns). These settle to GL 2400 Customer Credit Liability
/// via `CustomerCreditNoteService` and therefore never appear in
/// `customer_transactions`; without this section an adjustment return that
/// issued store credit would be invisible on the profile. Renders nothing
/// when the customer has no open/applied notes.
class _StoreCreditSection extends StatelessWidget {
  final int customerId;
  final CurrencyService currencyService;

  const _StoreCreditSection({
    required this.customerId,
    required this.currencyService,
  });

  String _statusLabel(String status) {
    switch (status) {
      case 'partially_applied':
        return 'customers.store_credit_status_partially_applied'.tr();
      case 'fully_applied':
        return 'customers.store_credit_status_fully_applied'.tr();
      case 'open':
      default:
        return 'customers.store_credit_status_open'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<List<CustomerCreditNote>>(
      stream: sl<CustomerCreditNoteService>().watchForCustomer(customerId),
      builder: (context, snapshot) {
        final notes = snapshot.data ?? const <CustomerCreditNote>[];
        if (notes.isEmpty) {
          return const SizedBox.shrink();
        }

        final totalAvailable = notes.fold<int>(
          0,
          (sum, n) => sum + n.balanceCents.toBigInt().toInt(),
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
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
                    children: [
                      const Icon(LucideIcons.wallet, size: 18, color: Colors.teal),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'customers.store_credit_title'.tr(),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        currencyService.format(totalAvailable),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'customers.store_credit_subtitle'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...notes.map((note) {
                    final balance = note.balanceCents.toBigInt().toInt();
                    final original = note.originalAmountCents.toBigInt().toInt();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: Colors.teal.withValues(alpha: 0.1),
                            child: const Icon(LucideIcons.ticket,
                                size: 18, color: Colors.teal),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  note.noteNumber,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${_statusLabel(note.status)} · '
                                  '${'customers.store_credit_original'.tr()}: '
                                  '${currencyService.format(original)}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                currencyService.format(balance),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                              Text(
                                'customers.store_credit_available'.tr(),
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
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  void _openUnifiedReturn(BuildContext context, Customer customer) {
    showUnifiedReturnSearchSheet(
      context,
      side: ReturnSide.sale,
      partyId: customer.id,
      partyName: customer.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyService = sl<CurrencyService>();

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => CustomerProfileBloc(sl<CustomerRepository>())
            ..add(CustomerProfileLoadRequested(widget.customerId)),
        ),
        BlocProvider(
          create: (context) => CustomerLoyaltyBloc(sl<LoyaltyRepository>())
            ..add(CustomerLoyaltyLoadRequested(widget.customerId)),
        ),
      ],
      child: BlocBuilder<CustomerProfileBloc, RealtimeState<Customer?>>(
        builder: (context, state) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;

          if (state is RealtimeLoading<Customer?>) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: CircularProgressIndicator()),
            );
          }

          if (state is RealtimeError<Customer?>) {
            return Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Text('common.error'.tr()),
              ),
            );
          }

          final customer = state is RealtimeSuccess<Customer?> ? state.data : null;
          if (customer == null) {
            return Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Text('customers.empty'.tr()),
              ),
            );
          }

          final balanceCents = customer.balanceCents.toBigInt().toInt();

          return Scaffold(
            appBar: AppBar(
              title: Text(customer.name),
              actions: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => context.push('/customers/${widget.customerId}/edit'),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'delete':
                        _showDeleteConfirmation(context, customer);
                        break;
                      case 'toggle_active':
                        _toggleActive(context, customer);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'toggle_active',
                      child: Row(
                        children: [
                          Icon(
                            customer.isActive
                                ? Icons.block_outlined
                                : Icons.check_circle_outline,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            customer.isActive
                                ? 'customers.deactivate'.tr()
                                : 'customers.activate'.tr(),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: colorScheme.error),
                          const SizedBox(width: 8),
                          Text(
                            'customers.delete'.tr(),
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
                  context.read<CustomerProfileBloc>().refresh();
                  context.read<CustomerLoyaltyBloc>().refresh();
                },
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _ProfileHeaderCard(customer: customer),
                    const SizedBox(height: 16),
                    _BalanceCard(
                      balanceCents: balanceCents,
                      openingBalanceCents: customer.openingBalanceCents.toBigInt().toInt(),
                      currencyService: currencyService,
                    ),
                    const SizedBox(height: 16),
                    _StoreCreditSection(
                      customerId: widget.customerId,
                      currencyService: currencyService,
                    ),
                    _LoyaltyToggleCard(customer: customer),
                    const SizedBox(height: 16),
                    if (customer.loyaltyEnabled) ...[
                      _LoyaltySection(customerId: widget.customerId),
                      const SizedBox(height: 16),
                    ],
                    _QuickActionsSection(
                      customer: customer,
                      onPaymentPressed: () => _showPaymentDialog(context, customer),
                      onDiscountPressed: () => _showDiscountDialog(context, customer),
                      onReturnPressed: () => _openUnifiedReturn(context, customer),
                    ),
                    const SizedBox(height: 16),
                    _OutstandingChequesSection(customerId: widget.customerId),
                    const SizedBox(height: 16),
                    _ContactInformationSection(customer: customer),
                    const SizedBox(height: 16),
                    _RecentTransactionsSection(customerId: widget.customerId, customer: customer),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Customer customer) {
    final balanceCents = customer.balanceCents.toBigInt().toInt();
    
    if (balanceCents != 0) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('customers.delete_not_allowed_title'.tr()),
          content: Text('customers.delete_not_allowed_message'.tr()),
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
        title: Text('customers.delete_confirm_title'.tr()),
        content: Text('customers.delete_confirm_message'.tr(args: [customer.name])),
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
              final colorScheme = Theme.of(context).colorScheme;
              navigator.pop();
              try {
                await sl<CustomerRepository>().deleteCustomer(customer.id);
                if (mounted) {
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text('customers.deleted_success'.tr())),
                  );
                  router.pop();
                }
              } catch (e) {
                if (!context.mounted) return;

                final msg = e.toString();
                final isFkError = msg.contains('FOREIGN KEY constraint failed');

                if (isFkError) {
                  showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('customers.delete_blocked_title'.tr()),
                      content: Text('customers.delete_blocked_message'.tr()),
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

                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    backgroundColor: colorScheme.error,
                  ),
                );
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

  void _toggleActive(BuildContext context, Customer customer) async {
    final updatedCustomer = customer.copyWith(
      isActive: !customer.isActive,
      updatedAt: DateTime.now(),
    );
    await sl<CustomerRepository>().updateCustomer(updatedCustomer);
  }

  void _showPaymentDialog(BuildContext context, Customer customer) {
    final profileBloc = context.read<CustomerProfileBloc>();
    final loyaltyBloc = context.read<CustomerLoyaltyBloc>();
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
                      'customers.receive_payment'.tr(),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: amountController,
                      decoration: InputDecoration(
                        labelText: 'customers.payment_amount'.tr(),
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
                          labelText: 'customers.payment_date'.tr(),
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
                        labelText: 'customers.description'.tr(),
                        hintText: 'customers.payment_description_hint'.tr(),
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
                                  SnackBar(content: Text('customers.amount_invalid'.tr())),
                                );
                                return;
                              }

                              navigator.pop();

                              try {
                                // Phase 3.5.3 — sign convention is owned by
                                // the repository (see CustomerRepository.
                                // recordPayment), not by the widget.
                                final amountCents = (amount * 100).round();
                                final txId = await sl<CustomerRepository>().recordPayment(
                                  customerId: customer.id,
                                  amountCents: amountCents,
                                  currencyId: customer.currencyId,
                                  description: descriptionController.text.isEmpty
                                      ? null
                                      : descriptionController.text,
                                  transactionDate: selectedDate,
                                );

                                profileBloc.refresh();
                                loyaltyBloc.refresh();

                                if (mounted) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(content: Text('customers.payment_recorded'.tr())),
                                  );
                                  _showReceiptDialog(this.context, txId, customer);
                                }
                              } catch (e) {
                                if (mounted) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content: Text('common.error'.tr()),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('customers.confirm_payment'.tr()),
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

  void _showReceiptDialog(BuildContext context, int transactionId, Customer customer) {
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
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        CustomerTransactionPdfService.printReceiptById(
                          context: context,
                          transactionId: transactionId,
                          customerName: customer.name,
                          customerPhone: customer.phone,
                          customerAddress: customer.address,
                        );
                      },
                      icon: const Icon(LucideIcons.printer),
                      label: Text(
                        'customers.print_receipt'.tr(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        CustomerTransactionPdfService.shareReceiptById(
                          context: context,
                          transactionId: transactionId,
                          customerName: customer.name,
                          customerPhone: customer.phone,
                          customerAddress: customer.address,
                        );
                      },
                      icon: const Icon(LucideIcons.share2),
                      label: Text(
                        'customers.share_receipt'.tr(),
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

  void _showDiscountDialog(BuildContext context, Customer customer) {
    final profileBloc = context.read<CustomerProfileBloc>();
    final loyaltyBloc = context.read<CustomerLoyaltyBloc>();

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
                      'customers.add_discount'.tr(),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<String>(
                      initialValue: selectedDiscountType,
                      decoration: InputDecoration(
                        labelText: 'customers.discount_type'.tr(),
                        prefixIcon: const Icon(LucideIcons.tag),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                      ),
                      items: discountTypes.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Text('customers.discount_type_$type'.tr()),
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
                        labelText: 'customers.discount_amount'.tr(),
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
                          labelText: 'customers.discount_date'.tr(),
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
                        labelText: 'customers.description'.tr(),
                        hintText: 'customers.discount_description_hint'.tr(),
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
                                  SnackBar(content: Text('customers.amount_invalid'.tr())),
                                );
                                return;
                              }

                              navigator.pop();

                              try {
                                final amountCents = (amount * 100).round();

                                // Phase 3.5.3 — discount is a positive
                                // operator-facing amount; the repository
                                // negates it before persisting.
                                final txId = await sl<CustomerRepository>().recordDiscount(
                                  customerId: customer.id,
                                  amountCents: amountCents,
                                  currencyId: customer.currencyId,
                                  description: descriptionController.text.isEmpty
                                      ? 'customers.discount_type_$selectedDiscountType'.tr()
                                      : descriptionController.text,
                                  discountType: selectedDiscountType,
                                  transactionDate: selectedDate,
                                );

                                profileBloc.refresh();
                                loyaltyBloc.refresh();

                                if (mounted) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(content: Text('customers.discount_applied'.tr())),
                                  );
                                  _showReceiptDialog(this.context, txId, customer);
                                }
                              } catch (e) {
                                if (mounted) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(
                                      content: Text('common.error'.tr()),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                }
                              }
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text('customers.apply_discount'.tr()),
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
  final Customer customer;

  const _ProfileHeaderCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final headerGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        (isDark ? AppColors.primaryDark : AppColors.primary).withValues(alpha: 0.95),
        (isDark ? AppColors.primary : AppColors.primaryContainer).withValues(alpha: 0.85),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        gradient: headerGradient,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.35),
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: Colors.white.withValues(alpha: isDark ? 0.18 : 0.22),
              child: Text(
                customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              customer.name,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            _SegmentBadge(segment: customer.segment),
            if (customer.phone != null || customer.email != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (customer.phone != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          customer.phone!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  if (customer.email != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.email_outlined,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          customer.email!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegmentBadge extends StatelessWidget {
  final String segment;

  const _SegmentBadge({required this.segment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    Color color;
    IconData icon;
    String label;

    switch (segment) {
      case 'wholesale':
        color = theme.colorScheme.secondary;
        icon = Icons.business_outlined;
        label = 'customers.segment_wholesale'.tr();
        break;
      case 'premium':
        color = theme.colorScheme.tertiary;
        icon = Icons.star;
        label = 'customers.segment_premium'.tr();
        break;
      default:
        color = theme.colorScheme.primary;
        icon = Icons.person_outline;
        label = 'customers.segment_retail'.tr();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isDark ? Colors.black : Colors.white).withValues(alpha: isDark ? 0.25 : 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.18 : 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.95),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final int balanceCents;
  final int openingBalanceCents;
  final CurrencyService currencyService;

  const _BalanceCard({
    required this.balanceCents,
    required this.openingBalanceCents,
    required this.currencyService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Phase 3.5.2 — delegate sign interpretation to the classifier so this
    // widget cannot drift from `customer_hub` / `supplier_*` screens.
    final status = sl<PartyBalanceClassifier>().statusOf(
      balanceCents,
      PartyKind.customer,
    );
    final isReceivable = status == PartyBalanceStatus.receivable;
    final isZero = status == PartyBalanceStatus.settled;
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    final baseCardColor = isDark
        ? const Color(0xFF0B0F14)
        : colorScheme.surface;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: baseCardColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              'customers.current_balance'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.7)
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              currencyService.format(balanceCents),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: isZero
                    ? (isDark ? const Color(0xFF64B5F6) : Colors.blue)
                    : isReceivable
                        ? (isDark ? const Color(0xFFA5D6A7) : Colors.green)
                        : (isDark ? const Color(0xFFEF9A9A) : Colors.red),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isZero
                  ? 'customers.balance_settled'.tr()
                  : isReceivable
                      ? 'customers.balance_receivable'.tr()
                      : 'customers.balance_credit'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.65)
                    : theme.colorScheme.onSurfaceVariant,
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
                        'customers.opening_balance'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.65)
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        currencyService.format(openingBalanceCents),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: openingBalanceCents > 0
                              ? (isDark ? const Color(0xFFA5D6A7) : Colors.green)
                              : (isDark ? const Color(0xFFEF9A9A) : Colors.red),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    openingBalanceCents > 0
                        ? '(${'customers.opening_balance_receivable'.tr()})'
                        : '(${'customers.opening_balance_payable'.tr()})',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.5)
                          : colorScheme.onSurfaceVariant,
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
}

class _LoyaltySection extends StatelessWidget {
  final int customerId;

  const _LoyaltySection({required this.customerId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    return BlocBuilder<CustomerLoyaltyBloc, RealtimeState<CustomerLoyaltySummary?>>(
      builder: (context, state) {
        if (state is RealtimeLoading) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        if (state is RealtimeError) {
          return const SizedBox.shrink();
        }

        if (state is RealtimeSuccess<CustomerLoyaltySummary?>) {
          final summary = state.data;
          if (summary == null) return const SizedBox.shrink();

          final baseCardColor = isDark
              ? const Color(0xFF0B0F14)
              : colorScheme.surface;

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            color: baseCardColor,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        Icons.card_giftcard,
                        color: isDark ? const Color(0xFF90CAF9) : theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'customers.loyalty'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : null,
                        ),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: () => _showChangeTierDialog(context, customerId, summary.currentTier),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: summary.currentTier != null 
                                ? _parseColor(summary.currentTier!.color)
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                summary.currentTier?.name ?? 'customers.no_tier'.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: summary.currentTier != null ? Colors.white : null,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                LucideIcons.chevronDown,
                                size: 14,
                                color: summary.currentTier != null ? Colors.white : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Points Stats
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _LoyaltyStat(
                            icon: Icons.stars_outlined,
                            label: 'customers.points_balance'.tr(),
                            value: summary.pointsBalance.toString(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _LoyaltyStat(
                            icon: Icons.trending_up,
                            label: 'customers.total_points_earned'.tr(),
                            value: summary.totalPointsEarned.toString(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Monetary value of the remaining points balance
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : theme.colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.savings_outlined,
                          size: 18,
                          color: isDark
                              ? const Color(0xFF90CAF9)
                              : theme.colorScheme.tertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'customers.points_balance_value'.tr(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? Colors.white70
                                  : theme.colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ),
                        Text(
                          '${summary.pointsBalanceValueCents} '
                          '${'customers.loyalty_cents'.tr()} = '
                          '${sl<CurrencyService>().format(summary.pointsBalanceValueCents)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tier Progress
                  if (summary.nextTier != null) ...[
                    Text(
                      'customers.tier_progress'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: summary.nextTier!.minPoints > 0
                          ? summary.pointsBalance / summary.nextTier!.minPoints
                          : 0,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${summary.pointsToNextTier} ${summary.nextTier!.name}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Current Benefits
                  if (summary.currentBenefits.isNotEmpty) ...[
                    Text(
                      'customers.your_benefits'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: summary.currentBenefits.map((benefit) {
                        return Chip(
                          label: Text(
                            '${benefit.labelKey.tr()}: ${benefit.value}',
                            style: theme.textTheme.bodySmall,
                          ),
                          backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                        );
                      }).toList(),
                    ),
                  ],

                  // Next Tier Benefits Button
                  if (summary.nextTier != null) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => _showNextTierBenefits(context, summary.nextTier!),
                      icon: const Icon(Icons.lock_open_outlined, size: 18),
                      label: Text('customers.next_tier_benefits'.tr()),
                    ),
                  ],

                  // Points History Button
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _showPointsHistory(context, customerId),
                    icon: const Icon(Icons.history, size: 18),
                    label: Text('customers.points_history'.tr()),
                  ),
                ],
              ),
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Color _parseColor(String hexColor) {
    try {
      return Color(int.parse(hexColor.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.grey;
    }
  }

  Future<void> _showChangeTierDialog(BuildContext context, int customerId, LoyaltyTier? currentTier) async {
    final loyaltyRepo = sl<LoyaltyRepository>();
    final tiers = await loyaltyRepo.getAllTiers();
    
    if (!context.mounted) return;
    
    final selectedTierId = await showDialog<int?>(
      context: context,
      builder: (ctx) => _ChangeTierDialog(
        tiers: tiers,
        currentTierId: currentTier?.id,
      ),
    );
    
    if (selectedTierId == null) return; // User cancelled or no change
    
    // -1 means "remove tier"
    final newTierId = selectedTierId == -1 ? null : selectedTierId;
    
    try {
      await loyaltyRepo.assignTierToCustomer(customerId, newTierId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('customers.tier_updated'.tr())),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showNextTierBenefits(BuildContext context, LoyaltyTier nextTier) {
    final theme = Theme.of(context);
    final loyaltyRepo = sl<LoyaltyRepository>();
    final benefitsSummary = loyaltyRepo.getTierBenefitsSummary(nextTier);

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.star,
                  color: _parseColor(nextTier.color),
                ),
                const SizedBox(width: 8),
                Text(
                  nextTier.name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'customers.next_tier_benefits'.tr(),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...benefitsSummary.benefits.map((benefit) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Text('${benefit.labelKey.tr()}: ${benefit.value}'),
                ],
              ),
            )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _showPointsHistory(BuildContext context, int customerId) async {
    final loyaltyRepo = sl<LoyaltyRepository>();
    final transactions = await loyaltyRepo.getPointsTransactions(customerId);
    
    if (!context.mounted) return;
    
    final theme = Theme.of(context);
    
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'customers.points_history'.tr(),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (transactions.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.history, size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 8),
                        Text(
                          'customers.no_points_history'.tr(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: transactions.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tx = transactions[index];
                      final isEarn = tx.transactionType == 'earn';
                      final isRedeem = tx.transactionType == 'redeem';
                      final isReturn = tx.referenceType == 'sale_return';
                      
                      IconData icon;
                      Color color;
                      String typeLabel;
                      
                      if (isReturn) {
                        icon = Icons.undo;
                        color = Colors.orange;
                        typeLabel = 'customers.points_returned'.tr();
                      } else if (isRedeem) {
                        icon = Icons.redeem;
                        color = Colors.red;
                        typeLabel = 'customers.points_redeemed'.tr();
                      } else {
                        icon = Icons.add_circle;
                        color = Colors.green;
                        typeLabel = 'customers.points_earned'.tr();
                      }
                      
                      final pointsText = isEarn ? '+${tx.points}' : '-${tx.points}';
                      
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.1),
                          child: Icon(icon, color: color, size: 20),
                        ),
                        title: Row(
                          children: [
                            Text(
                              pointsText,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: color,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              typeLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (tx.description != null)
                              Text(
                                tx.description!,
                                style: theme.textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            Text(
                              _formatDate(tx.transactionDate),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                        trailing: Text(
                          'customers.balance_after'.tr(args: [tx.balanceAfter.toString()]),
                          style: theme.textTheme.bodySmall,
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _LoyaltyStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _LoyaltyStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QuickActionsSection extends StatelessWidget {
  final Customer customer;
  final VoidCallback onPaymentPressed;
  final VoidCallback onDiscountPressed;
  final VoidCallback onReturnPressed;

  const _QuickActionsSection({
    required this.customer,
    required this.onPaymentPressed,
    required this.onDiscountPressed,
    required this.onReturnPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final colorScheme = Theme.of(context).colorScheme;

    final paymentBtn = _QuickActionButton(
      icon: Icons.payment,
      label: 'customers.payment'.tr(),
      color: isDark ? const Color(0xFF90CAF9) : colorScheme.primary,
      backgroundColor: isDark ? const Color(0xFF0D1B2A) : colorScheme.primaryContainer.withValues(alpha: 0.4),
      borderColor: isDark ? const Color(0xFF1E3A5F) : colorScheme.primary.withValues(alpha: 0.2),
      onTap: onPaymentPressed,
    );

    final discountBtn = _QuickActionButton(
      icon: Icons.discount_outlined,
      label: 'customers.discount'.tr(),
      color: isDark ? const Color(0xFFFFB74D) : colorScheme.secondary,
      backgroundColor: isDark ? const Color(0xFF1A1408) : colorScheme.secondaryContainer.withValues(alpha: 0.4),
      borderColor: isDark ? const Color(0xFF3D2E10) : colorScheme.secondary.withValues(alpha: 0.2),
      onTap: onDiscountPressed,
    );

    final returnBtn = _QuickActionButton(
      icon: Icons.assignment_return,
      label: 'customers.return'.tr(),
      color: isDark ? const Color(0xFF80CBC4) : colorScheme.tertiary,
      backgroundColor: isDark ? const Color(0xFF0B1A18) : colorScheme.tertiaryContainer.withValues(alpha: 0.4),
      borderColor: isDark ? const Color(0xFF1A3330) : colorScheme.tertiary.withValues(alpha: 0.2),
      onTap: onReturnPressed,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;

        if (!isNarrow) {
          return Row(
            children: [
              Expanded(child: paymentBtn),
              const SizedBox(width: 12),
              Expanded(child: discountBtn),
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
                Expanded(child: discountBtn),
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

class _RecentTransactionsSection extends StatefulWidget {
  final int customerId;
  final Customer customer;

  const _RecentTransactionsSection({required this.customerId, required this.customer});

  @override
  State<_RecentTransactionsSection> createState() => _RecentTransactionsSectionState();
}

class _RecentTransactionsSectionState extends State<_RecentTransactionsSection> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyService = sl<CurrencyService>();

    return StreamBuilder<List<CustomerTransaction>>(
      stream: sl<CustomerRepository>().watchCustomerTransactions(widget.customerId),
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
                      'customers.recent_transactions'.tr(),
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
                      child: Text(_showAll ? 'common.show_less'.tr() : 'customers.view_all'.tr()),
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
                          Icon(LucideIcons.receipt, size: 40, color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                          const SizedBox(height: 8),
                          Text(
                            'customers.no_transactions'.tr(),
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
                    customer: widget.customer,
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
  final CustomerTransaction transaction;
  final CurrencyService currencyService;
  final Customer? customer;

  const _TransactionTile({
    required this.transaction,
    required this.currencyService,
    this.customer,
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
        typeLabel = 'customers.transaction_payment'.tr();
        break;
      case 'discount':
        icon = LucideIcons.badgePercent;
        color = Colors.purple;
        typeLabel = 'customers.transaction_discount'.tr();
        break;
      case 'return':
        icon = LucideIcons.arrowLeftRight;
        color = Colors.green;
        typeLabel = 'customers.transaction_return'.tr();
        break;
      case 'credit_note':
        icon = LucideIcons.fileText;
        color = Colors.green;
        typeLabel = 'customers.transaction_credit_note'.tr();
        break;
      case 'refund':
        icon = LucideIcons.arrowLeftRight;
        color = Colors.green;
        typeLabel = 'customers.transaction_refund'.tr();
        break;
      case 'credit_note_reversal':
        icon = LucideIcons.fileX;
        color = Colors.red;
        typeLabel = 'customers.transaction_credit_note_reversal'.tr();
        break;
      case 'refund_reversal':
        icon = LucideIcons.fileX;
        color = Colors.red;
        typeLabel = 'customers.transaction_refund_reversal'.tr();
        break;
      case 'sale':
        icon = LucideIcons.shoppingCart;
        color = Colors.orange;
        typeLabel = 'customers.transaction_sale'.tr();
        break;
      case 'adjustment_return':
        icon = LucideIcons.unlink;
        color = Colors.teal;
        typeLabel = 'customers.transaction_adj_return'.tr();
        break;
      case 'adjustment_return_reversal':
        icon = LucideIcons.unlink;
        color = Colors.red;
        typeLabel = 'customers.transaction_adj_return_reversal'.tr();
        break;
      case 'adjustment':
        icon = LucideIcons.fileText;
        color = theme.colorScheme.outline;
        typeLabel = 'customers.transaction_adjustment'.tr();
        break;
      default:
        icon = LucideIcons.fileText;
        color = theme.colorScheme.outline;
        typeLabel = transaction.transactionType.toUpperCase();
    }

    final canPrint = transaction.transactionType == 'payment' ||
        transaction.transactionType == 'discount';

    return InkWell(
      onTap: canPrint && customer != null
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
                            'customers.discount_type_${transaction.discountType}'.tr(),
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
              title: Text('customers.edit_transaction'.tr()),
              onTap: () {
                Navigator.pop(sheetContext);
                _showEditDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.printer),
              title: Text('customers.print_receipt'.tr()),
              onTap: () {
                Navigator.pop(sheetContext);
                CustomerTransactionPdfService.printReceipt(
                  context: context,
                  transaction: transaction,
                  customerName: customer!.name,
                  customerPhone: customer!.phone,
                  customerAddress: customer!.address,
                );
              },
            ),
            ListTile(
              leading: const Icon(LucideIcons.share2),
              title: Text('customers.share_receipt'.tr()),
              onTap: () {
                Navigator.pop(sheetContext);
                CustomerTransactionPdfService.shareReceipt(
                  context: context,
                  transaction: transaction,
                  customerName: customer!.name,
                  customerPhone: customer!.phone,
                  customerAddress: customer!.address,
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
        await sl<CustomerRepository>().updateTransaction(
          transactionId: transaction.id,
          newAmountCents: newAmountCents,
          newDescription: newDescription,
        );
      },
    ).then((edited) {
      if (edited && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('customers.transaction_updated'.tr())),
        );
      }
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _LoyaltyToggleCard extends StatelessWidget {
  final Customer customer;

  const _LoyaltyToggleCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: isDark
          ? const Color(0xFF0B0F14)
          : colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.card_giftcard,
              color: isDark ? const Color(0xFF90CAF9) : colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'customers.loyalty'.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    customer.loyaltyEnabled
                        ? 'customers.loyalty_enabled'.tr()
                        : 'customers.loyalty_disabled'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.7)
                          : colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: customer.loyaltyEnabled,
              onChanged: (value) async {
                final updatedCustomer = customer.copyWith(
                  loyaltyEnabled: value,
                  updatedAt: DateTime.now(),
                );
                await sl<CustomerRepository>().updateCustomer(updatedCustomer);
                if (context.mounted) {
                  context.read<CustomerProfileBloc>().refresh();
                  context.read<CustomerLoyaltyBloc>().refresh();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactInformationSection extends StatelessWidget {
  final Customer customer;

  const _ContactInformationSection({required this.customer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (customer.email == null && customer.phone == null && customer.address == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'customers.contact_info'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (customer.email != null) ...[
              Row(
                children: [
                  Icon(Icons.email_outlined, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      customer.email!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (customer.phone != null) ...[
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      customer.phone!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (customer.address != null)
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      customer.address!,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Dialog for changing customer loyalty tier
class _ChangeTierDialog extends StatefulWidget {
  final List<LoyaltyTier> tiers;
  final int? currentTierId;

  const _ChangeTierDialog({
    required this.tiers,
    this.currentTierId,
  });

  @override
  State<_ChangeTierDialog> createState() => _ChangeTierDialogState();
}

class _ChangeTierDialogState extends State<_ChangeTierDialog> {
  late int? _selectedTierId;

  @override
  void initState() {
    super.initState();
    _selectedTierId = widget.currentTierId;
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.grey;
    try {
      return Color(int.parse(hex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return AlertDialog(
      title: Text('customers.change_tier'.tr()),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Option to remove tier
            ListTile(
              leading: const Icon(LucideIcons.userMinus),
              title: Text('customers.no_tier'.tr()),
              subtitle: Text('customers.no_tier_hint'.tr()),
              trailing: Icon(
                _selectedTierId == null 
                    ? Icons.radio_button_checked 
                    : Icons.radio_button_unchecked,
                color: _selectedTierId == null ? cs.primary : cs.outline,
              ),
              onTap: () => setState(() => _selectedTierId = null),
            ),
            const Divider(),
            // List of tiers
            ...widget.tiers.map((tier) {
              final tierColor = _parseColor(tier.color);
              final isSelected = _selectedTierId == tier.id;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: tierColor.withValues(alpha: 0.2),
                  child: Icon(LucideIcons.award, color: tierColor, size: 20),
                ),
                title: Text(
                  tier.name,
                  style: TextStyle(
                    color: tierColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'customers.loyalty_tier_points_range'.tr(args: [
                    tier.minPoints.toString(),
                    tier.maxPoints?.toString() ?? '∞',
                  ]),
                ),
                trailing: Icon(
                  isSelected 
                      ? Icons.radio_button_checked 
                      : Icons.radio_button_unchecked,
                  color: isSelected ? cs.primary : cs.outline,
                ),
                onTap: () => setState(() => _selectedTierId = tier.id),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            // Always return the selected tier ID
            // -1 means "remove tier" (when _selectedTierId is null)
            // Any positive number is a tier ID
            Navigator.pop(context, _selectedTierId ?? -1);
          },
          child: Text('common.save'.tr()),
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final Color? borderColor;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
    this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 1)
            : null,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
