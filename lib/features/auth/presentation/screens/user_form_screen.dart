import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/user_repository_interface.dart';
import '../bloc/user_form_bloc.dart';
import '../../../employees/domain/repositories/employee_repository.dart';
import '../../../employees/presentation/bloc/employees_bloc.dart';

class UserFormScreen extends StatelessWidget {
  final int? userId;

  const UserFormScreen({super.key, this.userId});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              UserFormBloc(sl<UserRepositoryInterface>())
                ..add(UserFormLoadRequested(userId: userId)),
        ),
        BlocProvider(
          create: (context) =>
              EmployeesBloc(sl<EmployeeRepository>())
                ..add(const EmployeesInitialized()),
        ),
      ],
      child: _UserFormContent(userId: userId),
    );
  }
}

class _UserFormContent extends StatefulWidget {
  final int? userId;

  const _UserFormContent({this.userId});

  @override
  State<_UserFormContent> createState() => _UserFormContentState();
}

class _UserFormContentState extends State<_UserFormContent> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _securityAnswerController = TextEditingController();

  UserRole _selectedRole = UserRole.salesperson;
  int? _selectedEmployeeId;
  String? _selectedEmployeeName;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isEdit = false;
  String? _selectedSecurityQuestion;
  String? _existingSecurityQuestion;

  List<String> get _securityQuestions => [
    'auth.security_questions.q1'.tr(),
    'auth.security_questions.q2'.tr(),
    'auth.security_questions.q3'.tr(),
    'auth.security_questions.q4'.tr(),
    'auth.security_questions.q5'.tr(),
    'auth.security_questions.q6'.tr(),
  ];

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _securityAnswerController.dispose();
    super.dispose();
  }

  String _roleDescription(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return 'users.role_owner_desc'.tr();
      case UserRole.manager:
        return 'users.role_manager_desc'.tr();
      case UserRole.accountant:
        return 'users.role_accountant_desc'.tr();
      case UserRole.cashier:
        return 'users.role_cashier_desc'.tr();
      case UserRole.salesperson:
        return 'users.role_salesperson_desc'.tr();
    }
  }

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return 'users.role_owner'.tr();
      case UserRole.manager:
        return 'users.role_manager'.tr();
      case UserRole.accountant:
        return 'users.role_accountant'.tr();
      case UserRole.cashier:
        return 'users.role_cashier'.tr();
      case UserRole.salesperson:
        return 'users.role_salesperson'.tr();
    }
  }

  IconData _roleIcon(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return Icons.workspace_premium_outlined;
      case UserRole.manager:
        return Icons.manage_accounts_outlined;
      case UserRole.accountant:
        return Icons.account_balance_outlined;
      case UserRole.cashier:
        return Icons.point_of_sale_outlined;
      case UserRole.salesperson:
        return Icons.storefront_outlined;
    }
  }

  Color _roleColor(UserRole role) {
    switch (role) {
      case UserRole.owner:
        return Colors.amber.shade700;
      case UserRole.manager:
        return Colors.blue;
      case UserRole.accountant:
        return Colors.indigo;
      case UserRole.cashier:
        return Colors.green;
      case UserRole.salesperson:
        return Colors.teal;
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    context.read<UserFormBloc>().add(
      UserFormSubmitRequested(
        userId: widget.userId,
        username: _usernameController.text,
        password: _passwordController.text,
        confirmPassword: _confirmPasswordController.text,
        role: _selectedRole,
        employeeId: _selectedEmployeeId,
        clearEmployeeLink: _selectedEmployeeId == null && _isEdit,
        securityQuestion: _selectedSecurityQuestion,
        securityAnswer: _securityAnswerController.text.trim().isNotEmpty
            ? _securityAnswerController.text.trim()
            : null,
      ),
    );
  }

  Future<void> _loadSelectedEmployeeName(int? employeeId) async {
    if (employeeId == null) return;
    final employee = await sl<EmployeeRepository>().getEmployee(employeeId);
    if (!mounted || _selectedEmployeeId != employeeId) return;
    setState(() => _selectedEmployeeName = employee?.name);
  }

  void _showEmployeeSelector() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return BlocProvider.value(
          value: context.read<EmployeesBloc>(),
          child: DraggableScrollableSheet(
            initialChildSize: 0.6,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) {
              return _EmployeeSelectorSheet(
                scrollController: scrollController,
                selectedEmployeeId: _selectedEmployeeId,
                onSelected: (employee) {
                  setState(() {
                    if (employee != null) {
                      _selectedEmployeeId = employee.id;
                      _selectedEmployeeName = employee.name;
                    } else {
                      _selectedEmployeeId = null;
                      _selectedEmployeeName = null;
                    }
                  });
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocConsumer<UserFormBloc, UserFormState>(
      listener: (context, state) {
        if (state is UserFormLoaded && state.existingUser != null) {
          final user = state.existingUser!;
          _usernameController.text = user.username;
          _selectedRole = user.role;
          _selectedEmployeeId = user.employeeId;
          _isEdit = true;
          _loadSelectedEmployeeName(user.employeeId);
          setState(() {});
        }
        if (state is UserFormSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('users.${state.message}'.tr())),
          );
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go('/users');
          }
        }
        if (state is UserFormError) {
          final errorKey = state.message;
          final localizedError = 'users.$errorKey'.tr();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                localizedError != 'users.$errorKey' ? localizedError : errorKey,
              ),
              backgroundColor: colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final isSubmitting = state is UserFormSubmitting;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.userId != null ? 'users.edit'.tr() : 'users.create'.tr(),
            ),
            centerTitle: true,
          ),
          body: state is UserFormLoading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Account Information Section
                              _SectionHeader(
                                icon: Icons.person_outline,
                                title: 'users.account_info'.tr(),
                                color: colorScheme.primary,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _usernameController,
                                decoration: InputDecoration(
                                  labelText: 'users.username'.tr(),
                                  hintText: 'users.username_hint'.tr(),
                                  prefixIcon: const Icon(Icons.alternate_email),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'users.username_required'.tr();
                                  }
                                  if (value.trim().length < 3) {
                                    return 'users.username_min_length'.tr();
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 24),

                              // Security Section
                              _SectionHeader(
                                icon: Icons.lock_outline,
                                title: 'users.security'.tr(),
                                color: colorScheme.primary,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                decoration: InputDecoration(
                                  labelText: _isEdit
                                      ? 'users.new_password'.tr()
                                      : 'users.password'.tr(),
                                  hintText: _isEdit
                                      ? 'users.new_password_hint'.tr()
                                      : 'users.password_hint'.tr(),
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  if (!_isEdit &&
                                      (value == null || value.isEmpty)) {
                                    return 'users.password_required'.tr();
                                  }
                                  if (value != null &&
                                      value.isNotEmpty &&
                                      value.length < 6) {
                                    return 'users.password_min_length'.tr();
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: _obscureConfirmPassword,
                                decoration: InputDecoration(
                                  labelText: 'users.confirm_password'.tr(),
                                  hintText: 'users.confirm_password_hint'.tr(),
                                  prefixIcon: const Icon(Icons.key_outlined),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirmPassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () => setState(
                                      () => _obscureConfirmPassword =
                                          !_obscureConfirmPassword,
                                    ),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                textInputAction: TextInputAction.done,
                                validator: (value) {
                                  if (_passwordController.text.isNotEmpty &&
                                      value != _passwordController.text) {
                                    return 'users.passwords_not_match'.tr();
                                  }
                                  return null;
                                },
                              ),
                              if (_isEdit) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'users.password_change_hint'.tr(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],

                              const SizedBox(height: 16),

                              // Security Question Section
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.shield_outlined,
                                      size: 20,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'auth.security_question_info'.tr(),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (_isEdit &&
                                  _existingSecurityQuestion != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 20,
                                        color: colorScheme.primary,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'users.security_question_set'.tr(),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: colorScheme.primary,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              DropdownButtonFormField<String>(
                                initialValue: _selectedSecurityQuestion,
                                decoration: InputDecoration(
                                  labelText: 'auth.security_question_label'
                                      .tr(),
                                  prefixIcon: const Icon(Icons.help_outline),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                isExpanded: true,
                                items: _securityQuestions
                                    .map(
                                      (q) => DropdownMenuItem(
                                        value: q,
                                        child: Text(
                                          q,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedSecurityQuestion = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _securityAnswerController,
                                decoration: InputDecoration(
                                  labelText: 'auth.security_answer_label'.tr(),
                                  hintText: 'auth.security_answer_hint'.tr(),
                                  prefixIcon: const Icon(
                                    Icons.message_outlined,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                textInputAction: TextInputAction.next,
                                validator: (value) {
                                  // Only validate if a question is selected
                                  if (_selectedSecurityQuestion != null &&
                                      (value == null || value.trim().isEmpty)) {
                                    return 'auth.security_answer_required'.tr();
                                  }
                                  if (value != null &&
                                      value.trim().isNotEmpty &&
                                      value.trim().length < 2) {
                                    return 'auth.security_answer_min_length'
                                        .tr();
                                  }
                                  return null;
                                },
                              ),
                              if (_isEdit) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'users.security_question_change_hint'.tr(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],

                              const SizedBox(height: 24),

                              // Role & Permissions Section
                              _SectionHeader(
                                icon: Icons.shield_outlined,
                                title: 'users.role_permissions'.tr(),
                                color: colorScheme.primary,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'users.select_role'.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: UserRole.values.map((role) {
                                  final isSelected = _selectedRole == role;
                                  final color = _roleColor(role);
                                  return ChoiceChip(
                                    avatar: Icon(
                                      _roleIcon(role),
                                      size: 18,
                                      color: isSelected
                                          ? color
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    label: Text(_roleLabel(role)),
                                    selected: isSelected,
                                    onSelected: (_) =>
                                        setState(() => _selectedRole = role),
                                    selectedColor: color.withValues(
                                      alpha: 0.15,
                                    ),
                                    checkmarkColor: color,
                                    labelStyle: TextStyle(
                                      color: isSelected
                                          ? color
                                          : colorScheme.onSurfaceVariant,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: isSelected
                                            ? color.withValues(alpha: 0.5)
                                            : colorScheme.outlineVariant,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),
                              // Role description
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 20,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _roleDescription(_selectedRole),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Link to Employee Section
                              _SectionHeader(
                                icon: Icons.link_outlined,
                                title: 'users.link_employee'.tr(),
                                color: colorScheme.primary,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                (_selectedRole == UserRole.cashier
                                        ? 'users.link_employee_cashier_required'
                                        : 'users.link_employee_desc')
                                    .tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'users.select_employee'.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: _showEmployeeSelector,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: colorScheme.outline,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person_outline,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _selectedEmployeeName ??
                                              'users.no_employee_link'.tr(),
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
                                                color:
                                                    _selectedEmployeeName !=
                                                        null
                                                    ? colorScheme.onSurface
                                                    : colorScheme
                                                          .onSurfaceVariant,
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 32),

                              // Submit Button
                              SizedBox(
                                height: 52,
                                child: FilledButton.icon(
                                  onPressed: isSubmitting ? null : _submit,
                                  icon: isSubmitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.person_add_outlined),
                                  label: Text(
                                    widget.userId != null
                                        ? 'users.edit'.tr()
                                        : 'users.create'.tr(),
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  style: FilledButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _EmployeeSelectorSheet extends StatelessWidget {
  final ScrollController scrollController;
  final int? selectedEmployeeId;
  final void Function(Employee?) onSelected;

  const _EmployeeSelectorSheet({
    required this.scrollController,
    required this.selectedEmployeeId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // Handle bar
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'users.select_employee'.tr(),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // No link option
        ListTile(
          leading: CircleAvatar(
            backgroundColor: colorScheme.surfaceContainerHighest,
            child: Icon(Icons.link_off, color: colorScheme.onSurfaceVariant),
          ),
          title: Text('users.no_employee_link'.tr()),
          selected: selectedEmployeeId == null,
          onTap: () => onSelected(null),
        ),
        const Divider(height: 1),
        // Employee list
        Expanded(
          child: BlocBuilder<EmployeesBloc, RealtimeState<List<Employee>>>(
            builder: (context, state) {
              if (state is RealtimeLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (state is RealtimeSuccess<List<Employee>>) {
                final employees = state.data;
                if (employees.isEmpty) {
                  return Center(child: Text('employees.no_employees'.tr()));
                }

                return ListView.builder(
                  controller: scrollController,
                  itemCount: employees.length,
                  itemBuilder: (context, index) {
                    final employee = employees[index];
                    final isSelected = employee.id == selectedEmployeeId;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSelected
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
                        child: Text(
                          _getInitials(employee.name),
                          style: TextStyle(
                            color: isSelected
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(employee.name),
                      subtitle: employee.position != null
                          ? Text(
                              employee.position!,
                              style: theme.textTheme.bodySmall,
                            )
                          : null,
                      selected: isSelected,
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: colorScheme.primary)
                          : null,
                      onTap: () => onSelected(employee),
                    );
                  },
                );
              }

              return const SizedBox.shrink();
            },
          ),
        ),
      ],
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }
}
