// Regression tests for AdjustmentReturnDao history queries used by the
// fraud-prevention warnings on unlinked (adjustment) returns.
//
// Bug context (Apr 2026, second pass):
// `getSupplierProductSuppliedQty` (and its sale-side twin
// `getCustomerProductPurchasedQty`) originally filtered on
// `variant_id IS NULL` whenever the caller passed `variantId: null`.
// But the purchase/sale forms resolve non-variant products to whatever
// `ProductVariantDao.getDefaultVariantByProduct` returns at save time —
// which is the STRICT default (color & size NULL) when present, otherwise
// any active variant of the product (e.g. a default later given a
// color/size). The first fix expanded the null branch to match
// `variant_id IS NULL OR variant_id = <strict_default_id>`, but that
// still misses the very common production case where the product's only
// variant carries a color/size (so no strict default exists), causing a
// bogus "never supplied by this supplier" warning even though the
// supplier did supply it.
//
// The second-pass fix drops the variant filter entirely when the caller
// passes `variantId: null` — the picker only emits null for products
// with `hasVariants == false`, so per-product aggregation is exactly the
// intended history regardless of which variant id was stamped on the
// historical row.
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late int supplierId;
  late int customerId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    currencyId = (await db.select(db.currencies).get()).first.id;

    supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'Acme Supplies',
            currencyId: currencyId,
          ),
        );
    customerId = await db.into(db.customers).insert(
          CustomersCompanion.insert(
            name: 'Beta Buyer',
            currencyId: currencyId,
          ),
        );
  });

  tearDown(() async => db.close());

  /// Insert a non-variant product. The purchase/sale forms always resolve
  /// non-variant products to a strict default variant (color & size NULL),
  /// so the test mirrors that convention and returns the default variant id.
  Future<({int productId, int defaultVariantId})> insertNonVariantProduct(
    String name,
  ) async {
    final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: name,
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            currencyId: Value(currencyId),
            hasVariants: const Value(false),
          ),
        );
    final defaultVariantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            stockQuantity: const Value(0),
          ),
        );
    return (productId: productId, defaultVariantId: defaultVariantId);
  }

  /// Insert a product flagged `hasVariants: false` whose only variant carries
  /// a color/size — the exact production scenario that broke the first fix.
  /// `getDefaultVariantByProduct` returns this variant via its any-active
  /// fallback, so the purchase form stamps `purchase_items.variant_id` with
  /// it, but the strict-default lookup misses it.
  Future<({int productId, int variantId})> insertNonVariantProductWithColorSize(
    String name,
  ) async {
    final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: name,
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            currencyId: Value(currencyId),
            hasVariants: const Value(false),
          ),
        );
    final colorId = await db.into(db.productColors).insert(
          ProductColorsCompanion.insert(name: '$name-Color'),
        );
    final sizeId = await db.into(db.sizes).insert(
          SizesCompanion.insert(name: '$name-Size'),
        );
    final variantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            colorId: Value(colorId),
            sizeId: Value(sizeId),
            costCents: Decimal.fromInt(100),
            priceCents: Decimal.fromInt(200),
            stockQuantity: const Value(0),
          ),
        );
    return (productId: productId, variantId: variantId);
  }

  Future<int> insertPurchaseItem({
    required int productId,
    required int? variantId,
    required int quantity,
  }) async {
    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber:
                'P-${DateTime.now().microsecondsSinceEpoch}-${variantId ?? 'n'}',
            supplierId: supplierId,
            currencyId: currencyId,
            subtotalCents: Decimal.fromInt(quantity * 100),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(quantity * 100),
            // 2026-05-13 — must be 'posted' (not the schema-default 'draft')
            // because `getSupplierProductSuppliedQty` now correctly filters
            // out draft/voided rows from the adjustment-return cap.
            status: const Value('posted'),
          ),
        );
    return db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitCostCents: Decimal.fromInt(100),
            subtotalCents: Decimal.fromInt(quantity * 100),
            totalCents: Decimal.fromInt(quantity * 100),
          ),
        );
  }

  Future<int> insertSaleItem({
    required int productId,
    required int? variantId,
    required int quantity,
  }) async {
    final saleId = await db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber:
                'S-${DateTime.now().microsecondsSinceEpoch}-${variantId ?? 'n'}',
            customerId: Value(customerId),
            currencyId: currencyId,
            subtotalCents: Decimal.fromInt(quantity * 200),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(quantity * 200),
            paymentMethod: 'cash',
          ),
        );
    return db.into(db.saleItems).insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            variantId: Value(variantId),
            quantity: quantity,
            unitPriceCents: Decimal.fromInt(200),
            subtotalCents: Decimal.fromInt(quantity * 200),
            totalCents: Decimal.fromInt(quantity * 200),
          ),
        );
  }

  group('getSupplierProductSuppliedQty (variant-id resolution)', () {
    test(
        'BUG REGRESSION: matches default variant id when caller passes null '
        'for a non-variant product whose purchase rows store the default '
        'variant id (current convention)', () async {
      final p = await insertNonVariantProduct('No-variant Item');
      // Mirror what `purchase_form_bloc._onLineItemAdded` produces for a
      // non-variant product: variant_id = default variant id (NOT null).
      await insertPurchaseItem(
        productId: p.productId,
        variantId: p.defaultVariantId,
        quantity: 7,
      );

      // The picker on the unlinked-return form passes `variantId: null` for
      // non-variant products. Before the fix this returned 0 → bogus
      // "never supplied" fraud warning.
      final qty = await db.adjustmentReturnDao.getSupplierProductSuppliedQty(
        supplierId: supplierId,
        productId: p.productId,
        variantId: null,
      );
      expect(qty, equals(7));
    });

    test('also matches truly-NULL legacy rows (back-compat)', () async {
      final p = await insertNonVariantProduct('Legacy Null Item');
      await insertPurchaseItem(
        productId: p.productId,
        variantId: null,
        quantity: 4,
      );

      final qty = await db.adjustmentReturnDao.getSupplierProductSuppliedQty(
        supplierId: supplierId,
        productId: p.productId,
        variantId: null,
      );
      expect(qty, equals(4));
    });

    test('aggregates legacy NULL + default-variant rows together', () async {
      final p = await insertNonVariantProduct('Mixed Item');
      await insertPurchaseItem(
        productId: p.productId,
        variantId: null,
        quantity: 3,
      );
      await insertPurchaseItem(
        productId: p.productId,
        variantId: p.defaultVariantId,
        quantity: 5,
      );

      final qty = await db.adjustmentReturnDao.getSupplierProductSuppliedQty(
        supplierId: supplierId,
        productId: p.productId,
        variantId: null,
      );
      expect(qty, equals(8));
    });

    test(
        'explicit variantId still matches exactly (variant-aware product) — '
        'does NOT bleed across variants', () async {
      final productId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'Variant Item',
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
              currencyId: Value(currencyId),
              hasVariants: const Value(true),
            ),
          );
      // Two real variants (with color/size set so they aren't the "default").
      final colorId = await db.into(db.productColors).insert(
            ProductColorsCompanion.insert(name: 'Red'),
          );
      final sizeId = await db.into(db.sizes).insert(
            SizesCompanion.insert(name: 'M'),
          );
      final variantA = await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              colorId: Value(colorId),
              sizeId: Value(sizeId),
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
            ),
          );
      final variantB = await db.into(db.productVariants).insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              colorId: Value(colorId),
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(200),
            ),
          );
      await insertPurchaseItem(
        productId: productId,
        variantId: variantA,
        quantity: 6,
      );
      await insertPurchaseItem(
        productId: productId,
        variantId: variantB,
        quantity: 9,
      );

      final qtyA = await db.adjustmentReturnDao.getSupplierProductSuppliedQty(
        supplierId: supplierId,
        productId: productId,
        variantId: variantA,
      );
      final qtyB = await db.adjustmentReturnDao.getSupplierProductSuppliedQty(
        supplierId: supplierId,
        productId: productId,
        variantId: variantB,
      );
      expect(qtyA, equals(6));
      expect(qtyB, equals(9));
    });

    test(
        'BUG REGRESSION (2nd pass): non-variant product whose default '
        'variant carries a color/size is still matched when caller passes '
        'null — reproduces the production screenshot where shirt(tt77) and '
        'skirt(tt55) wrongly warned "never supplied by this supplier"',
        () async {
      final p = await insertNonVariantProductWithColorSize('shirt');
      // Purchase form path: variant: null → getDefaultVariantByProduct
      // falls back to the only active variant (which has color/size) →
      // purchase_items.variant_id = that non-strict variant id.
      await insertPurchaseItem(
        productId: p.productId,
        variantId: p.variantId,
        quantity: 10,
      );

      // Adj-return picker emits variantId: null because hasVariants=false.
      final qty = await db.adjustmentReturnDao.getSupplierProductSuppliedQty(
        supplierId: supplierId,
        productId: p.productId,
        variantId: null,
      );
      // Before second-pass fix: 0 (strict-default lookup missed).
      // After: 10.
      expect(qty, equals(10));
    });

    test('returns 0 for an unrelated supplier', () async {
      final p = await insertNonVariantProduct('Item');
      await insertPurchaseItem(
        productId: p.productId,
        variantId: p.defaultVariantId,
        quantity: 7,
      );

      final otherSupplier = await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(
              name: 'Other',
              currencyId: currencyId,
            ),
          );
      final qty = await db.adjustmentReturnDao.getSupplierProductSuppliedQty(
        supplierId: otherSupplier,
        productId: p.productId,
        variantId: null,
      );
      expect(qty, equals(0));
    });
  });

  group('getCustomerProductPurchasedQty (symmetric sale-side query)', () {
    test(
        'matches default variant id when caller passes null for a '
        'non-variant product (mirrors the purchase-side fix)', () async {
      final p = await insertNonVariantProduct('Sale Item');
      await insertSaleItem(
        productId: p.productId,
        variantId: p.defaultVariantId,
        quantity: 5,
      );

      final qty = await db.adjustmentReturnDao.getCustomerProductPurchasedQty(
        customerId: customerId,
        productId: p.productId,
        variantId: null,
      );
      expect(qty, equals(5));
    });

    test(
        'BUG REGRESSION (2nd pass): non-variant product whose default '
        'variant carries a color/size is still matched on the sale side',
        () async {
      final p = await insertNonVariantProductWithColorSize('sale-shirt');
      await insertSaleItem(
        productId: p.productId,
        variantId: p.variantId,
        quantity: 4,
      );

      final qty = await db.adjustmentReturnDao.getCustomerProductPurchasedQty(
        customerId: customerId,
        productId: p.productId,
        variantId: null,
      );
      expect(qty, equals(4));
    });

    test('returns 0 when customerId is null (anonymous sale)', () async {
      final p = await insertNonVariantProduct('Item');
      await insertSaleItem(
        productId: p.productId,
        variantId: p.defaultVariantId,
        quantity: 3,
      );

      final qty = await db.adjustmentReturnDao.getCustomerProductPurchasedQty(
        customerId: null,
        productId: p.productId,
        variantId: null,
      );
      expect(qty, equals(0));
    });
  });
}
