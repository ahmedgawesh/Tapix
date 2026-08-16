import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/database/app_database.dart' hide Currency;
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../../accounting/presentation/utils/account_display_name.dart';
import '../../../accounting/presentation/utils/journal_description_localizer.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../../services/general_ledger_service.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/report_date_range.dart';

class GeneralLedgerScreen extends StatelessWidget {
  const GeneralLedgerScreen({super.key});

  @override
  Widget build(BuildContext context) => const _GeneralLedgerView();
}

class _GeneralLedgerView extends StatefulWidget {
  const _GeneralLedgerView();

  @override
  State<_GeneralLedgerView> createState() => _GeneralLedgerViewState();
}

class _GeneralLedgerViewState extends State<_GeneralLedgerView> {
  late final GeneralLedgerService _service;
  late ReportDateRange _dateRange;
  int? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    _service = GeneralLedgerService(sl<AppDatabase>());
    final settings = context.read<AppSettingsBloc>().state.settings;
    _dateRange = ReportDateRange.fromSettingsDefault(
      settings.defaultReportDateRange,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('reports.general_ledger'.tr())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DateRangeSelector(
              dateRange: _dateRange,
              onChanged: (range) => setState(() => _dateRange = range),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _AccountSelector(
              service: _service,
              selectedAccountId: _selectedAccountId,
              onChanged: (accountId) {
                setState(() => _selectedAccountId = accountId);
                if (accountId != null) {
                  sl<AuditLogService>().log(
                    entityType: 'report',
                    entityId: accountId,
                    action: 'view_general_ledger',
                  );
                }
              },
            ),
          ),
          Expanded(
            child: _selectedAccountId == null
                ? const _SelectAccountPrompt()
                : StreamBuilder<GeneralLedgerSnapshot>(
                    stream: _service.watch(
                      accountId: _selectedAccountId!,
                      startDate: _dateRange.startDate,
                      endDate: _dateRange.endDate,
                    ),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _LedgerError(onRetry: () => setState(() {}));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _LedgerContent(snapshot: snapshot.data!);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AccountSelector extends StatelessWidget {
  final GeneralLedgerService service;
  final int? selectedAccountId;
  final ValueChanged<int?> onChanged;

  const _AccountSelector({
    required this.service,
    required this.selectedAccountId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Account>>(
      stream: service.watchActiveAccounts(),
      builder: (context, snapshot) {
        final accounts = snapshot.data ?? const <Account>[];
        final selectedStillExists = accounts.any(
          (account) => account.id == selectedAccountId,
        );
        return DropdownButtonFormField<int>(
          initialValue: selectedStillExists ? selectedAccountId : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'reports.select_account'.tr(),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
          ),
          hint: Text('reports.select_account'.tr()),
          items: accounts
              .map(
                (account) => DropdownMenuItem<int>(
                  value: account.id,
                  child: Text(
                    '${account.accountCode} - ${localizedAccountName(account)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: snapshot.hasData ? onChanged : null,
        );
      },
    );
  }
}

class _SelectAccountPrompt extends StatelessWidget {
  const _SelectAccountPrompt();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 64,
            color: colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text('reports.select_account_prompt'.tr()),
        ],
      ),
    );
  }
}

class _LedgerContent extends StatelessWidget {
  final GeneralLedgerSnapshot snapshot;

  const _LedgerContent({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final cs = sl<CurrencyService>();
    final accountDescription = localizedAccountDescription(snapshot.account);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Text(
          '${snapshot.account.accountCode} - ${localizedAccountName(snapshot.account)}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _LedgerSummary(snapshot: snapshot, currencyService: cs),
        const SizedBox(height: 16),
        if (snapshot.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              children: [
                Text('reports.no_transactions'.tr()),
                if (accountDescription != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    accountDescription,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text('reports.date'.tr())),
                  DataColumn(label: Text('accounting.entry_number'.tr())),
                  DataColumn(label: Text('reports.description'.tr())),
                  DataColumn(numeric: true, label: Text('reports.debit'.tr())),
                  DataColumn(numeric: true, label: Text('reports.credit'.tr())),
                  DataColumn(
                    numeric: true,
                    label: Text('reports.balance'.tr()),
                  ),
                ],
                rows: snapshot.rows
                    .map(
                      (row) => DataRow(
                        cells: [
                          DataCell(
                            Text(DateFormat.yMd().format(row.entryDate)),
                          ),
                          DataCell(Text(row.entryNumber)),
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 280),
                              child: Text(
                                localizedJournalDescription(row.description),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              row.debitCents == 0
                                  ? '-'
                                  : cs.formatCents(row.debitCents),
                            ),
                          ),
                          DataCell(
                            Text(
                              row.creditCents == 0
                                  ? '-'
                                  : cs.formatCents(row.creditCents),
                            ),
                          ),
                          DataCell(
                            Text(cs.formatCents(row.runningBalanceCents)),
                          ),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
      ],
    );
  }
}

class _LedgerSummary extends StatelessWidget {
  final GeneralLedgerSnapshot snapshot;
  final CurrencyService currencyService;

  const _LedgerSummary({required this.snapshot, required this.currencyService});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth > 700
            ? (constraints.maxWidth - 24) / 4
            : (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SummaryItem(
              width: width,
              label: 'reports.opening_balance'.tr(),
              value: currencyService.formatCents(snapshot.openingBalanceCents),
            ),
            _SummaryItem(
              width: width,
              label: 'reports.total_debits'.tr(),
              value: currencyService.formatCents(snapshot.totalDebitCents),
            ),
            _SummaryItem(
              width: width,
              label: 'reports.total_credits'.tr(),
              value: currencyService.formatCents(snapshot.totalCreditCents),
            ),
            _SummaryItem(
              width: width,
              label: 'reports.closing_balance'.tr(),
              value: currencyService.formatCents(snapshot.closingBalanceCents),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final double width;
  final String label;
  final String value;

  const _SummaryItem({
    required this.width,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LedgerError extends StatelessWidget {
  final VoidCallback onRetry;

  const _LedgerError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 8),
          Text('common.error'.tr()),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text('reports.retry'.tr()),
          ),
        ],
      ),
    );
  }
}
