import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../data/services/permission_service.dart';
import '../../domain/entities/permission_constants.dart';
import '../../domain/entities/user_entity.dart';

class RolesScreen extends StatelessWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _RolesScreenContent();
  }
}

class _RolesScreenContent extends StatefulWidget {
  const _RolesScreenContent();

  @override
  State<_RolesScreenContent> createState() => _RolesScreenContentState();
}

class _RolesScreenContentState extends State<_RolesScreenContent> {
  UserRole? _selectedRole;

  static const _permissionCategories = <String, List<String>>{
    'system_admin': [
      Permissions.manageUsers,
      Permissions.promoteUsers,
      Permissions.deactivateUsers,
      Permissions.viewUserActivity,
      Permissions.backupRestore,
    ],
    'people': [
      Permissions.manageEmployees,
      Permissions.viewEmployees,
      Permissions.manageCustomers,
      Permissions.viewCustomers,
      Permissions.manageSuppliers,
      Permissions.viewSuppliers,
    ],
    'inventory': [
      Permissions.editProducts,
      Permissions.deleteProducts,
      Permissions.adjustStock,
      Permissions.manageCategories,
      Permissions.viewProducts,
      Permissions.manageBarcodes,
    ],
    'financial': [
      Permissions.processSales,
      Permissions.handleReturns,
      Permissions.manageDiscounts,
      Permissions.voidTransactions,
      Permissions.createSales,
      Permissions.managePurchases,
      Permissions.viewPurchases,
      Permissions.manageExpenses,
      Permissions.viewReports,
      Permissions.viewDailyReports,
    ],
    'settings': [
      Permissions.accessSettings,
      Permissions.manageTaxes,
      Permissions.manageAccounting,
      Permissions.exportData,
      Permissions.viewAuditLogs,
    ],
  };

  String _categoryLabel(String category) {
    switch (category) {
      case 'system_admin':
        return 'users.module_settings'.tr();
      case 'people':
        return 'users.module_employees'.tr();
      case 'inventory':
        return 'users.module_products'.tr();
      case 'financial':
        return 'users.module_sales'.tr();
      case 'settings':
        return 'users.module_settings'.tr();
      default:
        return category;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'system_admin':
        return Icons.admin_panel_settings_outlined;
      case 'people':
        return Icons.people_outline;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'financial':
        return Icons.attach_money_outlined;
      case 'settings':
        return Icons.settings_outlined;
      default:
        return Icons.help_outline;
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

  String _permissionLabel(String permission) {
    // Convert permission_name to a readable label
    return permission
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) {
          if (w.isEmpty) return w;
          return w[0].toUpperCase() + w.substring(1);
        })
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final permissionService = PermissionService();

    return Scaffold(
      appBar: AppBar(
        title: Text('users.roles_permissions'.tr()),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'users.roles_info_title'.tr(),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'users.roles_info_desc'.tr(),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Role Hierarchy
                  Text(
                    'users.system_roles'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Role cards
                  ...UserRole.values.map((role) {
                    final isSelected = _selectedRole == role;
                    final color = _roleColor(role);
                    final permissions = permissionService.getPermissionsForRole(
                      role,
                    );
                    // Filter out legacy permissions
                    final cleanPermissions = permissions
                        .where(
                          (p) =>
                              !p.contains('manage_') ||
                              Permissions.all.contains(p),
                        )
                        .toSet()
                        .toList();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected
                                ? color.withValues(alpha: 0.6)
                                : colorScheme.outlineVariant.withValues(
                                    alpha: 0.3,
                                  ),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        color: isSelected
                            ? color.withValues(alpha: 0.05)
                            : colorScheme.surfaceContainerHighest.withValues(
                                alpha: 0.3,
                              ),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedRole = isSelected ? null : role;
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: color.withValues(
                                        alpha: 0.15,
                                      ),
                                      child: Icon(
                                        _roleIcon(role),
                                        color: color,
                                        size: 22,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _roleLabel(role),
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                          ),
                                          Text(
                                            '${cleanPermissions.length} ${'users.permissions'.tr()}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      isSelected
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _roleDescription(role),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(height: 16),
                                  const Divider(height: 1),
                                  const SizedBox(height: 16),
                                  Text(
                                    'users.permissions_overview'.tr(),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ..._permissionCategories.entries.map((entry) {
                                    final categoryPerms = entry.value
                                        .where(
                                          (p) => cleanPermissions.contains(p),
                                        )
                                        .toList();
                                    if (categoryPerms.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return _PermissionCategorySection(
                                      icon: _categoryIcon(entry.key),
                                      label: _categoryLabel(entry.key),
                                      permissions: categoryPerms,
                                      permissionLabel: _permissionLabel,
                                      color: color,
                                    );
                                  }),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 24),

                  // Permission Matrix (comparison)
                  Text(
                    'users.permissions_overview'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _PermissionMatrix(
                    permissionService: permissionService,
                    categories: _permissionCategories,
                    categoryIcon: _categoryIcon,
                    categoryLabel: _categoryLabel,
                    permissionLabel: _permissionLabel,
                    roleLabel: _roleLabel,
                    roleColor: _roleColor,
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionCategorySection extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<String> permissions;
  final String Function(String) permissionLabel;
  final Color color;

  const _PermissionCategorySection({
    required this.icon,
    required this.label,
    required this.permissions,
    required this.permissionLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: permissions.map((p) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  permissionLabel(p),
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _PermissionMatrix extends StatelessWidget {
  final PermissionService permissionService;
  final Map<String, List<String>> categories;
  final IconData Function(String) categoryIcon;
  final String Function(String) categoryLabel;
  final String Function(String) permissionLabel;
  final String Function(UserRole) roleLabel;
  final Color Function(UserRole) roleColor;

  const _PermissionMatrix({
    required this.permissionService,
    required this.categories,
    required this.categoryIcon,
    required this.categoryLabel,
    required this.permissionLabel,
    required this.roleLabel,
    required this.roleColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        headingRowColor: WidgetStateProperty.all(
          colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        ),
        columns: [
          DataColumn(
            label: Text(
              'users.permissions'.tr(),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...UserRole.values.map(
            (role) => DataColumn(
              label: Text(
                roleLabel(role),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: roleColor(role),
                ),
              ),
            ),
          ),
        ],
        rows: categories.entries.expand((entry) {
          return entry.value.map((permission) {
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    permissionLabel(permission),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                ...UserRole.values.map((role) {
                  final perms = permissionService.getPermissionsForRole(role);
                  final has = perms.contains(permission);
                  return DataCell(
                    Center(
                      child: Icon(
                        has ? Icons.check_circle : Icons.remove_circle_outline,
                        color: has ? Colors.green : colorScheme.outlineVariant,
                        size: 20,
                      ),
                    ),
                  );
                }),
              ],
            );
          });
        }).toList(),
      ),
    );
  }
}
