import 'package:decimal/decimal.dart';
import 'product_import_service.dart';
import '../domain/repositories/product_variant_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import '../domain/entities/import_file_data.dart';
import '../domain/entities/import_result.dart';
import '../domain/repositories/product_repository.dart';
import '../domain/usecases/validate_import_data.dart';

class ImportValidationService implements ValidateImportData {
  final ProductRepository _productRepository;

  final ProductVariantRepository? variants;
  ImportValidationService(this._productRepository, {this.variants});

  @override
  Future<List<ImportError>> call({
    required ImportFileData fileData,
    required ColumnMapping columnMapping,
  }) async {
    final errors = <ImportError>[];

    final codes = <String, int>{};
    final groups = <String, ProductImportRow>{};
    for (var rowIndex = 0; rowIndex < fileData.rows.length; rowIndex++) {
      final row = fileData.rows[rowIndex];
      final rowErrors = await _validateRow(row, rowIndex, columnMapping);
      errors.addAll(rowErrors);
      try {
        final parsed = ProductImportService.parseRow(
          row,
          rowIndex,
          columnMapping,
          fileData.headers,
        );
        final first = groups[parsed.groupKey];
        if (first != null &&
            (first.hasVariantsExplicit == false ||
                first.productSignature != parsed.productSignature)) {
          errors.add(
            ImportError(
              rowIndex: rowIndex,
              field: 'product_id',
              message: 'import_products.group_conflict'.tr(),
              severity: ImportErrorSeverity.error,
            ),
          );
        }
        groups[parsed.groupKey] = first ?? parsed;
        for (final code in {
          parsed.sku,
          parsed.barcode,
        }.where((v) => v.isNotEmpty)) {
          final key = code.toLowerCase();
          if (codes.containsKey(key) && codes[key] != rowIndex) {
            errors.add(
              ImportError(
                rowIndex: rowIndex,
                field: 'sku/barcode',
                message: 'import_products.duplicate_code'.tr(args: [code]),
                severity: ImportErrorSeverity.error,
              ),
            );
          }
          codes[key] = rowIndex;
          if (variants != null &&
              (await variants!.isSkuTaken(code) ||
                  await variants!.isBarcodeTaken(code))) {
            errors.add(
              ImportError(
                rowIndex: rowIndex,
                field: 'sku/barcode',
                message: 'import_products.validation_sku_exists'.tr(
                  args: [code],
                ),
                severity: ImportErrorSeverity.error,
              ),
            );
          }
        }
      } catch (e) {
        errors.add(
          ImportError(
            rowIndex: rowIndex,
            field: 'row',
            message: e.toString(),
            severity: ImportErrorSeverity.error,
          ),
        );
      }
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
      errors.add(
        ImportError(
          rowIndex: rowIndex,
          field: 'name',
          message: 'import_products.validation_column_not_mapped'.tr(),
          severity: ImportErrorSeverity.error,
        ),
      );
    } else {
      final name = _getCellValue(row, nameIndex);
      if (name.isEmpty) {
        errors.add(
          ImportError(
            rowIndex: rowIndex,
            field: 'name',
            message: 'import_products.validation_name_required'.tr(),
            severity: ImportErrorSeverity.error,
          ),
        );
      }
    }

    final priceIndex = columnMapping.getColumnIndex('price');
    if (priceIndex != null) {
      final priceStr = _getCellValue(row, priceIndex);
      if (priceStr.isNotEmpty) {
        final priceValidation = _validateMoneyField(
          priceStr,
          'price',
          rowIndex,
        );
        if (priceValidation != null) errors.add(priceValidation);
      } else {
        errors.add(
          ImportError(
            rowIndex: rowIndex,
            field: 'price',
            message: 'import_products.validation_price_required'.tr(),
            severity: ImportErrorSeverity.error,
          ),
        );
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

    final wholesale = columnMapping.getColumnIndex('wholesale_price');
    if (wholesale != null && _getCellValue(row, wholesale).isNotEmpty) {
      final error = _validateMoneyField(
        _getCellValue(row, wholesale),
        'wholesale_price',
        rowIndex,
      );
      if (error != null) errors.add(error);
    }

    final skuIndex = columnMapping.getColumnIndex('sku');
    if (skuIndex != null) {
      final sku = _getCellValue(row, skuIndex);
      if (sku.isNotEmpty) {
        final existingProduct = await _productRepository.findBySku(sku);
        if (existingProduct != null) {
          errors.add(
            ImportError(
              rowIndex: rowIndex,
              field: 'sku',
              message: 'import_products.validation_sku_exists'.tr(args: [sku]),
              severity: ImportErrorSeverity.error,
            ),
          );
        }
      }
    }

    final barcodeIndex = columnMapping.getColumnIndex('barcode');
    if (barcodeIndex != null) {
      final barcode = _getCellValue(row, barcodeIndex);
      if (barcode.isNotEmpty) {
        final existingProduct = await _productRepository.findByBarcode(barcode);
        if (existingProduct != null) {
          errors.add(
            ImportError(
              rowIndex: rowIndex,
              field: 'barcode',
              message: 'import_products.validation_barcode_exists'.tr(
                args: [barcode],
              ),
              severity: ImportErrorSeverity.error,
            ),
          );
        }
      }
    }

    final stockIndex = columnMapping.getColumnIndex('stock_quantity');
    if (stockIndex != null) {
      final stockStr = _getCellValue(row, stockIndex);
      if (stockStr.isNotEmpty) {
        final stockValidation = _validateIntegerField(
          stockStr,
          'stock_quantity',
          rowIndex,
        );
        if (stockValidation != null) errors.add(stockValidation);
      }
    }

    final minStockIndex = columnMapping.getColumnIndex('min_quantity');
    if (minStockIndex != null) {
      final minStockStr = _getCellValue(row, minStockIndex);
      if (minStockStr.isNotEmpty) {
        final minStockValidation = _validateIntegerField(
          minStockStr,
          'min_quantity',
          rowIndex,
        );
        if (minStockValidation != null) errors.add(minStockValidation);
      }
    }

    return errors;
  }

  String _getCellValue(List<String> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  ImportError? _validateMoneyField(
    String value,
    String fieldName,
    int rowIndex,
  ) {
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

  ImportError? _validateIntegerField(
    String value,
    String fieldName,
    int rowIndex,
  ) {
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
