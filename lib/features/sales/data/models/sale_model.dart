import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/sale_dao.dart';
import '../../../../core/database/daos/adjustment_return_dao.dart';
import '../../domain/entities/sale_entity.dart';

class SaleModel extends SaleEntity {
  SaleModel({
    required super.id,
    required super.invoiceNumber,
    super.customerId,
    super.customerName,
    super.customerPhone,
    super.employeeId,
    super.employeeName,
    required super.subtotalCents,
    required super.taxCents,
    required super.discountCents,
    required super.totalCents,
    super.paidAmountCents,
    required super.currencyId,
    required super.paymentMethod,
    required super.status,
    super.notes,
    required super.saleDate,
    super.dueDate,
    required super.createdAt,
    required super.updatedAt,
  });

  factory SaleModel.fromDrift(db.Sale sale) {
    return SaleModel(
      id: sale.id,
      invoiceNumber: sale.invoiceNumber,
      customerId: sale.customerId,
      employeeId: sale.employeeId,
      subtotalCents: sale.subtotalCents,
      taxCents: sale.taxCents,
      discountCents: sale.discountCents,
      totalCents: sale.totalCents,
      paidAmountCents: sale.paidAmountCents,
      currencyId: sale.currencyId,
      paymentMethod: sale.paymentMethod,
      status: sale.status,
      notes: sale.notes,
      saleDate: sale.saleDate,
      dueDate: sale.dueDate,
      createdAt: sale.createdAt,
      updatedAt: sale.updatedAt,
    );
  }

  factory SaleModel.fromDriftWithCustomer(SaleWithCustomer swc) {
    return SaleModel(
      id: swc.sale.id,
      invoiceNumber: swc.sale.invoiceNumber,
      customerId: swc.sale.customerId,
      customerName: swc.customer?.name,
      customerPhone: swc.customer?.phone,
      employeeId: swc.sale.employeeId,
      employeeName: swc.employee?.name,
      subtotalCents: swc.sale.subtotalCents,
      taxCents: swc.sale.taxCents,
      discountCents: swc.sale.discountCents,
      totalCents: swc.sale.totalCents,
      paidAmountCents: swc.sale.paidAmountCents,
      currencyId: swc.sale.currencyId,
      paymentMethod: swc.sale.paymentMethod,
      status: swc.sale.status,
      notes: swc.sale.notes,
      saleDate: swc.sale.saleDate,
      dueDate: swc.sale.dueDate,
      createdAt: swc.sale.createdAt,
      updatedAt: swc.sale.updatedAt,
    );
  }
}

class SaleItemModel extends SaleItemEntity {
  const SaleItemModel({
    required super.id,
    required super.saleId,
    required super.productId,
    super.productName,
    super.variantId,
    super.variantSku,
    super.productSku,
    super.colorName,
    super.colorHex,
    super.sizeName,
    required super.quantity,
    required super.unitPriceCents,
    required super.subtotalCents,
    required super.discountCents,
    required super.taxCents,
    required super.totalCents,
    super.employeeId,
    super.employeeName,
    required super.createdAt,
  });

  factory SaleItemModel.fromDrift(db.SaleItem item) {
    return SaleItemModel(
      id: item.id,
      saleId: item.saleId,
      productId: item.productId,
      variantId: item.variantId,
      quantity: item.quantity,
      unitPriceCents: item.unitPriceCents,
      subtotalCents: item.subtotalCents,
      discountCents: item.discountCents,
      taxCents: item.taxCents,
      totalCents: item.totalCents,
      createdAt: item.createdAt,
    );
  }

  factory SaleItemModel.fromDriftWithDetails(SaleItemWithDetails details) {
    return SaleItemModel(
      id: details.item.id,
      saleId: details.item.saleId,
      productId: details.item.productId,
      productName: details.product.name,
      variantId: details.item.variantId,
      variantSku: details.variant?.sku,
      productSku: details.product.sku,
      colorName: details.colorName,
      colorHex: details.colorHex,
      sizeName: details.sizeName,
      quantity: details.item.quantity,
      unitPriceCents: details.item.unitPriceCents,
      subtotalCents: details.item.subtotalCents,
      discountCents: details.item.discountCents,
      taxCents: details.item.taxCents,
      totalCents: details.item.totalCents,
      employeeId: details.item.employeeId,
      employeeName: details.employee?.name,
      createdAt: details.item.createdAt,
    );
  }
}

class SaleReturnModel extends SaleReturnEntity {
  SaleReturnModel({
    required super.id,
    required super.saleId,
    super.saleInvoiceNumber,
    super.customerName,
    super.customerPhone,
    super.customerId,
    required super.returnNumber,
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
    super.isAdjustment,
    super.unifiedId,
  });

  factory SaleReturnModel.fromDrift(db.SaleReturn ret) {
    return SaleReturnModel(
      id: ret.id,
      saleId: ret.saleId,
      returnNumber: ret.returnNumber,
      subtotalCents: ret.subtotalCents,
      discountCents: ret.discountCents,
      taxCents: ret.taxCents,
      totalCents: ret.totalCents,
      currencyId: ret.currencyId,
      status: ret.status,
      dispositionType: ret.dispositionType,
      refundMethod: ret.refundMethod,
      reason: ret.reason,
      returnDate: ret.returnDate,
      createdAt: ret.createdAt,
      isAdjustment: false,
    );
  }

  factory SaleReturnModel.fromDriftWithParty(SaleReturnWithParty data) {
    return SaleReturnModel(
      id: data.saleReturn.id,
      saleId: data.saleReturn.saleId,
      saleInvoiceNumber: data.saleInvoiceNumber,
      customerName: data.customerName,
      customerPhone: data.customerPhone,
      returnNumber: data.saleReturn.returnNumber,
      subtotalCents: data.saleReturn.subtotalCents,
      discountCents: data.saleReturn.discountCents,
      taxCents: data.saleReturn.taxCents,
      totalCents: data.saleReturn.totalCents,
      currencyId: data.saleReturn.currencyId,
      status: data.saleReturn.status,
      dispositionType: data.saleReturn.dispositionType,
      refundMethod: data.saleReturn.refundMethod,
      reason: data.saleReturn.reason,
      returnDate: data.saleReturn.returnDate,
      createdAt: data.saleReturn.createdAt,
      isAdjustment: false,
    );
  }

  factory SaleReturnModel.fromAdjustment(db.SaleReturnAdjustment adj) {
    return SaleReturnModel(
      id: adj.id,
      saleId: 0, // No linked sale
      customerId: adj.customerId,
      returnNumber: adj.returnNumber,
      totalCents: adj.totalCents,
      currencyId: adj.currencyId,
      status: adj.status,
      refundMethod: adj.refundMethod,
      reason: adj.notes,
      returnDate: adj.returnDate,
      createdAt: adj.createdAt,
      isAdjustment: true,
    );
  }

  factory SaleReturnModel.fromAdjustmentWithParty(SaleAdjReturnWithParty data) {
    return SaleReturnModel(
      id: data.adjustment.id,
      saleId: 0, // No linked sale
      customerId: data.adjustment.customerId,
      customerName: data.customerName,
      customerPhone: data.customerPhone,
      returnNumber: data.adjustment.returnNumber,
      totalCents: data.adjustment.totalCents,
      currencyId: data.adjustment.currencyId,
      status: data.adjustment.status,
      refundMethod: data.adjustment.refundMethod,
      reason: data.adjustment.notes,
      returnDate: data.adjustment.returnDate,
      createdAt: data.adjustment.createdAt,
      isAdjustment: true,
    );
  }
}

class SaleReturnItemModel extends SaleReturnItemEntity {
  SaleReturnItemModel({
    required super.id,
    required super.returnId,
    required super.saleItemId,
    required super.quantity,
    super.subtotalCents,
    super.discountCents,
    super.taxCents,
    required super.refundCents,
    super.reason,
    super.productName,
    super.variantSku,
    super.productSku,
    super.variantBarcode,
    super.colorName,
    super.colorHex,
    super.sizeName,
    required super.createdAt,
  });

  factory SaleReturnItemModel.fromDrift(db.SaleReturnItem item) {
    return SaleReturnItemModel(
      id: item.id,
      returnId: item.returnId,
      saleItemId: item.saleItemId,
      quantity: item.quantity,
      subtotalCents: item.subtotalCents,
      discountCents: item.discountCents,
      taxCents: item.taxCents,
      refundCents: item.refundCents,
      reason: item.reason,
      createdAt: item.createdAt,
    );
  }

  factory SaleReturnItemModel.fromDriftWithDetails(
      SaleReturnItemWithDetails d) {
    return SaleReturnItemModel(
      id: d.returnItem.id,
      returnId: d.returnItem.returnId,
      saleItemId: d.returnItem.saleItemId,
      quantity: d.returnItem.quantity,
      subtotalCents: d.returnItem.subtotalCents,
      discountCents: d.returnItem.discountCents,
      taxCents: d.returnItem.taxCents,
      refundCents: d.returnItem.refundCents,
      reason: d.returnItem.reason,
      productName: d.product.name,
      variantSku: d.variant?.sku,
      productSku: d.product.sku,
      variantBarcode: d.variant?.barcode,
      colorName: d.colorName,
      colorHex: d.colorHex,
      sizeName: d.sizeName,
      createdAt: d.returnItem.createdAt,
    );
  }
}

class SalePaymentModel extends SalePaymentEntity {
  const SalePaymentModel({
    required super.id,
    required super.saleId,
    required super.amountCents,
    required super.currencyId,
    required super.paymentMethod,
    super.reference,
    super.notes,
    required super.paymentDate,
    required super.createdAt,
  });

  factory SalePaymentModel.fromDrift(db.SalePayment payment) {
    return SalePaymentModel(
      id: payment.id,
      saleId: payment.saleId,
      amountCents: payment.amountCents,
      currencyId: payment.currencyId,
      paymentMethod: payment.paymentMethod,
      reference: payment.reference,
      notes: payment.notes,
      paymentDate: payment.paymentDate,
      createdAt: payment.createdAt,
    );
  }
}
