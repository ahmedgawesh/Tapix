import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/purchase_dao.dart';
import '../../domain/entities/purchase_entity.dart';
import '../models/purchase_model.dart';

abstract class PurchaseLocalDatasource {
  Stream<List<PurchaseEntity>> watchAllPurchases();
  Stream<List<PurchaseEntity>> watchPurchasesByStatus(String status);
  Stream<List<PurchaseEntity>> watchPurchasesBySupplier(int supplierId);
  Future<PurchaseEntity?> getPurchaseById(int id);
  Future<List<PurchaseItemEntity>> getPurchaseItems(int purchaseId);
  Stream<List<PurchaseItemEntity>> watchPurchaseItems(int purchaseId);
  Future<String> generatePurchaseNumber();
  Future<int> createPurchase(db.PurchasesCompanion purchase, List<db.PurchaseItemsCompanion> items);
  Future<void> postPurchase(int purchaseId);
  Future<int> deletePurchase(int purchaseId);
  Future<bool> updatePurchaseStatus(int purchaseId, String status);
}

class PurchaseLocalDatasourceImpl implements PurchaseLocalDatasource {
  final PurchaseDao _dao;

  PurchaseLocalDatasourceImpl(this._dao);

  @override
  Stream<List<PurchaseEntity>> watchAllPurchases() {
    return _dao.watchAllPurchases().map((rows) => rows.map(PurchaseModel.fromDrift).toList());
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
  Future<PurchaseEntity?> getPurchaseById(int id) async {
    final p = await _dao.getPurchaseById(id);
    return p == null ? null : PurchaseModel.fromDrift(p);
  }

  @override
  Future<List<PurchaseItemEntity>> getPurchaseItems(int purchaseId) async {
    final items = await _dao.getPurchaseItems(purchaseId);
    return items.map(PurchaseItemModel.fromDrift).toList();
  }

  @override
  Stream<List<PurchaseItemEntity>> watchPurchaseItems(int purchaseId) {
    return _dao
        .watchPurchaseItems(purchaseId)
        .map((items) => items.map(PurchaseItemModel.fromDrift).toList());
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
  Future<void> postPurchase(int purchaseId) {
    return _dao.postPurchase(purchaseId);
  }

  @override
  Future<int> deletePurchase(int purchaseId) {
    return _dao.deletePurchase(purchaseId);
  }

  @override
  Future<bool> updatePurchaseStatus(int purchaseId, String status) {
    return _dao.updatePurchaseStatus(purchaseId, status);
  }
}

