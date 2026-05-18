import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/sale_dao.dart' hide SaleDashboardStats;
import '../../../../core/pricing/pricing_snapshot.dart';
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/commissions/commission_service.dart';
import '../../../../core/services/einvoice/einvoice_dispatch_service.dart';
import '../../../../core/services/einvoice/einvoice_document.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../../core/services/loyalty/loyalty_points_service.dart';
import '../../../../core/services/void_impact_analyzer.dart';
import '../../../auth/data/services/session_service.dart';
import '../../../customers/domain/repositories/loyalty_repository.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';
import '../datasources/sale_local_datasource.dart';

class SaleRepositoryImpl implements SaleRepository {
  final SaleLocalDatasource _datasource;
  final SaleDao _dao;
  final JournalEntryService _journalService;
  final AuditLogService _audit;
  final SessionService _sessionService;
  final LoyaltyRepository _loyaltyRepository;
  // Phase 6 — commission + loyalty math live in their own services.
  // This repository is now a pure consumer; no inline arithmetic.
  final CommissionService _commissionService;
  final LoyaltyPointsService _loyaltyPointsService;
  /// Optional — e-invoice dispatcher. Never throws; any failure is logged
  /// and persisted on the `einvoice_documents` row (status=`rejected`)
  /// so the sale/return is never rolled back for an e-invoicing issue.
  /// When null (old tests) dispatch is a silent no-op.
  final EInvoiceDispatchService? _einvoiceDispatch;

  SaleRepositoryImpl(
    this._datasource,
    this._dao,
    this._journalService,
    this._audit,
    this._sessionService,
    this._loyaltyRepository,
    this._commissionService,
    this._loyaltyPointsService, {
    EInvoiceDispatchService? einvoiceDispatch,
  }) : _einvoiceDispatch = einvoiceDispatch;

  Future<int?> _currentUserId() => _sessionService.getCurrentUserId();

  @override
  Future<String> generateInvoiceNumber() => _datasource.generateInvoiceNumber();

  @override
  Stream<List<SaleEntity>> watchAllSales() => _datasource.watchAllSales();

  @override
  Stream<List<SaleEntity>> watchCustomerSales(int customerId) =>
      _datasource.watchCustomerSales(customerId);

  @override
  Future<SaleEntity?> getSaleById(int id) => _datasource.getSaleById(id);

  @override
  Future<List<SaleItemEntity>> getSaleItems(int saleId) =>
      _datasource.getSaleItemsWithDetails(saleId);

  @override
  Stream<List<SaleItemEntity>> watchSaleItems(int saleId) =>
      _datasource.watchSaleItems(saleId);

  @override
  Future<int> createSale({
    int? customerId,
    int? employeeId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required Decimal paidAmountCents,
    required String paymentMethod,
    required List<SaleItemInput> items,
    String? notes,
    DateTime? saleDate,
    DateTime? dueDate,
    bool allowNegativeStock = false,
    bool taxInclusiveAtPost = false,
  }) async {
    // Invoice number is generated INSIDE the transaction (see below)
    // to prevent race conditions when two sales are created concurrently.

    final saleCompanion = db.SalesCompanion(
      invoiceNumber: const Value.absent(), // placeholder, set inside tx
      customerId: customerId != null ? Value(customerId) : const Value.absent(),
      employeeId: employeeId != null ? Value(employeeId) : const Value.absent(),
      subtotalCents: Value(subtotalCents),
      taxCents: Value(taxCents),
      discountCents: Value(discountCents),
      totalCents: Value(totalCents),
      paidAmountCents: Value(paidAmountCents),
      currencyId: Value(currencyId),
      paymentMethod: Value(paymentMethod),
      status: const Value('draft'),
      notes: notes != null ? Value(notes) : const Value.absent(),
      saleDate: saleDate != null ? Value(saleDate) : Value(DateTime.now()),
      dueDate: dueDate != null ? Value(dueDate) : const Value.absent(),
    ).withPricingSnapshot(taxInclusive: taxInclusiveAtPost);

    final itemCompanions = items.map((i) => db.SaleItemsCompanion(
          productId: Value(i.productId),
          variantId: i.variantId != null ? Value(i.variantId!) : const Value.absent(),
          employeeId: i.employeeId != null ? Value(i.employeeId!) : const Value.absent(),
          quantity: Value(i.quantity),
          unitPriceCents: Value(i.unitPriceCents),
          subtotalCents: Value(i.subtotalCents),
          discountCents: Value(i.discountCents),
          taxCents: Value(i.taxCents),
          totalCents: Value(i.totalCents),
        )).toList();

    // ATOMIC: Wrap sale creation, stock deduction, customer balance,
    // journal entries, and commissions in a single transaction.
    // If any step fails, everything rolls back — preventing GL ↔ sub-ledger drift.
    final userId = await _currentUserId();
    final effectiveSaleDate = saleDate ?? DateTime.now();

    const maxRetries = 3;
    late int saleId;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        saleId = await _dao.db.transaction(() async {
      // Generate invoice number INSIDE the transaction for atomicity
      final invoiceNumber = await _dao.generateInvoiceNumber();
      final companionWithNumber = saleCompanion.copyWith(
        invoiceNumber: Value(invoiceNumber),
      );
      final id = await _dao.createSaleWithItems(companionWithNumber, itemCompanions);

      // Auto-post: deduct stock and update customer balance
      await _dao.postSale(id, allowNegativeStock: allowNegativeStock);

      // Create journal entries — MANDATORY, errors propagate
      await _journalService.recordSaleJournalEntry(
        saleId: id,
        totalCents: totalCents.toBigInt().toInt(),
        paidAmountCents: paidAmountCents.toBigInt().toInt(),
        currencyId: currencyId,
        taxCents: taxCents.toBigInt().toInt(),
        paymentMethod: paymentMethod,
        userId: userId,
      );

      // COGS journal entry — MANDATORY (Dr COGS, Cr Inventory)
      final costCents = await _dao.computeSaleCostCents(id);
      await _journalService.recordSaleCOGSJournalEntry(
        saleId: id,
        costCents: costCents,
        currencyId: currencyId,
        userId: userId,
      );

      // Create commission records for assigned salesperson(s) via the
      // CommissionService (Phase 6 SoT).
      final totalItemCount = items.fold<int>(0, (sum, i) => sum + i.quantity);
      if (employeeId != null) {
        await _commissionService.createForSale(
          saleId: id,
          employeeId: employeeId,
          subtotalCents: subtotalCents.toBigInt().toInt(),
          discountCents: discountCents.toBigInt().toInt(),
          itemCount: totalItemCount,
          currencyId: currencyId,
          saleDate: effectiveSaleDate,
        );
      } else {
        // Per-item salesperson commissions: aggregate subtotal, discount and
        // item count per employee so percentage commission is computed on the
        // post-discount base per salesperson.
        final perEmployeeSubtotals = <int, int>{};
        final perEmployeeDiscounts = <int, int>{};
        final perEmployeeItemCounts = <int, int>{};
        for (final item in items) {
          if (item.employeeId != null) {
            perEmployeeSubtotals[item.employeeId!] =
                (perEmployeeSubtotals[item.employeeId!] ?? 0) +
                    item.subtotalCents.toBigInt().toInt();
            perEmployeeDiscounts[item.employeeId!] =
                (perEmployeeDiscounts[item.employeeId!] ?? 0) +
                    item.discountCents.toBigInt().toInt();
            perEmployeeItemCounts[item.employeeId!] =
                (perEmployeeItemCounts[item.employeeId!] ?? 0) + item.quantity;
          }
        }
        for (final empId in perEmployeeSubtotals.keys) {
          await _commissionService.createForSale(
            saleId: id,
            employeeId: empId,
            subtotalCents: perEmployeeSubtotals[empId]!,
            discountCents: perEmployeeDiscounts[empId] ?? 0,
            itemCount: perEmployeeItemCounts[empId]!,
            currencyId: currencyId,
            saleDate: effectiveSaleDate,
          );
        }
      }

      return id;
    });
        break; // success
      } catch (e) {
        // Retry on UNIQUE constraint violation (concurrent invoice number)
        final isUniqueViolation = e.toString().contains('UNIQUE constraint failed');
        if (isUniqueViolation && attempt < maxRetries) {
          developer.log(
            'Invoice number collision on attempt $attempt, retrying...',
            name: 'SaleRepository',
          );
          continue;
        }
        rethrow;
      }
    }

    // Award loyalty points outside transaction (non-critical) via
    // the LoyaltyPointsService (Phase 6 SoT).
    if (customerId != null) {
      await _loyaltyPointsService.awardForSale(
        customerId: customerId,
        saleId: saleId,
        totalCents: totalCents.toBigInt().toInt(),
      );
    }

    // Audit log outside transaction (non-critical, fire-and-forget)
    _audit.logSaleCreated(
      saleId: saleId,
      totalCents: totalCents.toBigInt().toInt(),
      paymentMethod: paymentMethod,
      customerId: customerId,
      userId: userId,
    );

    // Phase 4 — e-invoice dispatch (fire-and-forget, swallows errors).
    // Outside the accounting tx on purpose: a failed ZATCA/ETA/PEPPOL
    // submission must never roll back a posted sale. The dispatcher
    // records its own artifact row so operators can retry from the UI.
    await _dispatchSaleEInvoice(
      saleId: saleId,
      customerId: customerId,
      currencyId: currencyId,
      subtotalCents: subtotalCents.toBigInt().toInt(),
      taxCents: taxCents.toBigInt().toInt(),
      totalCents: totalCents.toBigInt().toInt(),
      issueDate: effectiveSaleDate,
      items: items,
    );

    return saleId;
  }

  @override
  Future<bool> updateSale({
    required int saleId,
    int? customerId,
    int? employeeId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required Decimal paidAmountCents,
    required String paymentMethod,
    required List<SaleItemInput> items,
    String? notes,
    DateTime? saleDate,
    DateTime? dueDate,
    bool taxInclusiveAtPost = false,
  }) async {
    // Guard: only draft/pending sales can be edited.
    // Posted/voided sales have journal entries that would become stale.
    final existing = await getSaleById(saleId);
    if (existing != null && existing.status != 'draft' && existing.status != 'pending') {
      throw Exception(
        'Cannot edit a ${existing.status} sale. Void it and create a new one instead.',
      );
    }

    // Phase 11.2 — the snapshot is re-stamped on edit because the
    // engine just recomputed the totals; the new triple is the
    // authoritative record of the run that produced this row.
    final saleCompanion = db.SalesCompanion(
      customerId: customerId != null ? Value(customerId) : const Value.absent(),
      employeeId: employeeId != null ? Value(employeeId) : const Value.absent(),
      subtotalCents: Value(subtotalCents),
      taxCents: Value(taxCents),
      discountCents: Value(discountCents),
      totalCents: Value(totalCents),
      paidAmountCents: Value(paidAmountCents),
      currencyId: Value(currencyId),
      paymentMethod: Value(paymentMethod),
      notes: notes != null ? Value(notes) : const Value.absent(),
      saleDate: saleDate != null ? Value(saleDate) : const Value.absent(),
      dueDate: dueDate != null ? Value(dueDate) : const Value.absent(),
    ).withPricingSnapshot(taxInclusive: taxInclusiveAtPost);

    final itemCompanions = items.map((i) => db.SaleItemsCompanion(
          productId: Value(i.productId),
          variantId: i.variantId != null ? Value(i.variantId!) : const Value.absent(),
          employeeId: i.employeeId != null ? Value(i.employeeId!) : const Value.absent(),
          quantity: Value(i.quantity),
          unitPriceCents: Value(i.unitPriceCents),
          subtotalCents: Value(i.subtotalCents),
          discountCents: Value(i.discountCents),
          taxCents: Value(i.taxCents),
          totalCents: Value(i.totalCents),
        )).toList();

    // Resolve userId once before entering the transaction.
    final userId = await _currentUserId();

    // ATOMIC: Wrap journal void → sale update → journal re-create → commission
    // re-create in a single transaction. If any step fails, everything rolls back.
    final ok = await _dao.db.transaction(() async {
      // 1. Void old journal entries
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'sales',
        sourceId: saleId,
        reason: 'Sale updated',
        userId: userId,
      );

      // 2. Update sale data and items
      final updated = await _dao.updateSaleWithItems(saleId, saleCompanion, itemCompanions);

      if (updated) {
        // 3. Re-create journal entries with new amounts
        await _journalService.recordSaleJournalEntry(
          saleId: saleId,
          totalCents: totalCents.toBigInt().toInt(),
          paidAmountCents: paidAmountCents.toBigInt().toInt(),
          currencyId: currencyId,
          taxCents: taxCents.toBigInt().toInt(),
          paymentMethod: paymentMethod,
          userId: userId,
        );

        // 4. Re-create commissions: delete old, create new if employee assigned
        await _commissionService.deleteForSale(saleId);
        final effectiveSaleDate = saleDate ?? DateTime.now();
        final totalItemCount = items.fold<int>(0, (sum, i) => sum + i.quantity);
        if (employeeId != null) {
          await _commissionService.createForSale(
            saleId: saleId,
            employeeId: employeeId,
            subtotalCents: subtotalCents.toBigInt().toInt(),
            discountCents: discountCents.toBigInt().toInt(),
            itemCount: totalItemCount,
            currencyId: currencyId,
            saleDate: effectiveSaleDate,
          );
        } else {
          // Per-item salesperson commissions: aggregate subtotal, discount and
          // item count per employee.
          final perEmployeeSubtotals = <int, int>{};
          final perEmployeeDiscounts = <int, int>{};
          final perEmployeeItemCounts = <int, int>{};
          for (final item in items) {
            if (item.employeeId != null) {
              perEmployeeSubtotals[item.employeeId!] =
                  (perEmployeeSubtotals[item.employeeId!] ?? 0) +
                      item.subtotalCents.toBigInt().toInt();
              perEmployeeDiscounts[item.employeeId!] =
                  (perEmployeeDiscounts[item.employeeId!] ?? 0) +
                      item.discountCents.toBigInt().toInt();
              perEmployeeItemCounts[item.employeeId!] =
                  (perEmployeeItemCounts[item.employeeId!] ?? 0) + item.quantity;
            }
          }
          for (final empId in perEmployeeSubtotals.keys) {
            await _commissionService.createForSale(
              saleId: saleId,
              employeeId: empId,
              subtotalCents: perEmployeeSubtotals[empId]!,
              discountCents: perEmployeeDiscounts[empId] ?? 0,
              itemCount: perEmployeeItemCounts[empId]!,
              currencyId: currencyId,
              saleDate: effectiveSaleDate,
            );
          }
        }
      }

      return updated;
    });

    // Audit log outside transaction (non-critical, must not block sale update)
    if (ok) {
      _audit.log(
        entityType: 'sale',
        entityId: saleId,
        action: 'update',
        newValue: {
          'totalCents': totalCents.toString(),
          'itemCount': items.length,
        },
        userId: userId,
      );
    }

    return ok;
  }

  @override
  Future<void> postSale(int saleId, {bool allowNegativeStock = false}) => 
      _dao.postSale(saleId, allowNegativeStock: allowNegativeStock);

  @override
  Future<void> voidSale(int saleId) async {
    // 2026-05-13 — pre-flight integrity guard. The analyzer is a side-
    // effect-free SoT that surfaces every condition that would corrupt
    // the books if the void went through (entangled adjustment returns,
    // negative-stock projections). On a hard blocker we throw
    // `VoidBlockedByImpactException` carrying the full report so the UI
    // can render an actionable dialog instead of silently producing GL
    // drift like the one diagnosed in `tapix_backup_20260513_121448.db`.
    final report = await VoidImpactAnalyzer(_dao.db).analyzeSaleVoid(saleId);
    if (report.hasBlockers) {
      throw VoidBlockedByImpactException(report);
    }

    // Void journal entries BEFORE voiding the sale (so we can still read the data).
    // This MUST succeed — if it fails the entire void is aborted to prevent GL drift.
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'sales',
      sourceId: saleId,
      reason: 'Sale voided',
      userId: await _currentUserId(),
    );

    // Void commissions linked to this sale
    await _commissionService.deleteForSale(saleId);

    // Reverse loyalty points (earned + redeemed) for this sale
    try {
      final sale = await getSaleById(saleId);
      if (sale != null && sale.customerId != null) {
        await _reverseLoyaltyPointsForSale(saleId, sale.customerId!);
      }
    } catch (_) {
      // Loyalty reversal failure should not block the void
    }

    // 2026-05-13 — pass the journal service so the DAO's cascade-void of
    // linked sale_returns also reverses their JEs (root-cause #3 fix).
    await _dao.voidSale(
      saleId,
      journalEntryService: _journalService,
      userId: await _currentUserId(),
    );
    // Audit: log sale void (CRITICAL)
    _audit.logSaleVoided(saleId: saleId, reason: 'voided', userId: await _currentUserId());
  }

  /// Reverse all loyalty point transactions linked to a sale
  Future<void> _reverseLoyaltyPointsForSale(int saleId, int customerId) async {
    final transactions = await _loyaltyRepository.getPointsTransactions(customerId);

    for (final tx in transactions) {
      if (tx.referenceId == saleId) {
        if (tx.transactionType == 'earn' && tx.referenceType == 'sale') {
          // Points were earned from this sale — deduct them
          final pointsToDeduct = tx.points;
          if (pointsToDeduct > 0) {
            await _loyaltyRepository.redeemPoints(
              customerId: customerId,
              points: pointsToDeduct,
              reason: 'Reversed earned points for voided sale #$saleId',
              referenceId: saleId,
              referenceType: 'sale_void',
            );
          }
        } else if (tx.transactionType == 'redeem' && tx.referenceType == 'sale_redemption') {
          // Points were redeemed during this sale — return them
          final pointsToReturn = tx.points.abs();
          if (pointsToReturn > 0) {
            await _loyaltyRepository.addPoints(
              customerId: customerId,
              points: pointsToReturn,
              source: 'sale_void',
              referenceId: saleId,
              referenceType: 'sale_void',
              description: 'Returned redeemed points for voided sale #$saleId',
            );
          }
        }
      }
    }
  }

  @override
  Future<int> editPostedSale({
    required int originalSaleId,
    int? customerId,
    int? employeeId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required Decimal paidAmountCents,
    required String paymentMethod,
    required List<SaleItemInput> items,
    String? notes,
    DateTime? saleDate,
    DateTime? dueDate,
    bool allowNegativeStock = false,
    bool taxInclusiveAtPost = false,
  }) async {
    // 1. Fetch original sale to validate
    final originalSale = await getSaleById(originalSaleId);
    if (originalSale == null) {
      throw StateError('Sale #$originalSaleId not found');
    }

    // 2. Check accounting period is open for the original sale date
    final txDate = originalSale.saleDate;
    final periodRows = await _dao.db.customSelect(
      '''SELECT id, is_closed FROM accounting_periods
         WHERE start_date <= ? AND end_date >= ?
         ORDER BY start_date DESC LIMIT 1''',
      variables: [
        Variable.withDateTime(txDate),
        Variable.withDateTime(txDate),
      ],
      readsFrom: {_dao.db.accountingPeriods},
    ).get();
    if (periodRows.isNotEmpty && periodRows.first.read<bool>('is_closed')) {
      throw StateError(
        'Cannot edit sale: the accounting period containing this '
        'sale has been closed.',
      );
    }

    // 3. Check if sale has any non-voided returns - cannot edit if returns exist
    final returns = await _dao.db.customSelect(
      'SELECT COUNT(*) as cnt FROM sale_returns WHERE sale_id = ? AND status != ?',
      variables: [
        Variable.withInt(originalSaleId),
        Variable.withString('voided'),
      ],
      readsFrom: {_dao.db.saleReturns},
    ).getSingle();
    if (returns.read<int>('cnt') > 0) {
      throw StateError(
        'Cannot edit sale: it has associated returns. '
        'Void the returns first or create a new sale.',
      );
    }

    final userId = await _currentUserId();

    // 4. Void the original sale (this restores stock and reverses accounting)
    await voidSale(originalSaleId);

    // 5. Create new sale with the edited data
    final newSaleId = await createSale(
      customerId: customerId,
      employeeId: employeeId,
      currencyId: currencyId,
      subtotalCents: subtotalCents,
      discountCents: discountCents,
      taxCents: taxCents,
      totalCents: totalCents,
      paidAmountCents: paidAmountCents,
      paymentMethod: paymentMethod,
      items: items,
      notes: notes != null 
          ? '$notes\n[Edited from ${originalSale.invoiceNumber}]'
          : '[Edited from ${originalSale.invoiceNumber}]',
      saleDate: saleDate ?? originalSale.saleDate,
      dueDate: dueDate,
      allowNegativeStock: allowNegativeStock,
      taxInclusiveAtPost: taxInclusiveAtPost,
    );

    // 6. Audit log
    await _audit.log(
      entityType: 'sale',
      entityId: newSaleId,
      action: 'edit_posted_sale',
      oldValue: {
        'originalSaleId': originalSaleId,
        'originalInvoiceNumber': originalSale.invoiceNumber,
        'originalTotalCents': originalSale.totalCents.toString(),
      },
      newValue: {
        'newSaleId': newSaleId,
        'newTotalCents': totalCents.toString(),
        'itemCount': items.length,
      },
      userId: userId,
    );

    return newSaleId;
  }

  @override
  Future<void> deleteSale(int saleId) async {
    // Void any journal entries BEFORE deleting the sale record.
    // This MUST succeed — if it fails the entire delete is aborted to prevent GL drift.
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'sales',
      sourceId: saleId,
      reason: 'Sale deleted',
      userId: await _currentUserId(),
    );

    // Delete commissions linked to this sale
    await _commissionService.deleteForSale(saleId);

    await _dao.deleteSale(saleId);
  }

  @override
  Stream<List<SaleReturnEntity>> watchAllSaleReturns() =>
      _datasource.watchAllSaleReturns();

  @override
  Future<SaleReturnEntity?> getSaleReturnById(int id) =>
      _datasource.getSaleReturnById(id);

  @override
  Stream<List<SaleReturnItemEntity>> watchSaleReturnItemsWithDetails(int returnId) =>
      _datasource.watchSaleReturnItemsWithDetails(returnId);

  @override
  Stream<List<SaleReturnEntity>> watchSaleReturnsBySale(int saleId) =>
      _datasource.watchSaleReturnsBySale(saleId);

  @override
  Stream<Set<int>> watchSaleIdsWithReturns() =>
      _datasource.watchSaleIdsWithReturns();

  @override
  Future<int> createSaleReturn({
    required int saleId,
    required int currencyId,
    required Decimal subtotalCents,
    required Decimal discountCents,
    required Decimal taxCents,
    required Decimal totalCents,
    required List<SaleReturnItemInput> items,
    String? reason,
    String? dispositionType,
    String? refundMethod,
    DateTime? returnDate,
    DateTime? dueDate,
    String? idempotencyKey,
    bool taxInclusiveAtPost = false,
  }) async {
    final returnNumber = await _datasource.generateSaleReturnNumber();

    // Phase 14.0 — only persist dueDate when refund method is cheque.
    // For cash/credit refunds the column stays NULL so the dashboard
    // reminder cannot accidentally surface a non-cheque refund.
    final effectiveDueDate =
        refundMethod == 'cheque' ? dueDate : null;

    final returnCompanion = db.SaleReturnsCompanion(
      saleId: Value(saleId),
      returnNumber: Value(returnNumber),
      subtotalCents: Value(subtotalCents),
      discountCents: Value(discountCents),
      taxCents: Value(taxCents),
      totalCents: Value(totalCents),
      currencyId: Value(currencyId),
      reason: reason != null ? Value(reason) : const Value.absent(),
      dispositionType: dispositionType != null ? Value(dispositionType) : const Value.absent(),
      refundMethod: refundMethod != null ? Value(refundMethod) : const Value.absent(),
      returnDate: returnDate != null ? Value(returnDate) : Value(DateTime.now()),
      dueDate: Value(effectiveDueDate),
      idempotencyKey: Value(idempotencyKey),
    ).withPricingSnapshot(taxInclusive: taxInclusiveAtPost);

    final itemCompanions = items.map((i) => db.SaleReturnItemsCompanion(
          saleItemId: Value(i.saleItemId),
          quantity: Value(i.quantity),
          subtotalCents: Value(i.subtotalCents),
          discountCents: Value(i.discountCents),
          taxCents: Value(i.taxCents),
          refundCents: Value(i.refundCents),
          reason: i.reason != null ? Value(i.reason!) : const Value.absent(),
        )).toList();

    // ATOMIC: Wrap return creation, stock restoration, journal entries,
    // and commission reversal in a single transaction.
    final userId = await _currentUserId();
    final effectiveReturnDate = returnDate ?? DateTime.now();

    final returnId = await _dao.db.transaction(() async {
      final id = await _dao.createSaleReturn(returnCompanion, itemCompanions);

      // Auto-post return: restore stock immediately
      await _dao.postSaleReturn(id);

      // Create journal entries — MANDATORY.
      // `postingDate` flows through so `ReturnPostingService` enforces
      // the Phase 2.5 fiscal-period guard; `partyId` flows through so
      // the credit-note sub-ledger (Phase 2.3) can auto-issue when the
      // customer takes an on-account refund.
      final sale = await _dao.getSaleById(saleId);
      await _journalService.recordSaleReturnJournalEntry(
        returnId: id,
        totalCents: totalCents.toBigInt().toInt(),
        currencyId: currencyId,
        taxCents: taxCents.toBigInt().toInt(),
        refundMethod: refundMethod ?? 'cash',
        partyId: sale?.customerId,
        userId: userId,
        postingDate: effectiveReturnDate,
      );

      // COGS reversal journal entry — MANDATORY (Dr Inventory, Cr COGS)
      final returnCostCents = await _dao.computeSaleReturnCostCents(id);
      await _journalService.recordSaleReturnCOGSReversalJournalEntry(
        returnId: id,
        costCents: returnCostCents,
        currencyId: currencyId,
        userId: userId,
      );

      // Reverse commission for the returned amount via the
      // CommissionService (Phase 6 SoT). The service requires the
      // original sale's subtotal + total item count so it can prorate
      // against the ORIGINAL commission amount (rate-change safe).
      final returnedItemCount = items.fold<int>(0, (sum, i) => sum + i.quantity);
      final originalSale = await _datasource.getSaleById(saleId);
      final saleSubtotalCents =
          originalSale?.subtotalCents.toBigInt().toInt() ?? 0;
      final originalSaleItems = await _datasource.getSaleItems(saleId);
      final totalSaleItems =
          originalSaleItems.fold<int>(0, (sum, i) => sum + i.quantity);
      await _commissionService.reverseForReturn(
        saleId: saleId,
        saleSubtotalCents: saleSubtotalCents,
        totalSaleItemCount: totalSaleItems,
        returnSubtotalCents: subtotalCents.toBigInt().toInt(),
        returnedItemCount: returnedItemCount,
        currencyId: currencyId,
        returnDate: effectiveReturnDate,
      );

      return id;
    });

    // Reverse loyalty points outside transaction (non-critical) via
    // the LoyaltyPointsService (Phase 6 SoT).
    await _loyaltyPointsService.reverseForReturn(
      saleId: saleId,
      returnId: returnId,
      returnTotalCents: totalCents.toBigInt().toInt(),
    );

    // Audit log outside transaction (non-critical)
    _audit.logSaleReturnCreated(
      returnId: returnId,
      saleId: saleId,
      totalCents: totalCents.toBigInt().toInt(),
      userId: userId,
    );

    // Phase 4 — e-invoice credit-note dispatch (fire-and-forget).
    final sale = await _dao.getSaleById(saleId);
    await _dispatchSaleReturnEInvoice(
      sourceTable: 'sale_returns',
      returnId: returnId,
      customerId: sale?.customerId,
      currencyId: currencyId,
      subtotalCents: subtotalCents.toBigInt().toInt(),
      taxCents: taxCents.toBigInt().toInt(),
      totalCents: totalCents.toBigInt().toInt(),
      issueDate: effectiveReturnDate,
      items: items,
      originalInvoiceNumber: sale?.invoiceNumber,
    );

    return returnId;
  }

  @override
  Future<void> voidSaleReturn(int returnId, {bool allowNegativeStock = false}) async {
    // Void journal entries BEFORE voiding the return.
    // This MUST succeed — if it fails the entire void is aborted to prevent GL drift.
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'sale_returns',
      sourceId: returnId,
      reason: 'Sale return voided',
      userId: await _currentUserId(),
    );

    await _datasource.voidSaleReturn(returnId, allowNegativeStock: allowNegativeStock);
    // Audit: log sale return void (CRITICAL)
    _audit.logVoid(entityType: 'sale_return', entityId: returnId, reason: 'voided', userId: await _currentUserId());
  }

  // ==================== SALE PAYMENTS ====================

  @override
  Stream<List<SalePaymentEntity>> watchSalePayments(int saleId) =>
      _datasource.watchSalePayments(saleId);

  @override
  Future<List<SalePaymentEntity>> getSalePayments(int saleId) =>
      _datasource.getSalePayments(saleId);

  @override
  Future<int> recordPayment({
    required int saleId,
    required Decimal amountCents,
    required int currencyId,
    required String paymentMethod,
    String? reference,
    String? notes,
    DateTime? paymentDate,
  }) async {
    final companion = db.SalePaymentsCompanion(
      saleId: Value(saleId),
      amountCents: Value(amountCents),
      currencyId: Value(currencyId),
      paymentMethod: Value(paymentMethod),
      reference: reference != null ? Value(reference) : const Value.absent(),
      notes: notes != null ? Value(notes) : const Value.absent(),
      paymentDate: paymentDate != null ? Value(paymentDate) : Value(DateTime.now()),
    );
    // ATOMIC: Wrap payment recording (which updates customer balance)
    // and journal entry creation in a single transaction.
    final userId = await _currentUserId();

    final paymentId = await _dao.db.transaction(() async {
      final id = await _datasource.recordPayment(companion);

      // Post journal entry: Dr Cash/Bank, Cr Accounts Receivable
      await _journalService.recordCustomerPaymentJournalEntry(
        paymentId: id,
        amountCents: amountCents.toBigInt().toInt(),
        currencyId: currencyId,
        paymentMethod: paymentMethod,
        userId: userId,
      );

      return id;
    });

    return paymentId;
  }

  @override
  Future<void> deletePayment(int paymentId) async {
    // Void journal entries BEFORE deleting the payment
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'sale_payments',
      sourceId: paymentId,
      reason: 'Sale payment deleted',
      userId: await _currentUserId(),
    );

    await _datasource.deletePayment(paymentId);
  }

  @override
  Future<int> getReturnedQuantity(int saleItemId) =>
      _datasource.getReturnedQuantity(saleItemId);

  @override
  Stream<SaleDashboardStats> watchDashboardStats() =>
      _datasource.watchDashboardStats();

  @override
  Stream<Map<int, List<String>>> watchSaleProductSearchTerms() =>
      _datasource.watchSaleProductSearchTerms();

  @override
  Stream<Map<String, List<String>>> watchSaleReturnProductSearchTerms() =>
      _datasource.watchSaleReturnProductSearchTerms();

  // ==================== PRIVATE HELPERS ====================
  //
  // Phase 6 (May 2026) — commission + loyalty arithmetic has been
  // extracted into `CommissionService` and `LoyaltyPointsService`. The
  // legacy `_createCommissionForSale`, `_reverseCommissionForReturn`,
  // `_awardLoyaltyPointsForSale`, and `_reverseLoyaltyPointsForReturn`
  // helpers that used to live here are GONE. Do not reintroduce them.
  // Any new commission/loyalty math belongs in the corresponding
  // service; this repository stays a pure consumer.

  // ────────────────────────── Phase 4 — e-invoice ──────────────────────────
  //
  // The two helpers below are the ONLY place in this repository that knows
  // anything about e-invoicing. They build an [EInvoiceSubject] snapshot
  // from the freshly-posted sale/return and hand it to the dispatcher.
  // All jurisdiction routing, chain context (ICV/PIH), signing and
  // submission live behind [EInvoiceDispatchService] — keeping the
  // accounting path free of country-specific logic.

  Future<void> _dispatchSaleEInvoice({
    required int saleId,
    int? customerId,
    required int currencyId,
    required int subtotalCents,
    required int taxCents,
    required int totalCents,
    required DateTime issueDate,
    required List<SaleItemInput> items,
  }) async {
    final dispatcher = _einvoiceDispatch;
    if (dispatcher == null) return;
    try {
      final sale = await _dao.getSaleById(saleId);
      final subject = EInvoiceSubject(
        sourceTable: 'sales',
        sourceId: saleId,
        documentNumber: sale?.invoiceNumber ?? 'SALE-$saleId',
        documentType: 'invoice',
        subtotalCents: subtotalCents,
        taxCents: taxCents,
        totalCents: totalCents,
        currencyId: currencyId,
        issueDate: issueDate,
        lines: items
            .map((i) => <String, Object?>{
                  'productId': i.productId,
                  'variantId': i.variantId,
                  'quantity': i.quantity,
                  'unitPriceCents': i.unitPriceCents.toBigInt().toInt(),
                  'discountCents': i.discountCents.toBigInt().toInt(),
                  'taxCents': i.taxCents.toBigInt().toInt(),
                  'totalCents': i.totalCents.toBigInt().toInt(),
                })
            .toList(growable: false),
      );
      await dispatcher.dispatch(subject);
    } catch (e, st) {
      // E-invoicing must NEVER break a posted sale.
      developer.log(
        'E-invoice dispatch failed for sale #$saleId: $e',
        name: 'SaleRepository',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _dispatchSaleReturnEInvoice({
    required String sourceTable,
    required int returnId,
    int? customerId,
    required int currencyId,
    required int subtotalCents,
    required int taxCents,
    required int totalCents,
    required DateTime issueDate,
    required List<SaleReturnItemInput> items,
    String? originalInvoiceNumber,
  }) async {
    final dispatcher = _einvoiceDispatch;
    if (dispatcher == null) return;
    try {
      final subject = EInvoiceSubject(
        sourceTable: sourceTable,
        sourceId: returnId,
        documentNumber: 'CN-$returnId',
        documentType: 'credit_note',
        subtotalCents: subtotalCents,
        taxCents: taxCents,
        totalCents: totalCents,
        currencyId: currencyId,
        issueDate: issueDate,
        lines: items
            .map((i) => <String, Object?>{
                  'saleItemId': i.saleItemId,
                  'quantity': i.quantity,
                  'subtotalCents': i.subtotalCents.toBigInt().toInt(),
                  'discountCents': i.discountCents.toBigInt().toInt(),
                  'taxCents': i.taxCents.toBigInt().toInt(),
                  'refundCents': i.refundCents.toBigInt().toInt(),
                })
            .toList(growable: false),
        originalInvoiceNumber: originalInvoiceNumber,
      );
      await dispatcher.dispatch(subject);
    } catch (e, st) {
      developer.log(
        'E-invoice dispatch failed for return #$returnId: $e',
        name: 'SaleRepository',
        error: e,
        stackTrace: st,
      );
    }
  }
}
