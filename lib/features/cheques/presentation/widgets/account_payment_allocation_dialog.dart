import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/services/party_account_payment_service.dart';
import '../../../../core/utils/app_date_formatter.dart';

Future<void> showAccountPaymentAllocationDialog(
  BuildContext context, {
  required int chequeId,
  int? userId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) =>
      _AccountPaymentAllocationSheet(chequeId: chequeId, userId: userId),
);

class _AccountPaymentAllocationSheet extends StatefulWidget {
  final int chequeId;
  final int? userId;

  const _AccountPaymentAllocationSheet({
    required this.chequeId,
    required this.userId,
  });

  @override
  State<_AccountPaymentAllocationSheet> createState() =>
      _AccountPaymentAllocationSheetState();
}

class _AccountPaymentAllocationSheetState
    extends State<_AccountPaymentAllocationSheet> {
  final _amount = TextEditingController();
  late final PartyAccountPaymentService _service;
  PartyAccountPaymentDetails? _details;
  List<PartyOutstandingDocument> _documents = const [];
  List<PartyAccountPaymentApplicationDetails> _applications = const [];
  PartyOutstandingDocument? _selected;
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _service = sl<PartyAccountPaymentService>();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final details = await _service.getDetailsByChequeId(widget.chequeId);
      if (details == null) throw StateError('account_payment_not_found');
      final documents = await _service.getOutstandingDocuments(
        details.payment.id,
      );
      final applications = await _service.getApplications(details.payment.id);
      final selectedId = _selected?.documentId;
      final selected = documents.cast<PartyOutstandingDocument?>().firstWhere(
        (item) => item?.documentId == selectedId,
        orElse: () => documents.isEmpty ? null : documents.first,
      );
      if (!mounted) return;
      setState(() {
        _details = details;
        _documents = documents;
        _applications = applications;
        _selected = selected;
        _error = null;
        _loading = false;
        _saving = false;
        _setSuggestedAmount();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
        _saving = false;
      });
    }
  }

  void _setSuggestedAmount() {
    final details = _details;
    final selected = _selected;
    if (details == null || selected == null) {
      _amount.clear();
      return;
    }
    final cents = details.availableCents < selected.outstandingCents
        ? details.availableCents
        : selected.outstandingCents;
    _amount.text = cents <= 0 ? '' : (cents / 100).toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    child: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? _ErrorState(error: _error!, onRetry: _load)
        : _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final details = _details!;
    final payment = details.payment;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      children: [
        Row(
          children: [
            const Icon(LucideIcons.walletCards),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'cheques.advance_allocation_title'.tr(),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${details.partyName} • ${details.cheque.chequeNumber ?? '#${details.cheque.id}'}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 14),
        _BalanceSummary(details: details),
        const SizedBox(height: 12),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('cheques.advance_unapplied_notice'.tr()),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'cheques.allocations'.tr(),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_applications.isEmpty)
          Text('cheques.no_allocations'.tr())
        else
          ..._applications.map(
            (item) => Card(
              child: ListTile(
                title: Text(item.documentNumber),
                subtitle: Text(
                  '${AppDateFormatter.date(item.application.appliedAt)} • '
                  '${'cheques.allocation_status_${item.application.status}'.tr()}',
                ),
                leading: Text(
                  _money(
                    item.application.amountCents.toBigInt().toInt(),
                    details.currencySymbol,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: item.application.status == 'active'
                    ? IconButton(
                        tooltip: 'cheques.reverse_allocation'.tr(),
                        onPressed: _saving
                            ? null
                            : () => _reverse(item.application.id),
                        icon: const Icon(LucideIcons.undo2),
                      )
                    : null,
              ),
            ),
          ),
        const SizedBox(height: 18),
        if (payment.status != PartyAccountPaymentStatus.reversed &&
            details.availableCents > 0) ...[
          Text(
            'cheques.optional_allocation'.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_documents.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text('cheques.no_open_documents_for_advance'.tr()),
              ),
            )
          else ...[
            DropdownButtonFormField<PartyOutstandingDocument>(
              initialValue: _selected,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'cheques.invoice_to_allocate'.tr(),
                prefixIcon: const Icon(LucideIcons.receiptText),
              ),
              items: _documents
                  .map(
                    (document) => DropdownMenuItem(
                      value: document,
                      child: Text(
                        '${document.documentNumber} — ${_money(document.outstandingCents, details.currencySymbol)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _saving
                  ? null
                  : (value) {
                      setState(() {
                        _selected = value;
                        _setSuggestedAmount();
                      });
                    },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'cheques.amount_to_allocate'.tr(),
                suffixText: details.currencyCode,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _apply,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(LucideIcons.link),
              label: Text('cheques.apply_to_invoice'.tr()),
            ),
          ],
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.close'.tr()),
        ),
      ],
    );
  }

  Future<void> _apply() async {
    final details = _details!;
    final document = _selected;
    if (document == null) return;
    try {
      setState(() => _saving = true);
      await _service.applyToDocument(
        accountPaymentId: details.payment.id,
        documentType: document.documentType,
        documentId: document.documentId,
        amountCents: _parseCents(_amount.text),
        userId: widget.userId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('cheques.allocation_saved'.tr())));
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _reverse(int applicationId) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('cheques.reverse_allocation'.tr()),
            content: Text('cheques.reverse_allocation_confirm'.tr()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('common.no'.tr()),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('common.yes'.tr()),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    try {
      setState(() => _saving = true);
      await _service.reverseApplication(
        applicationId: applicationId,
        reason: 'Manual allocation reversal',
        userId: widget.userId,
      );
      await _load();
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() => _saving = false);
    final raw = error.toString();
    const keys = [
      'account_payment_amount_invalid',
      'account_payment_not_found',
      'account_payment_reversed',
      'account_payment_exceeds_available',
      'account_payment_document_mismatch',
      'account_payment_document_not_open',
      'account_payment_exceeds_document',
      'account_application_not_found',
    ];
    final key = keys.where(raw.contains).firstOrNull;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          key == null
              ? 'cheques.action_failed'.tr(args: [raw])
              : 'cheques.error_$key'.tr(),
        ),
      ),
    );
  }
}

class _BalanceSummary extends StatelessWidget {
  final PartyAccountPaymentDetails details;

  const _BalanceSummary({required this.details});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _value(context, 'cheques.advance_total'.tr(), details.amountCents),
      const SizedBox(width: 8),
      _value(context, 'cheques.advance_applied'.tr(), details.appliedCents),
      const SizedBox(width: 8),
      _value(
        context,
        'cheques.advance_unapplied'.tr(),
        details.availableCents,
        highlight: true,
      ),
    ],
  );

  Widget _value(
    BuildContext context,
    String label,
    int cents, {
    bool highlight = false,
  }) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: highlight
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(
              _money(cents, details.currencySymbol),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.triangleAlert, size: 42),
          const SizedBox(height: 12),
          Text(error.toString(), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: Text('common.retry'.tr())),
        ],
      ),
    ),
  );
}

int _parseCents(String raw) {
  try {
    final value = Decimal.parse(raw.trim().replaceAll(',', '.'));
    final scaled = value * Decimal.fromInt(100);
    if (value <= Decimal.zero || !scaled.isInteger) {
      throw const FormatException();
    }
    return scaled.toBigInt().toInt();
  } on FormatException {
    throw ArgumentError('account_payment_amount_invalid');
  }
}

String _money(int cents, String symbol) =>
    '$symbol${(cents / 100).toStringAsFixed(2)}';
