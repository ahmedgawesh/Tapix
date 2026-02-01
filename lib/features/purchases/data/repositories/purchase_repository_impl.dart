import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../datasources/purchase_local_datasource.dart';

class PurchaseRepositoryImpl implements PurchaseRepository {
  final PurchaseLocalDatasource _datasource;

  PurchaseRepositoryImpl(this._datasource);

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
    required Decimal taxCents,
    required Decimal totalCents,
    required List<PurchaseItemInput> items,
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
      status: const Value('pending'),
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
  Future<int> deletePurchase(int purchaseId) {
    return _datasource.deletePurchase(purchaseId);
  }

  @override
  Future<bool> updatePurchaseStatus(int purchaseId, String status) {
    return _datasource.updatePurchaseStatus(purchaseId, status);
  }
}
