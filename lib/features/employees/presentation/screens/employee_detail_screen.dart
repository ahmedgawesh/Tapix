import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/repositories/employee_repository.dart';
import '../../domain/services/payroll_calculation_service.dart';
import '../bloc/employee_detail_bloc.dart';
import '../services/payslip_pdf_service.dart';

class EmployeeDetailScreen extends StatelessWidget {
  final int employeeId;

  const EmployeeDetailScreen({super.key, required this.employeeId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => EmployeeDetailBloc(sl<EmployeeRepository>())
        ..add(EmployeeDetailInitialized(employeeId)),
      child: const _EmployeeDetailContent(),
    );
  }
}

class _EmployeeDetailContent extends StatelessWidget {
  const _EmployeeDetailContent();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<EmployeeDetailBloc, EmployeeDetailState>(
      builder: (context, state) {
        final employee = state.employee;

        return Scaffold(
          appBar: AppBar(
            title: Text(employee?.name ?? 'employees.profile'.tr()),
            actions: [
              if (employee != null) ...[
                IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  onPressed: () => _exportPayslip(context, state),
                  tooltip: 'employees.export_payslip'.tr(),
                ),
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () => _sharePayslip(context, state),
                  tooltip: 'employees.share_payslip'.tr(),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      context.push('/employees/${state.employeeId}/edit'),
                  tooltip: 'employees.edit'.tr(),
                ),
              ],
            ],
          ),
          body: state.isLoading && employee == null
              ? const Center(child: CircularProgressIndicator())
              : employee == null
                  ? Center(child: Text('employees.not_found'.tr()))
                  : RefreshIndicator(
                      onRefresh: () async {
                        context.read<EmployeeDetailBloc>().add(
                              EmployeeDetailInitialized(state.employeeId),
                            );
                      },
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Employee Header Card
                          _EmployeeHeaderCard(
                            employee: employee,
                            role: state.role,
                          ),
                          const SizedBox(height: 16),

                          // Period Selector
                          _PeriodSelector(
                            period: state.period,
                            onChanged: (period) {
                              context.read<EmployeeDetailBloc>().add(
                                    EmployeeDetailPeriodChanged(period),
                                  );
                            },
                          ),
                          const SizedBox(height: 16),

                          // Salary & Compensation Card
                          _SalaryCard(employee: employee, state: state),
                          const SizedBox(height: 16),

                          // Attendance Summary Card
                          _AttendanceSummaryCard(state: state),
                          const SizedBox(height: 16),

                          // Leave Summary Card
                          _LeaveSummaryCard(state: state),
                          const SizedBox(height: 16),

                          // Net Pay Card
                          _NetPayCard(state: state),
                          const SizedBox(height: 16),

                          // Recent Attendance List
                          _RecentAttendanceSection(state: state),
                          const SizedBox(height: 80),
                        ],
                      ),
                    ),
        );
      },
    );
  }

  Future<void> _exportPayslip(
    BuildContext context,
    EmployeeDetailState state,
  ) async {
    if (state.employee == null) return;
    try {
      await PayslipPdfService.generateAndPrint(
        context: context,
        employee: state.employee!,
        role: state.role,
        period: state.period,
        attendanceCounts: state.attendanceCounts,
        payroll: state.latestPayroll,
        totalCommissionCents: state.totalCommissionCents,
        leaveRequests: state.leaveRequests,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _sharePayslip(
    BuildContext context,
    EmployeeDetailState state,
  ) async {
    if (state.employee == null) return;
    try {
      await PayslipPdfService.generateAndShare(
        context: context,
        employee: state.employee!,
        role: state.role,
        period: state.period,
        attendanceCounts: state.attendanceCounts,
        payroll: state.latestPayroll,
        totalCommissionCents: state.totalCommissionCents,
        leaveRequests: state.leaveRequests,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

// ==================== EMPLOYEE HEADER ====================

class _EmployeeHeaderCard extends StatelessWidget {
  final Employee employee;
  final Role? role;

  const _EmployeeHeaderCard({required this.employee, this.role});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: colorScheme.primaryContainer,
              child: Text(
                _getInitials(employee.name),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (employee.position != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.work_outline, size: 16,
                            color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          employee.position!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (employee.department != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.business_outlined, size: 16,
                            color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          employee.department!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (role != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _localizedRoleName(context, role!),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  if (employee.employeeCode != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.tag, size: 14,
                            color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          employee.employeeCode!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: employee.isActive
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                employee.isActive
                    ? 'common.active'.tr()
                    : 'common.inactive'.tr(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: employee.isActive ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
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

  String _localizedRoleName(BuildContext context, Role role) {
    final lang = context.locale.languageCode;
    final byLocale = switch (lang) {
      'ar' => role.nameAr,
      'fr' => role.nameFr,
      _ => null,
    };
    final trimmed = byLocale?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    final key = 'roles.${role.name}'.toLowerCase();
    final translated = key.tr();
    return translated == key ? role.name : translated;
  }
}

// ==================== PERIOD SELECTOR ====================

class _PeriodSelector extends StatelessWidget {
  final String period;
  final ValueChanged<String> onChanged;

  const _PeriodSelector({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final parts = period.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final dateFormat = DateFormat('MMMM yyyy', context.locale.toString());
    final displayDate = DateTime(year, month);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              final prev = month == 1
                  ? '${year - 1}-12'
                  : '$year-${(month - 1).toString().padLeft(2, '0')}';
              onChanged(prev);
            },
          ),
          Row(
            children: [
              Icon(Icons.calendar_month_outlined,
                  size: 18, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                dateFormat.format(displayDate),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              final now = DateTime.now();
              if (year < now.year ||
                  (year == now.year && month < now.month)) {
                final next = month == 12
                    ? '${year + 1}-01'
                    : '$year-${(month + 1).toString().padLeft(2, '0')}';
                onChanged(next);
              }
            },
          ),
        ],
      ),
    );
  }
}

// ==================== SALARY CARD ====================

class _SalaryCard extends StatelessWidget {
  final Employee employee;
  final EmployeeDetailState state;

  const _SalaryCard({required this.employee, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    final salaryCents = employee.salaryCents?.toBigInt().toInt() ?? 0;
    final commissionBps = employee.defaultCommissionRateBps;
    final totalCommission = state.totalCommissionCents;
    final dailyRate = employee.workingDaysPerPeriod > 0
        ? salaryCents ~/ employee.workingDaysPerPeriod
        : 0;

    final periodLabel = switch (employee.payPeriodType) {
      'weekly' => 'employees.period_weekly'.tr(),
      'daily' => 'employees.period_daily'.tr(),
      _ => 'employees.period_monthly'.tr(),
    };

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payments_outlined,
                    color: colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'employees.salary_compensation'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _DetailRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'employees.basic_salary'.tr(),
              value: cs.format(salaryCents),
              valueColor: colorScheme.onSurface,
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.schedule_outlined,
              label: 'employees.pay_period_type'.tr(),
              value: '$periodLabel · ${employee.workingDaysPerPeriod} ${'employees.working_days'.tr()} · ${employee.workingHoursPerDay}h',
              valueColor: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.today_outlined,
              label: 'employees.daily_rate'.tr(),
              value: cs.format(dailyRate),
              valueColor: colorScheme.secondary,
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.trending_up_outlined,
              label: 'employees.commission_rate'.tr(),
              value: '${(commissionBps / 100).toStringAsFixed(2)}%',
              valueColor: colorScheme.tertiary,
            ),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.monetization_on_outlined,
              label: 'employees.total_commission'.tr(),
              value: cs.format(totalCommission),
              valueColor: Colors.orange,
            ),
            if (state.latestPayroll != null) ...[
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.card_giftcard_outlined,
                label: 'employees.bonus'.tr(),
                value: cs.format(
                    state.latestPayroll!.bonusCents.toBigInt().toInt()),
                valueColor: Colors.green,
              ),
              const SizedBox(height: 10),
              _DetailRow(
                icon: Icons.more_time_outlined,
                label: 'employees.overtime_pay'.tr(),
                value: cs.format(
                    state.latestPayroll!.overtimeCents.toBigInt().toInt()),
                valueColor: Colors.blue,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================== ATTENDANCE SUMMARY ====================

class _AttendanceSummaryCard extends StatelessWidget {
  final EmployeeDetailState state;

  const _AttendanceSummaryCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_outlined,
                    color: colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'employees.attendance_summary'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _AttendanceStatTile(
                    icon: Icons.check_circle_outline,
                    label: 'employees.status_present'.tr(),
                    count: state.presentCount,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AttendanceStatTile(
                    icon: Icons.access_time,
                    label: 'employees.status_late'.tr(),
                    count: state.lateCount,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _AttendanceStatTile(
                    icon: Icons.cancel_outlined,
                    label: 'employees.status_absent'.tr(),
                    count: state.absentCount,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _AttendanceStatTile(
                    icon: Icons.beach_access_outlined,
                    label: 'employees.status_on_leave'.tr(),
                    count: state.leaveCount,
                    color: Colors.blue,
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

class _AttendanceStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;

  const _AttendanceStatTile({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count.toString(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color.withValues(alpha: 0.8),
                  ),
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

// ==================== LEAVE SUMMARY ====================

class _LeaveSummaryCard extends StatelessWidget {
  final EmployeeDetailState state;

  const _LeaveSummaryCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final approved =
        state.leaveRequests.where((l) => l.status == 'approved').length;
    final pending =
        state.leaveRequests.where((l) => l.status == 'pending').length;
    final totalDays = state.leaveRequests
        .where((l) => l.status == 'approved')
        .fold<int>(0, (sum, l) => sum + l.daysCount);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_note_outlined,
                    color: colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'employees.leave_summary'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'employees.leave_status_approved'.tr(),
                    value: approved.toString(),
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStat(
                    label: 'employees.leave_status_pending'.tr(),
                    value: pending.toString(),
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStat(
                    label: 'employees.total_leave_days'.tr(),
                    value: totalDays.toString(),
                    color: Colors.blue,
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

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color.withValues(alpha: 0.8),
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

// ==================== NET PAY CARD ====================

class _NetPayCard extends StatelessWidget {
  final EmployeeDetailState state;

  const _NetPayCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    final employee = state.employee;
    if (employee == null) return const SizedBox.shrink();

    final payroll = state.latestPayroll;
    final bonus = payroll?.bonusCents.toBigInt().toInt() ?? 0;
    final overtime = payroll?.overtimeCents.toBigInt().toInt() ?? 0;

    final calc = PayrollCalculationService.calculate(
      employee: employee,
      attendanceCounts: state.attendanceCounts,
      commissionCents: state.totalCommissionCents,
      bonusCents: bonus,
      overtimeCents: overtime,
    );

    return Card(
      elevation: 2,
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_outlined,
                    color: colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'employees.payslip_summary'.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _PayslipRow(
              label: 'employees.basic_salary'.tr(),
              value: cs.format(calc.basicSalaryCents),
            ),
            _PayslipRow(
              label: 'employees.commission'.tr(),
              value: cs.format(calc.commissionCents),
            ),
            _PayslipRow(
              label: 'employees.bonus'.tr(),
              value: cs.format(calc.bonusCents),
            ),
            _PayslipRow(
              label: 'employees.overtime_pay'.tr(),
              value: cs.format(calc.overtimeCents),
            ),
            const Divider(height: 16),
            _PayslipRow(
              label: 'employees.gross_pay'.tr(),
              value: cs.format(calc.grossPayCents),
              isBold: true,
            ),
            if (calc.absenceDeductionCents > 0)
              _PayslipRow(
                label: 'employees.absence_deduction'.tr(),
                value: '- ${cs.format(calc.absenceDeductionCents)}',
                valueColor: Colors.red,
              ),
            if (calc.lateDeductionCents > 0)
              _PayslipRow(
                label: 'employees.late_deduction'.tr(),
                value: '- ${cs.format(calc.lateDeductionCents)}',
                valueColor: Colors.orange,
              ),
            if (calc.totalDeductionCents > 0)
              _PayslipRow(
                label: 'employees.deductions'.tr(),
                value: '- ${cs.format(calc.totalDeductionCents)}',
                valueColor: Colors.red,
                isBold: true,
              ),
            const Divider(height: 16),
            _PayslipRow(
              label: 'employees.net_pay'.tr(),
              value: cs.format(calc.netPayCents),
              isBold: true,
              valueColor: Colors.green.shade700,
              isLarge: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _PayslipRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;
  final bool isLarge;

  const _PayslipRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
    this.isLarge = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: (isLarge
                    ? theme.textTheme.titleMedium
                    : theme.textTheme.bodyMedium)
                ?.copyWith(
              fontWeight: isBold ? FontWeight.bold : null,
            ),
          ),
          Text(
            value,
            style: (isLarge
                    ? theme.textTheme.titleLarge
                    : theme.textTheme.bodyMedium)
                ?.copyWith(
              fontWeight: isBold ? FontWeight.bold : null,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== DETAIL ROW ====================

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ==================== RECENT ATTENDANCE ====================

class _RecentAttendanceSection extends StatelessWidget {
  final EmployeeDetailState state;

  const _RecentAttendanceSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (state.attendances.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_outlined,
                color: colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              'employees.recent_attendance'.tr(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...state.attendances.take(10).map((a) {
          final dateFormat =
              DateFormat('EEE, MMM d', context.locale.toString());
          final timeFormat = DateFormat('hh:mm a');
          final statusColor = _statusColor(a.status);

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
            ),
            child: ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 16,
                backgroundColor: statusColor.withValues(alpha: 0.1),
                child: Icon(_statusIcon(a.status),
                    color: statusColor, size: 16),
              ),
              title: Text(dateFormat.format(a.attendanceDate)),
              subtitle: a.checkInTime != null
                  ? Text(
                      '${timeFormat.format(a.checkInTime!)}${a.checkOutTime != null ? ' - ${timeFormat.format(a.checkOutTime!)}' : ''}',
                      style: theme.textTheme.bodySmall,
                    )
                  : null,
              trailing: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusLabel(a.status),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'present':
        return Colors.green;
      case 'late':
        return Colors.orange;
      case 'absent':
        return Colors.red;
      case 'leave':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'present':
        return Icons.check_circle_outline;
      case 'late':
        return Icons.access_time;
      case 'absent':
        return Icons.cancel_outlined;
      case 'leave':
        return Icons.beach_access_outlined;
      default:
        return Icons.help_outline;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'present':
        return 'employees.status_present'.tr();
      case 'late':
        return 'employees.status_late'.tr();
      case 'absent':
        return 'employees.status_absent'.tr();
      case 'leave':
        return 'employees.status_on_leave'.tr();
      default:
        return status;
    }
  }
}
