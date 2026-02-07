import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/transactions.dart';
import '../tables/parties.dart';
import '../tables/products.dart';

part 'sale_dao.g.dart';

/// Data class for sale with customer info
class SaleWithCustomer {
  final Sale sale;
  final Customer? customer;

  SaleWithCustomer({required this.sale, this.customer});
}

/// Data class for sale item with product and variant info
class SaleItemWithDetails {
  final SaleItem item;
  final Product product;
  final ProductVariant? variant;

  SaleItemWithDetails({
    required this.item,
    required this.product,
    this.variant,
  });
}

/// Dashboard stats for sales
class SaleDashboardStats {
  final int totalCount;
  final int completedCount;
  final int voidedCount;
  final int totalSalesCents;
  final int returnsCount;
  final int totalReturnsCents;
  final int todaySalesCents;
  final int todayCount;

  SaleDashboardStats({
    required this.totalCount,
    required this.completedCount,
    required this.voidedCount,
    required this.totalSalesCents,
    required this.returnsCount,
    required this.totalReturnsCents,
    required this.todaySalesCents,
    required this.todayCount,
  });
}

@DriftAccessor(tables: [Sales, SaleItems, SaleTaxBands, SaleReturns, SaleReturnItems, Customers, Products, ProductVariants])
class SaleDao extends DatabaseAccessor<AppDatabase> with _$SaleDaoMixin {
  SaleDao(super.db);

  // ==================== SALES ====================

  /// Watch all sales ordered by date descending
  Stream<List<Sale>> watchAllSales() {
    return (select(sales)
          ..orderBy([(s) => OrderingTerm.desc(s.saleDate)]))
        .watch();
  }

  /// Watch all sales with customer info
  Stream<List<SaleWithCustomer>> watchAllSalesWithCustomer() {
    final query = select(sales).join([
      leftOuterJoin(customers, customers.id.equalsExp(sales.customerId)),
    ])
      ..orderBy([OrderingTerm.desc(sales.saleDate)]);

    return query.watch().map((rows) => rows.map((row) {
          return SaleWithCustomer(
            sale: row.readTable(sales),
            customer: row.readTableOrNull(customers),
          );
        }).toList());
  }

  /// Watch a single sale
  Stream<Sale?> watchSale(int id) {
    return (select(sales)..where((s) => s.id.equals(id))).watchSingleOrNull();
  }

  /// Get sale by ID
  Future<Sale?> getSaleById(int id) {
    return (select(sales)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  /// Get sale with customer by ID
  Future<SaleWithCustomer?> getSaleWithCustomerById(int id) async {
    final query = select(sales).join([
      leftOuterJoin(customers, customers.id.equalsExp(sales.customerId)),
    ])
      ..where(sales.id.equals(id));

    final row = await query.getSingleOrNull();
    if (row == null) return null;

    return SaleWithCustomer(
      sale: row.readTable(sales),
      customer: row.readTableOrNull(customers),
    );
  }

  /// Watch sales by customer
  Stream<List<Sale>> watchCustomerSales(int customerId) {
    return (select(sales)
          ..where((s) => s.customerId.equals(customerId))
          ..orderBy([(s) => OrderingTerm.desc(s.saleDate)]))
        .watch();
  }

  /// Watch sales by status
  Stream<List<Sale>> watchSalesByStatus(String status) {
    return (select(sales)
          ..where((s) => s.status.equals(status))
          ..orderBy([(s) => OrderingTerm.desc(s.saleDate)]))
        .watch();
  }

  /// Search sales by invoice number or customer name
  Stream<List<SaleWithCustomer>> searchSales(String query) {
    final searchQuery = '%$query%';
    final joinQuery = select(sales).join([
      leftOuterJoin(customers, customers.id.equalsExp(sales.customerId)),
    ])
      ..where(sales.invoiceNumber.like(searchQuery) |
          customers.name.like(searchQuery))
      ..orderBy([OrderingTerm.desc(sales.saleDate)]);

    return joinQuery.watch().map((rows) => rows.map((row) {
          return SaleWithCustomer(
            sale: row.readTable(sales),
            customer: row.readTableOrNull(customers),
          );
        }).toList());
  }

  /// Get sales by date range
  Future<List<Sale>> getSalesByDateRange(DateTime start, DateTime end) {
    return (select(sales)
          ..where((s) => s.saleDate.isBiggerOrEqualValue(start) & s.saleDate.isSmallerOrEqualValue(end))
          ..orderBy([(s) => OrderingTerm.desc(s.saleDate)]))
        .get();
  }

  /// Generate next invoice number
  Future<String> generateInvoiceNumber() async {
    final now = DateTime.now();
    final prefix = 'INV-${now.year}${now.month.toString().padLeft(2, '0')}';

    final lastSale = await (select(sales)
          ..where((s) => s.invoiceNumber.like('$prefix%'))
          ..orderBy([(s) => OrderingTerm.desc(s.invoiceNumber)])
          ..limit(1))
        .getSingleOrNull();

    int nextNum = 1;
    if (lastSale != null) {
      final lastNum = int.tryParse(lastSale.invoiceNumber.split('-').last) ?? 0;
      nextNum = lastNum + 1;
    }

    return '$prefix-${nextNum.toString().padLeft(4, '0')}';
  }

  /// Create sale with items in a transaction
  Future<int> createSaleWithItems(SalesCompanion sale, List<SaleItemsCompanion> items) {
    return transaction(() async {
      final saleId = await into(sales).insert(sale);

      for (final item in items) {
        final itemWithSaleId = item.copyWith(saleId: Value(saleId));
        await into(saleItems).insert(itemWithSaleId);
      }

      return saleId;
    });
  }

  /// Update sale and replace items
  Future<bool> updateSaleWithItems(
    int saleId,
    SalesCompanion sale,
    List<SaleItemsCompanion> items,
  ) {
    return transaction(() async {
      final updated = await (update(sales)..where((s) => s.id.equals(saleId)))
          .write(sale.copyWith(updatedAt: Value(DateTime.now())))
          .then((rows) => rows > 0);
      if (!updated) return false;

      await (delete(saleItems)..where((i) => i.saleId.equals(saleId))).go();

      for (final item in items) {
        final itemWithSaleId = item.copyWith(saleId: Value(saleId));
        await into(saleItems).insert(itemWithSaleId);
      }

      return true;
    });
  }

  /// Post sale - deduct variant stock
  Future<void> postSale(int saleId) {
    return transaction(() async {
      final sale = await getSaleById(saleId);
      if (sale == null) throw Exception('Sale not found');
      if (sale.status == 'completed') throw Exception('Sale already completed');

      final items = await getSaleItems(saleId);

      for (final item in items) {
        final variantId = item.variantId;
        if (variantId != null) {
          await customStatement(
            'UPDATE product_variants SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
            [item.quantity, DateTime.now().toIso8601String(), variantId],
          );
        }
      }

      await updateSaleStatus(saleId, 'completed');
    });
  }

  /// Void sale - reverse stock if completed (no hard delete)
  Future<void> voidSale(int saleId) {
    return transaction(() async {
      final sale = await getSaleById(saleId);
      if (sale == null) throw Exception('Sale not found');
      if (sale.status == 'voided') throw Exception('Sale already voided');

      if (sale.status == 'completed') {
        final items = await getSaleItems(saleId);
        for (final item in items) {
          final variantId = item.variantId;
          if (variantId != null) {
            await customStatement(
              'UPDATE product_variants SET stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
              [item.quantity, DateTime.now().toIso8601String(), variantId],
            );
          }
        }
      }

      await updateSaleStatus(saleId, 'voided');
    });
  }

  /// Delete sale (only if draft)
  Future<int> deleteSale(int saleId) {
    return transaction(() async {
      final sale = await getSaleById(saleId);
      if (sale == null || (sale.status != 'draft' && sale.status != 'pending')) {
        throw Exception('Cannot delete non-draft sale');
      }
      return (delete(sales)..where((s) => s.id.equals(saleId))).go();
    });
  }

  /// Update sale status
  Future<bool> updateSaleStatus(int saleId, String status) {
    return (update(sales)..where((s) => s.id.equals(saleId)))
        .write(SalesCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now()),
        ))
        .then((rows) => rows > 0);
  }

  // ==================== SALE ITEMS ====================

  /// Watch sale items
  Stream<List<SaleItem>> watchSaleItems(int saleId) {
    return (select(saleItems)..where((i) => i.saleId.equals(saleId))).watch();
  }

  /// Get sale items
  Future<List<SaleItem>> getSaleItems(int saleId) {
    return (select(saleItems)..where((i) => i.saleId.equals(saleId))).get();
  }

  /// Get sale items with product and variant details
  Future<List<SaleItemWithDetails>> getSaleItemsWithDetails(int saleId) async {
    final query = select(saleItems).join([
      innerJoin(products, products.id.equalsExp(saleItems.productId)),
      leftOuterJoin(productVariants, productVariants.id.equalsExp(saleItems.variantId)),
    ])
      ..where(saleItems.saleId.equals(saleId));

    final rows = await query.get();
    return rows.map((row) {
      return SaleItemWithDetails(
        item: row.readTable(saleItems),
        product: row.readTable(products),
        variant: row.readTableOrNull(productVariants),
      );
    }).toList();
  }

  /// Watch sale items with product and variant details
  Stream<List<SaleItemWithDetails>> watchSaleItemsWithDetails(int saleId) {
    final query = select(saleItems).join([
      innerJoin(products, products.id.equalsExp(saleItems.productId)),
      leftOuterJoin(productVariants, productVariants.id.equalsExp(saleItems.variantId)),
    ])
      ..where(saleItems.saleId.equals(saleId));

    return query.watch().map((rows) => rows.map((row) {
          return SaleItemWithDetails(
            item: row.readTable(saleItems),
            product: row.readTable(products),
            variant: row.readTableOrNull(productVariants),
          );
        }).toList());
  }

  // ==================== SALE RETURNS ====================

  /// Watch all sale returns
  Stream<List<SaleReturn>> watchAllSaleReturns() {
    return (select(saleReturns)
          ..orderBy([(r) => OrderingTerm.desc(r.returnDate)]))
        .watch();
  }

  /// Get sale return by ID
  Future<SaleReturn?> getSaleReturnById(int id) {
    return (select(saleReturns)..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  /// Watch return items
  Stream<List<SaleReturnItem>> watchSaleReturnItems(int returnId) {
    return (select(saleReturnItems)..where((i) => i.returnId.equals(returnId))).watch();
  }

  /// Generate next sale return number
  Future<String> generateSaleReturnNumber() async {
    final now = DateTime.now();
    final prefix = 'SR-${now.year}${now.month.toString().padLeft(2, '0')}';

    final lastReturn = await (select(saleReturns)
          ..where((r) => r.returnNumber.like('$prefix%'))
          ..orderBy([(r) => OrderingTerm.desc(r.returnNumber)])
          ..limit(1))
        .getSingleOrNull();

    int nextNum = 1;
    if (lastReturn != null) {
      final lastNum = int.tryParse(lastReturn.returnNumber.split('-').last) ?? 0;
      nextNum = lastNum + 1;
    }

    return '$prefix-${nextNum.toString().padLeft(4, '0')}';
  }

  /// Create sale return with items
  Future<int> createSaleReturn(
    SaleReturnsCompanion returnData,
    List<SaleReturnItemsCompanion> items,
  ) {
    return transaction(() async {
      final returnId = await into(saleReturns).insert(returnData);

      for (final item in items) {
        final itemWithReturnId = item.copyWith(returnId: Value(returnId));
        await into(saleReturnItems).insert(itemWithReturnId);
      }

      return returnId;
    });
  }

  /// Post sale return - restore variant stock
  Future<void> postSaleReturn(int returnId) {
    return transaction(() async {
      final returnData = await getSaleReturnById(returnId);
      if (returnData == null) throw Exception('Return not found');

      final query = select(saleReturnItems).join([
        innerJoin(saleItems, saleItems.id.equalsExp(saleReturnItems.saleItemId)),
      ])
        ..where(saleReturnItems.returnId.equals(returnId));

      final items = await query.get();
      for (final row in items) {
        final returnItem = row.readTable(saleReturnItems);
        final saleItem = row.readTable(saleItems);
        final variantId = saleItem.variantId;
        if (variantId == null) continue;
        await customStatement(
          'UPDATE product_variants SET stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
          [returnItem.quantity, DateTime.now().toIso8601String(), variantId],
        );
      }
    });
  }

  // ==================== DASHBOARD STATS ====================

  /// Get dashboard stats
  Future<SaleDashboardStats> getDashboardStats() async {
    final allSales = await (select(sales)).get();
    final completedSales = allSales.where((s) => s.status == 'completed').toList();
    final voidedSales = allSales.where((s) => s.status == 'voided').toList();

    final totalSalesCents = completedSales.fold<int>(
        0, (sum, s) => sum + s.totalCents.toBigInt().toInt());

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todaySales = completedSales.where((s) =>
        s.saleDate.isAfter(todayStart) || s.saleDate.isAtSameMomentAs(todayStart)).toList();
    final todaySalesCents = todaySales.fold<int>(
        0, (sum, s) => sum + s.totalCents.toBigInt().toInt());

    final allReturns = await (select(saleReturns)).get();
    final totalReturnsCents = allReturns.fold<int>(
        0, (sum, r) => sum + r.totalCents.toBigInt().toInt());

    return SaleDashboardStats(
      totalCount: allSales.length,
      completedCount: completedSales.length,
      voidedCount: voidedSales.length,
      totalSalesCents: totalSalesCents,
      returnsCount: allReturns.length,
      totalReturnsCents: totalReturnsCents,
      todaySalesCents: todaySalesCents,
      todayCount: todaySales.length,
    );
  }

  /// Watch dashboard stats
  Stream<SaleDashboardStats> watchDashboardStats() {
    return watchAllSales().asyncMap((_) => getDashboardStats());
  }
}
