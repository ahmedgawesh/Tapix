import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/employee_entity.dart';
import 'employee_selector_dialog.dart';

class LeaveRequestDialog extends StatefulWidget {
  const LeaveRequestDialog({super.key});

  @override
  State<LeaveRequestDialog> createState() => _LeaveRequestDialogState();
}

class _LeaveRequestDialogState extends State<LeaveRequestDialog> {
  Employee? _selectedEmployee;
  LeaveType _selectedLeaveType = LeaveType.annual;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 1));
  final TextEditingController _reasonController = TextEditingController();

  int get _daysCount {
    return _endDate.difference(_startDate).inDays + 1;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('yyyy-MM-dd');

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 400,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'employees.request_leave'.tr(),
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),

              // Employee Selector
              _buildField(
                label: 'employees.select_employee'.tr(),
                child: InkWell(
                  onTap: _selectEmployee,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 16,
                      ),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                    ),
                    child: Text(
                      _selectedEmployee?.name ?? 'employees.tap_to_select'.tr(),
                      style: TextStyle(
                        color: _selectedEmployee != null
                            ? null
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Leave Type
              _buildField(
                label: 'employees.leave_type'.tr(),
                child: DropdownButtonFormField<LeaveType>(
                  initialValue: _selectedLeaveType,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 16,
                    ),
                  ),
                  items: LeaveType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(_getLeaveTypeLabel(type)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedLeaveType = value);
                    }
                  },
                ),
              ),

              const SizedBox(height: 16),

              // Date Range
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      label: 'employees.start_date'.tr(),
                      child: InkWell(
                        onTap: () => _selectDate(true),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          child: Text(dateFormat.format(_startDate)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildField(
                      label: 'employees.end_date'.tr(),
                      child: InkWell(
                        onTap: () => _selectDate(false),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 16,
                            ),
                          ),
                          child: Text(dateFormat.format(_endDate)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Reason
              _buildField(
                label: 'employees.reason'.tr(),
                child: TextField(
                  controller: _reasonController,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hintText: 'employees.reason'.tr(),
                  ),
                  maxLines: 3,
                ),
              ),

              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('common.cancel'.tr()),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _selectedEmployee != null ? _submit : null,
                    child: Text('common.submit'.tr()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Future<void> _selectEmployee() async {
    final employee = await showDialog<Employee>(
      context: context,
      builder: (context) => const EmployeeSelectorDialog(),
    );

    if (employee != null) {
      setState(() => _selectedEmployee = employee);
    }
  }

  Future<void> _selectDate(bool isStart) async {
    final initialDate = isStart ? _startDate : _endDate;
    final firstDate = isStart ? DateTime.now() : _startDate;

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null) {
      setState(() {
        if (isStart) {
          _startDate = date;
          if (_endDate.isBefore(_startDate)) {
            _endDate = _startDate;
          }
        } else {
          _endDate = date;
        }
      });
    }
  }

  void _submit() {
    if (_selectedEmployee == null) return;

    Navigator.of(context).pop({
      'employeeId': _selectedEmployee!.id,
      'leaveType': _selectedLeaveType,
      'startDate': _startDate,
      'endDate': _endDate,
      'daysCount': _daysCount,
      'reason': _reasonController.text.isNotEmpty
          ? _reasonController.text
          : null,
    });
  }

  String _getLeaveTypeLabel(LeaveType type) {
    switch (type) {
      case LeaveType.annual:
        return 'employees.leave_type_annual'.tr();
      case LeaveType.sick:
        return 'employees.leave_type_sick'.tr();
      case LeaveType.personal:
        return 'employees.leave_type_personal'.tr();
      case LeaveType.unpaid:
        return 'employees.leave_type_unpaid'.tr();
      case LeaveType.maternity:
        return 'employees.leave_type_maternity'.tr();
      case LeaveType.paternity:
        return 'employees.leave_type_paternity'.tr();
    }
  }
}
