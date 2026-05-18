// Regression test for the IAS-2 cost split introduced in migration 10055.
//
// Background:
//   Before the split, `purchase_dao.postPurchase` stored a single value on
//   `product_variants.cost_cents` / `products.cost_cents`. After the
//   May-2026 trade-discount fix, that column became the IAS-2 NET basis
//   (`gross − discount/qty`) so the reconciliation invariant
//   `Inventory GL == Σ(stock × cost)` holds. That was correct for the
//   ledger but surprised the user: the product detail screen now showed
//   "99" after a 10-on-1000 discount instead of the typed-in supplier
//   list price of "100".
//
// Fix (migration 10055): split into two columns.
//   * `cost_cents`                  → IAS-2 NET basis, drives GL + COGS.
//   * `last_purchase_price_cents`   → GROSS supplier list price (pre line
//                                     discount), purely a UI snapshot.
//
// This test pins the contract from `purchase_dao.postPurchase`:
//   1. Discounted purchase    → net cost ≠ gross last-purchase price.
//   2. Undiscounted purchase  → net cost == gross last-purchase price.
//   3. Non-variant product    → write lands on `products` AND its
//                               default-variant mirror.
//   4. Repeated purchase at a NEW gross unit cost refreshes
//      `last_purchase_price_cents` to the latest gross (the "supplier
//      reference price is the most recent list price" rule).
//   5. Parent `products.last_purchase_price_cents` is propagated from
//      its variants by `ProductCostService.syncProductFromVariants`.
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    // Force initialization (seeds currencies + chart of accounts).
    await db.customSelect('SELECT 1').get();
    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();
    currencyId = usd.id;
    supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'IAS2 Split Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
  });

  tearDown(() async => db.close());

  // ──────────────────────────────────────────────────────────────────────
  // 1) Discounted purchase on a real variant.
  // ──────────────────────────────────────────────────────────────────────
  test(
      'discounted purchase (10 × 100, line discount 10): '
      'variant.cost_cents=99 (NET) AND variant.last_purchase_price_cents=100 (GROSS); '
      'parent.last_purchase_price_cents=100 via sync', () async {
    final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Discount Split Product',
            costCents: Decimal.fromInt(0),
            priceCents: Decimal.fromInt(0),
            currencyId: Value(currencyId),
            hasVariants: const Value(true),
            stockQuantity: const Value(0),
          ),
        );
    final variantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(0),
            costCents: Decimal.fromInt(0),
            priceCents: Decimal.fromInt(0),
          ),
        );

    const lineQty = 10;
    const grossUnit = 100; // typed-in list price
    const lineDiscount = 10; // 10 cents off the whole line
    const subtotal = lineQty * grossUnit; // 1000
    const lineNet = subtotal - lineDiscount; // 990
    const expectedNetUnit = 99; // 100 − round(10/10)

    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-LPP-001',
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(subtotal),
            discountCents: Value(Decimal.fromInt(lineDiscount)),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(lineNet),
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
            quantity: lineQty,
            unitCostCents: Decimal.fromInt(grossUnit),
            discountCents: Value(Decimal.fromInt(lineDiscount)),
            subtotalCents: Decimal.fromInt(subtotal),
            totalCents: Decimal.fromInt(lineNet),
          ),
        );

    await db.purchaseDao.postPurchase(purchaseId);

    // ── Variant: NET cost basis (IAS-2) AND GROSS supplier list price. ──
    final variant = await (db.select(db.productVariants)
          ..where((v) => v.id.equals(variantId)))
        .getSingle();
    expect(variant.stockQuantity, equals(lineQty));
    expect(
      variant.costCents.toBigInt().toInt(),
      equals(expectedNetUnit),
      reason: 'cost_cents must be the IAS-2 NET basis so '
          'Inventory GL == Σ(stock × cost) reconciles.',
    );
    expect(
      variant.lastPurchasePriceCents,
      isNotNull,
      reason:
          'Discounted purchase must stamp the supplier reference price.',
    );
    expect(
      variant.lastPurchasePriceCents!.toBigInt().toInt(),
      equals(grossUnit),
      reason: 'last_purchase_price_cents must be the GROSS unit cost '
          '(pre-discount) — what the user typed and expects to see in '
          'the product detail screen.',
    );

    // ── Parent product row: synced from variants by ProductCostService. ──
    final product = await (db.select(db.products)
          ..where((p) => p.id.equals(productId)))
        .getSingle();
    expect(
      product.lastPurchasePriceCents,
      isNotNull,
      reason:
          'syncProductFromVariants must propagate the variant gross price '
          'to the parent row (MAX aggregation).',
    );
    expect(
      product.lastPurchasePriceCents!.toBigInt().toInt(),
      equals(grossUnit),
    );

    // Sanity: cost basis on the parent is NET, not GROSS — proving the
    // two columns are actually decoupled.
    expect(
      product.costCents.toBigInt().toInt(),
      equals(expectedNetUnit),
      reason: 'Parent cost_cents must remain the NET basis.',
    );
    expect(
      product.costCents.toBigInt().toInt() ==
          product.lastPurchasePriceCents!.toBigInt().toInt(),
      isFalse,
      reason: 'The whole point of the split is that cost_cents and '
          'last_purchase_price_cents differ when a line discount applies.',
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  // 2) Undiscounted purchase — both columns must converge.
  // ──────────────────────────────────────────────────────────────────────
  test(
      'undiscounted purchase: cost_cents == last_purchase_price_cents == gross unit cost',
      () async {
    final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'No-discount Product',
            costCents: Decimal.fromInt(0),
            priceCents: Decimal.fromInt(0),
            currencyId: Value(currencyId),
            hasVariants: const Value(true),
            stockQuantity: const Value(0),
          ),
        );
    final variantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(0),
            costCents: Decimal.fromInt(0),
            priceCents: Decimal.fromInt(0),
          ),
        );

    const lineQty = 4;
    const grossUnit = 5000;
    const subtotal = lineQty * grossUnit;

    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-LPP-002',
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(subtotal),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(subtotal),
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
            quantity: lineQty,
            unitCostCents: Decimal.fromInt(grossUnit),
            subtotalCents: Decimal.fromInt(subtotal),
            totalCents: Decimal.fromInt(subtotal),
          ),
        );

    await db.purchaseDao.postPurchase(purchaseId);

    final variant = await (db.select(db.productVariants)
          ..where((v) => v.id.equals(variantId)))
        .getSingle();
    expect(variant.costCents.toBigInt().toInt(), equals(grossUnit));
    expect(
      variant.lastPurchasePriceCents!.toBigInt().toInt(),
      equals(grossUnit),
      reason: 'With zero discount the two columns must converge — '
          'no behavioural change for the common case.',
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  // 3) Non-variant product (no real variant, `hasVariants=false`). The
  //    DAO mirrors the gross price onto BOTH `products` AND the implicit
  //    default-variant row (color_id IS NULL AND size_id IS NULL).
  // ──────────────────────────────────────────────────────────────────────
  test(
      'non-variant product: gross supplier price lands on products row AND '
      'on the default-variant mirror', () async {
    final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Non-variant Product',
            costCents: Decimal.fromInt(0),
            priceCents: Decimal.fromInt(0),
            currencyId: Value(currencyId),
            hasVariants: const Value(false),
            stockQuantity: const Value(0),
          ),
        );
    // Default variant — the implicit row the DAO mirrors writes onto.
    final defaultVariantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(0),
            costCents: Decimal.fromInt(0),
            priceCents: Decimal.fromInt(0),
          ),
        );

    const lineQty = 5;
    const grossUnit = 200;
    const lineDiscount = 10;
    const subtotal = lineQty * grossUnit; // 1000
    const lineNet = subtotal - lineDiscount; // 990

    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-LPP-003',
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(subtotal),
            discountCents: Value(Decimal.fromInt(lineDiscount)),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(lineNet),
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
            // variantId omitted → non-variant branch in postPurchase.
            quantity: lineQty,
            unitCostCents: Decimal.fromInt(grossUnit),
            discountCents: Value(Decimal.fromInt(lineDiscount)),
            subtotalCents: Decimal.fromInt(subtotal),
            totalCents: Decimal.fromInt(lineNet),
          ),
        );

    await db.purchaseDao.postPurchase(purchaseId);

    final product = await (db.select(db.products)
          ..where((p) => p.id.equals(productId)))
        .getSingle();
    expect(
      product.lastPurchasePriceCents,
      isNotNull,
      reason: 'Non-variant branch must stamp the supplier reference price '
          'on the products row directly.',
    );
    expect(
      product.lastPurchasePriceCents!.toBigInt().toInt(),
      equals(grossUnit),
    );

    final defaultVariant = await (db.select(db.productVariants)
          ..where((v) => v.id.equals(defaultVariantId)))
        .getSingle();
    expect(
      defaultVariant.lastPurchasePriceCents,
      isNotNull,
      reason: 'Default-variant mirror must carry the same gross supplier '
          'price so variant-level UI reads stay consistent.',
    );
    expect(
      defaultVariant.lastPurchasePriceCents!.toBigInt().toInt(),
      equals(grossUnit),
    );
  });

  // ──────────────────────────────────────────────────────────────────────
  // 4) A second purchase at a different unit cost refreshes
  //    `last_purchase_price_cents` — semantically it is "the latest list
  //    price", not a historical average.
  // ──────────────────────────────────────────────────────────────────────
  test(
      'second purchase at a new gross unit cost overwrites '
      'last_purchase_price_cents (latest list price wins)', () async {
    final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Refresh Test Product',
            costCents: Decimal.fromInt(0),
            priceCents: Decimal.fromInt(0),
            currencyId: Value(currencyId),
            hasVariants: const Value(true),
            stockQuantity: const Value(0),
          ),
        );
    final variantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(0),
            costCents: Decimal.fromInt(0),
            priceCents: Decimal.fromInt(0),
          ),
        );

    Future<void> postPurchaseAt({
      required String number,
      required int qty,
      required int grossUnit,
      int lineDiscount = 0,
    }) async {
      final subtotal = qty * grossUnit;
      final net = subtotal - lineDiscount;
      final purchaseId = await db.into(db.purchases).insert(
            PurchasesCompanion.insert(
              purchaseNumber: number,
              supplierId: supplierId,
              subtotalCents: Decimal.fromInt(subtotal),
              discountCents: Value(Decimal.fromInt(lineDiscount)),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(net),
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
              quantity: qty,
              unitCostCents: Decimal.fromInt(grossUnit),
              discountCents: Value(Decimal.fromInt(lineDiscount)),
              subtotalCents: Decimal.fromInt(subtotal),
              totalCents: Decimal.fromInt(net),
            ),
          );
      await db.purchaseDao.postPurchase(purchaseId);
    }

    // First purchase: gross 100, discount 10 → net 99 per unit.
    await postPurchaseAt(
      number: 'PO-LPP-004A',
      qty: 10,
      grossUnit: 100,
      lineDiscount: 10,
    );
    var variant = await (db.select(db.productVariants)
          ..where((v) => v.id.equals(variantId)))
        .getSingle();
    expect(variant.lastPurchasePriceCents!.toBigInt().toInt(), equals(100));

    // Second purchase at a new list price of 150 (no discount). The new
    // supplier list price must replace the old one.
    await postPurchaseAt(
      number: 'PO-LPP-004B',
      qty: 5,
      grossUnit: 150,
    );
    variant = await (db.select(db.productVariants)
          ..where((v) => v.id.equals(variantId)))
        .getSingle();
    expect(
      variant.lastPurchasePriceCents!.toBigInt().toInt(),
      equals(150),
      reason:
          'last_purchase_price_cents must reflect the MOST RECENT supplier '
          'list price, not a historical aggregate.',
    );

    // Parent product row stays in sync via syncProductFromVariants
    // (MAX aggregation across active variants — here only one).
    final product = await (db.select(db.products)
          ..where((p) => p.id.equals(productId)))
        .getSingle();
    expect(
      product.lastPurchasePriceCents!.toBigInt().toInt(),
      equals(150),
    );
  });
}
