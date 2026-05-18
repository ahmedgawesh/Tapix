// Regression test for the multi-variant purchase rendering bug.
//
// Bug (May 2026):
// `purchase_detail_screen` looked up variant color/size via
// `ProductVariantRepository.watchVariantPreviews()`, a stream keyed by
// `productId` that exposes ONLY the first active variant per product.
// Every line of an invoice that bought multiple variants of the same
// product therefore rendered with the first variant's attributes — even
// though `purchase_items.variant_id` held the correct id.
//
// Root-cause fix: `PurchaseDao.getPurchaseItemsWithDetails` now joins
// `productColors` and `sizes` keyed by the line's own `variantId`, and
// `PurchaseItemEntity` carries `colorName`/`colorHex`/`sizeName`. The
// UI consumes these per-line fields directly (mirroring the existing
// sale/return detail screens).
//
// This test exercises the DAO end-to-end with a real in-memory DB and
// asserts that each line of a multi-variant purchase carries its own
// resolved attributes.
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  late int supplierId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    currencyId = (await db.select(db.currencies).get()).first.id;
    supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'Acme Supplies',
            currencyId: currencyId,
          ),
        );
  });

  tearDown(() async => db.close());

  test(
      'BUG REGRESSION: each line of a multi-variant purchase carries its OWN '
      'color/size — productId-keyed lookups would collapse them to the '
      'first variant', () async {
    // Product with two variants: Blue/Small + White/Medium.
    final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Variant Product',
            costCents: Decimal.fromInt(5000),
            priceCents: Decimal.fromInt(7500),
            currencyId: Value(currencyId),
            hasVariants: const Value(true),
          ),
        );
    final blueId = await db.into(db.productColors).insert(
          ProductColorsCompanion.insert(
            name: 'Blue',
            hexCode: const Value('#0000FF'),
          ),
        );
    final whiteId = await db.into(db.productColors).insert(
          ProductColorsCompanion.insert(
            name: 'White',
            hexCode: const Value('#FFFFFF'),
          ),
        );
    final smallId = await db.into(db.sizes).insert(
          SizesCompanion.insert(name: 'Small'),
        );
    final mediumId = await db.into(db.sizes).insert(
          SizesCompanion.insert(name: 'Medium'),
        );

    final blueSmallVariantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            sku: const Value('VP-1'),
            colorId: Value(blueId),
            sizeId: Value(smallId),
            costCents: Decimal.fromInt(5000),
            priceCents: Decimal.fromInt(7500),
          ),
        );
    final whiteMediumVariantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            sku: const Value('VP-2'),
            colorId: Value(whiteId),
            sizeId: Value(mediumId),
            costCents: Decimal.fromInt(5000),
            priceCents: Decimal.fromInt(7500),
          ),
        );

    // Insert a purchase with both variants as separate lines.
    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'P-MULTI-VARIANT-1',
            supplierId: supplierId,
            currencyId: currencyId,
            subtotalCents: Decimal.fromInt(10000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(10000),
          ),
        );
    await db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            variantId: Value(blueSmallVariantId),
            quantity: 1,
            unitCostCents: Decimal.fromInt(5000),
            subtotalCents: Decimal.fromInt(5000),
            totalCents: Decimal.fromInt(5000),
          ),
        );
    await db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            variantId: Value(whiteMediumVariantId),
            quantity: 1,
            unitCostCents: Decimal.fromInt(5000),
            subtotalCents: Decimal.fromInt(5000),
            totalCents: Decimal.fromInt(5000),
          ),
        );

    final details =
        await db.purchaseDao.getPurchaseItemsWithDetails(purchaseId);
    expect(details.length, equals(2));

    // Each row resolves color/size from its own variantId — not from
    // "the first variant of the product".
    final byVariantId = {for (final d in details) d.item.variantId: d};

    final blueLine = byVariantId[blueSmallVariantId]!;
    expect(blueLine.colorName, equals('Blue'));
    expect(blueLine.colorHex, equals('#0000FF'));
    expect(blueLine.sizeName, equals('Small'));

    final whiteLine = byVariantId[whiteMediumVariantId]!;
    expect(whiteLine.colorName, equals('White'));
    expect(whiteLine.colorHex, equals('#FFFFFF'));
    expect(whiteLine.sizeName, equals('Medium'));
  });

  test(
      'lines without a variantId resolve color/size to null '
      '(no false-positive attribution)', () async {
    final productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'No-variant Item',
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
            currencyId: Value(currencyId),
            hasVariants: const Value(false),
          ),
        );
    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'P-NO-VARIANT-1',
            supplierId: supplierId,
            currencyId: currencyId,
            subtotalCents: Decimal.fromInt(2000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(2000),
          ),
        );
    await db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            // variantId omitted (truly null legacy row)
            quantity: 2,
            unitCostCents: Decimal.fromInt(1000),
            subtotalCents: Decimal.fromInt(2000),
            totalCents: Decimal.fromInt(2000),
          ),
        );

    final details =
        await db.purchaseDao.getPurchaseItemsWithDetails(purchaseId);
    expect(details.length, equals(1));
    expect(details.first.colorName, isNull);
    expect(details.first.colorHex, isNull);
    expect(details.first.sizeName, isNull);
  });
}
