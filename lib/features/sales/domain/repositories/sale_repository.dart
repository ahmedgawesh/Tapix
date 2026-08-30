import 'package:decimal/decimal.dart';

import '../../../../core/services/return_calculation_service.dart';
import '../entities/sale_entity.dart';

/// Input class for sale line items
class SaleItemInput {
  final int productId;
  final int? variantId;
  final int quantity;
  final int quantityScale;
  final String measurementType;
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
    this.quantityScale = 1,
    this.measurementType = 'piece',
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
  final int quantityScale;
  final String measurementType;
  final Decimal subtotalCents;
  final Decimal discountCents;
  final Decimal taxCents;
  final Decimal refundCents;
  final String? reason;

  const SaleReturnItemInput({
    required this.saleItemId,
    required this.quantity,
    this.quantityScale = 1,
    this.measurementType = 'piece',
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.refundCents,
    this.reason,
  });

  /// Rebuilds the monetary snapshot while requiring the authoritative
  /// quantity representation from the original invoice line.
  SaleReturnItemInput withCalculatedAmounts(
    ProportionalReturnResult result, {
    required int sourceQuantityScale,
    required String sourceMeasurementType,
  }) {
    return SaleReturnItemInput(
      saleItemId: saleItemId,
      quantity: quantity,
      quantityScale: sourceQuantityScale,
      measurementType: sourceMeasurementType,
      subtotalCents: Decimal.fromInt(result.subtotalCents),
      discountCents: Decimal.fromInt(result.discountCents),
      taxCents: Decimal.fromInt(result.taxCents),
      refundCents: Decimal.fromInt(result.refundCents),
      reason: reason,
    );
  }
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
  /// If [allowNegativeStock] is true, stock validation is skipped.
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
    bool allowNegativeStock = false,

    /// Optional request identity. Re-sending the same non-empty value returns
    /// the already-created sale and never posts stock or journals twice.
    String? idempotencyKey,

    /// Explicit actor for trusted master-side LAN commands. Local callers
    /// leave this null and continue using the current local session.
    int? actorUserId,

    /// Phase 11.2 — tax-inclusive flag the engine used to produce the
    /// totals being persisted. Stamped on `sales.tax_inclusive_at_post`.
    bool taxInclusiveAtPost = false,
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

    /// Phase 11.2 — tax-inclusive flag the engine used to produce the
    /// totals being persisted.
    bool taxInclusiveAtPost = false,
  });

  /// Post/complete a sale (deducts stock)
  /// If [allowNegativeStock] is true, stock validation is skipped.
  Future<void> postSale(int saleId, {bool allowNegativeStock = false});

  /// Void a sale (restores stock if completed)
  Future<void> voidSale(int saleId, {int? actorUserId});

  /// Edit a posted sale by voiding the original and creating a new one.
  /// Returns the new sale ID.
  /// Throws if the accounting period is closed or user lacks permission.
  Future<int> editPostedSale({
    required int originalSaleId,
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
    bool allowNegativeStock = false,

    /// Phase 11.2 — tax-inclusive flag the engine used to produce the
    /// totals being persisted.
    bool taxInclusiveAtPost = false,
  });

  /// Delete a sale (only draft/pending)
  Future<void> deleteSale(int saleId);

  // ==================== SALE RETURNS ====================

  /// Watch all sale returns
  Stream<List<SaleReturnEntity>> watchAllSaleReturns();

  /// Get sale return by ID
  Future<SaleReturnEntity?> getSaleReturnById(int id);

  /// Watch return items with full product details
  Stream<List<SaleReturnItemEntity>> watchSaleReturnItemsWithDetails(
    int returnId,
  );

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

    /// Phase 14.0 — cheque due date when `refundMethod` is `cheque`.
    /// Required by the form bloc when refund method is cheque; ignored
    /// (stored as NULL) otherwise. Surfaces on the dashboard reminder.
    DateTime? dueDate,

    /// Optional client-generated idempotency token. The unique constraint on
    /// `sale_returns.idempotency_key` rejects duplicate inserts so a
    /// double-tap or retried network call cannot create two returns / GL
    /// entries / stock movements.
    String? idempotencyKey,

    /// Explicit actor for trusted master-side LAN commands. Local callers
    /// leave this null and continue using the current local session.
    int? actorUserId,

    /// Phase 11.2 — tax-inclusive flag the engine used to produce the
    /// totals being persisted. Stamped on
    /// `sale_returns.tax_inclusive_at_post`.
    bool taxInclusiveAtPost = false,
  });

  /// Void a sale return.
  ///
  /// Voiding a posted return DECREASES stock. If [allowNegativeStock] is false
  /// and current stock is insufficient to cover the reversal, the operation
  /// is rejected.
  Future<void> voidSaleReturn(int returnId, {bool allowNegativeStock = false});

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

  /// Get financial amounts from linked returns only (adjustments excluded).
  Future<LinkedReturnHistory> getLinkedReturnHistory(int saleItemId);

  // ==================== DASHBOARD ====================

  /// Generate next invoice number for display
  Future<String> generateInvoiceNumber();

  /// Watch dashboard stats
  Stream<SaleDashboardStats> watchDashboardStats();

  /// Watch a map of saleId → product search terms (names, barcodes, SKUs)
  Stream<Map<int, List<String>>> watchSaleProductSearchTerms();

  /// Watch product search terms for return items (unifiedId → terms)
  Stream<Map<String, List<String>>> watchSaleReturnProductSearchTerms();
}
