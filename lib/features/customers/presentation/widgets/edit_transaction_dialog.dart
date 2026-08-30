import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/widgets/inputs/select_all_on_focus.dart';
import '../../../auth/auth.dart';

/// A reusable dialog for editing payment or discount transaction amounts.
/// Works for both customer and supplier transactions.
///
/// [currentAmountCents] — absolute value of current amount in cents.
/// [transactionType] — 'payment' or 'discount'.
/// [onSave] — callback with (newAmountCents, newDescription). Returns a Future
///   that completes when the save is done. Throw to indicate an error.
class EditTransactionDialog extends StatefulWidget {
  final int currentAmountCents;
  final String transactionType;
  final String? currentDescription;
  final Future<void> Function(int newAmountCents, String? newDescription) onSave;

  const EditTransactionDialog({
    super.key,
    required this.currentAmountCents,
    required this.transactionType,
    this.currentDescription,
    required this.onSave,
  });

  /// Show the dialog only if the user has `editTransactions` permission.
  /// Returns `true` if the transaction was successfully edited.
  static Future<bool> show({
    required BuildContext context,
    required int currentAmountCents,
    required String transactionType,
    String? currentDescription,
    required Future<void> Function(int newAmountCents, String? newDescription) onSave,
  }) async {
    // Permission check
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('common.login_required'.tr())),
      );
      return false;
    }
    final permissionService = sl<PermissionService>();
    if (!permissionService.hasPermission(authState.user, Permissions.editTransactions)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('common.permission_denied'.tr())),
      );
      return false;
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => EditTransactionDialog(
        currentAmountCents: currentAmountCents,
        transactionType: transactionType,
        currentDescription: currentDescription,
        onSave: onSave,
      ),
    );
    return result ?? false;
  }

  @override
  State<EditTransactionDialog> createState() => _EditTransactionDialogState();
}

class _EditTransactionDialogState extends State<EditTransactionDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final cs = sl<CurrencyService>();
    // Convert cents to display amount (e.g. 1500 → "15.00")
    final displayAmount = (widget.currentAmountCents / 100).toStringAsFixed(cs.getCurrency().decimalDigits);
    _amountController = TextEditingController(text: displayAmount);
    _descriptionController = TextEditingController(text: widget.currentDescription ?? '');
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    final isPayment = widget.transactionType == 'payment';
    final icon = isPayment ? LucideIcons.banknote : LucideIcons.badgePercent;
    final titleKey = isPayment
        ? 'customers.edit_payment'
        : 'customers.edit_discount';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                titleKey.tr(),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'customers.edit_transaction_hint'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // Show current amount as reference
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'customers.current_amount'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      cs.formatCents(widget.currentAmountCents),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountController,
                decoration: InputDecoration(
                  labelText: 'customers.new_amount'.tr(),
                  prefixIcon: const Icon(LucideIcons.badgeDollarSign),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                onTap: () => selectAllText(_amountController),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'customers.description'.tr(),
                  hintText: 'customers.edit_reason_hint'.tr(),
                  prefixIcon: const Icon(LucideIcons.fileText),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('common.cancel'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _onSave,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text('common.save'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'customers.amount_invalid'.tr());
      return;
    }

    final newAmountCents = (amount * 100).round();
    if (newAmountCents == widget.currentAmountCents) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final desc = _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim();
      await widget.onSave(newAmountCents, desc);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString().replaceAll('StateError: ', '');
        });
      }
    }
  }
}
