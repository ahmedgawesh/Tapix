import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../bloc/supplier_form_bloc.dart';

/// Screen for creating or editing a supplier
class SupplierFormScreen extends StatelessWidget {
  final int? supplierId;

  const SupplierFormScreen({super.key, this.supplierId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SupplierFormBloc(sl<SupplierRepository>())
        ..add(SupplierFormLoadRequested(supplierId: supplierId)),
      child: _SupplierFormContent(supplierId: supplierId),
    );
  }
}

class _SupplierFormContent extends StatefulWidget {
  final int? supplierId;

  const _SupplierFormContent({this.supplierId});

  @override
  State<_SupplierFormContent> createState() => _SupplierFormContentState();
}

class _SupplierFormContentState extends State<_SupplierFormContent> {
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
    final isEditing = widget.supplierId != null;

    return BlocConsumer<SupplierFormBloc, SupplierFormState>(
      listener: (context, state) {
        if (state is SupplierFormSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                state.isNew
                    ? 'suppliers.created_success'.tr()
                    : 'suppliers.updated_success'.tr(),
              ),
              backgroundColor: Colors.green,
            ),
          );
          context.pop();
        } else if (state is SupplierFormError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        } else if (state is SupplierFormReady) {
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
        if (state is SupplierFormLoading) {
          return Scaffold(
            appBar: AppBar(
              title: Text(isEditing ? 'suppliers.edit'.tr() : 'suppliers.add'.tr()),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (state is! SupplierFormReady && state is! SupplierFormError) {
          return Scaffold(
            appBar: AppBar(
              title: Text(isEditing ? 'suppliers.edit'.tr() : 'suppliers.add'.tr()),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final formState = state is SupplierFormReady
            ? state
            : (state as SupplierFormError).previousState;

        return Scaffold(
          appBar: AppBar(
            title: Text(isEditing ? 'suppliers.edit'.tr() : 'suppliers.add'.tr()),
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
                      ? () => context.read<SupplierFormBloc>().add(
                            const SupplierFormSubmitted(),
                          )
                      : null,
                  child: Text(
                    isEditing ? 'suppliers.update'.tr() : 'suppliers.create'.tr(),
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
                  _SectionHeader(title: 'suppliers.basic_info'.tr()),
                  const SizedBox(height: 8),

                  // Name Field
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'suppliers.name'.tr(),
                      hintText: 'suppliers.name_hint'.tr(),
                      prefixIcon: Icon(LucideIcons.building2, color: theme.colorScheme.primary),
                      errorText: formState.errors['name']?.tr(),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: (value) => context.read<SupplierFormBloc>().add(
                          SupplierFormNameChanged(value),
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Contact Information Section
                  _SectionHeader(title: 'suppliers.contact_info'.tr()),
                  const SizedBox(height: 8),

                  // Email Field
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'suppliers.email'.tr(),
                      hintText: 'suppliers.email_hint'.tr(),
                      prefixIcon: Icon(LucideIcons.mail, color: theme.colorScheme.primary),
                      errorText: formState.errors['email']?.tr(),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    onChanged: (value) => context.read<SupplierFormBloc>().add(
                          SupplierFormEmailChanged(value),
                        ),
                  ),
                  const SizedBox(height: 16),

                  // Phone Field
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: 'suppliers.phone'.tr(),
                      hintText: 'suppliers.phone_hint'.tr(),
                      prefixIcon: Icon(LucideIcons.phone, color: theme.colorScheme.primary),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    onChanged: (value) => context.read<SupplierFormBloc>().add(
                          SupplierFormPhoneChanged(value),
                        ),
                  ),
                  const SizedBox(height: 16),

                  // Address Field
                  TextFormField(
                    controller: _addressController,
                    decoration: InputDecoration(
                      labelText: 'suppliers.address'.tr(),
                      hintText: 'suppliers.address_hint'.tr(),
                      prefixIcon: Icon(LucideIcons.mapPin, color: theme.colorScheme.primary),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    maxLines: 2,
                    textInputAction: TextInputAction.next,
                    onChanged: (value) => context.read<SupplierFormBloc>().add(
                          SupplierFormAddressChanged(value),
                        ),
                  ),
                  const SizedBox(height: 24),

                  // Financial Information Section
                  _SectionHeader(title: 'suppliers.financial_info'.tr()),
                  const SizedBox(height: 8),

                  // Opening Balance Field
                  TextFormField(
                    controller: _balanceController,
                    decoration: InputDecoration(
                      labelText: isEditing
                          ? 'suppliers.current_balance'.tr()
                          : 'suppliers.opening_balance'.tr(),
                      hintText: 'suppliers.opening_balance_hint'.tr(),
                      prefixIcon: Icon(LucideIcons.wallet, color: theme.colorScheme.primary),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      helperText: 'suppliers.opening_balance_helper'.tr(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    onTap: () => selectAllText(_balanceController),
                    onChanged: (value) => context.read<SupplierFormBloc>().add(
                          SupplierFormBalanceChanged(value),
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
