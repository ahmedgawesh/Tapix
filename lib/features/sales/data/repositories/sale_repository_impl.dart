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
  }) async {
    final invoiceNumber = await _datasource.generateInvoiceNumber();

    final saleCompanion = db.SalesCompanion(
      invoiceNumber: Value(invoiceNumber),
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

    final saleId = await _dao.db.transaction(() async {
      final id = await _dao.createSaleWithItems(saleCompanion, itemCompanions);

      // Auto-post: deduct stock and update customer balance
      await _dao.postSale(id);

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

      // Create commission records for assigned salesperson(s)
      if (employeeId != null) {
        await _createCommissionForSale(
          saleId: id,
          employeeId: employeeId,
          totalCents: totalCents.toBigInt().toInt(),
          currencyId: currencyId,
          saleDate: effectiveSaleDate,
        );
      } else {
        final perEmployeeTotals = <int, int>{};
        for (final item in items) {
          if (item.employeeId != null) {
            perEmployeeTotals[item.employeeId!] =
                (perEmployeeTotals[item.employeeId!] ?? 0) +
                    item.totalCents.toBigInt().toInt();
          }
        }
        for (final entry in perEmployeeTotals.entries) {
          await _createCommissionForSale(
            saleId: id,
            employeeId: entry.key,
            totalCents: entry.value,
            currencyId: currencyId,
            saleDate: effectiveSaleDate,
          );
        }
      }

      return id;
    });

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

    // Void old journal entries BEFORE updating the sale record
    await _journalService.voidJournalEntriesForSource(
      sourceTable: 'sales',
      sourceId: saleId,
      reason: 'Sale updated',
      userId: await _currentUserId(),
    );

    final ok = await _dao.updateSaleWithItems(saleId, saleCompanion, itemCompanions);

    if (ok) {
      // Re-create journal entries with new amounts
      await _journalService.recordSaleJournalEntry(
        saleId: saleId,
        totalCents: totalCents.toBigInt().toInt(),
        paidAmountCents: paidAmountCents.toBigInt().toInt(),
        currencyId: currencyId,
        taxCents: taxCents.toBigInt().toInt(),
        paymentMethod: paymentMethod,
        userId: await _currentUserId(),
      );

      // Audit: log sale update
      _audit.log(
        entityType: 'sale',
        entityId: saleId,
        action: 'update',
        newValue: {
          'totalCents': totalCents.toString(),
          'itemCount': items.length,
        },
        userId: await _currentUserId(),
      );

      // Re-create commission: delete old, create new if employee assigned
      await _employeeDao.deleteCommissionsBySaleId(saleId);
      final effectiveSaleDate = saleDate ?? DateTime.now();
      if (employeeId != null) {
        await _createCommissionForSale(
          saleId: saleId,
          employeeId: employeeId,
          totalCents: totalCents.toBigInt().toInt(),
          currencyId: currencyId,
          saleDate: effectiveSaleDate,
        );
      } else {
        // Per-item salesperson commissions
        final perEmployeeTotals = <int, int>{};
        for (final item in items) {
          if (item.employeeId != null) {
            perEmployeeTotals[item.employeeId!] =
                (perEmployeeTotals[item.employeeId!] ?? 0) +
                    item.totalCents.toBigInt().toInt();
          }
        }
        for (final entry in perEmployeeTotals.entries) {
          await _createCommissionForSale(
            saleId: saleId,
            employeeId: entry.key,
            totalCents: entry.value,
            currencyId: currencyId,
            saleDate: effectiveSaleDate,
          );
        }
      }
    }

    return ok;
  }

  @override
  Future<void> postSale(int saleId) => _dao.postSale(saleId);

  @override
  Future<void> voidSale(int saleId) async {
    // Void journal entries BEFORE voiding the sale (so we can still read the data)
    try {
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'sales',
        sourceId: saleId,
        reason: 'Sale voided',
        userId: await _currentUserId(),
      );
    } catch (e) {
      developer.log('Warning: Failed to void journal entries for sale #$saleId: $e',
          name: 'SaleRepository');
    }

    // Void commissions linked to this sale
    await _employeeDao.deleteCommissionsBySaleId(saleId);

    await _dao.voidSale(saleId);
    // Audit: log sale void (CRITICAL)
    _audit.logSaleVoided(saleId: saleId, reason: 'voided', userId: await _currentUserId());
  }

  @override
  Future<void> deleteSale(int saleId) async {
    // Void any journal entries BEFORE deleting the sale record
    try {
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'sales',
        sourceId: saleId,
        reason: 'Sale deleted',
        userId: await _currentUserId(),
      );
    } catch (e) {
      developer.log('Warning: Failed to void journal entries for sale #$saleId: $e',
          name: 'SaleRepository');
    }

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

      // Reverse commission for the returned amount
      await _reverseCommissionForReturn(
        saleId: saleId,
        returnTotalCents: totalCents.toBigInt().toInt(),
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
    // Void journal entries BEFORE voiding the return
    try {
      await _journalService.voidJournalEntriesForSource(
        sourceTable: 'sale_returns',
        sourceId: returnId,
        reason: 'Sale return voided',
        userId: await _currentUserId(),
      );
    } catch (e) {
      developer.log('Warning: Failed to void journal entries for sale return #$returnId: $e',
          name: 'SaleRepository');
    }

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
  /// The reversal ratio = returnTotalCents / saleTotalCents.
  Future<void> _reverseCommissionForReturn({
    required int saleId,
    required int returnTotalCents,
    required int currencyId,
    required DateTime returnDate,
  }) async {
    final sale = await _datasource.getSaleById(saleId);
    if (sale == null) return;

    final saleTotalCents = sale.totalCents.toBigInt().toInt();
    if (saleTotalCents <= 0) return;

    // Find all positive (original) commissions for this sale
    final commissions = await _employeeDao.getCommissionsBySaleId(saleId);
    if (commissions.isEmpty) return;

    final period =
        '${returnDate.year}-${returnDate.month.toString().padLeft(2, '0')}';

    for (final c in commissions) {
      final originalAmount = c.commissionAmountCents.toBigInt().toInt();
      if (originalAmount <= 0) continue; // skip already-reversed entries

      // Proportional reversal: if partial return, reverse proportionally
      final deduction = (originalAmount * returnTotalCents) ~/ saleTotalCents;
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
  /// - **percentage**: commissionAmountCents = (totalCents * rateBps) / 10000
  /// - **fixed**: commissionAmountCents = fixedCommissionCents (per sale)
  ///
  /// The period is derived from the sale date (YYYY-MM).
  Future<void> _createCommissionForSale({
    required int saleId,
    required int employeeId,
    required int totalCents,
    required int currencyId,
    required DateTime saleDate,
  }) async {
    final employee = await _employeeDao.getEmployee(employeeId);
    if (employee == null) return;

    int commissionAmountCents;
    int rateBps;

    if (employee.commissionType == 'fixed') {
      // Fixed commission per sale
      final fixedCents = employee.fixedCommissionCents?.toBigInt().toInt() ?? 0;
      if (fixedCents <= 0) return;
      commissionAmountCents = fixedCents;
      rateBps = 0; // Not applicable for fixed
    } else {
      // Percentage commission
      rateBps = employee.defaultCommissionRateBps;
      if (rateBps <= 0) return;
      commissionAmountCents = (totalCents * rateBps) ~/ 10000;
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

      // Get customer tier multiplier
      final summary = await _loyaltyRepository.getCustomerLoyaltySummary(customerId);
      final multiplier = summary?.currentTier?.pointsMultiplier ?? 1.0;

      // Calculate points: (totalCents / 100) * pointsPerCurrencyUnit * multiplier
      final pointsPerUnit = settings.pointsPerCurrencyUnit;
      final basePoints = (totalCents * pointsPerUnit) ~/ 100;
      final points = (basePoints * multiplier).round();

      developer.log(
        'Loyalty: pointsPerUnit=$pointsPerUnit, basePoints=$basePoints, multiplier=$multiplier, points=$points',
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
