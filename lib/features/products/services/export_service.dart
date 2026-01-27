import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import '../domain/repositories/product_repository.dart';
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

  ExportServiceImpl(this._productRepository);

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

    final rows = <List<dynamic>>[
      [
        'id',
        'sku',
        'barcode',
        'name',
        'name_ar',
        'name_fr',
        'description',
        'category_id',
        'supplier_id',
        'cost_cents',
        'price_cents',
        'wholesale_price_cents',
        'currency_id',
        'track_inventory',
        'stock_quantity',
        'min_quantity',
        'has_variants',
        'is_taxable',
        'tax_rate_bps',
        'is_active',
      ],
    ];

    for (final product in filteredProducts) {
      rows.add([
        product.id,
        product.sku ?? '',
        product.barcode ?? '',
        product.name,
        product.nameAr ?? '',
        product.nameFr ?? '',
        product.description ?? '',
        product.categoryId ?? '',
        product.supplierId ?? '',
        product.costCents.toBigInt().toInt(),
        product.priceCents.toBigInt().toInt(),
        product.wholesalePriceCents?.toBigInt().toInt() ?? '',
        product.currencyId ?? '',
        product.trackInventory,
        product.stockQuantity,
        product.minQuantity,
        product.hasVariants,
        product.isTaxable,
        product.taxRateBps,
        product.isActive,
      ]);
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

    // Header row
    final headers = [
      'ID',
      'SKU',
      'Barcode',
      'Name',
      'Name (Arabic)',
      'Name (French)',
      'Description',
      'Category ID',
      'Supplier ID',
      'Cost (Cents)',
      'Price (Cents)',
      'Wholesale Price (Cents)',
      'Currency ID',
      'Track Inventory',
      'Stock Quantity',
      'Min Quantity',
      'Has Variants',
      'Is Taxable',
      'Tax Rate (BPS)',
      'Is Active',
    ];

    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    // Data rows
    for (final product in filteredProducts) {
      sheet.appendRow([
        IntCellValue(product.id),
        TextCellValue(product.sku ?? ''),
        TextCellValue(product.barcode ?? ''),
        TextCellValue(product.name),
        TextCellValue(product.nameAr ?? ''),
        TextCellValue(product.nameFr ?? ''),
        TextCellValue(product.description ?? ''),
        product.categoryId != null ? IntCellValue(product.categoryId!) : TextCellValue(''),
        product.supplierId != null ? IntCellValue(product.supplierId!) : TextCellValue(''),
        IntCellValue(product.costCents.toBigInt().toInt()),
        IntCellValue(product.priceCents.toBigInt().toInt()),
        product.wholesalePriceCents != null 
            ? IntCellValue(product.wholesalePriceCents!.toBigInt().toInt()) 
            : TextCellValue(''),
        product.currencyId != null ? IntCellValue(product.currencyId!) : TextCellValue(''),
        TextCellValue(product.trackInventory.toString()),
        IntCellValue(product.stockQuantity),
        IntCellValue(product.minQuantity),
        TextCellValue(product.hasVariants.toString()),
        TextCellValue(product.isTaxable.toString()),
        IntCellValue(product.taxRateBps),
        TextCellValue(product.isActive.toString()),
      ]);
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
