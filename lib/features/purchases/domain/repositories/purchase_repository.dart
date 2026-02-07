import 'package:decimal/decimal.dart';
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
    required List<PurchaseItemInput> items,
    String? paymentMethod,
    String? supplierInvoiceRef,
    String? notes,
    DateTime? purchaseDate,
    DateTime? dueDate,
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
    required List<PurchaseItemInput> items,
    String? paymentMethod,
    String? supplierInvoiceRef,
    String? notes,
    DateTime? purchaseDate,
    DateTime? dueDate,
  });

  /// Post purchase (update variant stocks and costs)
  Future<void> postPurchase(int purchaseId);

  /// Void purchase (reverse stock if posted)
  Future<void> voidPurchase(int purchaseId);

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
  Stream<List<PurchaseReturnEntity>> watchPurchaseReturnsByPurchase(int purchaseId);

  /// Get returns for a specific purchase
  Future<List<PurchaseReturnEntity>> getPurchaseReturns(int purchaseId);

  /// Get return by ID
  Future<PurchaseReturnEntity?> getPurchaseReturnById(int id);

  /// Watch return items
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItems(int returnId);

  /// Generate next return number
  Future<String> generateReturnNumber();

  /// Create purchase return with items
  Future<int> createPurchaseReturn({
    required int purchaseId,
    required int currencyId,
    required Decimal totalCents,
    required List<PurchaseReturnItemInput> items,
    String dispositionType = 'restock',
    String? reason,
    DateTime? returnDate,
  });

  /// Post purchase return (update variant stock)
  Future<void> postPurchaseReturn(int returnId);

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
}

/// Input for creating/updating a purchase item
class PurchaseItemInput {
  final int productId;
  final int? variantId;
  final int quantity;
  final Decimal unitCostCents;
  final Decimal discountCents;
  final Decimal subtotalCents;
  final Decimal taxCents;
  final Decimal totalCents;
  final DateTime? expiryDate;

  PurchaseItemInput({
    required this.productId,
    this.variantId,
    required this.quantity,
    required this.unitCostCents,
    Decimal? discountCents,
    required this.subtotalCents,
    required this.taxCents,
    required this.totalCents,
    this.expiryDate,
  }) : discountCents = discountCents ?? Decimal.zero;
}

/// Input for creating a purchase return item
class PurchaseReturnItemInput {
  final int purchaseItemId;
  final int quantity;
  final Decimal refundCents;
  final String? reason;

  const PurchaseReturnItemInput({
    required this.purchaseItemId,
    required this.quantity,
    required this.refundCents,
    this.reason,
  });
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
