import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// Phase 6.4 / 6.5 — Costing-method lock + FIFO-aware expiry.
///
/// Covers the new product-form surface added in Phase 6.4:
///
///   1. setCostingMethod is unlocked while stock=0 and no consumptions exist
///   2. setCostingMethod is REFUSED with reason='has_stock' once stock>0
///   3. setCostingMethod is REFUSED with reason='has_consumptions' once a
///      sale (FIFO) has run, even if stock is later reduced to 0 — because
///      audit history is permanent
///   4. getCostingMethodLockReason returns null on a brand-new product
///   5. getProductRemainingExpiryInfo reflects depletion through sales,
///      hiding fully-consumed batches and reporting the *remaining* qty
///      (not the original purchased qty)
///   6. Mixed-batch expiry: a partially-sold lot is reported with its
///      reduced quantity, fully-sold lots disappear from the list
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late InventoryAdjustmentService invAdjService;

  late int currencyId;
  late int customerId;
  late int supplierId;

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<int> insertProduct({
    required String sku,
    required String name,
    int costCents = 1000,
    int priceCents = 2000,
    String costingMethod = 'fifo',
    bool hasVariants = false,
  }) async {
    final pid = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: Value(sku),
            name: name,
            costCents: Decimal.fromInt(costCents),
            priceCents: Decimal.fromInt(priceCents),
            currencyId: Value(currencyId),
            hasVariants: Value(hasVariants),
          ),
        );
    await db.customStatement(
      'UPDATE products SET costing_method = ? WHERE id = ?',
      [costingMethod, pid],
    );
    return pid;
  }

  Future<int> insertVariant({
    required int productId,
    int costCents = 1000,
    int priceCents = 2000,
  }) async {
    return db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            costCents: Decimal.fromInt(costCents),
            priceCents: Decimal.fromInt(priceCents),
          ),
        );
  }

  Future<int> postPurchase({
    required int productId,
    required int variantId,
    required int quantity,
    required int unitCostCents,
    DateTime? expiryDate,
    String poNumber = 'PO-X',
  }) async {
    final purchaseId = await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            purchaseNumber: poNumber,
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(quantity * unitCostCents),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(quantity * unitCostCents),
            paidAmountCents: Value(Decimal.zero),
            currencyId: currencyId,
            status: const Value('draft'),
            paymentMethod: const Value('credit'),
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
            subtotalCents: Decimal.fromInt(quantity * unitCostCents),
            totalCents: Decimal.fromInt(quantity * unitCostCents),
            expiryDate: Value(expiryDate),
          ),
        );
    await db.purchaseDao.postPurchase(purchaseId);

    // The batch row created by postPurchase doesn't carry the expiry date
    // from the purchase line — backfill it so the tests can assert against
    // the FIFO-aware expiry query.
    if (expiryDate != null) {
      await db.customStatement(
        '''
        UPDATE product_batches
           SET expiry_date = ?
         WHERE purchase_item_id = (
           SELECT id FROM purchase_items WHERE purchase_id = ? LIMIT 1
         )
        ''',
        [expiryDate.toIso8601String(), purchaseId],
      );
    }
    return purchaseId;
  }

  Future<int> postSale({
    required int productId,
    required int variantId,
    required int quantity,
    int unitPriceCents = 200,
    String invoiceNumber = 'INV-X',
  }) async {
    final saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: invoiceNumber,
            customerId: Value(customerId),
            subtotalCents: Decimal.fromInt(quantity * unitPriceCents),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(quantity * unitPriceCents),
            paidAmountCents: Value(Decimal.fromInt(quantity * unitPriceCents)),
            currencyId: currencyId,
            paymentMethod: 'cash',
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
            subtotalCents: Decimal.fromInt(quantity * unitPriceCents),
            totalCents: Decimal.fromInt(quantity * unitPriceCents),
          ),
        );
    await db.saleDao.postSale(saleId);
    return saleId;
  }

  // ─── Setup / teardown ─────────────────────────────────────────────────────

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final accounting = AccountingRepository(db);
    final journal = JournalEntryService(accounting);
    invAdjService = InventoryAdjustmentService(
      db: db,
      dao: db.inventoryAdjustmentDao,
      journal: journal,
    );

    await db.customSelect('SELECT 1').get();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, '
      'is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );

    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    currencyId = usd.id;

    customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'Phase 6.4 Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Phase 6.4 Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
  });

  tearDown(() async => db.close());

  // ──────────────────────────────────────────────────────────────────────────
  // 1-4. COSTING METHOD LOCK
  // ──────────────────────────────────────────────────────────────────────────
  group('Costing method lock', () {
    test('brand-new product (no stock, no consumptions) → unlocked', () async {
      final pid = await insertProduct(sku: 'L-001', name: 'L1');

      final reason = await db.productDao.getCostingMethodLockReason(pid);
      expect(reason, isNull);
    });

    test('setCostingMethod succeeds while unlocked', () async {
      final pid = await insertProduct(
        sku: 'L-002',
        name: 'L2',
        costingMethod: 'wac',
      );
      await insertVariant(productId: pid);

      final result = await db.productDao.setCostingMethod(
        productId: pid,
        method: 'fifo',
      );
      expect(result, isNull, reason: 'no lock reason returned on success');

      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(pid))).getSingle();
      expect(row.costingMethod, equals('fifo'));
    });

    test('locked once on-hand stock > 0 (post-purchase)', () async {
      final pid = await insertProduct(sku: 'L-003', name: 'L3');
      final vid = await insertVariant(productId: pid);

      await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 5,
        unitCostCents: 100,
        poNumber: 'PO-L3',
      );

      final reason = await db.productDao.getCostingMethodLockReason(pid);
      expect(reason, equals('has_stock'));

      final refusal = await db.productDao.setCostingMethod(
        productId: pid,
        method: 'wac',
      );
      expect(
        refusal,
        equals('has_stock'),
        reason: 'setter must refuse with the same reason',
      );

      // Persisted method must NOT have flipped despite the refused call.
      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(pid))).getSingle();
      expect(row.costingMethod, equals('fifo'));
    });

    test(
      'locked permanently once consumptions exist, even after stock returns to 0',
      () async {
        final pid = await insertProduct(sku: 'L-004', name: 'L4');
        final vid = await insertVariant(productId: pid);

        await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 5,
          unitCostCents: 100,
          poNumber: 'PO-L4',
        );

        // Sell everything → stock 0, but a batch_consumptions row exists.
        await postSale(
          productId: pid,
          variantId: vid,
          quantity: 5,
          invoiceNumber: 'INV-L4',
        );

        final reason = await db.productDao.getCostingMethodLockReason(pid);
        expect(
          reason,
          equals('has_consumptions'),
          reason: 'historical COGS must keep the method frozen',
        );

        final refusal = await db.productDao.setCostingMethod(
          productId: pid,
          method: 'wac',
        );
        expect(refusal, equals('has_consumptions'));
      },
    );

    test('inventory shrinkage also creates a consumption lock', () async {
      final pid = await insertProduct(sku: 'L-005', name: 'L5');
      final vid = await insertVariant(productId: pid);

      await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 5,
        unitCostCents: 100,
        poNumber: 'PO-L5',
      );

      await invAdjService.adjust(
        productId: pid,
        variantId: vid,
        type: InventoryAdjustmentType.shrinkage,
        quantityDelta: -5,
        reason: 'damage',
        currencyId: currencyId,
        userId: 0,
      );

      // Stock is back to 0 but the shrinkage left a consumption.
      final reason = await db.productDao.getCostingMethodLockReason(pid);
      expect(reason, equals('has_consumptions'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 5-6. FIFO-AWARE EXPIRY (the Phase 6.4 expiry-info bug fix)
  // ──────────────────────────────────────────────────────────────────────────
  group('FIFO-aware expiry info', () {
    test(
      'reports remaining qty after a partial sale (not original qty)',
      () async {
        final pid = await insertProduct(sku: 'E-001', name: 'E1');
        final vid = await insertVariant(productId: pid);
        final exp = DateTime.now().add(const Duration(days: 60));

        await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 100,
          unitCostCents: 100,
          expiryDate: exp,
          poNumber: 'PO-E1',
        );

        // Sell 88 → batch should have 12 remaining.
        await postSale(
          productId: pid,
          variantId: vid,
          quantity: 88,
          invoiceNumber: 'INV-E1',
        );

        final rows = await db.productDao.getProductRemainingExpiryInfo(pid);
        expect(rows.length, equals(1));
        expect(
          rows.first.quantity,
          equals(12),
          reason:
              'expiry info must reflect remaining_quantity, not the original 100',
        );
        // Compare on the day to avoid sub-second drift.
        expect(
          rows.first.expiryDate.toIso8601String().substring(0, 10),
          equals(exp.toIso8601String().substring(0, 10)),
        );
      },
    );

    test('fully-consumed batches are excluded; partial ones survive', () async {
      final pid = await insertProduct(sku: 'E-002', name: 'E2');
      final vid = await insertVariant(productId: pid);
      final near = DateTime.now().add(const Duration(days: 15));
      final far = DateTime.now().add(const Duration(days: 180));

      await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 5,
        unitCostCents: 100,
        expiryDate: near,
        poNumber: 'PO-E2-A',
      );
      await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 10,
        unitCostCents: 100,
        expiryDate: far,
        poNumber: 'PO-E2-B',
      );

      // Sell 7 → FIFO consumes all 5 from the near batch + 2 from the far.
      await postSale(
        productId: pid,
        variantId: vid,
        quantity: 7,
        invoiceNumber: 'INV-E2',
      );

      final rows = await db.productDao.getProductRemainingExpiryInfo(pid);
      expect(
        rows.length,
        equals(1),
        reason: 'depleted near-expiry batch must drop out of the report',
      );
      expect(
        rows.first.quantity,
        equals(8),
        reason: '10 received - 2 consumed = 8 remaining',
      );
      expect(
        rows.first.expiryDate.toIso8601String().substring(0, 10),
        equals(far.toIso8601String().substring(0, 10)),
      );
    });

    test('non-perishable batches (no expiry_date) are excluded', () async {
      final pid = await insertProduct(sku: 'E-003', name: 'E3');
      final vid = await insertVariant(productId: pid);

      await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 10,
        unitCostCents: 100,
        // expiryDate intentionally null
        poNumber: 'PO-E3',
      );

      final rows = await db.productDao.getProductRemainingExpiryInfo(pid);
      expect(
        rows,
        isEmpty,
        reason: 'batches with no expiry must not appear in the expiry list',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 7. MIGRATION SANITY — opening batches are seeded for legacy stock
  // ──────────────────────────────────────────────────────────────────────────
  group('FIFO activation migration (10044 → 10045+)', () {
    test(
      'a fresh DB has no orphaned opening batches and the schema is at 10068',
      () async {
        // The migration is exercised on every fresh in-memory DB. We assert:
        //   - schema is at the expected version (v10060 — re-prefixes legacy
        //     unlinked-sale-return batches from SR- to SAR-; v10059 added
        //     adjustment-return commission reversal)
        //   - no batch rows exist for an empty seed (sanity)
        expect(db.schemaVersion, equals(10068));

        final any = await db
            .customSelect('SELECT COUNT(*) AS c FROM product_batches')
            .getSingle();
        expect(
          any.read<int>('c'),
          equals(0),
          reason: 'no products seeded yet → no batches',
        );
      },
    );
  });
}
