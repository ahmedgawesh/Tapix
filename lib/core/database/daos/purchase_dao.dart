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

/// Data class for purchase return item with full product details
class PurchaseReturnItemWithDetails {
  final PurchaseReturnItem returnItem;
  final Product product;
  final ProductVariant? variant;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;

  PurchaseReturnItemWithDetails({
    required this.returnItem,
    required this.product,
    this.variant,
    this.colorName,
    this.colorHex,
    this.sizeName,
  });
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

      // Track which products were affected so we can sync them afterwards
      final affectedProductIds = <int>{};
      // Check if the purchase has any tax (to update product taxable flag)
      final purchaseTaxCents = purchase.taxCents.toBigInt().toInt();

      for (final item in items) {
        final variantId = item.variantId;
        final productId = item.productId;
        affectedProductIds.add(productId);
        final newCostCents = item.unitCostCents.toBigInt().toInt();
        final now = DateTime.now().toIso8601String();
        if (variantId != null) {
          // Increase variant stock
          await customUpdate(
            'UPDATE product_variants SET stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
            variables: [Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(variantId)],
            updates: {productVariants},
            updateKind: UpdateKind.update,
          );

          // Update cost based on strategy
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
                await customUpdate(
                  'UPDATE product_variants SET cost_cents = ?, updated_at = ? WHERE id = ?',
                  variables: [Variable.withInt(avgCost), Variable.withString(now), Variable.withInt(variantId)],
                  updates: {productVariants},
                  updateKind: UpdateKind.update,
                );
              }
            }
          } else {
            // last_cost (default)
            await customUpdate(
              'UPDATE product_variants SET cost_cents = ?, updated_at = ? WHERE id = ?',
              variables: [Variable.withInt(newCostCents), Variable.withString(now), Variable.withInt(variantId)],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          }
        } else {
          // Non-variant product: update the products table directly
          if (costStrategy == 'weighted_average') {
            final productRow = await customSelect(
              'SELECT cost_cents, stock_quantity FROM products WHERE id = ?',
              variables: [Variable.withInt(productId)],
            ).getSingleOrNull();
            if (productRow != null) {
              final oldCost = productRow.read<int>('cost_cents');
              final oldQty = productRow.read<int>('stock_quantity');
              if (oldQty + item.quantity > 0) {
                final avgCost = ((oldCost * oldQty) + (newCostCents * item.quantity)) ~/ (oldQty + item.quantity);
                await customUpdate(
                  'UPDATE products SET cost_cents = ?, stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
                  variables: [Variable.withInt(avgCost), Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(productId)],
                  updates: {products},
                  updateKind: UpdateKind.update,
                );
              } else {
                await customUpdate(
                  'UPDATE products SET cost_cents = ?, stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
                  variables: [Variable.withInt(newCostCents), Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(productId)],
                  updates: {products},
                  updateKind: UpdateKind.update,
                );
              }
            }
          } else {
            // last_cost (default)
            await customUpdate(
              'UPDATE products SET cost_cents = ?, stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
              variables: [Variable.withInt(newCostCents), Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(productId)],
              updates: {products},
              updateKind: UpdateKind.update,
            );
          }

          // Also sync the default variant if one exists
          await customUpdate(
            'UPDATE product_variants SET cost_cents = ?, stock_quantity = stock_quantity + ?, updated_at = ? '
            'WHERE product_id = ? AND color_id IS NULL AND size_id IS NULL',
            variables: [Variable.withInt(newCostCents), Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(productId)],
            updates: {productVariants},
            updateKind: UpdateKind.update,
          );
        }
      }

      // Sync products table from variants for ALL affected products
      // This keeps the product card display (price, stock, cost) up to date.
      // Both has_variants=true AND has_variants=false products need syncing
      // because non-variant products also have a default variant whose stock
      // is updated during purchase posting.
      for (final productId in affectedProductIds) {
        final now = DateTime.now().toIso8601String();
        // Aggregate stock from all active variants
        final stockRow = await customSelect(
          'SELECT COALESCE(SUM(stock_quantity), 0) AS total_stock, '
          'COALESCE(MAX(cost_cents), 0) AS latest_cost '
          'FROM product_variants WHERE product_id = ? AND is_active = 1',
          variables: [Variable.withInt(productId)],
        ).getSingleOrNull();
        if (stockRow != null) {
          final totalStock = stockRow.read<int>('total_stock');
          final latestCost = stockRow.read<int>('latest_cost');
          await customUpdate(
            'UPDATE products SET stock_quantity = ?, cost_cents = ?, updated_at = ? WHERE id = ?',
            variables: [Variable.withInt(totalStock), Variable.withInt(latestCost), Variable.withString(now), Variable.withInt(productId)],
            updates: {products},
            updateKind: UpdateKind.update,
          );
        }
      }

      // Update isTaxable flag on affected products when purchase has tax
      if (purchaseTaxCents > 0) {
        for (final productId in affectedProductIds) {
          await customUpdate(
            'UPDATE products SET is_taxable = 1, updated_at = ? WHERE id = ? AND is_taxable = 0',
            variables: [Variable.withString(DateTime.now().toIso8601String()), Variable.withInt(productId)],
            updates: {products},
            updateKind: UpdateKind.update,
          );
        }
      }

      // Update purchase status to posted
      await updatePurchaseStatus(purchaseId, 'posted', userId: userId);

      // Supplier accounting (one source of truth = suppliers.balanceCents):
      // - A posted purchase increases payable by total.
      // - Any paid amount decreases payable.
      // This keeps balances accurate even when paidAmountCents is used to settle
      // previous balance + this invoice.
      final totalCents = purchase.totalCents.toBigInt().toInt();

      // Ensure paidAmountCents is backed by purchase_payments rows so it doesn't
      // get lost when later payments are recorded.
      var totalPaidCents = (await getPurchasePayments(purchaseId))
          .fold<int>(0, (sum, p) => sum + p.amountCents.toBigInt().toInt());
      final headerPaidCents = purchase.paidAmountCents.toBigInt().toInt();
      int? backfilledInitialPaymentId;
      if (totalPaidCents == 0 && headerPaidCents > 0) {
        backfilledInitialPaymentId = await into(purchasePayments).insert(
          PurchasePaymentsCompanion.insert(
            purchaseId: purchaseId,
            amountCents: Decimal.fromInt(headerPaidCents),
            currencyId: purchase.currencyId,
            paymentMethod: purchase.paymentMethod ?? 'cash',
            reference: const Value(null),
            notes: const Value('Initial payment on posting'),
            paymentDate: Value(purchase.purchaseDate),
          ),
        );
        totalPaidCents = headerPaidCents;
      }

      // Keep purchases.paid_amount_cents consistent with payment rows.
      await (update(purchases)..where((p) => p.id.equals(purchaseId)))
          .write(PurchasesCompanion(
            paidAmountCents: Value(Decimal.fromInt(totalPaidCents)),
            updatedAt: Value(DateTime.now()),
          ));

      // Record supplier transactions for audit.
      await into(supplierTransactions).insert(
        SupplierTransactionsCompanion.insert(
          supplierId: purchase.supplierId,
          transactionType: 'purchase',
          amountCents: Decimal.fromInt(totalCents),
          currencyId: purchase.currencyId,
          description: Value('Purchase ${purchase.purchaseNumber}'),
          referenceId: Value(purchaseId),
          referenceType: const Value('purchase'),
        ),
      );

      // Only log an initial payment transaction when we had to backfill a payment row.
      // Later payments are logged via recordPayment().
      if (backfilledInitialPaymentId != null && totalPaidCents > 0) {
        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: purchase.supplierId,
            transactionType: 'payment',
            amountCents: Decimal.fromInt(-totalPaidCents),
            currencyId: purchase.currencyId,
            description: Value('Payment for ${purchase.purchaseNumber}'),
            referenceId: Value(backfilledInitialPaymentId),
            referenceType: const Value('purchase_payment'),
          ),
        );
      }

      // Apply net balance delta once.
      final deltaCents = totalCents - totalPaidCents;
      if (deltaCents != 0) {
        final supplier = await (select(suppliers)
              ..where((s) => s.id.equals(purchase.supplierId)))
            .getSingleOrNull();
        if (supplier != null) {
          final oldBalance = supplier.balanceCents.toBigInt().toInt();
          final newBalance = oldBalance + deltaCents;
          await (update(suppliers)..where((s) => s.id.equals(purchase.supplierId)))
              .write(SuppliersCompanion(
                balanceCents: Value(Decimal.fromInt(newBalance)),
                updatedAt: Value(DateTime.now()),
              ));
        }
      }
    });
  }

  /// Ensure supplier accounting exists for an already-posted purchase.
  /// This is used to repair legacy data created before supplier accounting was implemented.
  /// The method is idempotent: it only inserts missing supplier_transactions and only applies
  /// the corresponding missing balance deltas.
  Future<void> ensureSupplierAccountingForPostedPurchase(int purchaseId) {
    return transaction(() async {
      final purchase = await getPurchaseById(purchaseId);
      if (purchase == null) return;
      if (purchase.status != 'posted') return;

      final supplierId = purchase.supplierId;
      final currencyId = purchase.currencyId;
      final totalCents = purchase.totalCents.toBigInt().toInt();

      var deltaBalanceCents = 0;

      final existingPurchaseTx = await (select(supplierTransactions)
            ..where((t) => t.referenceType.equals('purchase') &
                t.referenceId.equals(purchaseId) &
                t.transactionType.equals('purchase')))
          .getSingleOrNull();

      if (existingPurchaseTx == null) {
        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: supplierId,
            transactionType: 'purchase',
            amountCents: Decimal.fromInt(totalCents),
            currencyId: currencyId,
            description: Value('Purchase ${purchase.purchaseNumber} (backfilled)'),
            referenceId: Value(purchaseId),
            referenceType: const Value('purchase'),
          ),
        );
        deltaBalanceCents += totalCents;
      }

      // Ensure there are payment rows when header paidAmountCents was used.
      var payments = await getPurchasePayments(purchaseId);
      if (payments.isEmpty) {
        final headerPaidCents = purchase.paidAmountCents.toBigInt().toInt();
        if (headerPaidCents > 0) {
          final backfilledPaymentId = await into(purchasePayments).insert(
            PurchasePaymentsCompanion.insert(
              purchaseId: purchaseId,
              amountCents: Decimal.fromInt(headerPaidCents),
              currencyId: currencyId,
              paymentMethod: purchase.paymentMethod ?? 'cash',
              reference: const Value(null),
              notes: const Value('Backfilled legacy payment'),
              paymentDate: Value(purchase.purchaseDate),
            ),
          );

          payments = await getPurchasePayments(purchaseId);

          // If we created a payment row, ensure its supplier transaction exists too.
          final existingPaymentTx = await (select(supplierTransactions)
                ..where((t) => t.referenceType.equals('purchase_payment') &
                    t.referenceId.equals(backfilledPaymentId) &
                    t.transactionType.equals('payment')))
              .getSingleOrNull();

          if (existingPaymentTx == null) {
            await into(supplierTransactions).insert(
              SupplierTransactionsCompanion.insert(
                supplierId: supplierId,
                transactionType: 'payment',
                amountCents: Decimal.fromInt(-headerPaidCents),
                currencyId: currencyId,
                description: Value('Payment for ${purchase.purchaseNumber} (backfilled)'),
                referenceId: Value(backfilledPaymentId),
                referenceType: const Value('purchase_payment'),
              ),
            );
            deltaBalanceCents -= headerPaidCents;
          }
        }
      }

      // Ensure each payment row has a matching supplier transaction.
      for (final p in payments) {
        final payId = p.id;
        final payCents = p.amountCents.toBigInt().toInt();

        final existingPaymentTx = await (select(supplierTransactions)
              ..where((t) => t.referenceType.equals('purchase_payment') &
                  t.referenceId.equals(payId) &
                  t.transactionType.equals('payment')))
            .getSingleOrNull();

        if (existingPaymentTx == null) {
          await into(supplierTransactions).insert(
            SupplierTransactionsCompanion.insert(
              supplierId: supplierId,
              transactionType: 'payment',
              amountCents: Decimal.fromInt(-payCents),
              currencyId: currencyId,
              description: Value('Payment for ${purchase.purchaseNumber} (backfilled)'),
              referenceId: Value(payId),
              referenceType: const Value('purchase_payment'),
            ),
          );
          deltaBalanceCents -= payCents;
        }
      }

      if (deltaBalanceCents != 0) {
        final supplier = await (select(suppliers)..where((s) => s.id.equals(supplierId)))
            .getSingleOrNull();
        if (supplier != null) {
          final oldBalance = supplier.balanceCents.toBigInt().toInt();
          final newBalance = oldBalance + deltaBalanceCents;
          await (update(suppliers)..where((s) => s.id.equals(supplierId)))
              .write(SuppliersCompanion(
                balanceCents: Value(Decimal.fromInt(newBalance)),
                updatedAt: Value(DateTime.now()),
              ));
        }
      }
    });
  }

  /// Void purchase - reverse stock changes if posted
  /// Also cascade-voids all associated returns to keep stock/accounting consistent.
  Future<void> voidPurchase(int purchaseId, {int? userId}) {
    return transaction(() async {
      final purchase = await getPurchaseById(purchaseId);
      if (purchase == null) {
        throw Exception('Purchase not found');
      }
      if (purchase.status == 'voided') {
        throw Exception('Purchase already voided');
      }

      // Cascade-void all associated returns first (reverses their stock/accounting)
      final associatedReturns = await (select(purchaseReturns)
            ..where((r) => r.purchaseId.equals(purchaseId)))
          .get();
      for (final ret in associatedReturns) {
        if (ret.status != 'voided') {
          await voidPurchaseReturn(ret.id);
        }
      }

      // If posted, reverse stock changes with negative-stock guard
      if (purchase.status == 'posted') {
        final items = await getPurchaseItems(purchaseId);
        final voidAffectedProductIds = <int>{};

        for (final item in items) {
          final variantId = item.variantId;
          final productId = item.productId;
          voidAffectedProductIds.add(productId);
          final now = DateTime.now().toIso8601String();

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
            await customUpdate(
              'UPDATE product_variants SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
              variables: [Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(variantId)],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          } else {
            // Non-variant product: check and reverse stock on products table
            final productRow = await customSelect(
              'SELECT stock_quantity FROM products WHERE id = ?',
              variables: [Variable.withInt(productId)],
            ).getSingleOrNull();
            if (productRow != null) {
              final currentStock = productRow.read<int>('stock_quantity');
              if (currentStock < item.quantity) {
                throw Exception(
                  'Cannot void: product #$productId stock ($currentStock) '
                  'is less than purchased quantity (${item.quantity}). '
                  'Some items may have been sold or returned.',
                );
              }
            }
            await customUpdate(
              'UPDATE products SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
              variables: [Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(productId)],
              updates: {products},
              updateKind: UpdateKind.update,
            );
            // Also reverse the default variant
            await customUpdate(
              'UPDATE product_variants SET stock_quantity = stock_quantity - ?, updated_at = ? '
              'WHERE product_id = ? AND color_id IS NULL AND size_id IS NULL',
              variables: [Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(productId)],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          }
        }

        // Sync products table from variants for ALL affected products
        for (final productId in voidAffectedProductIds) {
          final now = DateTime.now().toIso8601String();
          final stockRow = await customSelect(
            'SELECT COALESCE(SUM(stock_quantity), 0) AS total_stock, '
            'COALESCE(MAX(cost_cents), 0) AS latest_cost '
            'FROM product_variants WHERE product_id = ? AND is_active = 1',
            variables: [Variable.withInt(productId)],
          ).getSingleOrNull();
          if (stockRow != null) {
            final totalStock = stockRow.read<int>('total_stock');
            final latestCost = stockRow.read<int>('latest_cost');
            await customUpdate(
              'UPDATE products SET stock_quantity = ?, cost_cents = ?, updated_at = ? WHERE id = ?',
              variables: [Variable.withInt(totalStock), Variable.withInt(latestCost), Variable.withString(now), Variable.withInt(productId)],
              updates: {products},
              updateKind: UpdateKind.update,
            );
          }
        }

        // Reverse supplier balance: undo the net delta that was applied on posting.
        // On posting: balance += (totalCents - paidCents).
        // Each subsequent payment also reduced balance.
        // To fully reverse: credit back totalCents, then debit back all payments.
        final totalCents = purchase.totalCents.toBigInt().toInt();
        final payments = await getPurchasePayments(purchaseId);
        final totalPaidCents = payments.fold<int>(
          0, (sum, p) => sum + p.amountCents.toBigInt().toInt(),
        );

        // Record reversal transaction for the purchase
        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: purchase.supplierId,
            transactionType: 'purchase_void',
            amountCents: Decimal.fromInt(-totalCents),
            currencyId: purchase.currencyId,
            description: Value('Voided purchase ${purchase.purchaseNumber}'),
            referenceId: Value(purchaseId),
            referenceType: const Value('purchase'),
          ),
        );

        // Record reversal transactions for each payment
        if (totalPaidCents > 0) {
          await into(supplierTransactions).insert(
            SupplierTransactionsCompanion.insert(
              supplierId: purchase.supplierId,
              transactionType: 'payment_reversal',
              amountCents: Decimal.fromInt(totalPaidCents),
              currencyId: purchase.currencyId,
              description: Value('Reversed payments for voided purchase ${purchase.purchaseNumber}'),
              referenceId: Value(purchaseId),
              referenceType: const Value('purchase'),
            ),
          );
        }

        // Net balance change: -(totalCents - totalPaidCents)
        final netReversalCents = totalCents - totalPaidCents;
        if (netReversalCents != 0) {
          final supplier = await (select(suppliers)
                ..where((s) => s.id.equals(purchase.supplierId)))
              .getSingleOrNull();
          if (supplier != null) {
            final oldBalance = supplier.balanceCents.toBigInt().toInt();
            final newBalance = oldBalance - netReversalCents;
            await (update(suppliers)..where((s) => s.id.equals(purchase.supplierId)))
                .write(SuppliersCompanion(
                  balanceCents: Value(Decimal.fromInt(newBalance)),
                  updatedAt: Value(DateTime.now()),
                ));
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

  /// Watch upcoming due purchases for a supplier (posted, not fully paid, with due date)
  Stream<List<Purchase>> watchUpcomingDuePurchases(int supplierId) {
    return (select(purchases)
          ..where((p) =>
              p.supplierId.equals(supplierId) &
              p.status.equals('posted') &
              p.dueDate.isNotNull())
          ..orderBy([(p) => OrderingTerm.asc(p.dueDate)]))
        .watch()
        .map((list) => list.where((p) {
              final total = p.totalCents.toBigInt().toInt();
              final paid = p.paidAmountCents.toBigInt().toInt();
              return paid < total;
            }).toList());
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

    // Calculate totals only from posted purchases.
    // Drafts/pending should not affect accounting payables.
    int totalPostedCents = 0;
    int totalPostedPaidCents = 0;
    int overdueCount = 0;
    final now = DateTime.now();

    for (final p in allPurchases) {
      if (p.status == 'voided') continue;
      if (p.status == 'posted') {
        final total = p.totalCents.toBigInt().toInt();
        final paid = p.paidAmountCents.toBigInt().toInt();
        totalPostedCents += total;
        totalPostedPaidCents += paid;
      }

      // Overdue: posted, not fully paid, past due date
      if (p.status == 'posted' && p.dueDate != null) {
        final total = p.totalCents.toBigInt().toInt();
        final paid = p.paidAmountCents.toBigInt().toInt();
        if (paid < total) {
        if (p.dueDate!.isBefore(now)) {
          overdueCount++;
        }
        }
      }
    }

    // Returns count
    final returnsCount = await (select(purchaseReturns)).get().then((l) => l.length);

    return PurchaseDashboardStats(
      totalCount: totalCount,
      draftCount: draftCount,
      postedCount: postedCount,
      totalPayableCents: (totalPostedCents - totalPostedPaidCents).clamp(0, 1 << 62),
      totalPaidCents: totalPostedPaidCents,
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
      '  COALESCE(SUM(pri.subtotal_cents), 0) AS subtotal, '
      '  COALESCE(SUM(pri.discount_cents), 0) AS discount, '
      '  COALESCE(SUM(pri.tax_cents), 0) AS tax, '
      '  COALESCE(SUM(pri.refund_cents), 0) AS total '
      'FROM purchase_return_items pri '
      'WHERE pri.return_id = ?',
      variables: [Variable.withInt(returnId)],
    ).getSingle();

    final subtotalCents = totalsRow.read<int>('subtotal');
    final discountCents = totalsRow.read<int>('discount');
    final taxCents = totalsRow.read<int>('tax');
    final totalCents = totalsRow.read<int>('total');

    await customUpdate(
      'UPDATE purchase_returns '
      'SET subtotal_cents = ?, discount_cents = ?, tax_cents = ?, total_cents = ? '
      'WHERE id = ?',
      variables: [
        Variable.withInt(subtotalCents),
        Variable.withInt(discountCents),
        Variable.withInt(taxCents),
        Variable.withInt(totalCents),
        Variable.withInt(returnId),
      ],
      updates: {purchaseReturns},
      updateKind: UpdateKind.update,
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
        final returnAffectedProductIds = <int>{};
        for (final row in returnItemRows) {
          final returnItem = row.readTable(purchaseReturnItems);
          final purchaseItem = row.readTable(purchaseItems);
          final variantId = purchaseItem.variantId;
          final productId = purchaseItem.productId;
          returnAffectedProductIds.add(productId);
          final now = DateTime.now().toIso8601String();
          if (variantId != null) {
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

            await customUpdate(
              'UPDATE product_variants SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
              variables: [Variable.withInt(returnItem.quantity), Variable.withString(now), Variable.withInt(variantId)],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          } else {
            // Non-variant product: deduct from products table
            final productRow = await customSelect(
              'SELECT stock_quantity FROM products WHERE id = ?',
              variables: [Variable.withInt(productId)],
            ).getSingleOrNull();
            if (productRow != null) {
              final currentStock = productRow.read<int>('stock_quantity');
              if (currentStock < returnItem.quantity) {
                throw Exception(
                  'Cannot return: product #$productId stock ($currentStock) '
                  'is less than return quantity (${returnItem.quantity}).',
                );
              }
            }
            await customUpdate(
              'UPDATE products SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
              variables: [Variable.withInt(returnItem.quantity), Variable.withString(now), Variable.withInt(productId)],
              updates: {products},
              updateKind: UpdateKind.update,
            );
            // Also deduct from the default variant
            await customUpdate(
              'UPDATE product_variants SET stock_quantity = stock_quantity - ?, updated_at = ? '
              'WHERE product_id = ? AND color_id IS NULL AND size_id IS NULL',
              variables: [Variable.withInt(returnItem.quantity), Variable.withString(now), Variable.withInt(productId)],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          }
        }

        // Sync products.stock_quantity from variants for products with variants
        for (final productId in returnAffectedProductIds) {
          final now = DateTime.now().toIso8601String();
          final stockRow = await customSelect(
            'SELECT COALESCE(SUM(stock_quantity), 0) AS total_stock '
            'FROM product_variants WHERE product_id = ? AND is_active = 1',
            variables: [Variable.withInt(productId)],
          ).getSingleOrNull();
          if (stockRow != null) {
            final totalStock = stockRow.read<int>('total_stock');
            await customUpdate(
              'UPDATE products SET stock_quantity = ?, updated_at = ? WHERE id = ?',
              variables: [Variable.withInt(totalStock), Variable.withString(now), Variable.withInt(productId)],
              updates: {products},
              updateKind: UpdateKind.update,
            );
          }
        }
      }

      // Update return status to posted
      await (update(purchaseReturns)..where((r) => r.id.equals(returnId)))
          .write(const PurchaseReturnsCompanion(status: Value('posted')));

      // Create supplier transaction and adjust balance based on refund method
      final purchase = await getPurchaseById(returnData.purchaseId);
      if (purchase != null) {
        final refundCents = returnData.totalCents.toBigInt().toInt();
        final refundMethod = returnData.refundMethod;

        // Determine transaction type based on refund method
        // - credit: supplier owes us → deduct from balance (credit note)
        // - cash/cheque: supplier already paid us back → no balance change
        final isCreditRefund = refundMethod == 'credit';
        final txType = isCreditRefund ? 'credit_note' : 'refund';

        // Record supplier transaction for audit trail
        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: purchase.supplierId,
            transactionType: txType,
            amountCents: Decimal.fromInt(-refundCents),
            currencyId: purchase.currencyId,
            description: Value('Purchase return ${returnData.returnNumber} ($refundMethod)'),
            referenceId: Value(returnId),
            referenceType: const Value('purchase_return'),
          ),
        );

        // Only adjust supplier balance for credit refunds.
        // Cash/cheque means the supplier already gave us the money back,
        // so the balance (what we owe them) doesn't change.
        if (isCreditRefund) {
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
      }
    });
  }

  /// Watch purchase return items (raw)
  Stream<List<PurchaseReturnItem>> watchPurchaseReturnItems(int returnId) {
    return (select(purchaseReturnItems)..where((i) => i.returnId.equals(returnId))).watch();
  }

  /// Watch purchase return items with full product details (name, color, size, SKU)
  Stream<List<PurchaseReturnItemWithDetails>> watchPurchaseReturnItemsWithDetails(int returnId) {
    final query = select(purchaseReturnItems).join([
      innerJoin(purchaseItems, purchaseItems.id.equalsExp(purchaseReturnItems.purchaseItemId)),
      innerJoin(products, products.id.equalsExp(purchaseItems.productId)),
      leftOuterJoin(productVariants, productVariants.id.equalsExp(purchaseItems.variantId)),
      leftOuterJoin(productColors, productColors.id.equalsExp(productVariants.colorId)),
      leftOuterJoin(sizes, sizes.id.equalsExp(productVariants.sizeId)),
    ])
      ..where(purchaseReturnItems.returnId.equals(returnId));

    return query.watch().map((rows) => rows.map((row) {
      return PurchaseReturnItemWithDetails(
        returnItem: row.readTable(purchaseReturnItems),
        product: row.readTable(products),
        variant: row.readTableOrNull(productVariants),
        colorName: row.readTableOrNull(productColors)?.name,
        colorHex: row.readTableOrNull(productColors)?.hexCode,
        sizeName: row.readTableOrNull(sizes)?.name,
      );
    }).toList());
  }

  /// Get purchase return items with full product details
  Future<List<PurchaseReturnItemWithDetails>> getPurchaseReturnItemsWithDetails(int returnId) async {
    final query = select(purchaseReturnItems).join([
      innerJoin(purchaseItems, purchaseItems.id.equalsExp(purchaseReturnItems.purchaseItemId)),
      innerJoin(products, products.id.equalsExp(purchaseItems.productId)),
      leftOuterJoin(productVariants, productVariants.id.equalsExp(purchaseItems.variantId)),
      leftOuterJoin(productColors, productColors.id.equalsExp(productVariants.colorId)),
      leftOuterJoin(sizes, sizes.id.equalsExp(productVariants.sizeId)),
    ])
      ..where(purchaseReturnItems.returnId.equals(returnId));

    final rows = await query.get();
    return rows.map((row) {
      return PurchaseReturnItemWithDetails(
        returnItem: row.readTable(purchaseReturnItems),
        product: row.readTable(products),
        variant: row.readTableOrNull(productVariants),
        colorName: row.readTableOrNull(productColors)?.name,
        colorHex: row.readTableOrNull(productColors)?.hexCode,
        sizeName: row.readTableOrNull(sizes)?.name,
      );
    }).toList();
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
          final voidReturnAffectedProductIds = <int>{};
          for (final row in items) {
            final returnItem = row.readTable(purchaseReturnItems);
            final purchaseItem = row.readTable(purchaseItems);
            final variantId = purchaseItem.variantId;
            final productId = purchaseItem.productId;
            voidReturnAffectedProductIds.add(productId);
            final now = DateTime.now().toIso8601String();

            if (variantId != null) {
              await customUpdate(
                'UPDATE product_variants SET stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
                variables: [Variable.withInt(returnItem.quantity), Variable.withString(now), Variable.withInt(variantId)],
                updates: {productVariants},
                updateKind: UpdateKind.update,
              );
            } else {
              // Non-variant product: restore stock on products table
              await customUpdate(
                'UPDATE products SET stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
                variables: [Variable.withInt(returnItem.quantity), Variable.withString(now), Variable.withInt(productId)],
                updates: {products},
                updateKind: UpdateKind.update,
              );
              // Also restore the default variant
              await customUpdate(
                'UPDATE product_variants SET stock_quantity = stock_quantity + ?, updated_at = ? '
                'WHERE product_id = ? AND color_id IS NULL AND size_id IS NULL',
                variables: [Variable.withInt(returnItem.quantity), Variable.withString(now), Variable.withInt(productId)],
                updates: {productVariants},
                updateKind: UpdateKind.update,
              );
            }
          }

          // Sync products.stock_quantity from variants for products with variants
          for (final productId in voidReturnAffectedProductIds) {
            final now = DateTime.now().toIso8601String();
            final stockRow = await customSelect(
              'SELECT COALESCE(SUM(stock_quantity), 0) AS total_stock '
              'FROM product_variants WHERE product_id = ? AND is_active = 1',
              variables: [Variable.withInt(productId)],
            ).getSingleOrNull();
            if (stockRow != null) {
              final totalStock = stockRow.read<int>('total_stock');
              await customUpdate(
                'UPDATE products SET stock_quantity = ?, updated_at = ? WHERE id = ?',
                variables: [Variable.withInt(totalStock), Variable.withString(now), Variable.withInt(productId)],
                updates: {products},
                updateKind: UpdateKind.update,
              );
            }
          }
        }
      }

      // Reverse supplier accounting if return was posted
      if (returnData.status == 'posted') {
        final purchase = await getPurchaseById(returnData.purchaseId);
        if (purchase != null) {
          final refundCents = returnData.totalCents.toBigInt().toInt();
          final isCreditRefund = returnData.refundMethod == 'credit';

          // Record reversal transaction for audit trail (always)
          final reversalType = isCreditRefund ? 'credit_note_reversal' : 'refund_reversal';
          await into(supplierTransactions).insert(
            SupplierTransactionsCompanion.insert(
              supplierId: purchase.supplierId,
              transactionType: reversalType,
              amountCents: Decimal.fromInt(refundCents),
              currencyId: purchase.currencyId,
              description: Value('Voided purchase return ${returnData.returnNumber}'),
              referenceId: Value(returnId),
              referenceType: const Value('purchase_return'),
            ),
          );

          // Only restore supplier balance for credit refunds.
          // Cash/cheque refunds did not change the balance on posting,
          // so voiding them should not change it either.
          if (isCreditRefund) {
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

      final purchase = await getPurchaseById(payment.purchaseId.value);
      if (purchase == null) {
        throw Exception('Purchase not found');
      }

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

      // Supplier accounting: only posted purchases affect supplier balance.
      if (purchase.status == 'posted') {
        final amountCents = payment.amountCents.value.toBigInt().toInt();

        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: purchase.supplierId,
            transactionType: 'payment',
            amountCents: Decimal.fromInt(-amountCents),
            currencyId: purchase.currencyId,
            description: Value('Payment for ${purchase.purchaseNumber}'),
            referenceId: Value(paymentId),
            referenceType: const Value('purchase_payment'),
          ),
        );

        final supplier = await (select(suppliers)
              ..where((s) => s.id.equals(purchase.supplierId)))
            .getSingleOrNull();
        if (supplier != null) {
          final oldBalance = supplier.balanceCents.toBigInt().toInt();
          final newBalance = oldBalance - amountCents;
          await (update(suppliers)..where((s) => s.id.equals(purchase.supplierId)))
              .write(SuppliersCompanion(
                balanceCents: Value(Decimal.fromInt(newBalance)),
                updatedAt: Value(DateTime.now()),
              ));
        }
      }

      return paymentId;
    });
  }

  /// Delete a payment and recalculate paid_amount_cents
  Future<void> deletePayment(int paymentId) {
    return transaction(() async {
      final payment = await (select(purchasePayments)..where((p) => p.id.equals(paymentId))).getSingleOrNull();
      if (payment == null) return;

      final purchase = await getPurchaseById(payment.purchaseId);

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

      // Reverse supplier balance effect if purchase is posted.
      if (purchase != null && purchase.status == 'posted') {
        final amountCents = payment.amountCents.toBigInt().toInt();

        await into(supplierTransactions).insert(
          SupplierTransactionsCompanion.insert(
            supplierId: purchase.supplierId,
            transactionType: 'payment_reversal',
            amountCents: Decimal.fromInt(amountCents),
            currencyId: purchase.currencyId,
            description: Value('Deleted payment for ${purchase.purchaseNumber}'),
            referenceId: Value(paymentId),
            referenceType: const Value('purchase_payment'),
          ),
        );

        final supplier = await (select(suppliers)
              ..where((s) => s.id.equals(purchase.supplierId)))
            .getSingleOrNull();
        if (supplier != null) {
          final oldBalance = supplier.balanceCents.toBigInt().toInt();
          final newBalance = oldBalance + amountCents;
          await (update(suppliers)..where((s) => s.id.equals(purchase.supplierId)))
              .write(SuppliersCompanion(
                balanceCents: Value(Decimal.fromInt(newBalance)),
                updatedAt: Value(DateTime.now()),
              ));
        }
      }
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

  /// Watch set of purchase IDs that have at least one non-voided return
  Stream<Set<int>> watchPurchaseIdsWithReturns() {
    return (select(purchaseReturns)
          ..where((r) => r.status.equals('posted')))
        .watch()
        .map((list) => list.map((r) => r.purchaseId).toSet());
  }
}
