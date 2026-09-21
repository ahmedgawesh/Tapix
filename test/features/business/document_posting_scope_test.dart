import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/business/document_posting_scope.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late AdjustmentReturnDao adjustments;
  late int currency;
  late int customer;
  late int supplier;
  late int product;
  late int variant;
  int? otherVariant;
  int sequence = 0;
  var explicitVariant = false;

  Future<int> insert(
    String table,
    Map<String, Object?> values,
  ) => db.customInsert(
    'INSERT INTO $table (${values.keys.join(', ')}) VALUES (${List.filled(values.length, '?').join(', ')})',
    variables: values.values
        .map(
          (v) => switch (v) {
            int n => Variable.withInt(n),
            String s => Variable.withString(s),
            _ => const Variable<int>(null),
          },
        )
        .toList(),
  );

  setUp(() async {
    db = fixtures.memoryDb();
    journal = JournalEntryService(AccountingRepository(db));
    adjustments = AdjustmentReturnDao(db);
    currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    customer = await insert('customers', {
      'name': 'Customer',
      'currency_id': currency,
    });
    supplier = await insert('suppliers', {
      'name': 'Supplier',
      'currency_id': currency,
    });
    otherVariant = null;
  });
  tearDown(() => db.close());

  Future<void> seedProduct(bool hasVariants) async {
    explicitVariant = hasVariants;
    product = await insert('products', {
      'name': 'Matrix product',
      'has_variants': hasVariants ? 1 : 0,
      'currency_id': currency,
      'stock_quantity': hasVariants ? 50 : 20,
      'cost_cents': 500,
      'price_cents': 1000,
    });
    final size = await insert('sizes', {'name': 'Original size'});
    // A simple product may also have an optional size: NULL on the document
    // must still resolve its sole operational row correctly.
    variant = await insert('product_variants', {
      'product_id': product,
      'size_id': size,
      'stock_quantity': 20,
      'cost_cents': 500,
      'price_cents': 1000,
    });
    if (hasVariants) {
      final secondSize = await insert('sizes', {'name': 'Other size'});
      otherVariant = await insert('product_variants', {
        'product_id': product,
        'size_id': secondSize,
        'stock_quantity': 30,
        'cost_cents': 800,
        'price_cents': 1200,
      });
    }
  }

  Future<void> post(InventoryPostingDocument kind, int id) => switch (kind) {
    InventoryPostingDocument.sale => db.saleDao.postSale(id),
    InventoryPostingDocument.purchase => db.purchaseDao.postPurchase(id),
    InventoryPostingDocument.saleReturn => db.saleDao.postSaleReturn(id),
    InventoryPostingDocument.purchaseReturn =>
      db.purchaseDao.postPurchaseReturn(id),
    InventoryPostingDocument.saleAdjustment => adjustments.postSaleAdjReturn(
      id,
      journalEntryService: journal,
      allowOverHistory: true,
    ),
    InventoryPostingDocument.purchaseAdjustment =>
      adjustments.postPurchaseAdjReturn(
        id,
        journalEntryService: journal,
        allowOverHistory: true,
      ),
  };

  Future<void> undo(InventoryPostingDocument kind, int id) => switch (kind) {
    InventoryPostingDocument.sale => db.saleDao.voidSale(id),
    InventoryPostingDocument.purchase => db.purchaseDao.voidPurchase(id),
    InventoryPostingDocument.saleReturn => db.saleDao.voidSaleReturn(id),
    InventoryPostingDocument.purchaseReturn =>
      db.purchaseDao.voidPurchaseReturn(id),
    InventoryPostingDocument.saleAdjustment => adjustments.voidSaleAdjReturn(
      id,
      journalEntryService: journal,
    ),
    InventoryPostingDocument.purchaseAdjustment =>
      adjustments.voidPurchaseAdjReturn(id, journalEntryService: journal),
  };

  Future<int> create(
    InventoryPostingDocument kind, {
    int itemDiscount = 100,
    int invoiceDiscount = 100,
  }) async {
    final linked = switch (kind) {
      InventoryPostingDocument.saleReturn => InventoryPostingDocument.sale,
      InventoryPostingDocument.purchaseReturn =>
        InventoryPostingDocument.purchase,
      _ => null,
    };
    int? originalId;
    int? originalItem;
    if (linked != null) {
      originalId = await create(
        linked,
        itemDiscount: itemDiscount,
        invoiceDiscount: invoiceDiscount,
      );
      await post(linked, originalId);
      originalItem =
          (await db
                  .customSelect(
                    'SELECT id FROM ${linked.items} WHERE ${linked.parentKey} = $originalId',
                  )
                  .getSingle())
              .read<int>('id');
    }
    final isSale = kind == InventoryPostingDocument.sale;
    final isPurchase = kind == InventoryPostingDocument.purchase;
    final saleSide =
        isSale ||
        kind == InventoryPostingDocument.saleReturn ||
        kind == InventoryPostingDocument.saleAdjustment;
    final totalDiscount = itemDiscount + invoiceDiscount;
    final id = await insert(kind.table, {
      isSale
              ? 'invoice_number'
              : isPurchase
              ? 'purchase_number'
              : 'return_number':
          'DOC-${sequence++}',
      'currency_id': currency,
      'status': 'draft',
      'subtotal_cents': 2000,
      'discount_cents': totalDiscount,
      'tax_cents': 0,
      'total_cents': 2000 - totalDiscount,
      if (isSale || isPurchase)
        'payment_method': 'cash'
      else
        'refund_method': 'cash',
      if (linked != null) linked.parentKey: originalId,
      if (linked == null)
        saleSide ? 'customer_id' : 'supplier_id': saleSide
            ? customer
            : supplier,
      if (linked != null) 'reason': 'Posting matrix',
    });
    await insert(kind.items, {
      kind.parentKey: id,
      'quantity': 2,
      if (linked != null)
        linked == InventoryPostingDocument.sale
                ? 'sale_item_id'
                : 'purchase_item_id':
            originalItem,
      if (linked == null) ...{
        'product_id': product,
        'variant_id': explicitVariant ? variant : null,
        isPurchase ? 'unit_cost_cents' : 'unit_price_cents': 1000,
        if (!isSale && !isPurchase) 'unit_cost_cents': 500,
      },
      if (linked != null || isSale || isPurchase) 'subtotal_cents': 2000,
      'discount_cents': linked != null ? totalDiscount : itemDiscount,
      'tax_cents': 0,
      linked != null ? 'refund_cents' : 'total_cents':
          2000 - (linked != null ? totalDiscount : itemDiscount),
    });
    return id;
  }

  Future<int> quantity() async => (await (db.select(
    db.productVariants,
  )..where((v) => v.id.equals(variant))).getSingle()).stockQuantity;
  Future<Map<String, Object?>> totals(
    InventoryPostingDocument kind,
    int id,
  ) async =>
      (await db
              .customSelect(
                'SELECT subtotal_cents, discount_cents, tax_cents, total_cents FROM ${kind.table} WHERE id = $id',
              )
              .getSingle())
          .data;

  for (final kind in InventoryPostingDocument.values) {
    for (final hasVariants in [false, true]) {
      for (final discount in [(100, 0), (0, 100), (100, 100)]) {
        test(
          '${kind.name}: variants=$hasVariants item=${discount.$1} invoice=${discount.$2} post and void',
          () async {
            await seedProduct(hasVariants);
            final id = await create(
              kind,
              itemDiscount: discount.$1,
              invoiceDiscount: discount.$2,
            );
            final beforeQty = await quantity();
            final beforeTotals = await totals(kind, id);
            await post(kind, id);
            final increases =
                kind == InventoryPostingDocument.purchase ||
                kind == InventoryPostingDocument.saleReturn ||
                kind == InventoryPostingDocument.saleAdjustment;
            expect(await quantity(), beforeQty + (increases ? 2 : -2));
            expect(await totals(kind, id), beforeTotals);
            await undo(kind, id);
            expect(await quantity(), beforeQty);
            expect(await totals(kind, id), beforeTotals);
            if (otherVariant != null) {
              expect(
                (await (db.select(
                      db.productVariants,
                    )..where((v) => v.id.equals(otherVariant!))).getSingle())
                    .stockQuantity,
                30,
              );
            }
            final warehouse = await (db.select(
              db.businessWarehouseStocks,
            )..where((s) => s.variantId.equals(variant))).getSingle();
            expect(warehouse.quantity, beforeQty);
          },
        );
      }
    }
  }

  Future<void> relocate(InventoryPostingDocument kind, int id) async {
    final scope = await BusinessFoundationRepository(db).getScope();
    final other = const Uuid().v4();
    await insert('business_warehouses', {
      'id': other,
      'organization_id': scope.organizationId,
      'branch_id': scope.branchId,
      'code': other.substring(0, 8),
    });
    // Test-only simulation of a future imported document; production locations
    // remain immutable and additional warehouse posting remains unavailable.
    await db.customStatement(
      'DROP TRIGGER IF EXISTS business_location_immutable',
    );
    await db.customStatement(
      'UPDATE business_document_locations SET warehouse_id = ? WHERE source_table = ? AND source_id = ?',
      [other, kind.table, id],
    );
  }

  for (final kind in [
    InventoryPostingDocument.sale,
    InventoryPostingDocument.purchase,
  ]) {
    test(
      '${kind.name}: different per-line discounts coexist with an invoice discount',
      () async {
        await seedProduct(true);
        final id = await create(kind);
        await insert(kind.items, {
          kind.parentKey: id,
          'product_id': product,
          'variant_id': otherVariant,
          'quantity': 1,
          kind == InventoryPostingDocument.sale
                  ? 'unit_price_cents'
                  : 'unit_cost_cents':
              1200,
          'subtotal_cents': 1200,
          'discount_cents': 75,
          'tax_cents': 0,
          'total_cents': 1125,
        });
        await db.customStatement(
          'UPDATE ${kind.table} SET subtotal_cents = 3200, discount_cents = 275, total_cents = 2925 WHERE id = ?',
          [id],
        );
        final beforeTotals = await totals(kind, id);
        Future<List<int>> discounts() async =>
            (await db
                    .customSelect(
                      'SELECT discount_cents FROM ${kind.items} WHERE ${kind.parentKey} = $id ORDER BY id',
                    )
                    .get())
                .map((r) => r.read<int>('discount_cents'))
                .toList();
        final direction = kind == InventoryPostingDocument.sale ? -1 : 1;
        await post(kind, id);
        expect(await quantity(), 20 + direction * 2);
        expect(
          (await (db.select(
                db.productVariants,
              )..where((v) => v.id.equals(otherVariant!))).getSingle())
              .stockQuantity,
          30 + direction,
        );
        expect(await discounts(), [100, 75]);
        expect(await totals(kind, id), beforeTotals);
        await undo(kind, id);
        expect(await quantity(), 20);
        expect(
          (await (db.select(
                db.productVariants,
              )..where((v) => v.id.equals(otherVariant!))).getSingle())
              .stockQuantity,
          30,
        );
        expect(await discounts(), [100, 75]);
        expect(await totals(kind, id), beforeTotals);
      },
    );
  }

  for (final kind in InventoryPostingDocument.values) {
    test(
      '${kind.name}: foreign posting and void leave all legacy rows unchanged',
      () async {
        await seedProduct(true);
        final id = await create(kind);
        await relocate(kind, id);
        final before = await fixtures.legacySnapshot(db);
        await expectLater(post(kind, id), throwsStateError);
        await expectLater(undo(kind, id), throwsStateError);
        expect(await fixtures.legacySnapshot(db), before);
      },
    );
  }

  for (final kind in [
    InventoryPostingDocument.saleReturn,
    InventoryPostingDocument.purchaseReturn,
  ]) {
    test(
      '${kind.name}: local return cannot reverse a foreign original invoice',
      () async {
        await seedProduct(false);
        final id = await create(kind);
        final parent = kind == InventoryPostingDocument.saleReturn
            ? InventoryPostingDocument.sale
            : InventoryPostingDocument.purchase;
        final original =
            (await db
                    .customSelect(
                      'SELECT ${parent.parentKey} AS original_id FROM ${kind.table} WHERE id = $id',
                    )
                    .getSingle())
                .read<int>('original_id');
        await relocate(parent, original);
        final before = await fixtures.legacySnapshot(db);
        await expectLater(post(kind, id), throwsStateError);
        await expectLater(undo(kind, id), throwsStateError);
        expect(await fixtures.legacySnapshot(db), before);
      },
    );
    test('${kind.name}: cannot borrow a line from a different invoice', () async {
      await seedProduct(false);
      final id = await create(kind);
      final parent = kind == InventoryPostingDocument.saleReturn
          ? InventoryPostingDocument.sale
          : InventoryPostingDocument.purchase;
      final other = await create(parent);
      final otherItem =
          (await db
                  .customSelect(
                    'SELECT id FROM ${parent.items} WHERE ${parent.parentKey} = $other',
                  )
                  .getSingle())
              .read<int>('id');
      final key = parent == InventoryPostingDocument.sale
          ? 'sale_item_id'
          : 'purchase_item_id';
      await db.customStatement(
        'UPDATE ${kind.items} SET $key = ? WHERE return_id = ?',
        [otherItem, id],
      );
      final before = await fixtures.legacySnapshot(db);
      await expectLater(post(kind, id), throwsStateError);
      expect(await fixtures.legacySnapshot(db), before);
    });
  }

  test(
    'variant belonging to a different product fails before any side effect',
    () async {
      await seedProduct(true);
      final id = await create(InventoryPostingDocument.purchase);
      final otherProduct = await insert('products', {
        'name': 'Unrelated',
        'cost_cents': 1,
        'price_cents': 2,
      });
      await db.customStatement(
        'UPDATE purchase_items SET product_id = ? WHERE purchase_id = ?',
        [otherProduct, id],
      );
      final before = await fixtures.legacySnapshot(db);
      await expectLater(
        post(InventoryPostingDocument.purchase, id),
        throwsStateError,
      );
      expect(await fixtures.legacySnapshot(db), before);
    },
  );

  test('inactive warehouse cannot post or void an adjustment', () async {
    await seedProduct(false);
    final kind = InventoryPostingDocument.saleAdjustment;
    final id = await create(kind);
    await db
        .update(db.businessWarehouses)
        .write(const BusinessWarehousesCompanion(isActive: Value(false)));
    final before = await fixtures.legacySnapshot(db);
    await expectLater(post(kind, id), throwsStateError);
    await expectLater(undo(kind, id), throwsStateError);
    expect(await fixtures.legacySnapshot(db), before);
  });

  test(
    'adjustment history excludes foreign invoices without changing legacy simple-product matching',
    () async {
      await seedProduct(false);
      final sale = await create(InventoryPostingDocument.sale);
      await post(InventoryPostingDocument.sale, sale);
      expect(
        await adjustments.getCustomerProductPurchasedQty(
          customerId: customer,
          productId: product,
        ),
        2,
      );
      await relocate(InventoryPostingDocument.sale, sale);
      expect(
        await adjustments.getCustomerProductPurchasedQty(
          customerId: customer,
          productId: product,
        ),
        0,
      );
    },
  );
  for (final kind in [
    InventoryPostingDocument.sale,
    InventoryPostingDocument.saleReturn,
  ]) {
    for (final status in ['voided', 'invalid']) {
      test('${kind.name}: rejects posting $status without writes', () async {
        await seedProduct(false);
        final id = await create(kind);
        await db.customStatement(
          'UPDATE ${kind.table} SET status = ? WHERE id = ?',
          [status, id],
        );
        final before = await fixtures.legacySnapshot(db);
        await expectLater(post(kind, id), throwsStateError);
        expect(await fixtures.legacySnapshot(db), before);
      });
    }
  }
  for (final mutation in [
    'source_status',
    'currency',
    'quantity',
    'scale',
    'measurement',
    'empty',
  ]) {
    test('sale return rejects invalid $mutation atomically', () async {
      await seedProduct(false);
      final id = await create(InventoryPostingDocument.saleReturn);
      final header = (await db.saleDao.getSaleReturnById(id))!;
      switch (mutation) {
        case 'source_status':
          await db.customStatement(
            "UPDATE sales SET status = 'draft' WHERE id = ?",
            [header.saleId],
          );
        case 'currency':
          final other =
              (await db
                      .customSelect(
                        'SELECT id FROM currencies WHERE id != ? LIMIT 1',
                        variables: [Variable.withInt(currency)],
                      )
                      .getSingle())
                  .read<int>('id');
          await db.customStatement(
            'UPDATE sale_returns SET currency_id = ? WHERE id = ?',
            [other, id],
          );
        case 'quantity':
          await db.customStatement(
            'UPDATE sale_return_items SET quantity = -1 WHERE return_id = ?',
            [id],
          );
        case 'scale':
          await db.customStatement(
            'UPDATE sale_return_items SET quantity_scale = 1000 WHERE return_id = ?',
            [id],
          );
        case 'measurement':
          await db.customStatement(
            "UPDATE sale_return_items SET measurement_type = 'weight' WHERE return_id = ?",
            [id],
          );
        case 'empty':
          await db.customStatement(
            'DELETE FROM sale_return_items WHERE return_id = ?',
            [id],
          );
      }
      final before = await fixtures.legacySnapshot(db);
      await expectLater(db.saleDao.postSaleReturn(id), throwsStateError);
      expect(await fixtures.legacySnapshot(db), before);
    });
  }
  for (final kind in [
    InventoryPostingDocument.sale,
    InventoryPostingDocument.purchase,
    InventoryPostingDocument.saleAdjustment,
    InventoryPostingDocument.purchaseAdjustment,
  ]) {
    for (final mismatch in ['party', 'product', 'inactive_currency']) {
      test('${kind.name}: secondary posting terms reject $mismatch', () async {
        await seedProduct(false);
        final id = await create(kind);
        final local = await BusinessFoundationRepository(db).getScope();
        final other = const Uuid().v4();
        await insert('business_warehouses', {
          'id': other,
          'organization_id': local.organizationId,
          'branch_id': local.branchId,
          'code': 'TERMS',
        });
        final scope = await WarehouseOperationScope.resolve(
          db,
          warehouseId: other,
        );
        await BranchCurrencyPolicyStore(db).bind('USD');
        final otherCurrency =
            (await db
                    .customSelect(
                      'SELECT id FROM currencies WHERE id != ? LIMIT 1',
                      variables: [Variable.withInt(currency)],
                    )
                    .getSingle())
                .read<int>('id');
        if (mismatch == 'party') {
          final saleSide =
              kind == InventoryPostingDocument.sale ||
              kind == InventoryPostingDocument.saleAdjustment;
          await db.customStatement(
            'UPDATE ${saleSide ? 'customers' : 'suppliers'} SET currency_id = ? WHERE id = ?',
            [otherCurrency, saleSide ? customer : supplier],
          );
        } else if (mismatch == 'product') {
          await db.customStatement(
            'UPDATE products SET currency_id = ? WHERE id = ?',
            [otherCurrency, product],
          );
        } else {
          await db.customStatement(
            'UPDATE currencies SET is_active = 0 WHERE id = ?',
            [currency],
          );
        }
        final before = await fixtures.legacySnapshot(db);
        await expectLater(
          DocumentPostingScope.validatePostingTerms(db, kind, id, scope),
          throwsStateError,
        );
        expect(await fixtures.legacySnapshot(db), before);
      });
    }
  }
}
