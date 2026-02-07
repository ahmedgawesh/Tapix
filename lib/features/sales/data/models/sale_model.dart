import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/sale_dao.dart';
import '../../domain/entities/sale_entity.dart';

class SaleModel extends SaleEntity {
  SaleModel({
    required super.id,
    required super.invoiceNumber,
    super.customerId,
    super.customerName,
    super.employeeId,
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
      employeeId: swc.sale.employeeId,
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
    required super.quantity,
    required super.unitPriceCents,
    required super.subtotalCents,
    required super.discountCents,
    required super.taxCents,
    required super.totalCents,
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
      quantity: details.item.quantity,
      unitPriceCents: details.item.unitPriceCents,
      subtotalCents: details.item.subtotalCents,
      discountCents: details.item.discountCents,
      taxCents: details.item.taxCents,
      totalCents: details.item.totalCents,
      createdAt: details.item.createdAt,
    );
  }
}

class SaleReturnModel extends SaleReturnEntity {
  const SaleReturnModel({
    required super.id,
    required super.saleId,
    super.saleInvoiceNumber,
    super.customerName,
    required super.returnNumber,
    required super.totalCents,
    required super.currencyId,
    super.status,
    super.dispositionType,
    super.reason,
    required super.returnDate,
    required super.createdAt,
  });

  factory SaleReturnModel.fromDrift(db.SaleReturn ret) {
    return SaleReturnModel(
      id: ret.id,
      saleId: ret.saleId,
      returnNumber: ret.returnNumber,
      totalCents: ret.totalCents,
      currencyId: ret.currencyId,
      status: ret.status,
      dispositionType: ret.dispositionType,
      reason: ret.reason,
      returnDate: ret.returnDate,
      createdAt: ret.createdAt,
    );
  }
}

class SaleReturnItemModel extends SaleReturnItemEntity {
  const SaleReturnItemModel({
    required super.id,
    required super.returnId,
    required super.saleItemId,
    required super.quantity,
    required super.refundCents,
    super.reason,
    required super.createdAt,
  });

  factory SaleReturnItemModel.fromDrift(db.SaleReturnItem item) {
    return SaleReturnItemModel(
      id: item.id,
      returnId: item.returnId,
      saleItemId: item.saleItemId,
      quantity: item.quantity,
      refundCents: item.refundCents,
      reason: item.reason,
      createdAt: item.createdAt,
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
