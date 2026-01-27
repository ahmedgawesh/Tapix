import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import '../domain/entities/import_file_data.dart';
import '../domain/entities/import_result.dart';
import '../domain/repositories/product_repository.dart';
import '../domain/usecases/import_products.dart';

class ProductImportService implements ImportProducts {
  final ProductRepository _productRepository;

  ProductImportService(this._productRepository);

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

    for (var rowIndex = 0; rowIndex < fileData.rows.length; rowIndex++) {
      final row = fileData.rows[rowIndex];
      
      try {
        final productData = _parseRowToProductData(
          row,
          rowIndex,
          columnMapping,
          fileData.headers,
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
  ) {
    final name = _getCellValue(row, columnMapping, 'name');
    if (name.isEmpty) {
      throw Exception('import_products.validation_name_required'.tr());
    }

    final nameAr = _getCellValue(row, columnMapping, 'name_ar');
    final nameFr = _getCellValue(row, columnMapping, 'name_fr');
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
      nameAr: nameAr.isEmpty ? null : nameAr,
      nameFr: nameFr.isEmpty ? null : nameFr,
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
