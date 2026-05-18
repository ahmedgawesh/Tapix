import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/transactions.dart';
import '../tables/parties.dart';
import '../tables/products.dart';
import '../tables/people.dart';
import '../../services/stock_service.dart';
import '../../services/balance_service.dart';
import '../../services/batch_service.dart';
import '../../services/journal_entry_service.dart';

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

/// Data class for sale return joined with customer info
class SaleReturnWithParty {
  final SaleReturn saleReturn;
  final String? customerName;
  final String? customerPhone;
  final String? saleInvoiceNumber;

  SaleReturnWithParty({
    required this.saleReturn,
    this.customerName,
    this.customerPhone,
    this.saleInvoiceNumber,
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

  /// Returns `true` when the product needs **batch-level books**.
  ///
  /// Mirrors the same OR predicate used in [postSale]'s inline
  /// `consumeFromBatches` calculation: a product is FIFO/batch when its
  /// `inventory_tracking_type` is `batch`/`batch_expiry` OR the legacy
  /// `costing_method` is `fifo`. Used by I4 to gate the cross-table
  /// invariant assertion to products whose batch ledger we actually
  /// mutate — WAC products legitimately have stock without matching
  /// batch rows so an unconditional assertion would false-positive.
  Future<bool> _isFifoProduct(int productId) async {
    final row = await customSelect(
      'SELECT inventory_tracking_type, costing_method FROM products WHERE id = ?',
      variables: [Variable.withInt(productId)],
    ).getSingleOrNull();
    if (row == null) return false;
    final tracking = row.read<String?>('inventory_tracking_type');
    if (tracking == 'batch' || tracking == 'batch_expiry') return true;
    return (row.read<String?>('costing_method') ?? 'wac') == 'fifo';
  }

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

  /// Search sales by invoice number, customer name, or customer phone
  Stream<List<SaleWithCustomer>> searchSales(String query) {
    final searchQuery = '%$query%';
    final joinQuery = select(sales).join([
      leftOuterJoin(customers, customers.id.equalsExp(sales.customerId)),
      leftOuterJoin(employees, employees.id.equalsExp(sales.employeeId)),
    ])
      ..where(sales.invoiceNumber.like(searchQuery) |
          customers.name.like(searchQuery) |
          customers.phone.like(searchQuery))
      ..orderBy([OrderingTerm.desc(sales.saleDate)]);

    return joinQuery.watch().map((rows) => rows.map((row) {
          return SaleWithCustomer(
            sale: row.readTable(sales),
            customer: row.readTableOrNull(customers),
            employee: row.readTableOrNull(employees),
          );
        }).toList());
  }

  /// Watch a map of saleId → list of product search terms (name, barcode, sku)
  /// Used for smart unified search across product names/barcodes.
  Stream<Map<int, List<String>>> watchSaleProductSearchTerms() {
    final query = select(saleItems).join([
      innerJoin(products, products.id.equalsExp(saleItems.productId)),
      leftOuterJoin(productVariants, productVariants.id.equalsExp(saleItems.variantId)),
    ]);

    return query.watch().map((rows) {
      final map = <int, List<String>>{};
      for (final row in rows) {
        final item = row.readTable(saleItems);
        final product = row.readTable(products);
        final variant = row.readTableOrNull(productVariants);
        final terms = <String>[];
        terms.add(product.name);
        if (product.nameAr != null) terms.add(product.nameAr!);
        if (product.nameFr != null) terms.add(product.nameFr!);
        if (product.barcode != null) terms.add(product.barcode!);
        if (product.sku != null) terms.add(product.sku!);
        if (variant?.barcode != null) terms.add(variant!.barcode!);
        if (variant?.sku != null) terms.add(variant!.sku!);
        map.putIfAbsent(item.saleId, () => []).addAll(terms);
      }
      return map;
    });
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

  /// Update sale and replace items.
  ///
  /// I1 (defense-in-depth): only `draft`/`pending` sales may be edited.
  /// A posted/voided sale has stock movements, batch consumptions and
  /// journal entries that would silently desync if items were rewritten
  /// without re-running the post pipeline. The repository layer already
  /// gates on this, but we re-check inside the DAO so any future caller
  /// (test, script, new feature) cannot bypass the policy.
  Future<bool> updateSaleWithItems(
    int saleId,
    SalesCompanion sale,
    List<SaleItemsCompanion> items,
  ) {
    return transaction(() async {
      final existing = await (select(sales)..where((s) => s.id.equals(saleId)))
          .getSingleOrNull();
      if (existing == null) return false;
      if (existing.status != 'draft' && existing.status != 'pending') {
        throw StateError(
          'I1 violation: cannot edit a "${existing.status}" sale (#$saleId). '
          'Void it and create a new one instead.',
        );
      }

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

      // Cache per-product trackInventory once. Used everywhere below to
      // skip stock validation, stock deduction, and FIFO consumption for
      // non-tracked items (services, labor, etc.). Non-tracked products
      // still flow through GL: their sale_items.cost_cents stays 0 so COGS
      // posts as zero — matching how QuickBooks/Xero treat service items.
      final trackedProductIds = <int, bool>{};
      for (final item in items) {
        if (trackedProductIds.containsKey(item.productId)) continue;
        final row = await customSelect(
          'SELECT track_inventory FROM products WHERE id = ?',
          variables: [Variable.withInt(item.productId)],
        ).getSingleOrNull();
        trackedProductIds[item.productId] =
            (row?.read<int>('track_inventory') ?? 1) != 0;
      }

      if (!allowNegativeStock) {
        for (final item in items) {
          final variantId = item.variantId;
          final productId = item.productId;
          if (trackedProductIds[productId] == false) continue;

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

      // 2. Deduct stock (validated above) — skipped for non-tracked products.
      final affectedProductIds = <int>{};
      // I4 (Invariant I1): products whose batch ledger was actually mutated.
      // Populated inside the cost-snapshot loop below under `consumeFromBatches`.
      final batchedProductIds = <int>{};
      for (final item in items) {
        if (trackedProductIds[item.productId] == false) continue;
        affectedProductIds.add(item.productId);
        await StockService.adjustStock(this,
          productId: item.productId,
          variantId: item.variantId,
          quantity: item.quantity,
          direction: StockDirection.decrease,
        );
      }

      // 2b. Sync products.stock_quantity from variants
      for (final productId in affectedProductIds) {
        await StockService.syncProductStockFromVariants(this, productId: productId);
      }

      // 2c. Freeze unit cost onto each SaleItem for historical COGS accuracy.
      //     This snapshot must NEVER change after saving — it represents the
      //     exact cost at the moment of sale, ensuring stable profit reports.
      //
      //     Two paths:
      //       - WAC products: snapshot the current weighted-average cost from
      //         product_variants.cost_cents (or products.cost_cents).
      //       - FIFO products: feed the sale through BatchService.consumeFifo
      //         which deducts oldest batches first and freezes the *blended*
      //         cost across batches onto sale_items.cost_cents. The batch
      //         ledger keeps the per-batch breakdown for audit/COGS reports.
      for (final item in items) {
        // Non-tracked products carry no cost basis — leave sale_items.cost_cents
        // at its default of 0 so the COGS journal entry posts as zero, which
        // is the correct behaviour for services (no inventory movement).
        if (trackedProductIds[item.productId] == false) continue;

        // Phase D (two-layer inventory architecture): the consumption gate is
        // the per-product `inventory_tracking_type`. When tracking is
        // `batch` or `batch_expiry` we consume from `product_batches` (FEFO
        // ordering happens inside `BatchService.consumeFifo` via the
        // `ORDER BY (expiry_date IS NULL) ASC, expiry_date ASC, received_date
        // ASC` clause — so pharmacies/groceries get expiry-first removal for
        // free). Otherwise we snapshot the current weighted-average cost.
        //
        // Legacy fallback: rows that pre-date migration v10048 may still
        // carry `costing_method='fifo'` without an updated tracking type.
        // We OR the two signals so a freshly-restored backup is never
        // silently demoted to WAC consumption.
        final methodRow = await customSelect(
          'SELECT inventory_tracking_type, costing_method '
          'FROM products WHERE id = ?',
          variables: [Variable.withInt(item.productId)],
        ).getSingleOrNull();
        final trackingType =
            methodRow?.read<String?>('inventory_tracking_type');
        final legacyMethod =
            methodRow?.read<String?>('costing_method') ?? 'wac';
        final consumeFromBatches =
            trackingType == 'batch' ||
                trackingType == 'batch_expiry' ||
                legacyMethod == 'fifo';

        int unitCost;
        int totalCogsCents;

        if (consumeFromBatches) {
          batchedProductIds.add(item.productId);
          final consumed = await BatchService.consumeFifo(
            this,
            productId: item.productId,
            variantId: item.variantId,
            quantity: item.quantity,
            consumptionType: 'sale',
            saleItemId: item.id,
          );
          totalCogsCents = consumed.fold<int>(
            0,
            (sum, c) => sum + c.totalCostCents,
          );
          // Blended unit cost = total / qty (rounded). Used purely for the
          // snapshot column; per-batch breakdown lives in batch_consumptions.
          unitCost = item.quantity == 0
              ? 0
              : (totalCogsCents / item.quantity).round();
        } else {
          if (item.variantId != null) {
            final row = await customSelect(
              'SELECT cost_cents FROM product_variants WHERE id = ?',
              variables: [Variable.withInt(item.variantId!)],
            ).getSingleOrNull();
            unitCost = row?.read<int>('cost_cents') ?? 0;
          } else {
            final row = await customSelect(
              'SELECT cost_cents FROM products WHERE id = ?',
              variables: [Variable.withInt(item.productId)],
            ).getSingleOrNull();
            unitCost = row?.read<int>('cost_cents') ?? 0;
          }
          totalCogsCents = unitCost * item.quantity;
        }

        await customUpdate(
          'UPDATE sale_items SET cost_cents = ? WHERE id = ?',
          variables: [
            Variable.withInt(unitCost),
            Variable.withInt(item.id),
          ],
          updates: {saleItems},
          updateKind: UpdateKind.update,
        );

        // Silence unused warning when COGS journal logic isn't using it yet —
        // computeSaleCostCents already reads the snapshot above.
        // ignore: unused_local_variable
        final _ = totalCogsCents;
      }

      // 2c2. I4 (Invariant I1): assert Σ(batch.remaining) == variant.stock_quantity
      // for every product whose batch ledger was touched. Catches any silent
      // desync BEFORE the transaction commits — turns Phase A's documented
      // invariant into an enforced one.
      for (final productId in batchedProductIds) {
        await BatchService.assertInvariantForProduct(this,
            productId: productId);
      }

      // 2d. Update status
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
      await BalanceService.adjustCustomerBalance(this,
        customerId: customerId,
        deltaCents: deltaCents,
      );
    });
  }

  /// Void sale - reverse stock and customer accounting if completed.
  /// Also cascade-voids all associated returns to keep stock/accounting consistent.
  ///
  /// 2026-05-13 — accepts an optional [journalEntryService]. When provided
  /// (always true for the repository call path), the cascade reverses the
  /// linked sale-returns' journal entries before flipping their status.
  /// Without this, the cascade-voided return's GL leg stays posted while
  /// the sale's leg is reversed, producing the AR / Inventory drift
  /// reproduced in `tapix_backup_20260513_121448.db`. Existing
  /// DAO-level test callers that don't have a service may pass `null`;
  /// they keep the legacy behaviour and must reverse the JEs themselves.
  Future<void> voidSale(
    int saleId, {
    JournalEntryService? journalEntryService,
    int? userId,
  }) {
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
          // 2026-05-13 — emit the JE reversal BEFORE flipping the row's
          // status, mirroring `SaleRepositoryImpl.voidSaleReturn`. Skipped
          // when no service was injected (legacy DAO-only test path).
          if (journalEntryService != null) {
            await journalEntryService.voidJournalEntriesForSource(
              sourceTable: 'sale_returns',
              sourceId: ret.id,
              reason: 'Sale voided — cascade',
              userId: userId,
            );
          }
          // Cascade-void: when voiding the parent sale we must unwind the return
          // regardless of negative-stock policy, otherwise GL/stock/AR would
          // desynchronize. Pass true to skip the guard for this implicit flow.
          await voidSaleReturn(ret.id, allowNegativeStock: true);
        }
      }

      if (sale.status == 'completed') {
        // 1. Reverse stock
        final items = await getSaleItems(saleId);
        final voidAffectedProductIds = <int>{};
        // I4: products whose batch ledger we touch on void.
        final voidBatchedProductIds = <int>{};
        for (final item in items) {
          voidAffectedProductIds.add(item.productId);
          await StockService.adjustStock(this,
            productId: item.productId,
            variantId: item.variantId,
            quantity: item.quantity,
            direction: StockDirection.increase,
          );

          // 1a. FIFO restoration — for FIFO products, restore each batch the
          //     original sale consumed at its FROZEN unit cost so future
          //     COGS calculations stay accurate. WAC sales emit no batch_
          //     consumptions; restoreConsumptions silently no-ops for them.
          await BatchService.restoreConsumptions(
            this,
            reverseConsumptionType: 'void_sale_reverse',
            saleItemId: item.id,
          );
          if (await _isFifoProduct(item.productId)) {
            voidBatchedProductIds.add(item.productId);
          }
        }

        // 1b. Sync products.stock_quantity from variants
        for (final productId in voidAffectedProductIds) {
          await StockService.syncProductStockFromVariants(this, productId: productId);
        }

        // 1c. I4 (Invariant I1): cross-table invariant for FIFO products.
        for (final productId in voidBatchedProductIds) {
          await BatchService.assertInvariantForProduct(this,
              productId: productId);
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
          await BalanceService.adjustCustomerBalance(this,
            customerId: customerId,
            deltaCents: -netReversalCents,
          );
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
  /// Prefers the frozen cost snapshot stored on each SaleItem (set during
  /// postSale). Falls back to live product/variant cost for legacy rows
  /// that were created before the cost_cents column existed (NULL).
  Future<int> computeSaleCostCents(int saleId) async {
    final items = await getSaleItems(saleId);
    int totalCost = 0;
    for (final item in items) {
      if (item.costCents != null) {
        // Frozen cost snapshot — historically accurate
        totalCost += item.costCents!.toBigInt().toInt() * item.quantity;
      } else {
        // Legacy fallback: read current cost from product/variant
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
    }
    return totalCost;
  }

  /// Compute total cost of returned items for a sale return.
  ///
  /// Prefers the frozen cost snapshot from the original SaleItem. Falls back
  /// to live product/variant cost for legacy rows (NULL cost_cents).
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
      if (saleItem.costCents != null) {
        // Frozen cost snapshot — historically accurate
        totalCost += saleItem.costCents!.toBigInt().toInt() * returnItem.quantity;
      } else {
        // Legacy fallback: read current cost from product/variant
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

  /// Data class for sale return with party info
  /// Watch all sale returns with customer info (name, phone, invoice number)
  Stream<List<SaleReturnWithParty>> watchAllSaleReturnsWithParty() {
    final query = select(saleReturns).join([
      leftOuterJoin(sales, sales.id.equalsExp(saleReturns.saleId)),
      leftOuterJoin(customers, customers.id.equalsExp(sales.customerId)),
    ])
      ..orderBy([OrderingTerm.desc(saleReturns.returnDate)]);

    return query.watch().map((rows) => rows.map((row) {
          return SaleReturnWithParty(
            saleReturn: row.readTable(saleReturns),
            customerName: row.readTableOrNull(customers)?.name,
            customerPhone: row.readTableOrNull(customers)?.phone,
            saleInvoiceNumber: row.readTableOrNull(sales)?.invoiceNumber,
          );
        }).toList());
  }

  /// Watch all sale returns (raw, without party info)
  Stream<List<SaleReturn>> watchAllSaleReturns() {
    return (select(saleReturns)
          ..orderBy([(r) => OrderingTerm.desc(r.returnDate)]))
        .watch();
  }

  /// Watch product search terms for sale return items.
  /// Uses UNION ALL to combine linked return items and adjustment return items.
  Stream<Map<String, List<String>>> watchSaleReturnProductSearchTerms() {
    // For linked returns: join return_items → sale_items → products + variants
    final linkedQuery = select(saleReturnItems).join([
      innerJoin(saleItems, saleItems.id.equalsExp(saleReturnItems.saleItemId)),
      innerJoin(products, products.id.equalsExp(saleItems.productId)),
      leftOuterJoin(productVariants,
          productVariants.id.equalsExp(saleItems.variantId)),
    ]);

    return linkedQuery.watch().map((rows) {
      final map = <String, List<String>>{};
      for (final row in rows) {
        final item = row.readTable(saleReturnItems);
        final product = row.readTable(products);
        final variant = row.readTableOrNull(productVariants);
        final key = 'SR-${item.returnId}';
        final terms = <String>[];
        terms.add(product.name);
        if (product.nameAr != null) terms.add(product.nameAr!);
        if (product.nameFr != null) terms.add(product.nameFr!);
        if (product.barcode != null) terms.add(product.barcode!);
        if (product.sku != null) terms.add(product.sku!);
        if (variant?.barcode != null) terms.add(variant!.barcode!);
        if (variant?.sku != null) terms.add(variant!.sku!);
        map.putIfAbsent(key, () => []).addAll(terms);
      }
      return map;
    });
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

  /// Recompute and persist sale return header totals from its line items.
  /// Mirrors `PurchaseDao.updatePurchaseReturnTotals`.
  Future<void> updateSaleReturnTotals(int returnId) async {
    final totalsRow = await customSelect(
      'SELECT '
      '  COALESCE(SUM(sri.subtotal_cents), 0) AS subtotal, '
      '  COALESCE(SUM(sri.discount_cents), 0) AS discount, '
      '  COALESCE(SUM(sri.tax_cents), 0) AS tax, '
      '  COALESCE(SUM(sri.refund_cents), 0) AS total '
      'FROM sale_return_items sri '
      'WHERE sri.return_id = ?',
      variables: [Variable.withInt(returnId)],
    ).getSingle();

    final subtotalCents = totalsRow.read<int>('subtotal');
    final discountCents = totalsRow.read<int>('discount');
    final taxCents = totalsRow.read<int>('tax');
    final totalCents = totalsRow.read<int>('total');

    await customUpdate(
      'UPDATE sale_returns '
      'SET subtotal_cents = ?, discount_cents = ?, tax_cents = ?, total_cents = ? '
      'WHERE id = ?',
      variables: [
        Variable.withInt(subtotalCents),
        Variable.withInt(discountCents),
        Variable.withInt(taxCents),
        Variable.withInt(totalCents),
        Variable.withInt(returnId),
      ],
      updates: {saleReturns},
      updateKind: UpdateKind.update,
    );
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
        // I4: FIFO products whose batch ledger we restored to.
        final returnBatchedProductIds = <int>{};
        for (final row in returnItemRows) {
          final returnItem = row.readTable(saleReturnItems);
          final saleItem = row.readTable(saleItems);
          returnAffectedProductIds.add(saleItem.productId);
          await StockService.adjustStock(this,
            productId: saleItem.productId,
            variantId: saleItem.variantId,
            quantity: returnItem.quantity,
            direction: StockDirection.increase,
          );

          // FIFO restoration — for FIFO products, push the units back into
          // the exact batches they came from at the FROZEN unit cost. The
          // [upToQuantity] cap matters when only a partial quantity is
          // returned: the earliest 'out' rows are restored first so the
          // remaining 'out' rows still represent units the customer kept.
          await BatchService.restoreConsumptions(
            this,
            reverseConsumptionType: 'sale_return_reverse',
            saleItemId: saleItem.id,
            saleReturnItemId: returnItem.id,
            upToQuantity: returnItem.quantity,
          );
          if (await _isFifoProduct(saleItem.productId)) {
            returnBatchedProductIds.add(saleItem.productId);
          }
        }

        // Sync products.stock_quantity from variants
        for (final productId in returnAffectedProductIds) {
          await StockService.syncProductStockFromVariants(this, productId: productId);
        }

        // I4 (Invariant I1): cross-table invariant for FIFO products.
        for (final productId in returnBatchedProductIds) {
          await BatchService.assertInvariantForProduct(this,
              productId: productId);
        }
      }

      // ── Atomic counters: bump qty_returned_linked on each sale_item.
      //    Phase 0 hard cap — keeps the linked + adjustment counters in
      //    sync so subsequent adjustment returns can never exceed history.
      for (final row in returnItemRows) {
        final returnItem = row.readTable(saleReturnItems);
        await customStatement(
          'UPDATE sale_items '
          'SET qty_returned_linked = qty_returned_linked + ? '
          'WHERE id = ?',
          [returnItem.quantity, returnItem.saleItemId],
        );
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
          await BalanceService.adjustCustomerBalance(this,
            customerId: customerId,
            deltaCents: -refundCents,
          );
        }
      }
    });
  }

  /// Void a sale return - reverse stock and customer accounting if posted.
  /// Mirrors voidPurchaseReturn pattern.
  ///
  /// Voiding a posted sale return DECREASES stock (reverses the restoration done
  /// on post). If [allowNegativeStock] is false and current stock is insufficient
  /// to cover the reversal, the operation is rejected to match the inventory
  /// policy used by SAP / NetSuite / Odoo / QuickBooks.
  Future<void> voidSaleReturn(int returnId, {bool allowNegativeStock = false}) {
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

          // Pre-check: guard against negative stock (unless explicitly allowed).
          // We must validate ALL lines BEFORE any deduction, so a single
          // insufficient line aborts the whole void atomically.
          if (!allowNegativeStock) {
            for (final row in items) {
              final returnItem = row.readTable(saleReturnItems);
              final saleItem = row.readTable(saleItems);
              final variantId = saleItem.variantId;
              final productId = saleItem.productId;

              if (variantId != null) {
                final vRow = await customSelect(
                  'SELECT stock_quantity FROM product_variants WHERE id = ?',
                  variables: [Variable.withInt(variantId)],
                ).getSingleOrNull();
                final currentStock = vRow?.read<int>('stock_quantity') ?? 0;
                if (currentStock < returnItem.quantity) {
                  final infoRow = await customSelect(
                    'SELECT p.name AS product_name FROM products p '
                    'INNER JOIN product_variants pv ON pv.product_id = p.id '
                    'WHERE pv.id = ?',
                    variables: [Variable.withInt(variantId)],
                  ).getSingleOrNull();
                  final productName = infoRow?.read<String>('product_name') ?? 'Unknown';
                  throw Exception(
                    'Insufficient stock for "$productName" (variant #$variantId): '
                    'available $currentStock, required ${returnItem.quantity}.',
                  );
                }
              } else {
                final pRow = await customSelect(
                  'SELECT stock_quantity, name FROM products WHERE id = ?',
                  variables: [Variable.withInt(productId)],
                ).getSingleOrNull();
                final currentStock = pRow?.read<int>('stock_quantity') ?? 0;
                final productName = pRow?.read<String>('name') ?? 'Unknown';
                if (currentStock < returnItem.quantity) {
                  throw Exception(
                    'Insufficient stock for "$productName" (product #$productId): '
                    'available $currentStock, required ${returnItem.quantity}.',
                  );
                }
              }
            }
          }

          final voidReturnAffectedProductIds = <int>{};
          // I4: FIFO products whose batch ledger we touch.
          final voidReturnBatchedProductIds = <int>{};
          for (final row in items) {
            final returnItem = row.readTable(saleReturnItems);
            final saleItem = row.readTable(saleItems);
            voidReturnAffectedProductIds.add(saleItem.productId);
            await StockService.adjustStock(this,
              productId: saleItem.productId,
              variantId: saleItem.variantId,
              quantity: returnItem.quantity,
              direction: StockDirection.decrease,
            );

            // FIFO: voiding a sale return removes the units from inventory
            // again. We mirror this by deducting from the SAME batches the
            // return originally restored to (look up 'in' rows by
            // saleReturnItemId, then issue an 'out' against each batch). For
            // WAC products this is a silent no-op.
            await _reverseRestoredFifo(
              saleReturnItemId: returnItem.id,
              consumptionType: 'sale_return_void_reverse',
            );
            if (await _isFifoProduct(saleItem.productId)) {
              voidReturnBatchedProductIds.add(saleItem.productId);
            }

            // Atomic counter: decrement linked-return counter, guarded so
            // it never goes negative. If a manual data fix bypassed the
            // counter and it is already zero, we silently swallow rather
            // than failing the void (mirrors voidPurchaseReturn).
            await customStatement(
              'UPDATE sale_items SET qty_returned_linked = qty_returned_linked - ? '
              'WHERE id = ? AND qty_returned_linked >= ?',
              [returnItem.quantity, returnItem.saleItemId, returnItem.quantity],
            );
          }

          // Sync products.stock_quantity from variants
          for (final productId in voidReturnAffectedProductIds) {
            await StockService.syncProductStockFromVariants(this, productId: productId);
          }

          // I4 (Invariant I1): cross-table invariant for FIFO products.
          for (final productId in voidReturnBatchedProductIds) {
            await BatchService.assertInvariantForProduct(this,
                productId: productId);
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
            await BalanceService.adjustCustomerBalance(this,
              customerId: customerId,
              deltaCents: refundCents,
            );
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

        await BalanceService.adjustCustomerBalance(this,
          customerId: sale.customerId!,
          deltaCents: -amountCents,
        );
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

        await BalanceService.adjustCustomerBalance(this,
          customerId: sale.customerId!,
          deltaCents: amountCents,
        );
      }
    });
  }

  /// Get total returned quantity for a specific sale item.
  ///
  /// Returns the union of two history streams:
  ///   • `sale_return_items` rows where the parent `sale_returns.status != 'voided'`
  ///     (linked-return path — every non-voided draft / posted linked return).
  ///   • `sale_items.qty_returned_adjustment` — FIFO-allocated quantity that
  ///     posted **adjustment** (unlinked) returns have attributed to this
  ///     specific sale_item via `AdjustmentReturnDao._allocateSaleItemsForAdjustment`.
  ///     This counter is incremented on `postSaleAdjReturn` and decremented
  ///     on `voidSaleAdjReturn`, so it's always the current authoritative
  ///     adjustment-side total per line.
  ///
  /// Why both? Adjustment returns are not linked to a sale_item via FK
  /// (`sale_return_adjustment_items.original_invoice_id` is informational
  /// only), so the legacy SQL that only counted `sale_return_items` silently
  /// missed adjustment-return quantity. The downstream cap in
  /// `postSaleReturn` then allowed a linked return to over-return units that
  /// were already adjusted, inflating GL inventory above stock. Including
  /// the per-line adjustment counter closes that bypass at the SoT.
  Future<int> getReturnedQuantity(int saleItemId) async {
    final result = await customSelect(
      'SELECT '
      '  COALESCE(('
      '    SELECT SUM(sri.quantity) FROM sale_return_items sri '
      '    JOIN sale_returns sr ON sr.id = sri.return_id '
      "    WHERE sri.sale_item_id = ? AND sr.status != 'voided'"
      '  ), 0) '
      '  + '
      '  COALESCE(('
      '    SELECT qty_returned_adjustment FROM sale_items WHERE id = ?'
      '  ), 0) AS total',
      variables: [Variable.withInt(saleItemId), Variable.withInt(saleItemId)],
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

  /// FIFO helper: when voiding a posted sale return, reverse the 'in'
  /// (restore) consumption rows that posted the return back to their batches.
  /// We deduct each previously-restored quantity at the FROZEN unit cost so
  /// the batch ledger ends up exactly as if the return had never been posted.
  Future<void> _reverseRestoredFifo({
    required int saleReturnItemId,
    required String consumptionType,
  }) async {
    final inRows = await customSelect(
      'SELECT id, batch_id, quantity, unit_cost_cents '
      '  FROM batch_consumptions '
      ' WHERE direction = ? AND sale_return_item_id = ? '
      '   AND consumption_type = ? '
      ' ORDER BY id ASC',
      variables: [
        Variable.withString('in'),
        Variable.withInt(saleReturnItemId),
        Variable.withString('sale_return_reverse'),
      ],
    ).get();

    final now = DateTime.now().toIso8601String();
    for (final r in inRows) {
      final batchId = r.read<int>('batch_id');
      final qty = r.read<int>('quantity');
      final unitCost = r.read<int>('unit_cost_cents');

      // Optimistic guard — if the batch was somehow already depleted, skip
      // rather than letting remaining_quantity go negative.
      final updated = await customUpdate(
        'UPDATE product_batches '
        '   SET remaining_quantity = remaining_quantity - ?, updated_at = ? '
        ' WHERE id = ? AND remaining_quantity >= ?',
        variables: [
          Variable.withInt(qty),
          Variable.withString(now),
          Variable.withInt(batchId),
          Variable.withInt(qty),
        ],
        updates: {db.productBatches},
        updateKind: UpdateKind.update,
      );
      if (updated == 0) {
        throw StateError(
          'voidSaleReturn: batch=$batchId no longer holds $qty units to '
          'reverse — refusing to leave inventory and ledger desynchronised.',
        );
      }

      await customInsert(
        'INSERT INTO batch_consumptions '
        '(batch_id, consumption_type, direction, quantity, unit_cost_cents, '
        ' sale_return_item_id, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withInt(batchId),
          Variable.withString(consumptionType),
          Variable.withString('out'),
          Variable.withInt(qty),
          Variable.withInt(unitCost),
          Variable.withInt(saleReturnItemId),
          Variable.withString(now),
        ],
        updates: {db.batchConsumptions},
      );
    }
  }
}
