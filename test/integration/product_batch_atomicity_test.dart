import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
  });

  tearDown(() => db.close());

  test('product and variant batch rolls back as one aggregate', () async {
    await expectLater(
      db.productDao.runInTransaction<void>(() async {
        final ids = await db.productDao.bulkCreateProducts([
          ProductsCompanion.insert(
            name: 'Atomic product',
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
            hasVariants: const Value(true),
          ),
        ]);
        await db.productVariantDao.createVariant(
          ProductVariantsCompanion.insert(
            productId: ids.values.single,
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
          ),
        );
        throw StateError('simulate a later row failure');
      }),
      throwsA(isA<StateError>()),
    );

    expect(await db.select(db.products).get(), isEmpty);
    expect(await db.select(db.productVariants).get(), isEmpty);
  });

  test('import-created metadata also rolls back with the file', () async {
    final categoryCountBefore =
        (await db.select(db.productCategories).get()).length;
    final colorCountBefore = (await db.select(db.productColors).get()).length;
    final sizeCountBefore = (await db.select(db.sizes).get()).length;
    final productCountBefore = (await db.select(db.products).get()).length;
    final variantCountBefore =
        (await db.select(db.productVariants).get()).length;

    await expectLater(
      db.productDao.runInTransaction<void>(() async {
        final categoryId = await db
            .into(db.productCategories)
            .insert(ProductCategoriesCompanion.insert(name: 'Imported'));
        final colorId = await db
            .into(db.productColors)
            .insert(ProductColorsCompanion.insert(name: 'Atomic Azure'));
        final sizeId = await db
            .into(db.sizes)
            .insert(SizesCompanion.insert(name: 'Atomic Large'));
        final productId = await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                name: 'Imported product',
                categoryId: Value(categoryId),
                costCents: Decimal.fromInt(500),
                priceCents: Decimal.fromInt(1000),
                hasVariants: const Value(true),
              ),
            );
        await db.productVariantDao.createVariant(
          ProductVariantsCompanion.insert(
            productId: productId,
            colorId: Value(colorId),
            sizeId: Value(sizeId),
            costCents: Decimal.fromInt(500),
            priceCents: Decimal.fromInt(1000),
          ),
        );
        throw StateError('simulate an invalid later import row');
      }),
      throwsA(isA<StateError>()),
    );

    expect(
      (await db.select(db.productCategories).get()).length,
      categoryCountBefore,
    );
    expect((await db.select(db.productColors).get()).length, colorCountBefore);
    expect((await db.select(db.sizes).get()).length, sizeCountBefore);
    expect((await db.select(db.products).get()).length, productCountBefore);
    expect(
      (await db.select(db.productVariants).get()).length,
      variantCountBefore,
    );
  });
}
