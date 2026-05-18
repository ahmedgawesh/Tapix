import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../../../core/pricing/pricing_snapshot.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/services/void_impact_analyzer.dart';
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
    bool taxInclusiveAtPost = false,
  }) async {
    // Purchase number is generated INSIDE the transaction (see below)
    // to prevent race conditions when two purchases are created concurrently.

    final purchase = db.PurchasesCompanion(
      purchaseNumber: const Value.absent(), // placeholder, set inside tx
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
    ).withPricingSnapshot(taxInclusive: taxInclusiveAtPost);

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

    // Create purchase as draft — journal entries are deferred until postPurchase()
    // to keep GL and supplier sub-ledger in sync.
    final userId = await _currentUserId();

    const maxRetries = 3;
    late int purchaseId;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        purchaseId = await _db.transaction(() async {
          // Generate purchase number INSIDE the transaction for atomicity
          final purchaseNumber = await _datasource.generatePurchaseNumber();
          final companionWithNumber = purchase.copyWith(
            purchaseNumber: Value(purchaseNumber),
          );
          final id = await _datasource.createPurchase(companionWithNumber, itemCompanions);
          return id;
        });
        break; // success
      } catch (e) {
        // Retry on UNIQUE constraint violation (concurrent purchase number)
        final isUniqueViolation = e.toString().contains('UNIQUE constraint failed');
        if (isUniqueViolation && attempt < maxRetries) {
          developer.log(
            'Purchase number collision on attempt $attempt, retrying...',
            name: 'PurchaseRepository',
          );
          continue;
        }
        rethrow;
      }
    }

    // Audit log outside transaction (non-critical, fire-and-forget)
    _auditService.log(
      entityType: 'purchase',
      entityId: purchaseId,
      action: 'create',
      newValue: {
        'purchaseId': purchaseId,
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
    bool taxInclusiveAtPost = false,
  }) async {
    // Guard: only draft/pending purchases can be edited.
    // Posted/voided purchases have journal entries that would become stale.
    final existing = await getPurchaseById(purchaseId);
    if (existing != null && !existing.isDraft) {
      throw Exception(
        'Cannot edit a ${existing.status} purchase. Void it and create a new one instead.',
      );
    }

    // Phase 11.2 — the snapshot is re-stamped on edit because the
    // engine just recomputed the totals.
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
    ).withPricingSnapshot(taxInclusive: taxInclusiveAtPost);

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

    // Void any legacy journal entries that may exist from old code flow
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'purchases',
      sourceId: purchaseId,
      reason: 'Purchase updated (draft)',
      userId: await _currentUserId(),
    );

    final ok = await _datasource.updatePurchase(purchaseId, purchase, itemCompanions);

    if (ok) {
      // Journal entries are NOT created here — they are deferred to postPurchase()
      // to keep GL and supplier sub-ledger in sync.

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
    final userId = await _currentUserId();

    // Read purchase data BEFORE posting (need totalCents, paidAmountCents, etc.)
    final purchase = await _datasource.getPurchaseById(purchaseId);
    if (purchase == null) throw Exception('Purchase not found');

    // Post purchase (updates stock, supplier balance, supplier transactions)
    await _datasource.postPurchase(purchaseId);

    // Create journal entries AFTER posting so GL and sub-ledger stay in sync.
    // Void any legacy journal entries that may have been created at draft time.
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'purchases',
      sourceId: purchaseId,
      reason: 'Re-creating journal entries on post',
      userId: userId,
    );

    await _journalService.recordPurchaseJournalEntry(
      purchaseId: purchaseId,
      totalCents: purchase.totalCents.toBigInt().toInt(),
      paidAmountCents: purchase.paidAmountCents.toBigInt().toInt(),
      currencyId: purchase.currencyId,
      taxCents: purchase.taxCents.toBigInt().toInt(),
      paymentMethod: purchase.paymentMethod,
      userId: userId,
    );

    // Audit: log purchase posting (stock was updated)
    await _auditService.log(
      entityType: 'purchase',
      entityId: purchaseId,
      action: 'post',
      newValue: {'status': 'posted'},
      userId: userId,
    );
  }

  @override
  Future<void> voidPurchase(int purchaseId) async {
    // 2026-05-13 — pre-flight integrity guard. The analyzer is the single
    // source of truth for "what breaks if we void this purchase?". On a
    // hard blocker (entangled adjustment returns or projected negative
    // stock) we throw `VoidBlockedByImpactException` carrying the full
    // report so the UI can render an actionable dialog instead of
    // silently producing AP / Inventory drift like the one diagnosed in
    // `tapix_backup_20260513_121448.db`.
    final report = await VoidImpactAnalyzer(_db).analyzePurchaseVoid(purchaseId);
    if (report.hasBlockers) {
      throw VoidBlockedByImpactException(report);
    }

    // Void journal entries BEFORE voiding the purchase.
    // This MUST succeed — if it fails the entire void is aborted to prevent GL drift.
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'purchases',
      sourceId: purchaseId,
      reason: 'Purchase voided',
      userId: await _currentUserId(),
    );

    // 2026-05-13 — pass the journal service so the DAO's cascade-void of
    // linked purchase_returns also reverses their JEs (root-cause #3).
    await _datasource.voidPurchase(
      purchaseId,
      journalEntryService: _journalService,
      userId: await _currentUserId(),
    );

    // Audit: log purchase voiding (stock was reversed)
    await _auditService.logVoid(
      entityType: 'purchase',
      entityId: purchaseId,
      reason: 'User voided purchase',
      userId: await _currentUserId(),
    );
  }

  @override
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
    bool taxInclusiveAtPost = false,
  }) async {
    // 1. Fetch original purchase to validate
    final originalPurchase = await getPurchaseById(originalPurchaseId);
    if (originalPurchase == null) {
      throw StateError('Purchase #$originalPurchaseId not found');
    }

    // 2. Check accounting period is open for the original purchase date
    final txDate = originalPurchase.purchaseDate;
    final periodRows = await _db.customSelect(
      '''SELECT id, is_closed FROM accounting_periods
         WHERE start_date <= ? AND end_date >= ?
         ORDER BY start_date DESC LIMIT 1''',
      variables: [
        Variable.withDateTime(txDate),
        Variable.withDateTime(txDate),
      ],
      readsFrom: {_db.accountingPeriods},
    ).get();
    if (periodRows.isNotEmpty && periodRows.first.read<bool>('is_closed')) {
      throw StateError(
        'Cannot edit purchase: the accounting period containing this '
        'purchase has been closed.',
      );
    }

    // 3. Check if purchase has any non-voided returns - cannot edit if returns exist
    final returns = await _db.customSelect(
      'SELECT COUNT(*) as cnt FROM purchase_returns WHERE purchase_id = ? AND status != ?',
      variables: [
        Variable.withInt(originalPurchaseId),
        Variable.withString('voided'),
      ],
      readsFrom: {_db.purchaseReturns},
    ).getSingle();
    if (returns.read<int>('cnt') > 0) {
      throw StateError(
        'Cannot edit purchase: it has associated returns. '
        'Void the returns first or create a new purchase.',
      );
    }

    final userId = await _currentUserId();

    // 4. Void the original purchase (this restores stock and reverses accounting)
    await voidPurchase(originalPurchaseId);

    // 5. Create new purchase with the edited data
    final newPurchaseId = await createPurchase(
      supplierId: supplierId,
      currencyId: currencyId,
      subtotalCents: subtotalCents,
      discountCents: discountCents,
      taxCents: taxCents,
      totalCents: totalCents,
      paidAmountCents: paidAmountCents,
      items: items,
      paymentMethod: paymentMethod,
      supplierInvoiceRef: supplierInvoiceRef,
      notes: notes != null 
          ? '$notes\n[Edited from ${originalPurchase.purchaseNumber}]'
          : '[Edited from ${originalPurchase.purchaseNumber}]',
      purchaseDate: purchaseDate ?? originalPurchase.purchaseDate,
      dueDate: dueDate,
      taxInclusiveAtPost: taxInclusiveAtPost,
    );

    // 6. Post the new purchase to apply stock and accounting
    await postPurchase(newPurchaseId);

    // 7. Audit log
    await _auditService.log(
      entityType: 'purchase',
      entityId: newPurchaseId,
      action: 'edit_posted_purchase',
      oldValue: {
        'originalPurchaseId': originalPurchaseId,
        'originalPurchaseNumber': originalPurchase.purchaseNumber,
        'originalTotalCents': originalPurchase.totalCents.toString(),
      },
      newValue: {
        'newPurchaseId': newPurchaseId,
        'newTotalCents': totalCents.toString(),
        'itemCount': items.length,
      },
      userId: userId,
    );

    return newPurchaseId;
  }

  @override
  Future<int> deletePurchase(int purchaseId) async {
    // Void journal entries BEFORE deleting the purchase record.
    // This MUST succeed — if it fails the entire delete is aborted to prevent GL drift.
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'purchases',
      sourceId: purchaseId,
      reason: 'Purchase deleted',
      userId: await _currentUserId(),
    );

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
    DateTime? dueDate,
    bool allowNegativeStock = false,
    String? idempotencyKey,
    bool taxInclusiveAtPost = false,
  }) async {
    final returnNumber = await generateReturnNumber();

    // Phase 14.0 — only persist dueDate when refund method is cheque.
    final effectiveDueDate =
        refundMethod == 'cheque' ? dueDate : null;

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
      dueDate: Value(effectiveDueDate),
      idempotencyKey: Value(idempotencyKey),
    ).withPricingSnapshot(taxInclusive: taxInclusiveAtPost);

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
      await _datasource.postPurchaseReturn(id, allowNegativeStock: allowNegativeStock);

      // Create journal entries — MANDATORY.
      //
      // taxCents MUST be passed: it generates the Cr 1300 VAT Receivable
      // line that reverses the input VAT we claimed when we received the
      // goods. Omitting it (the previous bug) left the tax stuck on the
      // VAT-receivable account forever and caused regulator-facing tax
      // returns to over-claim refunds.
      // `postingDate` flows through to `ReturnPostingService` so the
      // Phase 2.5 fiscal-period guard rejects any post landing inside a
      // closed period — centrally, for every return flow.
      await _journalService.recordPurchaseReturnJournalEntry(
        returnId: id,
        totalCents: totalCents.toBigInt().toInt(),
        taxCents: taxCents.toBigInt().toInt(),
        currencyId: currencyId,
        refundMethod: refundMethod,
        userId: userId,
        postingDate: returnDate ?? DateTime.now(),
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
  Future<void> postPurchaseReturn(int returnId, {bool allowNegativeStock = false}) async {
    await _datasource.postPurchaseReturn(returnId, allowNegativeStock: allowNegativeStock);

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
    // Void journal entries BEFORE voiding the return.
    // This MUST succeed — if it fails the entire void is aborted to prevent GL drift.
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'purchase_returns',
      sourceId: returnId,
      reason: 'Purchase return voided',
      userId: await _currentUserId(),
    );

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

  @override
  Stream<Map<int, List<String>>> watchPurchaseProductSearchTerms() =>
      _datasource.watchPurchaseProductSearchTerms();

  @override
  Stream<Map<String, List<String>>> watchPurchaseReturnProductSearchTerms() =>
      _datasource.watchPurchaseReturnProductSearchTerms();
}
