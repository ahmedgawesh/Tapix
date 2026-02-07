import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/repositories/customer_repository.dart';
import '../bloc/customer_form_bloc.dart';

/// Screen for creating or editing a customer
class CustomerFormScreen extends StatelessWidget {
  final int? customerId;

  const CustomerFormScreen({super.key, this.customerId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CustomerFormBloc(sl<CustomerRepository>())
        ..add(CustomerFormLoadRequested(customerId: customerId)),
      child: _CustomerFormContent(customerId: customerId),
    );
  }
}

class _CustomerFormContent extends StatefulWidget {
  final int? customerId;

  const _CustomerFormContent({this.customerId});

  @override
  State<_CustomerFormContent> createState() => _CustomerFormContentState();
}

class _CustomerFormContentState extends State<_CustomerFormContent> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _balanceController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.customerId != null;

    return BlocConsumer<CustomerFormBloc, CustomerFormState>(
      listener: (context, state) {
        if (state is CustomerFormSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.isNew
                    ? 'customers.created_success'.tr()
                    : 'customers.updated_success'.tr(),
              ),
              backgroundColor: Colors.green,
            ),
          );
          context.pop();
        } else if (state is CustomerFormError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        } else if (state is CustomerFormReady) {
          // Sync controllers with state
          if (_nameController.text != state.name) {
            _nameController.text = state.name;
          }
          if (_emailController.text != state.email) {
            _emailController.text = state.email;
          }
          if (_phoneController.text != state.phone) {
            _phoneController.text = state.phone;
          }
          if (_addressController.text != state.address) {
            _addressController.text = state.address;
          }
          if (_balanceController.text != state.balance) {
            _balanceController.text = state.balance;
          }
        }
      },
      builder: (context, state) {
        if (state is CustomerFormLoading) {
          return Scaffold(
            appBar: AppBar(
              title: Text(isEditing ? 'customers.edit'.tr() : 'customers.add'.tr()),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (state is! CustomerFormReady && state is! CustomerFormError) {
          return Scaffold(
            appBar: AppBar(
              title: Text(isEditing ? 'customers.edit'.tr() : 'customers.add'.tr()),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final formState = state is CustomerFormReady
            ? state
            : (state as CustomerFormError).previousState;

        return Scaffold(
          appBar: AppBar(
            title: Text(isEditing ? 'customers.edit'.tr() : 'customers.add'.tr()),
            actions: [
              if (formState.isSubmitting)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                TextButton(
                  onPressed: formState.isValid
                      ? () => context.read<CustomerFormBloc>().add(
                            const CustomerFormSubmitted(),
                          )
                      : null,
                  child: Text(
                    isEditing ? 'customers.update'.tr() : 'customers.create'.tr(),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Basic Information Section
                  _SectionHeader(title: 'customers.basic_info'.tr()),
                  const SizedBox(height: 8),
                  
                  // Name Field
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'customers.name'.tr(),
                      hintText: 'customers.name_hint'.tr(),
                      prefixIcon: Icon(Icons.person_outline, color: theme.colorScheme.primary),
                      errorText: formState.errors['name']?.tr(),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: (value) => context.read<CustomerFormBloc>().add(
                          CustomerFormNameChanged(value),
                        ),
                  ),
                  const SizedBox(height: 16),

                  // Segment Dropdown
                  DropdownButtonFormField<String>(
                    initialValue: formState.segment,
                    decoration: InputDecoration(
                      labelText: 'customers.segment'.tr(),
                      hintText: 'customers.segment_hint'.tr(),
                      prefixIcon: Icon(Icons.category_outlined, color: theme.colorScheme.primary),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'retail',
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline, size: 20),
                            const SizedBox(width: 8),
                            Text('customers.segment_retail'.tr()),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'wholesale',
                        child: Row(
                          children: [
                            const Icon(Icons.business_outlined, size: 20),
                            const SizedBox(width: 8),
                            Text('customers.segment_wholesale'.tr()),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'premium',
                        child: Row(
                          children: [
                            const Icon(Icons.star_outline, size: 20),
                            const SizedBox(width: 8),
                            Text('customers.segment_premium'.tr()),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        context.read<CustomerFormBloc>().add(
                              CustomerFormSegmentChanged(value),
                            );
                      }
                    },
                  ),
                  const SizedBox(height: 24),

                  // Contact Information Section
                  _SectionHeader(title: 'customers.contact_info'.tr()),
                  const SizedBox(height: 8),

                  // Email Field
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'customers.email'.tr(),
                      hintText: 'customers.email_hint'.tr(),
                      prefixIcon: Icon(Icons.email_outlined, color: theme.colorScheme.primary),
                      errorText: formState.errors['email']?.tr(),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onChanged: (value) => context.read<CustomerFormBloc>().add(
                          CustomerFormEmailChanged(value),
                        ),
                  ),
                  const SizedBox(height: 16),

                  // Phone Field
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: 'customers.phone'.tr(),
                      hintText: 'customers.phone_hint'.tr(),
                      prefixIcon: Icon(Icons.phone_outlined, color: theme.colorScheme.primary),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    onChanged: (value) => context.read<CustomerFormBloc>().add(
                          CustomerFormPhoneChanged(value),
                        ),
                  ),
                  const SizedBox(height: 16),

                  // Address Field
                  TextFormField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: 'customers.address'.tr(),
                      hintText: 'customers.address_hint'.tr(),
                      prefixIcon: Icon(Icons.location_on_outlined, color: theme.colorScheme.primary),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 2,
                    textInputAction: TextInputAction.next,
                    onChanged: (value) => context.read<CustomerFormBloc>().add(
                          CustomerFormAddressChanged(value),
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Financial Information Section
                  _SectionHeader(title: 'customers.financial_info'.tr()),
                  const SizedBox(height: 8),

                  // Opening Balance Field
                  TextFormField(
                    controller: _balanceController,
                    readOnly: false,
                    decoration: InputDecoration(
                      labelText: isEditing
                          ? 'customers.current_balance'.tr()
                          : 'customers.opening_balance'.tr(),
                      hintText: isEditing ? null : 'customers.opening_balance_hint'.tr(),
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined, color: theme.colorScheme.primary),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      helperText: isEditing
                          ? 'customers.balance_edit_helper'.tr()
                          : 'customers.opening_balance_helper'.tr(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    onChanged: (value) => context.read<CustomerFormBloc>().add(
                          CustomerFormBalanceChanged(value),
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Loyalty Program Section
                  _SectionHeader(title: 'customers.loyalty'.tr()),
                  const SizedBox(height: 8),

                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: SwitchListTile(
                      value: formState.loyaltyEnabled,
                      onChanged: (value) => context.read<CustomerFormBloc>().add(
                            CustomerFormLoyaltyEnabledChanged(value),
                          ),
                      title: Text('customers.loyalty_toggle'.tr()),
                      subtitle: Text(
                        formState.loyaltyEnabled
                            ? 'customers.loyalty_enabled'.tr()
                            : 'customers.loyalty_disabled'.tr(),
                      ),
                      secondary: Icon(
                        formState.loyaltyEnabled
                            ? Icons.card_giftcard
                            : Icons.card_giftcard_outlined,
                        color: formState.loyaltyEnabled
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
