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
    super.paidAmountCents,
    required super.currencyId,
    required super.status,
    super.paymentMethod,
    super.supplierInvoiceRef,
    super.notes,
    required super.purchaseDate,
    super.dueDate,
    required super.createdAt,
    required super.updatedAt,
  });

  factory PurchaseModel.fromDrift(db.Purchase purchase) {
    return PurchaseModel(
      id: purchase.id,
      purchaseNumber: purchase.purchaseNumber,
      supplierId: purchase.supplierId,
      subtotalCents: purchase.subtotalCents,
      discountCents: purchase.discountCents,
      taxCents: purchase.taxCents,
      totalCents: purchase.totalCents,
      paidAmountCents: purchase.paidAmountCents,
      currencyId: purchase.currencyId,
      status: purchase.status,
      paymentMethod: purchase.paymentMethod,
      supplierInvoiceRef: purchase.supplierInvoiceRef,
      notes: purchase.notes,
      purchaseDate: purchase.purchaseDate,
      dueDate: purchase.dueDate,
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
      discountCents: pws.purchase.discountCents,
      taxCents: pws.purchase.taxCents,
      totalCents: pws.purchase.totalCents,
      paidAmountCents: pws.purchase.paidAmountCents,
      currencyId: pws.purchase.currencyId,
      status: pws.purchase.status,
      paymentMethod: pws.purchase.paymentMethod,
      supplierInvoiceRef: pws.purchase.supplierInvoiceRef,
      notes: pws.purchase.notes,
      purchaseDate: pws.purchase.purchaseDate,
      dueDate: pws.purchase.dueDate,
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
      discountCents: item.discountCents,
      subtotalCents: item.subtotalCents,
      taxCents: item.taxCents,
      totalCents: item.totalCents,
      expiryDate: item.expiryDate,
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
      discountCents: d.item.discountCents,
      subtotalCents: d.item.subtotalCents,
      taxCents: d.item.taxCents,
      totalCents: d.item.totalCents,
      expiryDate: d.item.expiryDate,
      createdAt: d.item.createdAt,
    );
  }
}

class PurchaseReturnModel extends PurchaseReturnEntity {
  PurchaseReturnModel({
    required super.id,
    required super.purchaseId,
    required super.returnNumber,
    super.supplierName,
    super.subtotalCents,
    super.discountCents,
    super.taxCents,
    required super.totalCents,
    required super.currencyId,
    super.status,
    super.dispositionType,
    super.refundMethod,
    super.reason,
    required super.returnDate,
    required super.createdAt,
  });

  factory PurchaseReturnModel.fromDrift(db.PurchaseReturn r) {
    return PurchaseReturnModel(
      id: r.id,
      purchaseId: r.purchaseId,
      returnNumber: r.returnNumber,
      subtotalCents: r.subtotalCents,
      discountCents: r.discountCents,
      taxCents: r.taxCents,
      totalCents: r.totalCents,
      currencyId: r.currencyId,
      status: r.status,
      dispositionType: r.dispositionType,
      refundMethod: r.refundMethod,
      reason: r.reason,
      returnDate: r.returnDate,
      createdAt: r.createdAt,
    );
  }
}

class PurchaseReturnItemModel extends PurchaseReturnItemEntity {
  PurchaseReturnItemModel({
    required super.id,
    required super.returnId,
    required super.purchaseItemId,
    required super.quantity,
    super.subtotalCents,
    super.discountCents,
    super.taxCents,
    required super.refundCents,
    super.reason,
    super.productName,
    super.variantSku,
    super.variantBarcode,
    super.colorName,
    super.colorHex,
    super.sizeName,
    required super.createdAt,
  });

  factory PurchaseReturnItemModel.fromDrift(db.PurchaseReturnItem item) {
    return PurchaseReturnItemModel(
      id: item.id,
      returnId: item.returnId,
      purchaseItemId: item.purchaseItemId,
      quantity: item.quantity,
      subtotalCents: item.subtotalCents,
      discountCents: item.discountCents,
      taxCents: item.taxCents,
      refundCents: item.refundCents,
      reason: item.reason,
      createdAt: item.createdAt,
    );
  }

  factory PurchaseReturnItemModel.fromDriftWithDetails(
      PurchaseReturnItemWithDetails d) {
    return PurchaseReturnItemModel(
      id: d.returnItem.id,
      returnId: d.returnItem.returnId,
      purchaseItemId: d.returnItem.purchaseItemId,
      quantity: d.returnItem.quantity,
      subtotalCents: d.returnItem.subtotalCents,
      discountCents: d.returnItem.discountCents,
      taxCents: d.returnItem.taxCents,
      refundCents: d.returnItem.refundCents,
      reason: d.returnItem.reason,
      productName: d.product.name,
      variantSku: d.variant?.sku,
      variantBarcode: d.variant?.barcode,
      colorName: d.colorName,
      colorHex: d.colorHex,
      sizeName: d.sizeName,
      createdAt: d.returnItem.createdAt,
    );
  }
}

class PurchasePaymentModel extends PurchasePaymentEntity {
  const PurchasePaymentModel({
    required super.id,
    required super.purchaseId,
    required super.amountCents,
    required super.currencyId,
    required super.paymentMethod,
    super.reference,
    super.notes,
    required super.paymentDate,
    required super.createdAt,
  });

  factory PurchasePaymentModel.fromDrift(db.PurchasePayment p) {
    return PurchasePaymentModel(
      id: p.id,
      purchaseId: p.purchaseId,
      amountCents: p.amountCents,
      currencyId: p.currencyId,
      paymentMethod: p.paymentMethod,
      reference: p.reference,
      notes: p.notes,
      paymentDate: p.paymentDate,
      createdAt: p.createdAt,
    );
  }
}
