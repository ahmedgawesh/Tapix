import 'dart:convert';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../auth/auth.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../settings/presentation/bloc/company_bloc.dart';
import '../../../settings/domain/entities/company_profile.dart';
import '../widgets/stock_alerts_section.dart';
import '../widgets/daily_sales_summary_section.dart';
import '../widgets/payment_reminders_section.dart';
import '../widgets/cheque_reminders_section.dart';
import '../../../inventory/presentation/widgets/expiry_alerts_section.dart';

/// Represents a single dashboard shortcut item.
class DashboardItemData {
  final String id;
  final IconData icon;
  final String titleKey;
  final Color color;
  final String route;
  /// If true, only shown to owner users.
  final bool ownerOnly;

  const DashboardItemData({
    required this.id,
    required this.icon,
    required this.titleKey,
    required this.color,
    required this.route,
    this.ownerOnly = false,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Master item registry – single unified list with all dashboard shortcuts.
// The default order below is the initial order for new users.
// ─────────────────────────────────────────────────────────────────────────────

const _kAllDefaultItems = [
  DashboardItemData(
    id: 'new_sale',
    icon: LucideIcons.shoppingCart,
    titleKey: 'dashboard.new_sale',
    color: Color(0xFF6750A4), // resolved to colorScheme.primary at runtime
    route: '/sales',
  ),
  DashboardItemData(
    id: 'products',
    icon: LucideIcons.package,
    titleKey: 'dashboard.products',
    color: Color(0xFF625B71),
    route: '/products',
  ),
  DashboardItemData(
    id: 'customers',
    icon: LucideIcons.users,
    titleKey: 'dashboard.customers',
    color: Color(0xFF7D5260),
    route: '/customers',
  ),
  DashboardItemData(
    id: 'reports',
    icon: LucideIcons.barChart3,
    titleKey: 'dashboard.reports',
    color: Color(0xFFB3261E),
    route: '/reports',
  ),
  DashboardItemData(
    id: 'suppliers',
    icon: LucideIcons.truck,
    titleKey: 'dashboard.suppliers',
    color: Colors.teal,
    route: '/suppliers',
  ),
  DashboardItemData(
    id: 'purchases',
    icon: LucideIcons.shoppingBag,
    titleKey: 'dashboard.purchases',
    color: Colors.indigo,
    route: '/purchases',
  ),
  DashboardItemData(
    id: 'employees',
    icon: LucideIcons.userCog,
    titleKey: 'dashboard.employees',
    color: Color(0xFF00ACC1),
    route: '/employees',
  ),
  DashboardItemData(
    id: 'users',
    icon: LucideIcons.shield,
    titleKey: 'dashboard.users',
    color: Color(0xFF7E57C2),
    route: '/users',
  ),
  DashboardItemData(
    id: 'expenses',
    icon: LucideIcons.receipt,
    titleKey: 'dashboard.expenses',
    color: Colors.orange,
    route: '/expenses',
  ),
  DashboardItemData(
    id: 'settings',
    icon: LucideIcons.settings,
    titleKey: 'dashboard.settings',
    color: Colors.blueGrey,
    route: '/settings',
  ),
  DashboardItemData(
    id: 'financial_mgmt',
    icon: LucideIcons.landmark,
    titleKey: 'dashboard.financial_mgmt',
    color: Color(0xFF1565C0),
    route: '/financial-management',
    ownerOnly: true,
  ),
];

// SharedPreferences key for the unified order.
const _kDashboardOrderKey = 'dashboard_items_order';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  bool _isEditMode = false;
  late AnimationController _wobbleController;

  /// The unified ordered list of all dashboard items.
  List<DashboardItemData> _items = List.of(_kAllDefaultItems);

  @override
  void initState() {
    super.initState();
    _wobbleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _loadSavedOrder();
  }

  @override
  void dispose() {
    _wobbleController.dispose();
    super.dispose();
  }

  // ─── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadSavedOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kDashboardOrderKey);

    if (saved != null && saved.isNotEmpty) {
      final byId = {for (final item in _kAllDefaultItems) item.id: item};
      final ordered = <DashboardItemData>[];
      for (final id in saved) {
        final item = byId.remove(id);
        if (item != null) ordered.add(item);
      }
      // Append any new items added after the user saved their order.
      ordered.addAll(byId.values);
      setState(() => _items = ordered);
    } else {
      setState(() {});
    }
  }

  Future<void> _saveOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kDashboardOrderKey,
      _items.map((e) => e.id).toList(),
    );
  }

  // ─── Edit mode ──────────────────────────────────────────────────────────────

  void _enterEditMode() {
    HapticFeedback.heavyImpact();
    setState(() => _isEditMode = true);
    _wobbleController.repeat(reverse: true);
  }

  void _exitEditMode() {
    setState(() => _isEditMode = false);
    _wobbleController.stop();
    _wobbleController.reset();
    _saveOrder();
  }

  // ─── Color resolution (theme-aware colors for specific items) ──────────────

  Color _resolveColor(DashboardItemData item, ColorScheme colorScheme) {
    switch (item.id) {
      case 'new_sale':
        return colorScheme.primary;
      case 'products':
        return colorScheme.secondary;
      case 'customers':
        return colorScheme.tertiary;
      case 'reports':
        return colorScheme.error;
      default:
        return item.color;
    }
  }

  // ─── Filter items by user role ─────────────────────────────────────────────

  List<DashboardItemData> _visibleItems(bool isOwner) {
    if (isOwner) return _items;
    return _items.where((item) => !item.ownerOnly).toList();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

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
          // Edit mode: show Done button
          if (_isEditMode)
            TextButton.icon(
              onPressed: _exitEditMode,
              icon: const Icon(LucideIcons.check, size: 18),
              label: Text('dashboard.done_editing'.tr()),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
              ),
            ),
          if (!_isEditMode) ...[
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
                          CircleAvatar(
                            radius: 16,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            backgroundImage: (profile.logoBase64 != null &&
                                    profile.logoBase64!.isNotEmpty)
                                ? MemoryImage(
                                    base64Decode(profile.logoBase64!))
                                : null,
                            child: (profile.logoBase64 == null ||
                                    profile.logoBase64!.isEmpty)
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
        ],
      ),
      body: SafeArea(
        child: BlocBuilder<AuthBloc, RealtimeState<UserEntity?>>(
          builder: (context, authState) {
            final isOwner = authState is AuthAuthenticated &&
                authState.user.isOwner;
            final visibleItems = _visibleItems(isOwner);

            return SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Edit mode banner
                  if (_isEditMode)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color:
                            colorScheme.primaryContainer.withAlpha(180),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.primary.withAlpha(80),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            LucideIcons.move,
                            size: 20,
                            color: colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'dashboard.edit_mode_hint'.tr(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Welcome message (hidden in edit mode)
                  if (!_isEditMode && authState is AuthAuthenticated)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'dashboard.welcome'.tr(
                                args: [authState.user.username]),
                            style:
                                theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'dashboard.role'.tr(args: [
                              authState.user.role.displayName
                            ]),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Info sections (hidden in edit mode)
                  if (!_isEditMode) ...[
                    const StockAlertsSection(),
                    const ExpiryAlertsSection(),
                    const DailySalesSummarySection(),
                    const PaymentRemindersSection(),
                    const ChequeRemindersSection(),
                  ],

                  // ─── Unified shortcuts section ─────────────────────
                  if (!_isEditMode) ...[
                    Text(
                      'dashboard.quick_actions'.tr(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ─── Grid mode (normal) ────────────────────────────
                  if (!_isEditMode)
                    GridView.count(
                      crossAxisCount: crossAxisCount,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: isDesktop ? 1.3 : 1.1,
                      children: visibleItems.map((item) {
                        final color =
                            _resolveColor(item, colorScheme);
                        return _DashboardCard(
                          icon: item.icon,
                          title: item.titleKey.tr(),
                          color: color,
                          onTap: () => context.push(item.route),
                          onLongPress: _enterEditMode,
                        );
                      }).toList(),
                    ),

                  // ─── List mode (edit / reorder) ────────────────────
                  if (_isEditMode)
                    ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, index, animation) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) {
                            final scale =
                                Tween<double>(begin: 1.0, end: 1.05)
                                    .animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOut,
                            ));
                            return Transform.scale(
                              scale: scale.value,
                              child: Material(
                                color: Colors.transparent,
                                elevation: 8,
                                shadowColor: Colors.black26,
                                borderRadius:
                                    BorderRadius.circular(12),
                                child: child,
                              ),
                            );
                          },
                          child: child,
                        );
                      },
                      onReorder: (oldIndex, newIndex) {
                        // Convert visible indices to _items indices.
                        final visOld = visibleItems[oldIndex];
                        final realOld = _items.indexOf(visOld);

                        // Determine the real new index.
                        int realNew;
                        if (newIndex > oldIndex) {
                          // Moving down: insert after the item at
                          // newIndex-1 in the visible list.
                          final visAfter =
                              visibleItems[newIndex - 1];
                          realNew =
                              _items.indexOf(visAfter) + 1;
                        } else {
                          // Moving up: insert before the item at
                          // newIndex in the visible list.
                          final visBefore =
                              visibleItems[newIndex];
                          realNew = _items.indexOf(visBefore);
                        }

                        setState(() {
                          final item =
                              _items.removeAt(realOld);
                          if (realNew > realOld) realNew--;
                          _items.insert(realNew, item);
                        });
                        HapticFeedback.lightImpact();
                      },
                      itemCount: visibleItems.length,
                      itemBuilder: (context, index) {
                        final item = visibleItems[index];
                        final color =
                            _resolveColor(item, colorScheme);
                        return _EditModeListTile(
                          key: ValueKey(item.id),
                          index: index,
                          item: item,
                          color: color,
                          wobbleController: _wobbleController,
                        );
                      },
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Edit mode list tile – shows a card with drag handle for reordering.
// ═══════════════════════════════════════════════════════════════════════════════

class _EditModeListTile extends StatelessWidget {
  final int index;
  final DashboardItemData item;
  final Color color;
  final AnimationController wobbleController;

  const _EditModeListTile({
    super.key,
    required this.index,
    required this.item,
    required this.color,
    required this.wobbleController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AnimatedBuilder(
      animation: wobbleController,
      builder: (context, child) {
        // Each item gets a unique wobble phase for an organic feel.
        final wobble =
            math.sin(wobbleController.value * math.pi * 2 + index * 0.7) *
                0.008;
        return Transform.rotate(angle: wobble, child: child);
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          elevation: 1,
          color: colorScheme.surfaceContainerHighest,
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                    color.withAlpha(38), Colors.transparent),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.icon, size: 22, color: color),
            ),
            title: Text(
              item.titleKey.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  LucideIcons.gripVertical,
                  color: colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Dashboard card (normal grid mode)
// ═══════════════════════════════════════════════════════════════════════════════

class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
    this.onLongPress,
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
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                      color.withAlpha(38), Colors.transparent),
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
