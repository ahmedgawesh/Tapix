import 'package:decimal/decimal.dart';

import '../entities/sale_entity.dart';

/// Input class for sale line items
class SaleItemInput {
  final int productId;
  final int? variantId;
  final int quantity;
  final Decimal unitPriceCents;
  final Decimal subtotalCents;
  final Decimal discountCents;
  final Decimal taxCents;
  final Decimal totalCents;
  final int? employeeId;
  final String? employeeName;

  const SaleItemInput({
    required this.productId,
    this.variantId,
    required this.quantity,
    required this.unitPriceCents,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    this.employeeId,
    this.employeeName,
  });
}

/// Input class for sale return items
class SaleReturnItemInput {
  final int saleItemId;
  final int quantity;
  final Decimal subtotalCents;
  final Decimal discountCents;
  final Decimal taxCents;
  final Decimal refundCents;
  final String? reason;

  const SaleReturnItemInput({
    required this.saleItemId,
    required this.quantity,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.refundCents,
    this.reason,
  });
}

abstract class SaleRepository {
  // ==================== SALES ====================

  /// Watch all sales (with customer name resolved)
  Stream<List<SaleEntity>> watchAllSales();

  /// Watch sales for a specific customer
  Stream<List<SaleEntity>> watchCustomerSales(int customerId);

  /// Get sale by ID
  Future<SaleEntity?> getSaleById(int id);

  /// Get sale items for a sale
  Future<List<SaleItemEntity>> getSaleItems(int saleId);

  /// Watch sale items for a sale
  Stream<List<SaleItemEntity>> watchSaleItems(int saleId);

  /// Create a new sale
  Future<int> createSale({
    int? customerId,
    int? employeeId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required Decimal paidAmountCents,
    required String paymentMethod,
    required List<SaleItemInput> items,
    String? notes,
    DateTime? saleDate,
    DateTime? dueDate,
  });

  /// Update an existing sale
  Future<bool> updateSale({
    required int saleId,
    int? customerId,
    int? employeeId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required Decimal paidAmountCents,
    required String paymentMethod,
    required List<SaleItemInput> items,
    String? notes,
    DateTime? saleDate,
    DateTime? dueDate,
  });

  /// Post/complete a sale (deducts stock)
  Future<void> postSale(int saleId);

  /// Void a sale (restores stock if completed)
  Future<void> voidSale(int saleId);

  /// Delete a sale (only draft/pending)
  Future<void> deleteSale(int saleId);

  // ==================== SALE RETURNS ====================

  /// Watch all sale returns
  Stream<List<SaleReturnEntity>> watchAllSaleReturns();

  /// Get sale return by ID
  Future<SaleReturnEntity?> getSaleReturnById(int id);

  /// Watch return items with full product details
  Stream<List<SaleReturnItemEntity>> watchSaleReturnItemsWithDetails(int returnId);

  /// Watch returns for a specific sale
  Stream<List<SaleReturnEntity>> watchSaleReturnsBySale(int saleId);

  /// Watch set of sale IDs that have at least one non-voided return
  Stream<Set<int>> watchSaleIdsWithReturns();

  /// Create a sale return
  Future<int> createSaleReturn({
    required int saleId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required List<SaleReturnItemInput> items,
    String? reason,
    String? dispositionType,
    String? refundMethod,
    DateTime? returnDate,
  });

  /// Void a sale return
  Future<void> voidSaleReturn(int returnId);

  // ==================== SALE PAYMENTS ====================

  /// Watch payments for a sale
  Stream<List<SalePaymentEntity>> watchSalePayments(int saleId);

  /// Get payments for a sale
  Future<List<SalePaymentEntity>> getSalePayments(int saleId);

  /// Record a payment
  Future<int> recordPayment({
    required int saleId,
    required Decimal amountCents,
    required int currencyId,
    required String paymentMethod,
    String? reference,
    String? notes,
    DateTime? paymentDate,
  });

  /// Delete a payment
  Future<void> deletePayment(int paymentId);

  /// Get total returned quantity for a sale item
  Future<int> getReturnedQuantity(int saleItemId);

  // ==================== DASHBOARD ====================

  /// Generate next invoice number for display
  Future<String> generateInvoiceNumber();

  /// Watch dashboard stats
  Stream<SaleDashboardStats> watchDashboardStats();
}
