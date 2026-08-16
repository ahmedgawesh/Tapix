import 'package:flutter/material.dart';
import '../../../../core/measurement/measurement_localization.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../domain/entities/product_entity.dart';

class ExportPreviewWidget extends StatelessWidget {
  final List<Product> products;
  final Set<int> selectedProductIds;
  final VoidCallback onToggleSelectAll;
  final ValueChanged<int> onToggleProduct;

  const ExportPreviewWidget({
    super.key,
    required this.products,
    required this.selectedProductIds,
    required this.onToggleSelectAll,
    required this.onToggleProduct,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'export_products.no_products'.tr(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'export_products.preview_description'.tr(
            args: [products.length.toString()],
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            showCheckboxColumn: false,
            columns: [
              DataColumn(
                label: Checkbox(
                  value:
                      selectedProductIds.isNotEmpty &&
                      selectedProductIds.length == products.length,
                  onChanged: (_) => onToggleSelectAll(),
                ),
              ),
              DataColumn(label: Text('export_products.column_id'.tr())),
              DataColumn(label: Text('export_products.column_sku'.tr())),
              DataColumn(label: Text('export_products.column_name'.tr())),
              DataColumn(label: Text('export_products.column_cost_cents'.tr())),
              DataColumn(
                label: Text('export_products.column_price_cents'.tr()),
              ),
              DataColumn(label: Text('export_products.column_stock'.tr())),
            ],
            rows: products.map((product) {
              final isSelected = selectedProductIds.contains(product.id);
              return DataRow(
                selected: isSelected,
                onSelectChanged: (_) => onToggleProduct(product.id),
                cells: [
                  DataCell(
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => onToggleProduct(product.id),
                    ),
                  ),
                  DataCell(Text(product.id.toString())),
                  DataCell(Text(product.sku ?? '-')),
                  DataCell(Text(product.name)),
                  DataCell(
                    Text(product.costCents.toBigInt().toInt().toString()),
                  ),
                  DataCell(
                    Text(product.priceCents.toBigInt().toInt().toString()),
                  ),
                  DataCell(
                    Text(
                      localizedQuantity(
                        product.stockQuantity,
                        product.measurementType,
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
