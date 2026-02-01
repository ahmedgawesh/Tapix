import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/transactions.dart';
import '../tables/parties.dart';
import '../tables/products.dart';

part 'purchase_dao.g.dart';

/// Data class for purchase with supplier info
class PurchaseWithSupplier {
  final Purchase purchase;
  final Supplier supplier;

  PurchaseWithSupplier({required this.purchase, required this.supplier});
}

/// Data class for purchase item with product and variant info
class PurchaseItemWithDetails {
  final PurchaseItem item;
  final Product product;
  final ProductVariant? variant;

  PurchaseItemWithDetails({
    required this.item,
    required this.product,
    this.variant,
  });
}

/// Dashboard stats for purchases
class PurchaseDashboardStats {
  final int pendingCount;
  final int draftCount;
  final int totalPayableCents;
  final int overdueCount;

  PurchaseDashboardStats({
    required this.pendingCount,
    required this.draftCount,
    required this.totalPayableCents,
    required this.overdueCount,
  });
}

@DriftAccessor(tables: [Purchases, PurchaseItems, PurchaseReturns, PurchaseReturnItems, Suppliers, Products, ProductVariants])
class PurchaseDao extends DatabaseAccessor<AppDatabase> with _$PurchaseDaoMixin {
  PurchaseDao(super.db);

  // ==================== PURCHASES ====================

  /// Watch all purchases ordered by date descending
  Stream<List<Purchase>> watchAllPurchases() {
    return (select(purchases)
          ..orderBy([(p) => OrderingTerm.desc(p.purchaseDate)]))
        .watch();
  }

  /// Watch all purchases with supplier info
  Stream<List<PurchaseWithSupplier>> watchAllPurchasesWithSupplier() {
    final query = select(purchases).join([
      innerJoin(suppliers, suppliers.id.equalsExp(purchases.supplierId)),
    ])
      ..orderBy([OrderingTerm.desc(purchases.purchaseDate)]);

    return query.watch().map((rows) => rows.map((row) {
          return PurchaseWithSupplier(
            purchase: row.readTable(purchases),
            supplier: row.readTable(suppliers),
          );
        }).toList());
  }

  /// Get purchase by ID
  Future<Purchase?> getPurchaseById(int id) {
    return (select(purchases)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// Get purchase with supplier by ID
  Future<PurchaseWithSupplier?> getPurchaseWithSupplierById(int id) async {
    final query = select(purchases).join([
      innerJoin(suppliers, suppliers.id.equalsExp(purchases.supplierId)),
    ])
      ..where(purchases.id.equals(id));

    final row = await query.getSingleOrNull();
    if (row == null) return null;

    return PurchaseWithSupplier(
      purchase: row.readTable(purchases),
      supplier: row.readTable(suppliers),
    );
  }

  /// Watch purchase items for a purchase
  Stream<List<PurchaseItem>> watchPurchaseItems(int purchaseId) {
    return (select(purchaseItems)..where((i) => i.purchaseId.equals(purchaseId))).watch();
  }

  /// Get purchase items for a purchase
  Future<List<PurchaseItem>> getPurchaseItems(int purchaseId) {
    return (select(purchaseItems)..where((i) => i.purchaseId.equals(purchaseId))).get();
  }

  /// Watch purchase items with product and variant details
  Stream<List<PurchaseItemWithDetails>> watchPurchaseItemsWithDetails(int purchaseId) {
    final query = select(purchaseItems).join([
      innerJoin(products, products.id.equalsExp(purchaseItems.productId)),
      leftOuterJoin(productVariants, productVariants.id.equalsExp(purchaseItems.variantId)),
    ])
      ..where(purchaseItems.purchaseId.equals(purchaseId));

    return query.watch().map((rows) => rows.map((row) {
          return PurchaseItemWithDetails(
            item: row.readTable(purchaseItems),
            product: row.readTable(products),
            variant: row.readTableOrNull(productVariants),
          );
        }).toList());
  }

  /// Generate next purchase number
  Future<String> generatePurchaseNumber() async {
    final now = DateTime.now();
    final prefix = 'PO-${now.year}${now.month.toString().padLeft(2, '0')}';

    final lastPurchase = await (select(purchases)
          ..where((p) => p.purchaseNumber.like('$prefix%'))
          ..orderBy([(p) => OrderingTerm.desc(p.purchaseNumber)])
          ..limit(1))
        .getSingleOrNull();

    int nextNum = 1;
    if (lastPurchase != null) {
      final lastNum = int.tryParse(lastPurchase.purchaseNumber.split('-').last) ?? 0;
      nextNum = lastNum + 1;
    }

    return '$prefix-${nextNum.toString().padLeft(4, '0')}';
  }

  /// Create purchase with items
  Future<int> createPurchase(PurchasesCompanion purchase, List<PurchaseItemsCompanion> items) {
    return transaction(() async {
      final purchaseId = await into(purchases).insert(purchase);

      for (final item in items) {
        final itemWithPurchaseId = item.copyWith(purchaseId: Value(purchaseId));
        await into(purchaseItems).insert(itemWithPurchaseId);
      }

      return purchaseId;
    });
  }

  /// Update purchase
  Future<bool> updatePurchase(int purchaseId, PurchasesCompanion purchase) {
    return (update(purchases)..where((p) => p.id.equals(purchaseId)))
        .write(purchase.copyWith(updatedAt: Value(DateTime.now())))
        .then((rows) => rows > 0);
  }

  /// Update purchase status
  Future<bool> updatePurchaseStatus(int purchaseId, String status, {int? userId}) {
    final companion = PurchasesCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now()),
    );

    return (update(purchases)..where((p) => p.id.equals(purchaseId)))
        .write(companion)
        .then((rows) => rows > 0);
  }

  /// Post purchase - update variant stock quantities and costs
  Future<void> postPurchase(int purchaseId, {int? userId, String costStrategy = 'last_cost'}) {
    return transaction(() async {
      final purchase = await getPurchaseById(purchaseId);
      if (purchase == null) {
        throw Exception('Purchase not found');
      }
      if (purchase.status == 'posted') {
        throw Exception('Purchase already posted');
      }

      final items = await getPurchaseItems(purchaseId);

      for (final item in items) {
        final variantId = item.variantId;
        if (variantId != null) {
          // Increase variant stock
          await customStatement(
            'UPDATE product_variants SET stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
            [item.quantity, DateTime.now().toIso8601String(), variantId],
          );

          // Update cost based on strategy
          if (costStrategy == 'last_cost') {
            await customStatement(
              'UPDATE product_variants SET cost_cents = ?, updated_at = ? WHERE id = ?',
              [item.unitCostCents.toBigInt().toInt(), DateTime.now().toIso8601String(), variantId],
            );
          }
          // TODO: Implement weighted average cost strategy

          // Update quantity received
          await (update(purchaseItems)..where((i) => i.id.equals(item.id)))
              .write(const PurchaseItemsCompanion());
        }
      }

      // Update purchase status to posted
      await updatePurchaseStatus(purchaseId, 'posted', userId: userId);
    });
  }

  /// Void purchase - reverse stock changes if posted
  Future<void> voidPurchase(int purchaseId, {int? userId}) {
    return transaction(() async {
      final purchase = await getPurchaseById(purchaseId);
      if (purchase == null) {
        throw Exception('Purchase not found');
      }
      if (purchase.status == 'voided') {
        throw Exception('Purchase already voided');
      }

      // If posted, reverse stock changes
      if (purchase.status == 'posted') {
        final items = await getPurchaseItems(purchaseId);
        for (final item in items) {
          final variantId = item.variantId;
          if (variantId != null) {
            await customStatement(
              'UPDATE product_variants SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
              [item.quantity, DateTime.now().toIso8601String(), variantId],
            );
          }
        }
      }

      await updatePurchaseStatus(purchaseId, 'voided', userId: userId);
    });
  }

  /// Delete purchase (only if draft)
  Future<int> deletePurchase(int purchaseId) {
    return transaction(() async {
      final purchase = await getPurchaseById(purchaseId);
      if (purchase == null || purchase.status != 'draft') {
        throw Exception('Cannot delete non-draft purchase');
      }

      // Items are deleted by cascade
      return (delete(purchases)..where((p) => p.id.equals(purchaseId))).go();
    });
  }

  /// Watch purchases by status
  Stream<List<Purchase>> watchPurchasesByStatus(String status) {
    return (select(purchases)
          ..where((p) => p.status.equals(status))
          ..orderBy([(p) => OrderingTerm.desc(p.purchaseDate)]))
        .watch();
  }

  /// Watch purchases by supplier
  Stream<List<Purchase>> watchPurchasesBySupplier(int supplierId) {
    return (select(purchases)
          ..where((p) => p.supplierId.equals(supplierId))
          ..orderBy([(p) => OrderingTerm.desc(p.purchaseDate)]))
        .watch();
  }

  /// Search purchases by number or supplier name
  Stream<List<PurchaseWithSupplier>> searchPurchases(String query) {
    final searchQuery = '%$query%';
    final joinQuery = select(purchases).join([
      innerJoin(suppliers, suppliers.id.equalsExp(purchases.supplierId)),
    ])
      ..where(purchases.purchaseNumber.like(searchQuery) |
          suppliers.name.like(searchQuery))
      ..orderBy([OrderingTerm.desc(purchases.purchaseDate)]);

    return joinQuery.watch().map((rows) => rows.map((row) {
          return PurchaseWithSupplier(
            purchase: row.readTable(purchases),
            supplier: row.readTable(suppliers),
          );
        }).toList());
  }

  /// Get dashboard stats
  Future<PurchaseDashboardStats> getDashboardStats() async {
    final draftCount = await (select(purchases)
          ..where((p) => p.status.equals('draft')))
        .get()
        .then((list) => list.length);

    final pendingCount = await (select(purchases)
          ..where((p) => p.status.equals('posted')))
        .get()
        .then((list) => list.length);

    // Calculate total payable from posted purchases
    final postedPurchases = await (select(purchases)
          ..where((p) => p.status.equals('posted')))
        .get();
    final totalPayable = postedPurchases.fold<int>(
        0, (sum, p) => sum + p.totalCents.toBigInt().toInt());

    return PurchaseDashboardStats(
      pendingCount: pendingCount,
      draftCount: draftCount,
      totalPayableCents: totalPayable,
      overdueCount: 0, // TODO: Implement overdue calculation based on expected date
    );
  }

  /// Watch dashboard stats
  Stream<PurchaseDashboardStats> watchDashboardStats() {
    return watchAllPurchases().asyncMap((_) => getDashboardStats());
  }

  // ==================== PURCHASE ITEMS ====================

  /// Add item to purchase
  Future<int> addPurchaseItem(PurchaseItemsCompanion item) {
    return into(purchaseItems).insert(item);
  }

  /// Update purchase item
  Future<bool> updatePurchaseItem(int itemId, PurchaseItemsCompanion item) {
    return (update(purchaseItems)..where((i) => i.id.equals(itemId)))
        .write(item)
        .then((rows) => rows > 0);
  }

  /// Delete purchase item
  Future<int> deletePurchaseItem(int itemId) {
    return (delete(purchaseItems)..where((i) => i.id.equals(itemId))).go();
  }

  /// Get items with expiry dates approaching (within days)
  Stream<List<PurchaseItemWithDetails>> watchExpiringItems(int withinDays) {
    // Current schema doesn't track expiry dates on purchase items.
    // Return empty stream to keep API stable.
    return const Stream.empty();
  }

  // ==================== PURCHASE RETURNS ====================

  /// Watch all purchase returns
  Stream<List<PurchaseReturn>> watchAllPurchaseReturns() {
    return (select(purchaseReturns)
          ..orderBy([(r) => OrderingTerm.desc(r.returnDate)]))
        .watch();
  }

  /// Get purchase return by ID
  Future<PurchaseReturn?> getPurchaseReturnById(int id) {
    return (select(purchaseReturns)..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  /// Generate next return number
  Future<String> generateReturnNumber() async {
    final now = DateTime.now();
    final prefix = 'PR-${now.year}${now.month.toString().padLeft(2, '0')}';

    final lastReturn = await (select(purchaseReturns)
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

  /// Create purchase return with items
  Future<int> createPurchaseReturn(
    PurchaseReturnsCompanion returnData,
    List<PurchaseReturnItemsCompanion> items,
  ) {
    return transaction(() async {
      final returnId = await into(purchaseReturns).insert(returnData);

      for (final item in items) {
        final itemWithReturnId = item.copyWith(returnId: Value(returnId));
        await into(purchaseReturnItems).insert(itemWithReturnId);
      }

      return returnId;
    });
  }

  /// Post purchase return - update variant stock
  Future<void> postPurchaseReturn(int returnId, {int? userId}) {
    return transaction(() async {
      final returnData = await getPurchaseReturnById(returnId);
      if (returnData == null) {
        throw Exception('Return not found');
      }

      final query = select(purchaseReturnItems).join([
        innerJoin(purchaseItems, purchaseItems.id.equalsExp(purchaseReturnItems.purchaseItemId)),
      ])
        ..where(purchaseReturnItems.returnId.equals(returnId));

      final items = await query.get();
      for (final row in items) {
        final returnItem = row.readTable(purchaseReturnItems);
        final purchaseItem = row.readTable(purchaseItems);
        final variantId = purchaseItem.variantId;
        if (variantId == null) continue;
        await customStatement(
          'UPDATE product_variants SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
          [returnItem.quantity, DateTime.now().toIso8601String(), variantId],
        );
      }
    });
  }

  /// Watch purchase return items
  Stream<List<PurchaseReturnItem>> watchPurchaseReturnItems(int returnId) {
    return (select(purchaseReturnItems)..where((i) => i.returnId.equals(returnId))).watch();
  }
}
