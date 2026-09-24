import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/measurement/measurement_localization.dart';
import '../bloc/supplier_sales_report_bloc.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/warehouse_report_context.dart';
import '../../services/supplier_sales_export_service.dart';

class SupplierSalesReportScreen extends StatelessWidget {
  const SupplierSalesReportScreen({super.key});
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<SupplierSalesReportBloc>(
      param1: WarehouseReportContext.maybeOf(context)?.scope,
    ),
    child: const _ReportView(),
  );
}

class _ReportView extends StatelessWidget {
  const _ReportView();
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<SupplierSalesReportBloc, RealtimeState<SupplierSalesReportData>>(
    builder: (context, state) {
      final data = state is RealtimeSuccess<SupplierSalesReportData>
          ? state.data
          : null;
      void update({
        int? supplier,
        int? category,
        int? product,
        bool changeSupplier = false,
        bool changeCategory = false,
        bool changeProduct = false,
      }) {
        if (data == null) return;
        context.read<SupplierSalesReportBloc>().add(
          SupplierSalesFilterChanged(
            range: data.range,
            supplierId: changeSupplier ? supplier : data.supplierId,
            categoryId: changeCategory ? category : data.categoryId,
            productId: changeSupplier || changeCategory
                ? null
                : changeProduct
                ? product
                : data.productId,
          ),
        );
      }

      Future<void> export(int choice) async {
        if (data == null) return;
        try {
          await SupplierSalesExportService.export(
            context,
            data,
            excel: choice == 2,
            share: choice == 1,
          );
        } catch (_) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('supplier_sales.export_failed'.tr())),
            );
          }
        }
      }

      return Scaffold(
        appBar: AppBar(
          title: Text('reports.sales_by_supplier'.tr()),
          actions: [
            PopupMenuButton<int>(
              enabled: data != null && data.rows.isNotEmpty,
              onSelected: export,
              itemBuilder: (_) => [
                for (final item in [(0, 'print'), (1, 'share'), (2, 'excel')])
                  PopupMenuItem(
                    value: item.$1,
                    child: Text('supplier_sales.${item.$2}'.tr()),
                  ),
              ],
              icon: const Icon(Icons.ios_share),
            ),
          ],
        ),
        body: SafeArea(
          child: data == null
              ? Center(
                  child: state is RealtimeError<SupplierSalesReportData>
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('supplier_sales.load_failed'.tr()),
                            TextButton(
                              onPressed: () => context
                                  .read<SupplierSalesReportBloc>()
                                  .refresh(),
                              child: Text('common.retry'.tr()),
                            ),
                          ],
                        )
                      : const CircularProgressIndicator(),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DateRangeSelector(
                      dateRange: data.range,
                      onChanged: (range) =>
                          context.read<SupplierSalesReportBloc>().add(
                            SupplierSalesFilterChanged(
                              range: range,
                              supplierId: data.supplierId,
                              categoryId: data.categoryId,
                              productId: data.productId,
                            ),
                          ),
                    ),
                    const SizedBox(height: 12),
                    _SupplierSearch(
                      key: ValueKey(data.supplierId),
                      data: data,
                      onChanged: (id) =>
                          update(supplier: id, changeSupplier: true),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Filter(
                          label: 'supplier_sales.category'.tr(),
                          selected: data.categoryId,
                          options: {
                            for (final e in data.categories.entries)
                              e.key: e.key < 0
                                  ? 'supplier_sales.uncategorized'.tr()
                                  : e.value,
                          },
                          onChanged: (id) =>
                              update(category: id, changeCategory: true),
                        ),
                        _Filter(
                          label: 'supplier_sales.product'.tr(),
                          searchHint: 'supplier_sales.search_product'.tr(),
                          selected: data.productId,
                          options: data.products,
                          onChanged: (id) =>
                              update(product: id, changeProduct: true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'supplier_sales.source_note'.tr(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        for (final e in data.netByCurrency.entries)
                          Chip(
                            label: Text(
                              '${'supplier_sales.net'.tr()}: ${supplierSalesMoney(e.value, e.key)}',
                            ),
                          ),
                      ],
                    ),
                    if (data.rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(child: Text('supplier_sales.empty'.tr())),
                      ),
                    for (final row in data.rows)
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                supplierSalesSourceName(
                                  row.supplierId,
                                  row.supplierName,
                                ),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                              Text(
                                'supplier_sales.quality_${row.sourceQuality}'
                                    .tr(),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                '${row.productName}${row.variantName.isEmpty ? '' : ' • ${row.variantName}'}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              if (row.consignmentReceipts.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '${'supplier_sales.consignment_receipts'.tr()}:',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final receipt
                                        in row.consignmentReceipts)
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text(receipt),
                                      ),
                                  ],
                                ),
                              ],
                              if (row.purchaseInvoices.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '${'supplier_sales.purchase_invoices'.tr()}:',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final invoice in row.purchaseInvoices)
                                      Chip(
                                        visualDensity: VisualDensity.compact,
                                        label: Text(
                                          '${invoice.purchaseNumber} · ${localizedQuantity(invoice.quantity, row.measurementType)}',
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 20,
                                runSpacing: 10,
                                children: [
                                  if (row.purchaseItemId >= 0)
                                    _Metric(
                                      'supplier_sales.purchased'.tr(),
                                      localizedQuantity(
                                        row.purchasedQuantity,
                                        row.measurementType,
                                      ),
                                    ),
                                  _Metric(
                                    'supplier_sales.sold'.tr(),
                                    localizedQuantity(
                                      row.soldQuantity,
                                      row.measurementType,
                                    ),
                                  ),
                                  _Metric(
                                    'supplier_sales.returned'.tr(),
                                    localizedQuantity(
                                      row.returnedQuantity,
                                      row.measurementType,
                                    ),
                                  ),
                                  _Metric(
                                    'supplier_sales.sales'.tr(),
                                    supplierSalesMoney(
                                      row.salesCents,
                                      row.currencyCode,
                                    ),
                                  ),
                                  _Metric(
                                    'supplier_sales.returns'.tr(),
                                    supplierSalesMoney(
                                      row.returnsCents,
                                      row.currencyCode,
                                    ),
                                  ),
                                  _Metric(
                                    'supplier_sales.net'.tr(),
                                    supplierSalesMoney(
                                      row.netCents,
                                      row.currencyCode,
                                    ),
                                  ),
                                  _Metric(
                                    'supplier_sales.tax'.tr(),
                                    supplierSalesMoney(
                                      row.taxCents,
                                      row.currencyCode,
                                    ),
                                  ),
                                  _Metric(
                                    'supplier_sales.discount'.tr(),
                                    supplierSalesMoney(
                                      row.discountCents,
                                      row.currencyCode,
                                    ),
                                  ),
                                ],
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

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _Filter extends StatelessWidget {
  const _Filter({
    required this.label,
    required this.selected,
    required this.options,
    required this.onChanged,
    this.searchHint,
  });
  final String label;
  final String? searchHint;
  final int? selected;
  final Map<int, String> options;
  final ValueChanged<int?> onChanged;
  @override
  Widget build(BuildContext context) => ActionChip(
    label: Text(
      '$label: ${selected == null ? 'supplier_sales.all'.tr() : options[selected] ?? '—'}',
    ),
    avatar: const Icon(Icons.filter_list, size: 18),
    onPressed: () async {
      final result = await showModalBottomSheet<(int?,)>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) =>
            _Picker(label: label, options: options, searchHint: searchHint),
      );
      if (result != null) onChanged(result.$1);
    },
  );
}

class _Picker extends StatefulWidget {
  const _Picker({required this.label, required this.options, this.searchHint});
  final String label;
  final String? searchHint;
  final Map<int, String> options;
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  String query = '';
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(
          children: [
            Text(widget.label, style: Theme.of(context).textTheme.titleLarge),
            TextField(
              onChanged: (v) => setState(() => query = v.toLowerCase().trim()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.searchHint ?? 'supplier_sales.search'.tr(),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    title: Text('supplier_sales.all'.tr()),
                    onTap: () => Navigator.pop(context, (null,)),
                  ),
                  for (final entry in widget.options.entries.where(
                    (e) => e.value.toLowerCase().contains(query),
                  ))
                    ListTile(
                      title: Text(entry.value),
                      onTap: () => Navigator.pop(context, (entry.key,)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SupplierSearch extends StatelessWidget {
  const _SupplierSearch({
    super.key,
    required this.data,
    required this.onChanged,
  });
  final SupplierSalesReportData data;
  final ValueChanged<int?> onChanged;
  @override
  Widget build(BuildContext context) {
    final options = {
      for (final e in data.suppliers.entries)
        e.key: supplierSalesSourceName(e.key, e.value),
    };
    return LayoutBuilder(
      builder: (context, constraints) => Autocomplete<MapEntry<int, String>>(
        initialValue: TextEditingValue(text: options[data.supplierId] ?? ''),
        displayStringForOption: (e) => e.value,
        optionsBuilder: (text) => options.entries.where(
          (e) => e.value.toLowerCase().contains(text.text.toLowerCase().trim()),
        ),
        onSelected: (e) => onChanged(e.key),
        fieldViewBuilder: (context, controller, focus, onSubmit) =>
            TextFormField(
              controller: controller,
              focusNode: focus,
              decoration: InputDecoration(
                labelText: 'supplier_sales.search_supplier'.tr(),
                hintText: 'supplier_sales.search_supplier'.tr(),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'supplier_sales.all'.tr(),
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onChanged(null);
                  },
                ),
              ),
              onFieldSubmitted: (_) => onSubmit(),
            ),
        optionsViewBuilder: (context, select, entries) => Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: constraints.maxWidth,
              height: 220,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: entries.length,
                itemBuilder: (context, i) {
                  final e = entries.elementAt(i);
                  return ListTile(title: Text(e.value), onTap: () => select(e));
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
