import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/business/branch_consignment_policy_store.dart';
import '../../../consignment/data/consignment_module_service.dart';
import 'settings_widgets.dart';

class ConsignmentSettingsSection extends StatefulWidget {
  const ConsignmentSettingsSection({super.key});

  @override
  State<ConsignmentSettingsSection> createState() =>
      _ConsignmentSettingsSectionState();
}

class _ConsignmentSettingsSectionState
    extends State<ConsignmentSettingsSection> {
  late Future<_ConsignmentSettingState> _state = _load();
  bool _saving = false;

  Future<_ConsignmentSettingState> _load() async {
    final module = sl<ConsignmentModuleService>();
    final policy = await module.initialize();
    return _ConsignmentSettingState(
      snapshot: policy,
      licensed: await module.canEnable(),
    );
  }

  Future<void> _change(bool enabled) async {
    if (_saving) return;
    final current = await _state;
    if (enabled && !current.licensed) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(LucideIcons.badgeDollarSign),
          title: Text('consignment.license_required'.tr()),
          content: Text('consignment.license_required_desc'.tr()),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text('common.ok'.tr()),
            ),
          ],
        ),
      );
      return;
    }
    final reason = await _reasonDialog(enabled);
    if (reason == null || !mounted) return;

    // Navigator completes the dialog future before its reverse transition has
    // necessarily left the Overlay. Wait one frame before rebuilding this
    // settings subtree so overlay entries are never reparented mid-frame.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(() => _saving = true);

    var saved = false;
    try {
      await sl<ConsignmentModuleService>().setEnabled(
        enabled: enabled,
        reason: reason,
      );
      saved = true;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('consignment.operation_failed'.tr())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          if (saved) _state = _load();
        });
      }
    }
  }

  Future<String?> _reasonDialog(bool enabled) => showDialog<String>(
    context: context,
    builder: (context) => _ConsignmentReasonDialog(enabled: enabled),
  );

  @override
  Widget build(BuildContext context) {
    return SettingsExpansionCard(
      title: 'consignment.settings_title'.tr(),
      icon: LucideIcons.packageCheck,
      children: [
        FutureBuilder<_ConsignmentSettingState>(
          future: _state,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: LinearProgressIndicator(),
              );
            }
            final data = snapshot.data!;
            final enabled = data.snapshot.policy.enabled;
            return Column(
              children: [
                SwitchListTile(
                  key: const ValueKey('consignment-module-switch'),
                  title: Text('consignment.enable'.tr()),
                  subtitle: Text('consignment.enable_desc'.tr()),
                  value: enabled,
                  onChanged: _saving ? null : _change,
                  secondary: _saving
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          data.licensed
                              ? LucideIcons.shieldCheck
                              : LucideIcons.lockKeyhole,
                        ),
                ),
                if (!data.licensed)
                  ListTile(
                    leading: const Icon(LucideIcons.badgeDollarSign),
                    title: Text('consignment.pro_required'.tr()),
                    subtitle: Text('consignment.pro_required_desc'.tr()),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'consignment.compatibility_note'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ConsignmentSettingState {
  const _ConsignmentSettingState({
    required this.snapshot,
    required this.licensed,
  });

  final BranchConsignmentPolicySnapshot snapshot;
  final bool licensed;
}

class _ConsignmentReasonDialog extends StatefulWidget {
  const _ConsignmentReasonDialog({required this.enabled});

  final bool enabled;

  @override
  State<_ConsignmentReasonDialog> createState() =>
      _ConsignmentReasonDialogState();
}

class _ConsignmentReasonDialogState extends State<_ConsignmentReasonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isNotEmpty) Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.enabled
            ? 'consignment.enable_confirm'.tr()
            : 'consignment.disable_confirm'.tr(),
      ),
      content: TextField(
        key: const ValueKey('consignment-change-reason-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 500,
        decoration: InputDecoration(
          labelText: 'consignment.change_reason'.tr(),
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          key: const ValueKey('consignment-change-confirm-button'),
          onPressed: _submit,
          child: Text('common.confirm'.tr()),
        ),
      ],
    );
  }
}
