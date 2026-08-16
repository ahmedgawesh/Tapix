import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/loyalty/loyalty_points_service.dart';
import 'package:tapix/core/services/unified_return_service.dart';
import 'package:tapix/core/services/return_calculation_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/customers/data/repositories/loyalty_repository_impl.dart';

/// Unified Return System integration tests.
///
/// Covers:
///   1. Mode resolution: linked vs adjustment
///   2. Price mismatch → adjustment
///   3. Quantity overflow → linked + adjustment split
///   4. FIFO allocation across multiple invoices
///   5. Sale return submission (stock, balance, journal)
///   6. Purchase return submission (stock, balance, journal)
///   7. batchId consistency across linked + adjustment records
void main() {
  late AppDatabase db;
  late UnifiedReturnService service;
  late AdjustmentReturnDao adjDao;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final accountingRepo = AccountingRepository(db);
    final journalService = JournalEntryService(accountingRepo);
    adjDao = AdjustmentReturnDao(db);
    service = UnifiedReturnService(
      db,
      db.purchaseDao,
      db.saleDao,
      adjDao,
      journalService,
      CommissionService(db.employeeDao),
      LoyaltyPointsService(
        LoyaltyRepositoryImpl(db, journalService),
        journalService,
        db,
      ),
    );

    // Force DB init (triggers beforeOpen → seeds accounts)
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() async {
    await db.close();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Future<int> getCurrencyId() async {
    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    return usd.id;
  }

  Future<int> createProduct({
    int stockQuantity = 100,
    int costCents = 5000,
    int priceCents = 10000,
    int? currencyId,
  }) async {
    currencyId ??= await getCurrencyId();
    return db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Test Product',
            costCents: Decimal.fromInt(costCents),
            priceCents: Decimal.fromInt(priceCents),
            currencyId: Value(currencyId),
            stockQuantity: Value(stockQuantity),
          ),
        );
  }

  Future<int> createVariant(
    int productId, {
    int stockQuantity = 100,
    int costCents = 5000,
    int priceCents = 10000,
  }) async {
    return db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: Value(stockQuantity),
            costCents: Decimal.fromInt(costCents),
            priceCents: Decimal.fromInt(priceCents),
          ),
        );
  }

  Future<int> createCustomer(int currencyId) async {
    return db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'Test Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
  }

  Future<int> createSupplier(int currencyId) async {
    return db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Test Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
  }

  /// Create and post a sale with the given qty and price.
  Future<int> createPostedSale({
    required int customerId,
    required int productId,
    required int variantId,
    required int currencyId,
    int quantity = 5,
    int unitPriceCents = 10000,
  }) async {
    final total = quantity * unitPriceCents;
    final saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-${DateTime.now().microsecondsSinceEpoch}',
            customerId: Value(customerId),
            subtotalCents: Decimal.fromInt(total),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(total),
            currencyId: currencyId,
            paymentMethod: 'cash',
            paidAmountCents: Value(Decimal.fromInt(total)),
            status: const Value('draft'),
          ),
        );

    await db
        .into(db.saleItems)
        .insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitPriceCents: Decimal.fromInt(unitPriceCents),
            subtotalCents: Decimal.fromInt(total),
            totalCents: Decimal.fromInt(total),
          ),
        );

    await db.saleDao.postSale(saleId);
    return saleId;
  }

  /// Create and post a purchase with the given qty and cost.
  Future<int> createPostedPurchase({
    required int supplierId,
    required int productId,
    required int variantId,
    required int currencyId,
    int quantity = 10,
    int unitCostCents = 5000,
  }) async {
    final total = quantity * unitCostCents;
    final purchaseId = await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PUR-${DateTime.now().microsecondsSinceEpoch}',
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(total),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(total),
            currencyId: currencyId,
            paymentMethod: const Value('cash'),
            paidAmountCents: Value(Decimal.fromInt(total)),
            status: const Value('draft'),
          ),
        );

    await db
        .into(db.purchaseItems)
        .insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitCostCents: Decimal.fromInt(unitCostCents),
            subtotalCents: Decimal.fromInt(total),
            totalCents: Decimal.fromInt(total),
          ),
        );

    await db.purchaseDao.postPurchase(purchaseId);
    return purchaseId;
  }

  Future<int> createFractionalSale({
    required int customerId,
    required int productId,
    required int variantId,
    required int currencyId,
    required int quantity,
    required int unitPriceCents,
    required int subtotalCents,
    required int discountCents,
    required int taxCents,
    required int totalCents,
    bool taxInclusive = false,
  }) async {
    final saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-FR-${DateTime.now().microsecondsSinceEpoch}',
            customerId: Value(customerId),
            subtotalCents: Decimal.fromInt(subtotalCents),
            discountCents: Value(Decimal.fromInt(discountCents)),
            taxCents: Decimal.fromInt(taxCents),
            totalCents: Decimal.fromInt(totalCents),
            currencyId: currencyId,
            paymentMethod: 'cash',
            paidAmountCents: Value(Decimal.fromInt(totalCents)),
            status: const Value('draft'),
            taxInclusiveAtPost: Value(taxInclusive),
          ),
        );
    await db
        .into(db.saleItems)
        .insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitPriceCents: Decimal.fromInt(unitPriceCents),
            subtotalCents: Decimal.fromInt(subtotalCents),
            discountCents: Value(Decimal.fromInt(discountCents)),
            taxCents: Value(Decimal.fromInt(taxCents)),
            totalCents: Decimal.fromInt(totalCents),
          ),
        );
    await db.saleDao.postSale(saleId);
    return saleId;
  }

  Future<int> createFractionalPurchase({
    required int supplierId,
    required int productId,
    required int variantId,
    required int currencyId,
    required int quantity,
    required int unitCostCents,
    required int subtotalCents,
    required int discountCents,
    required int taxCents,
    required int totalCents,
    bool taxInclusive = false,
  }) async {
    final purchaseId = await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PUR-FR-${DateTime.now().microsecondsSinceEpoch}',
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(subtotalCents),
            discountCents: Value(Decimal.fromInt(discountCents)),
            taxCents: Decimal.fromInt(taxCents),
            totalCents: Decimal.fromInt(totalCents),
            currencyId: currencyId,
            paymentMethod: const Value('cash'),
            paidAmountCents: Value(Decimal.fromInt(totalCents)),
            status: const Value('draft'),
            taxInclusiveAtPost: Value(taxInclusive),
          ),
        );
    await db
        .into(db.purchaseItems)
        .insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitCostCents: Decimal.fromInt(unitCostCents),
            subtotalCents: Decimal.fromInt(subtotalCents),
            discountCents: Value(Decimal.fromInt(discountCents)),
            taxCents: Value(Decimal.fromInt(taxCents)),
            totalCents: Decimal.fromInt(totalCents),
          ),
        );
    await db.purchaseDao.postPurchase(purchaseId);
    return purchaseId;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST 1: resolveLineItem — Price Match → Linked
  // ═══════════════════════════════════════════════════════════════════════════
  group('resolveLineItem — Mode Resolution', () {
    test('price match with available qty → linked mode', () async {
      final cid = await getCurrencyId();
      final pid = await createProduct(currencyId: cid);
      final vid = await createVariant(pid);
      final customerId = await createCustomer(cid);

      await createPostedSale(
        customerId: customerId,
        productId: pid,
        variantId: vid,
        currencyId: cid,
        quantity: 5,
        unitPriceCents: 10000,
      );

      final result = await service.resolveLineItem(
        productId: pid,
        variantId: vid,
        productName: 'Test Product',
        quantity: 3,
        unitPriceCents: 10000, // Exact match
        side: ReturnSide.sale,
        partyId: customerId,
      );

      expect(result.length, equals(1));
      expect(result[0].mode, equals(ReturnMode.linked));
      expect(result[0].modeReason, equals(ReturnModeReason.priceMatch));
      expect(result[0].quantity, equals(3));
      expect(result[0].linkedAllocations, isNotEmpty);
    });

    test('price mismatch → adjustment mode', () async {
      final cid = await getCurrencyId();
      final pid = await createProduct(currencyId: cid);
      final vid = await createVariant(pid);
      final customerId = await createCustomer(cid);

      await createPostedSale(
        customerId: customerId,
        productId: pid,
        variantId: vid,
        currencyId: cid,
        quantity: 5,
        unitPriceCents: 10000,
      );

      final result = await service.resolveLineItem(
        productId: pid,
        variantId: vid,
        productName: 'Test Product',
        quantity: 2,
        unitPriceCents: 9500, // Different price
        side: ReturnSide.sale,
        partyId: customerId,
      );

      expect(result.length, equals(1));
      expect(result[0].mode, equals(ReturnMode.adjustment));
      expect(result[0].modeReason, equals(ReturnModeReason.priceMismatch));
    });

    test('no invoice history → adjustment mode', () async {
      final cid = await getCurrencyId();
      final pid = await createProduct(currencyId: cid);
      final vid = await createVariant(pid);
      final customerId = await createCustomer(cid);
      // No sales created — no invoice history

      final result = await service.resolveLineItem(
        productId: pid,
        variantId: vid,
        productName: 'Test Product',
        quantity: 1,
        unitPriceCents: 10000,
        side: ReturnSide.sale,
        partyId: customerId,
      );

      expect(result.length, equals(1));
      expect(result[0].mode, equals(ReturnMode.adjustment));
      expect(result[0].modeReason, equals(ReturnModeReason.noInvoiceHistory));
    });

    test('quantity overflow → linked + adjustment split', () async {
      final cid = await getCurrencyId();
      final pid = await createProduct(currencyId: cid);
      final vid = await createVariant(pid);
      final customerId = await createCustomer(cid);

      // Sell 3 units
      await createPostedSale(
        customerId: customerId,
        productId: pid,
        variantId: vid,
        currencyId: cid,
        quantity: 3,
        unitPriceCents: 10000,
      );

      // Try to return 5 (only 3 available on invoice)
      final result = await service.resolveLineItem(
        productId: pid,
        variantId: vid,
        productName: 'Test Product',
        quantity: 5,
        unitPriceCents: 10000,
        side: ReturnSide.sale,
        partyId: customerId,
      );

      expect(
        result.length,
        equals(2),
        reason: 'Should split into linked + adjustment',
      );

      final linked = result.firstWhere((r) => r.mode == ReturnMode.linked);
      final adjustment = result.firstWhere(
        (r) => r.mode == ReturnMode.adjustment,
      );

      expect(
        linked.quantity,
        equals(3),
        reason: 'Linked qty = available on invoice',
      );
      expect(linked.modeReason, equals(ReturnModeReason.priceMatch));
      expect(linked.linkedAllocations, isNotEmpty);

      expect(adjustment.quantity, equals(2), reason: 'Overflow = 5 - 3');
      expect(adjustment.modeReason, equals(ReturnModeReason.quantityOverflow));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST 2: FIFO allocation across multiple invoices
  // ═══════════════════════════════════════════════════════════════════════════
  group('FIFO allocation', () {
    test('allocates across multiple invoices in FIFO order', () async {
      final cid = await getCurrencyId();
      final pid = await createProduct(currencyId: cid, stockQuantity: 200);
      final vid = await createVariant(pid, stockQuantity: 200);
      final customerId = await createCustomer(cid);

      // Invoice 1: 3 units
      await createPostedSale(
        customerId: customerId,
        productId: pid,
        variantId: vid,
        currencyId: cid,
        quantity: 3,
        unitPriceCents: 10000,
      );

      // Small delay to ensure different timestamps
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Invoice 2: 4 units
      await createPostedSale(
        customerId: customerId,
        productId: pid,
        variantId: vid,
        currencyId: cid,
        quantity: 4,
        unitPriceCents: 10000,
      );

      // Try to return 6 — should take 3 from inv1, 3 from inv2
      final result = await service.resolveLineItem(
        productId: pid,
        variantId: vid,
        productName: 'Test Product',
        quantity: 6,
        unitPriceCents: 10000,
        side: ReturnSide.sale,
        partyId: customerId,
      );

      expect(result.length, equals(1), reason: 'All 6 fit in linked');
      expect(result[0].mode, equals(ReturnMode.linked));
      expect(
        result[0].linkedAllocations.length,
        equals(2),
        reason: 'Should allocate across 2 invoices',
      );

      final totalAllocated = result[0].linkedAllocations.fold<int>(
        0,
        (sum, a) => sum + a.quantity,
      );
      expect(totalAllocated, equals(6));
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST 3: Sale return submission
  // ═══════════════════════════════════════════════════════════════════════════
  group('submitSaleReturn', () {
    test(
      'linked sale return creates return record and returns batchId',
      () async {
        final cid = await getCurrencyId();
        final pid = await createProduct(currencyId: cid);
        final vid = await createVariant(pid);
        final customerId = await createCustomer(cid);

        await createPostedSale(
          customerId: customerId,
          productId: pid,
          variantId: vid,
          currencyId: cid,
          quantity: 5,
          unitPriceCents: 10000,
        );

        // Resolve items
        final resolved = await service.resolveLineItem(
          productId: pid,
          variantId: vid,
          productName: 'Test Product',
          quantity: 2,
          unitPriceCents: 10000,
          side: ReturnSide.sale,
          partyId: customerId,
        );

        expect(resolved[0].mode, equals(ReturnMode.linked));

        final batchId = await service.submitSaleReturn(
          customerId: customerId,
          currencyId: cid,
          items: resolved,
          refundMethod: 'cash',
          notes: 'Test return',
        );

        expect(batchId, isNotEmpty, reason: 'batchId must be a valid UUID');
      },
    );

    test('adjustment sale return creates adj record', () async {
      final cid = await getCurrencyId();
      final pid = await createProduct(currencyId: cid);
      final vid = await createVariant(pid);
      final customerId = await createCustomer(cid);
      // No invoice → forces adjustment

      final resolved = await service.resolveLineItem(
        productId: pid,
        variantId: vid,
        productName: 'Test Product',
        quantity: 1,
        unitPriceCents: 10000,
        side: ReturnSide.sale,
        partyId: customerId,
      );

      expect(resolved[0].mode, equals(ReturnMode.adjustment));

      final batchId = await service.submitSaleReturn(
        customerId: customerId,
        currencyId: cid,
        items: resolved,
        refundMethod: 'credit',
        // No sale history in this test fixture — bypass Phase-0 cap.
        allowOverHistory: true,
      );

      expect(batchId, isNotEmpty);
    });

    test('empty items throws exception', () async {
      final cid = await getCurrencyId();
      final customerId = await createCustomer(cid);

      expect(
        () => service.submitSaleReturn(
          customerId: customerId,
          currencyId: cid,
          items: [],
          refundMethod: 'cash',
        ),
        throwsException,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST 4: Purchase return submission
  // ═══════════════════════════════════════════════════════════════════════════
  group('submitPurchaseReturn', () {
    test('linked purchase return creates return record', () async {
      final cid = await getCurrencyId();
      final pid = await createProduct(currencyId: cid);
      final vid = await createVariant(pid);
      final supplierId = await createSupplier(cid);

      await createPostedPurchase(
        supplierId: supplierId,
        productId: pid,
        variantId: vid,
        currencyId: cid,
        quantity: 10,
        unitCostCents: 5000,
      );

      final resolved = await service.resolveLineItem(
        productId: pid,
        variantId: vid,
        productName: 'Test Product',
        quantity: 3,
        unitPriceCents: 5000,
        side: ReturnSide.purchase,
        partyId: supplierId,
      );

      expect(resolved[0].mode, equals(ReturnMode.linked));

      final batchId = await service.submitPurchaseReturn(
        supplierId: supplierId,
        currencyId: cid,
        items: resolved,
        refundMethod: 'credit',
      );

      expect(batchId, isNotEmpty);
    });

    test('adjustment purchase return creates adj record', () async {
      final cid = await getCurrencyId();
      final pid = await createProduct(currencyId: cid);
      final vid = await createVariant(pid);
      final supplierId = await createSupplier(cid);
      // No purchase → forces adjustment

      final resolved = await service.resolveLineItem(
        productId: pid,
        variantId: vid,
        productName: 'Test Product',
        quantity: 2,
        unitPriceCents: 5000,
        side: ReturnSide.purchase,
        partyId: supplierId,
      );

      expect(resolved[0].mode, equals(ReturnMode.adjustment));

      final batchId = await service.submitPurchaseReturn(
        supplierId: supplierId,
        currencyId: cid,
        items: resolved,
        refundMethod: 'credit',
        // No purchase history in this test fixture — bypass Phase-0 cap.
        allowOverHistory: true,
      );

      expect(batchId, isNotEmpty);
    });

    test(
      'overflow purchase return creates both linked and adjustment',
      () async {
        final cid = await getCurrencyId();
        final pid = await createProduct(currencyId: cid);
        final vid = await createVariant(pid);
        final supplierId = await createSupplier(cid);

        // Purchase 5 units
        await createPostedPurchase(
          supplierId: supplierId,
          productId: pid,
          variantId: vid,
          currencyId: cid,
          quantity: 5,
          unitCostCents: 5000,
        );

        // Return 8 (5 linked + 3 overflow)
        final resolved = await service.resolveLineItem(
          productId: pid,
          variantId: vid,
          productName: 'Test Product',
          quantity: 8,
          unitPriceCents: 5000,
          side: ReturnSide.purchase,
          partyId: supplierId,
        );

        expect(resolved.length, equals(2));

        final batchId = await service.submitPurchaseReturn(
          supplierId: supplierId,
          currencyId: cid,
          items: resolved,
          refundMethod: 'credit',
          // The overflow 3 units have no invoice backing — bypass Phase-0 cap.
          allowOverHistory: true,
        );

        expect(
          batchId,
          isNotEmpty,
          reason: 'batchId must be returned for both linked + adjustment',
        );
      },
    );
  });

  group('linked return cent preservation and tax snapshots', () {
    test('three sequential sale returns reverse every original cent', () async {
      final cid = await getCurrencyId();
      final pid = await createProduct(currencyId: cid, stockQuantity: 20);
      final vid = await createVariant(pid, stockQuantity: 20);
      final customerId = await createCustomer(cid);
      final saleId = await createFractionalSale(
        customerId: customerId,
        productId: pid,
        variantId: vid,
        currencyId: cid,
        quantity: 3,
        unitPriceCents: 34,
        subtotalCents: 100,
        discountCents: 10,
        taxCents: 14,
        totalCents: 104,
      );

      for (var index = 0; index < 3; index++) {
        final resolved = await service.resolveLineItem(
          productId: pid,
          variantId: vid,
          productName: 'Test Product',
          quantity: 1,
          unitPriceCents: 34,
          side: ReturnSide.sale,
          partyId: customerId,
        );
        expect(resolved.single.mode, ReturnMode.linked);
        await service.submitSaleReturn(
          customerId: customerId,
          currencyId: cid,
          items: resolved,
          refundMethod: 'cash',
        );
      }

      final row = await db
          .customSelect(
            'SELECT SUM(sri.subtotal_cents) AS subtotal, '
            'SUM(sri.discount_cents) AS discount, '
            'SUM(sri.tax_cents) AS tax, '
            'SUM(sri.refund_cents) AS refund '
            'FROM sale_return_items sri '
            'JOIN sale_returns sr ON sr.id = sri.return_id '
            "WHERE sr.sale_id = ? AND sr.status != 'voided'",
            variables: [Variable.withInt(saleId)],
          )
          .getSingle();
      expect(row.read<int>('subtotal'), 100);
      expect(row.read<int>('discount'), 10);
      expect(row.read<int>('tax'), 14);
      expect(row.read<int>('refund'), 104);
    });

    test(
      'three sequential purchase returns reverse every original cent',
      () async {
        final cid = await getCurrencyId();
        final pid = await createProduct(currencyId: cid, stockQuantity: 20);
        final vid = await createVariant(pid, stockQuantity: 20);
        final supplierId = await createSupplier(cid);
        final purchaseId = await createFractionalPurchase(
          supplierId: supplierId,
          productId: pid,
          variantId: vid,
          currencyId: cid,
          quantity: 3,
          unitCostCents: 34,
          subtotalCents: 100,
          discountCents: 10,
          taxCents: 14,
          totalCents: 104,
        );

        for (var index = 0; index < 3; index++) {
          final resolved = await service.resolveLineItem(
            productId: pid,
            variantId: vid,
            productName: 'Test Product',
            quantity: 1,
            unitPriceCents: 34,
            side: ReturnSide.purchase,
            partyId: supplierId,
          );
          expect(resolved.single.mode, ReturnMode.linked);
          await service.submitPurchaseReturn(
            supplierId: supplierId,
            currencyId: cid,
            items: resolved,
            refundMethod: 'credit',
          );
        }

        final row = await db
            .customSelect(
              'SELECT SUM(pri.subtotal_cents) AS subtotal, '
              'SUM(pri.discount_cents) AS discount, '
              'SUM(pri.tax_cents) AS tax, '
              'SUM(pri.refund_cents) AS refund '
              'FROM purchase_return_items pri '
              'JOIN purchase_returns pr ON pr.id = pri.return_id '
              "WHERE pr.purchase_id = ? AND pr.status != 'voided'",
              variables: [Variable.withInt(purchaseId)],
            )
            .getSingle();
        expect(row.read<int>('subtotal'), 100);
        expect(row.read<int>('discount'), 10);
        expect(row.read<int>('tax'), 14);
        expect(row.read<int>('refund'), 104);
      },
    );

    test(
      'inclusive sale and purchase return tax without adding it twice',
      () async {
        final cid = await getCurrencyId();

        final salePid = await createProduct(currencyId: cid, stockQuantity: 5);
        final saleVid = await createVariant(salePid, stockQuantity: 5);
        final customerId = await createCustomer(cid);
        final saleId = await createFractionalSale(
          customerId: customerId,
          productId: salePid,
          variantId: saleVid,
          currencyId: cid,
          quantity: 1,
          unitPriceCents: 11500,
          subtotalCents: 11500,
          discountCents: 0,
          taxCents: 1500,
          totalCents: 11500,
          taxInclusive: true,
        );
        final saleResolved = await service.resolveLineItem(
          productId: salePid,
          variantId: saleVid,
          productName: 'Sale Product',
          quantity: 1,
          unitPriceCents: 11500,
          side: ReturnSide.sale,
          partyId: customerId,
        );
        await service.submitSaleReturn(
          customerId: customerId,
          currencyId: cid,
          items: saleResolved,
          refundMethod: 'cash',
        );
        final saleReturn = await (db.select(
          db.saleReturns,
        )..where((row) => row.saleId.equals(saleId))).getSingle();
        expect(saleReturn.taxCents.toBigInt().toInt(), 1500);
        expect(saleReturn.totalCents.toBigInt().toInt(), 11500);
        expect(saleReturn.taxInclusiveAtPost, isTrue);

        final purchasePid = await createProduct(
          currencyId: cid,
          stockQuantity: 5,
        );
        final purchaseVid = await createVariant(purchasePid, stockQuantity: 5);
        final supplierId = await createSupplier(cid);
        final purchaseId = await createFractionalPurchase(
          supplierId: supplierId,
          productId: purchasePid,
          variantId: purchaseVid,
          currencyId: cid,
          quantity: 1,
          unitCostCents: 11500,
          subtotalCents: 11500,
          discountCents: 0,
          taxCents: 1500,
          totalCents: 11500,
          taxInclusive: true,
        );
        final purchaseResolved = await service.resolveLineItem(
          productId: purchasePid,
          variantId: purchaseVid,
          productName: 'Purchase Product',
          quantity: 1,
          unitPriceCents: 11500,
          side: ReturnSide.purchase,
          partyId: supplierId,
        );
        await service.submitPurchaseReturn(
          supplierId: supplierId,
          currencyId: cid,
          items: purchaseResolved,
          refundMethod: 'credit',
        );
        final purchaseReturn = await (db.select(
          db.purchaseReturns,
        )..where((row) => row.purchaseId.equals(purchaseId))).getSingle();
        expect(purchaseReturn.taxCents.toBigInt().toInt(), 1500);
        expect(purchaseReturn.totalCents.toBigInt().toInt(), 11500);
        expect(purchaseReturn.taxInclusiveAtPost, isTrue);
      },
    );

    test('adjustment amount stays outside linked invoice allocation', () async {
      final cid = await getCurrencyId();
      final pid = await createProduct(currencyId: cid, stockQuantity: 20);
      final vid = await createVariant(pid, stockQuantity: 20);
      final customerId = await createCustomer(cid);
      final saleId = await createFractionalSale(
        customerId: customerId,
        productId: pid,
        variantId: vid,
        currencyId: cid,
        quantity: 3,
        unitPriceCents: 34,
        subtotalCents: 100,
        discountCents: 10,
        taxCents: 14,
        totalCents: 104,
      );

      final adjustment = await service.resolveLineItem(
        productId: pid,
        variantId: vid,
        productName: 'Test Product',
        quantity: 1,
        unitPriceCents: 50,
        side: ReturnSide.sale,
        partyId: customerId,
      );
      expect(adjustment.single.mode, ReturnMode.adjustment);
      await service.submitSaleReturn(
        customerId: customerId,
        currencyId: cid,
        items: adjustment,
        refundMethod: 'cash',
      );

      final linked = await service.resolveLineItem(
        productId: pid,
        variantId: vid,
        productName: 'Test Product',
        quantity: 2,
        unitPriceCents: 34,
        side: ReturnSide.sale,
        partyId: customerId,
      );
      expect(linked.single.mode, ReturnMode.linked);
      await service.submitSaleReturn(
        customerId: customerId,
        currencyId: cid,
        items: linked,
        refundMethod: 'cash',
      );

      final row = await db
          .customSelect(
            'SELECT SUM(sri.subtotal_cents) AS subtotal, '
            'SUM(sri.discount_cents) AS discount, '
            'SUM(sri.tax_cents) AS tax, '
            'SUM(sri.refund_cents) AS refund '
            'FROM sale_return_items sri '
            'JOIN sale_returns sr ON sr.id = sri.return_id '
            "WHERE sr.sale_id = ? AND sr.status != 'voided'",
            variables: [Variable.withInt(saleId)],
          )
          .getSingle();
      expect(row.read<int>('subtotal'), 66);
      expect(row.read<int>('discount'), 6);
      expect(row.read<int>('tax'), 9);
      expect(row.read<int>('refund'), 69);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════════
  // TEST 5: ReturnCalculationService proportional math
  // ═══════════════════════════════════════════════════════════════════════════
  group('ReturnCalculationService', () {
    test('proportional return for partial quantity', () {
      final result = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 10,
        returnQuantity: 3,
        originalSubtotalCents: 100000, // 1000.00
        originalDiscountCents: 10000, // 100.00
        originalTaxCents: 15000, // 150.00
      );

      // 3/10 of each
      expect(result.subtotalCents, equals(30000));
      expect(result.discountCents, equals(3000));
      expect(result.taxCents, equals(4500));
      expect(result.refundCents, equals(30000 - 3000 + 4500));
    });

    test('full quantity return equals original totals', () {
      final result = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 5,
        returnQuantity: 5,
        originalSubtotalCents: 50000,
        originalDiscountCents: 5000,
        originalTaxCents: 7500,
      );

      expect(result.subtotalCents, equals(50000));
      expect(result.discountCents, equals(5000));
      expect(result.taxCents, equals(7500));
      expect(result.refundCents, equals(50000 - 5000 + 7500));
    });

    test('single unit return', () {
      final result = ReturnCalculationService.computeProportionalReturn(
        originalQuantity: 3,
        returnQuantity: 1,
        originalSubtotalCents: 30000,
        originalDiscountCents: 3000,
        originalTaxCents: 4500,
      );

      // 1/3 of each
      expect(result.subtotalCents, equals(10000));
      expect(result.discountCents, equals(1000));
      expect(result.taxCents, equals(1500));
    });
  });
}
