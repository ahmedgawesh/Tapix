import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart' show BusinessWarehouse;
import '../../../../core/di/injection_container.dart';
import '../../../settings/presentation/screens/lan_network_settings_screen.dart';
import '../../data/online_branches_entitlement.dart';
import '../../data/online_branches_purchase_service.dart';
import '../../data/warehouse_setup_service.dart';
import '../../data/warehouse_transfer_application_service.dart';
import 'warehouse_reports_screen.dart';
import 'warehouse_setup_screen.dart';
import 'warehouse_transfer_screen.dart';

class BusinessLocationsHubScreen extends StatefulWidget {
  const BusinessLocationsHubScreen({
    super.key,
    this.setupService,
    this.transferService,
    this.onlineEntitlement,
    this.purchaseService,
  });

  final WarehouseSetupService? setupService;
  final WarehouseTransferApplicationService? transferService;
  final OnlineBranchesEntitlement? onlineEntitlement;
  final OnlineBranchesPurchaseService? purchaseService;

  @override
  State<BusinessLocationsHubScreen> createState() =>
      _BusinessLocationsHubScreenState();
}

class _BusinessLocationsHubScreenState
    extends State<BusinessLocationsHubScreen> {
  late final WarehouseSetupService _setup =
      widget.setupService ?? sl<WarehouseSetupService>();
  late final WarehouseTransferApplicationService _transfers =
      widget.transferService ?? sl<WarehouseTransferApplicationService>();
  late final OnlineBranchesEntitlement _online =
      widget.onlineEntitlement ?? sl<OnlineBranchesEntitlement>();
  late final OnlineBranchesPurchaseService _purchases =
      widget.purchaseService ?? sl<OnlineBranchesPurchaseService>();

  OnlineBranchesEntitlementSnapshot? _entitlement;
  bool _loadingEntitlement = true;
  bool _purchaseBusy = false;

  @override
  void initState() {
    super.initState();
    _loadEntitlement();
  }

  Future<void> _loadEntitlement() async {
    if (mounted) setState(() => _loadingEntitlement = true);
    try {
      final snapshot = await _online.inspect();
      if (mounted) setState(() => _entitlement = snapshot);
    } catch (_) {
      if (mounted) setState(() => _entitlement = null);
    } finally {
      if (mounted) setState(() => _loadingEntitlement = false);
    }
  }

  void _showMessage(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(key.tr())));
  }

  Future<void> _showPlans() async {
    if (_purchaseBusy) return;
    setState(() => _purchaseBusy = true);
    List<OnlineBranchesPlan> plans;
    try {
      plans = await _purchases.loadPlans();
    } catch (_) {
      plans = const [];
    }
    if (!mounted) return;
    setState(() => _purchaseBusy = false);
    if (plans.isEmpty) {
      final opened = await _purchases.openManagement();
      if (!opened) _showMessage('business_locations.plans_unavailable');
      return;
    }
    final selected = await showModalBottomSheet<OnlineBranchesPlan>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              'business_locations.choose_plan'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final plan in plans)
              Card(
                child: ListTile(
                  title: Text(plan.title),
                  subtitle: Text(plan.description),
                  trailing: Text(
                    plan.price,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  onTap: () => Navigator.pop(context, plan),
                ),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _purchaseBusy = true);
    final outcome = await _purchases.purchase(selected.id);
    if (!mounted) return;
    setState(() => _purchaseBusy = false);
    await _handlePurchaseOutcome(outcome);
  }

  Future<void> _restore() async {
    if (_purchaseBusy) return;
    setState(() => _purchaseBusy = true);
    final outcome = await _purchases.restore();
    if (!mounted) return;
    setState(() => _purchaseBusy = false);
    await _handlePurchaseOutcome(outcome);
  }

  Future<void> _handlePurchaseOutcome(
    OnlineBranchesPurchaseOutcome outcome,
  ) async {
    final key = switch (outcome.result) {
      OnlineBranchesStoreResult.success =>
        'business_locations.purchase_activated',
      OnlineBranchesStoreResult.cancelled =>
        'business_locations.purchase_cancelled',
      OnlineBranchesStoreResult.unavailable =>
        'business_locations.plans_unavailable',
      OnlineBranchesStoreResult.failed => 'business_locations.purchase_failed',
    };
    _showMessage(key);
    await _loadEntitlement();
  }

  Future<void> _manage() async {
    final opened = await _purchases.openManagement();
    if (!opened) _showMessage('business_locations.management_unavailable');
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _openReports() async {
    List<BusinessWarehouse> warehouses;
    try {
      warehouses = await _setup.warehouses();
    } catch (_) {
      warehouses = const [];
    }
    if (!mounted) return;
    if (warehouses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('business_locations.no_report_warehouses'.tr())),
      );
      return;
    }
    BusinessWarehouse? selected;
    if (warehouses.length == 1) {
      selected = warehouses.single;
    } else {
      selected = await showModalBottomSheet<BusinessWarehouse>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                'business_locations.choose_report_warehouse'.tr(),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final warehouse in warehouses)
                ListTile(
                  leading: const Icon(Icons.warehouse_outlined),
                  title: Text(
                    warehouse.name.isEmpty ? warehouse.code : warehouse.name,
                  ),
                  subtitle: Text(warehouse.code),
                  onTap: () => Navigator.pop(context, warehouse),
                ),
            ],
          ),
        ),
      );
    }
    if (!mounted || selected == null) return;
    _open(WarehouseReportsScreen(service: _setup, warehouseId: selected.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('business_locations.title'.tr()),
        actions: [
          IconButton(
            onPressed: _loadingEntitlement ? null : _loadEntitlement,
            tooltip: 'business_locations.refresh_license'.tr(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: _LocalOperationsHeader(theme: theme),
                  ),
                ),
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  sliver: SliverToBoxAdapter(child: _PrimaryWarehouseNotice()),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.crossAxisExtent;
                      final columns = width >= 960
                          ? 3
                          : width >= 600
                          ? 2
                          : 1;
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          mainAxisExtent: 190,
                        ),
                        delegate: SliverChildListDelegate.fixed([
                          _ActionCard(
                            icon: Icons.warehouse_outlined,
                            title: 'business_locations.warehouses'.tr(),
                            body: 'business_locations.warehouses_help'.tr(),
                            onTap: () =>
                                _open(WarehouseSetupScreen(service: _setup)),
                          ),
                          _ActionCard(
                            icon: Icons.move_down_outlined,
                            title: 'business_locations.transfers'.tr(),
                            body: 'business_locations.transfers_help'.tr(),
                            onTap: () => _open(
                              WarehouseTransferScreen(service: _transfers),
                            ),
                          ),
                          _ActionCard(
                            icon: Icons.analytics_outlined,
                            title: 'business_locations.reports'.tr(),
                            body: 'business_locations.reports_help'.tr(),
                            onTap: _openReports,
                          ),
                          _ActionCard(
                            icon: Icons.devices_other_outlined,
                            title: 'business_locations.devices'.tr(),
                            body: 'business_locations.devices_help'.tr(),
                            onTap: () =>
                                _open(const LanNetworkSettingsScreen()),
                          ),
                        ]),
                      );
                    },
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverToBoxAdapter(
                    child: _OnlineAddOnCard(
                      loading: _loadingEntitlement,
                      purchaseBusy: _purchaseBusy,
                      snapshot: _entitlement,
                      onRefresh: _loadEntitlement,
                      onPlans: _showPlans,
                      onRestore: _restore,
                      onManage: _manage,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LocalOperationsHeader extends StatelessWidget {
  const _LocalOperationsHeader({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              child: const Icon(Icons.hub_outlined),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'business_locations.local_title'.tr(),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('business_locations.local_help'.tr()),
                  const SizedBox(height: 10),
                  Chip(
                    avatar: const Icon(Icons.verified_outlined, size: 18),
                    label: Text('business_locations.included_in_pro'.tr()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryWarehouseNotice extends StatelessWidget {
  const _PrimaryWarehouseNotice();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.secondaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: colors.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'business_locations.primary_warehouse_title'.tr(),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'business_locations.primary_warehouse_help'.tr(),
                    style: TextStyle(color: colors.onSecondaryContainer),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(height: 14),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(body, maxLines: 4, overflow: TextOverflow.ellipsis),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Icon(
                  Icons.arrow_forward,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnlineAddOnCard extends StatelessWidget {
  const _OnlineAddOnCard({
    required this.loading,
    required this.purchaseBusy,
    required this.snapshot,
    required this.onRefresh,
    required this.onPlans,
    required this.onRestore,
    required this.onManage,
  });

  final bool loading;
  final bool purchaseBusy;
  final OnlineBranchesEntitlementSnapshot? snapshot;
  final VoidCallback onRefresh;
  final VoidCallback onPlans;
  final VoidCallback onRestore;
  final VoidCallback onManage;

  String _statusKey() => switch (snapshot?.state) {
    OnlineBranchesEntitlementState.active =>
      'business_locations.online_status.active',
    OnlineBranchesEntitlementState.baseProRequired =>
      'business_locations.online_status.base_pro_required',
    OnlineBranchesEntitlementState.expired =>
      'business_locations.online_status.expired',
    OnlineBranchesEntitlementState.unavailable =>
      'business_locations.online_status.unavailable',
    _ => 'business_locations.online_status.add_on_required',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = snapshot?.permitsOnlineBranches ?? false;
    final expiry = snapshot?.expirationDate;
    return Card(
      color: active
          ? theme.colorScheme.tertiaryContainer
          : theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_outlined,
                  color: active
                      ? theme.colorScheme.onTertiaryContainer
                      : theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'business_locations.online_title'.tr(),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (loading)
                  const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Chip(label: Text(_statusKey().tr())),
              ],
            ),
            const SizedBox(height: 10),
            Text('business_locations.online_help'.tr()),
            if (!loading && snapshot == null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: Text('business_locations.retry'.tr()),
              ),
            ],
            if (snapshot != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (expiry != null)
                    Chip(
                      label: Text(
                        'business_locations.expires'.tr(
                          namedArgs: {
                            'date': DateFormat.yMMMd(
                              context.locale.toString(),
                            ).format(expiry.toLocal()),
                          },
                        ),
                      ),
                    ),
                  if (snapshot!.willRenew)
                    Chip(label: Text('business_locations.renews'.tr())),
                  if (snapshot!.maxBranches != null)
                    Chip(
                      label: Text(
                        'business_locations.branch_limit'.tr(
                          namedArgs: {
                            'count': snapshot!.maxBranches.toString(),
                          },
                        ),
                      ),
                    ),
                  if (snapshot!.maxWarehouses != null)
                    Chip(
                      label: Text(
                        'business_locations.warehouse_limit'.tr(
                          namedArgs: {
                            'count': snapshot!.maxWarehouses.toString(),
                          },
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'business_locations.local_unaffected'.tr(),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (active)
                    FilledButton.icon(
                      onPressed: purchaseBusy ? null : onManage,
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: Text('business_locations.manage_plan'.tr()),
                    )
                  else
                    FilledButton.icon(
                      onPressed: purchaseBusy ? null : onPlans,
                      icon: const Icon(Icons.shopping_cart_outlined),
                      label: Text('business_locations.view_plans'.tr()),
                    ),
                  OutlinedButton.icon(
                    onPressed: purchaseBusy ? null : onRestore,
                    icon: const Icon(Icons.restore),
                    label: Text('business_locations.restore_purchase'.tr()),
                  ),
                  if (purchaseBusy)
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
