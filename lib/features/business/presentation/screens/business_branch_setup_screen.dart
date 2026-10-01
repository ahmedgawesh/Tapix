import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart';

import '../../../../core/services/lan/lan_network_service.dart';
import '../../data/lan_branch_enrollment_service.dart';
import '../../data/warehouse_setup_service.dart';

class BusinessBranchSetupScreen extends StatefulWidget {
  const BusinessBranchSetupScreen({
    super.key,
    required this.service,
    this.enrollmentService,
    this.lanService,
  });

  final WarehouseSetupService service;
  final LanBranchEnrollmentService? enrollmentService;
  final LanNetworkService? lanService;

  @override
  State<BusinessBranchSetupScreen> createState() =>
      _BusinessBranchSetupScreenState();
}

class _BusinessBranchSetupScreenState extends State<BusinessBranchSetupScreen> {
  List<BusinessBranchOverview> _branches = const [];
  bool _loading = true;
  bool _canManageDirectory = false;
  bool _coordinatorBusy = false;
  String? _errorKey;
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _presenceTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshPresence(),
    );
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshPresence() async {
    if (_loading) return;
    try {
      final rows = await widget.service.branches();
      if (!mounted) return;
      setState(() => _branches = rows);
    } catch (_) {
      // Presence refresh is best effort. The explicit refresh action still
      // surfaces directory errors without replacing usable cached rows.
    }
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorKey = null;
      });
    }
    try {
      final rows = await widget.service.branches();
      final canManageDirectory = await widget.service.canCreateWarehouse();
      if (!mounted) return;
      setState(() {
        _branches = rows;
        _canManageDirectory = canManageDirectory;
      });
    } on WarehouseSetupDenied {
      if (mounted) {
        setState(() => _errorKey = 'business_locations.branch_setup.denied');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorKey = 'business_locations.branch_setup.load_failed',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => _CreateBranchDialog(service: widget.service),
    );
    if (created == true) await _load();
  }

  Future<void> _addWarehouse(BusinessBranchOverview branch) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _CreateWarehouseDialog(service: widget.service, branch: branch),
    );
    if (created == true) await _load();
  }

  Future<void> _manageCatalogue(BusinessBranchOverview item) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) =>
          _BranchCataloguePolicyDialog(service: widget.service, branch: item),
    );
    if (saved == true) await _load();
  }

  Future<void> _renameBranch(BusinessBranchOverview item) async {
    final renamed = await showDialog<bool>(
      context: context,
      builder: (context) => _RenameLocationDialog(
        titleKey: 'business_locations.branch_setup.rename_branch',
        labelKey: 'business_locations.branch_setup.branch_name',
        initialName: item.branch.name.isEmpty
            ? item.branch.code
            : item.branch.name,
        code: item.branch.code,
        onSave: (name) =>
            widget.service.renameBranch(branchId: item.branch.id, name: name),
      ),
    );
    if (renamed == true) await _load();
  }

  Future<void> _renameWarehouse(
    BusinessBranchOverview item,
    String warehouseId,
  ) async {
    final warehouse = item.visibleWarehouses.singleWhere(
      (row) => row.id == warehouseId,
    );
    final renamed = await showDialog<bool>(
      context: context,
      builder: (context) => _RenameLocationDialog(
        titleKey: 'business_locations.branch_setup.rename_warehouse',
        labelKey: 'business_locations.branch_setup.warehouse_name',
        initialName: warehouse.name.isEmpty ? warehouse.code : warehouse.name,
        code: warehouse.code,
        onSave: (name) => widget.service.renameWarehouse(
          warehouseId: warehouse.id,
          name: name,
        ),
      ),
    );
    if (renamed == true) await _load();
  }

  Future<void> _issueInvitation(BusinessBranchOverview item) async {
    final enrollment = widget.enrollmentService;
    final lan = widget.lanService;
    if (enrollment == null || lan == null) return;
    final coordinator = await _readyCoordinator(lan);
    if (coordinator == null) return;
    try {
      final invitation = await enrollment.issueInvitation(
        branchId: item.branch.id,
        warehouseId: item.defaultWarehouse.id,
      );
      await _showInvitation(
        invitation,
        coordinator.snapshot,
        coordinator.fingerprint,
      );
    } on LanBranchEnrollmentException catch (error) {
      if (!mounted) return;
      final key = error.code == 'branch_already_enrolled'
          ? 'business_locations.branch_setup.already_enrolled'
          : 'business_locations.branch_setup.invitation_failed';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(key.tr())));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'business_locations.branch_setup.invitation_failed'.tr(),
          ),
        ),
      );
    }
  }

  Future<void> _showInvitation(
    LanBranchInvitation invitation,
    LanNetworkSnapshot snapshot,
    String coordinatorFingerprint,
  ) async {
    final connection = LanBranchConnectionInvitation(
      hosts: snapshot.addresses,
      port: snapshot.port,
      coordinatorFingerprint: coordinatorFingerprint,
      branch: invitation,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _InvitationDialog(
        invitation: invitation,
        connectionCode: connection.encode(),
      ),
    );
  }

  Future<void> _replaceWriter(
    BusinessBranchOverview item, {
    bool restoreBackup = false,
  }) async {
    final enrollment = widget.enrollmentService;
    final lan = widget.lanService;
    if (enrollment == null || lan == null) return;
    final coordinator = await _readyCoordinator(lan);
    if (coordinator == null || !mounted) return;
    final reason = TextEditingController();
    final approved = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          (restoreBackup
                  ? 'business_locations.branch_setup.restore_backup_title'
                  : 'business_locations.branch_setup.replace_writer_title')
              .tr(),
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                (restoreBackup
                        ? 'business_locations.branch_setup.restore_backup_help'
                        : 'business_locations.branch_setup.replace_writer_help')
                    .tr(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reason,
                maxLength: 500,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText:
                      (restoreBackup
                              ? 'business_locations.branch_setup.restore_backup_reason'
                              : 'business_locations.branch_setup.replace_writer_reason')
                          .tr(),
                  border: const OutlineInputBorder(),
                ),
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
              final value = reason.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: Text(
              (restoreBackup
                      ? 'business_locations.branch_setup.restore_backup_confirm'
                      : 'business_locations.branch_setup.replace_writer_confirm')
                  .tr(),
            ),
          ),
        ],
      ),
    );
    reason.dispose();
    if (approved == null) return;
    try {
      final invitation = restoreBackup
          ? await enrollment.issueBackupRecoveryInvitation(
              branchId: item.branch.id,
              reason: approved,
            )
          : await enrollment.issueReplacementInvitation(
              branchId: item.branch.id,
              warehouseId: item.defaultWarehouse.id,
              reason: approved,
            );
      await _showInvitation(
        invitation,
        coordinator.snapshot,
        coordinator.fingerprint,
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'business_locations.branch_setup.replacement_failed'.tr(),
          ),
        ),
      );
    }
  }

  Future<({LanNetworkSnapshot snapshot, String fingerprint})?>
  _readyCoordinator(LanNetworkService lan) async {
    if (lan.snapshot.mode == LanMode.client) {
      _showCoordinatorMessage(
        'business_locations.branch_setup.client_cannot_coordinate',
      );
      return null;
    }

    // Branch enrollment uses the stable TLS identity of the coordinator.
    // Cashier pairing codes expire quickly and must not gate this workflow.
    try {
      if (lan.snapshot.mode == LanMode.standalone) {
        // Preparing a branch invitation is an explicit request to make this
        // device the company coordinator. Avoid forcing the owner through a
        // second, unrelated settings screen before the same operation.
        await lan.startMaster(port: lan.snapshot.port);
      } else {
        await lan.refreshMasterNetwork();
      }
    } catch (_) {
      _showCoordinatorMessage(
        'business_locations.branch_setup.coordinator_unavailable',
      );
      return null;
    }
    final snapshot = lan.snapshot;
    final fingerprint = lan.masterTlsFingerprint;
    if (snapshot.status != LanConnectionStatus.online ||
        snapshot.addresses.isEmpty ||
        fingerprint == null ||
        fingerprint.isEmpty) {
      _showCoordinatorMessage(
        'business_locations.branch_setup.coordinator_unavailable',
      );
      return null;
    }
    return (snapshot: snapshot, fingerprint: fingerprint);
  }

  Future<void> _activateCoordinator() async {
    final lan = widget.lanService;
    if (lan == null || _coordinatorBusy) return;
    setState(() => _coordinatorBusy = true);
    try {
      if (lan.snapshot.mode == LanMode.client) {
        _showCoordinatorMessage(
          'business_locations.branch_setup.client_cannot_coordinate',
        );
        return;
      }
      if (lan.snapshot.mode == LanMode.master) {
        await lan.refreshMasterNetwork();
      } else {
        await lan.startMaster(port: lan.snapshot.port);
      }
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      _showCoordinatorMessage(
        'business_locations.branch_setup.coordinator_unavailable',
      );
    } finally {
      if (mounted) setState(() => _coordinatorBusy = false);
    }
  }

  void _showCoordinatorMessage(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(key.tr())));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('business_locations.branch_setup.title'.tr()),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'business_locations.branch_setup.refresh'.tr(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _canManageDirectory
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : _create,
              icon: const Icon(Icons.add_business_outlined),
              label: Text('business_locations.branch_setup.add'.tr()),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
                      children: [
                        Card(
                          color: theme.colorScheme.secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.account_tree_outlined,
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'business_locations.branch_setup.explanation_title'
                                            .tr(),
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: theme
                                                  .colorScheme
                                                  .onSecondaryContainer,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'business_locations.branch_setup.explanation_body'
                                            .tr(),
                                        style: TextStyle(
                                          color: theme
                                              .colorScheme
                                              .onSecondaryContainer,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (widget.lanService != null) ...[
                          _CoordinatorStatusCard(
                            snapshot: widget.lanService!.snapshot,
                            busy: _coordinatorBusy,
                            onActivate: _activateCoordinator,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (!_canManageDirectory && _errorKey == null) ...[
                          _MessageCard(
                            icon: Icons.admin_panel_settings_outlined,
                            text:
                                'business_locations.branch_setup.coordinator_managed'
                                    .tr(),
                            color: theme.colorScheme.tertiaryContainer,
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_errorKey != null)
                          _MessageCard(
                            icon: Icons.error_outline,
                            text: _errorKey!.tr(),
                            color: theme.colorScheme.errorContainer,
                          )
                        else if (_branches.isEmpty)
                          _MessageCard(
                            icon: Icons.store_mall_directory_outlined,
                            text: 'business_locations.branch_setup.empty'.tr(),
                            color: theme.colorScheme.surfaceContainerHighest,
                          )
                        else
                          for (final item in _branches) ...[
                            _BranchCard(
                              item: item,
                              onAddWarehouse: _canManageDirectory
                                  ? () => _addWarehouse(item)
                                  : null,
                              onRenameBranch: _canManageDirectory
                                  ? () => _renameBranch(item)
                                  : null,
                              onManageCatalogue: _canManageDirectory
                                  ? () => _manageCatalogue(item)
                                  : null,
                              onRenameWarehouse: _canManageDirectory
                                  ? (warehouseId) =>
                                        _renameWarehouse(item, warehouseId)
                                  : null,
                              onPrepareConnection:
                                  widget.enrollmentService != null &&
                                      widget.lanService != null &&
                                      !item.isLocal &&
                                      item.connectionStatus != 'active'
                                  ? () => _issueInvitation(item)
                                  : null,
                              onReplaceWriter:
                                  widget.enrollmentService != null &&
                                      widget.lanService != null &&
                                      !item.isLocal &&
                                      item.connectionStatus == 'active'
                                  ? () => _replaceWriter(item)
                                  : null,
                              onRestoreBackup:
                                  widget.enrollmentService != null &&
                                      widget.lanService != null &&
                                      !item.isLocal &&
                                      item.connectionStatus == 'active'
                                  ? () => _replaceWriter(
                                      item,
                                      restoreBackup: true,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 10),
                          ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _CoordinatorStatusCard extends StatelessWidget {
  const _CoordinatorStatusCard({
    required this.snapshot,
    required this.busy,
    required this.onActivate,
  });

  final LanNetworkSnapshot snapshot;
  final bool busy;
  final VoidCallback onActivate;

  bool get _isReady =>
      snapshot.mode == LanMode.master &&
      snapshot.status == LanConnectionStatus.online &&
      snapshot.addresses.isNotEmpty;

  String get _titleKey => switch (snapshot.mode) {
    LanMode.master when _isReady =>
      'business_locations.branch_setup.coordinator_ready',
    LanMode.master =>
      'business_locations.branch_setup.coordinator_needs_network',
    LanMode.client =>
      'business_locations.branch_setup.coordinator_client_device',
    LanMode.standalone =>
      'business_locations.branch_setup.coordinator_standalone',
  };

  String get _bodyKey => switch (snapshot.mode) {
    LanMode.master when _isReady =>
      'business_locations.branch_setup.coordinator_ready_help',
    LanMode.master =>
      'business_locations.branch_setup.coordinator_needs_network_help',
    LanMode.client =>
      'business_locations.branch_setup.coordinator_client_device_help',
    LanMode.standalone =>
      'business_locations.branch_setup.coordinator_standalone_help',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _isReady
        ? Colors.green
        : snapshot.mode == LanMode.client
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    return Card(
      color: color.withValues(alpha: 0.11),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  _isReady
                      ? Icons.hub_outlined
                      : Icons.settings_ethernet_outlined,
                  color: color,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _titleKey.tr(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_bodyKey.tr()),
            if (_isReady && snapshot.addresses.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '${snapshot.addresses.join(' / ')}:${snapshot.port}',
                style: theme.textTheme.labelMedium,
              ),
            ],
            if (!_isReady && snapshot.mode != LanMode.client) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton.tonalIcon(
                  onPressed: busy ? null : onActivate,
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.power_settings_new),
                  label: Text(
                    (snapshot.mode == LanMode.master
                            ? 'business_locations.branch_setup.retry_coordinator'
                            : 'business_locations.branch_setup.activate_coordinator')
                        .tr(),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.item,
    this.onPrepareConnection,
    this.onReplaceWriter,
    this.onRestoreBackup,
    this.onAddWarehouse,
    this.onRenameBranch,
    this.onRenameWarehouse,
    this.onManageCatalogue,
  });

  final BusinessBranchOverview item;
  final VoidCallback? onPrepareConnection;
  final VoidCallback? onReplaceWriter;
  final VoidCallback? onRestoreBackup;
  final VoidCallback? onAddWarehouse;
  final VoidCallback? onRenameBranch;
  final ValueChanged<String>? onRenameWarehouse;
  final VoidCallback? onManageCatalogue;

  String get _statusKey => switch (item.connectionStatus) {
    'current' => 'business_locations.branch_setup.current',
    'active' => 'business_locations.branch_setup.registered',
    'pending' => 'business_locations.branch_setup.invitation_pending',
    'expired' => 'business_locations.branch_setup.invitation_expired_status',
    _ => 'business_locations.branch_setup.not_connected',
  };

  IconData get _statusIcon => switch (item.connectionStatus) {
    'current' || 'active' => Icons.check_circle_outline,
    'pending' => Icons.schedule_outlined,
    'expired' => Icons.timer_off_outlined,
    _ => Icons.link_off,
  };

  bool get _hasPresence => item.isLocal || item.connectionStatus == 'active';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  item.isLocal
                      ? Icons.home_work_outlined
                      : Icons.store_outlined,
                  color: theme.colorScheme.primary,
                ),
                Text(
                  item.branch.name.isEmpty
                      ? item.branch.code
                      : item.branch.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Chip(label: Text(item.branch.code)),
                Chip(
                  avatar: Icon(_statusIcon, size: 18),
                  label: Text(_statusKey.tr()),
                ),
                if (_hasPresence)
                  Chip(
                    backgroundColor: item.isOnline
                        ? Colors.green.withValues(alpha: 0.16)
                        : theme.colorScheme.errorContainer,
                    side: BorderSide(
                      color: item.isOnline
                          ? Colors.green
                          : theme.colorScheme.error,
                    ),
                    avatar: Icon(
                      Icons.circle,
                      size: 11,
                      color: item.isOnline
                          ? Colors.green
                          : theme.colorScheme.error,
                    ),
                    label: Text(
                      (item.isOnline
                              ? 'business_locations.branch_setup.online'
                              : 'business_locations.branch_setup.offline')
                          .tr(),
                    ),
                  ),
                Chip(
                  avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text(
                    (item.catalogueMode ==
                                BranchCatalogueMode.allCompanyProducts
                            ? 'business_locations.branch_setup.catalogue_all'
                            : 'business_locations.branch_setup.catalogue_managed')
                        .tr(),
                  ),
                ),
                if (onManageCatalogue != null)
                  TextButton.icon(
                    onPressed: onManageCatalogue,
                    icon: const Icon(Icons.tune_outlined),
                    label: Text(
                      'business_locations.branch_setup.manage_catalogue'.tr(),
                    ),
                  ),
                if (onRenameBranch != null)
                  IconButton(
                    onPressed: onRenameBranch,
                    tooltip: 'business_locations.branch_setup.rename_branch'
                        .tr(),
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'business_locations.branch_setup.warehouses_title'.tr(
                namedArgs: {'count': '${item.warehouseCount}'},
              ),
              style: theme.textTheme.labelLarge,
            ),
            for (final warehouse in item.visibleWarehouses)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  warehouse.locationKind == 'branch_store'
                      ? Icons.storefront_outlined
                      : Icons.warehouse_outlined,
                ),
                title: Text(
                  warehouse.locationKind == 'branch_store'
                      ? (item.branch.name.isEmpty
                            ? item.branch.code
                            : item.branch.name)
                      : (warehouse.name.isEmpty
                            ? warehouse.code
                            : warehouse.name),
                ),
                subtitle: Text(
                  warehouse.locationKind == 'branch_store'
                      ? '${'business_locations.branch_setup.default_badge'.tr()} · ${warehouse.code}'
                      : '${'warehouse_transfer.location_warehouse'.tr()} · ${warehouse.code}',
                ),
                trailing: onRenameWarehouse == null
                    ? null
                    : IconButton(
                        onPressed: () => onRenameWarehouse!(warehouse.id),
                        tooltip:
                            'business_locations.branch_setup.rename_warehouse'
                                .tr(),
                        icon: const Icon(Icons.edit_outlined),
                      ),
              ),
            if (!item.isLocal && item.connectionStatus != 'active')
              Text(
                (item.connectionStatus == 'pending'
                        ? 'business_locations.branch_setup.pending_help'
                        : 'business_locations.branch_setup.awaiting_enrollment')
                    .tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (onPrepareConnection != null ||
                onReplaceWriter != null ||
                onRestoreBackup != null ||
                onAddWarehouse != null) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (onAddWarehouse != null)
                      OutlinedButton.icon(
                        onPressed: onAddWarehouse,
                        icon: const Icon(Icons.add_business_outlined),
                        label: Text(
                          'business_locations.branch_setup.add_warehouse'.tr(),
                        ),
                      ),
                    if (onPrepareConnection != null)
                      FilledButton.tonalIcon(
                        onPressed: onPrepareConnection,
                        icon: const Icon(Icons.qr_code_2),
                        label: Text(
                          'business_locations.branch_setup.prepare_connection'
                              .tr(),
                        ),
                      ),
                    if (onReplaceWriter != null)
                      OutlinedButton.icon(
                        onPressed: onReplaceWriter,
                        icon: const Icon(Icons.phonelink_erase_outlined),
                        label: Text(
                          'business_locations.branch_setup.replace_writer'.tr(),
                        ),
                      ),
                    if (onRestoreBackup != null)
                      OutlinedButton.icon(
                        onPressed: onRestoreBackup,
                        icon: const Icon(Icons.restore_page_outlined),
                        label: Text(
                          'business_locations.branch_setup.restore_backup'.tr(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BranchCataloguePolicyDialog extends StatefulWidget {
  const _BranchCataloguePolicyDialog({
    required this.service,
    required this.branch,
  });

  final WarehouseSetupService service;
  final BusinessBranchOverview branch;

  @override
  State<_BranchCataloguePolicyDialog> createState() =>
      _BranchCataloguePolicyDialogState();
}

class _BranchCataloguePolicyDialogState
    extends State<_BranchCataloguePolicyDialog> {
  BranchCatalogueMode _mode = BranchCatalogueMode.allCompanyProducts;
  BranchCatalogueOptions? _options;
  final Set<int> _categories = {};
  final Set<int> _products = {};
  final TextEditingController _search = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        widget.service.cataloguePolicy(widget.branch.branch.id),
        widget.service.catalogueOptions(widget.branch.branch.id),
      ]);
      if (!mounted) return;
      final policy = values[0] as BranchCataloguePolicy;
      setState(() {
        _mode = policy.mode;
        _categories.addAll(policy.categoryIds);
        _products.addAll(policy.productIds);
        _options = values[1] as BranchCatalogueOptions;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorKey = 'business_locations.branch_setup.catalogue_load_failed';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_mode == BranchCatalogueMode.managedAssortment &&
        _categories.isEmpty &&
        _products.isEmpty) {
      setState(
        () => _errorKey =
            'business_locations.branch_setup.catalogue_selection_required',
      );
      return;
    }
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      await widget.service.saveCataloguePolicy(
        branchId: widget.branch.branch.id,
        policy: BranchCataloguePolicy(
          mode: _mode,
          categoryIds: _categories,
          productIds: _products,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorKey = 'business_locations.branch_setup.catalogue_save_failed';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = _options;
    final query = _search.text.trim().toLowerCase();
    bool matches(BranchCatalogueOption item) =>
        query.isEmpty ||
        item.name.toLowerCase().contains(query) ||
        (item.code ?? '').toLowerCase().contains(query);
    final categories = options?.categories.where(matches).toList() ?? const [];
    final products = options?.products.where(matches).toList() ?? const [];
    return AlertDialog(
      title: Text(
        'business_locations.branch_setup.catalogue_title'.tr(
          namedArgs: {
            'branch': widget.branch.branch.name.isEmpty
                ? widget.branch.branch.code
                : widget.branch.branch.name,
          },
        ),
      ),
      content: SizedBox(
        width: 680,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('business_locations.branch_setup.catalogue_help'.tr()),
                    const SizedBox(height: 16),
                    SegmentedButton<BranchCatalogueMode>(
                      segments: [
                        ButtonSegment(
                          value: BranchCatalogueMode.allCompanyProducts,
                          icon: const Icon(Icons.all_inclusive),
                          label: Text(
                            'business_locations.branch_setup.catalogue_all'
                                .tr(),
                          ),
                        ),
                        ButtonSegment(
                          value: BranchCatalogueMode.managedAssortment,
                          icon: const Icon(Icons.tune_outlined),
                          label: Text(
                            'business_locations.branch_setup.catalogue_managed'
                                .tr(),
                          ),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: _saving
                          ? null
                          : (values) => setState(() => _mode = values.single),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      (_mode == BranchCatalogueMode.allCompanyProducts
                              ? 'business_locations.branch_setup.catalogue_all_help'
                              : 'business_locations.branch_setup.catalogue_managed_help')
                          .tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_mode == BranchCatalogueMode.managedAssortment) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText:
                              'business_locations.branch_setup.catalogue_search'
                                  .tr(),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'business_locations.branch_setup.catalogue_categories'
                            .tr(),
                        style: theme.textTheme.titleSmall,
                      ),
                      for (final item in categories)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: _categories.contains(item.id),
                          title: Text(item.name),
                          onChanged: _saving
                              ? null
                              : (selected) => setState(() {
                                  if (selected == true) {
                                    _categories.add(item.id);
                                  } else {
                                    _categories.remove(item.id);
                                  }
                                }),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'business_locations.branch_setup.catalogue_products'
                            .tr(),
                        style: theme.textTheme.titleSmall,
                      ),
                      for (final item in products.take(200))
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: _products.contains(item.id),
                          title: Text(item.name),
                          subtitle: item.code == null ? null : Text(item.code!),
                          onChanged: _saving
                              ? null
                              : (selected) => setState(() {
                                  if (selected == true) {
                                    _products.add(item.id);
                                  } else {
                                    _products.remove(item.id);
                                  }
                                }),
                        ),
                    ],
                    if (_errorKey != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorKey!.tr(),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton.icon(
          onPressed: _loading || _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text('business_locations.branch_setup.catalogue_save'.tr()),
        ),
      ],
    );
  }
}

class _RenameLocationDialog extends StatefulWidget {
  const _RenameLocationDialog({
    required this.titleKey,
    required this.labelKey,
    required this.initialName,
    required this.code,
    required this.onSave,
  });

  final String titleKey;
  final String labelKey;
  final String initialName;
  final String code;
  final Future<Object?> Function(String name) onSave;

  @override
  State<_RenameLocationDialog> createState() => _RenameLocationDialogState();
}

class _RenameLocationDialogState extends State<_RenameLocationDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  bool _saving = false;
  String? _errorKey;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _name.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _name.text.length,
      );
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      await widget.onSave(_name.text);
      if (mounted) Navigator.pop(context, true);
    } on WarehouseDirectoryAuthorityRequired {
      if (mounted) {
        setState(
          () =>
              _errorKey = 'business_locations.branch_setup.coordinator_managed',
        );
      }
    } on StateError {
      if (mounted) {
        setState(
          () => _errorKey = 'business_locations.branch_setup.duplicate_name',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorKey = 'business_locations.branch_setup.rename_failed',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.titleKey.tr()),
    content: SizedBox(
      width: 440,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'business_locations.branch_setup.rename_help'.tr(
                namedArgs: {'code': widget.code},
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: true,
              maxLength: 100,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: widget.labelKey.tr(),
                border: const OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'business_locations.branch_setup.required'.tr()
                  : null,
            ),
            if (_errorKey != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorKey!.tr(),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: Text('common.cancel'.tr()),
      ),
      FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: Text('business_locations.branch_setup.save_name'.tr()),
      ),
    ],
  );
}

class _CreateWarehouseDialog extends StatefulWidget {
  const _CreateWarehouseDialog({required this.service, required this.branch});

  final WarehouseSetupService service;
  final BusinessBranchOverview branch;

  @override
  State<_CreateWarehouseDialog> createState() => _CreateWarehouseDialogState();
}

class _CreateWarehouseDialogState extends State<_CreateWarehouseDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _saving = false;
  String? _errorKey;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? 'business_locations.branch_setup.required'.tr()
      : null;

  String? _validateCode(String? value) {
    if (_required(value) case final message?) return message;
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$').hasMatch(value!.trim())) {
      return 'business_locations.branch_setup.invalid_code'.tr();
    }
    return null;
  }

  void _selectAll(TextEditingController controller) {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      await widget.service.createWarehouse(
        branchId: widget.branch.branch.id,
        name: _name.text,
        code: _code.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on WarehouseDirectoryAuthorityRequired {
      if (mounted) {
        setState(
          () =>
              _errorKey = 'business_locations.branch_setup.coordinator_managed',
        );
      }
    } on WarehouseSetupDenied {
      if (mounted) {
        setState(() => _errorKey = 'business_locations.branch_setup.denied');
      }
    } on StateError {
      if (mounted) {
        setState(
          () =>
              _errorKey = 'business_locations.branch_setup.duplicate_warehouse',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorKey =
              'business_locations.branch_setup.warehouse_save_failed',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchName = widget.branch.branch.name.isEmpty
        ? widget.branch.branch.code
        : widget.branch.branch.name;
    return AlertDialog(
      title: Text(
        'business_locations.branch_setup.warehouse_dialog_title'.tr(),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'business_locations.branch_setup.warehouse_dialog_help'.tr(
                    namedArgs: {'branch': branchName},
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.words,
                  onTap: () => _selectAll(_name),
                  validator: _required,
                  decoration: InputDecoration(
                    labelText: 'business_locations.branch_setup.warehouse_name'
                        .tr(),
                    prefixIcon: const Icon(Icons.warehouse_outlined),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _code,
                  maxLength: 32,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]')),
                  ],
                  onTap: () => _selectAll(_code),
                  validator: _validateCode,
                  decoration: InputDecoration(
                    labelText: 'business_locations.branch_setup.warehouse_code'
                        .tr(),
                    prefixIcon: const Icon(Icons.qr_code_2),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_errorKey != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorKey!.tr(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text('business_locations.branch_setup.create_warehouse'.tr()),
        ),
      ],
    );
  }
}

class _InvitationDialog extends StatelessWidget {
  const _InvitationDialog({
    required this.invitation,
    required this.connectionCode,
  });

  final LanBranchInvitation invitation;
  final String connectionCode;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('business_locations.branch_setup.invitation_title'.tr()),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'business_locations.branch_setup.invitation_help'.tr(
                namedArgs: {
                  'branch': invitation.branchName.isEmpty
                      ? invitation.branchCode
                      : invitation.branchName,
                },
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: connectionCode,
                  width: 220,
                  height: 220,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'business_locations.branch_setup.invitation_expires'.tr(
                namedArgs: {
                  'time': DateFormat.yMd().add_Hm().format(
                    invitation.expiresAt.toLocal(),
                  ),
                },
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            SelectableText(
              connectionCode,
              maxLines: 4,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton.icon(
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: connectionCode));
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'business_locations.branch_setup.invitation_copied'.tr(),
              ),
            ),
          );
        },
        icon: const Icon(Icons.copy),
        label: Text('business_locations.branch_setup.copy_invitation'.tr()),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: Text('common.ok'.tr()),
      ),
    ],
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    color: color,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    ),
  );
}

class _CreateBranchDialog extends StatefulWidget {
  const _CreateBranchDialog({required this.service});

  final WarehouseSetupService service;

  @override
  State<_CreateBranchDialog> createState() => _CreateBranchDialogState();
}

class _CreateBranchDialogState extends State<_CreateBranchDialog> {
  final _form = GlobalKey<FormState>();
  final _branchName = TextEditingController();
  final _branchCode = TextEditingController();
  bool _saving = false;
  String? _errorKey;

  @override
  void dispose() {
    _branchName.dispose();
    _branchCode.dispose();
    super.dispose();
  }

  void _selectAll(TextEditingController controller) {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? 'business_locations.branch_setup.required'.tr()
      : null;

  String? _code(String? value) {
    if (_required(value) case final message?) return message;
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$').hasMatch(value!.trim())) {
      return 'business_locations.branch_setup.invalid_code'.tr();
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      await widget.service.createBranchWithDefaultWarehouse(
        branchName: _branchName.text,
        branchCode: _branchCode.text,
        // The first stock location represents the branch itself.
        // Separate warehouses can be added later only when they physically exist.
        warehouseName: _branchName.text,
        warehouseCode: _branchCode.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on WarehouseSetupDenied {
      if (mounted) {
        setState(() => _errorKey = 'business_locations.branch_setup.denied');
      }
    } on StateError catch (error) {
      if (!mounted) return;
      setState(
        () => _errorKey = error.message.toString().contains('Branch')
            ? 'business_locations.branch_setup.duplicate_branch'
            : 'business_locations.branch_setup.duplicate_warehouse',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorKey = 'business_locations.branch_setup.save_failed',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool code = false,
  }) => TextFormField(
    controller: controller,
    maxLength: code ? 32 : 100,
    textCapitalization: code
        ? TextCapitalization.characters
        : TextCapitalization.words,
    inputFormatters: code
        ? [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_-]'))]
        : null,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: const OutlineInputBorder(),
    ),
    validator: code ? _code : _required,
    onTap: () => _selectAll(controller),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('business_locations.branch_setup.dialog_title'.tr()),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('business_locations.branch_setup.dialog_help'.tr()),
              const SizedBox(height: 16),
              _field(
                controller: _branchName,
                label: 'business_locations.branch_setup.branch_name'.tr(),
                icon: Icons.store_outlined,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _branchCode,
                label: 'business_locations.branch_setup.branch_code'.tr(),
                icon: Icons.tag,
                code: true,
              ),
              const SizedBox(height: 4),
              Text(
                'business_locations.branch_setup.branch_location_help'.tr(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_errorKey != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorKey!.tr(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context, false),
        child: Text('common.cancel'.tr()),
      ),
      FilledButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check),
        label: Text('business_locations.branch_setup.create'.tr()),
      ),
    ],
  );
}
