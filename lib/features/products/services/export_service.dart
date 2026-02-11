import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import '../domain/repositories/product_repository.dart';
import '../domain/repositories/product_variant_repository.dart';
import '../domain/repositories/category_repository.dart';
import '../domain/entities/product_entity.dart';
import '../../../core/services/logging_service.dart';

abstract class ExportService {
  Stream<List<Product>> watchProducts({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
  });

  Future<String> exportToCSV({
    int? categoryId,
    int? supplierId,
    bool? activeOnly,
    Set<int>? selectedProductIds,
  });

  Future<Uint8List> exportToExcel({
    int? categoryId,
    int? supplierId,
    bool? activeOnly,
    Set<int>? selectedProductIds,
  });

  Future<List<Product>> getExportPreview({
    int? categoryId,
    int? supplierId,
    bool? activeOnly,
  });
}

class ExportServiceImpl implements ExportService {
  final ProductRepository _productRepository;
  final ProductVariantRepository _variantRepository;
  final CategoryRepository _categoryRepository;

  ExportServiceImpl(this._productRepository, this._variantRepository, this._categoryRepository);

  Future<Map<int, String>> _buildColorNameById() async {
    final colors = await _variantRepository.getAllColors();
    return {for (final c in colors) c.id: c.name};
  }

  Future<Map<int, String>> _buildSizeNameById() async {
    final sizes = await _variantRepository.getAllSizes();
    return {for (final s in sizes) s.id: s.name};
  }

  Future<Map<int, String>> _buildCategoryNameById() async {
    final categories = await _categoryRepository.getAllCategories();
    return {for (final c in categories) c.id: c.name};
  }

  @override
  Stream<List<Product>> watchProducts({
    int? categoryId,
    int? supplierId,
    bool activeOnly = true,
  }) {
    return _productRepository.watchProductsForExport(
      categoryId: categoryId,
      supplierId: supplierId,
      activeOnly: activeOnly,
    );
  }

  @override
  Future<String> exportToCSV({
    int? categoryId,
    int? supplierId,
    bool? activeOnly,
    Set<int>? selectedProductIds,
  }) async {
    LoggingService.methodEntry(
      'exportToCSV',
      params: {
        'categoryId': categoryId,
        'supplierId': supplierId,
        'activeOnly': activeOnly,
      },
      tag: 'ExportService',
    );
    
    try {
      final products = await _productRepository.fetchProductsForExport(
        categoryId: categoryId,
        supplierId: supplierId,
        activeOnly: activeOnly ?? true,
        limit: 100000,
        offset: 0,
      );

      final filteredProducts = (selectedProductIds == null || selectedProductIds.isEmpty)
          ? products
          : products.where((p) => selectedProductIds.contains(p.id)).toList();
      
      LoggingService.info(
        'Fetched products for CSV export',
        params: {'count': products.length},
        tag: 'ExportService',
      );

    final colorNameById = await _buildColorNameById();
    final sizeNameById = await _buildSizeNameById();
    final categoryNameById = await _buildCategoryNameById();

    final rows = <List<dynamic>>[
      [
        'product_id',
        'name',
        'description',
        'category',
        'sku',
        'barcode',
        'color',
        'size',
        'cost_cents',
        'price_cents',
        'wholesale_price_cents',
        'stock_quantity',
        'min_quantity',
        'supplier_id',
        'currency_id',
        'track_inventory',
        'has_variants',
        'is_taxable',
        'tax_rate_bps',
        'is_active',
      ],
    ];

    for (final product in filteredProducts) {
      final categoryName = product.categoryId == null
          ? ''
          : (categoryNameById[product.categoryId!] ?? '');

      if (!product.hasVariants) {
        // Non-variant product: single row with product-level data
        // Use default variant for stock/cost/price if available, but
        // always use product-level SKU/barcode/wholesale price
        final defaultVariant = await _variantRepository.getDefaultVariantByProduct(product.id);

        rows.add([
          product.id,
          product.name,
          product.description ?? '',
          categoryName,
          product.sku ?? '',
          product.barcode ?? '',
          '',
          '',
          (defaultVariant?.costCents ?? product.costCents).toBigInt().toInt(),
          (defaultVariant?.priceCents ?? product.priceCents).toBigInt().toInt(),
          product.wholesalePriceCents?.toBigInt().toInt() ?? '',
          defaultVariant?.stockQuantity ?? product.stockQuantity,
          product.minQuantity,
          product.supplierId ?? '',
          product.currencyId ?? '',
          product.trackInventory,
          false,
          product.isTaxable,
          product.purchaseTaxRateBps,
          product.salesTaxRateBps,
          product.isActive,
        ]);
      } else {
        // Variant product: one row per variant with variant-level data
        final variants = await _variantRepository.getVariantsByProduct(product.id);

        for (final v in variants) {
          final colorName = v.colorId != null ? (colorNameById[v.colorId!] ?? '') : '';
          final sizeName = v.sizeId != null ? (sizeNameById[v.sizeId!] ?? '') : '';

          rows.add([
            product.id,
            product.name,
            product.description ?? '',
            categoryName,
            v.sku ?? '',
            v.barcode ?? '',
            colorName,
            sizeName,
            v.costCents.toBigInt().toInt(),
            v.priceCents.toBigInt().toInt(),
            v.wholesalePriceCents?.toBigInt().toInt() ?? '',
            v.stockQuantity,
            product.minQuantity,
            product.supplierId ?? '',
            product.currencyId ?? '',
            product.trackInventory,
            true,
            product.isTaxable,
            product.purchaseTaxRateBps,
            product.salesTaxRateBps,
            product.isActive,
          ]);
        }
      }
    }

      final csv = const ListToCsvConverter().convert(rows);
      
      LoggingService.info(
        'CSV export completed',
        params: {
          'rows': rows.length.toString(),
          'size': '${csv.length} characters',
        },
        tag: 'ExportService',
      );
      
      return csv;
    } catch (e, st) {
      LoggingService.error(
        'CSV export failed',
        error: e,
        stackTrace: st,
        params: {
          'categoryId': categoryId,
          'supplierId': supplierId,
          'activeOnly': activeOnly,
        },
        tag: 'ExportService',
      );
      rethrow;
    } finally {
      LoggingService.methodExit('exportToCSV', tag: 'ExportService');
    }
  }

  @override
  Future<Uint8List> exportToExcel({
    int? categoryId,
    int? supplierId,
    bool? activeOnly,
    Set<int>? selectedProductIds,
  }) async {
    LoggingService.methodEntry(
      'exportToExcel',
      params: {
        'categoryId': categoryId,
        'supplierId': supplierId,
        'activeOnly': activeOnly,
      },
      tag: 'ExportService',
    );
    
    try {
      final products = await _productRepository.fetchProductsForExport(
        categoryId: categoryId,
        supplierId: supplierId,
        activeOnly: activeOnly ?? true,
        limit: 100000,
        offset: 0,
      );

      final filteredProducts = (selectedProductIds == null || selectedProductIds.isEmpty)
          ? products
          : products.where((p) => selectedProductIds.contains(p.id)).toList();
      
      LoggingService.info(
        'Fetched products for Excel export',
        params: {'count': products.length},
        tag: 'ExportService',
      );

    final excel = Excel.createExcel();
    final sheet = excel['Products'];

    final colorNameById = await _buildColorNameById();
    final sizeNameById = await _buildSizeNameById();
    final categoryNameById = await _buildCategoryNameById();

    // Header row
    final headers = [
      'Product ID',
      'Name',
      'Description',
      'Category',
      'SKU',
      'Barcode',
      'Color',
      'Size',
      'Cost (Cents)',
      'Price (Cents)',
      'Wholesale Price (Cents)',
      'Stock Quantity',
      'Min Quantity',
      'Supplier ID',
      'Currency ID',
      'Track Inventory',
      'Has Variants',
      'Is Taxable',
      'Tax Rate (BPS)',
      'Is Active',
    ];

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    // Data rows
    for (final product in filteredProducts) {
      final categoryName = product.categoryId == null
          ? ''
          : (categoryNameById[product.categoryId!] ?? '');

      if (!product.hasVariants) {
        // Non-variant product: single row with product-level data
        final defaultVariant = await _variantRepository.getDefaultVariantByProduct(product.id);

        sheet.appendRow([
          IntCellValue(product.id),
          TextCellValue(product.name),
          TextCellValue(product.description ?? ''),
          TextCellValue(categoryName),
          TextCellValue(product.sku ?? ''),
          TextCellValue(product.barcode ?? ''),
          TextCellValue(''),
          TextCellValue(''),
          IntCellValue((defaultVariant?.costCents ?? product.costCents).toBigInt().toInt()),
          IntCellValue((defaultVariant?.priceCents ?? product.priceCents).toBigInt().toInt()),
          product.wholesalePriceCents != null
              ? IntCellValue(product.wholesalePriceCents!.toBigInt().toInt())
              : TextCellValue(''),
          IntCellValue(defaultVariant?.stockQuantity ?? product.stockQuantity),
          IntCellValue(product.minQuantity),
          product.supplierId != null ? IntCellValue(product.supplierId!) : TextCellValue(''),
          product.currencyId != null ? IntCellValue(product.currencyId!) : TextCellValue(''),
          TextCellValue(product.trackInventory.toString()),
          TextCellValue('false'),
          TextCellValue(product.isTaxable.toString()),
          IntCellValue(product.purchaseTaxRateBps),
          IntCellValue(product.salesTaxRateBps),
          TextCellValue(product.isActive.toString()),
        ]);
      } else {
        // Variant product: one row per variant with variant-level data
        final variants = await _variantRepository.getVariantsByProduct(product.id);

        for (final v in variants) {
          final colorName = v.colorId != null ? (colorNameById[v.colorId!] ?? '') : '';
          final sizeName = v.sizeId != null ? (sizeNameById[v.sizeId!] ?? '') : '';

          sheet.appendRow([
            IntCellValue(product.id),
            TextCellValue(product.name),
            TextCellValue(product.description ?? ''),
            TextCellValue(categoryName),
            TextCellValue(v.sku ?? ''),
            TextCellValue(v.barcode ?? ''),
            TextCellValue(colorName),
            TextCellValue(sizeName),
            IntCellValue(v.costCents.toBigInt().toInt()),
            IntCellValue(v.priceCents.toBigInt().toInt()),
            v.wholesalePriceCents != null
                ? IntCellValue(v.wholesalePriceCents!.toBigInt().toInt())
                : TextCellValue(''),
            IntCellValue(v.stockQuantity),
            IntCellValue(product.minQuantity),
            product.supplierId != null ? IntCellValue(product.supplierId!) : TextCellValue(''),
            product.currencyId != null ? IntCellValue(product.currencyId!) : TextCellValue(''),
            TextCellValue(product.trackInventory.toString()),
            TextCellValue('true'),
            TextCellValue(product.isTaxable.toString()),
            IntCellValue(product.purchaseTaxRateBps),
            IntCellValue(product.salesTaxRateBps),
            TextCellValue(product.isActive.toString()),
          ]);
        }
      }
    }

      final fileBytes = excel.encode();
      
      if (fileBytes == null) {
        throw Exception('Failed to encode Excel file');
      }
      
      final result = Uint8List.fromList(fileBytes);
      
      LoggingService.info(
        'Excel export completed',
        params: {
          'rows': filteredProducts.length.toString(),
          'size': '${result.length} bytes',
        },
        tag: 'ExportService',
      );
      
      return result;
    } catch (e, st) {
      LoggingService.error(
        'Excel export failed',
        error: e,
        stackTrace: st,
        params: {
          'categoryId': categoryId,
          'supplierId': supplierId,
          'activeOnly': activeOnly,
        },
        tag: 'ExportService',
      );
      rethrow;
    } finally {
      LoggingService.methodExit('exportToExcel', tag: 'ExportService');
    }
  }

  @override
  Future<List<Product>> getExportPreview({
    int? categoryId,
    int? supplierId,
    bool? activeOnly,
  }) async {
    return _productRepository.fetchProductsForExport(
      categoryId: categoryId,
      supplierId: supplierId,
      activeOnly: activeOnly ?? true,
      limit: 10,
      offset: 0,
    );
  }
}
