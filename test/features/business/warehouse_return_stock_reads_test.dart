import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/loyalty/loyalty_points_service.dart';
import 'package:tapix/core/services/unified_return_service.dart';
import 'package:tapix/core/services/void_impact_analyzer.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/customers/data/repositories/loyalty_repository_impl.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late UnifiedReturnService returns;
  late int product, variant, purchase;
  late String warehouse;
  Future<int> insert(
    String table,
    Map<String, Object> values,
  ) => db.customInsert(
    'INSERT INTO $table (${values.keys.join(',')}) VALUES (${List.filled(values.length, '?').join(',')})',
    variables: values.values
        .map(
          (v) =>
              v is int ? Variable.withInt(v) : Variable.withString(v as String),
        )
        .toList(),
  );
  setUp(() async {
    db = fixtures.memoryDb();
    final journal = JournalEntryService(AccountingRepository(db));
    returns = UnifiedReturnService(
      db,
      db.purchaseDao,
      db.saleDao,
      AdjustmentReturnDao(db),
      journal,
      CommissionService(db.employeeDao),
      LoyaltyPointsService(LoyaltyRepositoryImpl(db, journal), journal, db),
    );
    product = await insert('products', {
      'name': 'Local',
      'cost_cents': 500,
      'price_cents': 1000,
      'stock_quantity': 99,
    });
    final size = await insert('sizes', {'name': 'Optional'});
    variant = await insert('product_variants', {
      'product_id': product,
      'size_id': size,
      'cost_cents': 500,
      'price_cents': 1000,
      'stock_quantity': 99,
    });
    final scope = await BusinessFoundationRepository(db).getScope();
    warehouse = scope.warehouseId;
    final other = const Uuid().v4();
    await db
        .into(db.businessWarehouses)
        .insert(
          BusinessWarehousesCompanion.insert(
            id: other,
            organizationId: scope.organizationId,
            branchId: scope.branchId,
            code: 'OTHER',
          ),
        );
    await db
        .into(db.businessWarehouseStocks)
        .insert(
          BusinessWarehouseStocksCompanion.insert(
            warehouseId: other,
            variantId: variant,
            quantity: const Value(1000),
          ),
        );
    await db.customStatement('DROP TRIGGER business_stock_primary_update');
    await db.customStatement(
      'UPDATE business_warehouse_stocks SET quantity = 2 WHERE warehouse_id = ?',
      [warehouse],
    );
    final currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    final supplier = await insert('suppliers', {
      'name': 'Supplier',
      'currency_id': currency,
    });
    purchase = await insert('purchases', {
      'purchase_number': 'P1',
      'supplier_id': supplier,
      'currency_id': currency,
      'status': 'posted',
      'subtotal_cents': 5000,
      'tax_cents': 0,
      'total_cents': 5000,
    });
    await insert('purchase_items', {
      'purchase_id': purchase,
      'product_id': product,
      'quantity': 5,
      'unit_cost_cents': 1000,
      'subtotal_cents': 5000,
      'total_cents': 5000,
    });
  });
  tearDown(() => db.close());

  for (final hasVariants in [false, true]) {
    for (final side in ReturnSide.values) {
      test(
        'search variants=$hasVariants side=$side reads local stock and preserves price',
        () async {
          await db.customStatement(
            'UPDATE products SET has_variants = ? WHERE id = ?',
            [hasVariants ? 1 : 0, product],
          );
          final result = await returns.searchProducts('Local', side: side);
          expect(result, hasLength(1));
          expect(result.single.stockQuantity, 2);
          expect(result.single.variantLabel, contains('Optional'));
          expect(
            result.single.lastPriceCents,
            side == ReturnSide.sale ? 1000 : 500,
          );
        },
      );
    }
    test(
      'purchase void variants=$hasVariants warns from local balance',
      () async {
        if (hasVariants) {
          await db.customStatement(
            'UPDATE products SET has_variants = 1 WHERE id = ?',
            [product],
          );
          await db.customStatement(
            'UPDATE purchase_items SET variant_id = ? WHERE purchase_id = ?',
            [variant, purchase],
          );
        }
        await db.customStatement(
          'UPDATE business_warehouses SET is_active = 0 WHERE id = ?',
          [warehouse],
        );
        final report = await VoidImpactAnalyzer(
          db,
        ).analyzePurchaseVoid(purchase);
        expect(report.negativeStockRisks, hasLength(1));
        expect(report.negativeStockRisks.single.currentStock, 2);
        expect(report.negativeStockRisks.single.requiredQuantity, 5);
      },
    );
  }
  test('ambiguous simple product rejects search and void preview', () async {
    await insert('product_variants', {
      'product_id': product,
      'cost_cents': 500,
      'price_cents': 1000,
    });
    await expectLater(
      returns.searchProducts('Local', side: ReturnSide.purchase),
      throwsStateError,
    );
    await expectLater(
      VoidImpactAnalyzer(db).analyzePurchaseVoid(purchase),
      throwsStateError,
    );
  });
  test(
    'missing warehouse balance fails instead of falling back to stale stock',
    () async {
      await db.customStatement('DROP TRIGGER business_stock_retain');
      await db.customStatement(
        'DELETE FROM business_warehouse_stocks WHERE warehouse_id = ?',
        [warehouse],
      );
      await expectLater(
        returns.searchProducts('Local', side: ReturnSide.purchase),
        throwsA(anything),
      );
      await expectLater(
        VoidImpactAnalyzer(db).analyzePurchaseVoid(purchase),
        throwsStateError,
      );
    },
  );
  test(
    'foreign explicit variant cannot supply the void preview balance',
    () async {
      final foreign = await insert('products', {
        'name': 'Other',
        'cost_cents': 1,
        'price_cents': 2,
      });
      final foreignVariant = await insert('product_variants', {
        'product_id': foreign,
        'cost_cents': 1,
        'price_cents': 2,
      });
      await db.customStatement(
        'UPDATE purchase_items SET variant_id = ? WHERE purchase_id = ?',
        [foreignVariant, purchase],
      );
      await expectLater(
        VoidImpactAnalyzer(db).analyzePurchaseVoid(purchase),
        throwsStateError,
      );
    },
  );
  test(
    'legacy product without operational row keeps parent fallback',
    () async {
      final legacy = await insert('products', {
        'name': 'Legacy',
        'cost_cents': 500,
        'price_cents': 1000,
        'stock_quantity': 3,
      });
      await db.customStatement(
        'UPDATE purchase_items SET product_id = ? WHERE purchase_id = ?',
        [legacy, purchase],
      );
      final result = await returns.searchProducts(
        'Legacy',
        side: ReturnSide.purchase,
      );
      expect(result.single.stockQuantity, 3);
      final report = await VoidImpactAnalyzer(db).analyzePurchaseVoid(purchase);
      expect(report.negativeStockRisks.single.currentStock, 3);
    },
  );
}
