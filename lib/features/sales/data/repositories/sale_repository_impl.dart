import 'dart:developer' as developer;

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/employee_dao.dart';
import '../../../../core/database/daos/sale_dao.dart' hide SaleDashboardStats;
import '../../../../core/services/audit_log_service.dart';
import '../../../../core/services/journal_entry_service.dart';
import '../../../auth/data/services/session_service.dart';
import '../../../customers/domain/repositories/loyalty_repository.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';
import '../datasources/sale_local_datasource.dart';

class SaleRepositoryImpl implements SaleRepository {
  final SaleLocalDatasource _datasource;
  final SaleDao _dao;
  final EmployeeDao _employeeDao;
  final JournalEntryService _journalService;
  final AuditLogService _audit;
  final SessionService _sessionService;
  final LoyaltyRepository _loyaltyRepository;

  SaleRepositoryImpl(this._datasource, this._dao, this._employeeDao, this._journalService, this._audit, this._sessionService, this._loyaltyRepository);

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
    );

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

      // Create commission records for assigned salesperson(s)
      // Calculate total item count for fixed commission
      final totalItemCount = items.fold<int>(0, (sum, i) => sum + i.quantity);
      if (employeeId != null) {
        await _createCommissionForSale(
          saleId: id,
          employeeId: employeeId,
          subtotalCents: subtotalCents.toBigInt().toInt(),
          itemCount: totalItemCount,
          currencyId: currencyId,
          saleDate: effectiveSaleDate,
        );
      } else {
        // Per-item salesperson commissions: aggregate subtotal and item count per employee
        final perEmployeeSubtotals = <int, int>{};
        final perEmployeeItemCounts = <int, int>{};
        for (final item in items) {
          if (item.employeeId != null) {
            perEmployeeSubtotals[item.employeeId!] =
                (perEmployeeSubtotals[item.employeeId!] ?? 0) +
                    item.subtotalCents.toBigInt().toInt();
            perEmployeeItemCounts[item.employeeId!] =
                (perEmployeeItemCounts[item.employeeId!] ?? 0) + item.quantity;
          }
        }
        for (final empId in perEmployeeSubtotals.keys) {
          await _createCommissionForSale(
            saleId: id,
            employeeId: empId,
            subtotalCents: perEmployeeSubtotals[empId]!,
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

    // Award loyalty points outside transaction (non-critical)
    if (customerId != null) {
      await _awardLoyaltyPointsForSale(
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
  }) async {
    // Guard: only draft/pending sales can be edited.
    // Posted/voided sales have journal entries that would become stale.
    final existing = await getSaleById(saleId);
    if (existing != null && existing.status != 'draft' && existing.status != 'pending') {
      throw Exception(
        'Cannot edit a ${existing.status} sale. Void it and create a new one instead.',
      );
    }

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
    );

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
        await _employeeDao.deleteCommissionsBySaleId(saleId);
        final effectiveSaleDate = saleDate ?? DateTime.now();
        final totalItemCount = items.fold<int>(0, (sum, i) => sum + i.quantity);
        if (employeeId != null) {
          await _createCommissionForSale(
            saleId: saleId,
            employeeId: employeeId,
            subtotalCents: subtotalCents.toBigInt().toInt(),
            itemCount: totalItemCount,
            currencyId: currencyId,
            saleDate: effectiveSaleDate,
          );
        } else {
          // Per-item salesperson commissions: aggregate subtotal and item count per employee
          final perEmployeeSubtotals = <int, int>{};
          final perEmployeeItemCounts = <int, int>{};
          for (final item in items) {
            if (item.employeeId != null) {
              perEmployeeSubtotals[item.employeeId!] =
                  (perEmployeeSubtotals[item.employeeId!] ?? 0) +
                      item.subtotalCents.toBigInt().toInt();
              perEmployeeItemCounts[item.employeeId!] =
                  (perEmployeeItemCounts[item.employeeId!] ?? 0) + item.quantity;
            }
          }
          for (final empId in perEmployeeSubtotals.keys) {
            await _createCommissionForSale(
              saleId: saleId,
              employeeId: empId,
              subtotalCents: perEmployeeSubtotals[empId]!,
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
    // Void journal entries BEFORE voiding the sale (so we can still read the data).
    // This MUST succeed — if it fails the entire void is aborted to prevent GL drift.
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'sales',
      sourceId: saleId,
      reason: 'Sale voided',
      userId: await _currentUserId(),
    );

    // Void commissions linked to this sale
    await _employeeDao.deleteCommissionsBySaleId(saleId);

    await _dao.voidSale(saleId);
    // Audit: log sale void (CRITICAL)
    _audit.logSaleVoided(saleId: saleId, reason: 'voided', userId: await _currentUserId());
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
    await _employeeDao.deleteCommissionsBySaleId(saleId);

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
  }) async {
    final returnNumber = await _datasource.generateSaleReturnNumber();

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
    );

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

      // Create journal entries — MANDATORY
      await _journalService.recordSaleReturnJournalEntry(
        returnId: id,
        totalCents: totalCents.toBigInt().toInt(),
        currencyId: currencyId,
        taxCents: taxCents.toBigInt().toInt(),
        refundMethod: refundMethod ?? 'cash',
        userId: userId,
      );

      // COGS reversal journal entry — MANDATORY (Dr Inventory, Cr COGS)
      final returnCostCents = await _dao.computeSaleReturnCostCents(id);
      await _journalService.recordSaleReturnCOGSReversalJournalEntry(
        returnId: id,
        costCents: returnCostCents,
        currencyId: currencyId,
        userId: userId,
      );

      // Reverse commission for the returned amount
      final returnedItemCount = items.fold<int>(0, (sum, i) => sum + i.quantity);
      await _reverseCommissionForReturn(
        saleId: saleId,
        returnSubtotalCents: subtotalCents.toBigInt().toInt(),
        returnedItemCount: returnedItemCount,
        currencyId: currencyId,
        returnDate: effectiveReturnDate,
      );

      return id;
    });

    // Reverse loyalty points outside transaction (non-critical)
    await _reverseLoyaltyPointsForReturn(
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

    return returnId;
  }

  @override
  Future<void> voidSaleReturn(int returnId) async {
    // Void journal entries BEFORE voiding the return.
    // This MUST succeed — if it fails the entire void is aborted to prevent GL drift.
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'sale_returns',
      sourceId: returnId,
      reason: 'Sale return voided',
      userId: await _currentUserId(),
    );

    await _datasource.voidSaleReturn(returnId);
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

  // ==================== PRIVATE HELPERS ====================

  /// Reverse (deduct) commission when a sale return is created.
  ///
  /// Reverses commissions for a sale return by looking up original positive
  /// commission records for this sale and creating proportional negative entries.
  ///
  /// This handles both invoice-level and per-item salesperson commissions.
  /// - For percentage commissions: reversal ratio = returnSubtotalCents / saleSubtotalCents
  /// - For fixed commissions: reversal = fixedCommissionCents * returnedItemCount
  Future<void> _reverseCommissionForReturn({
    required int saleId,
    required int returnSubtotalCents,
    required int returnedItemCount,
    required int currencyId,
    required DateTime returnDate,
  }) async {
    final sale = await _datasource.getSaleById(saleId);
    if (sale == null) return;

    final saleSubtotalCents = sale.subtotalCents.toBigInt().toInt();
    if (saleSubtotalCents <= 0) return;

    // Find all positive (original) commissions for this sale
    final commissions = await _employeeDao.getCommissionsBySaleId(saleId);
    if (commissions.isEmpty) return;

    final period =
        '${returnDate.year}-${returnDate.month.toString().padLeft(2, '0')}';

    for (final c in commissions) {
      final originalAmount = c.commissionAmountCents.toBigInt().toInt();
      if (originalAmount <= 0) continue; // skip already-reversed entries

      int deduction;
      final employee = await _employeeDao.getEmployee(c.employeeId);
      
      if (employee != null && employee.commissionType == 'fixed') {
        // Fixed commission: deduct based on returned item count
        final fixedCents = employee.fixedCommissionCents?.toBigInt().toInt() ?? 0;
        deduction = fixedCents * returnedItemCount;
      } else {
        // Percentage commission: proportional reversal based on subtotal
        if (saleSubtotalCents <= 0) continue;
        deduction = (originalAmount * returnSubtotalCents) ~/ saleSubtotalCents;
      }
      
      if (deduction <= 0) continue;

      final companion = db.CommissionsCompanion(
        employeeId: Value(c.employeeId),
        saleId: Value(saleId),
        commissionRateBps: Value(c.commissionRateBps),
        commissionAmountCents: Value(Decimal.fromInt(-deduction)),
        currencyId: Value(currencyId),
        period: Value(period),
        status: const Value('pending'),
        createdAt: Value(DateTime.now()),
      );

      await _employeeDao.createCommission(companion);
    }
  }

  /// Create a commission record for the assigned salesperson on a sale.
  ///
  /// Supports two commission types:
  /// - **percentage**: commissionAmountCents = (subtotalCents * rateBps) / 10000
  ///   Note: Uses subtotalCents (before tax) for percentage calculation
  /// - **fixed**: commissionAmountCents = fixedCommissionCents * itemCount (per item)
  ///
  /// The period is derived from the sale date (YYYY-MM).
  Future<void> _createCommissionForSale({
    required int saleId,
    required int employeeId,
    required int subtotalCents,
    required int itemCount,
    required int currencyId,
    required DateTime saleDate,
  }) async {
    final employee = await _employeeDao.getEmployee(employeeId);
    if (employee == null) return;

    int commissionAmountCents;
    int rateBps;

    if (employee.commissionType == 'fixed') {
      // Fixed commission per item (multiply by item count)
      final fixedCents = employee.fixedCommissionCents?.toBigInt().toInt() ?? 0;
      if (fixedCents <= 0) return;
      commissionAmountCents = fixedCents * itemCount;
      rateBps = 0; // Not applicable for fixed
    } else {
      // Percentage commission on subtotal (before tax)
      rateBps = employee.defaultCommissionRateBps;
      if (rateBps <= 0) return;
      commissionAmountCents = (subtotalCents * rateBps) ~/ 10000;
      if (commissionAmountCents <= 0) return;
    }

    final period =
        '${saleDate.year}-${saleDate.month.toString().padLeft(2, '0')}';

    final companion = db.CommissionsCompanion(
      employeeId: Value(employeeId),
      saleId: Value(saleId),
      commissionRateBps: Value(rateBps.toDouble()),
      commissionAmountCents: Value(Decimal.fromInt(commissionAmountCents)),
      currencyId: Value(currencyId),
      period: Value(period),
      status: const Value('pending'),
      createdAt: Value(DateTime.now()),
    );

    await _employeeDao.createCommission(companion);
  }

  /// Award loyalty points to a customer after a sale.
  ///
  /// Uses LoyaltySettings to determine:
  /// - Whether loyalty is enabled
  /// - Points per currency unit
  /// - Minimum spend threshold
  /// - Customer tier multiplier
  Future<void> _awardLoyaltyPointsForSale({
    required int customerId,
    required int saleId,
    required int totalCents,
  }) async {
    try {
      developer.log(
        'Loyalty: Attempting to award points for sale #$saleId, customer=$customerId, totalCents=$totalCents',
        name: 'SaleRepository',
      );

      final settings = await _loyaltyRepository.getLoyaltySettings();
      if (settings == null) {
        developer.log('Loyalty: No settings found — skipping', name: 'SaleRepository');
        return;
      }
      if (!settings.isEnabled) {
        developer.log('Loyalty: Program disabled — skipping', name: 'SaleRepository');
        return;
      }

      // Check minimum spend threshold (stored in cents)
      if (totalCents < settings.minSpendForPoints) {
        developer.log(
          'Loyalty: totalCents=$totalCents < minSpend=${settings.minSpendForPoints} — skipping',
          name: 'SaleRepository',
        );
        return;
      }

      // Get customer tier and its benefits
      final summary = await _loyaltyRepository.getCustomerLoyaltySummary(customerId);
      final tier = summary?.currentTier;
      final multiplier = tier?.pointsMultiplier ?? 1.0;
      final bonusPercent = tier?.discountPercent ?? 0.0; // Bonus points percentage

      // Calculate points: (totalCents / 100) * pointsPerCurrencyUnit * multiplier
      final pointsPerUnit = settings.pointsPerCurrencyUnit;
      final basePoints = (totalCents * pointsPerUnit) ~/ 100;
      var points = (basePoints * multiplier).round();
      
      // Add bonus points (discountPercent is now bonus points percentage)
      if (bonusPercent > 0) {
        final bonusPoints = (points * bonusPercent / 100).round();
        points += bonusPoints;
      }
      
      // Check for business birthday bonus (company anniversary)
      if (tier != null && tier.birthdayBonus && settings.businessBirthdayDate != null) {
        final today = DateTime.now();
        final businessBirthday = settings.businessBirthdayDate!;
        // Check if today is the business birthday (same month and day)
        if (today.month == businessBirthday.month && today.day == businessBirthday.day) {
          // Add birthday bonus points
          if (tier.birthdayBonusPoints > 0) {
            points += tier.birthdayBonusPoints;
          }
          // Add birthday discount as bonus points
          if (tier.birthdayDiscountPercent > 0) {
            final birthdayBonusPoints = (points * tier.birthdayDiscountPercent / 100).round();
            points += birthdayBonusPoints;
          }
        }
      }

      developer.log(
        'Loyalty: pointsPerUnit=$pointsPerUnit, basePoints=$basePoints, multiplier=$multiplier, bonusPercent=$bonusPercent, finalPoints=$points',
        name: 'SaleRepository',
      );

      if (points <= 0) {
        developer.log('Loyalty: points=$points <= 0 — skipping', name: 'SaleRepository');
        return;
      }

      await _loyaltyRepository.addPoints(
        customerId: customerId,
        points: points,
        source: 'sale',
        referenceId: saleId,
        referenceType: 'sale',
        description: 'Points earned from sale #$saleId',
      );
      developer.log('Loyalty: Successfully awarded $points points', name: 'SaleRepository');

      // STRICT RULE: Loyalty earn journal entry fires at sale completion.
      // Dr Discounts Given (5500), Cr Loyalty Points Liability (2300)
      final pointValueCents = settings.pointValueCents;
      final earnValueCents = points * pointValueCents;
      if (earnValueCents > 0) {
        final customer = await _dao.db.customerDao.getCustomer(customerId);
        final currencyId = customer?.currencyId ?? 1;
        await _journalService.recordLoyaltyEarnJournalEntry(
          saleId: saleId,
          valueCents: earnValueCents,
          currencyId: currencyId,
        );
      }
    } catch (e, st) {
      developer.log(
        'Warning: Failed to award loyalty points for sale #$saleId: $e\n$st',
        name: 'SaleRepository',
      );
    }
  }

  /// Reverse loyalty points when a sale return is created.
  ///
  /// Calculates proportional points to deduct based on return amount vs
  /// original sale amount, then redeems those points.
  Future<void> _reverseLoyaltyPointsForReturn({
    required int saleId,
    required int returnId,
    required int returnTotalCents,
  }) async {
    try {
      final sale = await _datasource.getSaleById(saleId);
      if (sale == null || sale.customerId == null) return;

      final settings = await _loyaltyRepository.getLoyaltySettings();
      if (settings == null || !settings.isEnabled) return;

      final saleTotalCents = sale.totalCents.toBigInt().toInt();
      if (saleTotalCents <= 0) return;

      // Get customer tier multiplier (use current tier)
      final summary = await _loyaltyRepository.getCustomerLoyaltySummary(sale.customerId!);
      final multiplier = summary?.currentTier?.pointsMultiplier ?? 1.0;

      // Calculate original points that were earned for the full sale
      final pointsPerUnit = settings.pointsPerCurrencyUnit;
      final originalBasePoints = (saleTotalCents * pointsPerUnit) ~/ 100;
      final originalPoints = (originalBasePoints * multiplier).round();

      if (originalPoints <= 0) return;

      // Proportional deduction
      if (saleTotalCents <= 0) return;
      final pointsToDeduct = (originalPoints * returnTotalCents) ~/ saleTotalCents;
      if (pointsToDeduct <= 0) return;

      // Only deduct if customer has enough points; otherwise deduct what's available
      final currentBalance = summary?.pointsBalance ?? 0;
      final actualDeduction = pointsToDeduct > currentBalance ? currentBalance : pointsToDeduct;
      if (actualDeduction <= 0) return;

      await _loyaltyRepository.redeemPoints(
        customerId: sale.customerId!,
        points: actualDeduction,
        reason: 'Points reversed for return #$returnId on sale #$saleId',
        referenceId: returnId,
        referenceType: 'sale_return',
      );
    } catch (e) {
      developer.log(
        'Warning: Failed to reverse loyalty points for return #$returnId: $e',
        name: 'SaleRepository',
      );
    }
  }
}
