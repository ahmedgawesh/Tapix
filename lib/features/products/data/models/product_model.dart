import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../domain/entities/product_entity.dart';

class ProductModel extends Product {
  const ProductModel({
    required super.id,
    required super.name,
    super.nameAr,
    super.nameFr,
    super.description,
    super.sku,
    super.barcode,
    required super.costCents,
    required super.priceCents,
    super.wholesalePriceCents,
    required super.stockQuantity,
    required super.minQuantity,
    super.categoryId,
    super.supplierId,
    super.currencyId,
    super.imagePath,
    required super.hasVariants,
    required super.isTaxable,
    required super.taxRateBps,
    required super.isActive,
    required super.trackInventory,
  });

  factory ProductModel.fromDrift(db.Product product) {
    return ProductModel(
      id: product.id,
      name: product.name,
      nameAr: product.nameAr,
      nameFr: product.nameFr,
      description: product.description,
      sku: product.sku,
      barcode: product.barcode,
      costCents: product.costCents,
      priceCents: product.priceCents,
      wholesalePriceCents: product.wholesalePriceCents,
      stockQuantity: product.stockQuantity,
      minQuantity: product.minQuantity,
      categoryId: product.categoryId,
      supplierId: product.supplierId,
      currencyId: product.currencyId,
      imagePath: product.imagePath,
      hasVariants: product.hasVariants,
      isTaxable: product.isTaxable,
      taxRateBps: product.taxRateBps,
      isActive: product.isActive,
      trackInventory: product.trackInventory,
    );
  }

  factory ProductModel.fromEntity(Product entity) {
    return ProductModel(
      id: entity.id,
      name: entity.name,
      nameAr: entity.nameAr,
      nameFr: entity.nameFr,
      description: entity.description,
      sku: entity.sku,
      barcode: entity.barcode,
      costCents: entity.costCents,
      priceCents: entity.priceCents,
      wholesalePriceCents: entity.wholesalePriceCents,
      stockQuantity: entity.stockQuantity,
      minQuantity: entity.minQuantity,
      categoryId: entity.categoryId,
      supplierId: entity.supplierId,
      currencyId: entity.currencyId,
      imagePath: entity.imagePath,
      hasVariants: entity.hasVariants,
      isTaxable: entity.isTaxable,
      taxRateBps: entity.taxRateBps,
      isActive: entity.isActive,
      trackInventory: entity.trackInventory,
    );
  }

  db.ProductsCompanion toCompanion() {
    return db.ProductsCompanion(
      id: Value(id),
      name: Value(name),
      nameAr: Value(nameAr),
      nameFr: Value(nameFr),
      description: Value(description),
      sku: Value(sku),
      barcode: Value(barcode),
      costCents: Value(costCents),
      priceCents: Value(priceCents),
      wholesalePriceCents: Value(wholesalePriceCents),
      stockQuantity: Value(stockQuantity),
      minQuantity: Value(minQuantity),
      categoryId: Value(categoryId),
      supplierId: Value(supplierId),
      currencyId: Value(currencyId ?? 1), 
      imagePath: Value(imagePath),
      hasVariants: Value(hasVariants),
      isTaxable: Value(isTaxable),
      taxRateBps: Value(taxRateBps),
      isActive: Value(isActive),
      trackInventory: Value(trackInventory),
    );
  }
}
