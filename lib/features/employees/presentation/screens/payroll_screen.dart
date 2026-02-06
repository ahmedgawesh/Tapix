import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/repositories/employee_repository.dart';
import '../../domain/services/payroll_calculation_service.dart';
import '../bloc/payroll_bloc.dart';
import '../widgets/payroll_summary_cards.dart';

class PayrollScreen extends StatelessWidget {
  const PayrollScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final now = DateTime.now();
        final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';
        return PayrollBloc(sl<EmployeeRepository>())
          ..add(PayrollInitialized(period: period));
      },
      child: const _PayrollScreenContent(),
    );
  }
}

class _PayrollScreenContent extends StatefulWidget {
  const _PayrollScreenContent();

  @override
  State<_PayrollScreenContent> createState() => _PayrollScreenContentState();
}

class _PayrollScreenContentState extends State<_PayrollScreenContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<PayrollStatus?> _statusFilters = [
    PayrollStatus.draft,
    PayrollStatus.processed,
    PayrollStatus.paid,
    null, // All
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      final status = _statusFilters[_tabController.index];
      context.read<PayrollBloc>().add(PayrollFilterChanged(status));
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('employees.payroll'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () => _showPeriodSelector(context),
            tooltip: 'employees.select_period'.tr(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'employees.payroll_draft'.tr()),
            Tab(text: 'employees.payroll_processed'.tr()),
            Tab(text: 'employees.payroll_paid'.tr()),
            Tab(text: 'common.all'.tr()),
          ],
        ),
      ),
      body: SafeArea(
        child: BlocBuilder<PayrollBloc, PayrollState>(
          builder: (context, state) {
            return Column(
              children: [
                // Period Selector
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'employees.period'.tr(),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          state.period,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Summary Cards
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: PayrollSummaryCards(summary: state.summary),
                ),

                // Payroll List
                Expanded(
                  child: state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : state.payrolls.isEmpty
                          ? _EmptyState()
                          : _PayrollList(payrolls: state.payrolls),
                ),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreatePayrollDialog(context),
        icon: const Icon(Icons.add),
        label: Text('employees.create_payroll'.tr()),
      ),
    );
  }

  Future<void> _showPeriodSelector(BuildContext context) async {
    final bloc = context.read<PayrollBloc>();
    final currentPeriod = bloc.state.period;
    final parts = currentPeriod.split('-');
    var year = int.parse(parts[0]);
    var month = int.parse(parts[1]);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => _PeriodSelectorDialog(
        initialYear: year,
        initialMonth: month,
      ),
    );

    if (result != null) {
      bloc.add(PayrollPeriodChanged(result));
    }
  }

  Future<void> _showCreatePayrollDialog(BuildContext context) async {
    final bloc = context.read<PayrollBloc>();
    final result = await showDialog<({int employeeId, PayrollCalculation calc})>(
      context: context,
      builder: (dialogContext) => _CreatePayrollDialog(
        period: bloc.state.period,
      ),
    );

    if (result != null && context.mounted) {
      final period = bloc.state.period;
      final parts = period.split('-');
      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final periodStart = DateTime(year, month, 1);
      final periodEnd = DateTime(year, month + 1, 0);

      final currencyId = await _getCurrentCurrencyId();
      if (!context.mounted) return;

      bloc.add(PayrollCreateRequested(
        employeeId: result.employeeId,
        periodStart: periodStart,
        periodEnd: periodEnd,
        basicSalaryCents: result.calc.basicSalaryCents,
        bonusCents: result.calc.bonusCents,
        overtimeCents: result.calc.overtimeCents,
        deductionCents: result.calc.totalDeductionCents,
        netPayCents: result.calc.netPayCents,
        currencyId: currencyId,
      ));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('employees.payroll_created'.tr())),
      );
    }
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
            Icons.receipt_long_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'employees.no_payroll'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'employees.no_payroll_hint'.tr(),
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

class _PayrollList extends StatelessWidget {
  final List<Payroll> payrolls;

  const _PayrollList({required this.payrolls});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: payrolls.length,
      itemBuilder: (context, index) {
        final payroll = payrolls[index];
        return _PayrollCard(payroll: payroll);
      },
    );
  }
}

class _PayrollCard extends StatelessWidget {
  final Payroll payroll;

  const _PayrollCard({required this.payroll});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyService = sl<CurrencyService>();

    final statusColor = _getStatusColor(payroll.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Employee #${payroll.employeeId}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _getStatusLabel(payroll.status),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _PayrollItem(
                  label: 'employees.basic_salary'.tr(),
                  value: currencyService.format(payroll.basicSalaryCents.toBigInt().toInt()),
                ),
                const SizedBox(width: 16),
                _PayrollItem(
                  label: 'employees.commission'.tr(),
                  value: currencyService.format(payroll.commissionCents.toBigInt().toInt()),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _PayrollItem(
                  label: 'employees.deductions'.tr(),
                  value: '-${currencyService.format(payroll.deductionCents.toBigInt().toInt())}',
                  valueColor: Colors.red,
                ),
                const SizedBox(width: 16),
                _PayrollItem(
                  label: 'employees.net_pay'.tr(),
                  value: currencyService.format(payroll.netPayCents.toBigInt().toInt()),
                  valueColor: Colors.green,
                  isBold: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.blue;
      case 'processed':
        return Colors.purple;
      case 'paid':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'employees.payroll_draft'.tr();
      case 'pending':
        return 'employees.payroll_pending'.tr();
      case 'approved':
        return 'employees.payroll_approved'.tr();
      case 'processed':
        return 'employees.payroll_processed'.tr();
      case 'paid':
        return 'employees.payroll_paid'.tr();
      default:
        return status;
    }
  }
}

class _PayrollItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;

  const _PayrollItem({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: valueColor,
              fontWeight: isBold ? FontWeight.bold : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodSelectorDialog extends StatefulWidget {
  final int initialYear;
  final int initialMonth;

  const _PeriodSelectorDialog({
    required this.initialYear,
    required this.initialMonth,
  });

  @override
  State<_PeriodSelectorDialog> createState() => _PeriodSelectorDialogState();
}

class _PeriodSelectorDialogState extends State<_PeriodSelectorDialog> {
  late int _selectedYear;
  late int _selectedMonth;

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialYear;
    _selectedMonth = widget.initialMonth;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();

    return AlertDialog(
      title: Text('employees.select_period'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Year Selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() => _selectedYear--);
                },
              ),
              Text(
                _selectedYear.toString(),
                style: theme.textTheme.titleLarge,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _selectedYear < now.year
                    ? () {
                        setState(() => _selectedYear++);
                      }
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Month Grid
          GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1.5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 12,
            itemBuilder: (context, index) {
              final month = index + 1;
              final isSelected = month == _selectedMonth;
              final isFuture = _selectedYear == now.year && month > now.month;

              return InkWell(
                onTap: isFuture
                    ? null
                    : () {
                        setState(() => _selectedMonth = month);
                      },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? theme.colorScheme.primaryContainer
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    DateFormat('MMM').format(DateTime(2024, month)),
                    style: TextStyle(
                      color: isFuture
                          ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                          : isSelected
                              ? theme.colorScheme.onPrimaryContainer
                              : null,
                      fontWeight: isSelected ? FontWeight.bold : null,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () {
            final period =
                '$_selectedYear-${_selectedMonth.toString().padLeft(2, '0')}';
            Navigator.of(context).pop(period);
          },
          child: Text('common.select'.tr()),
        ),
      ],
    );
  }
}

class _CreatePayrollDialog extends StatefulWidget {
  final String period;

  const _CreatePayrollDialog({required this.period});

  @override
  State<_CreatePayrollDialog> createState() => _CreatePayrollDialogState();
}

class _CreatePayrollDialogState extends State<_CreatePayrollDialog> {
  final _formKey = GlobalKey<FormState>();
  final _bonusController = TextEditingController();
  final _overtimeController = TextEditingController();

  Employee? _selectedEmployee;
  List<Employee> _employees = [];
  bool _isLoading = true;
  PayrollCalculation? _calculation;

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  Future<void> _loadEmployees() async {
    final repository = sl<EmployeeRepository>();
    final employees = await repository.searchEmployees('');
    setState(() {
      _employees = employees;
      _isLoading = false;
    });
  }

  Future<void> _recalculate() async {
    if (_selectedEmployee == null) return;
    final repository = sl<EmployeeRepository>();

    final parts = widget.period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final periodStart = DateTime(year, month, 1);
    final periodEnd = DateTime(year, month + 1, 0, 23, 59, 59);

    final counts = await repository.getEmployeeAttendanceCounts(
      _selectedEmployee!.id,
      periodStart,
      periodEnd,
    );

    final bonus = (double.tryParse(_bonusController.text) ?? 0) * 100;
    final overtime = (double.tryParse(_overtimeController.text) ?? 0) * 100;

    setState(() {
      _calculation = PayrollCalculationService.calculate(
        employee: _selectedEmployee!,
        attendanceCounts: counts,
        bonusCents: bonus.round(),
        overtimeCents: overtime.round(),
      );
    });
  }

  @override
  void dispose() {
    _bonusController.dispose();
    _overtimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.receipt_long_outlined, color: colorScheme.primary, size: 22),
          const SizedBox(width: 8),
          Text('employees.create_payroll'.tr()),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            )
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Employee Selector
                      DropdownButtonFormField<Employee>(
                        initialValue: _selectedEmployee,
                        hint: Text('employees.select_employee'.tr()),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.person_outline),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _employees.map((employee) {
                          return DropdownMenuItem(
                            value: employee,
                            child: Text(employee.name),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() => _selectedEmployee = value);
                          _recalculate();
                        },
                        validator: (value) {
                          if (value == null) {
                            return 'employees.select_employee'.tr();
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Bonus
                      TextFormField(
                        controller: _bonusController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'employees.bonus'.tr(),
                          prefixIcon: const Icon(Icons.card_giftcard_outlined),
                          suffixText: cs.currencySymbol,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (_) => _recalculate(),
                      ),
                      const SizedBox(height: 12),

                      // Overtime Pay
                      TextFormField(
                        controller: _overtimeController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'employees.overtime_pay'.tr(),
                          prefixIcon: const Icon(Icons.more_time_outlined),
                          suffixText: cs.currencySymbol,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (_) => _recalculate(),
                      ),

                      // Calculation Preview
                      if (_calculation != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'employees.payslip_summary'.tr(),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Attendance row
                              Row(
                                children: [
                                  Icon(Icons.assignment_outlined,
                                      size: 14, color: colorScheme.onSurfaceVariant),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${_calculation!.presentDays} ${'employees.status_present'.tr()} · '
                                    '${_calculation!.lateDays} ${'employees.status_late'.tr()} · '
                                    '${_calculation!.absentDays} ${'employees.status_absent'.tr()}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              const Divider(height: 16),

                              _calcRow(context, 'employees.basic_salary'.tr(),
                                  cs.format(_calculation!.basicSalaryCents)),
                              _calcRow(context, 'employees.bonus'.tr(),
                                  cs.format(_calculation!.bonusCents)),
                              _calcRow(context, 'employees.overtime_pay'.tr(),
                                  cs.format(_calculation!.overtimeCents)),
                              const Divider(height: 12),
                              _calcRow(
                                context,
                                'employees.absence_deduction'.tr(),
                                '- ${cs.format(_calculation!.absenceDeductionCents)}',
                                color: Colors.red,
                              ),
                              _calcRow(
                                context,
                                'employees.late_deduction'.tr(),
                                '- ${cs.format(_calculation!.lateDeductionCents)}',
                                color: Colors.orange,
                              ),
                              const Divider(height: 12),
                              _calcRow(
                                context,
                                'employees.net_pay'.tr(),
                                cs.format(_calculation!.netPayCents),
                                isBold: true,
                                color: Colors.green.shade700,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton.icon(
          onPressed: _selectedEmployee == null || _calculation == null
              ? null
              : () {
                  if (_formKey.currentState!.validate()) {
                    Navigator.of(context).pop((
                      employeeId: _selectedEmployee!.id,
                      calc: _calculation!,
                    ));
                  }
                },
          icon: const Icon(Icons.check, size: 18),
          label: Text('employees.create_payroll'.tr()),
        ),
      ],
    );
  }

  Widget _calcRow(BuildContext context, String label, String value,
      {bool isBold = false, Color? color}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: isBold ? FontWeight.bold : null,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
