import 'dart:async';
import 'dart:ui' as ui show TextDirection;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:mobile_scanner/mobile_scanner.dart' hide Barcode;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../../core/services/lan/device_mode_reset_service.dart';
import '../../../../core/utils/app_restart.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/domain/entities/user_entity.dart';
import 'lan_master_devices_sheet.dart';

class LanNetworkSettingsScreen extends StatefulWidget {
  const LanNetworkSettingsScreen({super.key, this.clientOnly = false});

  /// Pre-login mode only permits joining an existing master.
  final bool clientOnly;

  @override
  State<LanNetworkSettingsScreen> createState() =>
      _LanNetworkSettingsScreenState();
}

class _LanNetworkSettingsScreenState extends State<LanNetworkSettingsScreen> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '45820');
  final _codeController = TextEditingController();
  final _deviceNameController = TextEditingController();
  late final LanNetworkService _service;
  StreamSubscription<LanNetworkSnapshot>? _subscription;
  late LanNetworkSnapshot _snapshot;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service = sl<LanNetworkService>();
    _snapshot = _service.snapshot;
    _hydrateControllers(_snapshot);
    if (_snapshot.mode == LanMode.master) {
      unawaited(_service.refreshMasterNetwork());
    }
    _subscription = _service.changes.listen((snapshot) {
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
      _hydrateControllers(snapshot, overwrite: false);
    });
  }

  void _hydrateControllers(
    LanNetworkSnapshot snapshot, {
    bool overwrite = true,
  }) {
    if ((overwrite || _hostController.text.isEmpty) &&
        snapshot.masterHost != null) {
      _hostController.text = snapshot.masterHost!;
    }
    if (overwrite || _portController.text.isEmpty) {
      _portController.text = snapshot.port.toString();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _hostController.dispose();
    _portController.dispose();
    _codeController.dispose();
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'settings.network.operation_failed'.tr(args: [error.toString()]),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startMaster() => _run(() async {
    final port = int.tryParse(_portController.text.trim()) ?? 45820;
    await _service.startMaster(port: port);
  });

  Future<void> _pairClient() => _run(() async {
    final port = int.tryParse(_portController.text.trim()) ?? 45820;
    final result = await _service.pairWithMaster(
      host: _hostController.text,
      port: port,
      pairingCode: _codeController.text,
      deviceName: _deviceNameController.text,
    );
    if (!mounted) return;
    final failure = result.message == 'invalid_device_name'
        ? 'settings.network.invalid_device_name'.tr()
        : result.message ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? 'settings.network.pair_success'.tr()
              : 'settings.network.pair_failed'.tr(args: [failure]),
        ),
      ),
    );
    if (result.success && widget.clientOnly) {
      context.read<AuthBloc>().add(const AuthCheckRequested());
      context.go('/login');
    }
  });

  Future<void> _testConnection() => _run(() async {
    final success = await _service.testConnection(
      host: _hostController.text,
      port: int.tryParse(_portController.text.trim()),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'settings.network.test_success'.tr()
              : 'settings.network.test_failed'.tr(),
        ),
      ),
    );
  });

  Future<void> _confirmFreshReset(FreshDeviceModeTarget target) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated ||
        authState.user.role != UserRole.owner ||
        _snapshot.mode != LanMode.client) {
      context.go('/access-denied');
      return;
    }

    final targetKey = target == FreshDeviceModeTarget.master
        ? 'settings.network.fresh_reset.master_target'
        : 'settings.network.fresh_reset.standalone_target';
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: Text('settings.network.fresh_reset.confirm_title'.tr()),
        content: Text(
          'settings.network.fresh_reset.confirm_message'.tr(
            namedArgs: {'target': targetKey.tr()},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('settings.network.fresh_reset.confirm_action'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _run(() async {
      await sl<DeviceModeResetService>().resetClientToFreshDatabase(
        target: target,
        actorRole: authState.user.role,
      );
      await closeAppForFreshRestart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = context.watch<AuthBloc>().state;
    final ownerClientReset =
        !widget.clientOnly &&
        _snapshot.mode == LanMode.client &&
        authState is AuthAuthenticated &&
        authState.user.role == UserRole.owner;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go(widget.clientOnly ? '/login' : '/dashboard'),
        ),
        title: Text('settings.network.title'.tr()),
        centerTitle: true,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text('settings.network.phase_notice'.tr())),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!widget.clientOnly) ...[
              if (ownerClientReset) ...[
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.admin_panel_settings_outlined,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'settings.network.fresh_reset.owner_notice'.tr(),
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _RoleCard(
                title: 'settings.network.standalone'.tr(),
                subtitle: ownerClientReset
                    ? 'settings.network.fresh_reset.standalone_desc'.tr()
                    : 'settings.network.standalone_desc'.tr(),
                icon: Icons.smartphone,
                selected: _snapshot.mode == LanMode.standalone,
                onTap: ownerClientReset
                    ? () => _confirmFreshReset(FreshDeviceModeTarget.standalone)
                    : () => _run(_service.setStandalone),
              ),
              const SizedBox(height: 12),
              _RoleCard(
                title: 'settings.network.master'.tr(),
                subtitle: ownerClientReset
                    ? 'settings.network.fresh_reset.master_desc'.tr()
                    : 'settings.network.master_desc'.tr(),
                icon: Icons.dns_outlined,
                selected: _snapshot.mode == LanMode.master,
                trailing: _snapshot.mode == LanMode.master
                    ? _statusChip(context)
                    : null,
                onTap: ownerClientReset
                    ? () => _confirmFreshReset(FreshDeviceModeTarget.master)
                    : (_snapshot.mode == LanMode.master ? () {} : _startMaster),
                child: ownerClientReset ? null : _buildMasterControls(context),
              ),
              const SizedBox(height: 12),
            ],
            _RoleCard(
              title: 'settings.network.client'.tr(),
              subtitle: 'settings.network.client_desc'.tr(),
              icon: Icons.point_of_sale_outlined,
              selected: _snapshot.mode == LanMode.client,
              trailing: _snapshot.mode == LanMode.client
                  ? _statusChip(context)
                  : null,
              onTap: () {},
              child: _buildClientControls(context),
            ),
            if (_busy) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMasterControls(BuildContext context) {
    if (_snapshot.mode != LanMode.master) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton.icon(
          onPressed: _startMaster,
          icon: const Icon(Icons.play_arrow),
          label: Text('settings.network.start_master'.tr()),
        ),
      );
    }

    final addresses = _snapshot.addresses;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'settings.network.same_wifi_hint'.tr(),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          _InfoRow(
            label: 'settings.network.address'.tr(),
            value: addresses.isEmpty
                ? 'settings.network.no_address'.tr()
                : addresses.join(' / '),
          ),
          _InfoRow(
            label: 'settings.network.port'.tr(),
            value: _snapshot.port.toString(),
          ),
          Text('settings.network.pairing_code'.tr()),
          const SizedBox(height: 8),
          SelectableText(
            _snapshot.pairingCode ?? '—',
            textDirection: ui.TextDirection.ltr,
          ),
          if (_snapshot.pairingCode != null)
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: _snapshot.pairingCode!,
                  width: 180,
                  height: 180,
                  color: Colors.black,
                ),
              ),
            ),
          Text('settings.network.secure_pairing_hint'.tr()),
          TextButton.icon(
            onPressed: _snapshot.pairingCode == null
                ? null
                : () => Clipboard.setData(
                    ClipboardData(text: _snapshot.pairingCode!),
                  ),
            icon: const Icon(Icons.copy),
            label: Text('settings.network.copy_code'.tr()),
          ),
          _InfoRow(
            label: 'settings.network.authorized_devices'.tr(),
            value: _snapshot.pairedDevices.toString(),
          ),
          _InfoRow(
            label: 'settings.network.connected_devices'.tr(),
            value: _snapshot.connectedDevices.toString(),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => showLanMasterDevicesSheet(context),
            icon: const Icon(Icons.manage_accounts_outlined),
            label: Text('settings.network.management.open'.tr()),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _run(_service.refreshMasterNetwork),
                icon: const Icon(Icons.wifi_find),
                label: Text('settings.network.refresh_address'.tr()),
              ),
              OutlinedButton.icon(
                onPressed: () => _run(_service.regeneratePairingCode),
                icon: const Icon(Icons.refresh),
                label: Text('settings.network.new_code'.tr()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _scanPairingCode() async {
    var captured = false;
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (scannerContext) => Scaffold(
          appBar: AppBar(title: Text('settings.network.scan_code'.tr())),
          body: MobileScanner(
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final code = barcode.rawValue?.trim().toLowerCase();
                if (!captured &&
                    code != null &&
                    RegExp(r'^[0-9]{6}:[a-f0-9]{64}$').hasMatch(code)) {
                  captured = true;
                  Navigator.of(scannerContext).pop(code);
                  break;
                }
              }
            },
          ),
        ),
      ),
    );
    if (mounted && code != null) _codeController.text = code;
  }

  Widget _buildClientControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          TextField(
            controller: _hostController,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'settings.network.master_address'.tr(),
              hintText: '192.168.1.10',
              prefixIcon: const Icon(Icons.wifi),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'settings.network.port'.tr(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.text,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLines: 3,
                  minLines: 1,
                  maxLength: 71,
                  decoration: InputDecoration(
                    labelText: 'settings.network.pairing_code'.tr(),
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: 'settings.network.paste_code'.tr(),
                      icon: const Icon(Icons.content_paste),
                      onPressed: () async {
                        final data = await Clipboard.getData(
                          Clipboard.kTextPlain,
                        );
                        if (mounted && data?.text != null) {
                          _codeController.text = data!.text!.trim();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.android ||
                  defaultTargetPlatform == TargetPlatform.iOS))
            TextButton.icon(
              onPressed: _scanPairingCode,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text('settings.network.scan_code'.tr()),
            ),
          TextField(
            controller: _deviceNameController,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: 'settings.network.device_name'.tr(),
              hintText: 'settings.network.device_name_hint'.tr(),
              prefixIcon: const Icon(Icons.badge_outlined),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _pairClient,
              icon: const Icon(Icons.link),
              label: Text('settings.network.pair'.tr()),
            ),
          ),
          if (_snapshot.mode == LanMode.client) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testConnection,
                icon: const Icon(Icons.network_check),
                label: Text('settings.network.test'.tr()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context) {
    final ok =
        _snapshot.status == LanConnectionStatus.online ||
        _snapshot.status == LanConnectionStatus.paired;
    return Chip(
      avatar: Icon(
        ok ? Icons.check_circle : Icons.error_outline,
        size: 18,
        color: ok ? Colors.green : Theme.of(context).colorScheme.error,
      ),
      label: Text(
        ok
            ? (_snapshot.mode == LanMode.master
                  ? 'settings.network.master_ready'.tr()
                  : 'settings.network.connected'.tr())
            : 'settings.network.disconnected'.tr(),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.trailing,
    this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: selected ? colors.primaryContainer.withValues(alpha: 0.35) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(icon, color: colors.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(subtitle),
                      ],
                    ),
                  ),
                  trailing ?? const SizedBox.shrink(),
                ],
              ),
              child ?? const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
