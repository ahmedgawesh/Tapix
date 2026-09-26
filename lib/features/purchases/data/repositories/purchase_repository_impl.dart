import '../../../../core/services/business/warehouse_document_reader.dart';
import '../../../../core/services/business/document_posting_scope.dart';
import '../../../../core/services/business/warehouse_operation_scope.dart';
import '../../../../core/services/business/warehouse_read_scope.dart';
import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/cheque_confirmation_dao.dart';
import '../../../../core/database/daos/cheque_instrument_dao.dart';
import '../../../../core/payments/checkout_settlement.dart';
import '../../../../core/payments/return_settlement_service.dart';
import '../../../../core/pricing/pricing_snapshot.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/cheque_source_void_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/services/return_calculation_service.dart';
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
  final WarehouseOperationScope? warehouseScope;
  late final _reader = WarehouseDocumentReader(_db, scope: warehouseScope);

  PurchaseRepositoryImpl(
    this._datasource,
    this._auditService,
    this._sessionService,
    this._journalService,
    this._db, {
    this.warehouseScope,
  });

  /// Get the current user ID from the session for audit logging.
  Future<int?> _currentUserId() => _sessionService.getCurrentUserId();

  // ==================== PURCHASES ====================

  @override
  Stream<List<PurchaseEntity>> watchAllPurchases() {
    return _datasource.watchAllPurchases().asyncMap(
      (rows) => _reader.filter(
        rows,
        (_) => InventoryPostingDocument.purchase,
        (r) => r.id,
      ),
    );
  }

  @override
  Stream<List<PurchaseEntity>> watchPurchasesByStatus(String status) {
    return _datasource
        .watchPurchasesByStatus(status)
        .asyncMap(
          (rows) => _reader.filter(
            rows,
            (_) => InventoryPostingDocument.purchase,
            (r) => r.id,
          ),
        );
  }

  @override
  Stream<List<PurchaseEntity>> watchPurchasesBySupplier(int supplierId) {
    return _datasource
        .watchPurchasesBySupplier(supplierId)
        .asyncMap(
          (rows) => _reader.filter(
            rows,
            (_) => InventoryPostingDocument.purchase,
            (r) => r.id,
          ),
        );
  }

  @override
  Stream<List<PurchaseEntity>> searchPurchases(String query) {
    return _datasource
        .searchPurchases(query)
        .asyncMap(
          (rows) => _reader.filter(
            rows,
            (_) => InventoryPostingDocument.purchase,
            (r) => r.id,
          ),
        );
  }

  @override
  Future<PurchaseEntity?> getPurchaseById(int id) async {
    return await _reader.contains(InventoryPostingDocument.purchase, id)
        ? _datasource.getPurchaseById(id)
        : null;
  }

  @override
  Future<List<PurchaseItemEntity>> getPurchaseItems(int purchaseId) async {
    return await _reader.contains(InventoryPostingDocument.purchase, purchaseId)
        ? _datasource.getPurchaseItems(purchaseId)
        : [];
  }

  @override
  Stream<List<PurchaseItemEntity>> watchPurchaseItems(int purchaseId) {
    return _reader.gate(
      InventoryPostingDocument.purchase,
      purchaseId,
      _datasource.watchPurchaseItems(purchaseId),
      <PurchaseItemEntity>[],
    );
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
    List<CheckoutPaymentAllocation> initialPayments = const [],
  }) async {
    final settlement = CheckoutSettlement(initialPayments);
    final isPureCheque =
        initialPayments.isEmpty &&
        (paymentMethod == 'cheque' || paymentMethod == 'check');
    if (initialPayments.isNotEmpty) {
      settlement.validate(invoiceTotalCents: totalCents.toBigInt().toInt());
      if (settlement.totalSettledCents != paidAmountCents.toBigInt().toInt()) {
        throw ArgumentError('settlement_total_mismatch');
      }
    }
    if (isPureCheque && dueDate == null) {
      throw ArgumentError('cheque_due_date_required');
    }
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
      paidAmountCents: Value(isPureCheque ? Decimal.zero : paidAmountCents),
      status: const Value('draft'),
      paymentMethod: Value(paymentMethod),
      supplierInvoiceRef: Value(supplierInvoiceRef),
      notes: Value(notes),
      purchaseDate: Value(purchaseDate ?? DateTime.now()),
      dueDate: Value(dueDate),
    ).withPricingSnapshot(taxInclusive: taxInclusiveAtPost);

    final itemCompanions = items
        .map(
          (item) => db.PurchaseItemsCompanion(
            productId: Value(item.productId),
            supplierIdentityRequested: Value(item.supplierIdentityRequested),
            variantId: Value(item.variantId),
            quantity: Value(item.quantity),
            quantityScale: Value(item.quantityScale),
            measurementType: Value(item.measurementType),
            unitCostCents: Value(item.unitCostCents),
            discountCents: Value(item.discountCents),
            subtotalCents: Value(item.subtotalCents),
            taxCents: Value(item.taxCents),
            totalCents: Value(item.totalCents),
            originalCostCents: Value(item.originalCostCents),
            originalPriceCents: Value(item.originalPriceCents),
            originalWholesalePriceCents: Value(
              item.originalWholesalePriceCents,
            ),
            newSellPriceCents: Value(item.newSellPriceCents),
            newWholesalePriceCents: Value(item.newWholesalePriceCents),
            expiryDate: Value(item.expiryDate),
            manufacturerLotNumber: Value(item.manufacturerLotNumber),
          ),
        )
        .toList();

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
          final id = await _datasource.createPurchase(
            companionWithNumber,
            itemCompanions,
            scope: warehouseScope,
          );
          for (final allocation in initialPayments) {
            if (allocation.isCheque) {
              await ChequeInstrumentDao(_db).create(
                direction: ChequeDirectionValue.outgoing,
                sourceTable: ChequeSourceTables.purchase,
                sourceId: id,
                amountCents: allocation.amountCents,
                currencyId: currencyId,
                dueDate: allocation.dueDate!,
                partyType: 'supplier',
                partyId: supplierId,
                chequeNumber: allocation.reference,
                bankName: allocation.bankName,
                issueDate: allocation.issueDate ?? purchaseDate,
                userId: userId,
                note: allocation.note,
              );
              continue;
            }
            await _db
                .into(_db.purchasePayments)
                .insert(
                  db.PurchasePaymentsCompanion.insert(
                    purchaseId: id,
                    amountCents: Decimal.fromInt(allocation.amountCents),
                    currencyId: currencyId,
                    paymentMethod: allocation.method,
                    reference: Value(allocation.reference),
                    notes: Value(
                      allocation.note ?? 'Initial invoice settlement',
                    ),
                    paymentDate: Value(
                      allocation.issueDate ?? purchaseDate ?? DateTime.now(),
                    ),
                  ),
                );
          }
          return id;
        });
        break; // success
      } catch (e) {
        // Retry on UNIQUE constraint violation (concurrent purchase number)
        final isUniqueViolation = e.toString().contains(
          'UNIQUE constraint failed',
        );
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
  }) => _db.transaction(() async {
    await DocumentPostingScope.validate(
      _db,
      InventoryPostingDocument.purchase,
      purchaseId,
      scope: warehouseScope,
    );
    // Guard: only draft/pending purchases can be edited.
    // Posted/voided purchases have journal entries that would become stale.
    final existing = await getPurchaseById(purchaseId);
    if (existing == null) {
      throw StateError('Purchase not found in this warehouse.');
    }
    if (!existing.isDraft) {
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

    final itemCompanions = items
        .map(
          (item) => db.PurchaseItemsCompanion(
            productId: Value(item.productId),
            supplierIdentityRequested: Value(item.supplierIdentityRequested),
            variantId: Value(item.variantId),
            quantity: Value(item.quantity),
            quantityScale: Value(item.quantityScale),
            measurementType: Value(item.measurementType),
            unitCostCents: Value(item.unitCostCents),
            discountCents: Value(item.discountCents),
            subtotalCents: Value(item.subtotalCents),
            taxCents: Value(item.taxCents),
            totalCents: Value(item.totalCents),
            originalCostCents: Value(item.originalCostCents),
            originalPriceCents: Value(item.originalPriceCents),
            originalWholesalePriceCents: Value(
              item.originalWholesalePriceCents,
            ),
            newSellPriceCents: Value(item.newSellPriceCents),
            newWholesalePriceCents: Value(item.newWholesalePriceCents),
            expiryDate: Value(item.expiryDate),
            manufacturerLotNumber: Value(item.manufacturerLotNumber),
          ),
        )
        .toList();

    // Void any legacy journal entries that may exist from old code flow
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'purchases',
      sourceId: purchaseId,
      reason: 'Purchase updated (draft)',
      userId: await _currentUserId(),
    );

    final ok = await _datasource.updatePurchase(
      purchaseId,
      purchase,
      itemCompanions,
    );

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
  });

  @override
  Future<void> postPurchase(int purchaseId) async {
    await _db.transaction(() async {
      final userId = await _currentUserId();

      // Read purchase data BEFORE posting (need totalCents, paidAmountCents, etc.)
      final purchase = await _datasource.getPurchaseById(purchaseId);
      if (purchase == null) throw Exception('Purchase not found');
      if ((purchase.paymentMethod == 'cheque' ||
              purchase.paymentMethod == 'check') &&
          purchase.dueDate == null) {
        throw StateError('cheque_due_date_required');
      }

      // Post purchase (updates stock, supplier balance, supplier transactions)
      await _datasource.postPurchase(purchaseId, scope: warehouseScope);

      // Create journal entries AFTER posting so GL and sub-ledger stay in sync.
      // Void any legacy journal entries that may have been created at draft time.
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'purchases',
        sourceId: purchaseId,
        reason: 'Re-creating journal entries on post',
        userId: userId,
      );

      final inventoryNetCents = await _db.purchaseDao
          .computePurchaseInventoryNetCents(purchaseId);
      final payments = await _reader.read(
        InventoryPostingDocument.purchase,
        purchaseId,
        () => _datasource.getPurchasePayments(purchaseId),
        <PurchasePaymentEntity>[],
      );
      final useStructuredSettlement =
          purchase.paymentMethod == 'mixed' ||
          purchase.paymentMethod == 'cheque' ||
          purchase.paymentMethod == 'check';
      await _journalService.recordPurchaseJournalEntry(
        purchaseId: purchaseId,
        totalCents: purchase.totalCents.toBigInt().toInt(),
        paidAmountCents: useStructuredSettlement
            ? 0
            : purchase.paidAmountCents.toBigInt().toInt(),
        currencyId: purchase.currencyId,
        taxCents: purchase.taxCents.toBigInt().toInt(),
        inventoryNetCents: inventoryNetCents,
        paymentMethod: useStructuredSettlement
            ? 'credit'
            : purchase.paymentMethod,
        userId: userId,
      );

      if (useStructuredSettlement) {
        for (final payment in payments) {
          await _journalService.recordSupplierPaymentJournalEntry(
            paymentId: payment.id,
            amountCents: payment.amountCents.toBigInt().toInt(),
            currencyId: payment.currencyId,
            paymentMethod: payment.paymentMethod,
            userId: userId,
          );
        }
      }

      if ((purchase.paymentMethod == 'cheque' ||
              purchase.paymentMethod == 'check') &&
          purchase.dueDate != null) {
        final instrumentDao = ChequeInstrumentDao(_db);
        final existingInstruments = await instrumentDao.getBySource(
          sourceTable: ChequeSourceTables.purchase,
          sourceId: purchaseId,
        );
        if (existingInstruments.isEmpty) {
          await instrumentDao.ensurePrimary(
            direction: ChequeDirectionValue.outgoing,
            sourceTable: ChequeSourceTables.purchase,
            sourceId: purchaseId,
            amountCents: purchase.totalCents.toBigInt().toInt(),
            currencyId: purchase.currencyId,
            dueDate: purchase.dueDate!,
            partyType: 'supplier',
            partyId: purchase.supplierId,
            userId: userId,
          );
        }
      }

      final actualInventoryValue = await _db.purchaseDao
          .computePurchaseInventoryValueAtPostCents(purchaseId);
      final roundingDelta = actualInventoryValue - inventoryNetCents;
      if (roundingDelta != 0) {
        await _journalService.recordInventoryRoundingJournalEntry(
          sourceTable: 'purchases',
          sourceId: purchaseId,
          deltaValueCents: roundingDelta,
          currencyId: purchase.currencyId,
          reason: 'Purchase ${purchase.purchaseNumber}',
          userId: userId,
        );
      }

      // Audit: log purchase posting (stock was updated)
      await _auditService.log(
        entityType: 'purchase',
        entityId: purchaseId,
        action: 'post',
        newValue: {'status': 'posted'},
        userId: userId,
      );
    });
  }

  @override
  Future<void> voidPurchase(int purchaseId) async {
    await _db.transaction(() async {
      // 2026-05-13 — pre-flight integrity guard. The analyzer is the single
      // source of truth for "what breaks if we void this purchase?". On a
      // hard blocker (entangled adjustment returns or projected negative
      // stock) we throw `VoidBlockedByImpactException` carrying the full
      // report so the UI can render an actionable dialog instead of
      // silently producing AP / Inventory drift like the one diagnosed in
      // `tapix_backup_20260513_121448.db`.
      final report = await VoidImpactAnalyzer(
        _db,
        warehouseScope: warehouseScope == null
            ? null
            : await WarehouseReadScope.resolve(
                _db,
                warehouseId: warehouseScope!.warehouseId,
              ),
      ).analyzePurchaseVoid(purchaseId);
      if (report.hasBlockers) {
        throw VoidBlockedByImpactException(report);
      }

      final userId = await _currentUserId();
      final linkedReturns =
          await (_db.select(_db.purchaseReturns)..where(
                (row) =>
                    row.purchaseId.equals(purchaseId) &
                    row.status.isNotValue('voided'),
              ))
              .get();
      for (final purchaseReturn in linkedReturns) {
        await ChequeSourceVoidService.voidForSource(
          db: _db,
          journalService: _journalService,
          sourceTable: ChequeSourceTables.purchaseReturn,
          sourceId: purchaseReturn.id,
          reason: 'Purchase voided — linked return cheque cancelled',
          userId: userId,
        );
      }
      await ChequeSourceVoidService.voidForSource(
        db: _db,
        journalService: _journalService,
        sourceTable: ChequeSourceTables.purchase,
        sourceId: purchaseId,
        reason: 'Purchase voided — cheque cancelled',
        userId: userId,
      );

      // Void journal entries BEFORE voiding the purchase.
      // This MUST succeed — if it fails the entire void is aborted to prevent GL drift.
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'purchases',
        sourceId: purchaseId,
        reason: 'Purchase voided',
        userId: await _currentUserId(),
      );

      // 2026-05-18 — Phase 15.2 — Reverse the GL journal entry for EVERY
      // payment row attached to this purchase (cash, cheque-cleared, mixed
      // tender, supplier-credit reapplications). The DAO already records a
      // `payment_reversal` supplier_transaction so the sub-ledger zeroes out,
      // but until Phase 15.2 the GL leg was orphaned: JE Dr 2000 / Cr Cash|Bank
      // remained posted, so AP and the cash/bank ledger silently drifted by
      // the cleared payment amount. Root cause of the AP drift = 89991¢
      // reproduced in `tapix_backup_20260518_051956.db`.
      final paymentsForVoid = await _datasource.getPurchasePayments(purchaseId);
      for (final p in paymentsForVoid) {
        await _journalService.voidJournalEntriesForSource(
          sourceTable: 'purchase_payments',
          sourceId: p.id,
          reason: 'Purchase voided — payment JE reversed',
          userId: await _currentUserId(),
        );
      }

      // 2026-05-13 — pass the journal service so the DAO's cascade-void of
      // linked purchase_returns also reverses their JEs (root-cause #3).
      await _datasource.voidPurchase(
        purchaseId,
        scope: warehouseScope,
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
    });
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
  }) => _db.transaction(() async {
    // 1. Fetch original purchase to validate
    final originalPurchase = await getPurchaseById(originalPurchaseId);
    if (originalPurchase == null) {
      throw StateError('Purchase #$originalPurchaseId not found');
    }

    // 2. Check accounting period is open for the original purchase date
    final txDate = originalPurchase.purchaseDate;
    final periodRows = await _db
        .customSelect(
          '''SELECT id, is_closed FROM accounting_periods
         WHERE start_date <= ? AND end_date >= ?
         ORDER BY start_date DESC LIMIT 1''',
          variables: [
            Variable.withDateTime(txDate),
            Variable.withDateTime(txDate),
          ],
          readsFrom: {_db.accountingPeriods},
        )
        .get();
    if (periodRows.isNotEmpty && periodRows.first.read<bool>('is_closed')) {
      throw StateError(
        'Cannot edit purchase: the accounting period containing this '
        'purchase has been closed.',
      );
    }

    // 3. Check if purchase has any non-voided returns - cannot edit if returns exist
    final returns = await _db
        .customSelect(
          'SELECT COUNT(*) as cnt FROM purchase_returns WHERE purchase_id = ? AND status != ?',
          variables: [
            Variable.withInt(originalPurchaseId),
            Variable.withString('voided'),
          ],
          readsFrom: {_db.purchaseReturns},
        )
        .getSingle();
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
  });

  @override
  Future<int> deletePurchase(int purchaseId) => _db.transaction(() async {
    await DocumentPostingScope.validate(
      _db,
      InventoryPostingDocument.purchase,
      purchaseId,
      scope: warehouseScope,
    );
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
  });

  @override
  Future<bool> updatePurchaseStatus(int purchaseId, String status) =>
      _db.transaction(() async {
        await DocumentPostingScope.validate(
          _db,
          InventoryPostingDocument.purchase,
          purchaseId,
          scope: warehouseScope,
        );
        final purchase = await _datasource.getPurchaseById(purchaseId);
        if (purchase == null ||
            !purchase.isDraft ||
            (status != 'draft' && status != 'pending')) {
          throw StateError(
            'Posting and voiding require the accounting workflow.',
          );
        }
        return _datasource.updatePurchaseStatus(purchaseId, status);
      });

  @override
  Stream<PurchaseDashboardStats> watchDashboardStats() =>
      _reader.changes.asyncMap(
        (_) => _reader.snapshot((scope) async {
          final stats = await _db.purchaseDao.getDashboardStats(
            warehouseScope: scope,
          );
          return PurchaseDashboardStats(
            totalCount: stats.totalCount,
            draftCount: stats.draftCount,
            postedCount: stats.postedCount,
            totalPayableCents: stats.totalPayableCents,
            totalPaidCents: stats.totalPaidCents,
            overdueCount: stats.overdueCount,
            returnsCount: stats.returnsCount,
          );
        }),
      );

  // ==================== RETURNS ====================

  @override
  Stream<List<PurchaseReturnEntity>> watchAllPurchaseReturns() {
    return _datasource.watchAllPurchaseReturns().asyncMap(
      (rows) => _reader.filter(
        rows,
        (r) => r.isAdjustment
            ? InventoryPostingDocument.purchaseAdjustment
            : InventoryPostingDocument.purchaseReturn,
        (r) => r.id,
      ),
    );
  }

  @override
  Stream<List<PurchaseReturnEntity>> watchPurchaseReturnsByPurchase(
    int purchaseId,
  ) {
    return _datasource
        .watchPurchaseReturnsByPurchase(purchaseId)
        .asyncMap(
          (rows) => _reader.filter(
            rows,
            (_) => InventoryPostingDocument.purchaseReturn,
            (r) => r.id,
          ),
        );
  }

  @override
  Future<List<PurchaseReturnEntity>> getPurchaseReturns(int purchaseId) {
    return _reader.read(
      InventoryPostingDocument.purchase,
      purchaseId,
      () => _datasource.getPurchaseReturns(purchaseId),
      <PurchaseReturnEntity>[],
    );
  }

  @override
  Future<PurchaseReturnEntity?> getPurchaseReturnById(int id) {
    return _reader.read(
      InventoryPostingDocument.purchaseReturn,
      id,
      () => _datasource.getPurchaseReturnById(id),
      null,
    );
  }

  @override
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItems(
    int returnId,
  ) {
    return _reader.gate(
      InventoryPostingDocument.purchaseReturn,
      returnId,
      _datasource.watchPurchaseReturnItems(returnId),
      <PurchaseReturnItemEntity>[],
    );
  }

  @override
  Stream<List<PurchaseReturnItemEntity>> watchPurchaseReturnItemsWithDetails(
    int returnId,
  ) {
    return _reader.gate(
      InventoryPostingDocument.purchaseReturn,
      returnId,
      _datasource.watchPurchaseReturnItemsWithDetails(returnId),
      <PurchaseReturnItemEntity>[],
    );
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
    List<CheckoutPaymentAllocation> settlementAllocations = const [],
  }) async {
    final structuredSettlement = settlementAllocations.isNotEmpty;
    final effectiveRefundMethod = structuredSettlement ? 'mixed' : refundMethod;
    final isChequeRefund =
        !structuredSettlement &&
        (effectiveRefundMethod == 'cheque' || effectiveRefundMethod == 'check');
    if (isChequeRefund && dueDate == null) {
      throw ArgumentError('cheque_due_date_required');
    }

    // Phase 14.0 — only persist dueDate when refund method is cheque.
    final effectiveDueDate = isChequeRefund ? dueDate : null;

    // ATOMIC: Wrap return creation, stock deduction, and journal entries
    // in a single transaction.
    final userId = await _currentUserId();
    late int postedSubtotalCents;
    late int postedDiscountCents;
    late int postedTaxCents;
    late int postedTotalCents;

    late String returnNumber;
    final returnId = await _db.transaction(() async {
      returnNumber = await generateReturnNumber();
      final originalPurchase = await _datasource.getPurchaseById(purchaseId);
      if (originalPurchase == null) throw Exception('Purchase not found');
      final inclusive = originalPurchase.taxInclusiveAtPost;
      final originalItems = await _datasource.getPurchaseItems(purchaseId);
      final originalById = {for (final item in originalItems) item.id: item};
      final histories = <int, LinkedReturnHistory>{};
      final calculatedItems = <PurchaseReturnItemInput>[];

      for (final input in items) {
        final original = originalById[input.purchaseItemId];
        if (original == null) {
          throw Exception(
            'Purchase item #${input.purchaseItemId} does not belong to '
            'purchase #$purchaseId',
          );
        }
        final history =
            histories[input.purchaseItemId] ??
            await _db.purchaseDao.getLinkedReturnHistory(input.purchaseItemId);
        final calculated = ReturnCalculationService.computeProportionalReturn(
          originalQuantity: original.quantity,
          returnQuantity: input.quantity,
          originalSubtotalCents: original.subtotalCents.toBigInt().toInt(),
          originalDiscountCents: original.discountCents.toBigInt().toInt(),
          originalTaxCents: original.taxCents.toBigInt().toInt(),
          previousLinkedHistory: history,
          taxInclusivePricing: inclusive,
        );
        histories[input.purchaseItemId] = history.add(
          calculated,
          input.quantity,
        );
        calculatedItems.add(
          input.withCalculatedAmounts(
            calculated,
            sourceQuantityScale: original.quantityScale,
            sourceMeasurementType: original.measurementType,
          ),
        );
      }

      postedSubtotalCents = calculatedItems.fold(
        0,
        (sum, item) => sum + item.subtotalCents.toBigInt().toInt(),
      );
      postedDiscountCents = calculatedItems.fold(
        0,
        (sum, item) => sum + item.discountCents.toBigInt().toInt(),
      );
      postedTaxCents = calculatedItems.fold(
        0,
        (sum, item) => sum + item.taxCents.toBigInt().toInt(),
      );
      postedTotalCents = calculatedItems.fold(
        0,
        (sum, item) => sum + item.refundCents.toBigInt().toInt(),
      );

      final returnData = db.PurchaseReturnsCompanion(
        purchaseId: Value(purchaseId),
        returnNumber: Value(returnNumber),
        subtotalCents: Value(Decimal.fromInt(postedSubtotalCents)),
        discountCents: Value(Decimal.fromInt(postedDiscountCents)),
        taxCents: Value(Decimal.fromInt(postedTaxCents)),
        totalCents: Value(Decimal.fromInt(postedTotalCents)),
        currencyId: Value(currencyId),
        status: const Value('draft'),
        dispositionType: Value(dispositionType),
        refundMethod: Value(effectiveRefundMethod),
        reason: Value(reason),
        returnDate: Value(returnDate ?? DateTime.now()),
        dueDate: Value(effectiveDueDate),
        idempotencyKey: Value(idempotencyKey),
      ).withPricingSnapshot(taxInclusive: inclusive);

      final itemCompanions = calculatedItems
          .map(
            (item) => db.PurchaseReturnItemsCompanion(
              purchaseItemId: Value(item.purchaseItemId),
              quantity: Value(item.quantity),
              quantityScale: Value(item.quantityScale),
              measurementType: Value(item.measurementType),
              subtotalCents: Value(item.subtotalCents),
              discountCents: Value(item.discountCents),
              taxCents: Value(item.taxCents),
              refundCents: Value(item.refundCents),
              reason: Value(item.reason),
            ),
          )
          .toList();
      final id = await _datasource.createPurchaseReturn(
        returnData,
        itemCompanions,
      );

      // Auto-post the return (update stock)
      await _datasource.postPurchaseReturn(
        id,
        scope: warehouseScope,
        allowNegativeStock: allowNegativeStock,
      );

      // Inventory leg = ACTUAL valuation removed by the stock ledger
      // (FIFO batch consumption / WAC current cost), computed AFTER the post
      // so the batch_consumptions rows exist. Without this the JE defaults
      // 1200 to the refund net, which drifts away from Σ(stock×cost) whenever
      // a returned FIFO lot — or the current WAC cost — differs from the
      // original purchase price. The refund vs cost gap flows to 4100.
      final inventoryCostCents = await _db.purchaseDao
          .computePurchaseReturnInventoryCostCents(id);

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
        totalCents: postedTotalCents,
        taxCents: postedTaxCents,
        inventoryCostCents: inventoryCostCents,
        currencyId: currencyId,
        refundMethod: structuredSettlement ? 'credit' : effectiveRefundMethod,
        userId: userId,
        postingDate: returnDate ?? DateTime.now(),
      );

      if (structuredSettlement) {
        await ReturnSettlementService.apply(
          db: _db,
          journalService: _journalService,
          side: ReturnSettlementSide.purchase,
          sourceTable: ChequeSourceTables.purchaseReturn,
          sourceId: id,
          partyId: originalPurchase.supplierId,
          totalCents: postedTotalCents,
          currencyId: currencyId,
          allocations: settlementAllocations,
          documentDate: returnDate ?? DateTime.now(),
          userId: userId,
        );
      } else if (effectiveDueDate != null &&
          (effectiveRefundMethod == 'cheque' ||
              effectiveRefundMethod == 'check')) {
        await ChequeInstrumentDao(_db).ensurePrimary(
          direction: ChequeDirectionValue.incoming,
          sourceTable: ChequeSourceTables.purchaseReturn,
          sourceId: id,
          amountCents: postedTotalCents,
          currencyId: currencyId,
          dueDate: effectiveDueDate,
          partyType: 'supplier',
          partyId: originalPurchase.supplierId,
          userId: userId,
        );
      }

      return id;
    });

    // Await the non-critical audit write before returning. LAN callers may
    // own an outer transaction; a fire-and-forget write would otherwise keep
    // using that transaction runner after it has committed.
    try {
      await _auditService.log(
        entityType: 'purchase_return',
        entityId: returnId,
        action: 'create_and_post',
        newValue: {
          'purchaseId': purchaseId,
          'returnNumber': returnNumber,
          'totalCents': postedTotalCents.toString(),
          'dispositionType': dispositionType,
          'itemCount': items.length,
        },
        userId: userId,
      );
    } catch (_) {
      // Audit availability must not invalidate an already posted return.
    }

    return returnId;
  }

  @override
  Future<void> postPurchaseReturn(
    int returnId, {
    bool allowNegativeStock = false,
  }) async {
    await _datasource.postPurchaseReturn(
      returnId,
      scope: warehouseScope,
      allowNegativeStock: allowNegativeStock,
    );

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
    final userId = await _currentUserId();
    await _db.transaction(() async {
      await ChequeSourceVoidService.voidForSource(
        db: _db,
        journalService: _journalService,
        sourceTable: ChequeSourceTables.purchaseReturn,
        sourceId: returnId,
        reason: 'Purchase return voided — cheque cancelled',
        userId: userId,
      );
      await ReturnSettlementService.voidImmediate(
        db: _db,
        journalService: _journalService,
        side: ReturnSettlementSide.purchase,
        sourceTable: ChequeSourceTables.purchaseReturn,
        sourceId: returnId,
        reason: 'Purchase return settlement voided',
        userId: userId,
      );
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'purchase_returns',
        sourceId: returnId,
        reason: 'Purchase return voided',
        userId: userId,
      );
      await _datasource.voidPurchaseReturn(returnId, scope: warehouseScope);
    });

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
    return _reader.gate(
      InventoryPostingDocument.purchase,
      purchaseId,
      _datasource.watchPurchasePayments(purchaseId),
      <PurchasePaymentEntity>[],
    );
  }

  @override
  Future<List<PurchasePaymentEntity>> getPurchasePayments(int purchaseId) {
    return _reader.read(
      InventoryPostingDocument.purchase,
      purchaseId,
      () => _datasource.getPurchasePayments(purchaseId),
      <PurchasePaymentEntity>[],
    );
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
      await DocumentPostingScope.validate(
        _db,
        InventoryPostingDocument.purchase,
        purchaseId,
        scope: warehouseScope,
      );
      final source = await (_db.select(
        _db.purchases,
      )..where((d) => d.id.equals(purchaseId))).getSingle();
      if (source.status != 'posted') {
        throw StateError('Payments require a posted purchase');
      }
      if (source.currencyId != currencyId ||
          amountCents <= Decimal.zero ||
          Decimal.fromBigInt(amountCents.toBigInt()) != amountCents) {
        throw StateError(
          'Payment must use positive whole minor units in the invoice currency',
        );
      }
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
  Future<void> deletePayment(int paymentId) => _db.transaction(() async {
    final payment = await (_db.select(
      _db.purchasePayments,
    )..where((p) => p.id.equals(paymentId))).getSingleOrNull();
    if (payment == null) throw StateError('Payment not found');
    await DocumentPostingScope.validate(
      _db,
      InventoryPostingDocument.purchase,
      payment.purchaseId,
      scope: warehouseScope,
    );

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

    await _datasource.deletePayment(paymentId);
  });

  @override
  Future<int> getReturnedQuantity(int purchaseItemId) => _reader.readItem(
    InventoryPostingDocument.purchase,
    purchaseItemId,
    () => _datasource.getReturnedQuantity(purchaseItemId),
    0,
  );

  @override
  Future<LinkedReturnHistory> getLinkedReturnHistory(int purchaseItemId) =>
      _reader.readItem(
        InventoryPostingDocument.purchase,
        purchaseItemId,
        () => _db.purchaseDao.getLinkedReturnHistory(purchaseItemId),
        LinkedReturnHistory.zero,
      );

  @override
  Stream<Set<int>> watchPurchaseIdsWithReturns() => _datasource
      .watchPurchaseIdsWithReturns()
      .asyncMap((rows) => _reader.ids(InventoryPostingDocument.purchase, rows));

  @override
  Stream<Map<int, List<String>>> watchPurchaseProductSearchTerms() =>
      _datasource.watchPurchaseProductSearchTerms().asyncMap(
        (rows) => _reader.searchTerms(InventoryPostingDocument.purchase, rows),
      );

  @override
  Stream<Map<String, List<String>>> watchPurchaseReturnProductSearchTerms() =>
      _datasource.watchPurchaseReturnProductSearchTerms().asyncMap(
        _reader.returnSearchTerms,
      );
}
