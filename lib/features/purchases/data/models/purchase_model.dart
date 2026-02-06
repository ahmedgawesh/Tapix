import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/purchase_dao.dart';
import '../../domain/entities/purchase_entity.dart';

class PurchaseModel extends PurchaseEntity {
  PurchaseModel({
    required super.id,
    required super.purchaseNumber,
    required super.supplierId,
    super.supplierName,
    required super.subtotalCents,
    super.discountCents,
    required super.taxCents,
    required super.totalCents,
    required super.currencyId,
    required super.status,
    super.notes,
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

  factory PurchaseModel.fromDriftWithSupplier(PurchaseWithSupplier pws) {
    return PurchaseModel(
      id: pws.purchase.id,
      purchaseNumber: pws.purchase.purchaseNumber,
      supplierId: pws.purchase.supplierId,
      supplierName: pws.supplier.name,
      subtotalCents: pws.purchase.subtotalCents,
      taxCents: pws.purchase.taxCents,
      totalCents: pws.purchase.totalCents,
      currencyId: pws.purchase.currencyId,
      status: pws.purchase.status,
      purchaseDate: pws.purchase.purchaseDate,
      createdAt: pws.purchase.createdAt,
      updatedAt: pws.purchase.updatedAt,
    );
  }
}

class PurchaseItemModel extends PurchaseItemEntity {
  PurchaseItemModel({
    required super.id,
    required super.purchaseId,
    required super.productId,
    super.variantId,
    super.productName,
    super.variantSku,
    required super.quantity,
    required super.unitCostCents,
    super.discountCents,
    required super.subtotalCents,
    required super.taxCents,
    required super.totalCents,
    super.expiryDate,
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

  factory PurchaseItemModel.fromDriftWithDetails(PurchaseItemWithDetails d) {
    return PurchaseItemModel(
      id: d.item.id,
      purchaseId: d.item.purchaseId,
      productId: d.item.productId,
      variantId: d.item.variantId,
      productName: d.product.name,
      variantSku: d.variant?.sku,
      quantity: d.item.quantity,
      unitCostCents: d.item.unitCostCents,
      subtotalCents: d.item.subtotalCents,
      taxCents: d.item.taxCents,
      totalCents: d.item.totalCents,
      createdAt: d.item.createdAt,
    );
  }
}

class PurchaseReturnModel extends PurchaseReturnEntity {
  const PurchaseReturnModel({
    required super.id,
    required super.purchaseId,
    required super.returnNumber,
    super.supplierName,
    required super.totalCents,
    required super.currencyId,
    super.reason,
    required super.returnDate,
    required super.createdAt,
  });

  factory PurchaseReturnModel.fromDrift(db.PurchaseReturn r) {
    return PurchaseReturnModel(
      id: r.id,
      purchaseId: r.purchaseId,
      returnNumber: r.returnNumber,
      totalCents: r.totalCents,
      currencyId: r.currencyId,
      reason: r.reason,
      returnDate: r.returnDate,
      createdAt: r.createdAt,
    );
  }
}

class PurchaseReturnItemModel extends PurchaseReturnItemEntity {
  const PurchaseReturnItemModel({
    required super.id,
    required super.returnId,
    required super.purchaseItemId,
    required super.quantity,
    required super.refundCents,
    super.productName,
    super.variantSku,
    required super.createdAt,
  });

  factory PurchaseReturnItemModel.fromDrift(db.PurchaseReturnItem item) {
    return PurchaseReturnItemModel(
      id: item.id,
      returnId: item.returnId,
      purchaseItemId: item.purchaseItemId,
      quantity: item.quantity,
      refundCents: item.refundCents,
      createdAt: item.createdAt,
    );
  }
}
