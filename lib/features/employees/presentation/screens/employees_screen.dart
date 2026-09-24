import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/repositories/employee_repository.dart';
import '../bloc/employees_bloc.dart';
import '../bloc/roles_bloc.dart';
import '../widgets/employee_card.dart';
import '../widgets/employee_stats_cards.dart';

class EmployeesScreen extends StatelessWidget {
  const EmployeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              EmployeesBloc(sl<EmployeeRepository>())
                ..add(const EmployeesInitialized()),
        ),
        BlocProvider(
          create: (context) => EmployeeStatsBloc(sl<EmployeeRepository>()),
        ),
        BlocProvider(
          create: (context) =>
              RolesBloc(sl<EmployeeRepository>())
                ..add(const RolesInitialized()),
        ),
      ],
      child: const _EmployeesScreenContent(),
    );
  }
}

class _EmployeesScreenContent extends StatefulWidget {
  const _EmployeesScreenContent();

  @override
  State<_EmployeesScreenContent> createState() =>
      _EmployeesScreenContentState();
}

class _EmployeesScreenContentState extends State<_EmployeesScreenContent> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedRoleFilter;

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('employees.title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
            tooltip: 'settings.title'.tr(),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            context.read<EmployeesBloc>().refresh();
          },
          child: CustomScrollView(
            slivers: [
              // Quick Stats Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'employees.quick_stats'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const EmployeeStatsCards(),
                    ],
                  ),
                ),
              ),

              // Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'employees.search_hint'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                context.read<EmployeesBloc>().add(
                                  const EmployeeSearchRequested(''),
                                );
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    onChanged: (value) {
                      context.read<EmployeesBloc>().add(
                        EmployeeSearchRequested(value),
                      );
                    },
                  ),
                ),
              ),

              // Role Filter Chips
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'employees.filter_by_role'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      BlocBuilder<RolesBloc, RealtimeState<List<Role>>>(
                        builder: (context, state) {
                          final roles = state is RealtimeSuccess<List<Role>>
                              ? state.data
                              : <Role>[];

                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildFilterChip(
                                  context,
                                  label: 'common.all'.tr(),
                                  isSelected: _selectedRoleFilter == null,
                                  onSelected: () {
                                    setState(() => _selectedRoleFilter = null);
                                    context.read<EmployeesBloc>().add(
                                      const EmployeeFilterByRoleRequested(null),
                                    );
                                  },
                                ),
                                ...roles.map(
                                  (role) => _buildFilterChip(
                                    context,
                                    label: _localizedRoleName(context, role),
                                    isSelected:
                                        _selectedRoleFilter ==
                                        role.id.toString(),
                                    onSelected: () {
                                      setState(
                                        () => _selectedRoleFilter = role.id
                                            .toString(),
                                      );
                                      context.read<EmployeesBloc>().add(
                                        EmployeeFilterByRoleRequested(role.id),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Quick Action Chips
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: Icon(
                          Icons.person_add_outlined,
                          size: 18,
                          color: Colors.blue.shade400,
                        ),
                        label: Text('employees.add_employee'.tr()),
                        onPressed: () => context.push('/employees/create'),
                      ),
                      ActionChip(
                        avatar: Icon(
                          Icons.access_time_outlined,
                          size: 18,
                          color: Colors.amber.shade600,
                        ),
                        label: Text('employees.attendance'.tr()),
                        onPressed: () => context.push('/employees/attendance'),
                      ),
                      ActionChip(
                        avatar: Icon(
                          Icons.payments_outlined,
                          size: 18,
                          color: Colors.green.shade500,
                        ),
                        label: Text('employees.payroll'.tr()),
                        onPressed: () => context.push('/employees/payroll'),
                      ),
                      ActionChip(
                        avatar: Icon(
                          Icons.event_note_outlined,
                          size: 18,
                          color: Colors.purple.shade400,
                        ),
                        label: Text('employees.leave_requests'.tr()),
                        onPressed: () =>
                            context.push('/employees/leave-requests'),
                      ),
                    ],
                  ),
                ),
              ),

              // All Employees Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'employees.all_employees'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // Employee List
              BlocBuilder<EmployeesBloc, RealtimeState<List<Employee>>>(
                builder: (context, state) {
                  if (state is RealtimeLoading) {
                    return const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (state is RealtimeError) {
                    return SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 48,
                              color: colorScheme.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'common.error'.tr(),
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () =>
                                  context.read<EmployeesBloc>().refresh(),
                              child: Text('common.retry'.tr()),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (state is RealtimeSuccess<List<Employee>>) {
                    final employees = state.data;

                    if (employees.isEmpty) {
                      return SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 64,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'employees.no_employees'.tr(),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'employees.no_employees_hint'.tr(),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final employee = employees[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: EmployeeCard(
                              employee: employee,
                              onTap: () =>
                                  context.push('/employees/${employee.id}'),
                            ),
                          );
                        }, childCount: employees.length),
                      ),
                    );
                  }

                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                },
              ),

              // Bottom padding for FAB
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/employees/create'),
        icon: const Icon(Icons.add),
        label: Text('employees.add_employee'.tr()),
      ),
    );
  }

  Widget _buildFilterChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onSelected(),
        selectedColor: colorScheme.primaryContainer,
        checkmarkColor: colorScheme.onPrimaryContainer,
        labelStyle: TextStyle(
          color: isSelected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
