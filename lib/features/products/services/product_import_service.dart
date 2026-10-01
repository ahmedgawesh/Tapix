import 'package:decimal/decimal.dart';
import 'product_file_metadata.dart';
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
  final ProductFileMetadata? metadata;

  ProductImportService(
    this._productRepository,
    this._variantRepository,
    this._categoryRepository, {
    this.metadata,
  });

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
    final parsedRows = <ProductImportRow>[];
    final codes = <String, int>{};
    for (var rowIndex = 0; rowIndex < fileData.rows.length; rowIndex++) {
      final row = fileData.rows[rowIndex];
      try {
        final parsed = parseRow(row, rowIndex, columnMapping, fileData.headers);
        for (final code in {
          parsed.sku,
          parsed.barcode,
        }.where((v) => v.isNotEmpty)) {
          final key = code.toLowerCase();
          if (codes.containsKey(key) && codes[key] != rowIndex) {
            throw FormatException(
              'import_products.duplicate_code'.tr(args: [code]),
            );
          }
          codes[key] = rowIndex;
        }
        parsedRows.add(parsed);
      } catch (e) {
        errors.add(
          ImportError(
            rowIndex: rowIndex,
            field: 'import_products.field_row'.tr(),
            message: e.toString(),
            severity: ImportErrorSeverity.error,
          ),
        );
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

    // Import is all-or-nothing. Do not write the valid subset when another
    // row did not even parse; that would make retrying the corrected file
    // create duplicates and leave the operator unsure which rows committed.
    if (errors.isNotEmpty) {
      final duration = DateTime.now().difference(startTime);
      return ImportResult(
        totalRows: fileData.rows.length,
        successfulRows: 0,
        failedRows: fileData.rows.length,
        errors: errors,
        rowToProductId: const {},
        duration: duration,
      );
    }

    // Exported group keys separate identical names. Only explicit variant
    // rows in external files use name grouping; simple rows remain separate.
    final groupedByName = <String, List<ProductImportRow>>{};
    for (final parsed in parsedRows) {
      final key = parsed.groupKey;
      groupedByName.putIfAbsent(key, () => []).add(parsed);
    }

    int successCount = 0;

    try {
      // Categories/colors/sizes, products, and all variants share the same
      // AppDatabase instance. Running them in this outer transaction makes
      // the complete file atomic, including metadata created on demand.
      await _productRepository.runInTransaction<void>(() async {
        // --- Phase 3: Resolve categories, colors, sizes (create-if-missing) ---
        final categories = await _categoryRepository.getAllCategories();
        final categoryIdByLowerName = {
          for (final c in categories) c.name.toLowerCase(): c.id,
        };

        final colors = await _variantRepository.getAllColors();
        final sizes = await _variantRepository.getAllSizes();
        final colorIdByLowerName = {
          for (final c in colors) c.name.toLowerCase(): c.id,
        };
        final sizeIdByLowerName = {
          for (final s in sizes) s.name.toLowerCase(): s.id,
        };

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
            final hasVariants =
                firstRow.hasVariantsExplicit ??
                (firstRow.hasVariants ||
                    rows.length > 1 ||
                    rows.any((r) => r.color.isNotEmpty || r.size.isNotEmpty));
            if ((!hasVariants && rows.length != 1) ||
                rows.any(
                  (r) => r.productSignature != firstRow.productSignature,
                )) {
              throw FormatException('import_products.group_conflict'.tr());
            }
            final supplierId = await metadata?.supplier(
              firstRow.supplierCode,
              firstRow.supplierName,
              firstRow.supplierId,
            );
            final currencyId = await metadata?.currency(
              firstRow.currencyCode,
              firstRow.currencyId,
            );
            if (metadata == null && rows.any((r) => r.hasReferences)) {
              throw FormatException('import_products.reference_required'.tr());
            }

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

            final productId = await _productRepository.createProduct(
              name: firstRow.name,
              nameAr: firstRow.nameAr.isEmpty ? null : firstRow.nameAr,
              nameFr: firstRow.nameFr.isEmpty ? null : firstRow.nameFr,
              description: description,
              costCents: firstRow.costCents,
              priceCents: firstRow.priceCents,
              wholesalePriceCents: firstRow.wholesalePriceCents,
              stockQuantity: 0,
              minQuantity: firstRow.minQuantity,
              categoryId: categoryId,
              supplierId: supplierId,
              currencyId: currencyId,
              hasVariants: hasVariants,
              isTaxable: firstRow.isTaxable,
              purchaseTaxRateBps: firstRow.purchaseTaxRateBps,
              salesTaxRateBps: firstRow.salesTaxRateBps,
              isActive: firstRow.isActive,
              trackInventory: firstRow.trackInventory,
              measurementType: firstRow.measurementType,
              inventoryTrackingType: firstRow.inventoryTrackingType,
              costingMethod: firstRow.costingMethod,
              sku: hasVariants || firstRow.sku.isEmpty ? null : firstRow.sku,
              barcode: hasVariants || firstRow.barcode.isEmpty
                  ? null
                  : firstRow.barcode,
            );
            for (final r in rows) {
              int? colorId;
              int? sizeId;
              if (r.color.isNotEmpty) {
                final key = r.color.toLowerCase();
                colorId =
                    colorIdByLowerName[key] ??
                    await _variantRepository.createColor(r.color, null);
                colorIdByLowerName[key] = colorId;
              }
              if (r.size.isNotEmpty) {
                final key = r.size.toLowerCase();
                sizeId =
                    sizeIdByLowerName[key] ??
                    await _variantRepository.createSize(r.size, 0, null);
                sizeIdByLowerName[key] = sizeId;
              }
              // One operational variant for simple and dimensional products.
              // Opening stock is posted once through the existing inventory service.
              final variantId = await _variantRepository.createVariant(
                productId: productId,
                sku: r.sku.isEmpty ? null : r.sku,
                barcode: r.barcode.isEmpty ? null : r.barcode,
                colorId: colorId,
                sizeId: sizeId,
                costCents: r.costCents,
                priceCents: r.priceCents,
                wholesalePriceCents: r.wholesalePriceCents,
                stockQuantity: r.stockQuantity,
                isActive: r.variantIsActive,
              );
              if (!hasVariants && (colorId != null || sizeId != null)) {
                final created = await _productRepository.getProductById(
                  productId,
                );
                if (created == null ||
                    !await _productRepository.updateProduct(
                      created.copyWith(
                        hasVariants: false,
                        isActive: firstRow.isActive,
                      ),
                    )) {
                  throw StateError(
                    'Could not preserve the simple product definition.',
                  );
                }
              }
              await metadata?.importIdentities(
                r.supplierIdentities,
                productId,
                variantId,
              );
              rowToProductId[r.rowIndex] = productId;
              successCount++;
            }
          } catch (e) {
            for (final r in rows) {
              errors.add(
                ImportError(
                  rowIndex: r.rowIndex,
                  field: 'import_products.field_bulk_import'.tr(),
                  message: 'import_products.error_bulk_import'.tr(
                    args: [e.toString()],
                  ),
                  severity: ImportErrorSeverity.error,
                ),
              );
            }
          }
        }

        if (errors.isNotEmpty) {
          throw const _AtomicImportRollback();
        }
      });
    } catch (e) {
      // The DB transaction has rolled back every product, variant, category,
      // color and size. Reflect that truth in the result as well: no row may
      // be reported successful after an atomic rollback.
      successCount = 0;
      rowToProductId.clear();

      final failedRowIndexes = errors.map((error) => error.rowIndex).toSet();
      for (final row in parsedRows) {
        if (failedRowIndexes.contains(row.rowIndex)) continue;
        errors.add(
          ImportError(
            rowIndex: row.rowIndex,
            field: 'import_products.field_bulk_import'.tr(),
            message: e is _AtomicImportRollback
                ? 'import_products.error_atomic_rollback'.tr()
                : 'import_products.error_bulk_import'.tr(args: [e.toString()]),
            severity: ImportErrorSeverity.error,
          ),
        );
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

  static ProductImportRow parseRow(
    List<String> row,
    int rowIndex,
    ColumnMapping columnMapping,
    List<String> headers,
  ) {
    final detected = ColumnMapping.fromHeaders(headers);
    for (final field in [
      'product_id',
      'measurement_type',
      'inventory_tracking_type',
      'costing_method',
      'track_inventory',
      'has_variants',
      'variant_is_active',
      'supplier_owned_quantity',
      'supplier_identities',
      'purchase_tax_rate_bps',
      'sales_tax_rate_bps',
    ]) {
      if (detected.hasMapping(field) &&
          !columnMapping.hasMapping(field) &&
          _getCellValue(row, detected, field).isNotEmpty) {
        throw FormatException(
          'import_products.policy_mapping_required'.tr(args: [field]),
        );
      }
    }
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
    final costCents = costStr.isEmpty
        ? Decimal.zero
        : _parseMoneyLikeToCents(costStr, header: costHeader);

    final priceIndex = columnMapping.getColumnIndex('price');
    final priceHeader = _getHeader(headers, priceIndex);
    final priceStr = _getCellValue(row, columnMapping, 'price');
    if (priceStr.isEmpty) {
      throw Exception('import_products.validation_price_required'.tr());
    }
    final priceCents = _parseMoneyLikeToCents(priceStr, header: priceHeader);

    final wholesaleIndex = columnMapping.getColumnIndex('wholesale_price');
    final wholesaleHeader = _getHeader(headers, wholesaleIndex);
    final wholesalePriceStr = _getCellValue(
      row,
      columnMapping,
      'wholesale_price',
    );
    final wholesalePriceCents = wholesalePriceStr.isEmpty
        ? null
        : _parseMoneyLikeToCents(wholesalePriceStr, header: wholesaleHeader);

    final stockQuantityStr = _getCellValue(
      row,
      columnMapping,
      'stock_quantity',
    );
    final stockQuantity = stockQuantityStr.isEmpty
        ? 0
        : int.parse(stockQuantityStr);

    final minQuantityStr = _getCellValue(row, columnMapping, 'min_quantity');
    final minQuantity = minQuantityStr.isEmpty ? 0 : int.parse(minQuantityStr);

    String cell(String field) => _getCellValue(row, columnMapping, field);
    bool boolean(String field, bool fallback) {
      final value = cell(field).toLowerCase();
      if (value.isEmpty) return fallback;
      if (value == 'true' || value == '1') return true;
      if (value == 'false' || value == '0') return false;
      throw FormatException(
        'import_products.invalid_value'.tr(args: [field, value]),
      );
    }

    int rate(String field) {
      final value = cell(field);
      final rate = value.isEmpty ? 0 : int.parse(value);
      if (rate < 0 || rate > 10000) {
        throw FormatException(
          'import_products.invalid_value'.tr(args: [field, value]),
        );
      }
      return rate;
    }

    final isTaxable = boolean('is_taxable', false);
    final isActive = boolean('is_active', true);
    final hasVariants = boolean('has_variants', false);
    final trackInventory = boolean('track_inventory', true);
    final measurementType = cell('measurement_type').isEmpty
        ? 'piece'
        : cell('measurement_type');
    final tracking = cell('inventory_tracking_type').isEmpty
        ? 'standard'
        : cell('inventory_tracking_type');
    final costing = cell('costing_method').isEmpty
        ? (tracking == 'standard' ? 'wac' : 'fifo')
        : cell('costing_method');
    if (!{'piece', 'weight', 'length', 'volume'}.contains(measurementType) ||
        !{'standard', 'batch', 'batch_expiry'}.contains(tracking) ||
        !{'wac', 'fifo'}.contains(costing) ||
        (tracking != 'standard' && costing != 'fifo')) {
      throw FormatException('import_products.invalid_inventory_policy'.tr());
    }
    if (stockQuantity < 0 ||
        minQuantity < 0 ||
        costCents < Decimal.zero ||
        priceCents < Decimal.zero ||
        (wholesalePriceCents ?? Decimal.zero) < Decimal.zero) {
      throw FormatException('import_products.negative_value'.tr());
    }
    if (!trackInventory && stockQuantity != 0) {
      throw FormatException('import_products.untracked_stock'.tr());
    }
    if (stockQuantity != 0 && tracking != 'standard') {
      throw FormatException('import_products.batch_stock'.tr());
    }
    final supplierOwned = cell('supplier_owned_quantity');
    if (supplierOwned.isNotEmpty && int.parse(supplierOwned) != 0) {
      throw FormatException('import_products.consignment_stock'.tr());
    }
    if ((!isActive || !boolean('variant_is_active', true)) &&
        stockQuantity != 0) {
      throw FormatException('import_products.inactive_stock'.tr());
    }
    final explicitVariants = cell('has_variants').isEmpty ? null : hasVariants;
    final productKey = cell('product_id');
    final groupKey = productKey.isNotEmpty
        ? 'id:$productKey'
        : (explicitVariants == true ||
              (explicitVariants == null &&
                  (color.isNotEmpty || size.isNotEmpty)))
        ? 'variants:${name.toLowerCase()}'
        : 'row:$rowIndex';

    return ProductImportRow(
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
      hasVariantsExplicit: explicitVariants,
      groupKey: groupKey,
      trackInventory: trackInventory,
      measurementType: measurementType,
      inventoryTrackingType: tracking,
      costingMethod: costing,
      purchaseTaxRateBps: rate('purchase_tax_rate_bps'),
      salesTaxRateBps: rate('sales_tax_rate_bps'),
      variantIsActive: boolean('variant_is_active', true),
      nameAr: cell('name_ar'),
      nameFr: cell('name_fr'),
      supplierCode: cell('supplier_code'),
      supplierName: cell('supplier_name'),
      supplierId: cell('supplier_id'),
      currencyId: cell('currency_id'),
      currencyCode: cell('currency_code'),
      supplierIdentities: cell('supplier_identities'),
    );
  }

  static String _getCellValue(
    List<String> row,
    ColumnMapping columnMapping,
    String field,
  ) {
    final index = columnMapping.getColumnIndex(field);
    if (index == null || index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  static String? _getHeader(List<String> headers, int? index) {
    if (index == null || index < 0 || index >= headers.length) return null;
    return headers[index].trim();
  }

  static Decimal _parseMoneyLikeToCents(
    String value, {
    required String? header,
  }) {
    final cleanedValue = value.replaceAll(',', '').replaceAll(' ', '');

    final normalizedHeader = (header ?? '').toLowerCase();
    final isCentsColumn =
        normalizedHeader.contains('cents') ||
        normalizedHeader.endsWith('_cents');
    if (isCentsColumn) {
      final cents = Decimal.parse(cleanedValue);
      if (cents != cents.round()) {
        throw FormatException('import_products.fractional_cents'.tr());
      }
      return cents;
    }

    final decimal = Decimal.parse(cleanedValue);
    final cents = decimal * Decimal.fromInt(100);
    if (cents != cents.round()) {
      throw FormatException('import_products.fractional_cents'.tr());
    }
    return cents;
  }
}

class _AtomicImportRollback implements Exception {
  const _AtomicImportRollback();
}

class ProductImportRow {
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
  final bool? hasVariantsExplicit;
  final String groupKey;
  final bool trackInventory, variantIsActive;
  final String measurementType, inventoryTrackingType, costingMethod;
  final int purchaseTaxRateBps, salesTaxRateBps;
  final String nameAr,
      nameFr,
      supplierCode,
      supplierName,
      supplierId,
      currencyId,
      currencyCode,
      supplierIdentities;
  bool get hasReferences => [
    supplierCode,
    supplierName,
    supplierId,
    currencyId,
    currencyCode,
    supplierIdentities,
  ].any((v) => v.isNotEmpty);
  String get productSignature => [
    name,
    nameAr,
    nameFr,
    description,
    category,
    minQuantity,
    isTaxable,
    isActive,
    trackInventory,
    hasVariantsExplicit,
    measurementType,
    inventoryTrackingType,
    costingMethod,
    purchaseTaxRateBps,
    salesTaxRateBps,
    supplierCode,
    supplierName,
    supplierId,
    currencyId,
    currencyCode,
  ].join('\u0000');

  const ProductImportRow({
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
    required this.hasVariantsExplicit,
    required this.groupKey,
    required this.trackInventory,
    required this.variantIsActive,
    required this.measurementType,
    required this.inventoryTrackingType,
    required this.costingMethod,
    required this.purchaseTaxRateBps,
    required this.salesTaxRateBps,
    required this.nameAr,
    required this.nameFr,
    required this.supplierCode,
    required this.supplierName,
    required this.supplierId,
    required this.currencyId,
    required this.currencyCode,
    required this.supplierIdentities,
  });
}
