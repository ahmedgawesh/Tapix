import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/inventory/product_cost_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late AdjustmentReturnDao adjustmentDao;
  late JournalEntryService journal;
  late int currencyId;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    adjustmentDao = AdjustmentReturnDao(db);
    journal = JournalEntryService(AccountingRepository(db));
    await db.customSelect('SELECT 1').get();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users '
      '(id, username, password_hash, role, is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );

    currencyId = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'WAC return supplier',
            currencyId: currencyId,
          ),
        );
  });

  tearDown(() => db.close());

  Future<({int productId, int variantId})> createWacStock({
    required int stock,
    required int cost,
  }) async {
    final productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: Value('WAC-$stock-$cost'),
            name: 'WAC return product',
            costCents: Decimal.fromInt(cost),
            priceCents: Decimal.fromInt(2000),
            currencyId: Value(currencyId),
            stockQuantity: Value(stock),
            hasVariants: const Value(true),
            costingMethod: const Value(ProductCostService.methodWac),
          ),
        );
    final variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: Value(stock),
            costCents: Decimal.fromInt(cost),
            priceCents: Decimal.fromInt(2000),
          ),
        );
    return (productId: productId, variantId: variantId);
  }

  Future<void> setVariantState(
    ({int productId, int variantId}) stock, {
    required int quantity,
    required int cost,
  }) async {
    await (db.update(
      db.productVariants,
    )..where((v) => v.id.equals(stock.variantId))).write(
      ProductVariantsCompanion(
        stockQuantity: Value(quantity),
        costCents: Value(Decimal.fromInt(cost)),
      ),
    );
    await ProductCostService.syncProductFromVariants(
      db.purchaseDao,
      productId: stock.productId,
      syncPrice: false,
    );
  }

  Future<ProductVariant> variantOf(({int productId, int variantId}) stock) {
    return (db.select(
      db.productVariants,
    )..where((v) => v.id.equals(stock.variantId))).getSingle();
  }

  test(
    'linked sale return blends frozen sale cost and void removes it',
    () async {
      final stock = await createWacStock(stock: 10, cost: 120);
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'INV-WAC-SR',
              subtotalCents: Decimal.fromInt(4000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(4000),
              paidAmountCents: Value(Decimal.fromInt(4000)),
              currencyId: currencyId,
              paymentMethod: 'cash',
              status: const Value('completed'),
            ),
          );
      final saleItemId = await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: stock.productId,
              variantId: Value(stock.variantId),
              quantity: 2,
              unitPriceCents: Decimal.fromInt(2000),
              subtotalCents: Decimal.fromInt(4000),
              totalCents: Decimal.fromInt(4000),
              costCents: Value(Decimal.fromInt(100)),
            ),
          );
      final returnId = await db.saleDao.createSaleReturn(
        SaleReturnsCompanion.insert(
          returnNumber: 'SR-WAC-1',
          saleId: saleId,
          subtotalCents: Value(Decimal.fromInt(4000)),
          totalCents: Decimal.fromInt(4000),
          currencyId: currencyId,
          refundMethod: const Value('cash'),
        ),
        [
          SaleReturnItemsCompanion.insert(
            returnId: 0,
            saleItemId: saleItemId,
            quantity: 2,
            subtotalCents: Value(Decimal.fromInt(4000)),
            refundCents: Decimal.fromInt(4000),
          ),
        ],
      );

      await db.saleDao.postSaleReturn(returnId);

      var variant = await variantOf(stock);
      expect(variant.stockQuantity, 12);
      expect(variant.costCents.toBigInt().toInt(), 117);
      final returnItem = await (db.select(
        db.saleReturnItems,
      )..where((i) => i.returnId.equals(returnId))).getSingle();
      expect(returnItem.unitCostAtPostCents!.toBigInt().toInt(), 100);
      // The commercial/original frozen cost is 2.00, but WAC rounds from
      // 12.00 before to 14.04 after. Inventory 1200 must therefore use the
      // exact pool delta 2.04 so GL remains equal to stock x current cost.
      expect(returnItem.inventoryValueAtPostCents!.toBigInt().toInt(), 204);
      expect(await db.saleDao.computeSaleReturnCostCents(returnId), 204);

      await db.saleDao.voidSaleReturn(returnId);
      variant = await variantOf(stock);
      expect(variant.stockQuantity, 10);
      expect(variant.costCents.toBigInt().toInt(), 120);
    },
  );

  test(
    'linked purchase return freezes posting WAC for reports and void',
    () async {
      final stock = await createWacStock(stock: 12, cost: 117);
      final purchaseId = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'PO-WAC-PR',
              supplierId: supplierId,
              subtotalCents: Decimal.fromInt(200),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(200),
              paidAmountCents: Value(Decimal.zero),
              currencyId: currencyId,
              paymentMethod: const Value('credit'),
              status: const Value('posted'),
            ),
          );
      final purchaseItemId = await db
          .into(db.purchaseItems)
          .insert(
            PurchaseItemsCompanion.insert(
              purchaseId: purchaseId,
              productId: stock.productId,
              variantId: Value(stock.variantId),
              quantity: 2,
              unitCostCents: Decimal.fromInt(100),
              subtotalCents: Decimal.fromInt(200),
              totalCents: Decimal.fromInt(200),
            ),
          );
      final returnId = await db.purchaseDao.createPurchaseReturn(
        PurchaseReturnsCompanion.insert(
          returnNumber: 'PR-WAC-1',
          purchaseId: purchaseId,
          subtotalCents: Value(Decimal.fromInt(200)),
          totalCents: Decimal.fromInt(200),
          currencyId: currencyId,
          refundMethod: const Value('cash'),
        ),
        [
          PurchaseReturnItemsCompanion.insert(
            returnId: 0,
            purchaseItemId: purchaseItemId,
            quantity: 2,
            subtotalCents: Value(Decimal.fromInt(200)),
            refundCents: Decimal.fromInt(200),
          ),
        ],
      );

      await db.purchaseDao.postPurchaseReturn(returnId);
      var variant = await variantOf(stock);
      expect(variant.stockQuantity, 10);
      expect(variant.costCents.toBigInt().toInt(), 117);
      final returnItem = await (db.select(
        db.purchaseReturnItems,
      )..where((i) => i.returnId.equals(returnId))).getSingle();
      expect(returnItem.unitCostAtPostCents!.toBigInt().toInt(), 117);
      expect(
        await db.purchaseDao.computePurchaseReturnInventoryCostCents(returnId),
        234,
      );

      // Simulate a later purchase/revaluation. Historical return cost must not
      // drift to the new live 148-cent WAC.
      await setVariantState(stock, quantity: 12, cost: 148);
      expect(
        await db.purchaseDao.computePurchaseReturnInventoryCostCents(returnId),
        234,
      );

      await db.purchaseDao.voidPurchaseReturn(returnId);
      variant = await variantOf(stock);
      expect(variant.stockQuantity, 14);
      expect(variant.costCents.toBigInt().toInt(), 144);
    },
  );

  test(
    'sale adjustment return uses its frozen draft cost in WAC and void',
    () async {
      final stock = await createWacStock(stock: 10, cost: 100);
      final returnId = await adjustmentDao.createSaleAdjReturn(
        SaleReturnAdjustmentsCompanion.insert(
          returnNumber: 'SAR-WAC-1',
          customerId: const Value(null),
          currencyId: currencyId,
          totalCents: Decimal.fromInt(4000),
          refundMethod: const Value('cash'),
        ),
        [
          SaleReturnAdjustmentItemsCompanion.insert(
            sourceResolution: const Value('unverified'),
            sourceResolutionReason: const Value('test fixture'),
            returnId: 0,
            productId: stock.productId,
            variantId: Value(stock.variantId),
            quantity: 2,
            unitPriceCents: Decimal.fromInt(2000),
            totalCents: Decimal.fromInt(4000),
          ),
        ],
      );

      // The item froze 100 at draft creation; WAC changed to 120 before post.
      await setVariantState(stock, quantity: 10, cost: 120);
      await adjustmentDao.postSaleAdjReturn(
        returnId,
        journalEntryService: journal,
        allowOverHistory: true,
      );

      var variant = await variantOf(stock);
      expect(variant.stockQuantity, 12);
      expect(variant.costCents.toBigInt().toInt(), 117);
      final item = await (db.select(
        db.saleReturnAdjustmentItems,
      )..where((i) => i.returnId.equals(returnId))).getSingle();
      expect(item.unitCostAtPostCents!.toBigInt().toInt(), 100);

      await adjustmentDao.voidSaleAdjReturn(
        returnId,
        journalEntryService: journal,
      );
      variant = await variantOf(stock);
      expect(variant.stockQuantity, 10);
      expect(variant.costCents.toBigInt().toInt(), 120);
    },
  );

  test(
    'purchase adjustment return freezes posting WAC and void blends it',
    () async {
      final stock = await createWacStock(stock: 12, cost: 117);
      final returnId = await adjustmentDao.createPurchaseAdjReturn(
        PurchaseReturnAdjustmentsCompanion.insert(
          returnNumber: 'PAR-WAC-1',
          supplierId: supplierId,
          currencyId: currencyId,
          totalCents: Decimal.fromInt(2000),
          refundMethod: const Value('cash'),
        ),
        [
          PurchaseReturnAdjustmentItemsCompanion.insert(
            returnId: 0,
            productId: stock.productId,
            variantId: Value(stock.variantId),
            quantity: 2,
            unitPriceCents: Decimal.fromInt(1000),
            totalCents: Decimal.fromInt(2000),
          ),
        ],
      );

      // Draft captured 117, but an outbound WAC movement must use the actual
      // posting-time average (130).
      await setVariantState(stock, quantity: 12, cost: 130);
      await adjustmentDao.postPurchaseAdjReturn(
        returnId,
        journalEntryService: journal,
        allowOverHistory: true,
      );
      var variant = await variantOf(stock);
      expect(variant.stockQuantity, 10);
      expect(variant.costCents.toBigInt().toInt(), 130);
      final item = await (db.select(
        db.purchaseReturnAdjustmentItems,
      )..where((i) => i.returnId.equals(returnId))).getSingle();
      expect(item.unitCostAtPostCents!.toBigInt().toInt(), 130);

      await setVariantState(stock, quantity: 10, cost: 148);
      await adjustmentDao.voidPurchaseAdjReturn(
        returnId,
        journalEntryService: journal,
      );
      variant = await variantOf(stock);
      expect(variant.stockQuantity, 12);
      expect(variant.costCents.toBigInt().toInt(), 145);
    },
  );
}
