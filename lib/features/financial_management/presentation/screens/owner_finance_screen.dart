import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/money/money_input_parser.dart';
import '../../../../core/services/currency_service.dart';
import '../../../../core/services/owner_finance_service.dart';
import '../../../accounting/presentation/utils/account_display_name.dart';

class OwnerFinanceScreen extends StatefulWidget {
  const OwnerFinanceScreen({super.key});

  @override
  State<OwnerFinanceScreen> createState() => _OwnerFinanceScreenState();
}

class _OwnerFinanceScreenState extends State<OwnerFinanceScreen> {
  final _service = sl<OwnerFinanceService>();
  final _currency = sl<CurrencyService>();
  late final Future<({List<Account> accounts, int currencyId})> _setup;

  @override
  void initState() {
    super.initState();
    _setup = _loadSetup();
  }

  Future<({List<Account> accounts, int currencyId})> _loadSetup() async {
    final values = await Future.wait([
      _service.getMoneyAccounts(),
      _service.getDefaultCurrencyId(),
    ]);
    return (accounts: values[0] as List<Account>, currencyId: values[1] as int);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('financial_management.owner_finance'.tr()),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.add),
        label: Text('financial_management.owner_add_transaction'.tr()),
      ),
      body: StreamBuilder<List<OwnerFinanceTransaction>>(
        stream: _service.watchTransactions(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorView(message: _message(snapshot.error!));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return _EmptyView(
              icon: Icons.account_balance_wallet_outlined,
              title: 'financial_management.owner_empty'.tr(),
              subtitle: 'financial_management.owner_empty_desc'.tr(),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              _OwnerSummary(rows: rows, currency: _currency),
              const SizedBox(height: 16),
              for (final row in rows)
                _OwnerTransactionCard(
                  row: row,
                  currency: _currency,
                  onVoid: row.status == 'posted'
                      ? () => _voidTransaction(row)
                      : null,
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openCreateDialog() async {
    try {
      final setup = await _setup;
      if (!mounted) return;
      if (setup.accounts.isEmpty) {
        _showError('financial_management.owner_no_money_accounts'.tr());
        return;
      }
      final result = await showDialog<OwnerFinanceResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OwnerFinanceDialog(
          service: _service,
          accounts: setup.accounts,
          currencyId: setup.currencyId,
        ),
      );
      if (result != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'financial_management.owner_saved'.tr(
                args: [result.transactionNumber],
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) _showError(_message(error));
    }
  }

  Future<void> _voidTransaction(OwnerFinanceTransaction row) async {
    final reason = await _askVoidReason();
    if (reason == null || !mounted) return;
    try {
      await _service.voidTransaction(transactionId: row.id, reason: reason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('financial_management.void_success'.tr())),
        );
      }
    } catch (error) {
      if (mounted) _showError(_message(error));
    }
  }

  Future<String?> _askVoidReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('financial_management.void_title'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: 'financial_management.void_reason'.tr(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: Text('financial_management.void_action'.tr()),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  static String _message(Object error) =>
      error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
}

class _OwnerSummary extends StatelessWidget {
  final List<OwnerFinanceTransaction> rows;
  final CurrencyService currency;

  const _OwnerSummary({required this.rows, required this.currency});

  @override
  Widget build(BuildContext context) {
    var capital = 0;
    var loans = 0;
    for (final row in rows.where((row) => row.status == 'posted')) {
      final amount = row.amountCents.toBigInt().toInt();
      switch (row.transactionType) {
        case 'contribution':
          capital += amount;
        case 'withdrawal':
          capital -= amount;
        case 'loan_received':
          loans += amount;
        case 'loan_repayment':
          loans -= amount;
      }
    }

    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: 'financial_management.owner_net_capital'.tr(),
            value: currency.formatCents(capital),
            icon: Icons.savings_outlined,
            color: Colors.indigo,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            label: 'financial_management.owner_loan_balance'.tr(),
            value: currency.formatCents(loans),
            icon: Icons.handshake_outlined,
            color: Colors.orange,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OwnerTransactionCard extends StatelessWidget {
  final OwnerFinanceTransaction row;
  final CurrencyService currency;
  final VoidCallback? onVoid;

  const _OwnerTransactionCard({
    required this.row,
    required this.currency,
    this.onVoid,
  });

  @override
  Widget build(BuildContext context) {
    final incoming =
        row.transactionType == 'contribution' ||
        row.transactionType == 'loan_received';
    final color = row.status == 'voided'
        ? Theme.of(context).disabledColor
        : incoming
        ? Colors.green
        : Colors.red;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            incoming ? Icons.south_west : Icons.north_east,
            color: color,
          ),
        ),
        title: Text(
          'financial_management.owner_type_${row.transactionType}'.tr(),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row.description),
            Text(
              '${row.transactionNumber} • '
              '${DateFormat.yMMMd(context.locale.toString()).format(row.transactionDate)}',
            ),
            if (row.status == 'voided')
              Text(
                'financial_management.status_voided'.tr(),
                style: TextStyle(color: color),
              ),
          ],
        ),
        trailing: SizedBox(
          width: 126,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  '${incoming ? '+' : '-'}${currency.formatCents(row.amountCents.toBigInt().toInt())}',
                  textAlign: TextAlign.end,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
              ),
              if (onVoid != null)
                PopupMenuButton<String>(
                  onSelected: (_) => onVoid!(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'void',
                      child: Text('financial_management.void_action'.tr()),
                    ),
                  ],
                ),
            ],
          ),
        ),
        isThreeLine: true,
      ),
    );
  }
}

class _OwnerFinanceDialog extends StatefulWidget {
  final OwnerFinanceService service;
  final List<Account> accounts;
  final int currencyId;

  const _OwnerFinanceDialog({
    required this.service,
    required this.accounts,
    required this.currencyId,
  });

  @override
  State<_OwnerFinanceDialog> createState() => _OwnerFinanceDialogState();
}

class _OwnerFinanceDialogState extends State<_OwnerFinanceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _notes = TextEditingController();
  OwnerFinanceTransactionType _type = OwnerFinanceTransactionType.contribution;
  late Account _account;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _account = widget.accounts.first;
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('financial_management.owner_add_transaction'.tr()),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<OwnerFinanceTransactionType>(
                  initialValue: _type,
                  decoration: InputDecoration(
                    labelText: 'financial_management.transaction_type'.tr(),
                  ),
                  items: OwnerFinanceTransactionType.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(
                            'financial_management.owner_type_${type.wireName}'
                                .tr(),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _type = value!),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<Account>(
                  initialValue: _account,
                  decoration: InputDecoration(
                    labelText: 'financial_management.money_account'.tr(),
                  ),
                  items: widget.accounts
                      .map(
                        (account) => DropdownMenuItem(
                          value: account,
                          child: Text(
                            '${account.accountCode} — '
                            '${localizedAccountName(account)}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _account = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'financial_management.amount'.tr(),
                  ),
                  validator: (value) {
                    final result = sl<MoneyInputParser>().parse(value);
                    return !result.isValid || result.cents <= 0
                        ? 'financial_management.amount_required'.tr()
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  decoration: InputDecoration(
                    labelText: 'financial_management.description'.tr(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'financial_management.description_required'.tr()
                      : null,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('financial_management.transaction_date'.tr()),
                  subtitle: Text(
                    DateFormat.yMMMd(context.locale.toString()).format(_date),
                  ),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: _pickDate,
                ),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'financial_management.notes_optional'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                _PostingHint(type: _type, account: _account),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text('common.save'.tr()),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final amount = sl<MoneyInputParser>().parse(_amount.text).cents;
      final result = await widget.service.record(
        type: _type,
        offsetAccountId: _account.id,
        amountCents: amount,
        currencyId: widget.currencyId,
        transactionDate: _date,
        description: _description.text,
        notes: _notes.text,
      );
      if (mounted) Navigator.pop(context, result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(OwnerFinanceScreenStateMessage.message(error)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class OwnerFinanceScreenStateMessage {
  static String message(Object error) =>
      error.toString().replaceFirst(RegExp(r'^[^:]+:\s*'), '');
}

class _PostingHint extends StatelessWidget {
  final OwnerFinanceTransactionType type;
  final Account account;

  const _PostingHint({required this.type, required this.account});

  @override
  Widget build(BuildContext context) {
    final controlCode = type.controlAccountCode;
    final debitCode = type.debitOffsetAccount
        ? account.accountCode
        : controlCode;
    final creditCode = type.debitOffsetAccount
        ? controlCode
        : account.accountCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'financial_management.posting_preview'.tr(
          args: [debitCode, creditCode],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).disabledColor),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(message, textAlign: TextAlign.center));
  }
}
