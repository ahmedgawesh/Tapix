import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/promotions/promotion_repository.dart';
import '../../../../core/promotions/promotion_sale_snapshot.dart';

enum _PromotionReportSort { usage, profitability }

class PromotionUsageReportScreen extends StatefulWidget {
  const PromotionUsageReportScreen({super.key});

  @override
  State<PromotionUsageReportScreen> createState() =>
      _PromotionUsageReportScreenState();
}

class _PromotionUsageReportScreenState
    extends State<PromotionUsageReportScreen> {
  late DateTime _from;
  late DateTime _to;
  int? _promotionId;
  String _status = 'all';
  _PromotionReportSort _sort = _PromotionReportSort.profitability;
  late Future<List<Promotion>> _promotionsFuture;
  late Future<List<PromotionUsageReportRow>> _reportFuture;

  PromotionRepository get _repository => sl<PromotionRepository>();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    _promotionsFuture = _repository.watchAll().first;
    _reload();
  }

  DateTime get _toExclusive => _to.add(const Duration(days: 1));

  void _reload() {
    _reportFuture = _repository.loadUsageReport(
      from: _from,
      toExclusive: _toExclusive,
      promotionId: _promotionId,
      status: _status,
    );
  }

  void _refresh() => setState(_reload);

  Future<void> _pickDate({required bool start}) async {
    final initial = start ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('promotions.report.title'.tr()),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'common.refresh'.tr(),
            icon: const Icon(LucideIcons.refreshCw),
          ),
        ],
      ),
      body: Column(
        children: [
          _filters(context),
          Expanded(
            child: FutureBuilder<List<PromotionUsageReportRow>>(
              future: _reportFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ReportMessage(
                    icon: LucideIcons.triangleAlert,
                    text: 'promotions.report.load_error'.tr(),
                    action: FilledButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(LucideIcons.refreshCw),
                      label: Text('common.retry'.tr()),
                    ),
                  );
                }
                final rows = [...?snapshot.data];
                if (rows.isEmpty) {
                  return _ReportMessage(
                    icon: LucideIcons.chartNoAxesColumn,
                    text: 'promotions.report.empty'.tr(),
                  );
                }
                rows.sort(
                  _sort == _PromotionReportSort.usage
                      ? (a, b) =>
                            b.applicationCount.compareTo(a.applicationCount)
                      : (a, b) =>
                            b.grossProfitCents.compareTo(a.grossProfitCents),
                );
                return _reportBody(context, rows);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<List<Promotion>>(
          future: _promotionsFuture,
          builder: (context, snapshot) {
            final promotions = snapshot.data ?? const <Promotion>[];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickDate(start: true),
                  icon: const Icon(LucideIcons.calendarDays),
                  label: Text(
                    '${'promotions.report.from'.tr()}: ${dateFormat.format(_from)}',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickDate(start: false),
                  icon: const Icon(LucideIcons.calendarDays),
                  label: Text(
                    '${'promotions.report.to'.tr()}: ${dateFormat.format(_to)}',
                  ),
                ),
                SizedBox(
                  width: 250,
                  child: DropdownButtonFormField<int?>(
                    initialValue: _promotionId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'promotions.report.promotion'.tr(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          'promotions.report.all_promotions'.tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ...promotions.map(
                        (row) => DropdownMenuItem<int?>(
                          value: row.id,
                          child: Text(
                            '${row.name} — v${row.version}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _promotionId = value;
                        _reload();
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'promotions.report.status'.tr(),
                      isDense: true,
                    ),
                    items: ['all', 'draft', 'active', 'paused', 'archived']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value == 'all'
                                  ? 'promotions.report.all_statuses'.tr()
                                  : 'promotions.status.$value'.tr(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _status = value;
                        _reload();
                      });
                    },
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<_PromotionReportSort>(
                    segments: [
                      ButtonSegment(
                        value: _PromotionReportSort.profitability,
                        icon: const Icon(LucideIcons.trendingUp),
                        label: Text('promotions.report.sort_profit'.tr()),
                      ),
                      ButtonSegment(
                        value: _PromotionReportSort.usage,
                        icon: const Icon(LucideIcons.chartNoAxesColumn),
                        label: Text('promotions.report.sort_usage'.tr()),
                      ),
                    ],
                    selected: {_sort},
                    onSelectionChanged: (value) {
                      setState(() => _sort = value.first);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _reportBody(BuildContext context, List<PromotionUsageReportRow> rows) {
    final groups = <String, List<PromotionUsageReportRow>>{};
    for (final row in rows) {
      groups.putIfAbsent('${row.currencyId}', () => []).add(row);
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups.values.elementAt(index);
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: _CurrencyReportGroup(
            rows: group,
            from: _from,
            toExclusive: _toExclusive,
            status: _status,
          ),
        );
      },
    );
  }
}

class _CurrencyReportGroup extends StatelessWidget {
  final List<PromotionUsageReportRow> rows;
  final DateTime from;
  final DateTime toExclusive;
  final String status;

  const _CurrencyReportGroup({
    required this.rows,
    required this.from,
    required this.toExclusive,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final first = rows.first;
    final invoices = rows.fold<int>(
      0,
      (sum, row) => sum + row.transactionCount,
    );
    final applications = rows.fold<int>(
      0,
      (sum, row) => sum + row.applicationCount,
    );
    final sales = rows.fold<int>(0, (sum, row) => sum + row.netSalesCents);
    final discount = rows.fold<int>(
      0,
      (sum, row) => sum + row.netDiscountCents,
    );
    final profit = rows.fold<int>(0, (sum, row) => sum + row.grossProfitCents);
    final returned = rows.fold<int>(
      0,
      (sum, row) => sum + row.returnedGrossSalesCents,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${first.currencyCode} (${first.currencySymbol})',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Text('promotions.report.currency_separate_note'.tr()),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricCard(
              label: 'promotions.report.applications'.tr(),
              value: '$applications',
              secondary: '${'promotions.report.invoices'.tr()}: $invoices',
            ),
            _MetricCard(
              label: 'promotions.report.net_sales'.tr(),
              value: _money(context, first.currencySymbol, sales),
            ),
            _MetricCard(
              label: 'promotions.report.net_discount'.tr(),
              value: _money(context, first.currencySymbol, discount),
            ),
            _MetricCard(
              label: 'promotions.report.returns'.tr(),
              value: _money(context, first.currencySymbol, returned),
            ),
            _MetricCard(
              label: 'promotions.report.gross_profit'.tr(),
              value: _money(context, first.currencySymbol, profit),
              positive: profit >= 0,
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...rows.map(
          (row) => Card(
            child: ListTile(
              onTap: () => _showInvoices(context, row),
              leading: const CircleAvatar(
                child: Icon(LucideIcons.badgePercent),
              ),
              title: Text(
                row.promotionName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${row.promotionCode} • v${row.promotionVersion} • '
                '${'promotions.status.${row.status}'.tr()}\n'
                '${'promotions.report.applications'.tr()}: ${row.applicationCount} • '
                '${'promotions.report.invoices'.tr()}: ${row.transactionCount} • '
                '${'promotions.report.net_discount'.tr()}: '
                '${_money(context, row.currencySymbol, row.netDiscountCents)}',
              ),
              isThreeLine: true,
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(context, row.currencySymbol, row.netSalesCents),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${'promotions.report.profit'.tr()}: '
                      '${_money(context, row.currencySymbol, row.grossProfitCents)}',
                      style: TextStyle(
                        color: row.grossProfitCents >= 0
                            ? Colors.green
                            : Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showInvoices(
    BuildContext pageContext,
    PromotionUsageReportRow row,
  ) async {
    await showDialog<void>(
      context: pageContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '${row.promotionName} — ${'promotions.report.invoices'.tr()}',
        ),
        content: SizedBox(
          width: 760,
          height: 480,
          child: FutureBuilder<List<PromotionUsageInvoiceRow>>(
            future: sl<PromotionRepository>().loadUsageInvoices(
              promotionId: row.promotionId,
              currencyId: row.currencyId,
              from: from,
              toExclusive: toExclusive,
              status: status,
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final invoices = snapshot.data!;
              if (invoices.isEmpty) {
                return Center(child: Text('promotions.report.empty'.tr()));
              }
              return ListView.separated(
                itemCount: invoices.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final invoice = invoices[index];
                  return ListTile(
                    title: Text(invoice.invoiceNumber),
                    subtitle: Text(
                      '${DateFormat('dd/MM/yyyy').format(invoice.saleDate)} • '
                      '${'promotions.report.applications'.tr()}: ${invoice.applicationCount} • '
                      '${'promotions.report.net_discount'.tr()}: '
                      '${_money(pageContext, invoice.currencySymbol, invoice.netDiscountCents)}',
                    ),
                    trailing: Text(
                      _money(
                        pageContext,
                        invoice.currencySymbol,
                        invoice.grossProfitCents,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(dialogContext).pop();
                      pageContext.push('/sales/${invoice.saleId}');
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('common.close'.tr()),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? secondary;
  final bool? positive;

  const _MetricCard({
    required this.label,
    required this.value,
    this.secondary,
    this.positive,
  });

  @override
  Widget build(BuildContext context) {
    final color = positive == null
        ? null
        : positive!
        ? Colors.green
        : Theme.of(context).colorScheme.error;
    return SizedBox(
      width: 210,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (secondary != null)
                Text(secondary!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _ReportMessage({required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    ),
  );
}

String _money(BuildContext context, String symbol, int cents) =>
    NumberFormat.currency(
      locale: context.locale.toString(),
      symbol: symbol,
      decimalDigits: 2,
    ).format(cents / 100);
