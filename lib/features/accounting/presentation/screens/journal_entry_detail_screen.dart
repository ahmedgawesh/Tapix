import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../bloc/journal_entry_form_bloc.dart';
import '../bloc/journal_entries_bloc.dart';
import '../services/journal_pdf_service.dart';
import '../utils/account_display_name.dart';
import '../utils/journal_description_localizer.dart';
import '../utils/journal_entry_localizer.dart';

class JournalEntryDetailScreen extends StatelessWidget {
  final int entryId;

  const JournalEntryDetailScreen({super.key, required this.entryId});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) =>
              sl<JournalEntryFormBloc>()
                ..add(JournalEntryFormLoadRequested(entryId: entryId)),
        ),
        BlocProvider(create: (_) => sl<JournalEntriesBloc>()),
      ],
      child: _JournalEntryDetailView(entryId: entryId),
    );
  }
}

class _JournalEntryDetailView extends StatelessWidget {
  final int entryId;

  const _JournalEntryDetailView({required this.entryId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();

    return BlocBuilder<
      JournalEntryFormBloc,
      RealtimeState<JournalEntryFormData>
    >(
      builder: (context, state) {
        if (state is RealtimeLoading<JournalEntryFormData>) {
          return Scaffold(
            appBar: AppBar(title: Text('accounting.journal_entry'.tr())),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (state is RealtimeError<JournalEntryFormData>) {
          return Scaffold(
            appBar: AppBar(title: Text('accounting.journal_entry'.tr())),
            body: Center(child: Text('accounting.error_loading'.tr())),
          );
        }

        final data = (state as RealtimeSuccess<JournalEntryFormData>).data;
        final entry = data.existingEntry;
        final lines = data.existingLines;

        if (entry == null) {
          return Scaffold(
            appBar: AppBar(title: Text('accounting.journal_entry'.tr())),
            body: Center(child: Text('accounting.entry_not_found'.tr())),
          );
        }

        Color statusColor;
        switch (entry.status) {
          case 'posted':
            statusColor = Colors.green;
            break;
          case 'voided':
            statusColor = theme.colorScheme.error;
            break;
          default:
            statusColor = Colors.orange;
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(entry.entryNumber),
            actions: [
              if (entry.status == 'draft')
                IconButton(
                  icon: const Icon(Icons.check_circle_outline),
                  tooltip: 'accounting.post_entry'.tr(),
                  onPressed: () => _postEntry(context, entry),
                ),
              if (entry.status == 'posted')
                IconButton(
                  icon: const Icon(Icons.cancel_outlined),
                  tooltip: 'accounting.void_entry'.tr(),
                  onPressed: () => _voidEntry(context, entry),
                ),
              IconButton(
                icon: const Icon(Icons.print),
                tooltip: 'accounting.print'.tr(),
                onPressed: () => JournalPdfService.printJournalEntry(
                  context: context,
                  entry: entry,
                  lines: lines,
                  accounts: data.availableAccounts,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'accounting.share'.tr(),
                onPressed: () => JournalPdfService.shareJournalEntry(
                  context: context,
                  entry: entry,
                  lines: lines,
                  accounts: data.availableAccounts,
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status & Type header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'accounting.status_${entry.status}'.tr(),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: statusColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        localizedJournalEntryType(entry.entryType),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Description
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'accounting.description'.tr(),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          localizedJournalDescription(entry.description),
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('dd/MM/yyyy').format(entry.entryDate),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                        if (entry.sourceTable != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.link,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${'accounting.source'.tr()}: '
                                  '${localizedJournalSourceTable(entry.sourceTable!)} '
                                  '#${entry.sourceId}',
                                  style: theme.textTheme.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Lines
                Text(
                  'accounting.entry_lines'.tr(),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),

                // Lines table
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 24,
                      columns: [
                        DataColumn(label: Text('accounting.account'.tr())),
                        DataColumn(
                          label: Text('accounting.debit'.tr()),
                          numeric: true,
                        ),
                        DataColumn(
                          label: Text('accounting.credit'.tr()),
                          numeric: true,
                        ),
                        DataColumn(label: Text('accounting.description'.tr())),
                      ],
                      rows: lines.map((line) {
                        final account = data.availableAccounts
                            .where((a) => a.id == line.accountId)
                            .firstOrNull;
                        final debit = line.debitCents.toBigInt().toInt();
                        final credit = line.creditCents.toBigInt().toInt();

                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                account != null
                                    ? '${account.accountCode} - '
                                          '${localizedAccountName(account)}'
                                    : 'accounting.unknown_account'.tr(),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DataCell(
                              Text(
                                debit > 0 ? cs.formatCents(debit) : '-',
                                style: TextStyle(
                                  fontWeight: debit > 0
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                credit > 0 ? cs.formatCents(credit) : '-',
                                style: TextStyle(
                                  fontWeight: credit > 0
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                localizedJournalDescription(line.description),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Totals
                Card(
                  color: Colors.green.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'accounting.total_debits'.tr(),
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                cs.formatCents(
                                  entry.totalDebitCents.toBigInt().toInt(),
                                ),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'accounting.total_credits'.tr(),
                                style: theme.textTheme.bodySmall,
                              ),
                              Text(
                                cs.formatCents(
                                  entry.totalCreditCents.toBigInt().toInt(),
                                ),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.check_circle, color: Colors.green),
                      ],
                    ),
                  ),
                ),

                // Audit info
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'accounting.audit_trail'.tr(),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        _auditRow(
                          theme,
                          'accounting.created_at'.tr(),
                          DateFormat(
                            'dd/MM/yyyy',
                          ).add_jm().format(entry.createdAt),
                        ),
                        if (entry.postedAt != null)
                          _auditRow(
                            theme,
                            'accounting.posted_at'.tr(),
                            DateFormat(
                              'dd/MM/yyyy',
                            ).add_jm().format(entry.postedAt!),
                          ),
                        if (entry.isReversed)
                          _auditRow(
                            theme,
                            'accounting.reversed'.tr(),
                            'accounting.yes'.tr(),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _auditRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _postEntry(BuildContext context, JournalEntry entry) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('accounting.post_entry'.tr()),
        content: Text('accounting.post_entry_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('accounting.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<JournalEntriesBloc>().add(
                JournalEntryPostRequested(entry.id),
              );
              // Reload detail
              context.read<JournalEntryFormBloc>().add(
                JournalEntryFormLoadRequested(entryId: entry.id),
              );
            },
            child: Text('accounting.post'.tr()),
          ),
        ],
      ),
    );
  }

  void _voidEntry(BuildContext context, JournalEntry entry) {
    final reasonController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('accounting.void_entry'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('accounting.void_entry_confirm'.tr()),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: 'accounting.void_reason'.tr(),
                filled: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('accounting.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<JournalEntriesBloc>().add(
                JournalEntryVoidRequested(
                  entry.id,
                  reason: reasonController.text.isEmpty
                      ? 'Voided by user'
                      : reasonController.text,
                ),
              );
              // Reload detail
              context.read<JournalEntryFormBloc>().add(
                JournalEntryFormLoadRequested(entryId: entry.id),
              );
            },
            child: Text('accounting.void'.tr()),
          ),
        ],
      ),
    );
  }
}
