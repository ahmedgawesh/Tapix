import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/sale_dao.dart' hide SaleDashboardStats;
import '../../../../core/services/journal_entry_service.dart';
import '../../domain/entities/sale_entity.dart';
import '../../domain/repositories/sale_repository.dart';
import '../datasources/sale_local_datasource.dart';

class SaleRepositoryImpl implements SaleRepository {
  final SaleLocalDatasource _datasource;
  final SaleDao _dao;
  final JournalEntryService _journalService;

  SaleRepositoryImpl(this._datasource, this._dao, this._journalService);

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
          quantity: Value(i.quantity),
          unitPriceCents: Value(i.unitPriceCents),
          subtotalCents: Value(i.subtotalCents),
          discountCents: Value(i.discountCents),
          taxCents: Value(i.taxCents),
          totalCents: Value(i.totalCents),
        )).toList();

    final saleId = await _dao.createSaleWithItems(saleCompanion, itemCompanions);

    // Auto-post: deduct stock immediately for completed sales
    await _dao.postSale(saleId);

    // Create journal entries (best-effort, won't break sale flow)
    await _journalService.recordSaleJournalEntry(
      saleId: saleId,
      totalCents: totalCents.toBigInt().toInt(),
      paidAmountCents: paidAmountCents.toBigInt().toInt(),
      currencyId: currencyId,
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
          quantity: Value(i.quantity),
          unitPriceCents: Value(i.unitPriceCents),
          subtotalCents: Value(i.subtotalCents),
          discountCents: Value(i.discountCents),
          taxCents: Value(i.taxCents),
          totalCents: Value(i.totalCents),
        )).toList();

    return _dao.updateSaleWithItems(saleId, saleCompanion, itemCompanions);
  }

  @override
  Future<void> postSale(int saleId) => _dao.postSale(saleId);

  @override
  Future<void> voidSale(int saleId) => _dao.voidSale(saleId);

  @override
  Future<void> deleteSale(int saleId) async {
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

    final returnId = await _dao.createSaleReturn(returnCompanion, itemCompanions);

    // Auto-post return: restore stock immediately
    await _dao.postSaleReturn(returnId);

    // Create journal entries (best-effort)
    await _journalService.recordSaleReturnJournalEntry(
      returnId: returnId,
      totalCents: totalCents.toBigInt().toInt(),
      currencyId: currencyId,
    );

    return returnId;
  }

  @override
  Future<void> voidSaleReturn(int returnId) => _datasource.voidSaleReturn(returnId);

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
  }) {
    final companion = db.SalePaymentsCompanion(
      saleId: Value(saleId),
      amountCents: Value(amountCents),
      currencyId: Value(currencyId),
      paymentMethod: Value(paymentMethod),
      reference: reference != null ? Value(reference) : const Value.absent(),
      notes: notes != null ? Value(notes) : const Value.absent(),
      paymentDate: paymentDate != null ? Value(paymentDate) : Value(DateTime.now()),
    );
    return _datasource.recordPayment(companion);
  }

  @override
  Future<void> deletePayment(int paymentId) => _datasource.deletePayment(paymentId);

  @override
  Future<int> getReturnedQuantity(int saleItemId) =>
      _datasource.getReturnedQuantity(saleItemId);

  @override
  Stream<SaleDashboardStats> watchDashboardStats() =>
      _datasource.watchDashboardStats();
}
