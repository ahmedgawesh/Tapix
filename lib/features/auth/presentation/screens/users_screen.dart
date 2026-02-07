import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/user_repository_interface.dart';
import '../bloc/users_bloc.dart';
import '../widgets/user_card.dart';
import '../widgets/user_stats_cards.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => UsersBloc(sl<UserRepositoryInterface>())
            ..add(const UsersInitialized()),
        ),
        BlocProvider(
          create: (context) => UserStatsBloc(sl<UserRepositoryInterface>()),
        ),
      ],
      child: const _UsersScreenContent(),
    );
  }
}

class _UsersScreenContent extends StatefulWidget {
  const _UsersScreenContent();

  @override
  State<_UsersScreenContent> createState() => _UsersScreenContentState();
}

class _UsersScreenContentState extends State<_UsersScreenContent> {
  final TextEditingController _searchController = TextEditingController();
  UserRole? _selectedRoleFilter;

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
        title: Text('users.title'.tr()),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            onPressed: () => context.push('/users/roles'),
            tooltip: 'users.roles_permissions'.tr(),
          ),
          IconButton(
            icon: const Icon(Icons.history_outlined),
            onPressed: () => context.push('/audit'),
            tooltip: 'users.audit_logs'.tr(),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            context.read<UsersBloc>().refresh();
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
                        'users.quick_stats'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const UserStatsCards(),
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
                      hintText: 'users.search_hint'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                context
                                    .read<UsersBloc>()
                                    .add(const UserSearchRequested(''));
                                setState(() {});
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                    ),
                    onChanged: (value) {
                      context
                          .read<UsersBloc>()
                          .add(UserSearchRequested(value));
                      setState(() {});
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
                        'users.filter_by_role'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(
                              context,
                              label: 'common.all'.tr(),
                              isSelected: _selectedRoleFilter == null,
                              onSelected: () {
                                setState(() => _selectedRoleFilter = null);
                                context.read<UsersBloc>().add(
                                      const UserFilterByRoleRequested(null),
                                    );
                              },
                            ),
                            _buildFilterChip(
                              context,
                              label: 'users.role_owner'.tr(),
                              isSelected:
                                  _selectedRoleFilter == UserRole.owner,
                              onSelected: () {
                                setState(() =>
                                    _selectedRoleFilter = UserRole.owner);
                                context.read<UsersBloc>().add(
                                      const UserFilterByRoleRequested(
                                          UserRole.owner),
                                    );
                              },
                            ),
                            _buildFilterChip(
                              context,
                              label: 'users.role_manager'.tr(),
                              isSelected:
                                  _selectedRoleFilter == UserRole.manager,
                              onSelected: () {
                                setState(() =>
                                    _selectedRoleFilter = UserRole.manager);
                                context.read<UsersBloc>().add(
                                      const UserFilterByRoleRequested(
                                          UserRole.manager),
                                    );
                              },
                            ),
                            _buildFilterChip(
                              context,
                              label: 'users.role_cashier'.tr(),
                              isSelected:
                                  _selectedRoleFilter == UserRole.cashier,
                              onSelected: () {
                                setState(() =>
                                    _selectedRoleFilter = UserRole.cashier);
                                context.read<UsersBloc>().add(
                                      const UserFilterByRoleRequested(
                                          UserRole.cashier),
                                    );
                              },
                            ),
                            _buildFilterChip(
                              context,
                              label: 'users.role_salesperson'.tr(),
                              isSelected:
                                  _selectedRoleFilter == UserRole.salesperson,
                              onSelected: () {
                                setState(() =>
                                    _selectedRoleFilter = UserRole.salesperson);
                                context.read<UsersBloc>().add(
                                      const UserFilterByRoleRequested(
                                          UserRole.salesperson),
                                    );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // User List
              BlocBuilder<UsersBloc, RealtimeState<List<UserEntity>>>(
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
                                  context.read<UsersBloc>().refresh(),
                              child: Text('common.retry'.tr()),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  if (state is RealtimeSuccess<List<UserEntity>>) {
                    final users = state.data;

                    if (users.isEmpty) {
                      return SliverFillRemaining(
                        child: SingleChildScrollView(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.people_outline,
                                    size: 64,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'users.empty'.tr(),
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'users.empty_hint'.tr(),
                                    style:
                                        theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    return SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final user = users[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: UserCard(
                                user: user,
                                onTap: () =>
                                    context.push('/users/${user.id}/edit'),
                                onToggleActive: () {
                                  context.read<UsersBloc>().add(
                                        UserToggleActiveRequested(
                                          user.id,
                                          !user.isActive,
                                        ),
                                      );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        user.isActive
                                            ? 'users.deactivated_success'.tr()
                                            : 'users.activated_success'.tr(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                          childCount: users.length,
                        ),
                      ),
                    );
                  }

                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                },
              ),

              // Bottom padding for FAB
              const SliverToBoxAdapter(
                child: SizedBox(height: 80),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/users/add'),
        icon: const Icon(Icons.person_add_outlined),
        label: Text('users.add'.tr()),
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
      padding: const EdgeInsetsDirectional.only(end: 8),
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
