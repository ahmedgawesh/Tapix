import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart' hide Size;
import '../../../../core/services/currency_service.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/repositories/customer_repository.dart';
import '../bloc/customers_bloc.dart';

/// Screen for receiving payment from a customer
class ReceivePaymentScreen extends StatefulWidget {
  final int? preselectedCustomerId;

  const ReceivePaymentScreen({super.key, this.preselectedCustomerId});

  @override
  State<ReceivePaymentScreen> createState() => _ReceivePaymentScreenState();
}

class _ReceivePaymentScreenState extends State<ReceivePaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  
  Customer? _selectedCustomer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedCustomerId != null) {
      _loadPreselectedCustomer();
    }
  }

  Future<void> _loadPreselectedCustomer() async {
    final customer = await sl<CustomerRepository>().getCustomer(widget.preselectedCustomerId!);
    if (mounted && customer != null) {
      setState(() {
        _selectedCustomer = customer;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocProvider(
      create: (context) => CustomersBloc(sl<CustomerRepository>()),
      child: Scaffold(
        appBar: AppBar(
          title: Text('customers.receive_payment'.tr()),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Customer Selection Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'customers.select_customer'.tr(),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_selectedCustomer != null)
                          _buildSelectedCustomerTile(context, _selectedCustomer!)
                        else
                          _buildCustomerSelector(context),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Amount Input Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'customers.payment_details'.tr(),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _amountController,
                          decoration: InputDecoration(
                            labelText: 'customers.payment_amount'.tr(),
                            prefixIcon: const Icon(Icons.attach_money),
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                          ],
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'customers.amount_required'.tr();
                            }
                            final amount = double.tryParse(value);
                            if (amount == null || amount <= 0) {
                              return 'customers.amount_invalid'.tr();
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _descriptionController,
                          decoration: InputDecoration(
                            labelText: 'customers.description'.tr(),
                            hintText: 'customers.description_hint'.tr(),
                            prefixIcon: const Icon(Icons.notes),
                            border: const OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Submit Button
                FilledButton.icon(
                  onPressed: _selectedCustomer == null || _isLoading
                      ? null
                      : _submitPayment,
                  icon: _isLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.payment),
                  label: Text('customers.record_payment'.tr()),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedCustomerTile(BuildContext context, Customer customer) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyService = sl<CurrencyService>();
    final balanceCents = customer.balanceCents.toBigInt().toInt();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.primary,
            child: Text(
              customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
              style: TextStyle(
                color: colorScheme.onPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        customer.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: _buildSegmentBadge(context, customer.segment),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${'customers.current_balance'.tr()}: ${currencyService.format(balanceCents)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: balanceCents > 0 ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() {
                _selectedCustomer = null;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentBadge(BuildContext context, String segment) {
    final theme = Theme.of(context);
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
        color = Colors.amber;
        icon = Icons.star;
        label = 'customers.segment_premium'.tr();
        break;
      default:
        color = theme.colorScheme.primary;
        icon = Icons.person_outline;
        label = 'customers.segment_retail'.tr();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerSelector(BuildContext context) {
    return BlocBuilder<CustomersBloc, RealtimeState<CustomersData>>(
      builder: (context, state) {
        return InkWell(
          onTap: () => _showCustomerPicker(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.person_add_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'customers.tap_to_select'.tr(),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward_ios, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCustomerPicker(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyService = sl<CurrencyService>();

    showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => BlocProvider(
          create: (context) => CustomersBloc(sl<CustomerRepository>()),
          child: Builder(
            builder: (context) => Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        'customers.select_customer'.tr(),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('common.cancel'.tr()),
                      ),
                    ],
                  ),
                ),
                // Search bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'customers.search_hint'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                    ),
                    onChanged: (value) {
                      context.read<CustomersBloc>().add(
                        CustomersSearchRequested(value),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                // Customer list
                Expanded(
                  child: BlocBuilder<CustomersBloc, RealtimeState<CustomersData>>(
                    builder: (context, state) {
                      if (state is RealtimeLoading<CustomersData>) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (state is RealtimeSuccess<CustomersData>) {
                        final customers = state.data.customers;
                        if (customers.isEmpty) {
                          return Center(
                            child: Text('customers.no_results'.tr()),
                          );
                        }

                        return ListView.builder(
                          controller: scrollController,
                          itemCount: customers.length,
                          itemBuilder: (context, index) {
                            final customer = customers[index];
                            final balanceCents = customer.balanceCents.toBigInt().toInt();

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.primaryContainer,
                                child: Text(
                                  customer.name.isNotEmpty
                                      ? customer.name[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      customer.name,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildSegmentBadge(context, customer.segment),
                                ],
                              ),
                              subtitle: Text(
                                currencyService.format(balanceCents),
                                style: TextStyle(
                                  color: balanceCents > 0 ? Colors.red : Colors.green,
                                ),
                              ),
                              onTap: () {
                                Navigator.pop(context, customer);
                              },
                            );
                          },
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((customer) {
      if (customer != null) {
        setState(() {
          _selectedCustomer = customer;
        });
      }
      _searchController.clear();
    });
  }

  Future<void> _submitPayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    setState(() {
      _isLoading = true;
    });

    try {
      final amount = double.parse(_amountController.text);
      final amountCents = (amount * 100).round();
      final customer = _selectedCustomer!;

      await sl<CustomerRepository>().recordTransaction(
        customerId: customer.id,
        transactionType: 'payment',
        amountCents: -amountCents,
        currencyId: customer.currencyId,
        description: _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
      );

      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('customers.payment_recorded'.tr()),
            backgroundColor: Colors.green,
          ),
        );
        router.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('common.error'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
