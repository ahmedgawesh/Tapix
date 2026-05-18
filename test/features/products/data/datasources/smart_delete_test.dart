import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';

/// Regression tests for the smart-delete flow introduced in Phase 2 of the
/// products-module audit.
///
/// Product with *no* historical references -> hard delete.
/// Product *with* historical references -> deactivated; variants cascade to
/// is_active=false. Never hard-deleted (would break COGS + audit trail).
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

  Future<int> insertProduct({bool hasVariants = false}) {
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

  Future<int> insertVariant(int productId) {
    return db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
            priceAdjustmentCents: Value(Decimal.zero),
            stockQuantity: const Value(5),
          ),
        );
  }

  test('smartDeleteProduct hard-deletes when there are no references',
      () async {
    final productId = await insertProduct();
    await insertVariant(productId);

    final result = await db.productDao.smartDeleteProduct(productId);

    expect(result.wasDeleted, isTrue);
    expect(result.referenceCount, equals(0));
    final row = await (db.select(db.products)
          ..where((p) => p.id.equals(productId)))
        .getSingleOrNull();
    expect(row, isNull, reason: 'row must be removed when no references exist');
  });

  test('smartDeleteProduct soft-deletes when there are sale/purchase refs',
      () async {
    final productId = await insertProduct();
    final variantId = await insertVariant(productId);

    // Seed a supplier + purchase with one item referencing the product.
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

    final refCountBefore = await db.productDao.countProductReferences(productId);
    expect(refCountBefore, equals(1));

    final result = await db.productDao.smartDeleteProduct(productId);

    expect(result.wasDeleted, isFalse,
        reason: 'product with references must be soft-deleted to preserve audit trail');
    expect(result.referenceCount, equals(1));

    final prod = await (db.select(db.products)
          ..where((p) => p.id.equals(productId)))
        .getSingle();
    expect(prod.isActive, isFalse,
        reason: 'product row must still exist but inactive');

    final variants = await (db.select(db.productVariants)
          ..where((v) => v.productId.equals(productId)))
        .get();
    expect(variants, isNotEmpty);
    expect(
      variants.every((v) => v.isActive == false),
      isTrue,
      reason: 'all variants must cascade to inactive',
    );
  });
}
