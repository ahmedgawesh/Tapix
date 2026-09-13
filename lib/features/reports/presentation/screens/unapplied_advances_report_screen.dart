import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/utils/app_date_formatter.dart';
import '../../services/unapplied_advances_export_service.dart';
import '../../services/unapplied_advances_report_service.dart';

class UnappliedAdvancesReportScreen extends StatefulWidget {
  const UnappliedAdvancesReportScreen({super.key});

  @override
  State<UnappliedAdvancesReportScreen> createState() =>
      _UnappliedAdvancesReportScreenState();
}

class _UnappliedAdvancesReportScreenState
    extends State<UnappliedAdvancesReportScreen> {
  late final UnappliedAdvancesReportService _service;
  late final Stream<List<UnappliedAdvanceReportRow>> _stream;
  final _searchController = TextEditingController();
  UnappliedAdvancePartyFilter _filter = UnappliedAdvancePartyFilter.all;
  List<UnappliedAdvanceReportRow> _visibleRows = const [];

  @override
  void initState() {
    super.initState();
    _service = UnappliedAdvancesReportService(sl<AppDatabase>());
    _stream = _service.watchRows();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<List<UnappliedAdvanceReportRow>>(
        stream: _stream,
        builder: (context, snapshot) {
          final rows = _filtered(snapshot.data ?? const []);
          _visibleRows = rows;
          final summaries = _service.summarize(rows);
          return Scaffold(
            appBar: AppBar(
              title: Text('reports.unapplied_advances_report'.tr()),
              actions: [
                IconButton(
                  tooltip: 'common.print'.tr(),
                  onPressed: snapshot.hasData
                      ? () => _export(
                          () => UnappliedAdvancesExportService.printPdf(
                            context: context,
                            rows: _visibleRows,
                            summaries: _service.summarize(_visibleRows),
                          ),
                          'print_unapplied_advances_report',
                        )
                      : null,
                  icon: const Icon(LucideIcons.printer),
                ),
                IconButton(
                  tooltip: 'common.share'.tr(),
                  onPressed: snapshot.hasData
                      ? () => _export(
                          () => UnappliedAdvancesExportService.sharePdf(
                            context: context,
                            rows: _visibleRows,
                            summaries: _service.summarize(_visibleRows),
                          ),
                          'share_unapplied_advances_report',
                        )
                      : null,
                  icon: const Icon(LucideIcons.share2),
                ),
                IconButton(
                  tooltip: 'reports.export_excel'.tr(),
                  onPressed: snapshot.hasData
                      ? () => _export(
                          () => UnappliedAdvancesExportService.shareExcel(
                            context: context,
                            rows: _visibleRows,
                            summaries: _service.summarize(_visibleRows),
                          ),
                          'export_unapplied_advances_excel',
                        )
                      : null,
                  icon: const Icon(LucideIcons.fileSpreadsheet),
                ),
              ],
            ),
            body: _body(snapshot, rows, summaries),
          );
        },
      );

  Widget _body(
    AsyncSnapshot<List<UnappliedAdvanceReportRow>> snapshot,
    List<UnappliedAdvanceReportRow> rows,
    List<UnappliedAdvanceCurrencySummary> summaries,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(snapshot.error.toString(), textAlign: TextAlign.center),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'reports.search_unapplied_advances'.tr(),
                  prefixIcon: const Icon(LucideIcons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(LucideIcons.x),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: UnappliedAdvancePartyFilter.values
                      .map(
                        (filter) => ChoiceChip(
                          selected: _filter == filter,
                          label: Text(_filterLabel(filter)),
                          onSelected: (_) => setState(() => _filter = filter),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ],
          ),
        ),
        if (summaries.isNotEmpty)
          SizedBox(
            height: 108,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: summaries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) =>
                  _SummaryCard(summary: summaries[index]),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: rows.isEmpty
              ? _EmptyState(
                  hasSourceRows: (snapshot.data ?? const []).isNotEmpty,
                )
              : LayoutBuilder(
                  builder: (context, constraints) => constraints.maxWidth >= 760
                      ? _AdvanceTable(rows: rows)
                      : _AdvanceCards(rows: rows),
                ),
        ),
      ],
    );
  }

  List<UnappliedAdvanceReportRow> _filtered(
    List<UnappliedAdvanceReportRow> rows,
  ) {
    final query = _searchController.text.trim().toLowerCase();
    return rows
        .where((row) {
          if (_filter != UnappliedAdvancePartyFilter.all &&
              row.partyType != _filter.name) {
            return false;
          }
          return query.isEmpty ||
              row.partyName.toLowerCase().contains(query) ||
              row.chequeNumber.toLowerCase().contains(query) ||
              row.currencyCode.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  String _filterLabel(UnappliedAdvancePartyFilter filter) => switch (filter) {
    UnappliedAdvancePartyFilter.all => 'common.all'.tr(),
    UnappliedAdvancePartyFilter.customer => 'reports.advance_customers'.tr(),
    UnappliedAdvancePartyFilter.supplier => 'reports.advance_suppliers'.tr(),
  };

  Future<void> _export(
    Future<void> Function() action,
    String auditAction,
  ) async {
    try {
      await action();
      await sl<AuditLogService>().log(
        entityType: 'report',
        entityId: 0,
        action: auditAction,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${'common.error'.tr()}: $error')));
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final UnappliedAdvanceCurrencySummary summary;

  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) => Card(
    child: SizedBox(
      width: 260,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              summary.currencyCode,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            _summaryLine(
              context,
              'reports.customer_advances'.tr(),
              _money(summary.currencySymbol, summary.customerCents),
            ),
            _summaryLine(
              context,
              'reports.supplier_advances'.tr(),
              _money(summary.currencySymbol, summary.supplierCents),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _summaryLine(BuildContext context, String label, String value) => Row(
    children: [
      Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      const SizedBox(width: 8),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    ],
  );
}

class _AdvanceCards extends StatelessWidget {
  final List<UnappliedAdvanceReportRow> rows;

  const _AdvanceCards({required this.rows});

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    itemCount: rows.length,
    separatorBuilder: (_, _) => const SizedBox(height: 8),
    itemBuilder: (_, index) {
      final row = rows[index];
      final isCustomer = row.partyType == 'customer';
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(isCustomer ? LucideIcons.user : LucideIcons.truck),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      row.partyName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    _money(row.currencySymbol, row.unappliedCents),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${'reports.advance_cheque_number'.tr()}: ${row.chequeNumber}',
              ),
              Text(
                '${'reports.advance_recognized_date'.tr()}: ${AppDateFormatter.date(row.recognizedAt)}',
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  Text(
                    '${'reports.advance_original_amount'.tr()}: ${_money(row.currencySymbol, row.amountCents)}',
                  ),
                  Text(
                    '${'reports.advance_applied_amount'.tr()}: ${_money(row.currencySymbol, row.appliedCents)}',
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

class _AdvanceTable extends StatelessWidget {
  final List<UnappliedAdvanceReportRow> rows;

  const _AdvanceTable({required this.rows});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          DataColumn(label: Text('reports.advance_party_type'.tr())),
          DataColumn(label: Text('reports.advance_party'.tr())),
          DataColumn(label: Text('reports.advance_cheque_number'.tr())),
          DataColumn(label: Text('reports.advance_recognized_date'.tr())),
          DataColumn(label: Text('reports.advance_original_amount'.tr())),
          DataColumn(label: Text('reports.advance_applied_amount'.tr())),
          DataColumn(label: Text('reports.advance_unapplied_amount'.tr())),
        ],
        rows: rows
            .map(
              (row) => DataRow(
                cells: [
                  DataCell(
                    Text(
                      row.partyType == 'customer'
                          ? 'reports.advance_customer'.tr()
                          : 'reports.advance_supplier'.tr(),
                    ),
                  ),
                  DataCell(Text(row.partyName)),
                  DataCell(Text(row.chequeNumber)),
                  DataCell(Text(AppDateFormatter.date(row.recognizedAt))),
                  DataCell(Text(_money(row.currencySymbol, row.amountCents))),
                  DataCell(Text(_money(row.currencySymbol, row.appliedCents))),
                  DataCell(
                    Text(
                      _money(row.currencySymbol, row.unappliedCents),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            )
            .toList(growable: false),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final bool hasSourceRows;

  const _EmptyState({required this.hasSourceRows});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.badgeDollarSign, size: 52),
          const SizedBox(height: 12),
          Text(
            hasSourceRows
                ? 'common.no_results'.tr()
                : 'reports.no_unapplied_advances'.tr(),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

String _money(String symbol, int cents) =>
    '$symbol${(cents / 100).toStringAsFixed(2)}';
