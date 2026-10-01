import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/lan/device_mode_reset_service.dart';

import '../../data/lan_branch_enrollment_service.dart';
import '../../data/lan_branch_provisioning_service.dart';

class LanBranchJoinScreen extends StatefulWidget {
  const LanBranchJoinScreen({super.key, required this.service});

  final LanBranchProvisioningService service;

  @override
  State<LanBranchJoinScreen> createState() => _LanBranchJoinScreenState();
}

class _LanBranchJoinScreenState extends State<LanBranchJoinScreen> {
  final _controller = TextEditingController();
  LanBranchConnectionInvitation? _preview;
  String? _errorKey;
  bool _submitting = false;

  bool get _cameraAvailable =>
      kIsWeb || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _inspect(String raw) {
    LanBranchConnectionInvitation? decoded;
    String? error;
    if (raw.trim().isNotEmpty) {
      try {
        decoded = LanBranchConnectionInvitation.decode(raw);
      } catch (_) {
        error = 'business_locations.branch_join.invalid_code';
      }
    }
    setState(() {
      _preview = decoded;
      _errorKey = error;
    });
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    _inspect(text);
  }

  Future<void> _scan() async {
    final value = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _BranchInvitationScanner()),
    );
    if (!mounted || value == null) return;
    _controller.text = value;
    _inspect(value);
  }

  Future<void> _join() async {
    if (_preview == null || _submitting) return;
    setState(() {
      _submitting = true;
      _errorKey = null;
    });
    try {
      final result = await widget.service.join(_controller.text);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.verified_outlined, size: 40),
          title: Text('business_locations.branch_join.success_title'.tr()),
          content: Text(
            (result.sharedDataReady
                    ? 'business_locations.branch_join.success_body'
                    : 'business_locations.branch_join.success_pending_body')
                .tr(
                  namedArgs: {
                    'branch': result.branchName,
                    'warehouse': result.warehouseName,
                  },
                ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('business_locations.branch_join.continue'.tr()),
            ),
          ],
        ),
      );
      await sl<DeviceModeResetService>().clearPendingTarget(
        FreshDeviceModeTarget.independentBranch,
      );
      if (mounted) context.go('/setup');
    } on LanBranchProvisioningException catch (error) {
      if (!mounted) return;
      setState(() => _errorKey = _errorFor(error.code));
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _errorKey = 'business_locations.branch_join.unknown_error',
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _errorFor(String code) => switch (code) {
    'pro_required' => 'business_locations.branch_join.pro_required',
    'fresh_database_required' =>
      'business_locations.branch_join.fresh_database_required',
    'invitation_expired' => 'business_locations.branch_join.invitation_expired',
    'branch_coordinator_unreachable' || 'coordinator_unreachable' =>
      'business_locations.branch_join.coordinator_unreachable',
    'branch_enrollment_not_supported' =>
      'business_locations.branch_join.coordinator_outdated',
    'cashier_client_denied' =>
      'business_locations.branch_join.cashier_client_denied',
    'identity_conflict' || 'database_identity_reused' =>
      'business_locations.branch_join.identity_conflict',
    _ => 'business_locations.branch_join.invalid_code',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = _preview?.branch;
    return Scaffold(
      appBar: AppBar(title: Text('business_locations.branch_join.title'.tr())),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primaryContainer,
                          theme.colorScheme.secondaryContainer,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.hub_outlined,
                          size: 38,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'business_locations.branch_join.hero_title'.tr(),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'business_locations.branch_join.hero_body'.tr(),
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.security_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'business_locations.branch_join.safety'.tr(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    minLines: 3,
                    maxLines: 5,
                    onChanged: _inspect,
                    decoration: InputDecoration(
                      labelText: 'business_locations.branch_join.code'.tr(),
                      hintText: 'business_locations.branch_join.code_hint'.tr(),
                      prefixIcon: const Icon(Icons.qr_code_2_outlined),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _submitting ? null : _paste,
                        icon: const Icon(Icons.content_paste_outlined),
                        label: Text(
                          'business_locations.branch_join.paste'.tr(),
                        ),
                      ),
                      if (_cameraAvailable)
                        OutlinedButton.icon(
                          onPressed: _submitting ? null : _scan,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(
                            'business_locations.branch_join.scan'.tr(),
                          ),
                        ),
                    ],
                  ),
                  if (_errorKey != null) ...[
                    const SizedBox(height: 14),
                    Card(
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          _errorKey!.tr(),
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (target != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'business_locations.branch_join.preview'.tr(),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _PreviewRow(
                              icon: Icons.business_outlined,
                              label: 'business_locations.branch_join.company'
                                  .tr(),
                              value: target.organizationName,
                            ),
                            _PreviewRow(
                              icon: Icons.store_outlined,
                              label: 'business_locations.branch_join.branch'
                                  .tr(),
                              value:
                                  '${target.branchName} · ${target.branchCode}',
                            ),
                            _PreviewRow(
                              icon: Icons.warehouse_outlined,
                              label: 'business_locations.branch_join.warehouse'
                                  .tr(),
                              value:
                                  '${target.warehouseName} · ${target.warehouseCode}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: target == null || _submitting ? null : _join,
                    icon: _submitting
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_outlined),
                    label: Text(
                      _submitting
                          ? 'business_locations.branch_join.connecting'.tr()
                          : 'business_locations.branch_join.join'.tr(),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}

class _BranchInvitationScanner extends StatefulWidget {
  const _BranchInvitationScanner();

  @override
  State<_BranchInvitationScanner> createState() =>
      _BranchInvitationScannerState();
}

class _BranchInvitationScannerState extends State<_BranchInvitationScanner> {
  final MobileScannerController _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _detected(BarcodeCapture capture) {
    if (_handled || capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('business_locations.branch_join.scan_title'.tr()),
    ),
    body: MobileScanner(controller: _scanner, onDetect: _detected),
  );
}
