import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/products/data/datasources/variant_local_datasource.dart';
import 'package:tapix/features/products/data/models/product_color_model.dart';
import 'package:tapix/features/products/data/models/product_variant_model.dart';

/// Regression: updateVariant must preserve the original `createdAt`.
/// Before the fix, every update rewrote createdAt = DateTime.now(),
/// corrupting aging reports and SKU lifecycle tracking.
void main() {
  late AppDatabase db;
  late VariantLocalDatasourceImpl datasource;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    datasource = VariantLocalDatasourceImpl(
      db.productVariantDao,
      db.productColorDao,
      db.sizeDao,
    );

    // Seed a currency + product so variant FKs resolve.
    final currencyId = await db
        .into(db.currencies)
        .insert(
          CurrenciesCompanion.insert(
            code: 'TST',
            name: 'Test',
            symbol: 'T',
            exchangeRate: Decimal.fromInt(1),
          ),
        );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            name: 'Prod',
            costCents: Decimal.zero,
            priceCents: Decimal.zero,
            currencyId: Value(currencyId),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  test('updateVariant preserves original createdAt', () async {
    final originalCreatedAt = DateTime(2024, 1, 1, 12, 0, 0);

    // Insert variant with a known createdAt directly via Drift.
    final variantId = await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: 1,
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
            priceAdjustmentCents: Value(Decimal.zero),
            stockQuantity: const Value(10),
            createdAt: Value(originalCreatedAt),
          ),
        );

    // Sanity check.
    final before = await db.productVariantDao.getVariantById(variantId);
    expect(before?.createdAt, equals(originalCreatedAt));

    // Perform an unrelated update via the datasource (change price only).
    await datasource.updateVariant(
      ProductVariantModel(
        id: variantId,
        productId: 1,
        costCents: Decimal.fromInt(1000),
        priceCents: Decimal.fromInt(2500), // changed
        priceAdjustmentCents: Decimal.zero,
        stockQuantity: 10,
        isActive: true,
      ),
    );

    // Verify createdAt was NOT overwritten.
    final after = await db.productVariantDao.getVariantById(variantId);
    expect(after, isNotNull);
    expect(
      after!.createdAt,
      equals(originalCreatedAt),
      reason: 'updateVariant must never rewrite createdAt',
    );
    expect(after.priceCents, equals(Decimal.fromInt(2500)));
    expect(
      after.updatedAt.isAfter(originalCreatedAt),
      isTrue,
      reason: 'updatedAt should advance on update',
    );
  });

  test('updateColor preserves original createdAt', () async {
    final originalCreatedAt = DateTime(2023, 6, 15);
    final colorId = await db
        .into(db.productColors)
        .insert(
          ProductColorsCompanion.insert(
            name: 'Blue',
            hexCode: const Value('#0000FF'),
            createdAt: Value(originalCreatedAt),
          ),
        );

    await datasource.updateColor(
      ProductColorModel(
        id: colorId,
        name: 'Navy',
        hexCode: '#000080',
        isActive: true,
      ),
    );

    final after = await db.productColorDao.getColorById(colorId);
    expect(after?.createdAt, equals(originalCreatedAt));
    expect(after?.name, equals('Navy'));
  });
}
