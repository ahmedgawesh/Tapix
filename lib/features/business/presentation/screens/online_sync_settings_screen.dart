import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/online/online_branch_sync_service.dart';
import '../../../../core/services/online/online_setup_code.dart';
import '../../../../core/services/online/online_sync_controller.dart';
import '../../../../core/services/online/online_sync_gateway.dart';

class OnlineSyncSettingsScreen extends StatefulWidget {
  const OnlineSyncSettingsScreen({
    super.key,
    this.service,
    this.controller,
    this.pilotEnabled = OnlinePilot.enabled,
  });
  final OnlineBranchSyncService? service;
  final OnlineSyncController? controller;
  final bool pilotEnabled;
  @override
  State<OnlineSyncSettingsScreen> createState() =>
      _OnlineSyncSettingsScreenState();
}

class _OnlineSyncSettingsScreenState extends State<OnlineSyncSettingsScreen> {
  late final _service = widget.service ?? sl<OnlineBranchSyncService>();
  late final _sync = widget.controller ?? sl<OnlineSyncController>();
  final _code = TextEditingController();
  OnlineConnectionSummary? _connection;
  bool _busy = true, _authorized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _errorKey(Object error) {
    final code = error is OnlineSyncException
        ? error.code
        : 'online_sync_failed';
    return const {
          'owner_required': 'owner_required',
          'pro_required': 'pro_required',
          'online_writer_device_required': 'writer_required',
          'online_writer_not_enrolled': 'not_enrolled',
          'online_branch_not_enrolled': 'not_enrolled',
          'online_identity_mismatch': 'identity_mismatch',
          'online_invitation_expired': 'expired',
          'invalid_invitation': 'expired',
          'online_code_invalid': 'invalid_code',
          'online_entitlement_required': 'entitlement',
          'unauthorized': 'unauthorized',
          'online_connection_unavailable': 'connection_failed',
          'online_sync_busy': 'busy',
        }[code] ??
        'failed';
  }

  Future<void> _load() async {
    if (!widget.pilotEnabled) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'pilot_only';
        });
      }
      return;
    }
    try {
      await _service.authorizeConfiguration();
      final connection = await _service.inspectConnection();
      if (mounted) {
        setState(() {
          _authorized = true;
          _connection = connection;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = _errorKey(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _errorKey(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCode(OnlineSetupCode code) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'online_setup.${code.type == 'request' ? 'request_title' : 'invitation_title'}'
              .tr(),
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(code.name),
                const SizedBox(height: 12),
                Text(
                  'online_setup.${code.type == 'request' ? 'request_help' : 'invitation_help'}'
                      .tr(),
                ),
                const SizedBox(height: 12),
                SelectableText(code.encode(), textDirection: TextDirection.ltr),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code.encode()));
              if (context.mounted) Navigator.pop(context);
            },
            child: Text('online_setup.copy'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('online_setup.close'.tr()),
          ),
        ],
      ),
    );
  }

  Future<void> _connect() => _perform(() async {
    final code = OnlineSetupCode.decode(_code.text);
    if (code.type == 'request') {
      throw const OnlineSyncException('online_code_invalid');
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('online_setup.confirm'.tr()),
        content: Text(
          '${code.name}\n${code.endpoint?.origin}\n\n${'online_setup.confirm_help'.tr()}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('online_setup.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('online_setup.connect'.tr()),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    await _service.connectCode(_code.text);
    _code.clear();
    final connection = await _service.inspectConnection();
    if (mounted) setState(() => _connection = connection);
    _sync.start();
  });

  Future<void> _invite() => _perform(() async {
    final request = await showDialog<String>(
      context: context,
      builder: (_) => const _BranchRequestDialog(),
    );
    if (request == null || !mounted) return;
    final decoded = OnlineSetupCode.decode(request);
    if (decoded.type != 'request') {
      throw const OnlineSyncException('online_code_invalid');
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('online_setup.create_invitation'.tr()),
        content: Text(decoded.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('online_setup.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('online_setup.confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _showCode(await _service.issueInvitation(request));
    }
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('online_setup.title'.tr())),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('online_setup.pilot_help'.tr()),
              ),
            ),
            if (_busy && (ModalRoute.of(context)?.isCurrent ?? true))
              const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'online_setup.errors.$_error'.tr(),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_authorized) ...[
              if (_connection != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _connection!.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          _connection!.endpoint.origin,
                          textDirection: TextDirection.ltr,
                        ),
                        const SizedBox(height: 12),
                        AnimatedBuilder(
                          animation: _sync,
                          builder: (context, _) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'online_setup.status.${_sync.state.name}'.tr(),
                              ),
                              if (_sync.errorCode != null)
                                Text(
                                  'online_setup.errors.${_errorKey(OnlineSyncException(_sync.errorCode!))}'
                                      .tr(),
                                ),
                              if (_sync.lastSuccess != null)
                                Text(
                                  'online_setup.last_success'.tr(
                                    namedArgs: {
                                      'time':
                                          DateFormat.yMd(
                                            context.locale.toString(),
                                          ).add_Hms().format(
                                            _sync.lastSuccess!.toLocal(),
                                          ),
                                    },
                                  ),
                                ),
                              if (_sync.nextAttempt != null)
                                Text(
                                  'online_setup.next_attempt'.tr(
                                    namedArgs: {
                                      'time': DateFormat.Hms(
                                        context.locale.toString(),
                                      ).format(_sync.nextAttempt!.toLocal()),
                                    },
                                  ),
                                ),
                              const SizedBox(height: 12),
                              FilledButton.icon(
                                onPressed:
                                    _busy ||
                                        !_connection!.enabled ||
                                        _sync.state == OnlineSyncState.syncing
                                    ? null
                                    : () => _perform(_sync.refresh),
                                icon: const Icon(Icons.sync),
                                label: Text('online_setup.sync_now'.tr()),
                              ),
                            ],
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('online_setup.automatic'.tr()),
                          value: _connection!.enabled,
                          onChanged: _busy
                              ? null
                              : (value) => _perform(() async {
                                  await _service.setEnabled(value);
                                  final config = await _service
                                      .inspectConnection();
                                  if (mounted) {
                                    setState(() => _connection = config);
                                  }
                                  await _sync.refresh();
                                }),
                        ),
                        if (_connection!.role == 'owner')
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _invite,
                            icon: const Icon(Icons.add_link),
                            label: Text('online_setup.create_invitation'.tr()),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('online_setup.steps'.tr()),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _perform(
                        () async => _showCode(await _service.bindingRequest()),
                      ),
                icon: const Icon(Icons.share_outlined),
                label: Text('online_setup.request_title'.tr()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 8192,
                decoration: InputDecoration(
                  labelText: 'online_setup.code'.tr(),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: const Icon(Icons.link),
                label: Text('online_setup.connect'.tr()),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _BranchRequestDialog extends StatefulWidget {
  const _BranchRequestDialog();
  @override
  State<_BranchRequestDialog> createState() => _BranchRequestDialogState();
}

class _BranchRequestDialogState extends State<_BranchRequestDialog> {
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('online_setup.create_invitation'.tr()),
    content: TextField(
      controller: text,
      maxLines: 3,
      autocorrect: false,
      decoration: InputDecoration(
        labelText: 'online_setup.branch_request'.tr(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('online_setup.cancel'.tr()),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, text.text),
        child: Text('online_setup.next'.tr()),
      ),
    ],
  );
}
