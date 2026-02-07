import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/repositories/customer_repository.dart';
import '../bloc/customers_bloc.dart';

/// Main customer hub screen with quick stats, segments, and customer list
class CustomerHubScreen extends StatelessWidget {
  const CustomerHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => CustomersBloc(sl<CustomerRepository>()),
      child: const _CustomerHubContent(),
    );
  }
}

class _CustomerHubContent extends StatefulWidget {
  const _CustomerHubContent();

  @override
  State<_CustomerHubContent> createState() => _CustomerHubContentState();
}

class _CustomerHubContentState extends State<_CustomerHubContent> {
  final _searchController = TextEditingController();

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
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: Text('customers.title'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
            tooltip: 'settings.title'.tr(),
          ),
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<CustomersBloc, RealtimeState<CustomersData>>(
          builder: (context, state) {
            if (state is RealtimeLoading<CustomersData>) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is RealtimeError<CustomersData>) {
              return _buildErrorState(context, state);
            }

            if (state is RealtimeSuccess<CustomersData>) {
              return _buildContent(context, state.data);
            }

            return const SizedBox.shrink();
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/customers/new'),
        icon: const Icon(Icons.add),
        label: Text('customers.add'.tr()),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, RealtimeError<CustomersData> state) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
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
            onPressed: () => context.read<CustomersBloc>().refresh(),
            icon: const Icon(Icons.refresh),
            label: Text('common.retry'.tr()),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, CustomersData data) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final currencyService = sl<CurrencyService>();

    // Calculate metrics
    final activeCount = data.customers.length;
    final totalBalanceCents = data.customers.fold<int>(
      0,
      (sum, c) => sum + c.balanceCents.toDouble().round(),
    );
    final withCreditCount = data.customers.where((c) => c.balanceCents.toDouble() > 0).length;

    // Calculate segment counts
    final segmentCounts = <String, int>{
      'retail': 0,
      'wholesale': 0,
      'premium': 0,
    };
    for (final customer in data.customers) {
      segmentCounts[customer.segment] = (segmentCounts[customer.segment] ?? 0) + 1;
    }

    return RefreshIndicator(
      onRefresh: () async {
        context.read<CustomersBloc>().refresh();
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
                    'customers.quick_stats'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 700;

                      final activeCard = _StatCard(
                        icon: Icons.people_outline,
                        iconColor: isDark ? const Color(0xFF90CAF9) : colorScheme.primary,
                        backgroundColor: isDark ? const Color(0xFF0B0F14) : colorScheme.primaryContainer,
                        borderColor: isDark ? const Color(0xFF1E3A5F) : colorScheme.primary.withValues(alpha: 0.2),
                        label: 'customers.active_customers'.tr(),
                        value: activeCount.toString(),
                      );

                      final receivablesCard = _StatCard(
                        icon: Icons.account_balance_wallet_outlined,
                        iconColor: isDark ? const Color(0xFFFFB74D) : colorScheme.secondary,
                        backgroundColor: isDark ? const Color(0xFF0B0F14) : colorScheme.secondaryContainer,
                        borderColor: isDark ? const Color(0xFF3D2E10) : colorScheme.secondary.withValues(alpha: 0.2),
                        label: 'customers.total_receivables'.tr(),
                        value: currencyService.format(totalBalanceCents),
                      );

                      final creditCard = _StatCard(
                        icon: Icons.credit_card_outlined,
                        iconColor: isDark ? const Color(0xFF80CBC4) : colorScheme.tertiary,
                        backgroundColor: isDark ? const Color(0xFF0B0F14) : colorScheme.tertiaryContainer,
                        borderColor: isDark ? const Color(0xFF1A3330) : colorScheme.tertiary.withValues(alpha: 0.2),
                        label: 'customers.with_credit'.tr(),
                        value: withCreditCount.toString(),
                      );

                      if (!isNarrow) {
                        return Row(
                          children: [
                            Expanded(child: activeCard),
                            const SizedBox(width: 12),
                            Expanded(child: receivablesCard),
                            const SizedBox(width: 12),
                            Expanded(child: creditCard),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: activeCard),
                              const SizedBox(width: 12),
                              Expanded(child: receivablesCard),
                            ],
                          ),
                          const SizedBox(height: 12),
                          creditCard,
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Customer Segments Section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'customers.segments'.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _SegmentChip(
                          icon: Icons.person_outline,
                          label: 'customers.segment_retail'.tr(),
                          count: segmentCounts['retail'] ?? 0,
                          color: isDark ? const Color(0xFF90CAF9) : colorScheme.primary,
                          backgroundColor: isDark ? const Color(0xFF0B0F14) : colorScheme.primaryContainer,
                          borderColor: isDark ? const Color(0xFF1E3A5F) : colorScheme.primary.withValues(alpha: 0.2),
                        ),
                        const SizedBox(width: 8),
                        _SegmentChip(
                          icon: Icons.business_outlined,
                          label: 'customers.segment_wholesale'.tr(),
                          count: segmentCounts['wholesale'] ?? 0,
                          color: isDark ? const Color(0xFFFFB74D) : colorScheme.secondary,
                          backgroundColor: isDark ? const Color(0xFF0B0F14) : colorScheme.secondaryContainer,
                          borderColor: isDark ? const Color(0xFF3D2E10) : colorScheme.secondary.withValues(alpha: 0.2),
                        ),
                        const SizedBox(width: 8),
                        _SegmentChip(
                          icon: Icons.star_outline,
                          label: 'customers.segment_premium'.tr(),
                          count: segmentCounts['premium'] ?? 0,
                          color: isDark ? const Color(0xFFCE93D8) : colorScheme.tertiary,
                          backgroundColor: isDark ? const Color(0xFF0B0F14) : colorScheme.tertiaryContainer,
                          borderColor: isDark ? const Color(0xFF3A2440) : colorScheme.tertiary.withValues(alpha: 0.2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Search Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'customers.search_hint'.tr(),
                  prefixIcon: Icon(Icons.search, color: isDark ? const Color(0xFF8A97A6) : null),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            context.read<CustomersBloc>().add(
                              const CustomersSearchRequested(''),
                            );
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF0B0F14) : null,
                ),
                onChanged: (value) {
                  context.read<CustomersBloc>().add(
                    CustomersSearchRequested(value),
                  );
                },
              ),
            ),
          ),

          // Quick Actions
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.push('/customers/new'),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text('customers.add'.tr()),
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
                    onPressed: () => context.push('/customers/receive-payment'),
                    icon: const Icon(Icons.payment, size: 18),
                    label: Text('customers.receive_payment'.tr()),
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
                    onPressed: () {},
                    icon: const Icon(Icons.analytics_outlined, size: 18),
                    label: Text('customers.view_reports'.tr()),
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

          // All Customers Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'customers.all_customers'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Customer List
          if (data.customers.isEmpty)
            SliverFillRemaining(
              child: _buildEmptyState(context),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final customer = data.customers[index];
                  return _CustomerListTile(
                    customer: customer,
                    onTap: () => context.push('/customers/${customer.id}'),
                  );
                },
                childCount: data.customers.length,
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
              Icons.people_outline,
              size: 80,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'customers.empty'.tr(),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'customers.empty_hint'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.push('/customers/new'),
              icon: const Icon(Icons.add),
              label: Text('customers.add_first'.tr()),
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
  final Color? borderColor;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    this.borderColor,
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
        border: borderColor != null ? Border.all(color: borderColor!, width: 1) : null,
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

class _SegmentChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  final Color backgroundColor;
  final Color? borderColor;

  const _SegmentChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
    required this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: borderColor != null ? Border.all(color: borderColor!, width: 1) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Text(
                    count.toString(),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              Text(
                'customers.customers'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerListTile extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;

  const _CustomerListTile({
    required this.customer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currencyService = sl<CurrencyService>();
    final balanceCents = customer.balanceCents.toDouble().round();

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
                  customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            customer.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildSegmentBadge(context, customer.segment),
                      ],
                    ),
                    if (customer.phone != null || customer.email != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          customer.phone ?? customer.email ?? '',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                currencyService.format(balanceCents),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: balanceCents > 0 ? Colors.red : Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentBadge(BuildContext context, String segment) {
    final theme = Theme.of(context);
    Color color;
    IconData icon;
    String label;

    switch (segment) {
      case 'wholesale':
        color = theme.colorScheme.secondary;
        icon = Icons.business_outlined;
        label = 'customers.segment_wholesale'.tr();
        break;
      case 'premium':
        color = theme.colorScheme.tertiary;
        icon = Icons.star;
        label = 'customers.segment_premium'.tr();
        break;
      default:
        color = theme.colorScheme.primary;
        icon = Icons.person_outline;
        label = 'customers.segment_retail'.tr();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
