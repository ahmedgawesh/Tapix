import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import '../domain/entities/import_file_data.dart';
import '../domain/entities/import_result.dart';
import '../domain/repositories/product_repository.dart';
import '../domain/repositories/product_variant_repository.dart';
import '../domain/repositories/category_repository.dart';
import '../data/models/category_model.dart';
import '../domain/usecases/import_products.dart';

class ProductImportService implements ImportProducts {
  final ProductRepository _productRepository;
  final ProductVariantRepository _variantRepository;
  final CategoryRepository _categoryRepository;

  ProductImportService(this._productRepository, this._variantRepository, this._categoryRepository);

  @override
  Future<ImportResult> call({
    required ImportFileData fileData,
    required ColumnMapping columnMapping,
    Stream<ImportProgress> Function()? progressStream,
  }) async {
    final startTime = DateTime.now();
    final errors = <ImportError>[];
    final rowToProductId = <int, int>{};

    // --- Phase 1: Parse all rows ---
    final parsedRows = <_ParsedRow>[];
    for (var rowIndex = 0; rowIndex < fileData.rows.length; rowIndex++) {
      final row = fileData.rows[rowIndex];
      try {
        parsedRows.add(_parseRow(row, rowIndex, columnMapping, fileData.headers));
      } catch (e) {
        errors.add(ImportError(
          rowIndex: rowIndex,
          field: 'import_products.field_row'.tr(),
          message: e.toString(),
          severity: ImportErrorSeverity.error,
        ));
      }
    }

    if (parsedRows.isEmpty) {
      final duration = DateTime.now().difference(startTime);
      return ImportResult(
        totalRows: fileData.rows.length,
        successfulRows: 0,
        failedRows: fileData.rows.length,
        errors: errors,
        rowToProductId: rowToProductId,
        duration: duration,
      );
    }

    // --- Phase 2: Group rows by product name ---
    // Rows with the same name become one product with multiple variants.
    final groupedByName = <String, List<_ParsedRow>>{};
    for (final parsed in parsedRows) {
      final key = parsed.name.toLowerCase().trim();
      groupedByName.putIfAbsent(key, () => []).add(parsed);
    }

    // --- Phase 3: Resolve categories, colors, sizes (create-if-missing) ---
    final categories = await _categoryRepository.getAllCategories();
    final categoryIdByLowerName = {for (final c in categories) c.name.toLowerCase(): c.id};

    final colors = await _variantRepository.getAllColors();
    final sizes = await _variantRepository.getAllSizes();
    final colorIdByLowerName = {for (final c in colors) c.name.toLowerCase(): c.id};
    final sizeIdByLowerName = {for (final s in sizes) s.name.toLowerCase(): s.id};

    int successCount = 0;

    // --- Phase 4: Create one product per group, then variants ---
    for (final entry in groupedByName.entries) {
      final rows = entry.value;
      final firstRow = rows.first;

      try {
        // Determine if this product has variants:
        // 1. If the file explicitly says has_variants=true, respect it
        // 2. If any row has color or size, it's a variant product
        // 3. If multiple rows exist for the same product name, it's a variant product
        // 4. Otherwise, it's a non-variant product
        final hasVariants = firstRow.hasVariants ||
            rows.any((r) => r.color.isNotEmpty || r.size.isNotEmpty) ||
            rows.length > 1;

        // Resolve category from the first row that has one
        int? categoryId;
        for (final r in rows) {
          if (r.category.isNotEmpty) {
            final key = r.category.toLowerCase();
            categoryId = categoryIdByLowerName[key];
            if (categoryId == null) {
              final createdId = await _categoryRepository.createCategory(
                CategoryModel(
                  id: 0,
                  name: r.category,
                  description: null,
                  parentId: null,
                  isActive: true,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                ),
              );
              categoryIdByLowerName[key] = createdId;
              categoryId = createdId;
            }
            break;
          }
        }

        // Use description from the first row that has one
        String? description;
        for (final r in rows) {
          if (r.description.isNotEmpty) {
            description = r.description;
            break;
          }
        }

        if (!hasVariants) {
          // ===== NON-VARIANT PRODUCT =====
          // Single product with product-level SKU/barcode/wholesale price
          // and a default variant for stock/cost/price
          final r = firstRow;

          final productId = await _productRepository.createProduct(
            name: r.name,
            description: description,
            costCents: r.costCents,
            priceCents: r.priceCents,
            wholesalePriceCents: r.wholesalePriceCents,
            stockQuantity: r.stockQuantity,
            minQuantity: r.minQuantity,
            categoryId: categoryId,
            hasVariants: false,
            isTaxable: r.isTaxable,
            isActive: r.isActive,
            sku: r.sku.isEmpty ? null : r.sku,
            barcode: r.barcode.isEmpty ? null : r.barcode,
            trackInventory: true,
          );

          // Create default variant with all pricing data including wholesale
          await _variantRepository.ensureDefaultVariantForProduct(
            productId: productId,
            costCents: r.costCents,
            priceCents: r.priceCents,
            stockQuantity: r.stockQuantity,
          );

          final defaultVariant = await _variantRepository.getDefaultVariantByProduct(productId);
          if (defaultVariant != null) {
            final updated = defaultVariant.copyWith(
              sku: r.sku.isEmpty ? null : r.sku,
              barcode: r.barcode.isEmpty ? null : r.barcode,
              costCents: r.costCents,
              priceCents: r.priceCents,
              wholesalePriceCents: r.wholesalePriceCents,
              stockQuantity: r.stockQuantity,
            );
            await _variantRepository.updateVariant(updated);
          }

          rowToProductId[r.rowIndex] = productId;
          successCount++;
        } else {
          // ===== VARIANT PRODUCT =====
          // Product-level: no SKU/barcode (those belong to variants)
          // Each row becomes a variant with its own color/size/SKU/barcode/pricing
          final productId = await _productRepository.createProduct(
            name: firstRow.name,
            description: description,
            costCents: firstRow.costCents,
            priceCents: firstRow.priceCents,
            wholesalePriceCents: firstRow.wholesalePriceCents,
            stockQuantity: firstRow.stockQuantity,
            minQuantity: firstRow.minQuantity,
            categoryId: categoryId,
            hasVariants: true,
            isTaxable: firstRow.isTaxable,
            isActive: firstRow.isActive,
            trackInventory: true,
          );

          for (final r in rows) {
            int? colorId;
            int? sizeId;

            if (r.color.isNotEmpty) {
              final key = r.color.toLowerCase();
              colorId = colorIdByLowerName[key];
              if (colorId == null) {
                final createdId = await _variantRepository.createColor(r.color, null);
                colorIdByLowerName[key] = createdId;
                colorId = createdId;
              }
            }

            if (r.size.isNotEmpty) {
              final key = r.size.toLowerCase();
              sizeId = sizeIdByLowerName[key];
              if (sizeId == null) {
                final createdId = await _variantRepository.createSize(r.size, 0, null);
                sizeIdByLowerName[key] = createdId;
                sizeId = createdId;
              }
            }

            await _variantRepository.createVariant(
              productId: productId,
              sku: r.sku.isEmpty ? null : r.sku,
              barcode: r.barcode.isEmpty ? null : r.barcode,
              colorId: colorId,
              sizeId: sizeId,
              costCents: r.costCents,
              priceCents: r.priceCents,
              wholesalePriceCents: r.wholesalePriceCents,
              stockQuantity: r.stockQuantity,
            );

            rowToProductId[r.rowIndex] = productId;
            successCount++;
          }
        }
      } catch (e) {
        for (final r in rows) {
          errors.add(ImportError(
            rowIndex: r.rowIndex,
            field: 'import_products.field_bulk_import'.tr(),
            message: 'import_products.error_bulk_import'.tr(args: [e.toString()]),
            severity: ImportErrorSeverity.error,
          ));
        }
      }
    }

    final duration = DateTime.now().difference(startTime);

    return ImportResult(
      totalRows: fileData.rows.length,
      successfulRows: successCount,
      failedRows: fileData.rows.length - successCount,
      errors: errors,
      rowToProductId: rowToProductId,
      duration: duration,
    );
  }

  _ParsedRow _parseRow(
    List<String> row,
    int rowIndex,
    ColumnMapping columnMapping,
    List<String> headers,
  ) {
    final name = _getCellValue(row, columnMapping, 'name');
    if (name.isEmpty) {
      throw Exception('import_products.validation_name_required'.tr());
    }

    final description = _getCellValue(row, columnMapping, 'description');
    final color = _getCellValue(row, columnMapping, 'color');
    final size = _getCellValue(row, columnMapping, 'size');
    final sku = _getCellValue(row, columnMapping, 'sku');
    final barcode = _getCellValue(row, columnMapping, 'barcode');
    final category = _getCellValue(row, columnMapping, 'category');

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

    final hasVariantsStr = _getCellValue(row, columnMapping, 'has_variants');
    final hasVariants = hasVariantsStr.toLowerCase() == 'true' || hasVariantsStr == '1';

    return _ParsedRow(
      rowIndex: rowIndex,
      name: name,
      description: description,
      category: category,
      sku: sku,
      barcode: barcode,
      color: color,
      size: size,
      costCents: costCents,
      priceCents: priceCents,
      wholesalePriceCents: wholesalePriceCents,
      stockQuantity: stockQuantity,
      minQuantity: minQuantity,
      isTaxable: isTaxable,
      isActive: isActive,
      hasVariants: hasVariants,
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

class _ParsedRow {
  final int rowIndex;
  final String name;
  final String description;
  final String category;
  final String sku;
  final String barcode;
  final String color;
  final String size;
  final Decimal costCents;
  final Decimal priceCents;
  final Decimal? wholesalePriceCents;
  final int stockQuantity;
  final int minQuantity;
  final bool isTaxable;
  final bool isActive;
  final bool hasVariants;

  const _ParsedRow({
    required this.rowIndex,
    required this.name,
    required this.description,
    required this.category,
    required this.sku,
    required this.barcode,
    required this.color,
    required this.size,
    required this.costCents,
    required this.priceCents,
    this.wholesalePriceCents,
    required this.stockQuantity,
    required this.minQuantity,
    required this.isTaxable,
    required this.isActive,
    this.hasVariants = false,
  });
}
