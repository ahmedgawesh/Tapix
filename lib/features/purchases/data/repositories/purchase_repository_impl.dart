import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../datasources/purchase_local_datasource.dart';

class PurchaseRepositoryImpl implements PurchaseRepository {
  final PurchaseLocalDatasource _datasource;

  PurchaseRepositoryImpl(this._datasource);

  // ==================== PURCHASES ====================

  @override
  Stream<List<PurchaseEntity>> watchAllPurchases() {
    return _datasource.watchAllPurchases();
  }

  @override
  Stream<List<PurchaseEntity>> watchPurchasesByStatus(String status) {
    return _datasource.watchPurchasesByStatus(status);
  }

  @override
  Stream<List<PurchaseEntity>> watchPurchasesBySupplier(int supplierId) {
    return _datasource.watchPurchasesBySupplier(supplierId);
  }

  @override
  Stream<List<PurchaseEntity>> searchPurchases(String query) {
    return _datasource.searchPurchases(query);
  }

  @override
  Future<PurchaseEntity?> getPurchaseById(int id) {
    return _datasource.getPurchaseById(id);
  }

  @override
  Future<List<PurchaseItemEntity>> getPurchaseItems(int purchaseId) {
    return _datasource.getPurchaseItems(purchaseId);
  }

  @override
  Stream<List<PurchaseItemEntity>> watchPurchaseItems(int purchaseId) {
    return _datasource.watchPurchaseItems(purchaseId);
  }

  @override
  Future<String> generatePurchaseNumber() {
    return _datasource.generatePurchaseNumber();
  }

  @override
  Future<int> createPurchase({
    required int supplierId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required List<PurchaseItemInput> items,
    String? notes,
    DateTime? purchaseDate,
  }) async {
    final purchaseNumber = await generatePurchaseNumber();

    final purchase = db.PurchasesCompanion(
      purchaseNumber: Value(purchaseNumber),
      supplierId: Value(supplierId),
      currencyId: Value(currencyId),
      subtotalCents: Value(subtotalCents),
      taxCents: Value(taxCents),
      totalCents: Value(totalCents),
      status: const Value('draft'),
      purchaseDate: Value(purchaseDate ?? DateTime.now()),
    );

    final itemCompanions = items.map((item) => db.PurchaseItemsCompanion(
          productId: Value(item.productId),
          variantId: Value(item.variantId),
          quantity: Value(item.quantity),
          unitCostCents: Value(item.unitCostCents),
          subtotalCents: Value(item.subtotalCents),
          taxCents: Value(item.taxCents),
          totalCents: Value(item.totalCents),
        )).toList();

    return _datasource.createPurchase(purchase, itemCompanions);
  }

  @override
  Future<void> postPurchase(int purchaseId) {
    return _datasource.postPurchase(purchaseId);
  }

  @override
  Future<void> voidPurchase(int purchaseId) {
    return _datasource.voidPurchase(purchaseId);
  }

  @override
  Future<int> deletePurchase(int purchaseId) {
    return _datasource.deletePurchase(purchaseId);
  }

  @override
  Future<bool> updatePurchaseStatus(int purchaseId, String status) {
    return _datasource.updatePurchaseStatus(purchaseId, status);
  }

  @override
  Stream<PurchaseDashboardStats> watchDashboardStats() {
    return _datasource.watchDashboardStats();
  }

  // ==================== RETURNS ====================

  @override
  Stream<List<PurchaseReturnEntity>> watchAllPurchaseReturns() {
    return _datasource.watchAllPurchaseReturns();
  }

  @override
  Stream<List<PurchaseReturnEntity>> watchPurchaseReturnsByPurchase(int purchaseId) {
    return _datasource.watchPurchaseReturnsByPurchase(purchaseId);
  }

  @override
  Future<List<PurchaseReturnEntity>> getPurchaseReturns(int purchaseId) {
    return _datasource.getPurchaseReturns(purchaseId);
  }

  @override
  Future<PurchaseReturnEntity?> getPurchaseReturnById(int id) {
    return _datasource.getPurchaseReturnById(id);
  }

  @override
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItems(int returnId) {
    return _datasource.watchPurchaseReturnItems(returnId);
  }

  @override
  Future<String> generateReturnNumber() {
    return _datasource.generateReturnNumber();
  }

  @override
  Future<int> createPurchaseReturn({
    required int purchaseId,
    required int currencyId,
    required Decimal totalCents,
    required List<PurchaseReturnItemInput> items,
    String? reason,
    DateTime? returnDate,
  }) async {
    final returnNumber = await generateReturnNumber();

    final returnData = db.PurchaseReturnsCompanion(
      purchaseId: Value(purchaseId),
      returnNumber: Value(returnNumber),
      totalCents: Value(totalCents),
      currencyId: Value(currencyId),
      reason: Value(reason),
      returnDate: Value(returnDate ?? DateTime.now()),
    );

    final itemCompanions = items.map((item) => db.PurchaseReturnItemsCompanion(
          purchaseItemId: Value(item.purchaseItemId),
          quantity: Value(item.quantity),
          refundCents: Value(item.refundCents),
        )).toList();

    final returnId = await _datasource.createPurchaseReturn(returnData, itemCompanions);

    // Auto-post the return (update stock)
    await _datasource.postPurchaseReturn(returnId);

    return returnId;
  }

  @override
  Future<void> postPurchaseReturn(int returnId) {
    return _datasource.postPurchaseReturn(returnId);
  }
}
