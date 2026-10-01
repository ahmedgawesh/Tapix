import 'package:decimal/decimal.dart';

import '../../../../core/services/lan/lan_business_models.dart';
import '../../domain/entities/purchase_entity.dart';

PurchaseEntity lanPurchaseEntity(LanPurchaseSummary value) => PurchaseEntity(
  id: value.id,
  purchaseNumber: value.purchaseNumber,
  supplierId: value.supplierId,
  supplierName: value.supplierName,
  supplierPhone: value.supplierPhone,
  subtotalCents: Decimal.fromInt(value.subtotalCents),
  discountCents: Decimal.fromInt(value.discountCents),
  taxCents: Decimal.fromInt(value.taxCents),
  totalCents: Decimal.fromInt(value.totalCents),
  paidAmountCents: Decimal.fromInt(value.paidAmountCents),
  currencyId: value.currencyId,
  status: value.status,
  paymentMethod: value.paymentMethod,
  supplierInvoiceRef: value.supplierInvoiceRef,
  notes: value.notes,
  purchaseDate: value.purchaseDate,
  dueDate: value.dueDate,
  taxInclusiveAtPost: value.taxInclusiveAtPost,
  createdAt: value.createdAt,
  updatedAt: value.updatedAt,
);

PurchaseItemEntity lanPurchaseItemEntity(LanPurchaseDetailLine value) =>
    PurchaseItemEntity(
      id: value.id,
      purchaseId: value.purchaseId,
      productId: value.productId,
      productName: value.productName,
      variantId: value.variantId,
      variantSku: value.variantSku,
      supplierIdentityRequested: value.supplierIdentityRequested,
      supplierIdentityId: value.supplierIdentityId,
      supplierSourceSku: value.supplierSourceSku,
      colorName: value.colorName,
      colorHex: value.colorHex,
      sizeName: value.sizeName,
      quantity: value.quantity,
      quantityScale: value.quantityScale,
      measurementType: value.measurementType,
      unitCostCents: Decimal.fromInt(value.unitCostCents),
      discountCents: Decimal.fromInt(value.discountCents),
      subtotalCents: Decimal.fromInt(value.subtotalCents),
      taxCents: Decimal.fromInt(value.taxCents),
      totalCents: Decimal.fromInt(value.totalCents),
      originalCostCents: _optionalCents(value.originalCostCents),
      originalPriceCents: _optionalCents(value.originalPriceCents),
      originalWholesalePriceCents: _optionalCents(
        value.originalWholesalePriceCents,
      ),
      newSellPriceCents: _optionalCents(value.newSellPriceCents),
      newWholesalePriceCents: _optionalCents(value.newWholesalePriceCents),
      expiryDate: value.expiryDate,
      manufacturerLotNumber: value.manufacturerLotNumber,
      createdAt: value.createdAt,
    );

Decimal? _optionalCents(int? value) =>
    value == null ? null : Decimal.fromInt(value);

PurchaseReturnEntity lanPurchaseReturnEntity(LanPurchaseReturnSummary value) =>
    PurchaseReturnEntity(
      id: value.id,
      purchaseId: value.purchaseId,
      returnNumber: value.returnNumber,
      supplierId: value.supplierId,
      supplierName: value.supplierName,
      supplierPhone: value.supplierPhone,
      subtotalCents: Decimal.fromInt(value.subtotalCents),
      discountCents: Decimal.fromInt(value.discountCents),
      taxCents: Decimal.fromInt(value.taxCents),
      totalCents: Decimal.fromInt(value.totalCents),
      currencyId: value.currencyId,
      status: value.status,
      dispositionType: value.dispositionType,
      refundMethod: value.refundMethod,
      reason: value.reason,
      returnDate: value.returnDate,
      createdAt: value.createdAt,
      isAdjustment: value.isAdjustment,
      unifiedId: value.unifiedId,
    );
