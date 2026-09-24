import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/inventory/purchase_supplier_source_service.dart';
import 'package:tapix/core/services/inventory/supplier_identity_rules.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/business/warehouse_stock_initialization_service.dart';
import 'package:tapix/features/purchases/data/models/purchase_model.dart';

import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/purchases/data/datasources/purchase_local_datasource.dart';
import 'package:tapix/features/purchases/data/repositories/purchase_repository_impl.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';

class _Session extends Fake implements SessionService {
  @override
  Future<int?> getCurrentUserId() async => null;
}

void main() {
  late AppDatabase db;
  late int currency, noor, other, blank, product, variant;
  var serial = 0;
  Decimal cents(int value) => Decimal.fromInt(value);

  PurchasesCompanion header(int supplier, {int total = 5000}) =>
      PurchasesCompanion.insert(
        purchaseNumber: 'SUP-SRC-${serial++}',
        supplierId: supplier,
        currencyId: currency,
        subtotalCents: cents(total),
        taxCents: Decimal.zero,
        totalCents: cents(total),
        paymentMethod: const Value('credit'),
      );
  PurchaseItemsCompanion line({
    bool requested = true,
    int? productId,
    int? variantId,
    bool implicitVariant = false,
    int quantity = 2,
    int scale = 1,
    String type = 'piece',
    String? lot,
    DateTime? expiry,
  }) => PurchaseItemsCompanion.insert(
    purchaseId: 0,
    productId: productId ?? product,
    variantId: Value(implicitVariant ? null : (variantId ?? variant)),
    quantity: quantity,
    quantityScale: Value(scale),
    measurementType: Value(type),
    unitCostCents: cents(2500),
    subtotalCents: cents(quantity * 2500 ~/ scale),
    totalCents: cents(quantity * 2500 ~/ scale),
    taxCents: Value(Decimal.zero),
    supplierIdentityRequested: Value(requested),
    manufacturerLotNumber: Value(lot),
    expiryDate: Value(expiry),
  );
  Future<int> buy(
    int supplier, {
    bool requested = true,
    bool implicit = false,
    int quantity = 2,
    WarehouseOperationScope? scope,
  }) => db.purchaseDao.createPurchase(
    header(supplier, total: quantity * 2500),
    [line(requested: requested, implicitVariant: implicit, quantity: quantity)],
    scope: scope,
  );
  Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
    final result = <String, List<Map<String, Object?>>>{};
    for (final name in [
      'suppliers',
      'purchases',
      'purchase_items',
      'supplier_product_identities',
      'supplier_product_code_locks',
      'products',
      'product_variants',
      'business_warehouse_stocks',
      'inventory_origin_states',
      'inventory_origin_events',
      'supplier_transactions',
      'journal_entries',
      'journal_entry_lines',
    ]) {
      result[name] =
          (await db.customSelect('SELECT * FROM "$name" ORDER BY rowid').get())
              .map((r) => Map<String, Object?>.from(r.data))
              .toList();
    }
    return result;
  }

  Matcher sourceFailure(String key) => isA<SupplierIdentityException>().having(
    (e) => e.messageKey,
    'messageKey',
    key,
  );

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    serial = 0;
    currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    noor = await db.supplierDao.createSupplier(
      SuppliersCompanion.insert(
        name: 'Noor',
        currencyId: currency,
        productCode: const Value('N1'),
      ),
    );
    other = await db.supplierDao.createSupplier(
      SuppliersCompanion.insert(
        name: 'Other',
        currencyId: currency,
        productCode: const Value('007'),
      ),
    );
    blank = await db.supplierDao.createSupplier(
      SuppliersCompanion.insert(name: 'Legacy', currencyId: currency),
    );
    product = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Source test',
            sku: const Value('015'),
            currencyId: Value(currency),
            costCents: cents(2500),
            priceCents: cents(3500),
          ),
        );
    variant = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: product,
            costCents: cents(2500),
            priceCents: cents(3500),
          ),
        );
  });
  tearDown(() => db.close());

  test(
    'legacy purchase stays unbound even when the supplier has a code',
    () async {
      final id = await buy(noor, requested: false);
      final item = (await db.purchaseDao.getPurchaseItems(id)).single;
      expect(item.supplierIdentityRequested, isFalse);
      expect(item.supplierIdentityId, isNull);
      expect(await db.select(db.supplierProductIdentities).get(), isEmpty);
    },
  );
  test(
    'real create path binds simple null variant without changing base SKU or stock',
    () async {
      final id = await buy(noor, implicit: true);
      final details = (await db.purchaseDao.getPurchaseItemsWithDetails(
        id,
      )).single;
      expect(details.supplierIdentity!.sourceSku, 'N1-015');
      expect(details.supplierIdentity!.canonicalVariantId, variant);
      expect(details.product.sku, '015');
      expect(details.product.stockQuantity, 0);
      final model = PurchaseItemModel.fromDriftWithDetails(details);
      expect(model.supplierSourceSku, 'N1-015');
      expect(model.supplierIdentityId, details.supplierIdentity!.id);
    },
  );
  test(
    'N N 007 N creates exactly two stable identities and preserves leading zeros',
    () async {
      final ids = <int>[];
      for (final supplier in [noor, noor, other, noor]) {
        ids.add(
          (await db.purchaseDao.getPurchaseItems(
            await buy(supplier),
          )).single.supplierIdentityId!,
        );
      }
      expect(ids[0], ids[1]);
      expect(ids[0], ids[3]);
      expect(ids[0], isNot(ids[2]));
      expect(
        (await db.select(db.supplierProductIdentities).get())
            .map((i) => i.sourceSku)
            .toSet(),
        {'N1-015', '007-015'},
      );
    },
  );
  test(
    'repeated read-only previews create neither identity nor lock',
    () async {
      final service = PurchaseSupplierSourceService(db);
      final before = await snapshot();
      for (final supplier in [noor, other, noor]) {
        await service.preview(supplierId: supplier, productId: product);
      }
      expect(await snapshot(), before);
    },
  );
  test(
    'missing supplier code rolls back the invoice and all side effects',
    () async {
      final before = await snapshot();
      await expectLater(
        buy(blank),
        throwsA(sourceFailure('supplier_identity.code_required')),
      );
      expect(await snapshot(), before);
    },
  );
  test(
    'missing base SKU rolls back without guessing from barcode or name',
    () async {
      await (db.update(db.products)..where((p) => p.id.equals(product))).write(
        const ProductsCompanion(sku: Value(null), barcode: Value('12345678')),
      );
      final before = await snapshot();
      await expectLater(
        buy(noor),
        throwsA(sourceFailure('supplier_identity.base_sku_required')),
      );
      expect(await snapshot(), before);
    },
  );
  test(
    'code collision with manufacturer barcode rejects the whole purchase',
    () async {
      await (db.update(db.products)..where((p) => p.id.equals(product))).write(
        const ProductsCompanion(barcode: Value('N1-015')),
      );
      final before = await snapshot();
      await expectLater(
        buy(noor),
        throwsA(sourceFailure('supplier_identity.source_code_collision')),
      );
      expect(await snapshot(), before);
    },
  );
  test(
    'failure in second line rolls back first identity and supplier lock too',
    () async {
      final bad = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Untracked',
              sku: const Value('SVC'),
              costCents: cents(2500),
              priceCents: cents(3500),
              trackInventory: const Value(false),
            ),
          );
      final before = await snapshot();
      await expectLater(
        db.purchaseDao.createPurchase(header(noor), [
          line(),
          line(productId: bad),
        ]),
        throwsA(sourceFailure('supplier_purchase.untracked_product')),
      );
      expect(await snapshot(), before);
    },
  );
  test(
    'draft supplier N -> 007 -> N rebinds saved lines without stacking prefixes',
    () async {
      final id = await buy(noor);
      final first = (await db.purchaseDao.getPurchaseItems(
        id,
      )).single.supplierIdentityId;
      for (final supplier in [other, noor]) {
        expect(
          await db.purchaseDao.updatePurchaseWithItems(
            id,
            PurchasesCompanion(supplierId: Value(supplier)),
            [line()],
          ),
          isTrue,
        );
        final details = (await db.purchaseDao.getPurchaseItemsWithDetails(
          id,
        )).single;
        expect(
          details.supplierIdentity!.sourceSku,
          supplier == noor ? 'N1-015' : '007-015',
        );
      }
      expect(
        (await db.purchaseDao.getPurchaseItems(id)).single.supplierIdentityId,
        first,
      );
      expect(await db.select(db.supplierProductIdentities).get(), hasLength(2));
    },
  );
  test(
    'failed draft rebind preserves original supplier line and code',
    () async {
      final id = await buy(noor);
      final before = await snapshot();
      await expectLater(
        db.purchaseDao.updatePurchaseWithItems(
          id,
          PurchasesCompanion(supplierId: Value(blank)),
          [line()],
        ),
        throwsA(anything),
      );
      expect(await snapshot(), before);
    },
  );
  test('posting preserves source and adds stock exactly once', () async {
    final id = await buy(noor, quantity: 50);
    final identity = (await db.purchaseDao.getPurchaseItems(
      id,
    )).single.supplierIdentityId;
    await db.purchaseDao.postPurchase(id);
    expect(
      (await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variant))).getSingle()).stockQuantity,
      50,
    );
    expect(
      (await db.purchaseDao.getPurchaseItems(id)).single.supplierIdentityId,
      identity,
    );
    final before = await snapshot();
    await expectLater(db.purchaseDao.postPurchase(id), throwsA(anything));
    expect(await snapshot(), before);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  });
  test(
    'measured quantities keep scale and existing valuation pipeline',
    () async {
      await (db.update(db.products)..where((p) => p.id.equals(product))).write(
        const ProductsCompanion(measurementType: Value('length')),
      );
      final id = await db.purchaseDao.createPurchase(
        header(noor, total: 3125),
        [line(quantity: 1250, scale: 1000, type: 'length')],
      );
      await db.purchaseDao.postPurchase(id);
      final item = (await db.purchaseDao.getPurchaseItems(id)).single;
      expect(item.quantity, 1250);
      expect(item.quantityScale, 1000);
      expect(item.measurementType, 'length');
      expect(
        (await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(variant))).getSingle()).stockQuantity,
        1250,
      );
    },
  );
  test(
    'two lots keep independent batches under one supplier identity',
    () async {
      await (db.update(db.products)..where((p) => p.id.equals(product))).write(
        const ProductsCompanion(
          costingMethod: Value('fifo'),
          inventoryTrackingType: Value('batch_expiry'),
        ),
      );
      final id = await db.purchaseDao
          .createPurchase(header(noor, total: 10000), [
            line(lot: 'LOT-A', expiry: DateTime(2028, 6, 30)),
            line(lot: 'LOT-B', expiry: DateTime(2029, 6, 30)),
          ]);
      await db.purchaseDao.postPurchase(id);
      final items = await db.purchaseDao.getPurchaseItems(id);
      expect(items.map((i) => i.supplierIdentityId).toSet(), hasLength(1));
      final batches = await (db.select(
        db.productBatches,
      )..where((b) => b.productId.equals(product))).get();
      expect(batches, hasLength(2));
      expect(batches.map((b) => b.manufacturerLotNumber).toSet(), {
        'LOT-A',
        'LOT-B',
      });
      expect(
        batches.map((b) => b.purchaseItemId).toSet(),
        items.map((i) => i.id).toSet(),
      );
    },
  );
  test(
    'posted source cannot be reassigned or reopened through raw writes',
    () async {
      final id = await buy(noor);
      await db.purchaseDao.postPurchase(id);
      await expectLater(
        db.customStatement('UPDATE purchases SET supplier_id=? WHERE id=?', [
          other,
          id,
        ]),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement("UPDATE purchases SET status='draft' WHERE id=?", [
          id,
        ]),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'UPDATE purchase_items SET supplier_identity_requested=0,supplier_identity_id=NULL WHERE purchase_id=?',
          [id],
        ),
        throwsA(anything),
      );
      expect(
        (await db.purchaseDao.getPurchaseItemsWithDetails(
          id,
        )).single.supplierIdentity!.supplierId,
        noor,
      );
    },
  );
  test(
    'partial quantity update keeps existing binding, single add binds too',
    () async {
      final id = await buy(noor);
      final old = (await db.purchaseDao.getPurchaseItems(id)).single;
      await db.purchaseDao.updatePurchaseItem(
        old.id,
        const PurchaseItemsCompanion(quantity: Value(3)),
      );
      final updated = (await db.purchaseDao.getPurchaseItems(id)).single;
      expect(updated.supplierIdentityId, old.supplierIdentityId);
      expect(updated.quantity, 3);
      final second = await db.purchaseDao.addPurchaseItem(
        line().copyWith(purchaseId: Value(id)),
      );
      expect(
        (await (db.select(
          db.purchaseItems,
        )..where((i) => i.id.equals(second))).getSingle()).supplierIdentityId,
        old.supplierIdentityId,
      );
    },
  );
  test(
    'inactive supplier remains readable but cannot post new receipts',
    () async {
      final id = await buy(noor);
      await db.supplierDao.setSupplierActive(noor, false);
      expect(
        (await db.purchaseDao.getPurchaseItemsWithDetails(
          id,
        )).single.supplierIdentity!.sourceSku,
        'N1-015',
      );
      await expectLater(
        db.purchaseDao.postPurchase(id),
        throwsA(sourceFailure('supplier_identity.inactive_source')),
      );
    },
  );
  test(
    'client cannot issue locally or silently downgrade requested receipt',
    () async {
      await db.settingsDao.saveSetting('lan.mode', 'client');
      final before = await snapshot();
      await expectLater(
        buy(noor),
        throwsA(sourceFailure('supplier_identity.master_required')),
      );
      expect(await snapshot(), before);
    },
  );
  test(
    'later base-SKU edit does not change saved or future code for same pair',
    () async {
      final id = await buy(noor);
      await (db.update(db.products)..where((p) => p.id.equals(product))).write(
        const ProductsCompanion(sku: Value('016')),
      );
      final another = await buy(noor);
      for (final pid in [id, another]) {
        expect(
          (await db.purchaseDao.getPurchaseItemsWithDetails(
            pid,
          )).single.supplierIdentity!.sourceSku,
          'N1-015',
        );
      }
    },
  );

  test('two real variants receive distinct stable source codes', () async {
    // Different SKU text alone does not define a different color/size pair.
    // Keep the production uniqueness guard and create actual variant options.
    final blue = await db
        .into(db.productColors)
        .insert(ProductColorsCompanion.insert(name: 'Blue'));
    final smallSize = await db
        .into(db.sizes)
        .insert(SizesCompanion.insert(name: 'S'));
    final largeSize = await db
        .into(db.sizes)
        .insert(SizesCompanion.insert(name: 'L'));
    await (db.update(db.products)..where((p) => p.id.equals(product))).write(
      const ProductsCompanion(hasVariants: Value(true)),
    );
    await (db.update(
      db.productVariants,
    )..where((v) => v.id.equals(variant))).write(
      ProductVariantsCompanion(
        sku: const Value('015-BL-S'),
        colorId: Value(blue),
        sizeId: Value(smallSize),
      ),
    );
    final large = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: product,
            sku: const Value('015-BL-L'),
            colorId: Value(blue),
            sizeId: Value(largeSize),
            costCents: cents(2500),
            priceCents: cents(3500),
          ),
        );
    final id = await db.purchaseDao.createPurchase(header(noor, total: 10000), [
      line(),
      line(variantId: large),
    ]);
    final rows = await db.purchaseDao.getPurchaseItemsWithDetails(id);
    expect(rows.map((r) => r.supplierIdentity!.sourceSku).toSet(), {
      'N1-015-BL-S',
      'N1-015-BL-L',
    });
    expect(rows.map((r) => r.supplierIdentity!.canonicalVariantId).toSet(), {
      variant,
      large,
    });
    expect(rows.map((r) => r.supplierIdentity!.id).toSet(), hasLength(2));
    final before = await snapshot();
    await expectLater(
      buy(noor, implicit: true),
      throwsA(sourceFailure('supplier_identity.variant_required')),
    );
    expect(await snapshot(), before);
  });

  test('untracked lines remain exempt inside an opted-in purchase', () async {
    final serviceProduct = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Service',
            costCents: cents(2500),
            priceCents: cents(3500),
            trackInventory: const Value(false),
          ),
        );
    final id = await db.purchaseDao.createPurchase(header(noor, total: 10000), [
      line(),
      line(productId: serviceProduct, requested: false, implicitVariant: true),
    ]);
    final rows = await db.purchaseDao.getPurchaseItems(id);
    expect(rows.first.supplierIdentityId, isNotNull);
    expect(rows.last.supplierIdentityRequested, isFalse);
    expect(rows.last.supplierIdentityId, isNull);
  });

  test(
    'forged external identity is rejected and new invoice rolls back',
    () async {
      final first = await buy(other);
      final wrong = (await db.purchaseDao.getPurchaseItems(
        first,
      )).single.supplierIdentityId;
      final before = await snapshot();
      await expectLater(
        db.purchaseDao.createPurchase(header(noor), [
          line().copyWith(supplierIdentityId: Value(wrong)),
        ]),
        throwsA(sourceFailure('supplier_purchase.source_mismatch')),
      );
      expect(await snapshot(), before);
    },
  );

  test(
    'watch and one-off details read the same saved supplier identity',
    () async {
      final id = await buy(noor);
      final current = (await db.purchaseDao.getPurchaseItemsWithDetails(
        id,
      )).single;
      final watched =
          (await db.purchaseDao.watchPurchaseItemsWithDetails(id).first).single;
      expect(watched.supplierIdentity!.id, current.supplierIdentity!.id);
      expect(watched.supplierIdentity!.sourceSku, 'N1-015');
    },
  );

  test('failure during posting rolls back stock and account writes', () async {
    final id = await buy(noor, quantity: 50);
    final before = await snapshot();
    // The supplier posting occurs after stock work in the real DAO transaction.
    await db.customStatement('''CREATE TRIGGER test_abort_supplier_post
      BEFORE INSERT ON supplier_transactions
      BEGIN SELECT RAISE(ABORT, 'injected posting failure'); END''');
    await expectLater(db.purchaseDao.postPurchase(id), throwsA(anything));
    expect(await snapshot(), before);
    await db.customStatement('DROP TRIGGER test_abort_supplier_post');
    await db.purchaseDao.postPurchase(id);
    expect(
      (await (db.select(
        db.productVariants,
      )..where((v) => v.id.equals(variant))).getSingle()).stockQuantity,
      50,
    );
    expect(
      (await db.purchaseDao.getPurchaseItemsWithDetails(
        id,
      )).single.supplierIdentity!.sourceSku,
      'N1-015',
    );
  });

  test(
    'real repository -> datasource -> DAO saves and reads source metadata',
    () async {
      await BranchCurrencyPolicyStore(db).bind('USD');
      final repo = PurchaseRepositoryImpl(
        PurchaseLocalDatasourceImpl(db.purchaseDao, AdjustmentReturnDao(db)),
        AuditLogService(db),
        _Session(),
        JournalEntryService(AccountingRepository(db)),
        db,
      );
      final input = PurchaseItemInput(
        productId: product,
        variantId: variant,
        quantity: 2,
        unitCostCents: cents(2500),
        discountCents: Decimal.zero,
        subtotalCents: cents(5000),
        taxCents: Decimal.zero,
        totalCents: cents(5000),
        supplierIdentityRequested: true,
      );
      final id = await repo.createPurchase(
        supplierId: noor,
        currencyId: currency,
        subtotalCents: cents(5000),
        discountCents: Decimal.zero,
        taxCents: Decimal.zero,
        totalCents: cents(5000),
        paidAmountCents: Decimal.zero,
        paymentMethod: 'credit',
        items: [input],
      );
      expect(
        (await repo.getPurchaseItems(id)).single.supplierSourceSku,
        'N1-015',
      );
      await repo.updatePurchase(
        purchaseId: id,
        supplierId: other,
        currencyId: currency,
        subtotalCents: cents(5000),
        discountCents: Decimal.zero,
        taxCents: Decimal.zero,
        totalCents: cents(5000),
        paidAmountCents: Decimal.zero,
        paymentMethod: 'credit',
        items: [input],
      );
      expect(
        (await repo.getPurchaseItems(id)).single.supplierSourceSku,
        '007-015',
      );
      await repo.postPurchase(id);
      expect(
        (await repo.getPurchaseItems(id)).single.supplierSourceSku,
        '007-015',
      );
      expect(
        (await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(variant))).getSingle()).stockQuantity,
        2,
      );
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );

  test(
    'identity is shared across warehouses without duplicating global stock',
    () async {
      // Additional-warehouse posting requires an explicit branch currency.
      // Bind the same USD currency used by this test's supplier/product/invoices.
      final currencyPolicy = BranchCurrencyPolicyStore(db);
      await currencyPolicy.bind('USD');
      expect((await currencyPolicy.read())!.id, currency);
      final primary = await WarehouseOperationScope.resolve(db);
      const otherWarehouse = 'e1be9c3d-ab23-4e93-aad6-0a4b80b0c202';
      await db
          .into(db.businessWarehouses)
          .insert(
            BusinessWarehousesCompanion.insert(
              id: otherWarehouse,
              organizationId: primary.organizationId,
              branchId: primary.branchId,
              code: 'SOURCE-OTHER',
            ),
          );
      final secondary = await WarehouseOperationScope.resolve(
        db,
        warehouseId: otherWarehouse,
      );
      // A non-primary warehouse must have an explicit zero balance before
      // inventory documents can post against it. Use the production initializer
      // instead of bypassing WarehouseInventoryReader with a raw insert.
      final initializer = WarehouseStockInitializationService(db);
      expect(
        await initializer.initialize(
          scope: secondary,
          currencyId: currency,
          seeds: [WarehouseStockSeed(variantId: variant, unitCostCents: 2500)],
        ),
        1,
      );
      expect(
        (await (db.select(db.businessWarehouseStocks)..where(
                  (s) =>
                      s.warehouseId.equals(otherWarehouse) &
                      s.variantId.equals(variant),
                ))
                .getSingle())
            .quantity,
        0,
      );
      final first = await buy(noor, quantity: 2, scope: primary);
      final second = await buy(noor, quantity: 3, scope: secondary);
      await db.purchaseDao.postPurchase(first, scope: primary);
      await db.purchaseDao.postPurchase(second, scope: secondary);
      final a = (await db.purchaseDao.getPurchaseItems(first)).single;
      final b = (await db.purchaseDao.getPurchaseItems(second)).single;
      expect(a.supplierIdentityId, b.supplierIdentityId);
      expect(await db.select(db.supplierProductIdentities).get(), hasLength(1));
      expect(
        (await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(variant))).getSingle()).stockQuantity,
        2,
      );
      expect(
        (await (db.select(db.businessWarehouseStocks)..where(
                  (s) =>
                      s.warehouseId.equals(otherWarehouse) &
                      s.variantId.equals(variant),
                ))
                .getSingle())
            .quantity,
        3,
      );
    },
  );
}
