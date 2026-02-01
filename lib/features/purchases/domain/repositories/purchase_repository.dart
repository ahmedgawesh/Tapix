import 'package:decimal/decimal.dart';
import '../entities/purchase_entity.dart';

abstract class PurchaseRepository {
  /// Watch all purchases with supplier info
  Stream<List<PurchaseEntity>> watchAllPurchases();

  /// Watch purchases by status
  Stream<List<PurchaseEntity>> watchPurchasesByStatus(String status);

  /// Watch purchases by supplier
  Stream<List<PurchaseEntity>> watchPurchasesBySupplier(int supplierId);

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
    required Decimal taxCents,
    required Decimal totalCents,
    required List<PurchaseItemInput> items,
    DateTime? purchaseDate,
  });

  /// Post purchase (update variant stocks and costs)
  Future<void> postPurchase(int purchaseId);

  /// Delete purchase (only if draft)
  Future<int> deletePurchase(int purchaseId);

  /// Update purchase status
  Future<bool> updatePurchaseStatus(int purchaseId, String status);
}

/// Input for creating/updating a purchase item
class PurchaseItemInput {
  final int productId;
  final int? variantId;
  final int quantity;
  final Decimal unitCostCents;
  final Decimal subtotalCents;
  final Decimal taxCents;
  final Decimal totalCents;

  const PurchaseItemInput({
    required this.productId,
    this.variantId,
    required this.quantity,
    required this.unitCostCents,
    required this.subtotalCents,
    required this.taxCents,
    required this.totalCents,
  });
}
