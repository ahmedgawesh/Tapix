import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/migrations/sale_adjustment_return_item_immutability.dart';

AppDatabase _memoryDb() =>
    AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));

void main() {
  test(
    'sealed sale adjustment return items reject raw insert update delete',
    () async {
      final db = _memoryDb();
      addTearDown(db.close);
      await installSaleAdjustmentReturnItemImmutabilityGuards(db);

      final currency = (await (db.select(
        db.currencies,
      )..where((row) => row.code.equals('USD'))).getSingle()).id;
      final product = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Immutable return product',
              currencyId: Value(currency),
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(150),
            ),
          );
      final variant = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: product,
              costCents: Decimal.fromInt(100),
              priceCents: Decimal.fromInt(150),
            ),
          );
      final returnId = await db
          .into(db.saleReturnAdjustments)
          .insert(
            SaleReturnAdjustmentsCompanion.insert(
              returnNumber: 'SAR-IMMUTABLE-001',
              currencyId: currency,
              totalCents: Decimal.fromInt(150),
            ),
          );
      final itemId = await db
          .into(db.saleReturnAdjustmentItems)
          .insert(
            SaleReturnAdjustmentItemsCompanion.insert(
              returnId: returnId,
              productId: product,
              variantId: Value(variant),
              quantity: 1,
              unitPriceCents: Decimal.fromInt(150),
              totalCents: Decimal.fromInt(150),
              sourceResolution: const Value('unverified'),
            ),
          );

      // Draft lines remain editable.
      await db.customStatement(
        'UPDATE sale_return_adjustment_items SET quantity=2 WHERE id=?',
        [itemId],
      );
      await db.customStatement(
        "UPDATE sale_return_adjustments SET status='posted' WHERE id=?",
        [returnId],
      );

      await expectLater(
        db.customStatement(
          'UPDATE sale_return_adjustment_items SET quantity=3 WHERE id=?',
          [itemId],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO sale_return_adjustment_items('
          'return_id,product_id,variant_id,quantity,unit_price_cents,'
          'total_cents,source_resolution) VALUES(?,?,?,?,?,?,?)',
          [returnId, product, variant, 1, 150, 150, 'unverified'],
        ),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'DELETE FROM sale_return_adjustment_items WHERE id=?',
          [itemId],
        ),
        throwsA(anything),
      );

      final preserved = await (db.select(
        db.saleReturnAdjustmentItems,
      )..where((row) => row.id.equals(itemId))).getSingle();
      expect(preserved.quantity, 2);
    },
  );
}
