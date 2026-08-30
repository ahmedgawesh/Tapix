import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/price_history_service.dart';
import 'package:tapix/features/products/data/datasources/product_local_datasource.dart';
import 'package:tapix/features/products/data/models/product_model.dart';

void main() {
  test('new price-history writes preserve exact integer cents', () async {
    final db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    try {
      await db.customSelect('SELECT 1').get();
      final currency = await (db.select(
        db.currencies,
      )..where((c) => c.code.equals('USD'))).getSingle();
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Exact cents',
              costCents: Decimal.fromInt(1188),
              priceCents: Decimal.fromInt(2500),
              currencyId: Value(currency.id),
            ),
          );

      await PriceHistoryService.recordIfChanged(
        db.productDao,
        productId: productId,
        oldCostCents: 1188,
        newCostCents: 1275,
        oldPriceCents: 2500,
        newPriceCents: 2599,
        oldWholesalePriceCents: 2005,
        newWholesalePriceCents: 2117,
        changeReason: 'exact_cents_test',
      );

      final raw = await db
          .customSelect(
            'SELECT old_cost_cents, new_cost_cents, old_price_cents, '
            'new_price_cents, old_wholesale_price_cents, '
            'new_wholesale_price_cents FROM product_price_histories',
          )
          .getSingle();
      expect(raw.read<int>('old_cost_cents'), 1188);
      expect(raw.read<int>('new_cost_cents'), 1275);
      expect(raw.read<int>('old_price_cents'), 2500);
      expect(raw.read<int>('new_price_cents'), 2599);
      expect(raw.read<int>('old_wholesale_price_cents'), 2005);
      expect(raw.read<int>('new_wholesale_price_cents'), 2117);

      final history = await ProductLocalDatasourceImpl(
        db.productDao,
      ).getPriceHistory(productId);
      expect(history.single.oldCostCents, 1188);
      expect(history.single.newPriceCents, 2599);
      expect(history.single.newWholesalePriceCents, 2117);
    } finally {
      await db.close();
    }
  });

  test(
    'central product update writes history and protects ledger cost',
    () async {
      final db = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      try {
        await db.customSelect('SELECT 1').get();
        final currency = await (db.select(
          db.currencies,
        )..where((c) => c.code.equals('USD'))).getSingle();
        final productId = await db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                name: 'Central history product',
                costCents: Decimal.fromInt(1188),
                priceCents: Decimal.fromInt(2500),
                wholesalePriceCents: Value(Decimal.fromInt(2000)),
                currencyId: Value(currency.id),
              ),
            );
        final datasource = ProductLocalDatasourceImpl(db.productDao);
        final product = await datasource.getProductById(productId);

        await datasource.updateProduct(
          ProductModel.fromEntity(
            product!.copyWith(
              // A generic metadata/price update may not revalue inventory cost.
              costCents: Decimal.fromInt(9999),
              priceCents: Decimal.fromInt(2599),
              wholesalePriceCents: Decimal.fromInt(2117),
            ),
          ),
        );

        final persisted = await (db.select(
          db.products,
        )..where((p) => p.id.equals(productId))).getSingle();
        expect(persisted.costCents.toBigInt().toInt(), 1188);
        expect(persisted.priceCents.toBigInt().toInt(), 2599);

        final row = await (db.select(
          db.productPriceHistories,
        )..where((h) => h.productId.equals(productId))).getSingle();
        expect(row.oldCostCents.toBigInt().toInt(), 1188);
        expect(row.newCostCents.toBigInt().toInt(), 1188);
        expect(row.oldPriceCents.toBigInt().toInt(), 2500);
        expect(row.newPriceCents.toBigInt().toInt(), 2599);
        expect(row.oldWholesalePriceCents?.toBigInt().toInt(), 2000);
        expect(row.newWholesalePriceCents?.toBigInt().toInt(), 2117);
        expect(row.changeReason, 'product_update');
      } finally {
        await db.close();
      }
    },
  );

  test('10067 migrates legacy rows and recovers purchase snapshots', () async {
    final temp = await Directory.systemTemp.createTemp(
      'tapix-price-history-migration-',
    );
    final file = File('${temp.path}/tapix.db');
    AppDatabase? db;
    try {
      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await db.customSelect('SELECT 1').get();
      final currency = await (db.select(
        db.currencies,
      )..where((c) => c.code.equals('USD'))).getSingle();
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'History supplier',
              currencyId: currency.id,
              balanceCents: Value(Decimal.zero),
            ),
          );
      final productId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Migrated price product',
              costCents: Decimal.fromInt(1275),
              priceCents: Decimal.fromInt(2700),
              wholesalePriceCents: Value(Decimal.fromInt(2200)),
              currencyId: Value(currency.id),
            ),
          );
      final variantId = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: productId,
              costCents: Decimal.fromInt(1275),
              priceCents: Decimal.fromInt(2700),
              wholesalePriceCents: Value(Decimal.fromInt(2200)),
            ),
          );
      final purchaseId = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'PI-MIGRATION-HISTORY',
              supplierId: supplierId,
              subtotalCents: Decimal.fromInt(1275),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(1275),
              currencyId: currency.id,
              paymentMethod: const Value('cash'),
            ),
          );
      await db
          .into(db.purchaseItems)
          .insert(
            PurchaseItemsCompanion.insert(
              purchaseId: purchaseId,
              productId: productId,
              variantId: Value(variantId),
              quantity: 1,
              unitCostCents: Decimal.fromInt(1275),
              originalCostCents: Value(Decimal.fromInt(1188)),
              originalPriceCents: Value(Decimal.fromInt(2500)),
              newSellPriceCents: Value(Decimal.fromInt(2700)),
              originalWholesalePriceCents: Value(Decimal.fromInt(2000)),
              newWholesalePriceCents: Value(Decimal.fromInt(2200)),
              subtotalCents: Decimal.fromInt(1275),
              totalCents: Decimal.fromInt(1275),
            ),
          );

      // Simulate the pre-10067 writer after MoneyConverter truncated the
      // divided values to whole major units.
      await db.customStatement(
        'INSERT INTO product_price_histories ('
        'product_id, variant_id, old_cost_cents, new_cost_cents, '
        'old_price_cents, new_price_cents, old_wholesale_price_cents, '
        'new_wholesale_price_cents, change_reason, created_at'
        ') VALUES (?, ?, 11, 12, 25, 27, 20, 22, ?, ?)',
        [
          productId,
          variantId,
          'purchase_post:#$purchaseId',
          DateTime(2026, 8, 16).toIso8601String(),
        ],
      );
      await db.customStatement('PRAGMA user_version = 10066');
      await db.close();
      db = null;

      db = AppDatabase.connect(DatabaseConnection(NativeDatabase(file)));
      await db.customSelect('SELECT 1').get();

      final row = await db
          .customSelect(
            'SELECT old_cost_cents, new_cost_cents, old_price_cents, '
            'new_price_cents, old_wholesale_price_cents, '
            'new_wholesale_price_cents FROM product_price_histories',
          )
          .getSingle();
      expect(row.read<int>('old_cost_cents'), 1188);
      expect(row.read<int>('new_cost_cents'), 1275);
      expect(row.read<int>('old_price_cents'), 2500);
      expect(row.read<int>('new_price_cents'), 2700);
      expect(row.read<int>('old_wholesale_price_cents'), 2000);
      expect(row.read<int>('new_wholesale_price_cents'), 2200);
      expect(db.schemaVersion, 10070);
    } finally {
      await db?.close();
      await temp.delete(recursive: true);
    }
  });
}
