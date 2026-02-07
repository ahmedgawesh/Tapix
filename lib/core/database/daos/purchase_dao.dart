import 'package:decimal/decimal.dart';
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
  final int totalCount;
  final int draftCount;
  final int postedCount;
  final int totalPayableCents;
  final int totalPaidCents;
  final int overdueCount;
  final int returnsCount;

  PurchaseDashboardStats({
    required this.totalCount,
    required this.draftCount,
    required this.postedCount,
    required this.totalPayableCents,
    required this.totalPaidCents,
    required this.overdueCount,
    required this.returnsCount,
  });
}

@DriftAccessor(tables: [Purchases, PurchaseItems, PurchaseReturns, PurchaseReturnItems, PurchasePayments, Suppliers, SupplierTransactions, Products, ProductVariants])
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

  /// Get purchase items with product and variant details
  Future<List<PurchaseItemWithDetails>> getPurchaseItemsWithDetails(int purchaseId) async {
    final query = select(purchaseItems).join([
      innerJoin(products, products.id.equalsExp(purchaseItems.productId)),
      leftOuterJoin(productVariants, productVariants.id.equalsExp(purchaseItems.variantId)),
    ])
      ..where(purchaseItems.purchaseId.equals(purchaseId));

    final rows = await query.get();
    return rows.map((row) {
      return PurchaseItemWithDetails(
        item: row.readTable(purchaseItems),
        product: row.readTable(products),
        variant: row.readTableOrNull(productVariants),
      );
    }).toList();
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

  /// Update a purchase and replace its items
  Future<bool> updatePurchaseWithItems(
    int purchaseId,
    PurchasesCompanion purchase,
    List<PurchaseItemsCompanion> items,
  ) {
    return transaction(() async {
      final updated = await updatePurchase(purchaseId, purchase);
      if (!updated) return false;

      await (delete(purchaseItems)..where((i) => i.purchaseId.equals(purchaseId))).go();

      for (final item in items) {
        final itemWithPurchaseId = item.copyWith(purchaseId: Value(purchaseId));
        await into(purchaseItems).insert(itemWithPurchaseId);
      }

      return true;
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
          final newCostCents = item.unitCostCents.toBigInt().toInt();
          final now = DateTime.now().toIso8601String();
          if (costStrategy == 'weighted_average') {
            // Weighted average: (oldCost * oldQty + newCost * newQty) / (oldQty + newQty)
            final variantRow = await customSelect(
              'SELECT cost_cents, stock_quantity FROM product_variants WHERE id = ?',
              variables: [Variable.withInt(variantId)],
            ).getSingleOrNull();
            if (variantRow != null) {
              final oldCost = variantRow.read<int>('cost_cents');
              // stock_quantity was already incremented above, so subtract to get old qty
              final currentStock = variantRow.read<int>('stock_quantity');
              final oldQty = currentStock - item.quantity;
              if (oldQty + item.quantity > 0) {
                final avgCost = ((oldCost * oldQty) + (newCostCents * item.quantity)) ~/ (oldQty + item.quantity);
                await customStatement(
                  'UPDATE product_variants SET cost_cents = ?, updated_at = ? WHERE id = ?',
                  [avgCost, now, variantId],
                );
              }
            }
          } else {
            // last_cost (default)
            await customStatement(
              'UPDATE product_variants SET cost_cents = ?, updated_at = ? WHERE id = ?',
              [newCostCents, now, variantId],
            );
          }
        }
      }

      // Update purchase status to posted
      await updatePurchaseStatus(purchaseId, 'posted', userId: userId);
    });
  }

  /// Void purchase - reverse stock changes if posted
  /// Validates that reversing stock won't result in negative quantities.
  Future<void> voidPurchase(int purchaseId, {int? userId}) {
    return transaction(() async {
      final purchase = await getPurchaseById(purchaseId);
      if (purchase == null) {
        throw Exception('Purchase not found');
      }
      if (purchase.status == 'voided') {
        throw Exception('Purchase already voided');
      }

      // If posted, reverse stock changes with negative-stock guard
      if (purchase.status == 'posted') {
        final items = await getPurchaseItems(purchaseId);
        for (final item in items) {
          final variantId = item.variantId;
          if (variantId != null) {
            // Check current stock before deducting
            final variantRow = await customSelect(
              'SELECT stock_quantity FROM product_variants WHERE id = ?',
              variables: [Variable.withInt(variantId)],
            ).getSingleOrNull();
            if (variantRow != null) {
              final currentStock = variantRow.read<int>('stock_quantity');
              if (currentStock < item.quantity) {
                throw Exception(
                  'Cannot void: variant #$variantId stock ($currentStock) '
                  'is less than purchased quantity (${item.quantity}). '
                  'Some items may have been sold or returned.',
                );
              }
            }
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
    final allPurchases = await select(purchases).get();

    final draftCount = allPurchases.where((p) => p.status == 'draft' || p.status == 'pending').length;
    final postedCount = allPurchases.where((p) => p.status == 'posted').length;
    final totalCount = allPurchases.where((p) => p.status != 'voided').length;

    // Calculate total payable (total - paid) from non-voided purchases
    int totalPayable = 0;
    int totalPaid = 0;
    int overdueCount = 0;
    final now = DateTime.now();

    for (final p in allPurchases) {
      if (p.status == 'voided') continue;
      final total = p.totalCents.toBigInt().toInt();
      final paid = p.paidAmountCents.toBigInt().toInt();
      totalPayable += total;
      totalPaid += paid;

      // Overdue: posted, not fully paid, past due date
      if (p.status == 'posted' && paid < total && p.dueDate != null) {
        if (p.dueDate!.isBefore(now)) {
          overdueCount++;
        }
      }
    }

    // Returns count
    final returnsCount = await (select(purchaseReturns)).get().then((l) => l.length);

    return PurchaseDashboardStats(
      totalCount: totalCount,
      draftCount: draftCount,
      postedCount: postedCount,
      totalPayableCents: totalPayable - totalPaid,
      totalPaidCents: totalPaid,
      overdueCount: overdueCount,
      returnsCount: returnsCount,
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

  Future<void> updatePurchaseReturnTotals(int returnId) async {
    final totalsRow = await customSelect(
      'SELECT '
      '  COALESCE(SUM((pi.subtotal_cents * pri.quantity) / pi.quantity), 0) AS subtotal, '
      '  COALESCE(SUM((pi.tax_cents * pri.quantity) / pi.quantity), 0) AS tax '
      'FROM purchase_return_items pri '
      'JOIN purchase_items pi ON pi.id = pri.purchase_item_id '
      'WHERE pri.return_id = ?',
      variables: [Variable.withInt(returnId)],
    ).getSingle();

    final subtotalCents = totalsRow.read<int>('subtotal');
    final taxCents = totalsRow.read<int>('tax');

    await customStatement(
      'UPDATE purchase_returns '
      'SET subtotal_cents = ?, tax_cents = ? '
      'WHERE id = ?',
      [subtotalCents, taxCents, returnId],
    );
  }

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

  /// Post purchase return - update variant stock based on disposition
  /// Validates that return quantities don't exceed available (purchased - already returned).
  Future<void> postPurchaseReturn(int returnId, {int? userId}) {
    return transaction(() async {
      final returnData = await getPurchaseReturnById(returnId);
      if (returnData == null) {
        throw Exception('Return not found');
      }
      if (returnData.status == 'posted') {
        throw Exception('Return already posted');
      }

      // Validate return quantities don't exceed available
      final returnItemsQuery = select(purchaseReturnItems).join([
        innerJoin(purchaseItems, purchaseItems.id.equalsExp(purchaseReturnItems.purchaseItemId)),
      ])
        ..where(purchaseReturnItems.returnId.equals(returnId));

      final returnItemRows = await returnItemsQuery.get();
      for (final row in returnItemRows) {
        final returnItem = row.readTable(purchaseReturnItems);
        final purchaseItem = row.readTable(purchaseItems);

        // Check total already returned for this purchase item (excluding voided returns)
        final alreadyReturned = await getReturnedQuantity(purchaseItem.id);
        // Subtract this return's own quantity since it's not yet posted
        final previouslyReturned = alreadyReturned - returnItem.quantity;
        final maxReturnable = purchaseItem.quantity - previouslyReturned;

        if (returnItem.quantity > maxReturnable) {
          throw Exception(
            'Cannot return ${returnItem.quantity} units of item #${purchaseItem.id}. '
            'Only $maxReturnable available (purchased: ${purchaseItem.quantity}, '
            'already returned: $previouslyReturned).',
          );
        }
      }

      // Only deduct stock for restock/refund dispositions (not write_off/repair)
      final shouldDeductStock = returnData.dispositionType == 'restock' ||
          returnData.dispositionType == 'refund' ||
          returnData.dispositionType == 'replace';

      if (shouldDeductStock) {
        for (final row in returnItemRows) {
          final returnItem = row.readTable(purchaseReturnItems);
          final purchaseItem = row.readTable(purchaseItems);
          final variantId = purchaseItem.variantId;
          if (variantId == null) continue;

          // Guard against negative stock
          final variantRow = await customSelect(
            'SELECT stock_quantity FROM product_variants WHERE id = ?',
            variables: [Variable.withInt(variantId)],
          ).getSingleOrNull();
          if (variantRow != null) {
            final currentStock = variantRow.read<int>('stock_quantity');
            if (currentStock < returnItem.quantity) {
              throw Exception(
                'Cannot return: variant #$variantId stock ($currentStock) '
                'is less than return quantity (${returnItem.quantity}).',
              );
            }
          }

          await customStatement(
            'UPDATE product_variants SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
            [returnItem.quantity, DateTime.now().toIso8601String(), variantId],
          );
        }
      }

      // Update return status to posted
      await (update(purchaseReturns)..where((r) => r.id.equals(returnId)))
          .write(const PurchaseReturnsCompanion(status: Value('posted')));

      // Create supplier credit note transaction and adjust balance
      final purchase = await getPurchaseById(returnData.purchaseId);
      if (purchase != null) {
        final refundCents = returnData.totalCents.toBigInt().toInt();

        // Record supplier transaction (credit note)
        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: purchase.supplierId,
            transactionType: 'credit_note',
            amountCents: Decimal.fromInt(-refundCents),
            currencyId: purchase.currencyId,
            description: Value('Purchase return ${returnData.returnNumber}'),
            referenceId: Value(returnId),
            referenceType: const Value('purchase_return'),
          ),
        );

        // Decrease supplier balance (they owe us)
        final supplier = await (select(suppliers)
              ..where((s) => s.id.equals(purchase.supplierId)))
            .getSingleOrNull();
        if (supplier != null) {
          final oldBalance = supplier.balanceCents.toBigInt().toInt();
          final newBalance = oldBalance - refundCents;
          await (update(suppliers)..where((s) => s.id.equals(purchase.supplierId)))
              .write(SuppliersCompanion(
                balanceCents: Value(Decimal.fromInt(newBalance)),
                updatedAt: Value(DateTime.now()),
              ));
        }
      }
    });
  }

  /// Watch purchase return items
  Stream<List<PurchaseReturnItem>> watchPurchaseReturnItems(int returnId) {
    return (select(purchaseReturnItems)..where((i) => i.returnId.equals(returnId))).watch();
  }

  /// Void a purchase return
  Future<void> voidPurchaseReturn(int returnId) {
    return transaction(() async {
      final returnData = await getPurchaseReturnById(returnId);
      if (returnData == null) throw Exception('Return not found');
      if (returnData.status == 'voided') throw Exception('Return already voided');

      // If posted, reverse stock changes
      if (returnData.status == 'posted') {
        final shouldReverseStock = returnData.dispositionType == 'restock' ||
            returnData.dispositionType == 'refund' ||
            returnData.dispositionType == 'replace';

        if (shouldReverseStock) {
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
              'UPDATE product_variants SET stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
              [returnItem.quantity, DateTime.now().toIso8601String(), variantId],
            );
          }
        }
      }

      // Reverse supplier credit note if return was posted
      if (returnData.status == 'posted') {
        final purchase = await getPurchaseById(returnData.purchaseId);
        if (purchase != null) {
          final refundCents = returnData.totalCents.toBigInt().toInt();

          // Record reversal transaction
          await into(supplierTransactions).insert(
            SupplierTransactionsCompanion.insert(
              supplierId: purchase.supplierId,
              transactionType: 'credit_note_reversal',
              amountCents: Decimal.fromInt(refundCents),
              currencyId: purchase.currencyId,
              description: Value('Voided purchase return ${returnData.returnNumber}'),
              referenceId: Value(returnId),
              referenceType: const Value('purchase_return'),
            ),
          );

          // Restore supplier balance
          final supplier = await (select(suppliers)
                ..where((s) => s.id.equals(purchase.supplierId)))
              .getSingleOrNull();
          if (supplier != null) {
            final oldBalance = supplier.balanceCents.toBigInt().toInt();
            final newBalance = oldBalance + refundCents;
            await (update(suppliers)..where((s) => s.id.equals(purchase.supplierId)))
                .write(SuppliersCompanion(
                  balanceCents: Value(Decimal.fromInt(newBalance)),
                  updatedAt: Value(DateTime.now()),
                ));
          }
        }
      }

      await (update(purchaseReturns)..where((r) => r.id.equals(returnId)))
          .write(const PurchaseReturnsCompanion(status: Value('voided')));
    });
  }

  // ==================== PURCHASE PAYMENTS ====================

  /// Watch all payments for a purchase
  Stream<List<PurchasePayment>> watchPurchasePayments(int purchaseId) {
    return (select(purchasePayments)
          ..where((p) => p.purchaseId.equals(purchaseId))
          ..orderBy([(p) => OrderingTerm.desc(p.paymentDate)]))
        .watch();
  }

  /// Get all payments for a purchase
  Future<List<PurchasePayment>> getPurchasePayments(int purchaseId) {
    return (select(purchasePayments)
          ..where((p) => p.purchaseId.equals(purchaseId))
          ..orderBy([(p) => OrderingTerm.desc(p.paymentDate)]))
        .get();
  }

  /// Record a payment for a purchase and update paid_amount_cents
  Future<int> recordPayment(PurchasePaymentsCompanion payment) {
    return transaction(() async {
      final paymentId = await into(purchasePayments).insert(payment);

      // Recalculate total paid
      final payments = await getPurchasePayments(payment.purchaseId.value);
      final totalPaid = payments.fold<int>(
        0, (sum, p) => sum + p.amountCents.toBigInt().toInt(),
      );

      await (update(purchases)..where((p) => p.id.equals(payment.purchaseId.value)))
          .write(PurchasesCompanion(
            paidAmountCents: Value(Decimal.fromInt(totalPaid)),
            updatedAt: Value(DateTime.now()),
          ));

      return paymentId;
    });
  }

  /// Delete a payment and recalculate paid_amount_cents
  Future<void> deletePayment(int paymentId) {
    return transaction(() async {
      final payment = await (select(purchasePayments)..where((p) => p.id.equals(paymentId))).getSingleOrNull();
      if (payment == null) return;

      await (delete(purchasePayments)..where((p) => p.id.equals(paymentId))).go();

      // Recalculate total paid
      final remaining = await getPurchasePayments(payment.purchaseId);
      final totalPaid = remaining.fold<int>(
        0, (sum, p) => sum + p.amountCents.toBigInt().toInt(),
      );

      await (update(purchases)..where((p) => p.id.equals(payment.purchaseId)))
          .write(PurchasesCompanion(
            paidAmountCents: Value(Decimal.fromInt(totalPaid)),
            updatedAt: Value(DateTime.now()),
          ));
    });
  }

  /// Get total already returned quantity for a specific purchase item
  Future<int> getReturnedQuantity(int purchaseItemId) async {
    final rows = await customSelect(
      'SELECT COALESCE(SUM(pri.quantity), 0) as total '
      'FROM purchase_return_items pri '
      'JOIN purchase_returns pr ON pr.id = pri.return_id '
      'WHERE pri.purchase_item_id = ? AND pr.status != ?',
      variables: [Variable.withInt(purchaseItemId), const Variable('voided')],
    ).get();
    return rows.isEmpty ? 0 : rows.first.read<int>('total');
  }
}
