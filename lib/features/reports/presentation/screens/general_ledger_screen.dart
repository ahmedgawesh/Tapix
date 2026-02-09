import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart' hide Currency;
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../../accounting/presentation/bloc/accounts_bloc.dart';
import '../../../accounting/domain/repositories/journal_repository.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/report_date_range.dart';

class GeneralLedgerScreen extends StatelessWidget {
  const GeneralLedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AccountsBloc>(),
      child: const _GeneralLedgerView(),
    );
  }
}

class _GeneralLedgerView extends StatefulWidget {
  const _GeneralLedgerView();

  @override
  State<_GeneralLedgerView> createState() => _GeneralLedgerViewState();
}

class _GeneralLedgerViewState extends State<_GeneralLedgerView> {
  Account? _selectedAccount;
  List<JournalEntryLine>? _lines;
  bool _loadingLines = false;
  StreamSubscription<List<JournalEntryLine>>? _linesSubscription;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();

  @override
  void dispose() {
    _linesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final cs = sl<CurrencyService>();

    return Scaffold(
      appBar: AppBar(
        title: Text('reports.general_ledger'.tr()),
      ),
      body: Column(
        children: [
          // Date range selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DateRangeSelector(
              dateRange: _dateRange,
              onChanged: (range) {
                setState(() => _dateRange = range);
                if (_selectedAccount != null) {
                  _subscribeToLedgerLines(_selectedAccount!.id);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: BlocBuilder<AccountsBloc, RealtimeState<AccountsData>>(
              builder: (context, state) {
                List<Account> accounts = [];
                if (state is RealtimeSuccess<AccountsData>) {
                  accounts = state.data.accounts;
                }

                return InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'reports.select_account'.tr(),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.account_balance_wallet),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Account>(
                      value: _selectedAccount,
                      isExpanded: true,
                      hint: Text('reports.select_account'.tr()),
                      items: accounts.map((account) {
                        return DropdownMenuItem(
                          value: account,
                          child: Text(
                            '${account.accountCode} - ${account.accountName}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (account) {
                        setState(() {
                          _selectedAccount = account;
                        });
                        if (account != null) {
                          _subscribeToLedgerLines(account.id);
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _buildLedgerContent(theme, colorScheme, cs),
          ),
        ],
      ),
    );
  }

  void _subscribeToLedgerLines(int accountId) {
    _linesSubscription?.cancel();
    setState(() {
      _loadingLines = true;
      _lines = null;
    });

    final repo = sl<JournalRepository>();
    _linesSubscription = repo.watchPostedLinesByAccountAndDateRange(
      accountId, _dateRange.startDate, _dateRange.endDate,
    ).listen(
      (loadedLines) {
        if (mounted) {
          setState(() {
            _lines = loadedLines;
            _loadingLines = false;
          });
        }
      },
      onError: (Object e) {
        if (mounted) {
          setState(() {
            _lines = [];
            _loadingLines = false;
          });
        }
      },
    );

    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: accountId,
      action: 'view_general_ledger',
    );
  }

  Widget _buildLedgerContent(
    ThemeData theme,
    ColorScheme colorScheme,
    CurrencyService cs,
  ) {
    if (_selectedAccount == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book, size: 64, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'reports.select_account_prompt'.tr(),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_loadingLines) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_lines == null || _lines!.isEmpty) {
      return Center(
        child: Text(
          'reports.no_transactions'.tr(),
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    int runningBalance = 0;
    final account = _selectedAccount!;
    final isDebitNormal =
        account.accountType == 'asset' || account.accountType == 'expense';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 16,
          columns: [
            DataColumn(label: Text('reports.date'.tr())),
            DataColumn(label: Text('reports.description'.tr())),
            DataColumn(label: Text('reports.debit'.tr()), numeric: true),
            DataColumn(label: Text('reports.credit'.tr()), numeric: true),
            DataColumn(label: Text('reports.balance'.tr()), numeric: true),
          ],
          rows: _lines!.map((line) {
            final debit = line.debitCents.toBigInt().toInt();
            final credit = line.creditCents.toBigInt().toInt();

            if (isDebitNormal) {
              runningBalance += debit - credit;
            } else {
              runningBalance += credit - debit;
            }

            return DataRow(cells: [
              DataCell(Text(
                DateFormat.yMd().format(line.createdAt),
                style: theme.textTheme.bodySmall,
              )),
              DataCell(Text(line.description ?? '-')),
              DataCell(Text(
                debit > 0 ? cs.formatCents(debit) : '-',
                style: TextStyle(
                  fontWeight: debit > 0 ? FontWeight.bold : FontWeight.normal,
                ),
              )),
              DataCell(Text(
                credit > 0 ? cs.formatCents(credit) : '-',
                style: TextStyle(
                  fontWeight: credit > 0 ? FontWeight.bold : FontWeight.normal,
                ),
              )),
              DataCell(Text(
                cs.formatCents(runningBalance),
                style: const TextStyle(fontWeight: FontWeight.bold),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
