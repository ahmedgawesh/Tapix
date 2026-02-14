import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart' hide Currency;
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../bloc/journal_entries_bloc.dart';

class JournalEntriesListScreen extends StatelessWidget {
  const JournalEntriesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<JournalEntriesBloc>(),
      child: const _JournalEntriesListView(),
    );
  }
}

class _JournalEntriesListView extends StatelessWidget {
  const _JournalEntriesListView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();
    final currency = cs.getCurrency();

    return Scaffold(
      appBar: AppBar(
        title: Text('accounting.journal_entries'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'accounting.filter'.tr(),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      body: BlocBuilder<JournalEntriesBloc, RealtimeState<JournalEntriesData>>(
        builder: (context, state) {
          if (state is RealtimeLoading<JournalEntriesData>) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is RealtimeError<JournalEntriesData>) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                  const SizedBox(height: 16),
                  Text(
                    'accounting.error_loading'.tr(),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
            );
          }

          if (state is RealtimeSuccess<JournalEntriesData>) {
            final data = state.data;
            if (data.entries.isEmpty) {
              return Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.book_outlined, size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(
                        'accounting.no_journal_entries'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'accounting.no_journal_entries_hint'.tr(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: [
                // Search bar
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'accounting.search_entries'.tr(),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (query) {
                      context.read<JournalEntriesBloc>().add(
                        JournalEntriesSearchRequested(query),
                      );
                    },
                  ),
                ),
                // Entries list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: data.entries.length,
                    itemBuilder: (context, index) {
                      final entry = data.entries[index];
                      return _JournalEntryCard(
                        entry: entry,
                        currency: currency,
                        onTap: () => context.push('/accounting/journal-entries/${entry.id}'),
                      );
                    },
                  ),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    final bloc = context.read<JournalEntriesBloc>();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'accounting.filter_by_status'.tr(),
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: Text('accounting.all'.tr()),
                      selected: true,
                      onSelected: (_) {
                        bloc.add(const JournalEntriesFilterByStatusRequested(null));
                        Navigator.pop(ctx);
                      },
                    ),
                    FilterChip(
                      label: Text('accounting.status_draft'.tr()),
                      onSelected: (_) {
                        bloc.add(const JournalEntriesFilterByStatusRequested('draft'));
                        Navigator.pop(ctx);
                      },
                    ),
                    FilterChip(
                      label: Text('accounting.status_posted'.tr()),
                      onSelected: (_) {
                        bloc.add(const JournalEntriesFilterByStatusRequested('posted'));
                        Navigator.pop(ctx);
                      },
                    ),
                    FilterChip(
                      label: Text('accounting.status_voided'.tr()),
                      onSelected: (_) {
                        bloc.add(const JournalEntriesFilterByStatusRequested('voided'));
                        Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'accounting.filter_by_type'.tr(),
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: Text('accounting.type_manual'.tr()),
                      onSelected: (_) {
                        bloc.add(const JournalEntriesFilterByTypeRequested('manual'));
                        Navigator.pop(ctx);
                      },
                    ),
                    FilterChip(
                      label: Text('accounting.type_sale'.tr()),
                      onSelected: (_) {
                        bloc.add(const JournalEntriesFilterByTypeRequested('sale'));
                        Navigator.pop(ctx);
                      },
                    ),
                    FilterChip(
                      label: Text('accounting.type_purchase'.tr()),
                      onSelected: (_) {
                        bloc.add(const JournalEntriesFilterByTypeRequested('purchase'));
                        Navigator.pop(ctx);
                      },
                    ),
                    FilterChip(
                      label: Text('accounting.type_expense'.tr()),
                      onSelected: (_) {
                        bloc.add(const JournalEntriesFilterByTypeRequested('expense'));
                        Navigator.pop(ctx);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _JournalEntryCard extends StatelessWidget {
  final JournalEntry entry;
  final Currency currency;
  final VoidCallback onTap;

  const _JournalEntryCard({
    required this.entry,
    required this.currency,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = sl<CurrencyService>();
    final totalDebit = entry.totalDebitCents.toBigInt().toInt();

    Color statusColor;
    IconData statusIcon;
    switch (entry.status) {
      case 'posted':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'voided':
        statusColor = theme.colorScheme.error;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.edit_note;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, size: 18, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.entryNumber,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'accounting.status_${entry.status}'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(color: statusColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entry.description,
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat.yMMMd().format(entry.entryDate),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    cs.formatCents(totalDebit),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (entry.entryType != 'manual') ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.link, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'accounting.type_${entry.entryType}'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
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
    );
  }
}
