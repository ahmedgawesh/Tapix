import '../../../../core/services/business/warehouse_operation_scope.dart';
import 'dart:async';

import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/purchase_dao.dart'
    hide PurchaseDashboardStats;
import '../../../../core/database/daos/adjustment_return_dao.dart';
import '../../../../core/services/journal_entry_service.dart';
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
  Future<int> createPurchase(
    db.PurchasesCompanion purchase,
    List<db.PurchaseItemsCompanion> items, {
    WarehouseOperationScope? scope,
  });
  Future<bool> updatePurchase(
    int purchaseId,
    db.PurchasesCompanion purchase,
    List<db.PurchaseItemsCompanion> items,
  );
  Future<void> postPurchase(int purchaseId, {WarehouseOperationScope? scope});
  Future<void> voidPurchase(
    int purchaseId, {
    WarehouseOperationScope? scope,
    JournalEntryService? journalEntryService,
    int? userId,
  });
  Future<int> deletePurchase(int purchaseId);
  Future<bool> updatePurchaseStatus(int purchaseId, String status);
  Stream<PurchaseDashboardStats> watchDashboardStats();

  // Returns
  Stream<List<PurchaseReturnEntity>> watchAllPurchaseReturns();
  Stream<List<PurchaseReturnEntity>> watchPurchaseReturnsByPurchase(
    int purchaseId,
  );
  Future<List<PurchaseReturnEntity>> getPurchaseReturns(int purchaseId);
  Future<PurchaseReturnEntity?> getPurchaseReturnById(int id);
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItems(int returnId);
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItemsWithDetails(
    int returnId,
  );
  Future<String> generateReturnNumber();
  Future<int> createPurchaseReturn(
    db.PurchaseReturnsCompanion returnData,
    List<db.PurchaseReturnItemsCompanion> items,
  );
  Future<void> updatePurchaseReturnTotals(int returnId);
  Future<void> postPurchaseReturn(
    int returnId, {
    bool allowNegativeStock = false,
    WarehouseOperationScope? scope,
  });
  Future<void> voidPurchaseReturn(
    int returnId, {
    WarehouseOperationScope? scope,
  });

  // Payments
  Stream<List<PurchasePaymentEntity>> watchPurchasePayments(int purchaseId);
  Future<List<PurchasePaymentEntity>> getPurchasePayments(int purchaseId);
  Future<int> recordPayment(db.PurchasePaymentsCompanion payment);
  Future<void> deletePayment(int paymentId);

  // Returned quantity tracking
  Future<int> getReturnedQuantity(int purchaseItemId);

  // Watch purchase IDs that have returns
  Stream<Set<int>> watchPurchaseIdsWithReturns();

  // Watch product search terms for purchase items
  Stream<Map<int, List<String>>> watchPurchaseProductSearchTerms();

  // Watch product search terms for purchase return items
  Stream<Map<String, List<String>>> watchPurchaseReturnProductSearchTerms();
}

class PurchaseLocalDatasourceImpl implements PurchaseLocalDatasource {
  final PurchaseDao _dao;
  final AdjustmentReturnDao _adjDao;

  PurchaseLocalDatasourceImpl(this._dao, this._adjDao);

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
        .map(
          (items) => items.map(PurchaseItemModel.fromDriftWithDetails).toList(),
        );
  }

  @override
  Future<String> generatePurchaseNumber() {
    return _dao.generatePurchaseNumber();
  }

  @override
  Future<int> createPurchase(
    db.PurchasesCompanion purchase,
    List<db.PurchaseItemsCompanion> items, {
    WarehouseOperationScope? scope,
  }) {
    return _dao.createPurchase(purchase, items, scope: scope);
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
  Future<void> postPurchase(int purchaseId, {WarehouseOperationScope? scope}) {
    return _dao.postPurchase(purchaseId, scope: scope);
  }

  @override
  Future<void> voidPurchase(
    int purchaseId, {
    WarehouseOperationScope? scope,
    JournalEntryService? journalEntryService,
    int? userId,
  }) {
    // 2026-05-13 — pass journal service + userId so the DAO can cascade-
    // void the JEs of any linked purchase_returns inside the same tx.
    // Without this, the linked-return JE stays `posted` while the row is
    // flipped to `voided`, producing the AP / Inventory drift seen in
    // `tapix_backup_20260513_121448.db`.
    return _dao.voidPurchase(
      purchaseId,
      scope: scope,
      journalEntryService: journalEntryService,
      userId: userId,
    );
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
    return _dao.watchDashboardStats().map(
      (stats) => PurchaseDashboardStats(
        totalCount: stats.totalCount,
        draftCount: stats.draftCount,
        postedCount: stats.postedCount,
        totalPayableCents: stats.totalPayableCents,
        totalPaidCents: stats.totalPaidCents,
        overdueCount: stats.overdueCount,
        returnsCount: stats.returnsCount,
      ),
    );
  }

  // ==================== RETURNS ====================

  @override
  Stream<List<PurchaseReturnEntity>> watchAllPurchaseReturns() {
    List<PurchaseReturnEntity> lastLinked = [];
    List<PurchaseReturnEntity> lastAdj = [];
    var linkedLoaded = false;
    var adjustmentLoaded = false;

    List<PurchaseReturnEntity> merge() {
      final merged = <PurchaseReturnEntity>[...lastLinked, ...lastAdj];
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return merged;
    }

    final controller = StreamController<List<PurchaseReturnEntity>>.broadcast();
    final sub1 = _dao.watchAllPurchaseReturnsWithParty().listen((rows) {
      linkedLoaded = true;
      lastLinked = rows
          .map(
            (r) =>
                PurchaseReturnModel.fromDriftWithParty(r)
                    as PurchaseReturnEntity,
          )
          .toList();
      if (adjustmentLoaded) controller.add(merge());
    });
    final sub2 = _adjDao.watchAllPurchaseAdjReturnsWithParty().listen((rows) {
      adjustmentLoaded = true;
      lastAdj = rows
          .map(
            (a) =>
                PurchaseReturnModel.fromAdjustmentWithParty(a)
                    as PurchaseReturnEntity,
          )
          .toList();
      if (linkedLoaded) controller.add(merge());
    });
    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
      controller.close();
    };
    return controller.stream;
  }

  @override
  Stream<Map<String, List<String>>> watchPurchaseReturnProductSearchTerms() {
    Map<String, List<String>> lastLinked = {};
    Map<String, List<String>> lastAdj = {};

    final controller = StreamController<Map<String, List<String>>>.broadcast();
    final sub1 = _dao.watchPurchaseReturnProductSearchTerms().listen((data) {
      lastLinked = data;
      controller.add({...lastLinked, ...lastAdj});
    });
    final sub2 = _adjDao.watchPurchaseAdjReturnProductSearchTerms().listen((
      data,
    ) {
      lastAdj = data;
      controller.add({...lastLinked, ...lastAdj});
    });
    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
      controller.close();
    };
    return controller.stream;
  }

  @override
  Stream<List<PurchaseReturnEntity>> watchPurchaseReturnsByPurchase(
    int purchaseId,
  ) {
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
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItems(
    int returnId,
  ) {
    return _dao
        .watchPurchaseReturnItems(returnId)
        .map((items) => items.map(PurchaseReturnItemModel.fromDrift).toList());
  }

  @override
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItemsWithDetails(
    int returnId,
  ) {
    return _dao
        .watchPurchaseReturnItemsWithDetails(returnId)
        .map(
          (items) =>
              items.map(PurchaseReturnItemModel.fromDriftWithDetails).toList(),
        );
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
  Future<void> updatePurchaseReturnTotals(int returnId) {
    return _dao.updatePurchaseReturnTotals(returnId);
  }

  @override
  Future<void> postPurchaseReturn(
    int returnId, {
    bool allowNegativeStock = false,
    WarehouseOperationScope? scope,
  }) {
    return _dao.postPurchaseReturn(
      returnId,
      allowNegativeStock: allowNegativeStock,
      scope: scope,
    );
  }

  @override
  Future<void> voidPurchaseReturn(
    int returnId, {
    WarehouseOperationScope? scope,
  }) {
    return _dao.voidPurchaseReturn(returnId, scope: scope);
  }

  // ==================== PAYMENTS ====================

  @override
  Stream<List<PurchasePaymentEntity>> watchPurchasePayments(int purchaseId) {
    return _dao
        .watchPurchasePayments(purchaseId)
        .map((rows) => rows.map(PurchasePaymentModel.fromDrift).toList());
  }

  @override
  Future<List<PurchasePaymentEntity>> getPurchasePayments(
    int purchaseId,
  ) async {
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

  @override
  Stream<Set<int>> watchPurchaseIdsWithReturns() =>
      _dao.watchPurchaseIdsWithReturns();

  @override
  Stream<Map<int, List<String>>> watchPurchaseProductSearchTerms() =>
      _dao.watchPurchaseProductSearchTerms();
}
