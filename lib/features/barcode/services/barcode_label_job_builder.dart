import 'package:decimal/decimal.dart';

import '../../../core/database/app_database.dart' hide Product;
import '../../../core/database/daos/product_variant_dao.dart';
import '../../products/domain/entities/product_entity.dart';
import '../data/models/invoice_print_data.dart';
import '../domain/models/barcode_design_state.dart';
import 'barcode_variant_filter.dart';

typedef BarcodeLabelJob = ({Product product, int copies, String? variantInfo});

/// One authoritative resolver for both the on-screen preview and generated
/// PDF/Bluetooth jobs. Keeping variant selection and color/size lookup here
/// prevents measured products from losing their dimensions in one output
/// path while piece products happen to work in another.
class BarcodeLabelJobBuilder {
  final ProductVariantDao variantDao;

  const BarcodeLabelJobBuilder(this.variantDao);

  Future<List<BarcodeLabelJob>> build({
    required List<Product> selectedProducts,
    required BarcodeDesignSettings settings,
    Map<int, String> variantInfoByProductId = const {},
    Set<int> selectedVariantIds = const {},
    InvoicePrintData? invoiceData,
    Map<int, int> currentQuantities = const {},
  }) async {
    // Keep invoice lines as the identity source even when the user changes the
    // quantity selector to "one label", "custom", or "stock". The products
    // exposed by the invoice screen are lightweight label DTOs whose `id` is
    // the variant id. Sending those DTOs through the regular product path
    // makes that variant id look like a product id, which drops color/size in
    // both the preview and the generated PDF.
    if (invoiceData != null && invoiceData.lines.isNotEmpty) {
      // Invoice DTOs created by older screens (and restored invoices created
      // before the color/size joins were added) can still carry a valid
      // variantId while colorName/sizeName are null. Resolve the persisted
      // variant attributes here, at the last shared boundary used by both the
      // preview and every PDF/print path, so no caller can silently drop them.
      final persistedInfoByVariantId = await variantDao
          .getVariantInfoByVariantIds(
            invoiceData.lines.map((line) => line.variantId).toSet().toList(),
          );
      final stockByVariantId = <int, int>{};
      if (settings.quantityMode == QuantityMode.stockQuantity) {
        for (final variantId
            in invoiceData.lines.map((line) => line.variantId).toSet()) {
          final variant = await variantDao.getVariantById(variantId);
          if (variant != null) {
            stockByVariantId[variantId] = variant.stockQuantity;
          }
        }
      }

      final jobs = <BarcodeLabelJob>[];
      for (final line in invoiceData.lines) {
        final copies = switch (settings.quantityMode) {
          QuantityMode.single => 1,
          QuantityMode.custom => settings.copies,
          QuantityMode.invoiceQuantity =>
            currentQuantities[line.variantId] ?? line.quantity,
          QuantityMode.stockQuantity => stockByVariantId[line.variantId] ?? 0,
        };
        if (copies <= 0) continue;
        jobs.add((
          product: productFromInvoiceLine(line),
          copies: copies,
          variantInfo:
              _dimensionLabel(line.sizeName, line.colorName) ??
              persistedInfoByVariantId[line.variantId],
        ));
      }
      return jobs;
    }

    final jobs = <BarcodeLabelJob>[];
    for (final product in selectedProducts) {
      final variants = product.hasVariants
          ? (await variantDao.getVariantsByProduct(product.id))
                .where(
                  (variant) => shouldIncludeBarcodeVariant(
                    variantId: variant.id,
                    isActive: variant.isActive,
                    hasDimensions:
                        variant.colorId != null || variant.sizeId != null,
                    selectedVariantIds: selectedVariantIds,
                  ),
                )
                .toList()
          : <ProductVariant>[];

      if (variants.isEmpty) {
        if (product.hasVariants) continue;
        final copies = _copiesForStock(
          settings: settings,
          stockQuantity: product.stockQuantity,
        );
        if (copies <= 0) continue;
        final loadedInfo = await variantDao.getVariantInfoByProductIds([
          product.id,
        ]);
        jobs.add((
          product: product,
          copies: copies,
          variantInfo:
              variantInfoByProductId[product.id] ?? loadedInfo[product.id],
        ));
        continue;
      }

      final infoByVariantId = await variantDao.getVariantInfoByVariantIds(
        variants.map((variant) => variant.id).toList(),
      );
      for (final variant in variants) {
        final copies = _copiesForStock(
          settings: settings,
          stockQuantity: variant.stockQuantity,
        );
        if (copies <= 0) continue;
        jobs.add((
          product: product.copyWith(
            sku: variant.sku,
            barcode: variant.barcode,
            priceCents: variant.priceCents,
            wholesalePriceCents: variant.wholesalePriceCents,
          ),
          copies: copies,
          variantInfo: infoByVariantId[variant.id],
        ));
      }
    }
    return jobs;
  }

  int _copiesForStock({
    required BarcodeDesignSettings settings,
    required int stockQuantity,
  }) {
    return switch (settings.quantityMode) {
      QuantityMode.single => 1,
      QuantityMode.custom => settings.copies,
      QuantityMode.stockQuantity => stockQuantity,
      QuantityMode.invoiceQuantity => 1,
    };
  }

  static String? _dimensionLabel(String? sizeName, String? colorName) {
    final value = [
      sizeName,
      colorName,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' / ');
    return value.isEmpty ? null : value;
  }

  static Product productFromInvoiceLine(InvoiceLinePrintData line) {
    return Product(
      id: line.variantId,
      name: line.productName,
      sku: line.sku,
      barcode: line.barcode,
      costCents: Decimal.zero,
      priceCents: Decimal.fromInt(
        line.sellingPriceCents ?? line.unitPriceCents,
      ),
      wholesalePriceCents: line.wholesalePriceCents == null
          ? null
          : Decimal.fromInt(line.wholesalePriceCents!),
      stockQuantity: 0,
      minQuantity: 0,
      hasVariants: false,
      isTaxable: false,
      purchaseTaxRateBps: 0,
      salesTaxRateBps: 0,
      isActive: true,
      trackInventory: false,
    );
  }
}
