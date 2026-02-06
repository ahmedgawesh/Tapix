import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/entities/employee_entity.dart';
import '../../domain/repositories/employee_repository.dart';
import '../bloc/leave_requests_bloc.dart';
import '../bloc/employees_bloc.dart';
import '../widgets/leave_request_card.dart';
import '../widgets/leave_request_dialog.dart';

class LeaveRequestsScreen extends StatelessWidget {
  const LeaveRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => LeaveRequestsBloc(sl<EmployeeRepository>())
            ..add(const LeaveRequestsInitialized()),
        ),
        BlocProvider(
          create: (context) => EmployeesBloc(sl<EmployeeRepository>())
            ..add(const EmployeesInitialized()),
        ),
      ],
      child: const _LeaveRequestsScreenContent(),
    );
  }
}

class _LeaveRequestsScreenContent extends StatefulWidget {
  const _LeaveRequestsScreenContent();

  @override
  State<_LeaveRequestsScreenContent> createState() =>
      _LeaveRequestsScreenContentState();
}

class _LeaveRequestsScreenContentState
    extends State<_LeaveRequestsScreenContent>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<LeaveRequestStatus?> _statusFilters = [
    LeaveRequestStatus.pending,
    LeaveRequestStatus.approved,
    LeaveRequestStatus.rejected,
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
      context.read<LeaveRequestsBloc>().add(LeaveRequestsFilterChanged(status));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('employees.leave_requests'.tr()),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'employees.leave_status_pending'.tr()),
            Tab(text: 'employees.leave_status_approved'.tr()),
            Tab(text: 'employees.leave_status_rejected'.tr()),
            Tab(text: 'common.all'.tr()),
          ],
        ),
      ),
      body: SafeArea(
        child: BlocBuilder<LeaveRequestsBloc,
            RealtimeState<List<LeaveRequest>>>(
          builder: (context, state) {
            if (state is RealtimeLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is RealtimeError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text('common.error'.tr()),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          context.read<LeaveRequestsBloc>().refresh(),
                      child: Text('common.retry'.tr()),
                    ),
                  ],
                ),
              );
            }

            if (state is RealtimeSuccess<List<LeaveRequest>>) {
              final requests = state.data;

              if (requests.isEmpty) {
                return _EmptyState();
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: requests.length,
                itemBuilder: (context, index) {
                  final request = requests[index];
                  return LeaveRequestCard(
                    request: request,
                    onApprove: request.status == 'pending'
                        ? () => _approveRequest(request)
                        : null,
                    onReject: request.status == 'pending'
                        ? () => _rejectRequest(request)
                        : null,
                    onCancel: request.status == 'pending'
                        ? () => _cancelRequest(request)
                        : null,
                  );
                },
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: Text('employees.request_leave'.tr()),
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const LeaveRequestDialog(),
    );

    if (result != null && mounted) {
      context.read<LeaveRequestsBloc>().add(
            LeaveRequestCreateRequested(
              employeeId: result['employeeId'] as int,
              leaveType: result['leaveType'] as LeaveType,
              startDate: result['startDate'] as DateTime,
              endDate: result['endDate'] as DateTime,
              daysCount: result['daysCount'] as int,
              reason: result['reason'] as String?,
            ),
          );
    }
  }

  void _approveRequest(LeaveRequest request) {
    // TODO: Get current user ID from auth
    context.read<LeaveRequestsBloc>().add(
          LeaveRequestApproveRequested(
            id: request.id,
            approvedBy: 1, // Replace with actual user ID
          ),
        );
  }

  void _rejectRequest(LeaveRequest request) {
    // TODO: Show rejection reason dialog
    context.read<LeaveRequestsBloc>().add(
          LeaveRequestRejectRequested(
            id: request.id,
            rejectedBy: 1, // Replace with actual user ID
          ),
        );
  }

  void _cancelRequest(LeaveRequest request) {
    context.read<LeaveRequestsBloc>().add(
          LeaveRequestCancelRequested(request.id),
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
            Icons.event_busy_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'employees.no_leave_requests'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
