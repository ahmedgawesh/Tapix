import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/currency_service.dart';
import '../../data/company_branch_monitor_service.dart';
import '../../data/synced_location_report_service.dart';
import 'company_document_detail_screen.dart';

enum _SyncedReportPeriod { today, week, month, all }

class SyncedLocationReportScreen extends StatefulWidget {
  const SyncedLocationReportScreen({
    super.key,
    required this.reportKey,
    this.branchId,
    this.warehouseId,
    this.scope,
    required this.locationLabel,
    this.service,
  }) : assert(
         scope != null || (branchId != null && warehouseId != null),
         'Provide an explicit scope or both branchId and warehouseId.',
       );

  final String reportKey;
  final String? branchId;
  final String? warehouseId;
  final SyncedReportScope? scope;
  final String locationLabel;
  final SyncedLocationReportService? service;

  @override
  State<SyncedLocationReportScreen> createState() =>
      _SyncedLocationReportScreenState();
}

class _SyncedLocationReportScreenState
    extends State<SyncedLocationReportScreen> {
  late final SyncedLocationReportService _service =
      widget.service ??
      SyncedLocationReportService(
        CompanyBranchMonitorService(sl<AppDatabase>()),
      );
  _SyncedReportPeriod _period = _SyncedReportPeriod.month;

  bool get _isBalanceReport =>
      widget.reportKey == 'reports.inventory_reports' ||
      widget.reportKey == 'reports.supplier_stocktake';
  SyncedLocationReportData? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) get _range {
    final now = DateTime.now();
    if (_isBalanceReport) {
      return (DateTime.utc(2000), DateTime(now.year, now.month, now.day + 1));
    }
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return switch (_period) {
      _SyncedReportPeriod.today => (
        DateTime(now.year, now.month, now.day),
        tomorrow,
      ),
      _SyncedReportPeriod.week => (
        DateTime(now.year, now.month, now.day - now.weekday + 1),
        tomorrow,
      ),
      _SyncedReportPeriod.month => (DateTime(now.year, now.month), tomorrow),
      _SyncedReportPeriod.all => (DateTime.utc(2000), tomorrow),
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final range = _range;
      final value = await _service.load(
        reportKey: widget.reportKey,
        branchId: widget.branchId,
        warehouseId: widget.warehouseId,
        scope: widget.scope,
        from: range.$1,
        toExclusive: range.$2,
      );
      if (mounted) setState(() => _data = value);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _print() async {
    final data = _data;
    if (data == null) return;
    final rtl = context.locale.languageCode == 'ar';
    pw.Font regular;
    pw.Font bold;
    try {
      regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'),
      );
      bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'),
      );
    } catch (_) {
      regular = pw.Font.helvetica();
      bold = pw.Font.helveticaBold();
    }
    final currency = sl<CurrencyService>();
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: regular, bold: bold),
        textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        build: (_) => [
          pw.Text(
            widget.reportKey.tr(),
            style: pw.TextStyle(font: bold, fontSize: 18),
          ),
          pw.SizedBox(height: 4),
          pw.Text(widget.locationLabel),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: [
              'synced_reports.label'.tr(),
              'synced_reports.quantity'.tr(),
              'synced_reports.documents'.tr(),
              'synced_reports.total'.tr(),
            ],
            data: [
              for (final row in data.rows)
                [
                  row.label.trim().isEmpty
                      ? 'synced_reports.unknown'.tr()
                      : row.label.startsWith('reports.')
                      ? row.label.tr()
                      : row.label,
                  _formatQuantity(row.quantity),
                  row.documentCount.toString(),
                  currency.formatForCode(
                    widget.reportKey.contains('profit')
                        ? row.profitMinor
                        : row.amountMinor,
                    row.currencyCode,
                  ),
                ],
            ],
            headerStyle: pw.TextStyle(font: bold),
            cellStyle: pw.TextStyle(font: regular),
          ),
        ],
      ),
    );
    await Printing.layoutPdf(
      name: widget.reportKey.tr(),
      onLayout: (PdfPageFormat _) => document.save(),
    );
  }

  Future<void> _share() async {
    final data = _data;
    if (data == null) return;
    String cell(Object? value) =>
        '"${value?.toString().replaceAll('"', '""') ?? ''}"';
    final csv = StringBuffer()
      ..writeln(
        [
          'label',
          'quantity',
          'documents',
          'currency',
          'amount_minor',
          'discount_minor',
          'tax_minor',
          'cost_minor',
          'profit_minor',
        ].map(cell).join(','),
      );
    for (final row in data.rows) {
      csv.writeln(
        [
          row.label,
          row.quantity,
          row.documentCount,
          row.currencyCode,
          row.amountMinor,
          row.discountMinor,
          row.taxMinor,
          row.costMinor,
          row.profitMinor,
        ].map(cell).join(','),
      );
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode('﻿${csv.toString()}'),
            mimeType: 'text/csv',
          ),
        ],
        fileNameOverrides: [
          'tapix_${widget.reportKey.replaceAll('.', '_')}_${widget.scope?.kind.name ?? widget.warehouseId}.csv',
        ],
        subject: widget.reportKey.tr(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.reportKey.tr()),
        actions: [
          IconButton(
            onPressed: data == null || data.rows.isEmpty ? null : _print,
            tooltip: 'synced_reports.print'.tr(),
            icon: const Icon(Icons.print_outlined),
          ),
          IconButton(
            onPressed: data == null || data.rows.isEmpty ? null : _share,
            tooltip: 'synced_reports.share'.tr(),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: 'synced_reports.refresh'.tr(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              children: [
                _LocationHeader(
                  locationLabel: widget.locationLabel,
                  generatedAt: data?.generatedAt,
                ),
                if (_isBalanceReport)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Chip(
                        avatar: const Icon(Icons.inventory_2_outlined),
                        label: Text('synced_reports.current_balance'.tr()),
                      ),
                    ),
                  )
                else
                  _periods(),
                Expanded(child: _body(data)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _periods() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final period in _SyncedReportPeriod.values)
            ChoiceChip(
              label: Text('synced_reports.period.${period.name}'.tr()),
              selected: _period == period,
              onSelected: (selected) {
                if (!selected || _period == period) return;
                setState(() => _period = period);
                _load();
              },
            ),
        ],
      ),
    );
  }

  Widget _body(SyncedLocationReportData? data) {
    if (_loading && data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.sync_problem_outlined,
                size: 52,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                'synced_reports.load_failed'.tr(),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: Text('synced_reports.retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }
    final value = data!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          if (value.hasLegacyGaps)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: Text('synced_reports.legacy_gap_title'.tr()),
                subtitle: Text('synced_reports.legacy_gap_body'.tr()),
              ),
            ),
          _Summary(data: value),
          const SizedBox(height: 12),
          if (value.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 64),
              child: Column(
                children: [
                  const Icon(Icons.inbox_outlined, size: 56),
                  const SizedBox(height: 12),
                  Text('synced_reports.empty'.tr()),
                ],
              ),
            )
          else
            for (final row in value.rows) ...[
              _ReportRowCard(
                row: row,
                reportKey: widget.reportKey,
                onOpenDocuments: row.documents.isEmpty
                    ? null
                    : () => _openDocuments(row.documents),
              ),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Future<void> _openDocuments(List<CompanyDocumentSnapshot> documents) async {
    if (documents.length == 1) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              CompanyDocumentDetailScreen(document: documents.single),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ReportDocumentsScreen(documents: documents),
      ),
    );
  }
}

class _ReportDocumentsScreen extends StatelessWidget {
  const _ReportDocumentsScreen({required this.documents});

  final List<CompanyDocumentSnapshot> documents;

  @override
  Widget build(BuildContext context) {
    final ordered = [...documents]
      ..sort((left, right) => right.documentDate.compareTo(left.documentDate));
    final currency = sl<CurrencyService>();
    return Scaffold(
      appBar: AppBar(title: Text('synced_reports.source_documents'.tr())),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: ordered.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final document = ordered[index];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(document.number),
                subtitle: Text(
                  [
                    document.branchName,
                    document.warehouseName,
                    if (document.partyName?.trim().isNotEmpty == true)
                      document.partyName!,
                    DateFormat.yMd().format(document.documentDate.toLocal()),
                    'synced_reports.items_count'.tr(
                      namedArgs: {'count': '${document.lines.length}'},
                    ),
                  ].join(' · '),
                ),
                trailing: Text(
                  '${currency.formatForCode(document.totalMinor, document.currencyCode)} '
                  '${document.currencyCode}',
                  textAlign: TextAlign.end,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        CompanyDocumentDetailScreen(document: document),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LocationHeader extends StatelessWidget {
  const _LocationHeader({
    required this.locationLabel,
    required this.generatedAt,
  });

  final String locationLabel;
  final DateTime? generatedAt;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.analytics_outlined),
        title: Text(locationLabel),
        subtitle: Text(
          generatedAt == null
              ? 'synced_reports.read_only'.tr()
              : 'synced_reports.last_sync'.tr(
                  namedArgs: {
                    'time': DateFormat.yMd().add_Hm().format(
                      generatedAt!.toLocal(),
                    ),
                  },
                ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.data});

  final SyncedLocationReportData data;

  @override
  Widget build(BuildContext context) {
    final currency = sl<CurrencyService>();
    final profitReport = data.reportKey.contains('profit');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _metric(
              context,
              'synced_reports.documents'.tr(),
              '${data.documentCount}',
            ),
            if (data.hasFinancialFlowBreakdown) ...[
              _metric(
                context,
                'synced_reports.gross_documents'.tr(),
                '${data.grossDocumentCount}',
              ),
              _metric(
                context,
                'synced_reports.return_documents'.tr(),
                '${data.returnDocumentCount}',
              ),
            ],
            _metric(context, 'synced_reports.rows'.tr(), '${data.rows.length}'),
            if (data.hasFinancialFlowBreakdown)
              for (final currencyCode in <String>{
                ...data.grossTotalsByCurrency.keys,
                ...data.returnTotalsByCurrency.keys,
              }) ...[
                _metric(
                  context,
                  'synced_reports.gross'.tr(),
                  '${currency.formatForCode(data.grossTotalsByCurrency[currencyCode] ?? 0, currencyCode)} $currencyCode',
                ),
                _metric(
                  context,
                  'synced_reports.returns'.tr(),
                  '${currency.formatForCode(data.returnTotalsByCurrency[currencyCode] ?? 0, currencyCode)} $currencyCode',
                ),
                _metric(
                  context,
                  'synced_reports.net'.tr(),
                  '${currency.formatForCode(data.netTotalsByCurrency[currencyCode] ?? 0, currencyCode)} $currencyCode',
                ),
              ]
            else
              for (final entry
                  in (profitReport
                          ? data.profitByCurrency
                          : data.totalsByCurrency)
                      .entries)
                _metric(
                  context,
                  profitReport
                      ? 'synced_reports.net_profit'.tr()
                      : 'synced_reports.total'.tr(),
                  '${currency.formatForCode(entry.value, entry.key)} ${entry.key}',
                ),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _ReportRowCard extends StatelessWidget {
  const _ReportRowCard({
    required this.row,
    required this.reportKey,
    this.onOpenDocuments,
  });

  final SyncedLocationReportRow row;
  final String reportKey;
  final VoidCallback? onOpenDocuments;

  @override
  Widget build(BuildContext context) {
    final currency = sl<CurrencyService>();
    final label = row.label.trim().isEmpty
        ? 'synced_reports.unknown'.tr()
        : row.label.startsWith('reports.')
        ? row.label.tr()
        : row.label;
    final profit = reportKey.contains('profit');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDocuments,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final amount = profit ? row.profitMinor : row.amountMinor;
              final money =
                  '${currency.formatForCode(amount, row.currencyCode)} ${row.currencyCode}';
              final details = Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  _detail(
                    context,
                    'synced_reports.quantity'.tr(),
                    _formatQuantity(row.quantity),
                  ),
                  _detail(
                    context,
                    'synced_reports.documents'.tr(),
                    '${row.documentCount}',
                  ),
                  if (row.discountMinor != 0)
                    _detail(
                      context,
                      'synced_reports.discount'.tr(),
                      currency.formatForCode(
                        row.discountMinor,
                        row.currencyCode,
                      ),
                    ),
                  if (row.taxMinor != 0)
                    _detail(
                      context,
                      'synced_reports.tax'.tr(),
                      currency.formatForCode(row.taxMinor, row.currencyCode),
                    ),
                  if (profit)
                    _detail(
                      context,
                      'synced_reports.cost'.tr(),
                      currency.formatForCode(row.costMinor, row.currencyCode),
                    ),
                ],
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.titleMedium),
                    if (row.subtitle.isNotEmpty) Text(row.subtitle),
                    const SizedBox(height: 8),
                    Text(
                      money,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    details,
                    if (onOpenDocuments != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        children: [
                          const Icon(Icons.open_in_new, size: 16),
                          Text('synced_reports.open_documents'.tr()),
                        ],
                      ),
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (row.subtitle.isNotEmpty) Text(row.subtitle),
                        const SizedBox(height: 10),
                        details,
                        if (onOpenDocuments != null) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            children: [
                              const Icon(Icons.open_in_new, size: 16),
                              Text('synced_reports.open_documents'.tr()),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    money,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static Widget _detail(BuildContext context, String label, String value) {
    return Text('$label: $value', style: Theme.of(context).textTheme.bodySmall);
  }
}

String _formatQuantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
