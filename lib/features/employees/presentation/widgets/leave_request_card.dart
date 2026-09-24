import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';

class LeaveRequestCard extends StatelessWidget {
  final LeaveRequest request;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onCancel;

  const LeaveRequestCard({
    super.key,
    required this.request,
    this.onApprove,
    this.onReject,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dateFormat = DateFormat('MMM d, yyyy');

    final statusColor = _getStatusColor(request.status);
    final leaveIcon = _getLeaveTypeIcon(request.leaveType);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Employee #${request.employeeId}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            leaveIcon,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _getLeaveTypeLabel(request.leaveType),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _getStatusLabel(request.status),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Date Range
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  '${dateFormat.format(request.startDate)} - ${dateFormat.format(request.endDate)}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.access_time_outlined,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  '${request.daysCount} ${'employees.days'.tr()}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),

            // Reason
            if (request.reason != null && request.reason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                request.reason!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Action Buttons (for pending requests)
            if (request.status == 'pending' &&
                (onApprove != null ||
                    onReject != null ||
                    onCancel != null)) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (onCancel != null)
                    TextButton(
                      onPressed: onCancel,
                      child: Text('common.cancel'.tr()),
                    ),
                  if (onReject != null)
                    TextButton(
                      onPressed: onReject,
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                      child: Text('employees.reject'.tr()),
                    ),
                  if (onApprove != null)
                    TextButton(
                      onPressed: onApprove,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.green,
                      ),
                      child: Text('employees.approve'.tr()),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'employees.leave_status_pending'.tr();
      case 'approved':
        return 'employees.leave_status_approved'.tr();
      case 'rejected':
        return 'employees.leave_status_rejected'.tr();
      case 'cancelled':
        return 'employees.leave_status_cancelled'.tr();
      default:
        return status;
    }
  }

  IconData _getLeaveTypeIcon(String leaveType) {
    switch (leaveType) {
      case 'annual':
        return Icons.beach_access_outlined;
      case 'sick':
        return Icons.local_hospital_outlined;
      case 'personal':
        return Icons.person_outline;
      case 'unpaid':
        return Icons.money_off_outlined;
      case 'maternity':
      case 'paternity':
        return Icons.child_care_outlined;
      default:
        return Icons.event_note_outlined;
    }
  }

  String _getLeaveTypeLabel(String leaveType) {
    switch (leaveType) {
      case 'annual':
        return 'employees.leave_type_annual'.tr();
      case 'sick':
        return 'employees.leave_type_sick'.tr();
      case 'personal':
        return 'employees.leave_type_personal'.tr();
      case 'unpaid':
        return 'employees.leave_type_unpaid'.tr();
      case 'maternity':
        return 'employees.leave_type_maternity'.tr();
      case 'paternity':
        return 'employees.leave_type_paternity'.tr();
      default:
        return leaveType;
    }
  }
}
