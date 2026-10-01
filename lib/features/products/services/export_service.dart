import 'export_stock_reader.dart';
import 'product_file_metadata.dart';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import '../domain/repositories/product_repository.dart';
import '../domain/repositories/product_variant_repository.dart';
import '../domain/repositories/category_repository.dart';
import '../domain/entities/product_entity.dart';
import '../domain/entities/product_variant_entity.dart';

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
  final ExportStockReader _stockReader;
  final ProductFileMetadata? metadata;

  ExportServiceImpl(
    this._productRepository,
    this._variantRepository,
    this._categoryRepository,
    this._stockReader, {
    this.metadata,
  });

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

  static const headers = [
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
    'purchase_tax_rate_bps',
    'sales_tax_rate_bps',
    'is_active',
    'measurement_type',
    'inventory_tracking_type',
    'costing_method',
    'variant_is_active',
    'name_ar',
    'name_fr',
    'supplier_code',
    'supplier_name',
    'currency_code',
    'supplier_identities',
    'supplier_owned_quantity',
  ];

  Future<List<List<Object>>> _rows({
    int? categoryId,
    int? supplierId,
    bool? activeOnly,
    Set<int>? selectedProductIds,
  }) async {
    final products = <Product>[];
    var offset = 0;
    while (true) {
      final page = await _productRepository.fetchProductsForExport(
        categoryId: categoryId,
        supplierId: supplierId,
        activeOnly: activeOnly ?? true,
        limit: 100000,
        offset: offset,
      );
      products.addAll(page);
      if (page.length < 100000) break;
      offset += page.length;
    }
    final colors = await _buildColorNameById();
    final sizes = await _buildSizeNameById();
    final categories = await _buildCategoryNameById();
    final rows = <List<Object>>[headers];
    for (final p in products) {
      if (selectedProductIds != null &&
          selectedProductIds.isNotEmpty &&
          !selectedProductIds.contains(p.id)) {
        continue;
      }
      final List<ProductVariant?> variants = p.hasVariants
          ? await _variantRepository.getVariantsByProduct(p.id)
          : [await _variantRepository.getDefaultVariantByProduct(p.id)];
      if (!p.hasVariants && variants.single == null) {
        final archived = await _variantRepository.getVariantsByProduct(p.id);
        if (archived.length > 1) {
          throw StateError('Ambiguous archived variants for a simple product.');
        }
        if (archived.isNotEmpty) variants[0] = archived.single;
      }
      // A catalog product with no variants must not disappear from the file.
      if (variants.isEmpty) variants.add(null);
      for (final stored in variants) {
        final v = stored == null ? null : await _stockReader.read(stored);
        final extra = await metadata?.export(p.id, v?.id) ?? <String, Object>{};
        rows.add([
          p.id,
          p.name,
          p.description ?? '',
          categories[p.categoryId] ?? '',
          p.hasVariants ? (v?.sku ?? '') : (p.sku ?? v?.sku ?? ''),
          p.hasVariants ? (v?.barcode ?? '') : (p.barcode ?? v?.barcode ?? ''),
          colors[v?.colorId] ?? '',
          sizes[v?.sizeId] ?? '',
          (v?.costCents ?? p.costCents).toBigInt().toInt(),
          (v?.priceCents ?? p.priceCents).toBigInt().toInt(),
          (v?.wholesalePriceCents ?? p.wholesalePriceCents)
                  ?.toBigInt()
                  .toInt() ??
              '',
          v?.stockQuantity ?? p.stockQuantity,
          p.minQuantity,
          p.supplierId ?? '',
          p.currencyId ?? '',
          p.trackInventory.toString(),
          p.hasVariants.toString(),
          p.isTaxable.toString(),
          p.purchaseTaxRateBps,
          p.salesTaxRateBps,
          p.isActive.toString(),
          p.measurementType,
          p.inventoryTrackingType,
          p.costingMethod,
          (v?.isActive ?? true).toString(),
          p.nameAr ?? '',
          p.nameFr ?? '',
          extra['supplier_code'] ?? '',
          extra['supplier_name'] ?? '',
          extra['currency_code'] ?? '',
          extra['supplier_identities'] ?? '',
          extra['supplier_owned_quantity'] ?? 0,
        ]);
      }
    }
    return rows;
  }

  @override
  Future<String> exportToCSV({
    int? categoryId,
    int? supplierId,
    bool? activeOnly,
    Set<int>? selectedProductIds,
  }) => _stockReader.snapshot(() async {
    final rows = await _rows(
      categoryId: categoryId,
      supplierId: supplierId,
      activeOnly: activeOnly,
      selectedProductIds: selectedProductIds,
    );
    return const CsvEncoder().convert(rows);
  });

  @override
  Future<Uint8List> exportToExcel({
    int? categoryId,
    int? supplierId,
    bool? activeOnly,
    Set<int>? selectedProductIds,
  }) => _stockReader.snapshot(() async {
    final rows = await _rows(
      categoryId: categoryId,
      supplierId: supplierId,
      activeOnly: activeOnly,
      selectedProductIds: selectedProductIds,
    );
    final excel = Excel.createExcel();
    final sheet = excel['Products'];
    excel.delete('Sheet1');
    excel.setDefaultSheet('Products');
    for (final row in rows) {
      sheet.appendRow(
        row
            .map(
              (value) => value is int
                  ? IntCellValue(value)
                  : TextCellValue(value.toString()),
            )
            .toList(),
      );
    }
    return Uint8List.fromList(excel.encode()!);
  });

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
