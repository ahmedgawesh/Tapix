import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/stock_service.dart';

void main() {
  test(
    '10068 merges a split simple product without changing its operational id',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'tapix-simple-product-migration-',
      );
      final file = File('${temp.path}/tapix.db');
      AppDatabase? db;
      try {
        db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
        await db.customSelect('SELECT 1').get();
        final currency = await (db.select(
          db.currencies,
        )..where((c) => c.code.equals('USD'))).getSingle();
        final colorId = (await (db.select(
          db.productColors,
        )..where((c) => c.name.equals('Purple'))).getSingle()).id;
        final sizeId = await db
            .into(db.sizes)
            .insert(SizesCompanion.insert(name: 'عرض عرضين'));
        final productId = await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                name: 'قماش كريب',
                sku: const Value('KR1'),
                barcode: const Value('2057373895281'),
                costCents: Decimal.fromInt(1980),
                priceCents: Decimal.fromInt(3500),
                stockQuantity: const Value(1000),
                hasVariants: const Value(false),
                measurementType: const Value('length'),
                currencyId: Value(currency.id),
              ),
            );

        // v10067 regression shape: attributes/identity stayed here...
        final metadataId = await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                productId: productId,
                sku: const Value('KR1'),
                barcode: const Value('2057373895281'),
                colorId: Value(colorId),
                sizeId: Value(sizeId),
                costCents: Decimal.zero,
                priceCents: Decimal.zero,
                stockQuantity: const Value(0),
              ),
            );
        // ...while stock and invoice lineage moved to this generated row.
        final operationalId = await db
            .into(db.productVariants)
            .insert(
              ProductVariantsCompanion.insert(
                productId: productId,
                barcode: const Value('2900000000254'),
                costCents: Decimal.fromInt(1980),
                priceCents: Decimal.fromInt(3500),
                stockQuantity: const Value(1000),
              ),
            );
        await db.customStatement(
          'INSERT INTO product_price_histories ('
          'product_id, variant_id, old_cost_cents, new_cost_cents, '
          'old_price_cents, new_price_cents'
          ') VALUES (?, ?, 1980, 1980, 3500, 3500)',
          [productId, operationalId],
        );
        await db.customStatement(
          'INSERT INTO print_histories (product_id, variant_id, '
          'quantity_printed) VALUES (?, ?, 1)',
          [productId, metadataId],
        );

        await db.customStatement('PRAGMA user_version = 10067');
        await db.close();
        db = null;

        db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
        await db.customSelect('SELECT 1').get();

        final variants = await (db.select(
          db.productVariants,
        )..where((v) => v.productId.equals(productId))).get();
        expect(variants, hasLength(1));
        final canonical = variants.single;
        expect(canonical.id, operationalId);
        expect(canonical.sku, 'KR1');
        expect(canonical.barcode, '2057373895281');
        expect(canonical.colorId, colorId);
        expect(canonical.sizeId, sizeId);
        expect(canonical.stockQuantity, 1000);
        expect(canonical.costCents.toBigInt().toInt(), 1980);

        final history = await db
            .customSelect(
              'SELECT variant_id FROM product_price_histories '
              'WHERE product_id = ?',
              variables: [Variable.withInt(productId)],
            )
            .getSingle();
        expect(history.read<int>('variant_id'), operationalId);
        final print = await db
            .customSelect(
              'SELECT variant_id FROM print_histories WHERE product_id = ?',
              variables: [Variable.withInt(productId)],
            )
            .getSingle();
        expect(print.read<int>('variant_id'), operationalId);

        final info = await db.productVariantDao.getVariantInfoByProductIds([
          productId,
        ]);
        expect(info[productId], 'عرض عرضين / Purple');

        // A null-variant stock call must still target this dimensional row.
        await StockService.adjustStock(
          db.productVariantDao,
          productId: productId,
          quantity: 500,
          direction: StockDirection.increase,
        );
        final after = await (db.select(
          db.productVariants,
        )..where((v) => v.id.equals(operationalId))).getSingle();
        expect(after.stockQuantity, 1500);
        expect(db.schemaVersion, 10070);
      } finally {
        await db?.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
