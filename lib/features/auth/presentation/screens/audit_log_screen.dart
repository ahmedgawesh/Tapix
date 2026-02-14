import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../bloc/audit_log_bloc.dart';

class AuditLogScreen extends StatelessWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuditLogBloc(
        auditService: sl<AuditLogService>(),
        db: sl<AppDatabase>(),
      ),
      child: const _AuditLogScreenContent(),
    );
  }
}

class _AuditLogScreenContent extends StatefulWidget {
  const _AuditLogScreenContent();

  @override
  State<_AuditLogScreenContent> createState() => _AuditLogScreenContentState();
}

class _AuditLogScreenContentState extends State<_AuditLogScreenContent> {
  final _searchController = TextEditingController();

  AuditLogViewModel _vm(RealtimeState<AuditLogViewModel> s) {
    if (s is RealtimeSuccess<AuditLogViewModel>) return s.data;
    if (s is RealtimeLoading<AuditLogViewModel> && s.previousData != null) return s.previousData!;
    if (s is RealtimeError<AuditLogViewModel> && s.previousData != null) return s.previousData!;
    if (s is RealtimeOptimistic<AuditLogViewModel>) return s.optimisticData;
    return const AuditLogViewModel();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/dashboard');
            }
          },
          tooltip: 'common.back'.tr(),
        ),
        title: Text('audit.title'.tr()),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'audit.search_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.search, size: 18),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            context.read<AuditLogBloc>().add(const AuditLogSearchChanged(''));
                            setState(() {});
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (value) {
                  context.read<AuditLogBloc>().add(AuditLogSearchChanged(value));
                  setState(() {});
                },
              ),
            ),

            // Filter chips
            BlocBuilder<AuditLogBloc, RealtimeState<AuditLogViewModel>>(
              buildWhen: (prev, curr) {
                final p = _vm(prev);
                final c = _vm(curr);
                return p.entityTypeFilter != c.entityTypeFilter ||
                    p.actionFilter != c.actionFilter ||
                    p.logs != c.logs;
              },
              builder: (context, state) {
                final vm = _vm(state);
                return _FilterSection(
                  entityTypeFilter: vm.entityTypeFilter,
                  actionFilter: vm.actionFilter,
                  entityTypes: vm.logs.map((l) => l.targetTable).toSet().toList()..sort(),
                  actions: vm.logs.map((l) => l.action).toSet().toList()..sort(),
                );
              },
            ),

            // Stats bar
            BlocBuilder<AuditLogBloc, RealtimeState<AuditLogViewModel>>(
              buildWhen: (prev, curr) {
                final p = _vm(prev);
                final c = _vm(curr);
                return p.filteredLogs.length != c.filteredLogs.length ||
                    p.logs.length != c.logs.length;
              },
              builder: (context, state) {
                final vm = _vm(state);
                final hasFilter = vm.entityTypeFilter != null ||
                    vm.actionFilter != null ||
                    vm.searchQuery.isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Icon(LucideIcons.activity, size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Text(
                        hasFilter
                            ? 'audit.showing_filtered'.tr(args: [
                                vm.filteredLogs.length.toString(),
                                vm.logs.length.toString(),
                              ])
                            : 'audit.total_entries'.tr(args: [vm.logs.length.toString()]),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      if (hasFilter)
                        TextButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            context.read<AuditLogBloc>().add(const AuditLogFiltersCleared());
                            setState(() {});
                          },
                          icon: const Icon(LucideIcons.x, size: 14),
                          label: Text('audit.clear_filters'.tr()),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                            textStyle: theme.textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),

            const Divider(height: 1),

            // Log list
            Expanded(
              child: BlocBuilder<AuditLogBloc, RealtimeState<AuditLogViewModel>>(
                builder: (context, state) {
                  if (state is RealtimeLoading<AuditLogViewModel> && state.previousData == null) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (state is RealtimeError<AuditLogViewModel> && state.previousData == null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.alertTriangle, size: 48, color: cs.error),
                          const SizedBox(height: 16),
                          Text('common.error'.tr(), style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Text(state.error.toString(), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    );
                  }

                  final vm = _vm(state);

                  if (vm.filteredLogs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(LucideIcons.fileSearch, size: 56, color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          Text(
                            'audit.empty'.tr(),
                            style: theme.textTheme.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'audit.empty_hint'.tr(),
                            style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: vm.filteredLogs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final log = vm.filteredLogs[index];
                      // Resolve username: userNames map → changes.performedBy fallback
                      final resolvedName = (log.userId != null ? vm.userNames[log.userId] : null)
                          ?? log.changes['performedBy']?.toString();
                      return _AuditLogTile(
                        log: log,
                        userName: resolvedName,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// FILTER SECTION
// ═══════════════════════════════════════════════════════
class _FilterSection extends StatelessWidget {
  final String? entityTypeFilter;
  final String? actionFilter;
  final List<String> entityTypes;
  final List<String> actions;

  const _FilterSection({
    required this.entityTypeFilter,
    required this.actionFilter,
    required this.entityTypes,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Entity type filters
          Text(
            'audit.filter_entity'.tr(),
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildChip(
                  context,
                  label: 'common.all'.tr(),
                  isSelected: entityTypeFilter == null,
                  onTap: () => context.read<AuditLogBloc>().add(const AuditLogEntityTypeFilterChanged(null)),
                ),
                for (final type in entityTypes)
                  _buildChip(
                    context,
                    label: _entityTypeLabel(type),
                    isSelected: entityTypeFilter == type,
                    onTap: () => context.read<AuditLogBloc>().add(AuditLogEntityTypeFilterChanged(type)),
                    color: _entityTypeColor(type, cs),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Action filters
          Text(
            'audit.filter_action'.tr(),
            style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildChip(
                  context,
                  label: 'common.all'.tr(),
                  isSelected: actionFilter == null,
                  onTap: () => context.read<AuditLogBloc>().add(const AuditLogActionFilterChanged(null)),
                ),
                for (final action in actions)
                  _buildChip(
                    context,
                    label: _actionLabel(action),
                    isSelected: actionFilter == action,
                    onTap: () => context.read<AuditLogBloc>().add(AuditLogActionFilterChanged(action)),
                    color: _actionColor(action, cs),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Color? color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 6),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: color?.withValues(alpha: 0.2) ?? cs.primaryContainer,
        checkmarkColor: color ?? cs.onPrimaryContainer,
        labelStyle: TextStyle(
          fontSize: 11,
          color: isSelected ? (color ?? cs.onPrimaryContainer) : cs.onSurfaceVariant,
        ),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  static String _entityTypeLabel(String type) {
    switch (type) {
      case 'purchase':
        return 'audit.entity_purchase'.tr();
      case 'purchase_return':
        return 'audit.entity_purchase_return'.tr();
      case 'purchase_payment':
        return 'audit.entity_purchase_payment'.tr();
      case 'sale':
        return 'audit.entity_sale'.tr();
      case 'sale_return':
        return 'audit.entity_sale_return'.tr();
      case 'product':
        return 'audit.entity_product'.tr();
      case 'customer':
        return 'audit.entity_customer'.tr();
      case 'supplier':
        return 'audit.entity_supplier'.tr();
      case 'user':
        return 'audit.entity_user'.tr();
      case 'accounting_period':
        return 'audit.entity_accounting_period'.tr();
      case 'journal_entry':
        return 'audit.entity_journal_entry'.tr();
      case 'expense':
        return 'audit.entity_expense'.tr();
      default:
        return type.replaceAll('_', ' ');
    }
  }

  static Color _entityTypeColor(String type, ColorScheme cs) {
    switch (type) {
      case 'purchase':
      case 'purchase_return':
      case 'purchase_payment':
        return cs.primary;
      case 'sale':
      case 'sale_return':
        return Colors.green;
      case 'product':
        return Colors.orange;
      case 'customer':
        return Colors.purple;
      case 'supplier':
        return Colors.teal;
      case 'user':
        return Colors.deepPurple;
      case 'accounting_period':
      case 'journal_entry':
        return Colors.indigo;
      case 'expense':
        return Colors.deepOrange;
      default:
        return cs.secondary;
    }
  }

  static String _actionLabel(String action) {
    switch (action) {
      case 'create':
        return 'audit.action_create'.tr();
      case 'update':
        return 'audit.action_update'.tr();
      case 'delete':
        return 'audit.action_delete'.tr();
      case 'post':
        return 'audit.action_post'.tr();
      case 'void':
        return 'audit.action_void'.tr();
      case 'create_and_post':
        return 'audit.action_create_and_post'.tr();
      case 'balance_change':
        return 'audit.action_balance_change'.tr();
      case 'price_change':
        return 'audit.action_price_change'.tr();
      case 'stock_adjustment':
        return 'audit.action_stock_adjustment'.tr();
      case 'close_period':
        return 'audit.action_close_period'.tr();
      case 'below_cost_override':
        return 'audit.action_below_cost_override'.tr();
      case 'login':
        return 'audit.action_login'.tr();
      case 'logout':
        return 'audit.action_logout'.tr();
      default:
        return action.replaceAll('_', ' ');
    }
  }

  static Color _actionColor(String action, ColorScheme cs) {
    switch (action) {
      case 'create':
      case 'create_and_post':
        return Colors.green;
      case 'update':
        return Colors.blue;
      case 'delete':
        return cs.error;
      case 'post':
        return Colors.teal;
      case 'void':
        return cs.error;
      case 'balance_change':
        return Colors.orange;
      case 'price_change':
        return Colors.purple;
      case 'stock_adjustment':
        return Colors.indigo;
      case 'close_period':
        return Colors.red;
      case 'below_cost_override':
        return Colors.deepOrange;
      case 'login':
        return Colors.cyan;
      case 'logout':
        return Colors.grey;
      default:
        return cs.secondary;
    }
  }
}

// ═══════════════════════════════════════════════════════
// AUDIT LOG TILE
// ═══════════════════════════════════════════════════════
class _AuditLogTile extends StatelessWidget {
  final AuditLog log;
  final String? userName;

  const _AuditLogTile({required this.log, this.userName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final actionColor = _FilterSection._actionColor(log.action, cs);
    final entityColor = _FilterSection._entityTypeColor(log.targetTable, cs);

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Action icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_actionIcon(log.action), size: 18, color: actionColor),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Action badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: actionColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _FilterSection._actionLabel(log.action),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: actionColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Entity badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: entityColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _FilterSection._entityTypeLabel(log.targetTable),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: entityColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        const Spacer(),
                        // Record ID
                        Text(
                          '#${log.recordId}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // User + time
                    Row(
                      children: [
                        Icon(LucideIcons.user, size: 12, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          userName ?? 'audit.system'.tr(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(LucideIcons.clock, size: 12, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          _formatTime(log.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'create':
      case 'create_and_post':
        return LucideIcons.plus;
      case 'update':
        return LucideIcons.pencil;
      case 'delete':
        return LucideIcons.trash2;
      case 'post':
        return LucideIcons.checkCircle;
      case 'void':
        return LucideIcons.ban;
      case 'balance_change':
        return LucideIcons.wallet;
      case 'price_change':
        return LucideIcons.tag;
      case 'stock_adjustment':
        return LucideIcons.package;
      default:
        return LucideIcons.fileText;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'audit.just_now'.tr();
    if (diff.inMinutes < 60) return 'audit.minutes_ago'.tr(args: [diff.inMinutes.toString()]);
    if (diff.inHours < 24) return 'audit.hours_ago'.tr(args: [diff.inHours.toString()]);
    if (diff.inDays < 7) return 'audit.days_ago'.tr(args: [diff.inDays.toString()]);

    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showDetails(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final changes = log.changes;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (ctx, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scrollController,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Title
              Text(
                'audit.detail_title'.tr(),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              // Info rows
              _detailRow(context, LucideIcons.hash, 'ID', log.id.toString()),
              _detailRow(context, LucideIcons.layers, 'audit.entity'.tr(),
                  _FilterSection._entityTypeLabel(log.targetTable)),
              _detailRow(context, LucideIcons.hash, 'audit.record_id'.tr(), log.recordId.toString()),
              _detailRow(context, LucideIcons.zap, 'audit.action_label'.tr(),
                  _FilterSection._actionLabel(log.action)),
              _detailRow(context, LucideIcons.user, 'audit.user'.tr(),
                  userName ?? 'audit.system'.tr()),
              _detailRow(context, LucideIcons.clock, 'audit.timestamp'.tr(),
                  log.createdAt.toIso8601String().replaceFirst('T', ' ').split('.').first),
              const SizedBox(height: 16),
              // Changes
              Text(
                'audit.changes'.tr(),
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(
                  _formatChanges(changes),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  String _formatChanges(Map<String, dynamic> changes) {
    if (changes.isEmpty) return '(empty)';
    final buffer = StringBuffer();
    for (final entry in changes.entries) {
      if (entry.value is Map) {
        buffer.writeln('${entry.key}:');
        for (final sub in (entry.value as Map).entries) {
          buffer.writeln('  ${sub.key}: ${sub.value}');
        }
      } else {
        buffer.writeln('${entry.key}: ${entry.value}');
      }
    }
    return buffer.toString().trimRight();
  }
}
