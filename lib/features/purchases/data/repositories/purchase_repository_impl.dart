import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../../../core/services/audit_log_service.dart';
import '../../../auth/data/services/session_service.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../datasources/purchase_local_datasource.dart';

class PurchaseRepositoryImpl implements PurchaseRepository {
  final PurchaseLocalDatasource _datasource;
  final AuditLogService _auditService;
  final SessionService _sessionService;

  PurchaseRepositoryImpl(this._datasource, this._auditService, this._sessionService);

  /// Get the current user ID from the session for audit logging.
  Future<int?> _currentUserId() => _sessionService.getCurrentUserId();

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
    String? paymentMethod,
    String? supplierInvoiceRef,
    String? notes,
    DateTime? purchaseDate,
    DateTime? dueDate,
  }) async {
    final purchaseNumber = await generatePurchaseNumber();

    final purchase = db.PurchasesCompanion(
      purchaseNumber: Value(purchaseNumber),
      supplierId: Value(supplierId),
      currencyId: Value(currencyId),
      subtotalCents: Value(subtotalCents),
      discountCents: Value(discountCents),
      taxCents: Value(taxCents),
      totalCents: Value(totalCents),
      status: const Value('draft'),
      paymentMethod: Value(paymentMethod),
      supplierInvoiceRef: Value(supplierInvoiceRef),
      notes: Value(notes),
      purchaseDate: Value(purchaseDate ?? DateTime.now()),
      dueDate: Value(dueDate),
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

    final purchaseId = await _datasource.createPurchase(purchase, itemCompanions);

    // Audit: log purchase creation
    await _auditService.log(
      entityType: 'purchase',
      entityId: purchaseId,
      action: 'create',
      newValue: {
        'purchaseNumber': purchaseNumber,
        'supplierId': supplierId,
        'totalCents': totalCents.toString(),
        'itemCount': items.length,
      },
      userId: await _currentUserId(),
    );

    return purchaseId;
  }

  @override
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
  }) async {
    final purchase = db.PurchasesCompanion(
      supplierId: Value(supplierId),
      currencyId: Value(currencyId),
      subtotalCents: Value(subtotalCents),
      discountCents: Value(discountCents),
      taxCents: Value(taxCents),
      totalCents: Value(totalCents),
      paymentMethod: Value(paymentMethod),
      supplierInvoiceRef: Value(supplierInvoiceRef),
      notes: Value(notes),
      purchaseDate: Value(purchaseDate ?? DateTime.now()),
      dueDate: Value(dueDate),
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

    final ok = await _datasource.updatePurchase(purchaseId, purchase, itemCompanions);

    if (ok) {
      // Audit: log purchase update
      await _auditService.log(
        entityType: 'purchase',
        entityId: purchaseId,
        action: 'update',
        newValue: {
          'supplierId': supplierId,
          'totalCents': totalCents.toString(),
          'itemCount': items.length,
        },
        userId: await _currentUserId(),
      );
    }

    return ok;
  }

  @override
  Future<void> postPurchase(int purchaseId) async {
    await _datasource.postPurchase(purchaseId);

    // Audit: log purchase posting (stock was updated)
    await _auditService.log(
      entityType: 'purchase',
      entityId: purchaseId,
      action: 'post',
      newValue: {'status': 'posted'},
      userId: await _currentUserId(),
    );
  }

  @override
  Future<void> voidPurchase(int purchaseId) async {
    await _datasource.voidPurchase(purchaseId);

    // Audit: log purchase voiding (stock was reversed)
    await _auditService.logVoid(
      entityType: 'purchase',
      entityId: purchaseId,
      reason: 'User voided purchase',
      userId: await _currentUserId(),
    );
  }

  @override
  Future<int> deletePurchase(int purchaseId) async {
    // Audit: log before deletion (data will be gone after)
    await _auditService.log(
      entityType: 'purchase',
      entityId: purchaseId,
      action: 'delete',
      oldValue: {'purchaseId': purchaseId},
      userId: await _currentUserId(),
    );

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
    String dispositionType = 'restock',
    String? reason,
    DateTime? returnDate,
  }) async {
    final returnNumber = await generateReturnNumber();

    final returnData = db.PurchaseReturnsCompanion(
      purchaseId: Value(purchaseId),
      returnNumber: Value(returnNumber),
      totalCents: Value(totalCents),
      currencyId: Value(currencyId),
      status: const Value('draft'),
      dispositionType: Value(dispositionType),
      reason: Value(reason),
      returnDate: Value(returnDate ?? DateTime.now()),
    );

    final itemCompanions = items.map((item) => db.PurchaseReturnItemsCompanion(
          purchaseItemId: Value(item.purchaseItemId),
          quantity: Value(item.quantity),
          refundCents: Value(item.refundCents),
          reason: Value(item.reason),
        )).toList();

    final returnId = await _datasource.createPurchaseReturn(returnData, itemCompanions);

    // Auto-post the return (update stock)
    await _datasource.postPurchaseReturn(returnId);

    // Audit: log return creation + posting
    await _auditService.log(
      entityType: 'purchase_return',
      entityId: returnId,
      action: 'create_and_post',
      newValue: {
        'purchaseId': purchaseId,
        'returnNumber': returnNumber,
        'totalCents': totalCents.toString(),
        'dispositionType': dispositionType,
        'itemCount': items.length,
      },
      userId: await _currentUserId(),
    );

    return returnId;
  }

  @override
  Future<void> postPurchaseReturn(int returnId) async {
    await _datasource.postPurchaseReturn(returnId);

    await _auditService.log(
      entityType: 'purchase_return',
      entityId: returnId,
      action: 'post',
      newValue: {'status': 'posted'},
      userId: await _currentUserId(),
    );
  }

  @override
  Future<void> voidPurchaseReturn(int returnId) async {
    await _datasource.voidPurchaseReturn(returnId);

    await _auditService.logVoid(
      entityType: 'purchase_return',
      entityId: returnId,
      reason: 'User voided purchase return',
      userId: await _currentUserId(),
    );
  }

  // ==================== PAYMENTS ====================

  @override
  Stream<List<PurchasePaymentEntity>> watchPurchasePayments(int purchaseId) {
    return _datasource.watchPurchasePayments(purchaseId);
  }

  @override
  Future<List<PurchasePaymentEntity>> getPurchasePayments(int purchaseId) {
    return _datasource.getPurchasePayments(purchaseId);
  }

  @override
  Future<int> recordPayment({
    required int purchaseId,
    required int currencyId,
    required Decimal amountCents,
    required String paymentMethod,
    String? reference,
    String? notes,
    DateTime? paymentDate,
  }) async {
    final payment = db.PurchasePaymentsCompanion(
      purchaseId: Value(purchaseId),
      amountCents: Value(amountCents),
      currencyId: Value(currencyId),
      paymentMethod: Value(paymentMethod),
      reference: Value(reference),
      notes: Value(notes),
      paymentDate: Value(paymentDate ?? DateTime.now()),
    );
    final paymentId = await _datasource.recordPayment(payment);

    // Audit: log payment recording
    await _auditService.log(
      entityType: 'purchase_payment',
      entityId: paymentId,
      action: 'create',
      newValue: {
        'purchaseId': purchaseId,
        'amountCents': amountCents.toString(),
        'paymentMethod': paymentMethod,
      },
      userId: await _currentUserId(),
    );

    return paymentId;
  }

  @override
  Future<void> deletePayment(int paymentId) async {
    // Audit: log before deletion
    await _auditService.log(
      entityType: 'purchase_payment',
      entityId: paymentId,
      action: 'delete',
      oldValue: {'paymentId': paymentId},
      userId: await _currentUserId(),
    );

    return _datasource.deletePayment(paymentId);
  }

  @override
  Future<int> getReturnedQuantity(int purchaseItemId) {
    return _datasource.getReturnedQuantity(purchaseItemId);
  }
}
