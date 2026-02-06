import 'dart:ui' as ui;
import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide Size;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/repositories/employee_repository.dart';
import '../bloc/roles_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';

enum CommissionType { percentage, fixed }
enum TargetPeriod { monthly, quarterly, yearly }

class EmployeeFormScreen extends StatefulWidget {
  final int? employeeId;

  const EmployeeFormScreen({super.key, this.employeeId});

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repository = sl<EmployeeRepository>();

  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _positionController = TextEditingController();
  final _departmentController = TextEditingController();
  final _employeeCodeController = TextEditingController();
  final _salaryController = TextEditingController();
  final _commissionValueController = TextEditingController();
  final _targetAmountController = TextEditingController();
  final _targetBonusController = TextEditingController();
  final _notesController = TextEditingController();
  final _workingDaysController = TextEditingController(text: '26');
  final _workingHoursController = TextEditingController(text: '8');
  final _absenceRateController = TextEditingController(text: '100');
  final _lateRateController = TextEditingController(text: '25');

  // State
  bool _isLoading = false;
  bool _isEditing = false;
  Employee? _employee;
  int? _selectedRoleId;
  int? _selectedManagerId;
  CommissionType _commissionType = CommissionType.percentage;
  TargetPeriod _targetPeriod = TargetPeriod.monthly;
  String _payPeriodType = 'monthly';
  List<Employee> _managers = [];

  @override
  void initState() {
    super.initState();
    _isEditing = widget.employeeId != null;
    _loadData();
  }

  String _localizedRoleName(BuildContext context, Role role) {
    final lang = context.locale.languageCode;
    final byLocale = switch (lang) {
      'ar' => role.nameAr,
      'fr' => role.nameFr,
      _ => null,
    };
    final trimmed = byLocale?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }

    final key = 'roles.${role.name}'.toLowerCase();
    final translated = key.tr();
    return translated == key ? role.name : translated;
  }

  Future<int> _getCurrentCurrencyId() async {
    final db = sl<AppDatabase>();
    final currencyCode = sl<CurrencyService>().currencyCode;
    final row = await (db.select(db.currencies)
          ..where((c) => c.code.equals(currencyCode)))
        .getSingleOrNull();
    if (row != null) {
      return row.id;
    }

    final usd = await (db.select(db.currencies)..where((c) => c.code.equals('USD')))
        .getSingleOrNull();
    return usd?.id ?? 1;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Load managers
    final employees = await _repository.searchEmployees('');
    _managers = employees.where((e) => e.id != widget.employeeId).toList();

    // Generate employee code for new employees
    if (!_isEditing) {
      final code = await _repository.generateEmployeeCode();
      _employeeCodeController.text = code;
    }

    // Load existing employee data if editing
    if (_isEditing) {
      _employee = await _repository.getEmployee(widget.employeeId!);
      if (_employee != null) {
        _populateForm(_employee!);
      }
    }

    setState(() => _isLoading = false);
  }

  void _populateForm(Employee employee) {
    _nameController.text = employee.name;
    _emailController.text = employee.email ?? '';
    _phoneController.text = employee.phone ?? '';
    _positionController.text = employee.position ?? '';
    _departmentController.text = employee.department ?? '';
    _employeeCodeController.text = employee.employeeCode ?? '';
    _selectedRoleId = employee.roleId;
    _selectedManagerId = employee.managerId;

    if (employee.salaryCents != null) {
      final salaryAmount = employee.salaryCents!.toDouble() / 100;
      _salaryController.text = salaryAmount.toStringAsFixed(2);
    }

    if (employee.defaultCommissionRateBps > 0) {
      _commissionType = CommissionType.percentage;
      final rate = employee.defaultCommissionRateBps / 100;
      _commissionValueController.text = rate.toStringAsFixed(2);
    }

    _payPeriodType = employee.payPeriodType;
    _workingDaysController.text = employee.workingDaysPerPeriod.toString();
    _workingHoursController.text = employee.workingHoursPerDay.toString();
    _absenceRateController.text = (employee.absenceDeductionRateBps / 100).toStringAsFixed(0);
    _lateRateController.text = (employee.lateDeductionRateBps / 100).toStringAsFixed(0);

    _notesController.text = employee.notes ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _positionController.dispose();
    _departmentController.dispose();
    _employeeCodeController.dispose();
    _salaryController.dispose();
    _commissionValueController.dispose();
    _targetAmountController.dispose();
    _targetBonusController.dispose();
    _notesController.dispose();
    _workingDaysController.dispose();
    _workingHoursController.dispose();
    _absenceRateController.dispose();
    _lateRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => RolesBloc(_repository)..add(const RolesInitialized()),
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: Text(
            _isEditing ? 'employees.edit'.tr() : 'employees.create'.tr(),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Basic Info Section
                    _buildSectionHeader(
                      context,
                      icon: Icons.person_outline,
                      title: 'employees.basic_info'.tr(),
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _nameController,
                      label: 'employees.name'.tr(),
                      hint: 'employees.name_hint'.tr(),
                      prefixIcon: Icons.person_outline,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'employees.name_required'.tr();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _emailController,
                      label: 'employees.email'.tr(),
                      hint: 'employees.email_hint'.tr(),
                      prefixIcon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _phoneController,
                      label: 'employees.phone'.tr(),
                      hint: 'employees.phone_hint'.tr(),
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _positionController,
                      label: 'employees.position'.tr(),
                      hint: 'employees.position_hint'.tr(),
                      prefixIcon: Icons.work_outline,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _departmentController,
                      label: 'employees.department'.tr(),
                      hint: 'employees.department_hint'.tr(),
                      prefixIcon: Icons.business_outlined,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _employeeCodeController,
                      label: 'employees.employee_code'.tr(),
                      hint: 'employees.employee_code_hint'.tr(),
                      prefixIcon: Icons.tag,
                    ),

                    const SizedBox(height: 24),

                    // Role Section
                    _buildSectionHeader(
                      context,
                      icon: Icons.badge_outlined,
                      title: 'employees.role'.tr(),
                    ),
                    const SizedBox(height: 12),
                    BlocBuilder<RolesBloc, RealtimeState<List<Role>>>(
                      builder: (context, state) {
                        final roles = state is RealtimeSuccess<List<Role>>
                            ? state.data
                            : <Role>[];
                        return _buildDropdown<int>(
                          value: _selectedRoleId,
                          hint: 'employees.role_hint'.tr(),
                          prefixIcon: Icons.badge_outlined,
                          items: roles.map((role) {
                            return DropdownMenuItem(
                              value: role.id,
                              child: Text(_localizedRoleName(context, role)),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setState(() => _selectedRoleId = value);
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Manager Section
                    _buildSectionHeader(
                      context,
                      icon: Icons.supervisor_account_outlined,
                      title: 'employees.manager'.tr(),
                    ),
                    const SizedBox(height: 12),
                    _buildDropdown<int>(
                      value: _selectedManagerId,
                      hint: 'employees.manager_hint'.tr(),
                      prefixIcon: Icons.supervisor_account_outlined,
                      items: [
                        DropdownMenuItem<int>(
                          value: null,
                          child: Text('common.none'.tr()),
                        ),
                        ..._managers.map((manager) {
                          return DropdownMenuItem(
                            value: manager.id,
                            child: Text(manager.name),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() => _selectedManagerId = value);
                      },
                    ),

                    const SizedBox(height: 24),

                    // Salary Section
                    _buildSectionHeader(
                      context,
                      icon: Icons.payments_outlined,
                      title: 'employees.salary'.tr(),
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _salaryController,
                      label: 'employees.salary'.tr(),
                      prefixIcon: Icons.attach_money,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Commission Section
                    _buildSectionHeader(
                      context,
                      icon: Icons.percent,
                      title: 'employees.commission_type'.tr(),
                    ),
                    const SizedBox(height: 12),
                    _buildCommissionTypeSelector(colorScheme),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _commissionValueController,
                      label: 'employees.commission_value'.tr(),
                      prefixIcon: _commissionType == CommissionType.percentage
                          ? Icons.percent
                          : Icons.attach_money,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Sales Target Section
                    _buildSectionHeader(
                      context,
                      icon: Icons.track_changes,
                      title: 'employees.sales_target'.tr(),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'employees.target_period'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildTargetPeriodSelector(colorScheme),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _targetAmountController,
                            label: 'employees.target_amount'.tr(),
                            prefixIcon: Icons.track_changes,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildTextField(
                                controller: _targetBonusController,
                                label: 'employees.target_bonus'.tr(),
                                prefixIcon: Icons.card_giftcard,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'employees.target_bonus_hint'.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Work Schedule & Deductions Section
                    _buildSectionHeader(
                      context,
                      icon: Icons.schedule_outlined,
                      title: 'employees.work_schedule'.tr(),
                    ),
                    const SizedBox(height: 12),
                    // Pay Period Type
                    Text(
                      'employees.pay_period_type'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildPayPeriodSelector(colorScheme),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _workingDaysController,
                            label: 'employees.working_days'.tr(),
                            prefixIcon: Icons.calendar_view_day_outlined,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _workingHoursController,
                            label: 'employees.working_hours'.tr(),
                            prefixIcon: Icons.access_time_outlined,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionHeader(
                      context,
                      icon: Icons.remove_circle_outline,
                      title: 'employees.deduction_rates'.tr(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _absenceRateController,
                            label: 'employees.absence_rate'.tr(),
                            prefixIcon: Icons.person_off_outlined,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            hint: '100%',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildTextField(
                            controller: _lateRateController,
                            label: 'employees.late_rate'.tr(),
                            prefixIcon: Icons.timer_off_outlined,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            hint: '25%',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'employees.deduction_rates_hint'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Notes Section
                    _buildSectionHeader(
                      context,
                      icon: Icons.notes_outlined,
                      title: 'employees.notes'.tr(),
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(
                      controller: _notesController,
                      label: 'employees.notes'.tr(),
                      prefixIcon: Icons.notes_outlined,
                      maxLines: 3,
                    ),

                    const SizedBox(height: 32),

                    // Submit Button
                    FilledButton.icon(
                      onPressed: _isLoading ? null : _saveEmployee,
                      icon: const Icon(Icons.person_add_outlined),
                      label: Text(
                        _isEditing
                            ? 'employees.update'.tr()
                            : 'employees.create'.tr(),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const ui.Size(double.infinity, 56),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, color: colorScheme.primary, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? prefixIcon,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T? value,
    required String hint,
    required IconData prefixIcon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      hint: Text(hint),
      decoration: InputDecoration(
        prefixIcon: Icon(prefixIcon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildCommissionTypeSelector(ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
          child: _buildToggleButton(
            label: 'employees.commission_percentage'.tr(),
            icon: Icons.percent,
            isSelected: _commissionType == CommissionType.percentage,
            onTap: () => setState(() => _commissionType = CommissionType.percentage),
            colorScheme: colorScheme,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildToggleButton(
            label: 'employees.commission_fixed'.tr(),
            icon: Icons.attach_money,
            isSelected: _commissionType == CommissionType.fixed,
            onTap: () => setState(() => _commissionType = CommissionType.fixed),
            colorScheme: colorScheme,
          ),
        ),
      ],
    );
  }

  Widget _buildPayPeriodSelector(ColorScheme colorScheme) {
    return Row(
      children: [
        _buildPeriodChip(
          label: 'employees.period_monthly'.tr(),
          isSelected: _payPeriodType == 'monthly',
          onTap: () {
            setState(() {
              _payPeriodType = 'monthly';
              _workingDaysController.text = '26';
            });
          },
          colorScheme: colorScheme,
        ),
        const SizedBox(width: 8),
        _buildPeriodChip(
          label: 'employees.period_weekly'.tr(),
          isSelected: _payPeriodType == 'weekly',
          onTap: () {
            setState(() {
              _payPeriodType = 'weekly';
              _workingDaysController.text = '6';
            });
          },
          colorScheme: colorScheme,
        ),
        const SizedBox(width: 8),
        _buildPeriodChip(
          label: 'employees.period_daily'.tr(),
          isSelected: _payPeriodType == 'daily',
          onTap: () {
            setState(() {
              _payPeriodType = 'daily';
              _workingDaysController.text = '1';
            });
          },
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildTargetPeriodSelector(ColorScheme colorScheme) {
    return Row(
      children: [
        _buildPeriodChip(
          label: 'employees.target_monthly'.tr(),
          isSelected: _targetPeriod == TargetPeriod.monthly,
          onTap: () => setState(() => _targetPeriod = TargetPeriod.monthly),
          colorScheme: colorScheme,
        ),
        const SizedBox(width: 8),
        _buildPeriodChip(
          label: 'employees.target_quarterly'.tr(),
          isSelected: _targetPeriod == TargetPeriod.quarterly,
          onTap: () => setState(() => _targetPeriod = TargetPeriod.quarterly),
          colorScheme: colorScheme,
        ),
        const SizedBox(width: 8),
        _buildPeriodChip(
          label: 'employees.target_yearly'.tr(),
          isSelected: _targetPeriod == TargetPeriod.yearly,
          onTap: () => setState(() => _targetPeriod = TargetPeriod.yearly),
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildToggleButton({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outline,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.check,
                  size: 16,
                  color: colorScheme.primary,
                ),
              ),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Parse salary to cents
      int? salaryCents;
      if (_salaryController.text.isNotEmpty) {
        final salary = double.tryParse(_salaryController.text) ?? 0;
        salaryCents = (salary * 100).round();
      }

      // Parse commission rate to basis points
      int commissionRateBps = 0;
      if (_commissionValueController.text.isNotEmpty) {
        final value = double.tryParse(_commissionValueController.text) ?? 0;
        if (_commissionType == CommissionType.percentage) {
          commissionRateBps = (value * 100).round(); // Convert percentage to basis points
        }
      }

      final workingDays = int.tryParse(_workingDaysController.text) ?? 26;
      final workingHours = int.tryParse(_workingHoursController.text) ?? 8;
      final absenceRate = (int.tryParse(_absenceRateController.text) ?? 100) * 100;
      final lateRate = (int.tryParse(_lateRateController.text) ?? 25) * 100;

      if (_isEditing && _employee != null) {
        // Update existing employee
        final updatedEmployee = Employee(
          id: _employee!.id,
          name: _nameController.text,
          nameAr: _employee!.nameAr,
          nameFr: _employee!.nameFr,
          employeeCode: _employeeCodeController.text.isEmpty ? null : _employeeCodeController.text,
          userId: _employee!.userId,
          email: _emailController.text.isEmpty ? null : _emailController.text,
          phone: _phoneController.text.isEmpty ? null : _phoneController.text,
          position: _positionController.text.isEmpty ? null : _positionController.text,
          department: _departmentController.text.isEmpty ? null : _departmentController.text,
          roleId: _selectedRoleId,
          managerId: _selectedManagerId,
          salaryCents: salaryCents != null ? Decimal.fromInt(salaryCents) : null,
          defaultCommissionRateBps: commissionRateBps,
          payPeriodType: _payPeriodType,
          workingDaysPerPeriod: workingDays,
          workingHoursPerDay: workingHours,
          absenceDeductionRateBps: absenceRate,
          lateDeductionRateBps: lateRate,
          currencyId: _employee!.currencyId,
          isActive: _employee!.isActive,
          hireDate: _employee!.hireDate,
          terminationDate: _employee!.terminationDate,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
          createdAt: _employee!.createdAt,
          updatedAt: DateTime.now(),
        );

        await _repository.updateEmployee(updatedEmployee);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('employees.updated_success'.tr())),
          );
          context.pop();
        }
      } else {
        // Create new employee
        await _repository.createEmployee(
          name: _nameController.text,
          employeeCode: _employeeCodeController.text.isEmpty ? null : _employeeCodeController.text,
          email: _emailController.text.isEmpty ? null : _emailController.text,
          phone: _phoneController.text.isEmpty ? null : _phoneController.text,
          position: _positionController.text.isEmpty ? null : _positionController.text,
          department: _departmentController.text.isEmpty ? null : _departmentController.text,
          roleId: _selectedRoleId,
          managerId: _selectedManagerId,
          salaryCents: salaryCents,
          defaultCommissionRateBps: commissionRateBps,
          payPeriodType: _payPeriodType,
          workingDaysPerPeriod: workingDays,
          workingHoursPerDay: workingHours,
          absenceDeductionRateBps: absenceRate,
          lateDeductionRateBps: lateRate,
          currencyId: await _getCurrentCurrencyId(),
          notes: _notesController.text.isEmpty ? null : _notesController.text,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('employees.created_success'.tr())),
          );
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
