import 'dart:async';

import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/sale_dao.dart' hide SaleDashboardStats;
import '../../../../core/database/daos/sale_dao.dart' as dao show SaleDashboardStats;
import '../../../../core/database/daos/adjustment_return_dao.dart';
import '../../domain/entities/sale_entity.dart';
import '../models/sale_model.dart';

abstract class SaleLocalDatasource {
  Stream<List<SaleEntity>> watchAllSales();
  Stream<List<SaleEntity>> watchCustomerSales(int customerId);
  Future<SaleEntity?> getSaleById(int id);
  Future<List<SaleItemEntity>> getSaleItems(int saleId);
  Stream<List<SaleItemEntity>> watchSaleItems(int saleId);
  Future<List<SaleItemEntity>> getSaleItemsWithDetails(int saleId);
  Stream<List<SaleReturnEntity>> watchAllSaleReturns();
  Future<SaleReturnEntity?> getSaleReturnById(int id);
  Stream<List<SaleReturnItemEntity>> watchSaleReturnItemsWithDetails(int returnId);
  Stream<List<SaleReturnEntity>> watchSaleReturnsBySale(int saleId);
  Stream<Set<int>> watchSaleIdsWithReturns();
  Future<void> voidSaleReturn(int returnId, {bool allowNegativeStock = false});
  Stream<List<SalePaymentEntity>> watchSalePayments(int saleId);
  Future<List<SalePaymentEntity>> getSalePayments(int saleId);
  Future<int> recordPayment(db.SalePaymentsCompanion payment);
  Future<void> deletePayment(int paymentId);
  Future<int> getReturnedQuantity(int saleItemId);
  Stream<SaleDashboardStats> watchDashboardStats();
  Stream<Map<int, List<String>>> watchSaleProductSearchTerms();
  Stream<Map<String, List<String>>> watchSaleReturnProductSearchTerms();
  Future<String> generateInvoiceNumber();
  Future<String> generateSaleReturnNumber();
}

class SaleLocalDatasourceImpl implements SaleLocalDatasource {
  final SaleDao _dao;
  final AdjustmentReturnDao _adjDao;

  SaleLocalDatasourceImpl(this._dao, this._adjDao);

  @override
  Stream<List<SaleEntity>> watchAllSales() {
    return _dao.watchAllSalesWithCustomer().map(
      (list) => list.map((swc) => SaleModel.fromDriftWithCustomer(swc)).toList(),
    );
  }

  @override
  Stream<List<SaleEntity>> watchCustomerSales(int customerId) {
    return _dao.watchCustomerSales(customerId).map(
      (list) => list.map((s) => SaleModel.fromDrift(s)).toList(),
    );
  }

  @override
  Future<SaleEntity?> getSaleById(int id) async {
    final swc = await _dao.getSaleWithCustomerById(id);
    if (swc == null) return null;
    return SaleModel.fromDriftWithCustomer(swc);
  }

  @override
  Future<List<SaleItemEntity>> getSaleItems(int saleId) async {
    final items = await _dao.getSaleItems(saleId);
    return items.map((i) => SaleItemModel.fromDrift(i)).toList();
  }

  @override
  Stream<List<SaleItemEntity>> watchSaleItems(int saleId) {
    return _dao.watchSaleItems(saleId).map(
      (items) => items.map((i) => SaleItemModel.fromDrift(i)).toList(),
    );
  }

  @override
  Future<List<SaleItemEntity>> getSaleItemsWithDetails(int saleId) async {
    final details = await _dao.getSaleItemsWithDetails(saleId);
    return details.map((d) => SaleItemModel.fromDriftWithDetails(d)).toList();
  }

  @override
  Stream<List<SaleReturnEntity>> watchAllSaleReturns() {
    List<SaleReturnEntity> lastLinked = [];
    List<SaleReturnEntity> lastAdj = [];

    List<SaleReturnEntity> merge() {
      final merged = <SaleReturnEntity>[...lastLinked, ...lastAdj];
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return merged;
    }

    final controller = StreamController<List<SaleReturnEntity>>.broadcast();
    final sub1 = _dao.watchAllSaleReturnsWithParty().listen((rows) {
      lastLinked = rows.map((r) => SaleReturnModel.fromDriftWithParty(r) as SaleReturnEntity).toList();
      controller.add(merge());
    });
    final sub2 = _adjDao.watchAllSaleAdjReturnsWithParty().listen((rows) {
      lastAdj = rows.map((a) => SaleReturnModel.fromAdjustmentWithParty(a) as SaleReturnEntity).toList();
      controller.add(merge());
    });
    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
      controller.close();
    };
    return controller.stream;
  }

  @override
  Stream<Map<String, List<String>>> watchSaleReturnProductSearchTerms() {
    Map<String, List<String>> lastLinked = {};
    Map<String, List<String>> lastAdj = {};

    final controller = StreamController<Map<String, List<String>>>.broadcast();
    final sub1 = _dao.watchSaleReturnProductSearchTerms().listen((data) {
      lastLinked = data;
      controller.add({...lastLinked, ...lastAdj});
    });
    final sub2 = _adjDao.watchSaleAdjReturnProductSearchTerms().listen((data) {
      lastAdj = data;
      controller.add({...lastLinked, ...lastAdj});
    });
    controller.onCancel = () {
      sub1.cancel();
      sub2.cancel();
      controller.close();
    };
    return controller.stream;
  }

  @override
  Future<SaleReturnEntity?> getSaleReturnById(int id) async {
    final r = await _dao.getSaleReturnById(id);
    if (r == null) return null;
    return SaleReturnModel.fromDrift(r);
  }

  @override
  Stream<List<SaleReturnItemEntity>> watchSaleReturnItemsWithDetails(int returnId) {
    return _dao.watchSaleReturnItemsWithDetails(returnId).map(
      (list) => list.map((d) => SaleReturnItemModel.fromDriftWithDetails(d)).toList(),
    );
  }

  @override
  Stream<List<SaleReturnEntity>> watchSaleReturnsBySale(int saleId) {
    return _dao.watchSaleReturnsBySale(saleId).map(
      (list) => list.map((r) => SaleReturnModel.fromDrift(r)).toList(),
    );
  }

  @override
  Stream<Set<int>> watchSaleIdsWithReturns() => _dao.watchSaleIdsWithReturns();

  @override
  Future<void> voidSaleReturn(int returnId, {bool allowNegativeStock = false}) =>
      _dao.voidSaleReturn(returnId, allowNegativeStock: allowNegativeStock);

  @override
  Stream<List<SalePaymentEntity>> watchSalePayments(int saleId) {
    return _dao.watchSalePayments(saleId).map(
      (list) => list.map((p) => SalePaymentModel.fromDrift(p)).toList(),
    );
  }

  @override
  Future<List<SalePaymentEntity>> getSalePayments(int saleId) async {
    final payments = await _dao.getSalePayments(saleId);
    return payments.map((p) => SalePaymentModel.fromDrift(p)).toList();
  }

  @override
  Future<int> recordPayment(db.SalePaymentsCompanion payment) =>
      _dao.recordPayment(payment);

  @override
  Future<void> deletePayment(int paymentId) => _dao.deletePayment(paymentId);

  @override
  Future<int> getReturnedQuantity(int saleItemId) =>
      _dao.getReturnedQuantity(saleItemId);

  @override
  Stream<SaleDashboardStats> watchDashboardStats() {
    return _dao.watchDashboardStats().map((dao.SaleDashboardStats stats) => SaleDashboardStats(
          totalCount: stats.totalCount,
          completedCount: stats.completedCount,
          voidedCount: stats.voidedCount,
          totalSalesCents: stats.totalSalesCents,
          returnsCount: stats.returnsCount,
          totalReturnsCents: stats.totalReturnsCents,
          todaySalesCents: stats.todaySalesCents,
          todayCount: stats.todayCount,
        ));
  }

  @override
  Stream<Map<int, List<String>>> watchSaleProductSearchTerms() =>
      _dao.watchSaleProductSearchTerms();

  @override
  Future<String> generateInvoiceNumber() => _dao.generateInvoiceNumber();

  @override
  Future<String> generateSaleReturnNumber() => _dao.generateSaleReturnNumber();
}
