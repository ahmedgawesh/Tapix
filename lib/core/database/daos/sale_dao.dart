import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/transactions.dart';

part 'sale_dao.g.dart';

@DriftAccessor(tables: [Sales, SaleItems, SaleTaxBands, SaleReturns, SaleReturnItems])
class SaleDao extends DatabaseAccessor<AppDatabase> with _$SaleDaoMixin {
  SaleDao(super.db);

  Stream<List<Sale>> watchAllSales() {
    return (select(sales)..orderBy([(s) => OrderingTerm(expression: s.saleDate, mode: OrderingMode.desc)])).watch();
  }

  Stream<Sale?> watchSale(int id) {
    return (select(sales)..where((s) => s.id.equals(id))).watchSingleOrNull();
  }

  Stream<List<Sale>> watchCustomerSales(int customerId) {
    return (select(sales)
          ..where((s) => s.customerId.equals(customerId))
          ..orderBy([(s) => OrderingTerm(expression: s.saleDate, mode: OrderingMode.desc)]))
        .watch();
  }

  Future<int> createSale(SalesCompanion sale) {
    return into(sales).insert(sale);
  }

  Future<int> createSaleItem(SaleItemsCompanion item) {
    return into(saleItems).insert(item);
  }

  Future<int> createSaleTaxBand(SaleTaxBandsCompanion taxBand) {
    return into(saleTaxBands).insert(taxBand);
  }

  Stream<List<SaleItem>> watchSaleItems(int saleId) {
    return (select(saleItems)..where((i) => i.saleId.equals(saleId))).watch();
  }

  Future<List<Sale>> getSalesByDateRange(DateTime start, DateTime end) {
    return (select(sales)
          ..where((s) => s.saleDate.isBiggerOrEqualValue(start) & s.saleDate.isSmallerOrEqualValue(end))
          ..orderBy([(s) => OrderingTerm(expression: s.saleDate, mode: OrderingMode.desc)]))
        .get();
  }
}
