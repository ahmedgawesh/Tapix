import '../../../../core/database/app_database.dart' as db;
import '../../domain/entities/purchase_entity.dart';

class PurchaseModel extends PurchaseEntity {
  const PurchaseModel({
    required super.id,
    required super.purchaseNumber,
    required super.supplierId,
    required super.subtotalCents,
    required super.taxCents,
    required super.totalCents,
    required super.currencyId,
    required super.status,
    required super.purchaseDate,
    required super.createdAt,
    required super.updatedAt,
  });

  factory PurchaseModel.fromDrift(db.Purchase purchase) {
    return PurchaseModel(
      id: purchase.id,
      purchaseNumber: purchase.purchaseNumber,
      supplierId: purchase.supplierId,
      subtotalCents: purchase.subtotalCents,
      taxCents: purchase.taxCents,
      totalCents: purchase.totalCents,
      currencyId: purchase.currencyId,
      status: purchase.status,
      purchaseDate: purchase.purchaseDate,
      createdAt: purchase.createdAt,
      updatedAt: purchase.updatedAt,
    );
  }
}

class PurchaseItemModel extends PurchaseItemEntity {
  const PurchaseItemModel({
    required super.id,
    required super.purchaseId,
    required super.productId,
    super.variantId,
    required super.quantity,
    required super.unitCostCents,
    required super.subtotalCents,
    required super.taxCents,
    required super.totalCents,
    required super.createdAt,
  });

  factory PurchaseItemModel.fromDrift(db.PurchaseItem item) {
    return PurchaseItemModel(
      id: item.id,
      purchaseId: item.purchaseId,
      productId: item.productId,
      variantId: item.variantId,
      quantity: item.quantity,
      unitCostCents: item.unitCostCents,
      subtotalCents: item.subtotalCents,
      taxCents: item.taxCents,
      totalCents: item.totalCents,
      createdAt: item.createdAt,
    );
  }
}
