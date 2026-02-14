import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/attendance_service.dart';
import '../../domain/repositories/employee_repository.dart';
import '../bloc/attendance_bloc.dart';
import '../bloc/employees_bloc.dart';
import '../widgets/attendance_status_cards.dart';
import '../widgets/employee_selector_dialog.dart';

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => AttendanceBloc(sl<EmployeeRepository>(), sl<AttendanceService>())
            ..add(AttendanceInitialized(DateTime.now())),
        ),
        BlocProvider(
          create: (context) => EmployeesBloc(sl<EmployeeRepository>())
            ..add(const EmployeesInitialized()),
        ),
      ],
      child: const _AttendanceScreenContent(),
    );
  }
}

class _AttendanceScreenContent extends StatefulWidget {
  const _AttendanceScreenContent();

  @override
  State<_AttendanceScreenContent> createState() => _AttendanceScreenContentState();
}

class _AttendanceScreenContentState extends State<_AttendanceScreenContent> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('employees.attendance'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => _selectDate(context),
            tooltip: 'employees.select_date'.tr(),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<AttendanceBloc, AttendanceState>(
          builder: (context, state) {
            return Column(
              children: [
                // Date Navigation
                _DateNavigator(
                  selectedDate: state.selectedDate,
                  onDateChanged: (date) {
                    context.read<AttendanceBloc>().add(AttendanceDateChanged(date));
                  },
                ),

                // Status Summary Cards
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: AttendanceStatusCards(summary: state.summary),
                ),

                // Attendance List
                Expanded(
                  child: state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : state.attendances.isEmpty
                          ? _EmptyState()
                          : _AttendanceList(
                              attendances: state.attendances,
                              employeeNames: state.employeeNames,
                            ),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: _AttendanceFAB(
        onCheckIn: () => _showCheckInDialog(context),
        onCheckOut: () => _showCheckOutDialog(context),
        onMarkLate: () => _showMarkLateDialog(context),
        onMarkAbsent: () => _showMarkAbsentDialog(context),
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final bloc = context.read<AttendanceBloc>();
    final currentDate = bloc.state.selectedDate;

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selectedDate != null) {
      bloc.add(AttendanceDateChanged(selectedDate));
    }
  }

  Future<void> _showCheckInDialog(BuildContext context) async {
    final result = await _promptAttendanceAction(_AttendanceAction.checkIn);

    if (result != null && context.mounted) {
      context.read<AttendanceBloc>().add(AttendanceDateChanged(result.date));
      context.read<AttendanceBloc>().add(
            AttendanceCheckInRequested(
              employeeId: result.employeeId,
              checkInMethod: 'manual',
              checkInTime: result.dateTime,
            ),
          );
    }
  }

  Future<void> _showMarkLateDialog(BuildContext context) async {
    final result = await _promptAttendanceAction(_AttendanceAction.late);

    if (result != null && context.mounted) {
      context.read<AttendanceBloc>().add(AttendanceDateChanged(result.date));
      context.read<AttendanceBloc>().add(
            AttendanceMarkLateRequested(
              employeeId: result.employeeId,
              notes: result.notes,
              checkInTime: result.dateTime,
            ),
          );
    }
  }

  Future<void> _showMarkAbsentDialog(BuildContext context) async {
    final result = await _promptAttendanceAction(_AttendanceAction.absent);

    if (result != null && context.mounted) {
      context.read<AttendanceBloc>().add(AttendanceDateChanged(result.date));
      context.read<AttendanceBloc>().add(
            AttendanceMarkAbsentRequested(
              employeeId: result.employeeId,
              notes: result.notes,
            ),
          );
    }
  }

  Future<void> _showCheckOutDialog(BuildContext context) async {
    final bloc = context.read<AttendanceBloc>();
    final checkedInAttendances = bloc.state.attendances.where((a) {
      return a.checkInTime != null &&
          a.checkOutTime == null &&
          (a.status == 'present' || a.status == 'late');
    }).toList();

    if (checkedInAttendances.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('employees.no_checked_in_employees'.tr()),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final result = await showDialog<_CheckOutResult>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) => _CheckOutSelectorDialog(
        attendances: checkedInAttendances,
        employeeNames: bloc.state.employeeNames,
      ),
    );

    if (result != null && context.mounted) {
      // Build the check-out DateTime from the selected date + time
      final selectedDate = bloc.state.selectedDate;
      DateTime? checkOutTime;
      if (result.checkOutTime != null) {
        checkOutTime = DateTime(
          selectedDate.year,
          selectedDate.month,
          selectedDate.day,
          result.checkOutTime!.hour,
          result.checkOutTime!.minute,
        );
      }
      bloc.add(AttendanceCheckOutRequested(
        employeeId: result.attendance.employeeId,
        checkOutTime: checkOutTime,
      ));
    }
  }

  Future<_AttendanceActionResult?> _promptAttendanceAction(_AttendanceAction action) async {
    final employee = await showDialog<Employee>(
      context: context,
      useRootNavigator: true,
      builder: (context) => const EmployeeSelectorDialog(),
    );
    if (!mounted || employee == null) {
      return null;
    }

    return showDialog<_AttendanceActionResult>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _AttendanceActionDialog(
        action: action,
        initialEmployee: employee,
      ),
    );
  }
}

enum _AttendanceAction { checkIn, late, absent }

class _AttendanceActionResult {
  final int employeeId;
  final DateTime date;
  final String? notes;
  final TimeOfDay? time;

  const _AttendanceActionResult({
    required this.employeeId,
    required this.date,
    this.notes,
    this.time,
  });

  /// Combine date + time into a single DateTime for check-in/check-out
  DateTime? get dateTime {
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time!.hour, time!.minute);
  }
}

class _AttendanceActionDialog extends StatefulWidget {
  final _AttendanceAction action;
  final Employee initialEmployee;

  const _AttendanceActionDialog({required this.action, required this.initialEmployee});

  @override
  State<_AttendanceActionDialog> createState() => _AttendanceActionDialogState();
}

class _AttendanceActionDialogState extends State<_AttendanceActionDialog> {
  final _formKey = GlobalKey<FormState>();
  late Employee _selectedEmployee;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay? _selectedTime;
  final _notesController = TextEditingController();

  /// Whether this action needs a time picker (check-in and late need it, absent does not)
  bool get _needsTime => widget.action != _AttendanceAction.absent;

  @override
  void initState() {
    super.initState();
    _selectedEmployee = widget.initialEmployee;
    if (_needsTime) {
      _selectedTime = TimeOfDay.now();
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _titleKey() {
    switch (widget.action) {
      case _AttendanceAction.checkIn:
        return 'employees.check_in';
      case _AttendanceAction.late:
        return 'employees.mark_late';
      case _AttendanceAction.absent:
        return 'employees.mark_absent';
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _openEmployeeSelector() async {
    final employee = await showDialog<Employee>(
      context: context,
      useRootNavigator: true,
      builder: (context) => const EmployeeSelectorDialog(),
    );
    if (employee != null && mounted) {
      setState(() => _selectedEmployee = employee);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd', context.locale.toString());

    return AlertDialog(
      title: Text(_titleKey().tr()),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Employee
              InkWell(
                onTap: () async {
                  await _openEmployeeSelector();
                },
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'employees.select_employee'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedEmployee.name,
                        ),
                      ),
                      const Icon(Icons.expand_more),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Date
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'employees.select_date'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.calendar_month_outlined),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(dateFormat.format(_selectedDate)),
                  ),
                ),
              ),

              // Time picker (for check-in and late only)
              if (_needsTime) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickTime,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'employees.select_time'.tr(),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.access_time_outlined),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _selectedTime != null
                            ? _selectedTime!.format(context)
                            : 'employees.select_time'.tr(),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Notes
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'common.notes'.tr(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _AttendanceActionResult(
                employeeId: _selectedEmployee.id,
                date: DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day),
                notes: _notesController.text.isEmpty ? null : _notesController.text,
                time: _selectedTime,
              ),
            );
          },
          child: Text('common.submit'.tr()),
        ),
      ],
    );
  }
}

class _DateNavigator extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  const _DateNavigator({
    required this.selectedDate,
    required this.onDateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('EEEE, MMM d, yyyy', context.locale.toString());

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              onDateChanged(selectedDate.subtract(const Duration(days: 1)));
            },
          ),
          InkWell(
            onTap: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                onDateChanged(date);
              }
            },
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  dateFormat.format(selectedDate),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              onDateChanged(selectedDate.add(const Duration(days: 1)));
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'employees.no_attendance_records'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'employees.no_attendance_hint'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AttendanceList extends StatelessWidget {
  final List<Attendance> attendances;
  final Map<int, String> employeeNames;

  const _AttendanceList({required this.attendances, required this.employeeNames});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: attendances.length,
      itemBuilder: (context, index) {
        final attendance = attendances[index];
        return _AttendanceCard(
          attendance: attendance,
          employeeName: employeeNames[attendance.employeeId],
        );
      },
    );
  }
}

class _AttendanceCard extends StatelessWidget {
  final Attendance attendance;
  final String? employeeName;

  const _AttendanceCard({required this.attendance, this.employeeName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFormat = DateFormat('hh:mm a');

    final statusColor = _getStatusColor(attendance.status);
    final statusIcon = _getStatusIcon(attendance.status);

    final hasCheckedIn = attendance.checkInTime != null;
    final hasCheckedOut = attendance.checkOutTime != null;
    final canCheckOut = hasCheckedIn && !hasCheckedOut &&
        (attendance.status == 'present' || attendance.status == 'late');

    // Calculate hours worked
    String? hoursWorkedText;
    if (hasCheckedIn && hasCheckedOut) {
      final duration = attendance.checkOutTime!.difference(attendance.checkInTime!);
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      hoursWorkedText = '${hours}h ${minutes}m';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: statusColor.withValues(alpha: 0.1),
              child: Icon(statusIcon, color: statusColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employeeName ?? 'Employee #${attendance.employeeId}',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (hasCheckedIn) ...[
                        Icon(Icons.login, size: 14, color: Colors.green.shade600),
                        const SizedBox(width: 4),
                        Text(
                          timeFormat.format(attendance.checkInTime!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.green.shade600,
                          ),
                        ),
                      ],
                      if (hasCheckedOut) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.logout, size: 14, color: Colors.red.shade600),
                        const SizedBox(width: 4),
                        Text(
                          timeFormat.format(attendance.checkOutTime!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.red.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (hoursWorkedText != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 14, color: theme.colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          hoursWorkedText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        if (attendance.overtimeMinutes > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'OT: ${attendance.overtimeMinutes}m',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.orange.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getStatusLabel(attendance.status),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (canCheckOut) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 30,
                    child: FilledButton.tonalIcon(
                      onPressed: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (time != null && context.mounted) {
                          final bloc = context.read<AttendanceBloc>();
                          final date = bloc.state.selectedDate;
                          final checkOutTime = DateTime(
                            date.year, date.month, date.day,
                            time.hour, time.minute,
                          );
                          bloc.add(
                            AttendanceCheckOutRequested(
                              employeeId: attendance.employeeId,
                              checkOutTime: checkOutTime,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.logout, size: 14),
                      label: Text(
                        'employees.check_out'.tr(),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'present':
        return Colors.green;
      case 'late':
        return Colors.orange;
      case 'absent':
        return Colors.red;
      case 'leave':
        return Colors.blue;
      case 'early_departure':
        return Colors.deepOrange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'present':
        return Icons.check_circle_outline;
      case 'late':
        return Icons.access_time;
      case 'absent':
        return Icons.cancel_outlined;
      case 'leave':
        return Icons.beach_access_outlined;
      case 'early_departure':
        return Icons.exit_to_app_outlined;
      default:
        return Icons.help_outline;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'present':
        return 'employees.status_present'.tr();
      case 'late':
        return 'employees.status_late'.tr();
      case 'absent':
        return 'employees.status_absent'.tr();
      case 'leave':
        return 'employees.status_on_leave'.tr();
      case 'early_departure':
        return 'employees.status_early_departure'.tr();
      default:
        return status;
    }
  }
}

class _CheckOutResult {
  final Attendance attendance;
  final TimeOfDay? checkOutTime;

  const _CheckOutResult({required this.attendance, this.checkOutTime});
}

class _CheckOutSelectorDialog extends StatefulWidget {
  final List<Attendance> attendances;
  final Map<int, String> employeeNames;

  const _CheckOutSelectorDialog({required this.attendances, required this.employeeNames});

  @override
  State<_CheckOutSelectorDialog> createState() => _CheckOutSelectorDialogState();
}

class _CheckOutSelectorDialogState extends State<_CheckOutSelectorDialog> {
  TimeOfDay _checkOutTime = TimeOfDay.now();

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _checkOutTime,
    );
    if (picked != null) {
      setState(() => _checkOutTime = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFormat = DateFormat('hh:mm a');

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.logout, color: Colors.red.shade600, size: 22),
          const SizedBox(width: 8),
          Text('employees.check_out'.tr()),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'employees.select_employee_checkout'.tr(),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            // Check-out time picker
            InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'employees.select_checkout_time'.tr(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.access_time_outlined),
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(_checkOutTime.format(context)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...widget.attendances.map((a) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: a.status == 'late'
                      ? Colors.orange.withValues(alpha: 0.1)
                      : Colors.green.withValues(alpha: 0.1),
                  child: Icon(
                    Icons.person_outline,
                    color: a.status == 'late' ? Colors.orange : Colors.green,
                  ),
                ),
                title: Text(widget.employeeNames[a.employeeId] ?? 'Employee #${a.employeeId}'),
                subtitle: a.checkInTime != null
                    ? Text(
                        '${'employees.check_in'.tr()}: ${timeFormat.format(a.checkInTime!)}',
                        style: theme.textTheme.bodySmall,
                      )
                    : null,
                trailing: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).pop(
                    _CheckOutResult(attendance: a, checkOutTime: _checkOutTime),
                  ),
                  icon: const Icon(Icons.logout, size: 16),
                  label: Text('employees.check_out'.tr()),
                ),
              ),
            )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
      ],
    );
  }
}

class _AttendanceFAB extends StatefulWidget {
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  final VoidCallback onMarkLate;
  final VoidCallback onMarkAbsent;

  const _AttendanceFAB({
    required this.onCheckIn,
    required this.onCheckOut,
    required this.onMarkLate,
    required this.onMarkAbsent,
  });

  @override
  State<_AttendanceFAB> createState() => _AttendanceFABState();
}

class _AttendanceFABState extends State<_AttendanceFAB> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_isExpanded) ...[
          _buildMiniButton(
            icon: Icons.cancel_outlined,
            label: 'employees.mark_absent'.tr(),
            color: colorScheme.error,
            onPressed: () {
              setState(() => _isExpanded = false);
              widget.onMarkAbsent();
            },
          ),
          const SizedBox(height: 8),
          _buildMiniButton(
            icon: Icons.access_time,
            label: 'employees.mark_late'.tr(),
            color: colorScheme.tertiary,
            onPressed: () {
              setState(() => _isExpanded = false);
              widget.onMarkLate();
            },
          ),
          const SizedBox(height: 8),
          _buildMiniButton(
            icon: Icons.check_circle_outline,
            label: 'employees.check_in'.tr(),
            color: colorScheme.primary,
            onPressed: () {
              setState(() => _isExpanded = false);
              widget.onCheckIn();
            },
          ),
          const SizedBox(height: 8),
          _buildMiniButton(
            icon: Icons.logout,
            label: 'employees.check_out'.tr(),
            color: Colors.red.shade600,
            onPressed: () {
              setState(() => _isExpanded = false);
              widget.onCheckOut();
            },
          ),
          const SizedBox(height: 16),
        ],
        FloatingActionButton.extended(
          onPressed: () => setState(() => _isExpanded = !_isExpanded),
          icon: AnimatedRotation(
            turns: _isExpanded ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add),
          ),
          label: Text('employees.record_attendance'.tr()),
        ),
      ],
    );
  }

  Widget _buildMiniButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(28),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
