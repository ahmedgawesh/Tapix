import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../auth/auth.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../settings/presentation/bloc/company_bloc.dart';
import '../../../settings/domain/entities/company_profile.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Responsive breakpoints
    final isDesktop = screenWidth >= 1024;
    final isTablet = screenWidth >= 600 && screenWidth < 1024;
    
    // Responsive grid
    final crossAxisCount = isDesktop ? 4 : (isTablet ? 3 : 2);
    final padding = isDesktop ? 24.0 : (isTablet ? 20.0 : 16.0);

    return Scaffold(
      appBar: AppBar(
        title: Text('dashboard.title'.tr()),
        centerTitle: true,
        actions: [
          // Company info
          BlocBuilder<CompanyBloc, RealtimeState<CompanyProfile>>(
            builder: (context, state) {
              if (state is RealtimeSuccess<CompanyProfile>) {
                final profile = state.data;
                if (profile.name.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Company logo
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          backgroundImage: (profile.logoBase64 != null && profile.logoBase64!.isNotEmpty)
                              ? MemoryImage(base64Decode(profile.logoBase64!))
                              : null,
                          child: (profile.logoBase64 == null || profile.logoBase64!.isEmpty)
                              ? Icon(
                                  LucideIcons.building2,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant,
                                )
                              : null,
                        ),
                        if (isDesktop || isTablet) ...[
                          const SizedBox(width: 8),
                          Text(
                            profile.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }
              }
              return const SizedBox.shrink();
            },
          ),
          const SizedBox(width: 8),
          // User info
          BlocBuilder<AuthBloc, RealtimeState<UserEntity?>>(
            builder: (context, state) {
              if (state is AuthAuthenticated) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        radius: 16,
                        child: Icon(
                          LucideIcons.user,
                          size: 18,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      if (isDesktop || isTablet) ...[
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              state.user.username,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              state.user.role.displayName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          // Logout button
          IconButton(
            icon: const Icon(LucideIcons.logOut),
            tooltip: 'auth.logout'.tr(),
            onPressed: () {
              context.read<AuthBloc>().add(const AuthLogoutRequested());
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome message
              BlocBuilder<AuthBloc, RealtimeState<UserEntity?>>(
                builder: (context, state) {
                  if (state is AuthAuthenticated) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'dashboard.welcome'.tr(args: [state.user.username]),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'dashboard.role'.tr(args: [state.user.role.displayName]),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              
              // Quick actions grid
              Text(
                'dashboard.quick_actions'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              
              GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: isDesktop ? 1.3 : 1.1,
                children: [
                  _DashboardCard(
                    icon: LucideIcons.shoppingCart,
                    title: 'dashboard.new_sale'.tr(),
                    color: colorScheme.primary,
                    onTap: () => context.push('/sales'),
                  ),
                  _DashboardCard(
                    icon: LucideIcons.package,
                    title: 'dashboard.products'.tr(),
                    color: colorScheme.secondary,
                    onTap: () => context.push('/products'),
                  ),
                  _DashboardCard(
                    icon: LucideIcons.users,
                    title: 'dashboard.customers'.tr(),
                    color: colorScheme.tertiary,
                    onTap: () => context.push('/customers'),
                  ),
                  _DashboardCard(
                    icon: LucideIcons.barChart3,
                    title: 'dashboard.reports'.tr(),
                    color: colorScheme.error,
                    onTap: () => context.push('/reports'),
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Management section
              Text(
                'dashboard.management'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              
              GridView.count(
                crossAxisCount: crossAxisCount,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: isDesktop ? 1.3 : 1.1,
                children: [
                  _DashboardCard(
                    icon: LucideIcons.truck,
                    title: 'dashboard.suppliers'.tr(),
                    color: Colors.teal,
                    onTap: () => context.push('/suppliers'),
                  ),
                  _DashboardCard(
                    icon: LucideIcons.shoppingBag,
                    title: 'dashboard.purchases'.tr(),
                    color: Colors.indigo,
                    onTap: () => context.push('/purchases'),
                  ),
                  _DashboardCard(
                    icon: LucideIcons.userCog,
                    title: 'dashboard.employees'.tr(),
                    color: const Color(0xFF00ACC1), // Cyan 600 - distinct and professional
                    onTap: () => context.push('/employees'),
                  ),
                  _DashboardCard(
                    icon: LucideIcons.receipt,
                    title: 'dashboard.expenses'.tr(),
                    color: Colors.orange,
                    onTap: () => context.push('/expenses'),
                  ),
                  _DashboardCard(
                    icon: LucideIcons.settings,
                    title: 'dashboard.settings'.tr(),
                    color: Colors.blueGrey,
                    onTap: () => context.push('/settings'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(color.withAlpha(38), Colors.transparent),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: color,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
