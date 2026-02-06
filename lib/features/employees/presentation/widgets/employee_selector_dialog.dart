import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/repositories/employee_repository.dart';
import '../bloc/employees_bloc.dart';
import '../bloc/roles_bloc.dart';

class EmployeeSelectorDialog extends StatefulWidget {
  final String? title;
  final bool showRoleFilter;

  const EmployeeSelectorDialog({
    super.key,
    this.title,
    this.showRoleFilter = true,
  });

  @override
  State<EmployeeSelectorDialog> createState() => _EmployeeSelectorDialogState();
}

class _EmployeeSelectorDialogState extends State<EmployeeSelectorDialog> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedRoleFilter;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => EmployeesBloc(sl<EmployeeRepository>())
            ..add(const EmployeesInitialized()),
        ),
        BlocProvider(
          create: (context) => RolesBloc(sl<EmployeeRepository>())
            ..add(const RolesInitialized()),
        ),
      ],
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 500,
            maxHeight: 600,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.title ?? 'employees.select_employee'.tr(),
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

              // Search Bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'employees.search_by_name_phone'.tr(),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value.toLowerCase());
                  },
                ),
              ),

              // Role Filter Chips
              if (widget.showRoleFilter)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: BlocBuilder<RolesBloc, RealtimeState<List<Role>>>(
                    builder: (context, state) {
                      final roles = state is RealtimeSuccess<List<Role>>
                          ? state.data
                          : <Role>[];

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(
                              label: 'common.all'.tr(),
                              isSelected: _selectedRoleFilter == null,
                              onSelected: () {
                                setState(() => _selectedRoleFilter = null);
                              },
                            ),
                            ...roles.map((role) => _buildFilterChip(
                                  label: _localizedRoleName(context, role),
                                  isSelected:
                                      _selectedRoleFilter == role.name,
                                  onSelected: () {
                                    setState(
                                        () => _selectedRoleFilter = role.name);
                                  },
                                )),
                          ],
                        ),
                      );
                    },
                  ),
                ),

              const SizedBox(height: 8),

              // Employee List
              Expanded(
                child: BlocBuilder<EmployeesBloc, RealtimeState<List<Employee>>>(
                  builder: (context, state) {
                    if (state is RealtimeLoading) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (state is RealtimeError) {
                      return Center(
                        child: Text('common.error'.tr()),
                      );
                    }

                    if (state is RealtimeSuccess<List<Employee>>) {
                      var employees = state.data;

                      // Apply search filter
                      if (_searchQuery.isNotEmpty) {
                        employees = employees.where((e) {
                          return e.name.toLowerCase().contains(_searchQuery) ||
                              (e.phone?.toLowerCase().contains(_searchQuery) ??
                                  false) ||
                              (e.email?.toLowerCase().contains(_searchQuery) ??
                                  false);
                        }).toList();
                      }

                      if (employees.isEmpty) {
                        return Center(
                          child: Text('employees.no_employees'.tr()),
                        );
                      }

                      return ListView.builder(
                        itemCount: employees.length,
                        itemBuilder: (context, index) {
                          final employee = employees[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: colorScheme.primaryContainer,
                              child: Text(
                                _getInitials(employee.name),
                                style: TextStyle(
                                  color: colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(employee.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (employee.phone != null)
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.phone_outlined,
                                        size: 14,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        employee.phone!,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                if (employee.position != null)
                                  Text(
                                    employee.position!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                            onTap: () => Navigator.of(context).pop(employee),
                          );
                        },
                      );
                    }

                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
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
        labelStyle: TextStyle(
          color: isSelected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
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
}
