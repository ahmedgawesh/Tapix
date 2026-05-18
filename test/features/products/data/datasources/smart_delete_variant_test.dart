import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

/// Regression tests for variant-level smart delete (audit gap #16).
///
/// QuickBooks/Xero/Odoo invariants enforced here:
///   * variant with NO references          -> hard delete
///   * variant with sale/purchase/return/adjustment/batch refs -> soft delete
///     (`is_active = 0`) so journal entries, COGS history and audit trail
///     stay reproducible.
///   * `products.has_variants` flips to false only when no dimensional
///     variants remain active.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.into(db.currencies).insert(
          CurrenciesCompanion.insert(
            code: 'TST',
            name: 'Test',
            symbol: 'T',
            exchangeRate: Decimal.fromInt(1),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertProduct({bool hasVariants = true}) {
    return db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Prod',
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
            currencyId: const Value(1),
            hasVariants: Value(hasVariants),
          ),
        );
  }

  Future<int> insertVariant(int productId, {int? colorId, int? sizeId}) {
    return db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            colorId: Value(colorId),
            sizeId: Value(sizeId),
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
            priceAdjustmentCents: Value(Decimal.zero),
            stockQuantity: const Value(5),
          ),
        );
  }

  test('smartDeleteVariant hard-deletes when no references exist', () async {
    final productId = await insertProduct();
    final colorId = await db.into(db.productColors).insert(
          ProductColorsCompanion.insert(name: 'Red', hexCode: const Value('#FF0000')),
        );
    final variantId = await insertVariant(productId, colorId: colorId);

    final result = await db.productVariantDao.smartDeleteVariant(variantId);

    expect(result.wasDeleted, isTrue);
    expect(result.referenceCount, equals(0));
    final row = await (db.select(db.productVariants)
          ..where((v) => v.id.equals(variantId)))
        .getSingleOrNull();
    expect(row, isNull, reason: 'variant row must be removed when unreferenced');

    // No active dimensional variants left -> products.has_variants = 0.
    final prod = await (db.select(db.products)
          ..where((p) => p.id.equals(productId)))
        .getSingle();
    expect(prod.hasVariants, isFalse);
  });

  test('smartDeleteVariant soft-deletes when a purchase item references it',
      () async {
    final productId = await insertProduct();
    final colorId = await db.into(db.productColors).insert(
          ProductColorsCompanion.insert(name: 'Blue', hexCode: const Value('#0000FF')),
        );
    final variantId = await insertVariant(productId, colorId: colorId);

    // Seed a supplier + purchase with one item referencing the variant.
    final supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(name: 'S1', currencyId: 1),
        );
    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'P-1',
            supplierId: supplierId,
            currencyId: 1,
            subtotalCents: Decimal.fromInt(500),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(500),
          ),
        );
    await db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            variantId: Value(variantId),
            quantity: 1,
            unitCostCents: Decimal.fromInt(500),
            subtotalCents: Decimal.fromInt(500),
            totalCents: Decimal.fromInt(500),
          ),
        );

    final refsBefore = await db.productVariantDao.countVariantReferences(variantId);
    expect(refsBefore, equals(1));

    final result = await db.productVariantDao.smartDeleteVariant(variantId);

    expect(result.wasDeleted, isFalse,
        reason: 'variant with refs must be soft-deleted to preserve audit trail');
    expect(result.referenceCount, equals(1));

    final variant = await (db.select(db.productVariants)
          ..where((v) => v.id.equals(variantId)))
        .getSingle();
    expect(variant.isActive, isFalse,
        reason: 'variant row must still exist but inactive');

    // Original purchase item must still reference the variant unchanged.
    final pi = await (db.select(db.purchaseItems)
          ..where((p) => p.variantId.equals(variantId)))
        .getSingle();
    expect(pi.variantId, equals(variantId));
  });

  test(
      'smartDeleteVariant keeps products.has_variants=true when other active dimensional variants remain',
      () async {
    final productId = await insertProduct();
    final colorRed = await db.into(db.productColors).insert(
          ProductColorsCompanion.insert(name: 'Red', hexCode: const Value('#FF0000')),
        );
    final colorBlue = await db.into(db.productColors).insert(
          ProductColorsCompanion.insert(name: 'Blue', hexCode: const Value('#0000FF')),
        );
    final v1 = await insertVariant(productId, colorId: colorRed);
    await insertVariant(productId, colorId: colorBlue);

    final result = await db.productVariantDao.smartDeleteVariant(v1);
    expect(result.wasDeleted, isTrue);

    final prod = await (db.select(db.products)
          ..where((p) => p.id.equals(productId)))
        .getSingle();
    expect(prod.hasVariants, isTrue,
        reason: 'has_variants must stay true while other dimensional variants exist');
  });

  test('watchVariantsByProduct excludes soft-deleted variants', () async {
    final productId = await insertProduct();
    final colorId = await db.into(db.productColors).insert(
          ProductColorsCompanion.insert(name: 'Red', hexCode: const Value('#FF0000')),
        );
    final variantId = await insertVariant(productId, colorId: colorId);

    // Seed a sale_items reference so the smart delete soft-deletes.
    final customerId = await db.into(db.customers).insert(
          CustomersCompanion.insert(name: 'C1', currencyId: 1),
        );
    final saleId = await db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: 'S-1',
            customerId: Value(customerId),
            currencyId: 1,
            subtotalCents: Decimal.fromInt(1000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(1000),
            paymentMethod: 'cash',
          ),
        );
    await db.into(db.saleItems).insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            variantId: Value(variantId),
            quantity: 1,
            unitPriceCents: Decimal.fromInt(1000),
            subtotalCents: Decimal.fromInt(1000),
            totalCents: Decimal.fromInt(1000),
          ),
        );

    final result = await db.productVariantDao.smartDeleteVariant(variantId);
    expect(result.wasDeleted, isFalse);

    final visible = await db.productVariantDao
        .watchVariantsByProduct(productId)
        .first;
    expect(visible, isEmpty,
        reason: 'soft-deleted variants must drop out of the watch stream');
  });
}
