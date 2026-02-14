import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../auth/data/services/session_service.dart';
import '../../domain/entities/purchase_entity.dart';
import '../../domain/repositories/purchase_repository.dart';
import '../datasources/purchase_local_datasource.dart';

class PurchaseRepositoryImpl implements PurchaseRepository {
  final PurchaseLocalDatasource _datasource;
  final AuditLogService _auditService;
  final SessionService _sessionService;
  final JournalEntryService _journalService;
  final db.AppDatabase _db;

  PurchaseRepositoryImpl(this._datasource, this._auditService, this._sessionService, this._journalService, this._db);

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
    required Decimal paidAmountCents,
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
      paidAmountCents: Value(paidAmountCents),
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
          discountCents: Value(item.discountCents),
          subtotalCents: Value(item.subtotalCents),
          taxCents: Value(item.taxCents),
          totalCents: Value(item.totalCents),
          originalCostCents: Value(item.originalCostCents),
          originalPriceCents: Value(item.originalPriceCents),
          originalWholesalePriceCents: Value(item.originalWholesalePriceCents),
          newSellPriceCents: Value(item.newSellPriceCents),
          newWholesalePriceCents: Value(item.newWholesalePriceCents),
          expiryDate: Value(item.expiryDate),
        )).toList();

    // ATOMIC: Wrap purchase creation and journal entries in a single transaction.
    // If any step fails, everything rolls back — preventing GL ↔ sub-ledger drift.
    final userId = await _currentUserId();

    final purchaseId = await _db.transaction(() async {
      final id = await _datasource.createPurchase(purchase, itemCompanions);

      // Create journal entries — MANDATORY, errors propagate
      await _journalService.recordPurchaseJournalEntry(
        purchaseId: id,
        totalCents: totalCents.toBigInt().toInt(),
        paidAmountCents: paidAmountCents.toBigInt().toInt(),
        currencyId: currencyId,
        paymentMethod: paymentMethod,
        userId: userId,
      );

      return id;
    });

    // Audit log outside transaction (non-critical, fire-and-forget)
    _auditService.log(
      entityType: 'purchase',
      entityId: purchaseId,
      action: 'create',
      newValue: {
        'purchaseNumber': purchaseNumber,
        'supplierId': supplierId,
        'totalCents': totalCents.toString(),
        'itemCount': items.length,
      },
      userId: userId,
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
    required Decimal paidAmountCents,
    required List<PurchaseItemInput> items,
    String? paymentMethod,
    String? supplierInvoiceRef,
    String? notes,
    DateTime? purchaseDate,
    DateTime? dueDate,
  }) async {
    // Guard: only draft/pending purchases can be edited.
    // Posted/voided purchases have journal entries that would become stale.
    final existing = await getPurchaseById(purchaseId);
    if (existing != null && !existing.isDraft) {
      throw Exception(
        'Cannot edit a ${existing.status} purchase. Void it and create a new one instead.',
      );
    }

    final purchase = db.PurchasesCompanion(
      supplierId: Value(supplierId),
      currencyId: Value(currencyId),
      subtotalCents: Value(subtotalCents),
      discountCents: Value(discountCents),
      taxCents: Value(taxCents),
      totalCents: Value(totalCents),
      paidAmountCents: Value(paidAmountCents),
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
          discountCents: Value(item.discountCents),
          subtotalCents: Value(item.subtotalCents),
          taxCents: Value(item.taxCents),
          totalCents: Value(item.totalCents),
          originalCostCents: Value(item.originalCostCents),
          originalPriceCents: Value(item.originalPriceCents),
          originalWholesalePriceCents: Value(item.originalWholesalePriceCents),
          newSellPriceCents: Value(item.newSellPriceCents),
          newWholesalePriceCents: Value(item.newWholesalePriceCents),
          expiryDate: Value(item.expiryDate),
        )).toList();

    // Void old journal entries BEFORE updating the purchase record
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'purchases',
      sourceId: purchaseId,
      reason: 'Purchase updated',
      userId: await _currentUserId(),
    );

    final ok = await _datasource.updatePurchase(purchaseId, purchase, itemCompanions);

    if (ok) {
      // Re-create journal entries with new amounts
      await _journalService.recordPurchaseJournalEntry(
        purchaseId: purchaseId,
        totalCents: totalCents.toBigInt().toInt(),
        paidAmountCents: paidAmountCents.toBigInt().toInt(),
        currencyId: currencyId,
        paymentMethod: paymentMethod,
        userId: await _currentUserId(),
      );

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
    // Void journal entries BEFORE voiding the purchase
    try {
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'purchases',
        sourceId: purchaseId,
        reason: 'Purchase voided',
        userId: await _currentUserId(),
      );
    } catch (e) {
      developer.log('Warning: Failed to void journal entries for purchase #$purchaseId: $e',
          name: 'PurchaseRepository');
    }

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
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItemsWithDetails(int returnId) {
    return _datasource.watchPurchaseReturnItemsWithDetails(returnId);
  }

  @override
  Future<String> generateReturnNumber() {
    return _datasource.generateReturnNumber();
  }

  @override
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
  }) async {
    final returnNumber = await generateReturnNumber();

    final returnData = db.PurchaseReturnsCompanion(
      purchaseId: Value(purchaseId),
      returnNumber: Value(returnNumber),
      subtotalCents: Value(subtotalCents),
      discountCents: Value(discountCents),
      taxCents: Value(taxCents),
      totalCents: Value(totalCents),
      currencyId: Value(currencyId),
      status: const Value('draft'),
      dispositionType: Value(dispositionType),
      refundMethod: Value(refundMethod),
      reason: Value(reason),
      returnDate: Value(returnDate ?? DateTime.now()),
    );

    final itemCompanions = items.map((item) => db.PurchaseReturnItemsCompanion(
          purchaseItemId: Value(item.purchaseItemId),
          quantity: Value(item.quantity),
          subtotalCents: Value(item.subtotalCents),
          discountCents: Value(item.discountCents),
          taxCents: Value(item.taxCents),
          refundCents: Value(item.refundCents),
          reason: Value(item.reason),
        )).toList();

    // ATOMIC: Wrap return creation, stock deduction, and journal entries
    // in a single transaction.
    final userId = await _currentUserId();

    final returnId = await _db.transaction(() async {
      final id = await _datasource.createPurchaseReturn(returnData, itemCompanions);

      // Auto-post the return (update stock)
      await _datasource.postPurchaseReturn(id);

      // Create journal entries — MANDATORY
      await _journalService.recordPurchaseReturnJournalEntry(
        returnId: id,
        totalCents: totalCents.toBigInt().toInt(),
        currencyId: currencyId,
        refundMethod: refundMethod,
        userId: userId,
      );

      return id;
    });

    // Audit log outside transaction (non-critical)
    _auditService.log(
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
      userId: userId,
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
    // Void journal entries BEFORE voiding the return
    try {
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'purchase_returns',
        sourceId: returnId,
        reason: 'Purchase return voided',
        userId: await _currentUserId(),
      );
    } catch (e) {
      developer.log('Warning: Failed to void journal entries for purchase return #$returnId: $e',
          name: 'PurchaseRepository');
    }

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
    // ATOMIC: Wrap payment recording (which updates supplier balance)
    // and journal entry creation in a single transaction.
    final userId = await _currentUserId();

    final paymentId = await _db.transaction(() async {
      final id = await _datasource.recordPayment(payment);

      // Post journal entry: Dr Accounts Payable, Cr Cash/Bank
      await _journalService.recordSupplierPaymentJournalEntry(
        paymentId: id,
        amountCents: amountCents.toBigInt().toInt(),
        currencyId: currencyId,
        paymentMethod: paymentMethod,
        userId: userId,
      );

      return id;
    });

    // Audit log outside transaction (non-critical)
    _auditService.log(
      entityType: 'purchase_payment',
      entityId: paymentId,
      action: 'create',
      newValue: {
        'purchaseId': purchaseId,
        'amountCents': amountCents.toString(),
        'paymentMethod': paymentMethod,
      },
      userId: userId,
    );

    return paymentId;
  }

  @override
  Future<void> deletePayment(int paymentId) async {
    // Void journal entries BEFORE deleting the payment
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'purchase_payments',
      sourceId: paymentId,
      reason: 'Purchase payment deleted',
      userId: await _currentUserId(),
    );

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

  @override
  Stream<Set<int>> watchPurchaseIdsWithReturns() =>
      _datasource.watchPurchaseIdsWithReturns();
}
