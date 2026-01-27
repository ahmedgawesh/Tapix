import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import '../domain/entities/import_file_data.dart';
import '../domain/entities/import_result.dart';
import '../domain/repositories/product_repository.dart';
import '../domain/repositories/product_variant_repository.dart';
import '../domain/usecases/import_products.dart';

class ProductImportService implements ImportProducts {
  final ProductRepository _productRepository;
  final ProductVariantRepository _variantRepository;

  ProductImportService(this._productRepository, this._variantRepository);

  @override
  Future<ImportResult> call({
    required ImportFileData fileData,
    required ColumnMapping columnMapping,
    Stream<ImportProgress> Function()? progressStream,
  }) async {
    final startTime = DateTime.now();
    final errors = <ImportError>[];
    final rowToProductId = <int, int>{};
    final bulkProducts = <BulkProductData>[];

    final rowToColorName = <int, String>{};
    final rowToSizeName = <int, String>{};

    for (var rowIndex = 0; rowIndex < fileData.rows.length; rowIndex++) {
      final row = fileData.rows[rowIndex];
      
      try {
        final productData = _parseRowToProductData(
          row,
          rowIndex,
          columnMapping,
          fileData.headers,
          rowToColorName: rowToColorName,
          rowToSizeName: rowToSizeName,
        );
        bulkProducts.add(productData);
      } catch (e) {
        errors.add(ImportError(
          rowIndex: rowIndex,
          field: 'import_products.field_row'.tr(),
          message: e.toString(),
          severity: ImportErrorSeverity.error,
        ));
      }
    }

    Map<int, int> insertedProducts = {};
    
    if (bulkProducts.isNotEmpty) {
      try {
        insertedProducts = await _productRepository.bulkCreateProducts(bulkProducts);
        rowToProductId.addAll(insertedProducts);

        if (insertedProducts.isNotEmpty) {
          final colors = await _variantRepository.getAllColors();
          final sizes = await _variantRepository.getAllSizes();
          final colorIdByLowerName = {for (final c in colors) c.name.toLowerCase(): c.id};
          final sizeIdByLowerName = {for (final s in sizes) s.name.toLowerCase(): s.id};

          for (final entry in insertedProducts.entries) {
            final rowIndex = entry.key;
            final productId = entry.value;

            final colorName = (rowToColorName[rowIndex] ?? '').trim();
            final sizeName = (rowToSizeName[rowIndex] ?? '').trim();

            int? colorId;
            int? sizeId;

            if (colorName.isNotEmpty) {
              final key = colorName.toLowerCase();
              colorId = colorIdByLowerName[key];
              if (colorId == null) {
                final createdId = await _variantRepository.createColor(colorName, null);
                colorIdByLowerName[key] = createdId;
                colorId = createdId;
              }
            }

            if (sizeName.isNotEmpty) {
              final key = sizeName.toLowerCase();
              sizeId = sizeIdByLowerName[key];
              if (sizeId == null) {
                final createdId = await _variantRepository.createSize(sizeName, 0, null);
                sizeIdByLowerName[key] = createdId;
                sizeId = createdId;
              }
            }

            if (colorId != null || sizeId != null) {
              final product = bulkProducts.firstWhere((p) => p.rowIndex == rowIndex);
              await _variantRepository.createVariant(
                productId: productId,
                colorId: colorId,
                sizeId: sizeId,
                costCents: product.costCents,
                priceCents: product.priceCents,
                stockQuantity: product.stockQuantity,
              );
            }
          }
        }
      } catch (e) {
        errors.add(ImportError(
          rowIndex: -1,
          field: 'import_products.field_bulk_import'.tr(),
          message: 'import_products.error_bulk_import'.tr(args: [e.toString()]),
          severity: ImportErrorSeverity.error,
        ));
      }
    }

    final duration = DateTime.now().difference(startTime);
    
    return ImportResult(
      totalRows: fileData.rows.length,
      successfulRows: insertedProducts.length,
      failedRows: fileData.rows.length - insertedProducts.length,
      errors: errors,
      rowToProductId: rowToProductId,
      duration: duration,
    );
  }

  BulkProductData _parseRowToProductData(
    List<String> row,
    int rowIndex,
    ColumnMapping columnMapping,
    List<String> headers,
    {
    required Map<int, String> rowToColorName,
    required Map<int, String> rowToSizeName,
  }
  ) {
    final name = _getCellValue(row, columnMapping, 'name');
    if (name.isEmpty) {
      throw Exception('import_products.validation_name_required'.tr());
    }

    final color = _getCellValue(row, columnMapping, 'color');
    final size = _getCellValue(row, columnMapping, 'size');
    if (color.isNotEmpty) {
      rowToColorName[rowIndex] = color;
    }
    if (size.isNotEmpty) {
      rowToSizeName[rowIndex] = size;
    }
    final sku = _getCellValue(row, columnMapping, 'sku');
    final barcode = _getCellValue(row, columnMapping, 'barcode');

    final costIndex = columnMapping.getColumnIndex('cost');
    final costHeader = _getHeader(headers, costIndex);
    final costStr = _getCellValue(row, columnMapping, 'cost');
    final costCents = costStr.isEmpty ? Decimal.zero : _parseMoneyLikeToCents(costStr, header: costHeader);

    final priceIndex = columnMapping.getColumnIndex('price');
    final priceHeader = _getHeader(headers, priceIndex);
    final priceStr = _getCellValue(row, columnMapping, 'price');
    if (priceStr.isEmpty) {
      throw Exception('import_products.validation_price_required'.tr());
    }
    final priceCents = _parseMoneyLikeToCents(priceStr, header: priceHeader);

    final wholesaleIndex = columnMapping.getColumnIndex('wholesale_price');
    final wholesaleHeader = _getHeader(headers, wholesaleIndex);
    final wholesalePriceStr = _getCellValue(row, columnMapping, 'wholesale_price');
    final wholesalePriceCents = wholesalePriceStr.isEmpty
        ? null
        : _parseMoneyLikeToCents(wholesalePriceStr, header: wholesaleHeader);

    final stockQuantityStr = _getCellValue(row, columnMapping, 'stock_quantity');
    final stockQuantity = stockQuantityStr.isEmpty ? 0 : int.parse(stockQuantityStr);

    final minQuantityStr = _getCellValue(row, columnMapping, 'min_quantity');
    final minQuantity = minQuantityStr.isEmpty ? 0 : int.parse(minQuantityStr);

    final isTaxableStr = _getCellValue(row, columnMapping, 'is_taxable');
    final isTaxable = isTaxableStr.toLowerCase() == 'true' || isTaxableStr == '1';

    final isActiveStr = _getCellValue(row, columnMapping, 'is_active');
    final isActive = isActiveStr.isEmpty || isActiveStr.toLowerCase() == 'true' || isActiveStr == '1';

    return BulkProductData(
      rowIndex: rowIndex,
      name: name,
      sku: sku.isEmpty ? null : sku,
      barcode: barcode.isEmpty ? null : barcode,
      costCents: costCents,
      priceCents: priceCents,
      wholesalePriceCents: wholesalePriceCents,
      stockQuantity: stockQuantity,
      minQuantity: minQuantity,
      isTaxable: isTaxable,
      isActive: isActive,
    );
  }

  String _getCellValue(List<String> row, ColumnMapping columnMapping, String field) {
    final index = columnMapping.getColumnIndex(field);
    if (index == null || index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  String? _getHeader(List<String> headers, int? index) {
    if (index == null || index < 0 || index >= headers.length) return null;
    return headers[index].trim();
  }

  Decimal _parseMoneyLikeToCents(
    String value, {
    required String? header,
  }) {
    final cleanedValue = value.replaceAll(',', '').replaceAll(' ', '');

    final normalizedHeader = (header ?? '').toLowerCase();
    final isCentsColumn = normalizedHeader.contains('cents') || normalizedHeader.endsWith('_cents');
    if (isCentsColumn) {
      return Decimal.parse(cleanedValue);
    }

    final decimal = Decimal.parse(cleanedValue);
    return decimal * Decimal.fromInt(100);
  }
}
