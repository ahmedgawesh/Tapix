import '../entities/product_entity.dart';
import '../entities/product_variant_entity.dart';
import '../repositories/product_repository.dart';
import '../repositories/product_variant_repository.dart';

/// The transactional meaning of a scanned product barcode.
///
/// A parent product barcode is a lookup/group identifier when the product has
/// variants; it is never allowed to silently identify an arbitrary child.
enum ProductBarcodeResolutionType {
  variant,
  simpleProduct,
  variantParent,
  notFound,
  ambiguous,
}

class ProductBarcodeResolution {
  final ProductBarcodeResolutionType type;
  final Product? product;
  final ProductVariant? variant;

  const ProductBarcodeResolution._({
    required this.type,
    this.product,
    this.variant,
  });

  const ProductBarcodeResolution.variant({
    required Product product,
    required ProductVariant variant,
  }) : this._(
         type: ProductBarcodeResolutionType.variant,
         product: product,
         variant: variant,
       );

  const ProductBarcodeResolution.simpleProduct(Product product)
    : this._(
        type: ProductBarcodeResolutionType.simpleProduct,
        product: product,
      );

  const ProductBarcodeResolution.variantParent(Product product)
    : this._(
        type: ProductBarcodeResolutionType.variantParent,
        product: product,
      );

  const ProductBarcodeResolution.notFound()
    : this._(type: ProductBarcodeResolutionType.notFound);

  const ProductBarcodeResolution.ambiguous()
    : this._(type: ProductBarcodeResolutionType.ambiguous);
}

/// Resolves both product-level and variant-level barcode namespaces using one
/// deterministic policy shared by sales and purchases.
class ProductBarcodeResolver {
  final ProductRepository _productRepository;
  final ProductVariantRepository _variantRepository;

  const ProductBarcodeResolver({
    required ProductRepository productRepository,
    required ProductVariantRepository variantRepository,
  }) : _productRepository = productRepository,
       _variantRepository = variantRepository;

  Future<ProductBarcodeResolution> resolve(String rawBarcode) async {
    final barcode = rawBarcode.trim();
    if (barcode.isEmpty) return const ProductBarcodeResolution.notFound();

    final matches = await Future.wait<Object?>([
      _productRepository.findByBarcode(barcode),
      _variantRepository.getVariantByBarcode(barcode),
    ]);
    final directProduct = matches[0] as Product?;
    final variant = matches[1] as ProductVariant?;

    // The same barcode may intentionally exist on a simple product and its
    // own default variant. A collision across different products, however,
    // is unsafe: choosing either match could move the wrong stock.
    if (directProduct != null &&
        variant != null &&
        directProduct.id != variant.productId) {
      return const ProductBarcodeResolution.ambiguous();
    }

    if (variant != null) {
      final parent = directProduct?.id == variant.productId
          ? directProduct
          : await _productRepository.getProductById(variant.productId);
      if (parent == null || !parent.isActive) {
        return const ProductBarcodeResolution.notFound();
      }

      // A product converted from simple → variants can retain a historical
      // default row that shares the parent barcode. More generally, whenever
      // the scanned value matches BOTH the parent and one of its children,
      // its parent meaning wins: the operator must choose explicitly. A code
      // found only on a child still identifies that exact child directly.
      if (parent.hasVariants && directProduct?.id == parent.id) {
        return ProductBarcodeResolution.variantParent(parent);
      }
      return ProductBarcodeResolution.variant(
        product: parent,
        variant: variant,
      );
    }

    if (directProduct == null || !directProduct.isActive) {
      return const ProductBarcodeResolution.notFound();
    }

    if (directProduct.hasVariants) {
      return ProductBarcodeResolution.variantParent(directProduct);
    }
    return ProductBarcodeResolution.simpleProduct(directProduct);
  }
}
