import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/lan/lan_network_service.dart';
import '../../../auth/domain/entities/user_entity.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';

Future<void> showLanMasterDevicesSheet(BuildContext context) async {
  final authState = context.read<AuthBloc>().state;
  if (authState is! AuthAuthenticated) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _LanMasterDevicesSheet(actor: authState.user),
  );
}

class _LanMasterDevicesSheet extends StatefulWidget {
  const _LanMasterDevicesSheet({required this.actor});

  final UserEntity actor;

  @override
  State<_LanMasterDevicesSheet> createState() => _LanMasterDevicesSheetState();
}

class _LanMasterDevicesSheetState extends State<_LanMasterDevicesSheet> {
  late final LanNetworkService _service;
  StreamSubscription<LanNetworkSnapshot>? _subscription;
  Timer? _refreshTimer;
  List<LanMasterDeviceInfo> _devices = const [];
  String? _busyDeviceId;

  @override
  void initState() {
    super.initState();
    _service = sl<LanNetworkService>();
    _refresh();
    _subscription = _service.changes.listen((_) {
      if (mounted) _refresh();
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    final devices = _service.getMasterDevices();
    if (mounted) setState(() => _devices = devices);
  }

  Future<String?> _askText({
    required String titleKey,
    required String labelKey,
    String initialValue = '',
    bool required = true,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (_) => _LanTextPromptDialog(
        titleKey: titleKey,
        labelKey: labelKey,
        initialValue: initialValue,
        isRequired: required,
      ),
    );
  }

  Future<void> _rename(LanMasterDeviceInfo device) async {
    final name = await _askText(
      titleKey: 'settings.network.management.rename',
      labelKey: 'settings.network.management.device_name',
      initialValue: device.name,
    );
    if (name == null || name == device.name) return;
    await _run(
      device.id,
      () => _service.renameMasterDevice(
        deviceId: device.id,
        name: name,
        actorUserId: widget.actor.id,
        actorUsername: widget.actor.username,
      ),
    );
  }

  Future<void> _logout(LanMasterDeviceInfo device) async {
    final reason = await _askText(
      titleKey: 'settings.network.management.logout_title',
      labelKey: 'settings.network.management.reason',
    );
    if (reason == null) return;
    await _run(
      device.id,
      () => _service.logoutMasterDevice(
        deviceId: device.id,
        actorUserId: widget.actor.id,
        actorUsername: widget.actor.username,
        reason: reason,
      ),
    );
  }

  Future<void> _revoke(LanMasterDeviceInfo device) async {
    final reason = await _askText(
      titleKey: 'settings.network.management.revoke_title',
      labelKey: 'settings.network.management.reason',
    );
    if (reason == null) return;
    await _run(
      device.id,
      () => _service.revokeMasterDevice(
        deviceId: device.id,
        actorUserId: widget.actor.id,
        actorUsername: widget.actor.username,
        reason: reason,
      ),
    );
  }

  Future<void> _run(String deviceId, Future<bool> Function() operation) async {
    if (_busyDeviceId != null) return;
    setState(() => _busyDeviceId = deviceId);
    try {
      final success = await operation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'settings.network.management.success'.tr()
                : 'settings.network.management.no_change'.tr(),
          ),
        ),
      );
      _refresh();
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
      if (mounted) setState(() => _busyDeviceId = null);
    }
  }

  String _date(BuildContext context, DateTime? value) {
    if (value == null) return '—';
    return DateFormat('dd/MM/yyyy').add_jm().format(value.toLocal());
  }

  String _role(String? role) {
    if (role == null || role.isEmpty) {
      return 'settings.network.management.no_user'.tr();
    }
    return 'settings.network.role_$role'.tr();
  }

  IconData _platformIcon(String platform) {
    return switch (platform.toLowerCase()) {
      'android' => Icons.android,
      'windows' => Icons.window,
      'linux' => Icons.computer,
      'ios' || 'macos' => Icons.apple,
      _ => Icons.devices_other,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Icon(Icons.devices, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'settings.network.management.title'.tr(),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _refresh,
                  tooltip: 'common.refresh'.tr(),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: Text(
                      'settings.network.management.empty'.tr(),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _devices.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final busy = _busyDeviceId == device.id;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    child: Icon(_platformIcon(device.platform)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          device.name,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        Text(
                                          device.platform == 'unknown'
                                              ? 'settings.network.management.unknown_device'
                                                    .tr()
                                              : device.platform,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Chip(
                                    avatar: Icon(
                                      device.isConnected
                                          ? Icons.circle
                                          : Icons.circle_outlined,
                                      size: 12,
                                      color: device.isConnected
                                          ? Colors.green
                                          : theme.colorScheme.outline,
                                    ),
                                    label: Text(
                                      device.isConnected
                                          ? 'settings.network.connected'.tr()
                                          : 'settings.network.disconnected'
                                                .tr(),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 18,
                                runSpacing: 10,
                                children: [
                                  _Detail(
                                    icon: Icons.person_outline,
                                    label: 'settings.network.management.user'
                                        .tr(),
                                    value:
                                        device.employeeName ??
                                        device.username ??
                                        'settings.network.management.no_user'
                                            .tr(),
                                  ),
                                  _Detail(
                                    icon: Icons.admin_panel_settings_outlined,
                                    label: 'settings.network.role'.tr(),
                                    value: _role(device.userRole),
                                  ),
                                  _Detail(
                                    icon: Icons.lan_outlined,
                                    label: 'settings.network.management.ip'
                                        .tr(),
                                    value: device.remoteAddress ?? '—',
                                  ),
                                  _Detail(
                                    icon: Icons.schedule,
                                    label:
                                        'settings.network.management.last_seen'
                                            .tr(),
                                    value: device.isConnected
                                        ? 'settings.network.management.now'.tr()
                                        : _date(context, device.lastSeenAt),
                                  ),
                                  if (device.sessionStartedAt != null)
                                    _Detail(
                                      icon: Icons.login,
                                      label:
                                          'settings.network.management.signed_in_at'
                                              .tr(),
                                      value: _date(
                                        context,
                                        device.sessionStartedAt,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: busy
                                        ? null
                                        : () => _rename(device),
                                    icon: const Icon(Icons.edit_outlined),
                                    label: Text(
                                      'settings.network.management.rename'.tr(),
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: busy || !device.hasUserSession
                                        ? null
                                        : () => _logout(device),
                                    icon: const Icon(Icons.logout),
                                    label: Text(
                                      'settings.network.management.remote_logout'
                                          .tr(),
                                    ),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: busy
                                        ? null
                                        : () => _revoke(device),
                                    icon: const Icon(Icons.link_off),
                                    label: Text(
                                      'settings.network.management.revoke'.tr(),
                                    ),
                                  ),
                                  if (busy)
                                    const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: SizedBox.square(
                                        dimension: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LanTextPromptDialog extends StatefulWidget {
  const _LanTextPromptDialog({
    required this.titleKey,
    required this.labelKey,
    required this.initialValue,
    required this.isRequired,
  });

  final String titleKey;
  final String labelKey;
  final String initialValue;
  final bool isRequired;

  @override
  State<_LanTextPromptDialog> createState() => _LanTextPromptDialogState();
}

class _LanTextPromptDialogState extends State<_LanTextPromptDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final value = _controller.text.trim();
    if (widget.isRequired && value.isEmpty) {
      setState(() {
        _error = 'settings.network.management.required'.tr();
      });
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titleKey.tr()),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 160,
        decoration: InputDecoration(
          labelText: widget.labelKey.tr(),
          errorText: _error,
        ),
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(onPressed: _confirm, child: Text('common.confirm'.tr())),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 170),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Flexible(child: Text('$label: $value')),
        ],
      ),
    );
  }
}
