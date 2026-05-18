import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/batch_service.dart';
import 'package:tapix/core/services/inventory/inventory_adjustment_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

/// ────────────────────────────────────────────────────────────────────────────
/// Phase 6.3d — FIFO integration regression suite.
///
/// Covers:
///   1.  Purchase post creates a batch with FROZEN unit cost
///   2.  Sale on a FIFO product consumes oldest batch first (sub-batch order)
///   3.  Sale crossing a batch boundary produces multi-line consumption
///   4.  Sale return (linked) restores consumed batches at original cost
///   5.  Void sale restores the exact batches it consumed
///   6.  Inventory shrinkage consumes FIFO and links to adjustment id
///   7.  Inventory gain creates a new 'found' batch at current cost
///   8.  Sale Adj Return (post)  → new batch, source='sale_return'
///   9.  Sale Adj Return (void)  → consume FIFO + link to ret. item id
///   10. Purchase Adj Return  post → consume FIFO; void → mirror restore
///   11. Linked Purchase Return post → consume; void → restore
///   12. Void Purchase BLOCKS when its batch was partially consumed
///   13. WAC products: NO batch_consumptions rows are written
///   14. Invariant guard: Σ(batch.remaining)==variant.stock_quantity always
///   15. Variant isolation: selling variant A doesn't touch variant B batches
/// ────────────────────────────────────────────────────────────────────────────
void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late InventoryAdjustmentService invAdjService;
  late AdjustmentReturnDao adjReturnDao;

  late int currencyId;
  late int customerId;
  late int supplierId;

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<int> insertProduct({
    required String sku,
    required String name,
    int costCents = 1000,
    int priceCents = 2000,
    int stock = 0,
    String costingMethod = 'fifo',
    bool hasVariants = false,
  }) async {
    final pid = await db.into(db.products).insert(
          ProductsCompanion.insert(
            sku: Value(sku),
            name: name,
            costCents: Decimal.fromInt(costCents),
            priceCents: Decimal.fromInt(priceCents),
            currencyId: Value(currencyId),
            stockQuantity: Value(stock),
            hasVariants: Value(hasVariants),
          ),
        );
    // Set costing method explicitly (default in schema is 'wac')
    await db.customStatement(
      'UPDATE products SET costing_method = ? WHERE id = ?',
      [costingMethod, pid],
    );
    return pid;
  }

  Future<int> insertVariant({
    required int productId,
    int stock = 0,
    int costCents = 1000,
    int priceCents = 2000,
    int? colorId,
    int? sizeId,
  }) async {
    return db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: Value(stock),
            costCents: Decimal.fromInt(costCents),
            priceCents: Decimal.fromInt(priceCents),
            colorId: Value(colorId),
            sizeId: Value(sizeId),
          ),
        );
  }

  Future<int> postPurchase({
    required int productId,
    required int variantId,
    required int quantity,
    required int unitCostCents,
    String poNumber = 'PO-X',
  }) async {
    final purchaseId = await db.into(db.purchases).insert(
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
    await db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitCostCents: Decimal.fromInt(unitCostCents),
            subtotalCents: Decimal.fromInt(quantity * unitCostCents),
            totalCents: Decimal.fromInt(quantity * unitCostCents),
          ),
        );
    await db.purchaseDao.postPurchase(purchaseId);
    return purchaseId;
  }

  Future<int> postSale({
    required int productId,
    required int variantId,
    required int quantity,
    required int unitPriceCents,
    String invoiceNumber = 'INV-X',
  }) async {
    final saleId = await db.into(db.sales).insert(
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
    await db.into(db.saleItems).insert(
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

  Future<List<({int id, int remaining, int unitCost, String source})>>
      activeBatches({required int productId, int? variantId}) async {
    final filterVar = variantId == null ? '' : 'AND variant_id = ?';
    final vars = <Variable>[Variable.withInt(productId)];
    if (variantId != null) vars.add(Variable.withInt(variantId));
    final rows = await db.customSelect(
      'SELECT id, remaining_quantity, unit_cost_cents, source '
      '  FROM product_batches '
      ' WHERE product_id = ? $filterVar AND is_active = 1 '
      ' ORDER BY received_date ASC, id ASC',
      variables: vars,
    ).get();
    return rows
        .map((r) => (
              id: r.read<int>('id'),
              remaining: r.read<int>('remaining_quantity'),
              unitCost: r.read<int>('unit_cost_cents'),
              source: r.read<String>('source'),
            ))
        .toList();
  }

  Future<List<({String type, String direction, int qty, int unitCost})>>
      consumptionsForSale(int saleItemId) async {
    final rows = await db.customSelect(
      'SELECT consumption_type, direction, quantity, unit_cost_cents '
      '  FROM batch_consumptions '
      ' WHERE sale_item_id = ? '
      ' ORDER BY id ASC',
      variables: [Variable.withInt(saleItemId)],
    ).get();
    return rows
        .map((r) => (
              type: r.read<String>('consumption_type'),
              direction: r.read<String>('direction'),
              qty: r.read<int>('quantity'),
              unitCost: r.read<int>('unit_cost_cents'),
            ))
        .toList();
  }

  Future<int> consumptionCountForProduct(int productId) async {
    final row = await db.customSelect(
      'SELECT COUNT(*) AS cnt FROM batch_consumptions bc '
      'INNER JOIN product_batches pb ON pb.id = bc.batch_id '
      'WHERE pb.product_id = ?',
      variables: [Variable.withInt(productId)],
    ).getSingle();
    return row.read<int>('cnt');
  }

  // ─── Setup / teardown ─────────────────────────────────────────────────────

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final accounting = AccountingRepository(db);
    journal = JournalEntryService(accounting);
    invAdjService = InventoryAdjustmentService(
      db: db,
      dao: db.inventoryAdjustmentDao,
      journal: journal,
    );
    adjReturnDao = AdjustmentReturnDao(db);

    // Force DB init (seeds accounts + currencies)
    await db.customSelect('SELECT 1').get();

    // Seed system user (FK target for created_by / posted_by)
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, '
      'is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );

    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();
    currencyId = usd.id;

    customerId = await db.into(db.customers).insert(
          CustomersCompanion.insert(
            name: 'FIFO Test Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
    supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'FIFO Test Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
  });

  tearDown(() async => db.close());

  // ──────────────────────────────────────────────────────────────────────────
  // 1. PURCHASE POST → BATCH CREATION
  // ──────────────────────────────────────────────────────────────────────────
  group('Purchase post (FIFO product)', () {
    test('creates ONE batch per purchase line, FROZEN at unit cost', () async {
      final pid = await insertProduct(sku: 'F-001', name: 'F1');
      final vid = await insertVariant(productId: pid);

      await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 10,
        unitCostCents: 100,
        poNumber: 'PO-F1',
      );

      final batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches.length, equals(1));
      expect(batches.first.remaining, equals(10));
      expect(batches.first.unitCost, equals(100));
      expect(batches.first.source, equals('purchase'));

      await BatchService.assertInvariant(
        db.purchaseDao,
        productId: pid,
        variantId: vid,
      );
    });

    test('two purchases at different costs → two independent batches',
        () async {
      final pid = await insertProduct(sku: 'F-002', name: 'F2');
      final vid = await insertVariant(productId: pid);

      await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 10,
        unitCostCents: 100,
        poNumber: 'PO-F2-A',
      );
      await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 10,
        unitCostCents: 120,
        poNumber: 'PO-F2-B',
      );

      final batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches.length, equals(2));
      expect(batches[0].unitCost, equals(100));
      expect(batches[1].unitCost, equals(120));
      expect(batches.fold<int>(0, (s, b) => s + b.remaining), equals(20));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 2-3. SALE CONSUMES OLDEST FIRST, ACROSS BATCH BOUNDARIES
  // ──────────────────────────────────────────────────────────────────────────
  group('Sale on FIFO product', () {
    test('consumes the OLDEST batch first', () async {
      final pid = await insertProduct(sku: 'F-003', name: 'F3');
      final vid = await insertVariant(productId: pid);

      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          unitCostCents: 100,
          poNumber: 'PO-F3-A');
      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          unitCostCents: 120,
          poNumber: 'PO-F3-B');

      final saleId = await postSale(
        productId: pid,
        variantId: vid,
        quantity: 5,
        unitPriceCents: 200,
        invoiceNumber: 'INV-F3',
      );

      final saleItem = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(saleId)))
          .getSingle();
      final cons = await consumptionsForSale(saleItem.id);
      expect(cons.length, equals(1));
      expect(cons.first.qty, equals(5));
      expect(cons.first.unitCost, equals(100), reason: 'oldest batch first');
      expect(cons.first.direction, equals('out'));

      final batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches[0].remaining, equals(5),
          reason: 'first batch depleted by 5');
      expect(batches[1].remaining, equals(10), reason: 'newer batch untouched');

      await BatchService.assertInvariant(
        db.saleDao,
        productId: pid,
        variantId: vid,
      );
    });

    test('crossing batch boundary → multi-line consumption', () async {
      final pid = await insertProduct(sku: 'F-004', name: 'F4');
      final vid = await insertVariant(productId: pid);

      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          unitCostCents: 100,
          poNumber: 'PO-F4-A');
      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          unitCostCents: 120,
          poNumber: 'PO-F4-B');

      final saleId = await postSale(
        productId: pid,
        variantId: vid,
        quantity: 14,
        unitPriceCents: 200,
        invoiceNumber: 'INV-F4',
      );

      final saleItem = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(saleId)))
          .getSingle();
      final cons = await consumptionsForSale(saleItem.id);
      expect(cons.length, equals(2),
          reason: 'consumption spans two batches');
      expect(cons[0].qty, equals(10));
      expect(cons[0].unitCost, equals(100));
      expect(cons[1].qty, equals(4));
      expect(cons[1].unitCost, equals(120));

      // Total COGS = 10*100 + 4*120 = 1000 + 480 = 1480
      final totalCogs = cons.fold<int>(0, (s, c) => s + c.qty * c.unitCost);
      expect(totalCogs, equals(1480));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 4-5. RETURNS / VOID SALE — RESTORE ORIGINAL BATCHES AT ORIGINAL COST
  // ──────────────────────────────────────────────────────────────────────────
  group('Sale reversal restores exact batches', () {
    test('void sale restores both batches that were consumed', () async {
      final pid = await insertProduct(sku: 'F-005', name: 'F5');
      final vid = await insertVariant(productId: pid);
      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          unitCostCents: 100,
          poNumber: 'PO-F5-A');
      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          unitCostCents: 120,
          poNumber: 'PO-F5-B');

      final saleId = await postSale(
        productId: pid,
        variantId: vid,
        quantity: 14,
        unitPriceCents: 200,
        invoiceNumber: 'INV-F5',
      );

      // Sanity: 10 from b1, 4 from b2
      var batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches[0].remaining, equals(0));
      expect(batches[1].remaining, equals(6));

      await db.saleDao.voidSale(saleId);

      batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches[0].remaining, equals(10),
          reason: 'first batch fully restored');
      expect(batches[1].remaining, equals(10),
          reason: 'second batch fully restored');

      await BatchService.assertInvariant(
        db.saleDao,
        productId: pid,
        variantId: vid,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 6-7. INVENTORY ADJUSTMENTS
  // ──────────────────────────────────────────────────────────────────────────
  group('Inventory adjustments (FIFO product)', () {
    test('shrinkage consumes FIFO and links to adjustment id', () async {
      final pid = await insertProduct(sku: 'F-006', name: 'F6');
      final vid = await insertVariant(productId: pid);
      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          unitCostCents: 100,
          poNumber: 'PO-F6-A');
      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          unitCostCents: 120,
          poNumber: 'PO-F6-B');

      final result = await invAdjService.adjust(
        productId: pid,
        variantId: vid,
        type: InventoryAdjustmentType.shrinkage,
        quantityDelta: -3,
        reason: 'damage',
        currencyId: currencyId,
        userId: 0,
      );

      // FIFO consumed 3 from oldest (b1@100)
      final batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches[0].remaining, equals(7));
      expect(batches[1].remaining, equals(10));

      // Linked consumption row exists
      final rows = await db.customSelect(
        'SELECT consumption_type, direction, quantity, unit_cost_cents '
        '  FROM batch_consumptions '
        ' WHERE inventory_adjustment_id = ?',
        variables: [Variable.withInt(result.adjustmentId)],
      ).get();
      expect(rows.length, equals(1));
      expect(rows.first.read<String>('direction'), equals('out'));
      expect(rows.first.read<int>('quantity'), equals(3));
      expect(rows.first.read<int>('unit_cost_cents'), equals(100));
    });

    test('gain creates new "found" batch at current cost', () async {
      final pid = await insertProduct(
        sku: 'F-007',
        name: 'F7',
        costCents: 100,
      );
      final vid = await insertVariant(productId: pid, costCents: 100);
      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 5,
          unitCostCents: 100,
          poNumber: 'PO-F7');

      await invAdjService.adjust(
        productId: pid,
        variantId: vid,
        type: InventoryAdjustmentType.gain,
        quantityDelta: 4,
        reason: 'found in back room',
        currencyId: currencyId,
        userId: 0,
      );

      final batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches.length, equals(2));
      expect(batches.last.source, equals('found'));
      expect(batches.last.remaining, equals(4));

      await BatchService.assertInvariant(
        db.inventoryAdjustmentDao,
        productId: pid,
        variantId: vid,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 8-9. SALE ADJUSTMENT RETURN (no original invoice)
  // ──────────────────────────────────────────────────────────────────────────
  group('Sale Adjustment Return — FIFO', () {
    test('post → new batch source=sale_return; void → consume FIFO',
        () async {
      final pid = await insertProduct(sku: 'F-008', name: 'F8', costCents: 30);
      final vid = await insertVariant(productId: pid, costCents: 30);
      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          unitCostCents: 30,
          poNumber: 'PO-F8');

      final retId = await adjReturnDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-F8',
          customerId: Value(customerId),
          currencyId: currencyId,
          totalCents: Decimal.fromInt(100),
          refundMethod: const Value('credit'),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: pid,
            variantId: Value(vid),
            quantity: 2,
            unitPriceCents: Decimal.fromInt(50),
            totalCents: Decimal.fromInt(100),
          ),
        ],
      );
      await adjReturnDao.postSaleAdjReturn(
        retId,
        journalEntryService: journal,
        allowOverHistory: true,
      );

      // After post: original batch 10 + new sale_return batch 2 = 12
      var batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches.length, equals(2));
      final saleReturnBatch =
          batches.firstWhere((b) => b.source == 'sale_return');
      expect(saleReturnBatch.remaining, equals(2));
      expect(saleReturnBatch.unitCost, equals(30));

      await BatchService.assertInvariant(
        db.saleDao,
        productId: pid,
        variantId: vid,
      );

      // Now void → must consume FIFO from oldest (the original purchase batch)
      await adjReturnDao.voidSaleAdjReturn(
        retId,
        journalEntryService: journal,
      );

      batches = await activeBatches(productId: pid, variantId: vid);
      final purchaseBatch =
          batches.firstWhere((b) => b.source == 'purchase');
      expect(purchaseBatch.remaining, equals(8),
          reason: 'oldest batch consumed first on void');

      await BatchService.assertInvariant(
        db.saleDao,
        productId: pid,
        variantId: vid,
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 10. PURCHASE ADJUSTMENT RETURN (no original invoice) — mirror reversal
  // ──────────────────────────────────────────────────────────────────────────
  group('Purchase Adjustment Return — FIFO', () {
    test('post consumes FIFO; void restores SAME batches at SAME cost',
        () async {
      final pid = await insertProduct(sku: 'F-009', name: 'F9', costCents: 30);
      final vid = await insertVariant(productId: pid, costCents: 30);
      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          unitCostCents: 30,
          poNumber: 'PO-F9');

      final retId = await adjReturnDao.createPurchaseAdjReturn(
        PurchaseReturnAdjustmentsCompanion.insert(
          returnNumber: 'PAR-F9',
          supplierId: supplierId,
          currencyId: currencyId,
          totalCents: Decimal.fromInt(150),
        ),
        [
          PurchaseReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: pid,
            variantId: Value(vid),
            quantity: 3,
            unitPriceCents: Decimal.fromInt(50),
            totalCents: Decimal.fromInt(150),
          ),
        ],
      );

      await adjReturnDao.postPurchaseAdjReturn(
        retId,
        journalEntryService: journal,
        allowOverHistory: true,
      );
      var batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches.first.remaining, equals(7));

      await adjReturnDao.voidPurchaseAdjReturn(
        retId,
        journalEntryService: journal,
      );
      batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches.first.remaining, equals(10),
          reason: 'void restored exactly the same batch');
      expect(batches.first.unitCost, equals(30));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 11. LINKED PURCHASE RETURN — batch consumption + restore
  // ──────────────────────────────────────────────────────────────────────────
  group('Linked Purchase Return — FIFO', () {
    test('post consumes FIFO; void restores', () async {
      final pid = await insertProduct(sku: 'F-010', name: 'F10', costCents: 30);
      final vid = await insertVariant(productId: pid, costCents: 30);
      final purchaseId = await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 10,
        unitCostCents: 30,
        poNumber: 'PO-F10',
      );
      final purchaseItem = await (db.select(db.purchaseItems)
            ..where((i) => i.purchaseId.equals(purchaseId)))
          .getSingle();

      final retId = await db.purchaseDao.createPurchaseReturn(
        PurchaseReturnsCompanion.insert(
          returnNumber: 'PR-F10',
          purchaseId: purchaseId,
          subtotalCents: Value(Decimal.fromInt(120)),
          taxCents: Value(Decimal.zero),
          totalCents: Decimal.fromInt(120),
          currencyId: currencyId,
        ),
        [
          PurchaseReturnItemsCompanion.insert(
            returnId: 0,
            purchaseItemId: purchaseItem.id,
            quantity: 4,
            refundCents: Decimal.fromInt(120),
            subtotalCents: Value(Decimal.fromInt(120)),
          ),
        ],
      );

      await db.purchaseDao.postPurchaseReturn(retId);
      var batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches.first.remaining, equals(6));

      await db.purchaseDao.voidPurchaseReturn(retId);
      batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches.first.remaining, equals(10),
          reason: 'restored back to original');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 12. VOID PURCHASE BLOCKS WHEN PARTIALLY CONSUMED
  // ──────────────────────────────────────────────────────────────────────────
  group('Void purchase guards', () {
    test('BLOCKS when batch from this purchase has been partially consumed',
        () async {
      final pid = await insertProduct(sku: 'F-011', name: 'F11', costCents: 30);
      final vid = await insertVariant(productId: pid, costCents: 30);
      final purchaseId = await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 10,
        unitCostCents: 30,
        poNumber: 'PO-F11',
      );

      // Sell 3 → batch is partially consumed
      await postSale(
        productId: pid,
        variantId: vid,
        quantity: 3,
        unitPriceCents: 50,
        invoiceNumber: 'INV-F11',
      );

      // Now voiding the purchase MUST raise.
      expect(
        () => db.purchaseDao.voidPurchase(purchaseId),
        throwsA(isA<Exception>()),
      );
    });

    test('ALLOWS void when batch is fully untouched', () async {
      final pid = await insertProduct(sku: 'F-012', name: 'F12', costCents: 30);
      final vid = await insertVariant(productId: pid, costCents: 30);
      final purchaseId = await postPurchase(
        productId: pid,
        variantId: vid,
        quantity: 10,
        unitCostCents: 30,
        poNumber: 'PO-F12',
      );

      await db.purchaseDao.voidPurchase(purchaseId);

      final p = await db.purchaseDao.getPurchaseById(purchaseId);
      expect(p!.status, equals('voided'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 13. WAC PRODUCTS — NO BATCH CONSUMPTIONS
  // ──────────────────────────────────────────────────────────────────────────
  group('WAC products (legacy path untouched)', () {
    test('purchase + sale on WAC product writes ZERO batch_consumption rows',
        () async {
      final pid = await insertProduct(
        sku: 'W-001',
        name: 'WAC1',
        costingMethod: 'wac',
      );
      final vid = await insertVariant(productId: pid);

      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 10,
          unitCostCents: 100,
          poNumber: 'PO-W1');
      await postSale(
        productId: pid,
        variantId: vid,
        quantity: 3,
        unitPriceCents: 200,
        invoiceNumber: 'INV-W1',
      );

      // No consumption rows are written for WAC products on sale.
      expect(await consumptionCountForProduct(pid), equals(0));

      // Purchase still creates a batch row (the batch ledger is the canonical
      // source for expiry tracking, even on WAC products), but the sale must
      // NOT touch its remaining_quantity.
      final batches = await activeBatches(productId: pid, variantId: vid);
      expect(batches.length, equals(1));
      expect(batches.first.remaining, equals(10),
          reason: 'WAC sale must not deplete the batch ledger');

      // Variant stock_quantity is the source of truth for WAC: 10 - 3 = 7.
      final v = await (db.select(db.productVariants)
            ..where((x) => x.id.equals(vid)))
          .getSingle();
      expect(v.stockQuantity, equals(7));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 14. INVARIANT GUARD AFTER A LONG MIXED OPERATION SEQUENCE
  // ──────────────────────────────────────────────────────────────────────────
  group('Invariant after mixed-op sequence', () {
    test('Σ(batch.remaining) == variant.stock_quantity at every checkpoint',
        () async {
      final pid = await insertProduct(sku: 'F-013', name: 'F13', costCents: 50);
      final vid = await insertVariant(productId: pid, costCents: 50);

      // Mix of purchases / sales / shrink / gain
      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 20,
          unitCostCents: 50,
          poNumber: 'PO-F13-A');
      await postPurchase(
          productId: pid,
          variantId: vid,
          quantity: 30,
          unitCostCents: 60,
          poNumber: 'PO-F13-B');
      await BatchService.assertInvariant(db.purchaseDao,
          productId: pid, variantId: vid);

      await postSale(
        productId: pid,
        variantId: vid,
        quantity: 25,
        unitPriceCents: 100,
        invoiceNumber: 'INV-F13-A',
      );
      await BatchService.assertInvariant(db.saleDao,
          productId: pid, variantId: vid);

      await invAdjService.adjust(
        productId: pid,
        variantId: vid,
        type: InventoryAdjustmentType.shrinkage,
        quantityDelta: -2,
        reason: 'count diff',
        currencyId: currencyId,
        userId: 0,
      );
      await BatchService.assertInvariant(db.inventoryAdjustmentDao,
          productId: pid, variantId: vid);

      await invAdjService.adjust(
        productId: pid,
        variantId: vid,
        type: InventoryAdjustmentType.gain,
        quantityDelta: 5,
        reason: 'recount',
        currencyId: currencyId,
        userId: 0,
      );
      await BatchService.assertInvariant(db.inventoryAdjustmentDao,
          productId: pid, variantId: vid);

      // Final ground truth: 20 + 30 - 25 - 2 + 5 = 28
      final v = await (db.select(db.productVariants)
            ..where((x) => x.id.equals(vid)))
          .getSingle();
      expect(v.stockQuantity, equals(28));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 15. VARIANT ISOLATION
  // ──────────────────────────────────────────────────────────────────────────
  group('Variant isolation', () {
    test('selling variant A never touches variant B batches', () async {
      final pid = await insertProduct(
        sku: 'F-014',
        name: 'F14',
        costCents: 50,
        hasVariants: true,
      );
      // Insert two real (color-tagged) variants — leave NO strict-default
      // variant so accidental null-variant calls would explode loudly.
      final colorRed = await db.into(db.productColors).insert(
            ProductColorsCompanion.insert(name: 'Red'),
          );
      final colorBlue = await db.into(db.productColors).insert(
            ProductColorsCompanion.insert(name: 'Blue'),
          );
      final vA = await insertVariant(
        productId: pid,
        colorId: colorRed,
        costCents: 50,
      );
      final vB = await insertVariant(
        productId: pid,
        colorId: colorBlue,
        costCents: 50,
      );

      await postPurchase(
          productId: pid,
          variantId: vA,
          quantity: 10,
          unitCostCents: 50,
          poNumber: 'PO-F14-A');
      await postPurchase(
          productId: pid,
          variantId: vB,
          quantity: 10,
          unitCostCents: 80,
          poNumber: 'PO-F14-B');

      await postSale(
        productId: pid,
        variantId: vA,
        quantity: 4,
        unitPriceCents: 100,
        invoiceNumber: 'INV-F14',
      );

      final batchesA = await activeBatches(productId: pid, variantId: vA);
      final batchesB = await activeBatches(productId: pid, variantId: vB);
      expect(batchesA.first.remaining, equals(6));
      expect(batchesB.first.remaining, equals(10),
          reason: 'sibling variant batches must be untouched');
      expect(batchesB.first.unitCost, equals(80));

      await BatchService.assertInvariant(db.saleDao,
          productId: pid, variantId: vA);
      await BatchService.assertInvariant(db.saleDao,
          productId: pid, variantId: vB);
    });
  });
}
