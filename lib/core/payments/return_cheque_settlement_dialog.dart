import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'checkout_settlement.dart';

Future<List<CheckoutPaymentAllocation>?> showReturnChequeSettlementDialog(
  BuildContext context, {
  required int totalCents,
  required String formattedTotal,
  DateTime? initialDueDate,
  DateTime? documentDate,
  List<CheckoutPaymentAllocation> initialAllocations = const [],
}) {
  return showDialog<List<CheckoutPaymentAllocation>>(
    context: context,
    builder: (_) => _ReturnChequeSettlementDialog(
      totalCents: totalCents,
      formattedTotal: formattedTotal,
      initialDueDate: initialDueDate,
      documentDate: documentDate ?? DateTime.now(),
      initialAllocations: initialAllocations,
    ),
  );
}

bool isReturnChequeSettlementValid(
  List<CheckoutPaymentAllocation> allocations, {
  required int totalCents,
}) {
  if (allocations.isEmpty || !allocations.any((p) => p.method == 'cheque')) {
    return false;
  }
  try {
    CheckoutSettlement(allocations).validate(invoiceTotalCents: totalCents);
    return true;
  } catch (_) {
    return false;
  }
}

DateTime? returnChequePrimaryDueDate(
  List<CheckoutPaymentAllocation> allocations,
) => allocations
    .where((payment) => payment.method == 'cheque')
    .firstOrNull
    ?.dueDate;

class ReturnChequeSettlementSummary extends StatelessWidget {
  final List<CheckoutPaymentAllocation> allocations;
  final int totalCents;
  final String Function(int cents) formatAmount;
  final VoidCallback onEdit;

  const ReturnChequeSettlementSummary({
    super.key,
    required this.allocations,
    required this.totalCents,
    required this.formatAmount,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isValid = isReturnChequeSettlementValid(
      allocations,
      totalCents: totalCents,
    );
    final chequeCount = allocations
        .where((payment) => payment.method == 'cheque')
        .length;
    final allocatedCents = allocations.fold<int>(
      0,
      (sum, payment) => sum + payment.amountCents,
    );
    final creditCents = (totalCents - allocatedCents).clamp(0, totalCents);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isValid
            ? cs.primaryContainer.withValues(alpha: 0.25)
            : cs.errorContainer.withValues(alpha: 0.22),
        border: Border.all(
          color: isValid
              ? cs.primary.withValues(alpha: 0.45)
              : cs.error.withValues(alpha: 0.45),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isValid
                ? 'returns.cheque_details_configured'.tr(
                    namedArgs: {
                      'count': '$chequeCount',
                      'amount': formatAmount(allocatedCents),
                    },
                  )
                : 'returns.cheque_details_required'.tr(),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isValid ? cs.onSurface : cs.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isValid && creditCents > 0) ...[
            const SizedBox(height: 4),
            Text(
              'returns.cheque_credit_remainder'.tr(
                namedArgs: {'amount': formatAmount(creditCents)},
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onEdit,
            icon: Icon(isValid ? Icons.edit_outlined : Icons.add_card),
            label: Text(
              isValid
                  ? 'returns.edit_cheque_details'.tr()
                  : 'returns.enter_cheque_details'.tr(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReturnChequeSettlementDialog extends StatefulWidget {
  final int totalCents;
  final String formattedTotal;
  final DateTime? initialDueDate;
  final DateTime documentDate;
  final List<CheckoutPaymentAllocation> initialAllocations;

  const _ReturnChequeSettlementDialog({
    required this.totalCents,
    required this.formattedTotal,
    required this.initialDueDate,
    required this.documentDate,
    required this.initialAllocations,
  });

  @override
  State<_ReturnChequeSettlementDialog> createState() =>
      _ReturnChequeSettlementDialogState();
}

class _ReturnChequeSettlementDialogState
    extends State<_ReturnChequeSettlementDialog> {
  late final TextEditingController _amount;
  final _number = TextEditingController();
  final _bank = TextEditingController();
  final _remainderNumber = TextEditingController();
  final _remainderBank = TextEditingController();
  late DateTime? _dueDate;
  DateTime? _remainderDueDate;
  String _remainderMethod = 'credit';
  String? _error;

  @override
  void initState() {
    super.initState();
    final primaryCheque = widget.initialAllocations
        .where((payment) => payment.method == 'cheque')
        .firstOrNull;
    final remainderPayment = widget.initialAllocations
        .where((payment) => payment != primaryCheque)
        .firstOrNull;
    _amount = TextEditingController(
      text: ((primaryCheque?.amountCents ?? widget.totalCents) / 100)
          .toStringAsFixed(2),
    );
    _number.text = primaryCheque?.reference ?? '';
    _bank.text = primaryCheque?.bankName ?? '';
    _dueDate = primaryCheque?.dueDate ?? widget.initialDueDate;
    if (remainderPayment != null) {
      _remainderMethod = remainderPayment.method;
      if (remainderPayment.method == 'cheque') {
        _remainderNumber.text = remainderPayment.reference ?? '';
        _remainderBank.text = remainderPayment.bankName ?? '';
        _remainderDueDate = remainderPayment.dueDate;
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _number.dispose();
    _bank.dispose();
    _remainderNumber.dispose();
    _remainderBank.dispose();
    super.dispose();
  }

  int get _chequeCents {
    final parsed = Decimal.tryParse(_amount.text.trim().replaceAll(',', '.'));
    if (parsed == null) return 0;
    return (parsed * Decimal.fromInt(100)).round().toBigInt().toInt();
  }

  int get _remainder => widget.totalCents - _chequeCents;

  Future<void> _pickDueDate({required bool remainder}) async {
    final first = DateUtils.dateOnly(widget.documentDate);
    final current = remainder ? _remainderDueDate : _dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? first.add(const Duration(days: 30)),
      firstDate: first,
      lastDate: first.add(const Duration(days: 3650)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (remainder) {
        _remainderDueDate = picked;
      } else {
        _dueDate = picked;
      }
    });
  }

  String _dateLabel(DateTime? value) => value == null
      ? 'sales.select_due_date'.tr()
      : MaterialLocalizations.of(context).formatMediumDate(value);

  void _submit() {
    final chequeCents = _chequeCents;
    if (chequeCents <= 0 || chequeCents > widget.totalCents) {
      setState(() => _error = 'cheques.error_cheque_amount_invalid'.tr());
      return;
    }
    if (_number.text.trim().isEmpty) {
      setState(() => _error = 'cheques.error_cheque_number_required'.tr());
      return;
    }
    if (_dueDate == null) {
      setState(() => _error = 'cheques.error_due_date_required'.tr());
      return;
    }
    if (_remainder > 0 &&
        _remainderMethod == 'cheque' &&
        (_remainderNumber.text.trim().isEmpty || _remainderDueDate == null)) {
      setState(
        () => _error = _remainderNumber.text.trim().isEmpty
            ? 'cheques.error_cheque_number_required'.tr()
            : 'cheques.error_due_date_required'.tr(),
      );
      return;
    }
    final payments = <CheckoutPaymentAllocation>[
      CheckoutPaymentAllocation(
        method: 'cheque',
        amountCents: chequeCents,
        reference: _number.text.trim(),
        bankName: _bank.text.trim(),
        issueDate: widget.documentDate,
        dueDate: _dueDate,
      ),
      if (_remainder > 0 && _remainderMethod != 'credit')
        CheckoutPaymentAllocation(
          method: _remainderMethod,
          amountCents: _remainder,
          reference: _remainderMethod == 'cheque'
              ? _remainderNumber.text.trim()
              : null,
          bankName: _remainderMethod == 'cheque'
              ? _remainderBank.text.trim()
              : null,
          issueDate: widget.documentDate,
          dueDate: _remainderMethod == 'cheque' ? _remainderDueDate : null,
        ),
    ];
    try {
      CheckoutSettlement(
        payments,
      ).validate(invoiceTotalCents: widget.totalCents);
      Navigator.of(context).pop(payments);
    } catch (_) {
      setState(() => _error = 'cheques.error_cheque_amount_invalid'.tr());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('returns.cheque_split_title'.tr()),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'returns.cheque_split_total'.tr(
                  namedArgs: {'amount': widget.formattedTotal},
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(labelText: 'cheques.amount'.tr()),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _number,
                decoration: InputDecoration(labelText: 'cheques.number'.tr()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bank,
                decoration: InputDecoration(labelText: 'cheques.bank'.tr()),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _pickDueDate(remainder: false),
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(_dateLabel(_dueDate)),
              ),
              if (_remainder > 0) ...[
                const Divider(height: 28),
                Text(
                  'returns.cheque_split_remainder'.tr(
                    namedArgs: {
                      'amount': (_remainder / 100).toStringAsFixed(2),
                    },
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _remainderMethod,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'cheques.remainder_method'.tr(),
                  ),
                  items:
                      [
                            ('credit', 'sales.payment_credit'.tr()),
                            ('cash', 'sales.payment_cash'.tr()),
                            ('card', 'sales.payment_card'.tr()),
                            ('cheque', 'sales.payment_cheque'.tr()),
                          ]
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.$1,
                              child: Text(
                                entry.$2,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (value) =>
                      setState(() => _remainderMethod = value ?? 'credit'),
                ),
                if (_remainderMethod == 'cheque') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _remainderNumber,
                    decoration: InputDecoration(
                      labelText: 'cheques.remainder_cheque_number'.tr(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _remainderBank,
                    decoration: InputDecoration(
                      labelText: 'cheques.remainder_cheque_bank'.tr(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _pickDueDate(remainder: true),
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(_dateLabel(_remainderDueDate)),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(onPressed: _submit, child: Text('common.confirm'.tr())),
      ],
    );
  }
}
