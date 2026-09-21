import 'package:decimal/decimal.dart';
import '../../../../core/payments/checkout_settlement.dart';
import '../../../../core/services/return_calculation_service.dart';
import '../entities/purchase_entity.dart';

abstract class PurchaseRepository {
  // ==================== PURCHASES ====================

  /// Watch all purchases with supplier info
  Stream<List<PurchaseEntity>> watchAllPurchases();

  /// Watch purchases by status
  Stream<List<PurchaseEntity>> watchPurchasesByStatus(String status);

  /// Watch purchases by supplier
  Stream<List<PurchaseEntity>> watchPurchasesBySupplier(int supplierId);

  /// Search purchases by number or supplier name
  Stream<List<PurchaseEntity>> searchPurchases(String query);

  /// Get purchase by ID with supplier info
  Future<PurchaseEntity?> getPurchaseById(int id);

  /// Get purchase items
  Future<List<PurchaseItemEntity>> getPurchaseItems(int purchaseId);

  /// Watch purchase items with product/variant details
  Stream<List<PurchaseItemEntity>> watchPurchaseItems(int purchaseId);

  /// Generate next purchase number
  Future<String> generatePurchaseNumber();

  /// Create purchase with items
  Future<int> createPurchase({
    required int supplierId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required Decimal paidAmountCents,
    required List<PurchaseItemInput> items,
    String? paymentMethod,
    String? supplierInvoiceRef,
    String? notes,
    DateTime? purchaseDate,
    DateTime? dueDate,

    /// Phase 11.2 — tax-inclusive flag the engine used to produce the
    /// totals being persisted. Stamped on `purchases.tax_inclusive_at_post`.
    bool taxInclusiveAtPost = false,

    /// Payments already handed over at checkout. They stay attached to the
    /// draft and are journaled when the purchase is posted.
    List<CheckoutPaymentAllocation> initialPayments = const [],
  });

  /// Update an existing purchase and replace its items
  Future<bool> updatePurchase({
    required int purchaseId,
    required int supplierId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required Decimal paidAmountCents,
    required List<PurchaseItemInput> items,
    String? paymentMethod,
    String? supplierInvoiceRef,
    String? notes,
    DateTime? purchaseDate,
    DateTime? dueDate,

    /// Phase 11.2 — tax-inclusive flag the engine used to produce the
    /// totals being persisted.
    bool taxInclusiveAtPost = false,
  });

  /// Post purchase (update variant stocks and costs)
  Future<void> postPurchase(int purchaseId);

  /// Void purchase (reverse stock if posted)
  Future<void> voidPurchase(int purchaseId);

  /// Edit a posted purchase by voiding the original and creating a new one.
  /// Returns the new purchase ID.
  /// Throws if the accounting period is closed or user lacks permission.
  Future<int> editPostedPurchase({
    required int originalPurchaseId,
    required int supplierId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required Decimal paidAmountCents,
    required List<PurchaseItemInput> items,
    String? paymentMethod,
    String? supplierInvoiceRef,
    String? notes,
    DateTime? purchaseDate,
    DateTime? dueDate,

    /// Phase 11.2 — tax-inclusive flag the engine used to produce the
    /// totals being persisted.
    bool taxInclusiveAtPost = false,
  });

  /// Delete purchase (only if draft)
  Future<int> deletePurchase(int purchaseId);

  /// Update purchase status
  Future<bool> updatePurchaseStatus(int purchaseId, String status);

  /// Watch dashboard stats
  Stream<PurchaseDashboardStats> watchDashboardStats();

  // ==================== PURCHASE RETURNS ====================

  /// Watch all purchase returns
  Stream<List<PurchaseReturnEntity>> watchAllPurchaseReturns();

  /// Watch returns for a specific purchase
  Stream<List<PurchaseReturnEntity>> watchPurchaseReturnsByPurchase(
    int purchaseId,
  );

  /// Get returns for a specific purchase
  Future<List<PurchaseReturnEntity>> getPurchaseReturns(int purchaseId);

  /// Get return by ID
  Future<PurchaseReturnEntity?> getPurchaseReturnById(int id);

  /// Watch return items
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItems(int returnId);

  /// Watch return items with full product details (name, color, size, SKU)
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItemsWithDetails(
    int returnId,
  );

  /// Generate next return number
  Future<String> generateReturnNumber();

  /// Create purchase return with items.
  ///
  /// This creates AND auto-posts the return inside a single transaction, so
  /// [allowNegativeStock] is forwarded to the internal post step.
  Future<int> createPurchaseReturn({
    required int purchaseId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required List<PurchaseReturnItemInput> items,
    String dispositionType = 'restock',
    String refundMethod = 'credit',
    String? reason,
    DateTime? returnDate,

    /// Phase 14.0 — cheque due date when `refundMethod` is `cheque`.
    /// Required by the form bloc when refund method is cheque; ignored
    /// (stored as NULL) otherwise. Surfaces on the dashboard reminder.
    DateTime? dueDate,
    bool allowNegativeStock = false,

    /// Optional client-generated idempotency token. The unique constraint on
    /// `purchase_returns.idempotency_key` rejects duplicate inserts so a
    /// double-tap or retried network call cannot create two returns / GL
    /// entries / stock movements.
    String? idempotencyKey,

    /// Phase 11.2 — tax-inclusive flag the engine used to produce the
    /// totals being persisted. Stamped on
    /// `purchase_returns.tax_inclusive_at_post`.
    bool taxInclusiveAtPost = false,

    /// Optional structured refund legs. Pending cheques are allocations, not
    /// settled cash; an unallocated remainder stays on the supplier account.
    List<CheckoutPaymentAllocation> settlementAllocations = const [],
  });

  /// Post purchase return (update variant stock).
  ///
  /// Posting a purchase return DECREASES stock (goods leaving the warehouse
  /// back to the supplier). If [allowNegativeStock] is false and current
  /// stock is insufficient, the operation is rejected.
  Future<void> postPurchaseReturn(
    int returnId, {
    bool allowNegativeStock = false,
  });

  /// Void purchase return (reverse stock if posted)
  Future<void> voidPurchaseReturn(int returnId);

  // ==================== PURCHASE PAYMENTS ====================

  /// Watch payments for a purchase
  Stream<List<PurchasePaymentEntity>> watchPurchasePayments(int purchaseId);

  /// Get payments for a purchase
  Future<List<PurchasePaymentEntity>> getPurchasePayments(int purchaseId);

  /// Record a payment
  Future<int> recordPayment({
    required int purchaseId,
    required int currencyId,
    required Decimal amountCents,
    required String paymentMethod,
    String? reference,
    String? notes,
    DateTime? paymentDate,
  });

  /// Delete a payment
  Future<void> deletePayment(int paymentId);

  /// Get total already returned quantity for a purchase item
  Future<int> getReturnedQuantity(int purchaseItemId);

  /// Get financial amounts from linked returns only (adjustments excluded).
  Future<LinkedReturnHistory> getLinkedReturnHistory(int purchaseItemId);

  /// Watch set of purchase IDs that have at least one non-voided return
  Stream<Set<int>> watchPurchaseIdsWithReturns();

  /// Watch product search terms (name, barcode, SKU) for all purchase items.
  Stream<Map<int, List<String>>> watchPurchaseProductSearchTerms();

  /// Watch product search terms for return items (unifiedId → terms)
  Stream<Map<String, List<String>>> watchPurchaseReturnProductSearchTerms();
}

/// Input for creating/updating a purchase item
class PurchaseItemInput {
  final int productId;
  final int? variantId;
  final int quantity;
  final int quantityScale;
  final String measurementType;
  final Decimal unitCostCents;
  final Decimal discountCents;
  final Decimal subtotalCents;
  final Decimal taxCents;
  final Decimal totalCents;
  final DateTime? expiryDate;
  final String? manufacturerLotNumber;
  final Decimal? originalCostCents;
  final Decimal? originalPriceCents;
  final Decimal? originalWholesalePriceCents;
  final Decimal? newSellPriceCents;
  final Decimal? newWholesalePriceCents;

  PurchaseItemInput({
    required this.productId,
    this.variantId,
    required this.quantity,
    this.quantityScale = 1,
    this.measurementType = 'piece',
    required this.unitCostCents,
    Decimal? discountCents,
    required this.subtotalCents,
    required this.taxCents,
    required this.totalCents,
    this.expiryDate,
    this.manufacturerLotNumber,
    this.originalCostCents,
    this.originalPriceCents,
    this.originalWholesalePriceCents,
    this.newSellPriceCents,
    this.newWholesalePriceCents,
  }) : discountCents = discountCents ?? Decimal.zero;
}

/// Input for creating a purchase return item
class PurchaseReturnItemInput {
  final int purchaseItemId;
  final int quantity;
  final int quantityScale;
  final String measurementType;
  final Decimal subtotalCents;
  final Decimal discountCents;
  final Decimal taxCents;
  final Decimal refundCents;
  final String? reason;

  const PurchaseReturnItemInput({
    required this.purchaseItemId,
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
  PurchaseReturnItemInput withCalculatedAmounts(
    ProportionalReturnResult result, {
    required int sourceQuantityScale,
    required String sourceMeasurementType,
  }) {
    return PurchaseReturnItemInput(
      purchaseItemId: purchaseItemId,
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

/// Dashboard stats for purchases
class PurchaseDashboardStats {
  final int totalCount;
  final int draftCount;
  final int postedCount;
  final int totalPayableCents;
  final int totalPaidCents;
  final int overdueCount;
  final int returnsCount;

  const PurchaseDashboardStats({
    required this.totalCount,
    required this.draftCount,
    required this.postedCount,
    required this.totalPayableCents,
    this.totalPaidCents = 0,
    this.overdueCount = 0,
    required this.returnsCount,
  });
}
