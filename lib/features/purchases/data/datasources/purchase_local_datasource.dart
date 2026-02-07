import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/purchase_dao.dart' hide PurchaseDashboardStats;
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../models/purchase_model.dart';

abstract class PurchaseLocalDatasource {
  // Purchases
  Stream<List<PurchaseEntity>> watchAllPurchases();
  Stream<List<PurchaseEntity>> watchPurchasesByStatus(String status);
  Stream<List<PurchaseEntity>> watchPurchasesBySupplier(int supplierId);
  Stream<List<PurchaseEntity>> searchPurchases(String query);
  Future<PurchaseEntity?> getPurchaseById(int id);
  Future<List<PurchaseItemEntity>> getPurchaseItems(int purchaseId);
  Stream<List<PurchaseItemEntity>> watchPurchaseItems(int purchaseId);
  Future<String> generatePurchaseNumber();
  Future<int> createPurchase(db.PurchasesCompanion purchase, List<db.PurchaseItemsCompanion> items);
  Future<bool> updatePurchase(int purchaseId, db.PurchasesCompanion purchase, List<db.PurchaseItemsCompanion> items);
  Future<void> postPurchase(int purchaseId);
  Future<void> voidPurchase(int purchaseId);
  Future<int> deletePurchase(int purchaseId);
  Future<bool> updatePurchaseStatus(int purchaseId, String status);
  Stream<PurchaseDashboardStats> watchDashboardStats();

  // Returns
  Stream<List<PurchaseReturnEntity>> watchAllPurchaseReturns();
  Stream<List<PurchaseReturnEntity>> watchPurchaseReturnsByPurchase(int purchaseId);
  Future<List<PurchaseReturnEntity>> getPurchaseReturns(int purchaseId);
  Future<PurchaseReturnEntity?> getPurchaseReturnById(int id);
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItems(int returnId);
  Future<String> generateReturnNumber();
  Future<int> createPurchaseReturn(db.PurchaseReturnsCompanion returnData, List<db.PurchaseReturnItemsCompanion> items);
  Future<void> postPurchaseReturn(int returnId);
  Future<void> voidPurchaseReturn(int returnId);

  // Payments
  Stream<List<PurchasePaymentEntity>> watchPurchasePayments(int purchaseId);
  Future<List<PurchasePaymentEntity>> getPurchasePayments(int purchaseId);
  Future<int> recordPayment(db.PurchasePaymentsCompanion payment);
  Future<void> deletePayment(int paymentId);

  // Returned quantity tracking
  Future<int> getReturnedQuantity(int purchaseItemId);
}

class PurchaseLocalDatasourceImpl implements PurchaseLocalDatasource {
  final PurchaseDao _dao;

  PurchaseLocalDatasourceImpl(this._dao);

  // ==================== PURCHASES ====================

  @override
  Stream<List<PurchaseEntity>> watchAllPurchases() {
    return _dao.watchAllPurchasesWithSupplier().map(
      (rows) => rows.map(PurchaseModel.fromDriftWithSupplier).toList(),
    );
  }

  @override
  Stream<List<PurchaseEntity>> watchPurchasesByStatus(String status) {
    return _dao
        .watchPurchasesByStatus(status)
        .map((rows) => rows.map(PurchaseModel.fromDrift).toList());
  }

  @override
  Stream<List<PurchaseEntity>> watchPurchasesBySupplier(int supplierId) {
    return _dao
        .watchPurchasesBySupplier(supplierId)
        .map((rows) => rows.map(PurchaseModel.fromDrift).toList());
  }

  @override
  Stream<List<PurchaseEntity>> searchPurchases(String query) {
    return _dao
        .searchPurchases(query)
        .map((rows) => rows.map(PurchaseModel.fromDriftWithSupplier).toList());
  }

  @override
  Future<PurchaseEntity?> getPurchaseById(int id) async {
    final pws = await _dao.getPurchaseWithSupplierById(id);
    return pws == null ? null : PurchaseModel.fromDriftWithSupplier(pws);
  }

  @override
  Future<List<PurchaseItemEntity>> getPurchaseItems(int purchaseId) async {
    final items = await _dao.getPurchaseItemsWithDetails(purchaseId);
    return items.map(PurchaseItemModel.fromDriftWithDetails).toList();
  }

  @override
  Stream<List<PurchaseItemEntity>> watchPurchaseItems(int purchaseId) {
    return _dao
        .watchPurchaseItemsWithDetails(purchaseId)
        .map((items) => items.map(PurchaseItemModel.fromDriftWithDetails).toList());
  }

  @override
  Future<String> generatePurchaseNumber() {
    return _dao.generatePurchaseNumber();
  }

  @override
  Future<int> createPurchase(db.PurchasesCompanion purchase, List<db.PurchaseItemsCompanion> items) {
    return _dao.createPurchase(purchase, items);
  }

  @override
  Future<bool> updatePurchase(
    int purchaseId,
    db.PurchasesCompanion purchase,
    List<db.PurchaseItemsCompanion> items,
  ) {
    return _dao.updatePurchaseWithItems(purchaseId, purchase, items);
  }

  @override
  Future<void> postPurchase(int purchaseId) {
    return _dao.postPurchase(purchaseId);
  }

  @override
  Future<void> voidPurchase(int purchaseId) {
    return _dao.voidPurchase(purchaseId);
  }

  @override
  Future<int> deletePurchase(int purchaseId) {
    return _dao.deletePurchase(purchaseId);
  }

  @override
  Future<bool> updatePurchaseStatus(int purchaseId, String status) {
    return _dao.updatePurchaseStatus(purchaseId, status);
  }

  @override
  Stream<PurchaseDashboardStats> watchDashboardStats() {
    return _dao.watchDashboardStats().map((stats) => PurchaseDashboardStats(
          totalCount: stats.totalCount,
          draftCount: stats.draftCount,
          postedCount: stats.postedCount,
          totalPayableCents: stats.totalPayableCents,
          totalPaidCents: stats.totalPaidCents,
          overdueCount: stats.overdueCount,
          returnsCount: stats.returnsCount,
        ));
  }

  // ==================== RETURNS ====================

  @override
  Stream<List<PurchaseReturnEntity>> watchAllPurchaseReturns() {
    return _dao
        .watchAllPurchaseReturns()
        .map((rows) => rows.map(PurchaseReturnModel.fromDrift).toList());
  }

  @override
  Stream<List<PurchaseReturnEntity>> watchPurchaseReturnsByPurchase(int purchaseId) {
    // Filter from all returns by purchaseId
    return _dao.watchAllPurchaseReturns().map(
      (rows) => rows
          .where((r) => r.purchaseId == purchaseId)
          .map(PurchaseReturnModel.fromDrift)
          .toList(),
    );
  }

  @override
  Future<List<PurchaseReturnEntity>> getPurchaseReturns(int purchaseId) async {
    final all = await _dao.watchAllPurchaseReturns().first;
    return all
        .where((r) => r.purchaseId == purchaseId)
        .map(PurchaseReturnModel.fromDrift)
        .toList();
  }

  @override
  Future<PurchaseReturnEntity?> getPurchaseReturnById(int id) async {
    final r = await _dao.getPurchaseReturnById(id);
    return r == null ? null : PurchaseReturnModel.fromDrift(r);
  }

  @override
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItems(int returnId) {
    return _dao
        .watchPurchaseReturnItems(returnId)
        .map((items) => items.map(PurchaseReturnItemModel.fromDrift).toList());
  }

  @override
  Future<String> generateReturnNumber() {
    return _dao.generateReturnNumber();
  }

  @override
  Future<int> createPurchaseReturn(
    db.PurchaseReturnsCompanion returnData,
    List<db.PurchaseReturnItemsCompanion> items,
  ) {
    return _dao.createPurchaseReturn(returnData, items);
  }

  @override
  Future<void> postPurchaseReturn(int returnId) {
    return _dao.postPurchaseReturn(returnId);
  }

  @override
  Future<void> voidPurchaseReturn(int returnId) {
    return _dao.voidPurchaseReturn(returnId);
  }

  // ==================== PAYMENTS ====================

  @override
  Stream<List<PurchasePaymentEntity>> watchPurchasePayments(int purchaseId) {
    return _dao
        .watchPurchasePayments(purchaseId)
        .map((rows) => rows.map(PurchasePaymentModel.fromDrift).toList());
  }

  @override
  Future<List<PurchasePaymentEntity>> getPurchasePayments(int purchaseId) async {
    final payments = await _dao.getPurchasePayments(purchaseId);
    return payments.map(PurchasePaymentModel.fromDrift).toList();
  }

  @override
  Future<int> recordPayment(db.PurchasePaymentsCompanion payment) {
    return _dao.recordPayment(payment);
  }

  @override
  Future<void> deletePayment(int paymentId) {
    return _dao.deletePayment(paymentId);
  }

  @override
  Future<int> getReturnedQuantity(int purchaseItemId) {
    return _dao.getReturnedQuantity(purchaseItemId);
  }
}
