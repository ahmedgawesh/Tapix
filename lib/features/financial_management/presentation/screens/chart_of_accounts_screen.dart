import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../accounting/presentation/bloc/accounts_bloc.dart';

class ChartOfAccountsScreen extends StatelessWidget {
  const ChartOfAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AccountsBloc>(),
      child: const _ChartView(),
    );
  }
}

class _ChartView extends StatefulWidget {
  const _ChartView();

  @override
  State<_ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<_ChartView> {
  String? _selectedType;

  static const _accountTypes = [
    null, // All
    'asset',
    'liability',
    'equity',
    'revenue',
    'expense',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('financial_management.chart_of_accounts'.tr()),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'financial_management.add_account'.tr(),
            onPressed: () => _showAccountDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Type filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: _accountTypes.map((type) {
                final isSelected = _selectedType == type;
                final label = type == null
                    ? 'common.all'.tr()
                    : 'financial_management.type_$type'.tr();
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(label),
                    onSelected: (_) {
                      setState(() => _selectedType = type);
                      context.read<AccountsBloc>().add(
                            AccountFilterByTypeRequested(type),
                          );
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // Accounts list
          Expanded(
            child: BlocBuilder<AccountsBloc, RealtimeState<AccountsData>>(
              builder: (context, state) {
                if (state is RealtimeLoading<AccountsData>) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is RealtimeSuccess<AccountsData>) {
                  final accounts = state.data.accounts;
                  if (accounts.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.bookOpen, size: 64,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          Text(
                            'financial_management.no_accounts'.tr(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // Group by type
                  final grouped = <String, List<Account>>{};
                  for (final acc in accounts) {
                    grouped.putIfAbsent(acc.accountType, () => []).add(acc);
                  }

                  final sortedTypes = ['asset', 'liability', 'equity', 'revenue', 'expense'];
                  final orderedKeys = sortedTypes.where((t) => grouped.containsKey(t)).toList();

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: orderedKeys.length,
                    itemBuilder: (context, index) {
                      final type = orderedKeys[index];
                      final typeAccounts = grouped[type]!;
                      return _AccountTypeGroup(
                        type: type,
                        accounts: typeAccounts,
                        cs: cs,
                        onEdit: (acc) => _showAccountDialog(context, account: acc),
                        onDelete: (acc) => _confirmDelete(context, acc),
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
    );
  }

  void _showAccountDialog(BuildContext context, {Account? account}) {
    final isEdit = account != null;
    final codeController = TextEditingController(text: account?.accountCode ?? '');
    final nameController = TextEditingController(text: account?.accountName ?? '');
    final descController = TextEditingController(text: account?.description ?? '');
    String selectedType = account?.accountType ?? 'asset';

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text(isEdit
                  ? 'financial_management.edit_account'.tr()
                  : 'financial_management.add_account'.tr()),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: codeController,
                      decoration: InputDecoration(
                        labelText: 'financial_management.account_code'.tr(),
                        hintText: '1000',
                        border: const OutlineInputBorder(),
                      ),
                      enabled: !isEdit,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'financial_management.account_name'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedType,
                      decoration: InputDecoration(
                        labelText: 'financial_management.account_type'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      items: ['asset', 'liability', 'equity', 'revenue', 'expense']
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text('financial_management.type_$t'.tr()),
                              ))
                          .toList(),
                      onChanged: isEdit ? null : (v) => setState(() => selectedType = v!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      decoration: InputDecoration(
                        labelText: 'financial_management.description'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text('common.cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () {
                    final code = codeController.text.trim();
                    final name = nameController.text.trim();
                    if (code.isEmpty || name.isEmpty) return;

                    if (isEdit) {
                      final updated = Account(
                        id: account.id,
                        accountCode: account.accountCode,
                        accountName: name,
                        accountType: account.accountType,
                        parentAccountId: account.parentAccountId,
                        balanceCents: account.balanceCents,
                        currencyId: account.currencyId,
                        isActive: account.isActive,
                        isSystemAccount: account.isSystemAccount,
                        displayOrder: account.displayOrder,
                        description: descController.text.trim().isEmpty
                            ? null
                            : descController.text.trim(),
                        createdAt: account.createdAt,
                        updatedAt: DateTime.now(),
                      );
                      context.read<AccountsBloc>().add(AccountUpdateRequested(updated));
                    } else {
                      context.read<AccountsBloc>().add(AccountCreateRequested(
                            accountCode: code,
                            accountName: name,
                            accountType: selectedType,
                            currencyId: 1,
                            description: descController.text.trim().isEmpty
                                ? null
                                : descController.text.trim(),
                          ));
                    }
                    Navigator.pop(dialogContext);
                  },
                  child: Text(isEdit ? 'common.save'.tr() : 'common.create'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, Account account) {
    final colorScheme = Theme.of(context).colorScheme;

    if (account.isSystemAccount) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('financial_management.cannot_delete_system_account'.tr()),
          backgroundColor: colorScheme.error,
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(LucideIcons.trash2, color: colorScheme.error),
          title: Text('financial_management.delete_account_title'.tr()),
          content: Text(
            'financial_management.delete_account_body'.tr(
              args: [account.accountName],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
              onPressed: () {
                context.read<AccountsBloc>().add(AccountDeleteRequested(account.id));
                Navigator.pop(dialogContext);
              },
              child: Text('common.delete'.tr()),
            ),
          ],
        );
      },
    );
  }
}

class _AccountTypeGroup extends StatelessWidget {
  final String type;
  final List<Account> accounts;
  final CurrencyService cs;
  final void Function(Account) onEdit;
  final void Function(Account) onDelete;

  const _AccountTypeGroup({
    required this.type,
    required this.accounts,
    required this.cs,
    required this.onEdit,
    required this.onDelete,
  });

  Color _typeColor(String type) {
    switch (type) {
      case 'asset':
        return Colors.blue;
      case 'liability':
        return Colors.orange;
      case 'equity':
        return Colors.purple;
      case 'revenue':
        return Colors.green;
      case 'expense':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'asset':
        return LucideIcons.wallet;
      case 'liability':
        return LucideIcons.creditCard;
      case 'equity':
        return LucideIcons.landmark;
      case 'revenue':
        return LucideIcons.trendingUp;
      case 'expense':
        return LucideIcons.trendingDown;
      default:
        return LucideIcons.helpCircle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _typeColor(type);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Type header
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(_typeIcon(type), size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                'financial_management.type_$type'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${accounts.length}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Account cards
        ...accounts.map((acc) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              elevation: 0,
              child: ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Text(
                    acc.accountCode.length > 2
                        ? acc.accountCode.substring(0, 2)
                        : acc.accountCode,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Text(
                      acc.accountCode,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        acc.accountName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: acc.description != null && acc.description!.isNotEmpty
                    ? Text(acc.description!, style: theme.textTheme.bodySmall)
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cs.formatCents(acc.balanceCents.toBigInt().toInt()),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: acc.balanceCents >= Decimal.zero ? color : colorScheme.error,
                      ),
                    ),
                    if (!acc.isSystemAccount) ...[
                      const SizedBox(width: 4),
                      PopupMenuButton<String>(
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                const Icon(LucideIcons.edit, size: 16),
                                const SizedBox(width: 8),
                                Text('common.edit'.tr()),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(LucideIcons.trash2, size: 16, color: colorScheme.error),
                                const SizedBox(width: 8),
                                Text('common.delete'.tr(),
                                    style: TextStyle(color: colorScheme.error)),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (action) {
                          if (action == 'edit') onEdit(acc);
                          if (action == 'delete') onDelete(acc);
                        },
                      ),
                    ],
                    if (acc.isSystemAccount)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(LucideIcons.lock, size: 14,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                      ),
                  ],
                ),
              ),
            )),
        const SizedBox(height: 12),
      ],
    );
  }
}
