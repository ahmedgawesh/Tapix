import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../bloc/suppliers_bloc.dart';

/// Main supplier hub screen with quick stats, search, and supplier list
class SupplierHubScreen extends StatelessWidget {
  const SupplierHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SuppliersBloc(sl<SupplierRepository>()),
      child: const _SupplierHubContent(),
    );
  }
}

class _SupplierHubContent extends StatefulWidget {
  const _SupplierHubContent();

  @override
  State<_SupplierHubContent> createState() => _SupplierHubContentState();
}

class _SupplierHubContentState extends State<_SupplierHubContent> {
  final _searchController = TextEditingController();

  void _showSupplierPickerBottomSheet({
    required List<Supplier> suppliers,
  }) {
    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('suppliers.empty'.tr())),
      );
      return;
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currencyService = sl<CurrencyService>();

    showModalBottomSheet<Supplier>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return _SupplierPickerSheet(
          suppliers: suppliers,
          theme: theme,
          colorScheme: colorScheme,
          currencyService: currencyService,
        );
      },
    ).then((supplier) {
      if (supplier != null && mounted) {
        context.push('/suppliers/${supplier.id}');
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: Text('suppliers.title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'settings.title'.tr(),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<SuppliersBloc, RealtimeState<SuppliersData>>(
          builder: (context, state) {
            if (state is RealtimeLoading<SuppliersData>) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is RealtimeError<SuppliersData>) {
              return _buildErrorState(context, state);
            }

            if (state is RealtimeSuccess<SuppliersData>) {
              return _buildContent(context, state.data);
            }

            return const SizedBox.shrink();
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/suppliers/new'),
        icon: const Icon(LucideIcons.plus),
        label: Text('suppliers.add'.tr()),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, RealtimeError<SuppliersData> state) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.alertCircle,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'common.error'.tr(),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => context.read<SuppliersBloc>().refresh(),
            icon: const Icon(LucideIcons.rotateCcw),
            label: Text('common.retry'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, SuppliersData data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final currencyService = sl<CurrencyService>();

    // Calculate metrics
    final activeCount = data.suppliers.length;
    final totalPayableCents = data.suppliers.fold<int>(
      0,
      (sum, s) {
        final balance = s.balanceCents.toBigInt().toInt();
        return balance != 0 ? sum + balance.abs() : sum;
      },
    );
    final withBalanceCount = data.suppliers.where((s) => s.balanceCents.toBigInt().toInt() != 0).length;

    return RefreshIndicator(
      onRefresh: () async {
        context.read<SuppliersBloc>().refresh();
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
                    'suppliers.quick_stats'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 700;

                      final activeCard = _StatCard(
                        icon: LucideIcons.truck,
                        iconColor: colorScheme.primary,
                        backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.5),
                        label: 'suppliers.active_suppliers'.tr(),
                        value: activeCount.toString(),
                      );

                      final payablesCard = _StatCard(
                        icon: LucideIcons.wallet,
                        iconColor: colorScheme.secondary,
                        backgroundColor: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                        label: 'suppliers.total_payables'.tr(),
                        value: currencyService.format(totalPayableCents),
                      );

                      final withBalanceCard = _StatCard(
                        icon: LucideIcons.fileText,
                        iconColor: colorScheme.tertiary,
                        backgroundColor: colorScheme.tertiaryContainer.withValues(alpha: 0.5),
                        label: 'suppliers.with_balance'.tr(),
                        value: withBalanceCount.toString(),
                      );

                      if (!isNarrow) {
                        return Row(
                          children: [
                            Expanded(child: activeCard),
                            const SizedBox(width: 12),
                            Expanded(child: payablesCard),
                            const SizedBox(width: 12),
                            Expanded(child: withBalanceCard),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: activeCard),
                              const SizedBox(width: 12),
                              Expanded(child: payablesCard),
                            ],
                          ),
                          const SizedBox(height: 12),
                          withBalanceCard,
                        ],
                      );
                    },
                  ),
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
                  hintText: 'suppliers.search_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(LucideIcons.x),
                          onPressed: () {
                            _searchController.clear();
                            context.read<SuppliersBloc>().add(
                              const SuppliersSearchRequested(''),
                            );
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                onChanged: (value) {
                  context.read<SuppliersBloc>().add(
                    SuppliersSearchRequested(value),
                  );
                },
              ),
            ),
          ),

          // Quick Actions
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.push('/suppliers/new'),
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: Text('suppliers.add'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? const Color(0xFF90CAF9) : null,
                      side: BorderSide(
                        color: (isDark ? const Color(0xFF1E3A5F) : colorScheme.outlineVariant)
                            .withValues(alpha: isDark ? 0.9 : 0.8),
                      ),
                      backgroundColor: isDark ? const Color(0xFF0B0F14) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _showSupplierPickerBottomSheet(
                      suppliers: data.suppliers,
                    ),
                    icon: const Icon(LucideIcons.banknote, size: 18),
                    label: Text('suppliers.make_payment'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? const Color(0xFFFFB74D) : null,
                      side: BorderSide(
                        color: (isDark ? const Color(0xFF3D2E10) : colorScheme.outlineVariant)
                            .withValues(alpha: isDark ? 0.9 : 0.8),
                      ),
                      backgroundColor: isDark ? const Color(0xFF0B0F14) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/reports'),
                    icon: const Icon(LucideIcons.barChart3, size: 18),
                    label: Text('suppliers.view_reports'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? const Color(0xFFB0BEC5) : null,
                      side: BorderSide(
                        color: (isDark ? const Color(0xFF253242) : colorScheme.outlineVariant)
                            .withValues(alpha: isDark ? 0.9 : 0.8),
                      ),
                      backgroundColor: isDark ? const Color(0xFF0B0F14) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // All Suppliers Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'suppliers.all_suppliers'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Supplier List
          if (data.suppliers.isEmpty)
            SliverFillRemaining(
              child: _buildEmptyState(context),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final supplier = data.suppliers[index];
                  return _SupplierListTile(
                    supplier: supplier,
                    onTap: () => context.push('/suppliers/${supplier.id}'),
                  );
                },
                childCount: data.suppliers.length,
              ),
            ),

          // Bottom padding for FAB
          const SliverToBoxAdapter(
            child: SizedBox(height: 80),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.truck,
              size: 80,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'suppliers.empty'.tr(),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'suppliers.empty_hint'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/suppliers/new'),
              icon: const Icon(LucideIcons.plus),
              label: Text('suppliers.add_first'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 32),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SupplierListTile extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback onTap;

  const _SupplierListTile({
    required this.supplier,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyService = sl<CurrencyService>();
    final balanceCents = supplier.balanceCents.toBigInt().toInt();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  supplier.name.isNotEmpty ? supplier.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (supplier.phone != null || supplier.email != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(
                              supplier.phone != null ? LucideIcons.phone : LucideIcons.mail,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                supplier.phone ?? supplier.email ?? '',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                currencyService.format(balanceCents),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: balanceCents > 0 ? Colors.red : balanceCents < 0 ? Colors.green : Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupplierPickerSheet extends StatefulWidget {
  const _SupplierPickerSheet({
    required this.suppliers,
    required this.theme,
    required this.colorScheme,
    required this.currencyService,
  });

  final List<Supplier> suppliers;
  final ThemeData theme;
  final ColorScheme colorScheme;
  final CurrencyService currencyService;

  @override
  State<_SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<_SupplierPickerSheet> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final query = _searchController.text.toLowerCase();
        final filtered = query.isEmpty
            ? widget.suppliers
            : widget.suppliers.where((s) => s.name.toLowerCase().contains(query)).toList();

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: widget.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(
                    'purchases.select_supplier'.tr(),
                    style: widget.theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('common.cancel'.tr()),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'suppliers.search_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text('suppliers.no_results'.tr()))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final supplier = filtered[index];
                        final balanceCents = supplier.balanceCents.toBigInt().toInt();

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: widget.colorScheme.primaryContainer,
                            child: Text(
                              supplier.name.isNotEmpty
                                  ? supplier.name[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                color: widget.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            supplier.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            widget.currencyService.format(balanceCents),
                            style: TextStyle(
                              color: balanceCents > 0 ? Colors.red : balanceCents < 0 ? Colors.green : Colors.blue,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, supplier),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
