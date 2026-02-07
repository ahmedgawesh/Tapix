import '../../../../core/database/app_database.dart' as db;
import '../../../../core/database/daos/sale_dao.dart' hide SaleDashboardStats;
import '../../../../core/database/daos/sale_dao.dart' as dao show SaleDashboardStats;
import '../../domain/entities/sale_entity.dart';
import '../models/sale_model.dart';

abstract class SaleLocalDatasource {
  Stream<List<SaleEntity>> watchAllSales();
  Future<SaleEntity?> getSaleById(int id);
  Future<List<SaleItemEntity>> getSaleItems(int saleId);
  Stream<List<SaleItemEntity>> watchSaleItems(int saleId);
  Future<List<SaleItemEntity>> getSaleItemsWithDetails(int saleId);
  Stream<List<SaleReturnEntity>> watchAllSaleReturns();
  Future<void> voidSaleReturn(int returnId);
  Stream<List<SalePaymentEntity>> watchSalePayments(int saleId);
  Future<List<SalePaymentEntity>> getSalePayments(int saleId);
  Future<int> recordPayment(db.SalePaymentsCompanion payment);
  Future<void> deletePayment(int paymentId);
  Future<int> getReturnedQuantity(int saleItemId);
  Stream<SaleDashboardStats> watchDashboardStats();
  Future<String> generateInvoiceNumber();
  Future<String> generateSaleReturnNumber();
}

class SaleLocalDatasourceImpl implements SaleLocalDatasource {
  final SaleDao _dao;

  SaleLocalDatasourceImpl(this._dao);

  @override
  Stream<List<SaleEntity>> watchAllSales() {
    return _dao.watchAllSalesWithCustomer().map(
      (list) => list.map((swc) => SaleModel.fromDriftWithCustomer(swc)).toList(),
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
    return _dao.watchAllSaleReturns().map(
      (list) => list.map((r) => SaleReturnModel.fromDrift(r)).toList(),
    );
  }

  @override
  Future<void> voidSaleReturn(int returnId) => _dao.voidSaleReturn(returnId);

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
  Future<String> generateInvoiceNumber() => _dao.generateInvoiceNumber();

  @override
  Future<String> generateSaleReturnNumber() => _dao.generateSaleReturnNumber();
}
