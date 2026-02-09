import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../domain/repositories/journal_repository.dart';
import '../bloc/journal_entry_form_bloc.dart';

class JournalEntryFormScreen extends StatelessWidget {
  final int? entryId;

  const JournalEntryFormScreen({super.key, this.entryId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<JournalEntryFormBloc>()
        ..add(JournalEntryFormLoadRequested(entryId: entryId)),
      child: _JournalEntryFormView(entryId: entryId),
    );
  }
}

class _JournalEntryFormView extends StatefulWidget {
  final int? entryId;

  const _JournalEntryFormView({this.entryId});

  @override
  State<_JournalEntryFormView> createState() => _JournalEntryFormViewState();
}

class _JournalEntryFormViewState extends State<_JournalEntryFormView> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  DateTime _entryDate = DateTime.now();
  final List<_LineEntry> _lines = [_LineEntry(), _LineEntry()];

  bool get _isViewMode => widget.entryId != null;

  @override
  void dispose() {
    _descriptionController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocConsumer<JournalEntryFormBloc, RealtimeState<JournalEntryFormData>>(
      listener: (context, state) {
        if (state is RealtimeSuccess<JournalEntryFormData> && state.data.isSubmitted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('accounting.entry_created'.tr()),
              backgroundColor: Colors.green,
            ),
          );
          context.pop();
        }
        if (state is RealtimeSuccess<JournalEntryFormData> && state.data.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.data.errorMessage!),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      },
      builder: (context, state) {
        final isLoading = state is RealtimeLoading<JournalEntryFormData>;
        final data = state is RealtimeSuccess<JournalEntryFormData> ? state.data : null;
        final isSubmitting = data?.isSubmitting ?? false;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              _isViewMode
                  ? 'accounting.view_journal_entry'.tr()
                  : 'accounting.add_journal_entry'.tr(),
            ),
          ),
          body: isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Description
                        TextFormField(
                          controller: _descriptionController,
                          readOnly: _isViewMode,
                          decoration: InputDecoration(
                            labelText: 'accounting.description'.tr(),
                            filled: true,
                          ),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'accounting.description_required'.tr() : null,
                        ),
                        const SizedBox(height: 16),

                        // Date picker
                        InkWell(
                          onTap: _isViewMode ? null : () => _pickDate(context),
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'accounting.entry_date'.tr(),
                              filled: true,
                              suffixIcon: const Icon(Icons.calendar_today),
                            ),
                            child: Text(DateFormat.yMMMd().format(_entryDate)),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Lines header
                        Row(
                          children: [
                            Text(
                              'accounting.entry_lines'.tr(),
                              style: theme.textTheme.titleMedium,
                            ),
                            const Spacer(),
                            if (!_isViewMode)
                              TextButton.icon(
                                onPressed: _addLine,
                                icon: const Icon(Icons.add, size: 18),
                                label: Text('accounting.add_line'.tr()),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Lines
                        ...List.generate(_lines.length, (i) {
                          return _JournalLineRow(
                            key: ValueKey(i),
                            line: _lines[i],
                            accounts: data?.availableAccounts ?? [],
                            index: i,
                            readOnly: _isViewMode,
                            onRemove: _lines.length > 2 ? () => _removeLine(i) : null,
                          );
                        }),

                        const SizedBox(height: 16),

                        // Totals
                        _buildTotals(theme),

                        const SizedBox(height: 24),

                        // Submit button
                        if (!_isViewMode)
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: isSubmitting ? null : _submit,
                              child: isSubmitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text('accounting.save_entry'.tr()),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildTotals(ThemeData theme) {
    final cs = sl<CurrencyService>();
    int totalDebits = 0;
    int totalCredits = 0;
    for (final line in _lines) {
      totalDebits += int.tryParse(line.debitController.text) ?? 0;
      totalCredits += int.tryParse(line.creditController.text) ?? 0;
    }
    final isBalanced = totalDebits == totalCredits && totalDebits > 0;

    return Card(
      color: isBalanced
          ? Colors.green.withValues(alpha: 0.1)
          : theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('accounting.total_debits'.tr(), style: theme.textTheme.bodySmall),
                  Text(
                    cs.formatCents(totalDebits),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('accounting.total_credits'.tr(), style: theme.textTheme.bodySmall),
                  Text(
                    cs.formatCents(totalCredits),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Icon(
              isBalanced ? Icons.check_circle : Icons.warning,
              color: isBalanced ? Colors.green : theme.colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }

  void _addLine() {
    setState(() {
      _lines.add(_LineEntry());
    });
  }

  void _removeLine(int index) {
    setState(() {
      _lines[index].dispose();
      _lines.removeAt(index);
    });
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _entryDate = picked;
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final lines = <JournalLineInput>[];

    for (final line in _lines) {
      if (line.selectedAccountId == null) continue;
      final debit = int.tryParse(line.debitController.text) ?? 0;
      final credit = int.tryParse(line.creditController.text) ?? 0;
      if (debit == 0 && credit == 0) continue;

      lines.add(JournalLineInput(
        accountId: line.selectedAccountId!,
        debitCents: Decimal.fromInt(debit),
        creditCents: Decimal.fromInt(credit),
        currencyId: 1, // Default currency
        description: line.descriptionController.text.isEmpty
            ? null
            : line.descriptionController.text,
      ));
    }

    context.read<JournalEntryFormBloc>().add(
      JournalEntryFormSubmitRequested(
        description: _descriptionController.text,
        entryDate: _entryDate,
        lines: lines,
      ),
    );
  }
}

class _LineEntry {
  int? selectedAccountId;
  final debitController = TextEditingController();
  final creditController = TextEditingController();
  final descriptionController = TextEditingController();

  void dispose() {
    debitController.dispose();
    creditController.dispose();
    descriptionController.dispose();
  }
}

class _JournalLineRow extends StatefulWidget {
  final _LineEntry line;
  final List<Account> accounts;
  final int index;
  final bool readOnly;
  final VoidCallback? onRemove;

  const _JournalLineRow({
    super.key,
    required this.line,
    required this.accounts,
    required this.index,
    this.readOnly = false,
    this.onRemove,
  });

  @override
  State<_JournalLineRow> createState() => _JournalLineRowState();
}

class _JournalLineRowState extends State<_JournalLineRow> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  '${'accounting.line'.tr()} ${widget.index + 1}',
                  style: theme.textTheme.labelMedium,
                ),
                const Spacer(),
                if (widget.onRemove != null && !widget.readOnly)
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: theme.colorScheme.error),
                    onPressed: widget.onRemove,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Account selector
            DropdownButtonFormField<int>(
              // ignore: deprecated_member_use
              value: widget.line.selectedAccountId,
              decoration: InputDecoration(
                labelText: 'accounting.account'.tr(),
                filled: true,
                isDense: true,
              ),
              items: widget.accounts.map((a) {
                return DropdownMenuItem(
                  value: a.id,
                  child: Text(
                    '${a.accountCode} - ${a.accountName}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: widget.readOnly
                  ? null
                  : (v) => setState(() => widget.line.selectedAccountId = v),
            ),
            const SizedBox(height: 8),
            // Debit / Credit row
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 400) {
                  return Column(
                    children: [
                      TextFormField(
                        controller: widget.line.debitController,
                        readOnly: widget.readOnly,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'accounting.debit'.tr(),
                          filled: true,
                          isDense: true,
                          suffixText: 'accounting.cents'.tr(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: widget.line.creditController,
                        readOnly: widget.readOnly,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'accounting.credit'.tr(),
                          filled: true,
                          isDense: true,
                          suffixText: 'accounting.cents'.tr(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: widget.line.debitController,
                        readOnly: widget.readOnly,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'accounting.debit'.tr(),
                          filled: true,
                          isDense: true,
                          suffixText: 'accounting.cents'.tr(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: widget.line.creditController,
                        readOnly: widget.readOnly,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'accounting.credit'.tr(),
                          filled: true,
                          isDense: true,
                          suffixText: 'accounting.cents'.tr(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
