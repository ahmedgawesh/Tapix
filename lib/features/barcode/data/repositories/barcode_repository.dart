import '../../../../core/database/app_database.dart';
import '../models/invoice_print_data.dart';

/// Repository interface for barcode-related operations
/// Handles both barcode design and invoice-based label printing
abstract class BarcodeRepository {
  /// Get purchase invoice data for label printing
  Future<InvoicePrintData> getPurchasePrintData(int purchaseId);

  /// Get sale invoice data for label printing
  Future<InvoicePrintData> getSalePrintData(int saleId);

  /// Get variant information by ID
  Future<ProductVariant?> getVariantById(int variantId);

  /// Get product information by ID
  Future<Product?> getProductById(int productId);

  /// Get color information by ID
  Future<ProductColor?> getColorById(int colorId);

  /// Get size information by ID
  Future<Size?> getSizeById(int sizeId);
}

/// Implementation of BarcodeRepository using Drift database
class BarcodeRepositoryImpl implements BarcodeRepository {
  final AppDatabase _database;

  BarcodeRepositoryImpl(this._database);

  @override
  Future<InvoicePrintData> getPurchasePrintData(int purchaseId) async {
    // Get purchase header information
    final purchase = await (_database.select(_database.purchases)
          ..where((p) => p.id.equals(purchaseId)))
        .getSingleOrNull();

    if (purchase == null) {
      throw InvoiceNotFoundException(purchaseId, 'purchase');
    }

    // Check if posted (status == 'posted')
    if (purchase.status != 'posted') {
      throw InvoiceNotPostedException(purchaseId, 'purchase');
    }

    // Get purchase line items with variant information
    final purchaseItems = await (_database.select(_database.purchaseItems)
          ..where((pi) => pi.purchaseId.equals(purchaseId)))
        .get();

    final lines = <InvoiceLinePrintData>[];

    for (final item in purchaseItems) {
      // Skip if no variant
      if (item.variantId == null) continue;
      
      // Get variant information
      final variant = await getVariantById(item.variantId!);
      if (variant == null || !variant.isActive) {
        continue; // Skip inactive or missing variants
      }

      // Get product information
      final product = await getProductById(variant.productId);
      if (product == null) {
        continue; // Skip products without valid data
      }

      // Get color and size information if available
      String? colorName;
      String? sizeName;

      if (variant.colorId != null) {
        final color = await getColorById(variant.colorId!);
        colorName = color?.name;
      }

      if (variant.sizeId != null) {
        final size = await getSizeById(variant.sizeId!);
        sizeName = size?.name;
      }

      lines.add(InvoiceLinePrintData(
        variantId: variant.id,
        quantity: item.quantity,
        productName: product.name,
        colorName: colorName,
        sizeName: sizeName,
        barcode: variant.barcode ?? '',
        sku: variant.sku ?? '',
        unitPriceCents: item.unitCostCents.toBigInt().toInt(),
        isActive: variant.isActive,
      ));
    }

    return InvoicePrintData(
      lines: lines,
      invoiceType: 'purchase',
      invoiceId: purchase.id,
      invoiceNumber: purchase.purchaseNumber,
      invoiceDate: purchase.purchaseDate,
    );
  }

  @override
  Future<InvoicePrintData> getSalePrintData(int saleId) async {
    // Get sale header information
    final sale = await (_database.select(_database.sales)
          ..where((s) => s.id.equals(saleId)))
        .getSingleOrNull();

    if (sale == null) {
      throw InvoiceNotFoundException(saleId, 'sale');
    }

    // Check if posted (status == 'posted')
    if (sale.status != 'posted') {
      throw InvoiceNotPostedException(saleId, 'sale');
    }

    // Get sale line items with variant information
    final saleItems = await (_database.select(_database.saleItems)
          ..where((si) => si.saleId.equals(saleId)))
        .get();

    final lines = <InvoiceLinePrintData>[];

    for (final item in saleItems) {
      // Skip if no variant
      if (item.variantId == null) continue;
      
      // Get variant information
      final variant = await getVariantById(item.variantId!);
      if (variant == null || !variant.isActive) {
        continue; // Skip inactive or missing variants
      }

      // Get product information
      final product = await getProductById(variant.productId);
      if (product == null) {
        continue; // Skip products without valid data
      }

      // Get color and size information if available
      String? colorName;
      String? sizeName;

      if (variant.colorId != null) {
        final color = await getColorById(variant.colorId!);
        colorName = color?.name;
      }

      if (variant.sizeId != null) {
        final size = await getSizeById(variant.sizeId!);
        sizeName = size?.name;
      }

      lines.add(InvoiceLinePrintData(
        variantId: variant.id,
        quantity: item.quantity,
        productName: product.name,
        colorName: colorName,
        sizeName: sizeName,
        barcode: variant.barcode ?? '',
        sku: variant.sku ?? '',
        unitPriceCents: item.unitPriceCents.toBigInt().toInt(),
        isActive: variant.isActive,
      ));
    }

    return InvoicePrintData(
      lines: lines,
      invoiceType: 'sale',
      invoiceId: sale.id,
      invoiceNumber: sale.invoiceNumber,
      invoiceDate: sale.saleDate,
    );
  }

  @override
  Future<ProductVariant?> getVariantById(int variantId) async {
    return await (_database.select(_database.productVariants)
          ..where((v) => v.id.equals(variantId)))
        .getSingleOrNull();
  }

  @override
  Future<Product?> getProductById(int productId) async {
    return await (_database.select(_database.products)
          ..where((p) => p.id.equals(productId)))
        .getSingleOrNull();
  }

  @override
  Future<ProductColor?> getColorById(int colorId) async {
    return await (_database.select(_database.productColors)
          ..where((c) => c.id.equals(colorId)))
        .getSingleOrNull();
  }

  @override
  Future<Size?> getSizeById(int sizeId) async {
    return await (_database.select(_database.sizes)
          ..where((s) => s.id.equals(sizeId)))
        .getSingleOrNull();
  }
}
