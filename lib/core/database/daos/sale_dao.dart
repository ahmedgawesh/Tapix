import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/transactions.dart';
import '../tables/parties.dart';
import '../tables/products.dart';
import '../tables/people.dart';

part 'sale_dao.g.dart';

/// Data class for sale with customer and employee info
class SaleWithCustomer {
  final Sale sale;
  final Customer? customer;
  final Employee? employee;

  SaleWithCustomer({required this.sale, this.customer, this.employee});
}

/// Data class for sale item with product and variant info
class SaleItemWithDetails {
  final SaleItem item;
  final Product product;
  final ProductVariant? variant;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;
  final Employee? employee;

  SaleItemWithDetails({
    required this.item,
    required this.product,
    this.variant,
    this.colorName,
    this.colorHex,
    this.sizeName,
    this.employee,
  });
}

/// Data class for sale return item with product details
class SaleReturnItemWithDetails {
  final SaleReturnItem returnItem;
  final Product product;
  final ProductVariant? variant;
  final String? colorName;
  final String? colorHex;
  final String? sizeName;

  SaleReturnItemWithDetails({
    required this.returnItem,
    required this.product,
    this.variant,
    this.colorName,
    this.colorHex,
    this.sizeName,
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

@DriftAccessor(tables: [
  Sales,
  SaleItems,
  SaleTaxBands,
  SaleReturns,
  SaleReturnItems,
  SalePayments,
  Customers,
  CustomerTransactions,
  Products,
  ProductVariants,
  Employees,
])
class SaleDao extends DatabaseAccessor<AppDatabase> with _$SaleDaoMixin {
  SaleDao(super.db);

  // ==================== SALES ====================

  /// Watch all sales ordered by date descending
  Stream<List<Sale>> watchAllSales() {
    return (select(sales)
          ..orderBy([(s) => OrderingTerm.desc(s.saleDate)]))
        .watch();
  }

  /// Watch all sales with customer and employee info
  Stream<List<SaleWithCustomer>> watchAllSalesWithCustomer() {
    final query = select(sales).join([
      leftOuterJoin(customers, customers.id.equalsExp(sales.customerId)),
      leftOuterJoin(employees, employees.id.equalsExp(sales.employeeId)),
    ])
      ..orderBy([OrderingTerm.desc(sales.saleDate)]);

    return query.watch().map((rows) => rows.map((row) {
          return SaleWithCustomer(
            sale: row.readTable(sales),
            customer: row.readTableOrNull(customers),
            employee: row.readTableOrNull(employees),
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

  /// Get sale with customer and employee by ID
  Future<SaleWithCustomer?> getSaleWithCustomerById(int id) async {
    final query = select(sales).join([
      leftOuterJoin(customers, customers.id.equalsExp(sales.customerId)),
      leftOuterJoin(employees, employees.id.equalsExp(sales.employeeId)),
    ])
      ..where(sales.id.equals(id));

    final row = await query.getSingleOrNull();
    if (row == null) return null;

    return SaleWithCustomer(
      sale: row.readTable(sales),
      customer: row.readTableOrNull(customers),
      employee: row.readTableOrNull(employees),
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
      leftOuterJoin(employees, employees.id.equalsExp(sales.employeeId)),
    ])
      ..where(sales.invoiceNumber.like(searchQuery) |
          customers.name.like(searchQuery))
      ..orderBy([OrderingTerm.desc(sales.saleDate)]);

    return joinQuery.watch().map((rows) => rows.map((row) {
          return SaleWithCustomer(
            sale: row.readTable(sales),
            customer: row.readTableOrNull(customers),
            employee: row.readTableOrNull(employees),
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

  /// Post sale - deduct variant stock and handle customer accounting.
  ///
  /// Accounting rules by payment method:
  /// - cash / card: Fully settled at point of sale. paidAmountCents >= totalCents.
  ///   A sale_payment row is created. No impact on customer balance.
  /// - credit: Full invoice amount added to customer balance (accounts receivable).
  ///   Customer owes the full amount until payments are recorded via recordPayment().
  /// - cheque: Like credit — full amount added to customer balance.
  ///   The cheque due date tracks when payment is expected.
  ///
  /// If [allowNegativeStock] is true, stock validation is skipped and stock can go negative.
  Future<void> postSale(int saleId, {bool allowNegativeStock = false}) {
    return transaction(() async {
      final sale = await getSaleById(saleId);
      if (sale == null) throw Exception('Sale not found');
      if (sale.status == 'completed') throw Exception('Sale already completed');

      // 1. Validate stock availability BEFORE any deduction (unless allowNegativeStock)
      final items = await getSaleItems(saleId);
      if (!allowNegativeStock) {
        for (final item in items) {
          final variantId = item.variantId;
          final productId = item.productId;

          if (variantId != null) {
            final row = await customSelect(
              'SELECT stock_quantity FROM product_variants WHERE id = ?',
              variables: [Variable.withInt(variantId)],
            ).getSingleOrNull();
            final currentStock = row?.read<int>('stock_quantity') ?? 0;
            if (currentStock < item.quantity) {
              // Look up variant display info for a clear error message
              final infoRow = await customSelect(
                'SELECT p.name AS product_name FROM products p '
                'INNER JOIN product_variants pv ON pv.product_id = p.id '
                'WHERE pv.id = ?',
                variables: [Variable.withInt(variantId)],
              ).getSingleOrNull();
              final productName = infoRow?.read<String>('product_name') ?? 'Unknown';
              throw Exception(
                'Insufficient stock for "$productName" (variant #$variantId): '
                'available $currentStock, required ${item.quantity}.',
              );
            }
          } else {
            final row = await customSelect(
              'SELECT stock_quantity, name FROM products WHERE id = ?',
              variables: [Variable.withInt(productId)],
            ).getSingleOrNull();
            final currentStock = row?.read<int>('stock_quantity') ?? 0;
            final productName = row?.read<String>('name') ?? 'Unknown';
            if (currentStock < item.quantity) {
              throw Exception(
                'Insufficient stock for "$productName" (product #$productId): '
                'available $currentStock, required ${item.quantity}.',
              );
            }
          }
        }
      }

      // 2. Deduct stock (validated above)
      final affectedProductIds = <int>{};
      for (final item in items) {
        final variantId = item.variantId;
        final productId = item.productId;
        affectedProductIds.add(productId);
        final now = DateTime.now().toIso8601String();

        if (variantId != null) {
          await customUpdate(
            'UPDATE product_variants SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
            variables: [Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(variantId)],
            updates: {productVariants},
            updateKind: UpdateKind.update,
          );
        } else {
          // Non-variant product: deduct from products table
          await customUpdate(
            'UPDATE products SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
            variables: [Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(productId)],
            updates: {products},
            updateKind: UpdateKind.update,
          );
          // Also deduct from the default variant
          await customUpdate(
            'UPDATE product_variants SET stock_quantity = stock_quantity - ?, updated_at = ? '
            'WHERE product_id = ? AND color_id IS NULL AND size_id IS NULL AND stock_quantity >= ?',
            variables: [Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(productId), Variable.withInt(item.quantity)],
            updates: {productVariants},
            updateKind: UpdateKind.update,
          );
        }
      }

      // 1b. Sync products.stock_quantity from variants for products with variants
      for (final productId in affectedProductIds) {
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

      // 2. Update status
      await updateSaleStatus(saleId, 'completed');

      // 3. Customer accounting (only if a customer is assigned)
      final customerId = sale.customerId;
      if (customerId == null) return;

      final totalCents = sale.totalCents.toBigInt().toInt();
      final headerPaidCents = sale.paidAmountCents.toBigInt().toInt();
      final paymentMethod = sale.paymentMethod;

      // 3a. Ensure paidAmountCents is backed by sale_payments rows
      //     (mirrors purchase_dao.postPurchase pattern)
      var totalPaidCents = (await getSalePayments(saleId))
          .fold<int>(0, (sum, p) => sum + p.amountCents.toBigInt().toInt());
      int? backfilledPaymentId;
      int? excessPaymentId;
      if (totalPaidCents == 0 && headerPaidCents > 0) {
        // If overpaying, split into invoice payment + excess credit payment
        final invoicePayment = headerPaidCents > totalCents ? totalCents : headerPaidCents;
        final excessPayment = headerPaidCents > totalCents ? headerPaidCents - totalCents : 0;

        backfilledPaymentId = await into(salePayments).insert(
          SalePaymentsCompanion.insert(
            saleId: saleId,
            amountCents: Decimal.fromInt(invoicePayment),
            currencyId: sale.currencyId,
            paymentMethod: paymentMethod,
            reference: const Value(null),
            notes: const Value('Initial payment on posting'),
            paymentDate: Value(sale.saleDate),
          ),
        );

        if (excessPayment > 0) {
          excessPaymentId = await into(salePayments).insert(
            SalePaymentsCompanion.insert(
              saleId: saleId,
              amountCents: Decimal.fromInt(excessPayment),
              currencyId: sale.currencyId,
              paymentMethod: paymentMethod,
              reference: const Value(null),
              notes: const Value('Excess cash — added to customer balance'),
              paymentDate: Value(sale.saleDate),
            ),
          );
        }

        totalPaidCents = headerPaidCents;
      }

      // 3b. Keep sales.paid_amount_cents consistent with payment rows
      await (update(sales)..where((s) => s.id.equals(saleId)))
          .write(SalesCompanion(
            paidAmountCents: Value(Decimal.fromInt(totalPaidCents)),
            updatedAt: Value(DateTime.now()),
          ));

      // 3c. Record sale transaction in customer ledger
      await into(db.customerTransactions).insert(
        CustomerTransactionsCompanion.insert(
          customerId: customerId,
          transactionType: 'sale',
          amountCents: Decimal.fromInt(totalCents),
          currencyId: sale.currencyId,
          description: Value('Sale ${sale.invoiceNumber}'),
          referenceId: Value(saleId),
          referenceType: const Value('sale'),
        ),
      );

      // 3d. Record payment transaction(s) only when we backfilled payment rows.
      //     Later payments are logged via recordPayment().
      if (backfilledPaymentId != null) {
        final invoicePayment = headerPaidCents > totalCents ? totalCents : headerPaidCents;
        if (invoicePayment > 0) {
          await into(db.customerTransactions).insert(
            CustomerTransactionsCompanion.insert(
              customerId: customerId,
              transactionType: 'payment',
              amountCents: Decimal.fromInt(-invoicePayment),
              currencyId: sale.currencyId,
              description: Value('Payment for ${sale.invoiceNumber}'),
              referenceId: Value(backfilledPaymentId),
              referenceType: const Value('sale_payment'),
            ),
          );
        }
      }

      // 3d2. Record excess cash as a separate payment transaction
      if (excessPaymentId != null) {
        final excessPayment = headerPaidCents - totalCents;
        await into(db.customerTransactions).insert(
          CustomerTransactionsCompanion.insert(
            customerId: customerId,
            transactionType: 'payment',
            amountCents: Decimal.fromInt(-excessPayment),
            currencyId: sale.currencyId,
            description: Value('Excess cash added to balance — ${sale.invoiceNumber}'),
            referenceId: Value(excessPaymentId),
            referenceType: const Value('sale_payment'),
          ),
        );
      }

      // 3e. Apply net balance delta once.
      //     For cash/card: delta = 0 (fully paid)
      //     For credit/cheque: delta = totalCents (full amount owed)
      final deltaCents = totalCents - totalPaidCents;
      if (deltaCents != 0) {
        final customer = await (select(customers)
              ..where((c) => c.id.equals(customerId)))
            .getSingleOrNull();
        if (customer != null) {
          final oldBalance = customer.balanceCents.toBigInt().toInt();
          final newBalance = oldBalance + deltaCents;
          await (update(customers)..where((c) => c.id.equals(customerId)))
              .write(CustomersCompanion(
                balanceCents: Value(Decimal.fromInt(newBalance)),
                updatedAt: Value(DateTime.now()),
              ));
        }
      }
    });
  }

  /// Void sale - reverse stock and customer accounting if completed.
  /// Also cascade-voids all associated returns to keep stock/accounting consistent.
  Future<void> voidSale(int saleId) {
    return transaction(() async {
      final sale = await getSaleById(saleId);
      if (sale == null) throw Exception('Sale not found');
      if (sale.status == 'voided') throw Exception('Sale already voided');

      // Cascade-void all associated returns first (reverses their stock/accounting)
      final associatedReturns = await (select(saleReturns)
            ..where((r) => r.saleId.equals(saleId)))
          .get();
      for (final ret in associatedReturns) {
        if (ret.status != 'voided') {
          await voidSaleReturn(ret.id);
        }
      }

      if (sale.status == 'completed') {
        // 1. Reverse stock
        final items = await getSaleItems(saleId);
        final voidAffectedProductIds = <int>{};
        for (final item in items) {
          final variantId = item.variantId;
          final productId = item.productId;
          voidAffectedProductIds.add(productId);
          final now = DateTime.now().toIso8601String();

          if (variantId != null) {
            await customUpdate(
              'UPDATE product_variants SET stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
              variables: [Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(variantId)],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          } else {
            // Non-variant product: restore stock on products table
            await customUpdate(
              'UPDATE products SET stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
              variables: [Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(productId)],
              updates: {products},
              updateKind: UpdateKind.update,
            );
            // Also restore the default variant
            await customUpdate(
              'UPDATE product_variants SET stock_quantity = stock_quantity + ?, updated_at = ? '
              'WHERE product_id = ? AND color_id IS NULL AND size_id IS NULL',
              variables: [Variable.withInt(item.quantity), Variable.withString(now), Variable.withInt(productId)],
              updates: {productVariants},
              updateKind: UpdateKind.update,
            );
          }
        }

        // 1b. Sync products.stock_quantity from variants for products with variants
        for (final productId in voidAffectedProductIds) {
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

        // 2. Reverse customer accounting
        final customerId = sale.customerId;
        if (customerId != null) {
          final totalCents = sale.totalCents.toBigInt().toInt();
          final payments = await getSalePayments(saleId);
          final totalPaidCents = payments.fold<int>(
            0, (sum, p) => sum + p.amountCents.toBigInt().toInt(),
          );

          // Record reversal transaction for the sale (negative = undo receivable)
          await into(db.customerTransactions).insert(
            CustomerTransactionsCompanion.insert(
              customerId: customerId,
              transactionType: 'sale_void',
              amountCents: Decimal.fromInt(-totalCents),
              currencyId: sale.currencyId,
              description: Value('Voided sale ${sale.invoiceNumber}'),
              referenceId: Value(saleId),
              referenceType: const Value('sale'),
            ),
          );

          // Record reversal for payments (positive = undo payment offset)
          if (totalPaidCents > 0) {
            await into(db.customerTransactions).insert(
              CustomerTransactionsCompanion.insert(
                customerId: customerId,
                transactionType: 'payment_reversal',
                amountCents: Decimal.fromInt(totalPaidCents),
                currencyId: sale.currencyId,
                description: Value('Reversed payments for voided sale ${sale.invoiceNumber}'),
                referenceId: Value(saleId),
                referenceType: const Value('sale'),
              ),
            );
          }

          // Net balance change: -(totalCents - totalPaidCents)
          // Undoes the delta that was applied on posting
          final netReversalCents = totalCents - totalPaidCents;
          if (netReversalCents != 0) {
            final customer = await (select(customers)
                  ..where((c) => c.id.equals(customerId)))
                .getSingleOrNull();
            if (customer != null) {
              final oldBalance = customer.balanceCents.toBigInt().toInt();
              final newBalance = oldBalance - netReversalCents;
              await (update(customers)..where((c) => c.id.equals(customerId)))
                  .write(CustomersCompanion(
                    balanceCents: Value(Decimal.fromInt(newBalance)),
                    updatedAt: Value(DateTime.now()),
                  ));
            }
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

  /// Compute total cost of goods sold for a sale.
  ///
  /// For each sale item, looks up cost_cents from the variant (if variantId is set)
  /// or from the product. Returns the sum of (cost_cents * quantity) for all items.
  Future<int> computeSaleCostCents(int saleId) async {
    final items = await getSaleItems(saleId);
    int totalCost = 0;
    for (final item in items) {
      int unitCost = 0;
      if (item.variantId != null) {
        final row = await customSelect(
          'SELECT cost_cents FROM product_variants WHERE id = ?',
          variables: [Variable.withInt(item.variantId!)],
        ).getSingleOrNull();
        if (row != null) {
          unitCost = row.read<int>('cost_cents');
        }
      } else {
        final row = await customSelect(
          'SELECT cost_cents FROM products WHERE id = ?',
          variables: [Variable.withInt(item.productId)],
        ).getSingleOrNull();
        if (row != null) {
          unitCost = row.read<int>('cost_cents');
        }
      }
      totalCost += unitCost * item.quantity;
    }
    return totalCost;
  }

  /// Compute total cost of returned items for a sale return.
  ///
  /// For each return item, looks up cost_cents from the variant (if variantId is set
  /// on the original sale item) or from the product.
  Future<int> computeSaleReturnCostCents(int returnId) async {
    final query = select(saleReturnItems).join([
      innerJoin(saleItems, saleItems.id.equalsExp(saleReturnItems.saleItemId)),
    ])
      ..where(saleReturnItems.returnId.equals(returnId));

    final rows = await query.get();
    int totalCost = 0;
    for (final row in rows) {
      final returnItem = row.readTable(saleReturnItems);
      final saleItem = row.readTable(saleItems);
      int unitCost = 0;
      if (saleItem.variantId != null) {
        final costRow = await customSelect(
          'SELECT cost_cents FROM product_variants WHERE id = ?',
          variables: [Variable.withInt(saleItem.variantId!)],
        ).getSingleOrNull();
        if (costRow != null) {
          unitCost = costRow.read<int>('cost_cents');
        }
      } else {
        final costRow = await customSelect(
          'SELECT cost_cents FROM products WHERE id = ?',
          variables: [Variable.withInt(saleItem.productId)],
        ).getSingleOrNull();
        if (costRow != null) {
          unitCost = costRow.read<int>('cost_cents');
        }
      }
      totalCost += unitCost * returnItem.quantity;
    }
    return totalCost;
  }

  /// Get sale items with product and variant details
  Future<List<SaleItemWithDetails>> getSaleItemsWithDetails(int saleId) async {
    final query = select(saleItems).join([
      innerJoin(products, products.id.equalsExp(saleItems.productId)),
      leftOuterJoin(productVariants, productVariants.id.equalsExp(saleItems.variantId)),
      leftOuterJoin(productColors, productColors.id.equalsExp(productVariants.colorId)),
      leftOuterJoin(sizes, sizes.id.equalsExp(productVariants.sizeId)),
      leftOuterJoin(employees, employees.id.equalsExp(saleItems.employeeId)),
    ])
      ..where(saleItems.saleId.equals(saleId));

    final rows = await query.get();
    return rows.map((row) {
      return SaleItemWithDetails(
        item: row.readTable(saleItems),
        product: row.readTable(products),
        variant: row.readTableOrNull(productVariants),
        colorName: row.readTableOrNull(productColors)?.name,
        colorHex: row.readTableOrNull(productColors)?.hexCode,
        sizeName: row.readTableOrNull(sizes)?.name,
        employee: row.readTableOrNull(employees),
      );
    }).toList();
  }

  /// Watch sale items with product and variant details
  Stream<List<SaleItemWithDetails>> watchSaleItemsWithDetails(int saleId) {
    final query = select(saleItems).join([
      innerJoin(products, products.id.equalsExp(saleItems.productId)),
      leftOuterJoin(productVariants, productVariants.id.equalsExp(saleItems.variantId)),
      leftOuterJoin(productColors, productColors.id.equalsExp(productVariants.colorId)),
      leftOuterJoin(sizes, sizes.id.equalsExp(productVariants.sizeId)),
      leftOuterJoin(employees, employees.id.equalsExp(saleItems.employeeId)),
    ])
      ..where(saleItems.saleId.equals(saleId));

    return query.watch().map((rows) => rows.map((row) {
          return SaleItemWithDetails(
            item: row.readTable(saleItems),
            product: row.readTable(products),
            variant: row.readTableOrNull(productVariants),
            colorName: row.readTableOrNull(productColors)?.name,
            colorHex: row.readTableOrNull(productColors)?.hexCode,
            sizeName: row.readTableOrNull(sizes)?.name,
            employee: row.readTableOrNull(employees),
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

  /// Post sale return - restore variant stock and handle customer accounting.
  ///
  /// Customer accounting rules by refund method:
  /// - cash / cheque: Customer already received money back → no balance change.
  /// - credit: Refund applied as credit note → reduces customer balance (they owe less).
  Future<void> postSaleReturn(int returnId) {
    return transaction(() async {
      final returnData = await getSaleReturnById(returnId);
      if (returnData == null) throw Exception('Return not found');
      if (returnData.status == 'posted') throw Exception('Return already posted');

      // Validate return quantities don't exceed available (sold - already returned)
      final returnItemsQuery = select(saleReturnItems).join([
        innerJoin(saleItems, saleItems.id.equalsExp(saleReturnItems.saleItemId)),
      ])
        ..where(saleReturnItems.returnId.equals(returnId));

      final returnItemRows = await returnItemsQuery.get();
      for (final row in returnItemRows) {
        final returnItem = row.readTable(saleReturnItems);
        final saleItem = row.readTable(saleItems);

        final alreadyReturned = await getReturnedQuantity(saleItem.id);
        // Subtract this return's own quantity since it's not yet posted
        final previouslyReturned = alreadyReturned - returnItem.quantity;
        final maxReturnable = saleItem.quantity - previouslyReturned;

        if (returnItem.quantity > maxReturnable) {
          throw Exception(
            'Cannot return ${returnItem.quantity} units of item #${saleItem.id}. '
            'Only $maxReturnable available (sold: ${saleItem.quantity}, '
            'already returned: $previouslyReturned).',
          );
        }
      }

      // 1. Always restore stock for sale returns regardless of disposition.
      // The goods are returning to inventory whether restocked, refunded, written off,
      // or exchanged. Disposition only affects financial treatment.
      {
        final returnAffectedProductIds = <int>{};
        for (final row in returnItemRows) {
          final returnItem = row.readTable(saleReturnItems);
          final saleItem = row.readTable(saleItems);
          final variantId = saleItem.variantId;
          final productId = saleItem.productId;
          returnAffectedProductIds.add(productId);
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

      // 2. Update return status to posted
      await (update(saleReturns)..where((r) => r.id.equals(returnId)))
          .write(const SaleReturnsCompanion(status: Value('posted')));

      // 3. Customer accounting
      final sale = await getSaleById(returnData.saleId);
      if (sale != null && sale.customerId != null) {
        final customerId = sale.customerId!;
        final refundCents = returnData.totalCents.toBigInt().toInt();
        final refundMethod = returnData.refundMethod;

        // Determine transaction type based on refund method:
        // - credit: customer gets credit note → reduces what they owe
        // - cash/cheque: customer already got money back → no balance change
        final isCreditRefund = refundMethod == 'credit';
        final txType = isCreditRefund ? 'credit_note' : 'refund';

        // Record customer transaction for audit trail (always)
        await into(db.customerTransactions).insert(
          CustomerTransactionsCompanion.insert(
            customerId: customerId,
            transactionType: txType,
            amountCents: Decimal.fromInt(-refundCents),
            currencyId: sale.currencyId,
            description: Value('Sale return ${returnData.returnNumber} ($refundMethod)'),
            referenceId: Value(returnId),
            referenceType: const Value('sale_return'),
          ),
        );

        // Only adjust customer balance for credit refunds.
        // Cash/cheque means we already gave the customer money back,
        // so the balance (what they owe us) doesn't change.
        if (isCreditRefund) {
          final customer = await (select(customers)
                ..where((c) => c.id.equals(customerId)))
              .getSingleOrNull();
          if (customer != null) {
            final oldBalance = customer.balanceCents.toBigInt().toInt();
            final newBalance = oldBalance - refundCents;
            await (update(customers)..where((c) => c.id.equals(customerId)))
                .write(CustomersCompanion(
                  balanceCents: Value(Decimal.fromInt(newBalance)),
                  updatedAt: Value(DateTime.now()),
                ));
          }
        }
      }
    });
  }

  /// Void a sale return - reverse stock and customer accounting if posted.
  /// Mirrors voidPurchaseReturn pattern.
  Future<void> voidSaleReturn(int returnId) {
    return transaction(() async {
      final returnData = await getSaleReturnById(returnId);
      if (returnData == null) throw Exception('Return not found');
      if (returnData.status == 'voided') throw Exception('Return already voided');

      if (returnData.status == 'posted') {
        // 1. Always reverse stock changes (mirrors postSaleReturn).
        {
          final query = select(saleReturnItems).join([
            innerJoin(saleItems, saleItems.id.equalsExp(saleReturnItems.saleItemId)),
          ])
            ..where(saleReturnItems.returnId.equals(returnId));

          final items = await query.get();
          final voidReturnAffectedProductIds = <int>{};
          for (final row in items) {
            final returnItem = row.readTable(saleReturnItems);
            final saleItem = row.readTable(saleItems);
            final variantId = saleItem.variantId;
            final productId = saleItem.productId;
            voidReturnAffectedProductIds.add(productId);
            final now = DateTime.now().toIso8601String();

            if (variantId != null) {
              await customUpdate(
                'UPDATE product_variants SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
                variables: [Variable.withInt(returnItem.quantity), Variable.withString(now), Variable.withInt(variantId)],
                updates: {productVariants},
                updateKind: UpdateKind.update,
              );
            } else {
              // Non-variant product: deduct stock from products table
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

        // 2. Reverse customer accounting
        final sale = await getSaleById(returnData.saleId);
        if (sale != null && sale.customerId != null) {
          final customerId = sale.customerId!;
          final refundCents = returnData.totalCents.toBigInt().toInt();
          final isCreditRefund = returnData.refundMethod == 'credit';

          // Record reversal transaction for audit trail (always)
          final reversalType = isCreditRefund ? 'credit_note_reversal' : 'refund_reversal';
          await into(db.customerTransactions).insert(
            CustomerTransactionsCompanion.insert(
              customerId: customerId,
              transactionType: reversalType,
              amountCents: Decimal.fromInt(refundCents),
              currencyId: sale.currencyId,
              description: Value('Voided sale return ${returnData.returnNumber}'),
              referenceId: Value(returnId),
              referenceType: const Value('sale_return'),
            ),
          );

          // Only restore customer balance for credit refunds.
          // Cash/cheque refunds did not change the balance on posting,
          // so voiding them should not change it either.
          if (isCreditRefund) {
            final customer = await (select(customers)
                  ..where((c) => c.id.equals(customerId)))
                .getSingleOrNull();
            if (customer != null) {
              final oldBalance = customer.balanceCents.toBigInt().toInt();
              final newBalance = oldBalance + refundCents;
              await (update(customers)..where((c) => c.id.equals(customerId)))
                  .write(CustomersCompanion(
                    balanceCents: Value(Decimal.fromInt(newBalance)),
                    updatedAt: Value(DateTime.now()),
                  ));
            }
          }
        }
      }

      await (update(saleReturns)..where((r) => r.id.equals(returnId)))
          .write(const SaleReturnsCompanion(status: Value('voided')));
    });
  }

  // ==================== SALE PAYMENTS ====================

  /// Watch all payments for a sale
  Stream<List<SalePayment>> watchSalePayments(int saleId) {
    return (select(salePayments)
          ..where((p) => p.saleId.equals(saleId))
          ..orderBy([(p) => OrderingTerm.desc(p.paymentDate)]))
        .watch();
  }

  /// Get payments for a sale
  Future<List<SalePayment>> getSalePayments(int saleId) {
    return (select(salePayments)
          ..where((p) => p.saleId.equals(saleId))
          ..orderBy([(p) => OrderingTerm.desc(p.paymentDate)]))
        .get();
  }

  /// Record a payment and update paid_amount_cents on the sale
  Future<int> recordPayment(SalePaymentsCompanion payment) {
    return transaction(() async {
      final sale = await getSaleById(payment.saleId.value);
      if (sale == null) {
        throw Exception('Sale not found');
      }

      final paymentId = await into(salePayments).insert(payment);

      // Recalculate total paid
      final allPayments = await getSalePayments(payment.saleId.value);
      final totalPaid = allPayments.fold<int>(
          0, (sum, p) => sum + p.amountCents.toBigInt().toInt());

      await (update(sales)..where((s) => s.id.equals(payment.saleId.value)))
          .write(SalesCompanion(
            paidAmountCents: Value(Decimal.fromInt(totalPaid)),
            updatedAt: Value(DateTime.now()),
          ));

      final isOnAccount = sale.paymentMethod == 'credit' || sale.paymentMethod == 'cheque';
      if (sale.customerId != null && sale.status == 'completed' && isOnAccount) {
        final amountCents = payment.amountCents.value.toBigInt().toInt();

        await into(db.customerTransactions).insert(
          CustomerTransactionsCompanion.insert(
            customerId: sale.customerId!,
            transactionType: 'payment',
            amountCents: Decimal.fromInt(-amountCents),
            currencyId: sale.currencyId,
            description: Value('Payment for ${sale.invoiceNumber}'),
            referenceId: Value(paymentId),
            referenceType: const Value('sale_payment'),
          ),
        );

        final customer = await (select(customers)
              ..where((c) => c.id.equals(sale.customerId!)))
            .getSingleOrNull();
        if (customer != null) {
          final oldBalance = customer.balanceCents.toBigInt().toInt();
          final newBalance = oldBalance - amountCents;
          await (update(customers)..where((c) => c.id.equals(sale.customerId!)))
              .write(CustomersCompanion(
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
      final payment = await (select(salePayments)..where((p) => p.id.equals(paymentId))).getSingleOrNull();
      if (payment == null) return;

      final sale = await getSaleById(payment.saleId);

      await (delete(salePayments)..where((p) => p.id.equals(paymentId))).go();

      final remaining = await getSalePayments(payment.saleId);
      final totalPaid = remaining.fold<int>(
          0, (sum, p) => sum + p.amountCents.toBigInt().toInt());

      await (update(sales)..where((s) => s.id.equals(payment.saleId)))
          .write(SalesCompanion(
            paidAmountCents: Value(Decimal.fromInt(totalPaid)),
            updatedAt: Value(DateTime.now()),
          ));

      final isOnAccount = sale?.paymentMethod == 'credit' || sale?.paymentMethod == 'cheque';
      if (sale != null && sale.customerId != null && sale.status == 'completed' && isOnAccount) {
        final amountCents = payment.amountCents.toBigInt().toInt();

        await into(db.customerTransactions).insert(
          CustomerTransactionsCompanion.insert(
            customerId: sale.customerId!,
            transactionType: 'payment_reversal',
            amountCents: Decimal.fromInt(amountCents),
            currencyId: sale.currencyId,
            description: Value('Deleted payment for ${sale.invoiceNumber}'),
            referenceId: Value(paymentId),
            referenceType: const Value('sale_payment'),
          ),
        );

        final customer = await (select(customers)
              ..where((c) => c.id.equals(sale.customerId!)))
            .getSingleOrNull();
        if (customer != null) {
          final oldBalance = customer.balanceCents.toBigInt().toInt();
          final newBalance = oldBalance + amountCents;
          await (update(customers)..where((c) => c.id.equals(sale.customerId!)))
              .write(CustomersCompanion(
                balanceCents: Value(Decimal.fromInt(newBalance)),
                updatedAt: Value(DateTime.now()),
              ));
        }
      }
    });
  }

  /// Get total returned quantity for a specific sale item (excluding voided returns)
  Future<int> getReturnedQuantity(int saleItemId) async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(sri.quantity), 0) as total '
      'FROM sale_return_items sri '
      'JOIN sale_returns sr ON sr.id = sri.return_id '
      'WHERE sri.sale_item_id = ? AND sr.status != ?',
      variables: [Variable.withInt(saleItemId), const Variable('voided')],
    ).getSingle();
    return result.read<int>('total');
  }

  // ==================== DASHBOARD STATS ====================

  /// Get dashboard stats using SQL aggregation (no full-table load).
  Future<SaleDashboardStats> getDashboardStats() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

    // Single aggregation query for all sale stats
    // COALESCE all SUM expressions to handle NULL when table is empty
    final statsRow = await customSelect(
      'SELECT '
      '  COUNT(*) AS total_count, '
      "  COALESCE(SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END), 0) AS completed_count, "
      "  COALESCE(SUM(CASE WHEN status = 'voided' THEN 1 ELSE 0 END), 0) AS voided_count, "
      "  COALESCE(SUM(CASE WHEN status = 'completed' THEN total_cents ELSE 0 END), 0) AS total_sales_cents, "
      "  COALESCE(SUM(CASE WHEN status = 'completed' AND sale_date >= ? THEN total_cents ELSE 0 END), 0) AS today_sales_cents, "
      "  COALESCE(SUM(CASE WHEN status = 'completed' AND sale_date >= ? THEN 1 ELSE 0 END), 0) AS today_count "
      'FROM sales',
      variables: [Variable.withString(todayStart), Variable.withString(todayStart)],
    ).getSingle();

    // Single aggregation query for returns
    final returnsRow = await customSelect(
      'SELECT COUNT(*) AS returns_count, '
      'COALESCE(SUM(total_cents), 0) AS total_returns_cents '
      'FROM sale_returns',
    ).getSingle();

    return SaleDashboardStats(
      totalCount: statsRow.read<int>('total_count'),
      completedCount: statsRow.read<int>('completed_count'),
      voidedCount: statsRow.read<int>('voided_count'),
      totalSalesCents: statsRow.read<int>('total_sales_cents'),
      returnsCount: returnsRow.read<int>('returns_count'),
      totalReturnsCents: returnsRow.read<int>('total_returns_cents'),
      todaySalesCents: statsRow.read<int>('today_sales_cents'),
      todayCount: statsRow.read<int>('today_count'),
    );
  }

  /// Watch dashboard stats
  Stream<SaleDashboardStats> watchDashboardStats() {
    return watchAllSales().asyncMap((_) => getDashboardStats());
  }

  /// Watch sale return items
  Stream<List<SaleReturnItem>> watchSaleReturnItemsList(int returnId) {
    return (select(saleReturnItems)..where((i) => i.returnId.equals(returnId))).watch();
  }

  /// Watch sale return items with full product details (name, color, size, SKU)
  Stream<List<SaleReturnItemWithDetails>> watchSaleReturnItemsWithDetails(int returnId) {
    final query = select(saleReturnItems).join([
      innerJoin(saleItems, saleItems.id.equalsExp(saleReturnItems.saleItemId)),
      innerJoin(products, products.id.equalsExp(saleItems.productId)),
      leftOuterJoin(productVariants, productVariants.id.equalsExp(saleItems.variantId)),
      leftOuterJoin(productColors, productColors.id.equalsExp(productVariants.colorId)),
      leftOuterJoin(sizes, sizes.id.equalsExp(productVariants.sizeId)),
    ])
      ..where(saleReturnItems.returnId.equals(returnId));

    return query.watch().map((rows) => rows.map((row) {
      return SaleReturnItemWithDetails(
        returnItem: row.readTable(saleReturnItems),
        product: row.readTable(products),
        variant: row.readTableOrNull(productVariants),
        colorName: row.readTableOrNull(productColors)?.name,
        colorHex: row.readTableOrNull(productColors)?.hexCode,
        sizeName: row.readTableOrNull(sizes)?.name,
      );
    }).toList());
  }

  /// Watch set of sale IDs that have at least one non-voided return
  Stream<Set<int>> watchSaleIdsWithReturns() {
    return (select(saleReturns)
          ..where((r) => r.status.equals('posted')))
        .watch()
        .map((list) => list.map((r) => r.saleId).toSet());
  }

  /// Watch returns for a specific sale
  Stream<List<SaleReturn>> watchSaleReturnsBySale(int saleId) {
    return (select(saleReturns)
          ..where((r) => r.saleId.equals(saleId))
          ..orderBy([(r) => OrderingTerm.desc(r.returnDate)]))
        .watch();
  }
}
