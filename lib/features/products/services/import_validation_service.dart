import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import '../domain/entities/import_file_data.dart';
import '../domain/entities/import_result.dart';
import '../domain/repositories/product_repository.dart';
import '../domain/usecases/validate_import_data.dart';

class ImportValidationService implements ValidateImportData {
  final ProductRepository _productRepository;

  ImportValidationService(this._productRepository);

  @override
  Future<List<ImportError>> call({
    required ImportFileData fileData,
    required ColumnMapping columnMapping,
  }) async {
    final errors = <ImportError>[];

    for (var rowIndex = 0; rowIndex < fileData.rows.length; rowIndex++) {
      final row = fileData.rows[rowIndex];
      final rowErrors = await _validateRow(row, rowIndex, columnMapping);
      errors.addAll(rowErrors);
    }

    return errors;
  }

  Future<List<ImportError>> _validateRow(
    List<String> row,
    int rowIndex,
    ColumnMapping columnMapping,
  ) async {
    final errors = <ImportError>[];

    final nameIndex = columnMapping.getColumnIndex('name');
    if (nameIndex == null) {
      errors.add(ImportError(
        rowIndex: rowIndex,
        field: 'name',
        message: 'import_products.validation_column_not_mapped'.tr(),
        severity: ImportErrorSeverity.error,
      ));
    } else {
      final name = _getCellValue(row, nameIndex);
      if (name.isEmpty) {
        errors.add(ImportError(
          rowIndex: rowIndex,
          field: 'name',
          message: 'import_products.validation_name_required'.tr(),
          severity: ImportErrorSeverity.error,
        ));
      }
    }

    final priceIndex = columnMapping.getColumnIndex('price');
    if (priceIndex != null) {
      final priceStr = _getCellValue(row, priceIndex);
      if (priceStr.isNotEmpty) {
        final priceValidation = _validateMoneyField(priceStr, 'price', rowIndex);
        if (priceValidation != null) errors.add(priceValidation);
      } else {
        errors.add(ImportError(
          rowIndex: rowIndex,
          field: 'price',
          message: 'import_products.validation_price_required'.tr(),
          severity: ImportErrorSeverity.error,
        ));
      }
    }

    final costIndex = columnMapping.getColumnIndex('cost');
    if (costIndex != null) {
      final costStr = _getCellValue(row, costIndex);
      if (costStr.isNotEmpty) {
        final costValidation = _validateMoneyField(costStr, 'cost', rowIndex);
        if (costValidation != null) errors.add(costValidation);
      }
    }

    final skuIndex = columnMapping.getColumnIndex('sku');
    if (skuIndex != null) {
      final sku = _getCellValue(row, skuIndex);
      if (sku.isNotEmpty) {
        final existingProduct = await _productRepository.findBySku(sku);
        if (existingProduct != null) {
          errors.add(ImportError(
            rowIndex: rowIndex,
            field: 'sku',
            message: 'import_products.validation_sku_exists'.tr(args: [sku]),
            severity: ImportErrorSeverity.error,
          ));
        }
      }
    }

    final barcodeIndex = columnMapping.getColumnIndex('barcode');
    if (barcodeIndex != null) {
      final barcode = _getCellValue(row, barcodeIndex);
      if (barcode.isNotEmpty) {
        final existingProduct = await _productRepository.findByBarcode(barcode);
        if (existingProduct != null) {
          errors.add(ImportError(
            rowIndex: rowIndex,
            field: 'barcode',
            message: 'import_products.validation_barcode_exists'.tr(args: [barcode]),
            severity: ImportErrorSeverity.error,
          ));
        }
      }
    }

    final stockIndex = columnMapping.getColumnIndex('stock_quantity');
    if (stockIndex != null) {
      final stockStr = _getCellValue(row, stockIndex);
      if (stockStr.isNotEmpty) {
        final stockValidation = _validateIntegerField(stockStr, 'stock_quantity', rowIndex);
        if (stockValidation != null) errors.add(stockValidation);
      }
    }

    final minStockIndex = columnMapping.getColumnIndex('min_quantity');
    if (minStockIndex != null) {
      final minStockStr = _getCellValue(row, minStockIndex);
      if (minStockStr.isNotEmpty) {
        final minStockValidation = _validateIntegerField(minStockStr, 'min_quantity', rowIndex);
        if (minStockValidation != null) errors.add(minStockValidation);
      }
    }

    return errors;
  }

  String _getCellValue(List<String> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  ImportError? _validateMoneyField(String value, String fieldName, int rowIndex) {
    try {
      final parsed = Decimal.parse(value.replaceAll(',', ''));
      if (parsed < Decimal.zero) {
        String errorKey;
        switch (fieldName) {
          case 'price':
            errorKey = 'import_products.validation_negative_price';
            break;
          case 'cost':
            errorKey = 'import_products.validation_negative_cost';
            break;
          case 'wholesale_price':
            errorKey = 'import_products.validation_negative_wholesale';
            break;
          default:
            errorKey = 'import_products.validation_negative_price';
        }
        return ImportError(
          rowIndex: rowIndex,
          field: fieldName,
          message: errorKey.tr(),
          severity: ImportErrorSeverity.error,
        );
      }
      return null;
    } catch (e) {
      return ImportError(
        rowIndex: rowIndex,
        field: fieldName,
        message: 'Invalid $fieldName format: $value',
        severity: ImportErrorSeverity.error,
      );
    }
  }

  ImportError? _validateIntegerField(String value, String fieldName, int rowIndex) {
    try {
      final parsed = int.parse(value);
      if (parsed < 0) {
        return ImportError(
          rowIndex: rowIndex,
          field: fieldName,
          message: '$fieldName cannot be negative',
          severity: ImportErrorSeverity.error,
        );
      }
      return null;
    } catch (e) {
      String errorKey;
      switch (fieldName) {
        case 'stock_quantity':
          errorKey = 'import_products.validation_invalid_stock';
          break;
        case 'min_quantity':
          errorKey = 'import_products.validation_invalid_min_stock';
          break;
        default:
          errorKey = 'Invalid integer value for $fieldName';
      }
      return ImportError(
        rowIndex: rowIndex,
        field: fieldName,
        message: errorKey.tr(),
        severity: ImportErrorSeverity.error,
      );
    }
  }
}
