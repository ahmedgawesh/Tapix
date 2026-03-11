import 'package:drift/drift.dart' hide Column;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/database/app_database.dart' hide Currency;
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/currency_service.dart';
import '../../../settings/presentation/bloc/app_settings_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/report_date_range.dart';

// ── Lightweight model for a single ledger row ──
class _LedgerEntry {
  final DateTime date;
  final String description;
  final int debitCents;
  final int creditCents;

  const _LedgerEntry({
    required this.date,
    required this.description,
    required this.debitCents,
    required this.creditCents,
  });
}

// ── Account definitions matching the synthetic chart used by ReportsBloc ──
class _VirtualAccount {
  final String code;
  final String nameKey;
  final String type;

  const _VirtualAccount(this.code, this.nameKey, this.type);

  String get name => 'financial_management.$nameKey'.tr();
}

const _virtualAccounts = [
  _VirtualAccount('1000', 'acct_1000_name', 'asset'),
  _VirtualAccount('1010', 'acct_1010_name', 'asset'),
  _VirtualAccount('1100', 'acct_1100_name', 'asset'),
  _VirtualAccount('1200', 'acct_1200_name', 'asset'),
  _VirtualAccount('1300', 'acct_1300_name', 'asset'),
  _VirtualAccount('2000', 'acct_2000_name', 'liability'),
  _VirtualAccount('2100', 'acct_2100_name', 'liability'),
  _VirtualAccount('2300', 'acct_2300_name', 'liability'),
  _VirtualAccount('3000', 'acct_3000_name', 'equity'),
  _VirtualAccount('4000', 'acct_4000_name', 'revenue'),
  _VirtualAccount('5100', 'acct_5100_name', 'expense'),
  _VirtualAccount('5200', 'acct_5200_name', 'expense'),
  _VirtualAccount('5500', 'acct_5500_name', 'expense'),
  _VirtualAccount('5600', 'acct_5600_name', 'expense'),
];

class GeneralLedgerScreen extends StatelessWidget {
  const GeneralLedgerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const _GeneralLedgerView();
  }
}

class _GeneralLedgerView extends StatefulWidget {
  const _GeneralLedgerView();

  @override
  State<_GeneralLedgerView> createState() => _GeneralLedgerViewState();
}

class _GeneralLedgerViewState extends State<_GeneralLedgerView> {
  _VirtualAccount? _selectedAccount;
  List<_LedgerEntry>? _entries;
  bool _loading = false;
  late ReportDateRange _dateRange;

  @override
  void initState() {
    super.initState();
    final settings = context.read<AppSettingsBloc>().state.settings;
    _dateRange = ReportDateRange.fromSettingsDefault(settings.defaultReportDateRange);
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
                  _loadLedgerEntries(_selectedAccount!);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'reports.select_account'.tr(),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.account_balance_wallet),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_VirtualAccount>(
                  value: _selectedAccount,
                  isExpanded: true,
                  hint: Text('reports.select_account'.tr()),
                  items: _virtualAccounts.map((account) {
                    return DropdownMenuItem(
                      value: account,
                      child: Text(
                        '${account.code} - ${account.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (account) {
                    setState(() => _selectedAccount = account);
                    if (account != null) {
                      _loadLedgerEntries(account);
                    }
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: _buildLedgerContent(theme, colorScheme, cs),
          ),
        ],
      ),
    );
  }

  Future<void> _loadLedgerEntries(_VirtualAccount account) async {
    setState(() {
      _loading = true;
      _entries = null;
    });

    try {
      final db = sl<AppDatabase>();
      final startIso = _dateRange.startDate.toIso8601String();
      final endIso = _dateRange.endDate.toIso8601String();
      final entries = <_LedgerEntry>[];

      switch (account.code) {
        case '1000': // Cash
          // Sales payments received
          final salesRows = await db.customSelect(
            '''
            SELECT s.sale_date AS dt, s.invoice_number AS ref, s.paid_amount_cents AS amount
            FROM sales s
            WHERE s.status != 'voided' AND s.paid_amount_cents > 0
              AND s.sale_date >= ? AND s.sale_date <= ?
            ORDER BY s.sale_date
            ''',
            variables: [Variable.withString(startIso), Variable.withString(endIso)],
            readsFrom: {db.sales},
          ).get();
          for (final r in salesRows) {
            entries.add(_LedgerEntry(
              date: DateTime.parse(r.read<String>('dt')),
              description: 'reports.txn_sale'.tr(args: [r.read<String>('ref')]),
              debitCents: r.read<int>('amount'),
              creditCents: 0,
            ));
          }
          // Purchase payments made
          final purchRows = await db.customSelect(
            '''
            SELECT p.purchase_date AS dt, p.purchase_number AS ref, p.paid_amount_cents AS amount
            FROM purchases p
            WHERE p.status != 'voided' AND p.paid_amount_cents > 0
              AND p.purchase_date >= ? AND p.purchase_date <= ?
            ORDER BY p.purchase_date
            ''',
            variables: [Variable.withString(startIso), Variable.withString(endIso)],
            readsFrom: {db.purchases},
          ).get();
          for (final r in purchRows) {
            entries.add(_LedgerEntry(
              date: DateTime.parse(r.read<String>('dt')),
              description: 'reports.txn_purchase'.tr(args: [r.read<String>('ref')]),
              debitCents: 0,
              creditCents: r.read<int>('amount'),
            ));
          }
          // Expenses paid
          final expRows = await db.customSelect(
            '''
            SELECT e.expense_date AS dt, e.description AS ref, e.amount_cents AS amount
            FROM expenses e
            WHERE e.expense_date >= ? AND e.expense_date <= ?
            ORDER BY e.expense_date
            ''',
            variables: [Variable.withString(startIso), Variable.withString(endIso)],
            readsFrom: {db.expenses},
          ).get();
          for (final r in expRows) {
            entries.add(_LedgerEntry(
              date: DateTime.parse(r.read<String>('dt')),
              description: 'reports.txn_expense'.tr(args: [r.read<String>('ref')]),
              debitCents: 0,
              creditCents: r.read<int>('amount'),
            ));
          }
          // Sale returns (cash refunded)
          final sRetRows = await db.customSelect(
            '''
            SELECT sr.return_date AS dt, sr.return_number AS ref, sr.total_cents AS amount
            FROM sale_returns sr
            WHERE sr.status = 'posted'
              AND sr.return_date >= ? AND sr.return_date <= ?
            ORDER BY sr.return_date
            ''',
            variables: [Variable.withString(startIso), Variable.withString(endIso)],
            readsFrom: {db.saleReturns},
          ).get();
          for (final r in sRetRows) {
            entries.add(_LedgerEntry(
              date: DateTime.parse(r.read<String>('dt')),
              description: 'reports.txn_sale_return'.tr(args: [r.read<String>('ref')]),
              debitCents: 0,
              creditCents: r.read<int>('amount'),
            ));
          }
          // Purchase returns (cash received)
          final pRetRows = await db.customSelect(
            '''
            SELECT pr.return_date AS dt, pr.return_number AS ref, pr.total_cents AS amount
            FROM purchase_returns pr
            WHERE pr.status = 'posted'
              AND pr.return_date >= ? AND pr.return_date <= ?
            ORDER BY pr.return_date
            ''',
            variables: [Variable.withString(startIso), Variable.withString(endIso)],
            readsFrom: {db.purchaseReturns},
          ).get();
          for (final r in pRetRows) {
            entries.add(_LedgerEntry(
              date: DateTime.parse(r.read<String>('dt')),
              description: 'reports.txn_purchase_return'.tr(args: [r.read<String>('ref')]),
              debitCents: r.read<int>('amount'),
              creditCents: 0,
            ));
          }

        case '1100': // Accounts Receivable
          final rows = await db.customSelect(
            '''
            SELECT s.sale_date AS dt, s.invoice_number AS ref,
                   s.total_cents AS total, s.paid_amount_cents AS paid
            FROM sales s
            WHERE s.status != 'voided'
              AND s.sale_date >= ? AND s.sale_date <= ?
            ORDER BY s.sale_date
            ''',
            variables: [Variable.withString(startIso), Variable.withString(endIso)],
            readsFrom: {db.sales},
          ).get();
          for (final r in rows) {
            final unpaid = r.read<int>('total') - r.read<int>('paid');
            if (unpaid > 0) {
              entries.add(_LedgerEntry(
                date: DateTime.parse(r.read<String>('dt')),
                description: 'reports.txn_sale_unpaid'.tr(args: [r.read<String>('ref')]),
                debitCents: unpaid,
                creditCents: 0,
              ));
            }
          }

        case '1200': // Inventory
          final purchRows = await db.customSelect(
            '''
            SELECT p.purchase_date AS dt, p.purchase_number AS ref,
                   (p.total_cents - p.tax_cents) AS net
            FROM purchases p
            WHERE p.status != 'voided'
              AND p.purchase_date >= ? AND p.purchase_date <= ?
            ORDER BY p.purchase_date
            ''',
            variables: [Variable.withString(startIso), Variable.withString(endIso)],
            readsFrom: {db.purchases},
          ).get();
          for (final r in purchRows) {
            entries.add(_LedgerEntry(
              date: DateTime.parse(r.read<String>('dt')),
              description: 'reports.txn_purchase'.tr(args: [r.read<String>('ref')]),
              debitCents: r.read<int>('net'),
              creditCents: 0,
            ));
          }
          final retRows = await db.customSelect(
            '''
            SELECT pr.return_date AS dt, pr.return_number AS ref,
                   (pr.total_cents - pr.tax_cents) AS net
            FROM purchase_returns pr
            WHERE pr.status = 'posted'
              AND pr.return_date >= ? AND pr.return_date <= ?
            ORDER BY pr.return_date
            ''',
            variables: [Variable.withString(startIso), Variable.withString(endIso)],
            readsFrom: {db.purchaseReturns},
          ).get();
          for (final r in retRows) {
            entries.add(_LedgerEntry(
              date: DateTime.parse(r.read<String>('dt')),
              description: 'reports.txn_purchase_return'.tr(args: [r.read<String>('ref')]),
              debitCents: 0,
              creditCents: r.read<int>('net'),
            ));
          }

        case '2000': // Accounts Payable
          final rows = await db.customSelect(
            '''
            SELECT p.purchase_date AS dt, p.purchase_number AS ref,
                   p.total_cents AS total, p.paid_amount_cents AS paid
            FROM purchases p
            WHERE p.status != 'voided'
              AND p.purchase_date >= ? AND p.purchase_date <= ?
            ORDER BY p.purchase_date
            ''',
            variables: [Variable.withString(startIso), Variable.withString(endIso)],
            readsFrom: {db.purchases},
          ).get();
          for (final r in rows) {
            final unpaid = r.read<int>('total') - r.read<int>('paid');
            if (unpaid > 0) {
              entries.add(_LedgerEntry(
                date: DateTime.parse(r.read<String>('dt')),
                description: 'reports.txn_purchase_unpaid'.tr(args: [r.read<String>('ref')]),
                debitCents: 0,
                creditCents: unpaid,
              ));
            }
          }

        case '4000': // Sales Revenue
          final salesRows = await db.customSelect(
            '''
            SELECT s.sale_date AS dt, s.invoice_number AS ref,
                   (s.total_cents - s.tax_cents) AS net_revenue
            FROM sales s
            WHERE s.status != 'voided'
              AND s.sale_date >= ? AND s.sale_date <= ?
            ORDER BY s.sale_date
            ''',
            variables: [Variable.withString(startIso), Variable.withString(endIso)],
            readsFrom: {db.sales},
          ).get();
          for (final r in salesRows) {
            entries.add(_LedgerEntry(
              date: DateTime.parse(r.read<String>('dt')),
              description: 'reports.txn_sale'.tr(args: [r.read<String>('ref')]),
              debitCents: 0,
              creditCents: r.read<int>('net_revenue'),
            ));
          }
          final retRows = await db.customSelect(
            '''
            SELECT sr.return_date AS dt, sr.return_number AS ref,
                   (sr.total_cents - sr.tax_cents) AS net_return
            FROM sale_returns sr
            WHERE sr.status = 'posted'
              AND sr.return_date >= ? AND sr.return_date <= ?
            ORDER BY sr.return_date
            ''',
            variables: [Variable.withString(startIso), Variable.withString(endIso)],
            readsFrom: {db.saleReturns},
          ).get();
          for (final r in retRows) {
            entries.add(_LedgerEntry(
              date: DateTime.parse(r.read<String>('dt')),
              description: 'reports.txn_sale_return'.tr(args: [r.read<String>('ref')]),
              debitCents: r.read<int>('net_return'),
              creditCents: 0,
            ));
          }

        case '5100': // Expenses
          final rows = await db.customSelect(
            '''
            SELECT e.expense_date AS dt, e.description AS ref, e.amount_cents AS amount
            FROM expenses e
            WHERE e.expense_date >= ? AND e.expense_date <= ?
            ORDER BY e.expense_date
            ''',
            variables: [Variable.withString(startIso), Variable.withString(endIso)],
            readsFrom: {db.expenses},
          ).get();
          for (final r in rows) {
            entries.add(_LedgerEntry(
              date: DateTime.parse(r.read<String>('dt')),
              description: r.read<String>('ref'),
              debitCents: r.read<int>('amount'),
              creditCents: 0,
            ));
          }
      }

      // Sort by date
      entries.sort((a, b) => a.date.compareTo(b.date));

      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _entries = [];
          _loading = false;
        });
      }
    }

    sl<AuditLogService>().log(
      entityType: 'report',
      entityId: 0,
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

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_entries == null || _entries!.isEmpty) {
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
        account.type == 'asset' || account.type == 'expense';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 16,
          columns: [
            DataColumn(label: Text('reports.date'.tr())),
            DataColumn(label: Text('reports.description'.tr())),
            DataColumn(
              label: Tooltip(
                message: 'financial_management.debit_tooltip'.tr(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('reports.debit'.tr()),
                    const SizedBox(width: 4),
                    Icon(Icons.help_outline, size: 12,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  ],
                ),
              ),
              numeric: true,
            ),
            DataColumn(
              label: Tooltip(
                message: 'financial_management.credit_tooltip'.tr(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('reports.credit'.tr()),
                    const SizedBox(width: 4),
                    Icon(Icons.help_outline, size: 12,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  ],
                ),
              ),
              numeric: true,
            ),
            DataColumn(label: Text('reports.balance'.tr()), numeric: true),
          ],
          rows: _entries!.map((entry) {
            if (isDebitNormal) {
              runningBalance += entry.debitCents - entry.creditCents;
            } else {
              runningBalance += entry.creditCents - entry.debitCents;
            }

            return DataRow(cells: [
              DataCell(Text(
                DateFormat.yMd().format(entry.date),
                style: theme.textTheme.bodySmall,
              )),
              DataCell(Text(entry.description)),
              DataCell(Text(
                entry.debitCents > 0 ? cs.formatCents(entry.debitCents) : '-',
                style: TextStyle(
                  fontWeight: entry.debitCents > 0 ? FontWeight.bold : FontWeight.normal,
                ),
              )),
              DataCell(Text(
                entry.creditCents > 0 ? cs.formatCents(entry.creditCents) : '-',
                style: TextStyle(
                  fontWeight: entry.creditCents > 0 ? FontWeight.bold : FontWeight.normal,
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
