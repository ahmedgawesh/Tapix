import '../../../../core/database/app_database.dart';
import '../models/invoice_print_data.dart';

/// Repository interface for barcode-related operations
/// Handles both barcode design and invoice-based label printing
abstract class BarcodeRepository {
  /// Get purchase invoice data for label printing
  Future<InvoicePrintData> getPurchasePrintData(
    int purchaseId, {
    bool allowDraft = false,
  });

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
  Future<InvoicePrintData> getPurchasePrintData(
    int purchaseId, {
    bool allowDraft = false,
  }) async {
    // Get purchase header information
    final purchase = await (_database.select(
      _database.purchases,
    )..where((p) => p.id.equals(purchaseId))).getSingleOrNull();

    if (purchase == null) {
      throw InvoiceNotFoundException(purchaseId, 'purchase');
    }

    // Check if posted (status == 'posted')
    if (purchase.status != 'posted' &&
        !(allowDraft && purchase.status == 'draft')) {
      throw InvoiceNotPostedException(purchaseId, 'purchase');
    }

    final items = await _database.purchaseDao.getPurchaseItemsWithDetails(
      purchaseId,
    );
    final lines = <InvoiceLinePrintData>[];
    for (final details in items) {
      final item = details.item;
      final product = details.product;
      // Old draft lines can omit the internal stock variant. Resolve only
      // unambiguous simple products; never pick a random size or color.
      var variant = details.variant;
      if (variant == null && !product.hasVariants) {
        final active = (await _database.productVariantDao.getVariantsByProduct(
          product.id,
        )).where((v) => v.isActive).toList();
        if (active.length == 1) variant = active.single;
      }
      if (variant == null || !variant.isActive) continue;
      final barcode =
          (product.hasVariants
                  ? variant.barcode
                  : (product.barcode?.trim().isNotEmpty == true
                        ? product.barcode
                        : variant.barcode))
              ?.trim() ??
          '';
      if (barcode.isEmpty) continue;
      lines.add(
        InvoiceLinePrintData(
          variantId: variant.id,
          quantity: item.quantity,
          productName: product.name,
          colorName: details.colorName,
          sizeName: details.sizeName,
          barcode: barcode,
          sku: resolveInvoiceLabelSku(
            hasVariants: product.hasVariants,
            productSku: product.sku,
            variantSku: variant.sku,
            supplierSourceSku: details.supplierIdentity?.sourceSku,
          ),
          unitPriceCents: variant.priceCents.toBigInt().toInt(),
          sellingPriceCents: variant.priceCents.toBigInt().toInt(),
          wholesalePriceCents: variant.wholesalePriceCents?.toBigInt().toInt(),
          isActive: variant.isActive,
        ),
      );
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
    final sale = await (_database.select(
      _database.sales,
    )..where((s) => s.id.equals(saleId))).getSingleOrNull();

    if (sale == null) {
      throw InvoiceNotFoundException(saleId, 'sale');
    }

    // Check if posted (status == 'posted')
    if (sale.status != 'posted') {
      throw InvoiceNotPostedException(saleId, 'sale');
    }

    // Get sale line items with variant information
    final saleItems = await (_database.select(
      _database.saleItems,
    )..where((si) => si.saleId.equals(saleId))).get();

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

      lines.add(
        InvoiceLinePrintData(
          variantId: variant.id,
          quantity: item.quantity,
          productName: product.name,
          colorName: colorName,
          sizeName: sizeName,
          barcode: variant.barcode ?? '',
          sku: resolveInvoiceLabelSku(
            hasVariants: product.hasVariants,
            productSku: product.sku,
            variantSku: variant.sku,
          ),
          unitPriceCents: item.unitPriceCents.toBigInt().toInt(),
          sellingPriceCents: variant.priceCents.toBigInt().toInt(),
          wholesalePriceCents: variant.wholesalePriceCents?.toBigInt().toInt(),
          isActive: variant.isActive,
        ),
      );
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
    return await (_database.select(
      _database.productVariants,
    )..where((v) => v.id.equals(variantId))).getSingleOrNull();
  }

  @override
  Future<Product?> getProductById(int productId) async {
    return await (_database.select(
      _database.products,
    )..where((p) => p.id.equals(productId))).getSingleOrNull();
  }

  @override
  Future<ProductColor?> getColorById(int colorId) async {
    return await (_database.select(
      _database.productColors,
    )..where((c) => c.id.equals(colorId))).getSingleOrNull();
  }

  @override
  Future<Size?> getSizeById(int sizeId) async {
    return await (_database.select(
      _database.sizes,
    )..where((s) => s.id.equals(sizeId))).getSingleOrNull();
  }
}
