import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';
import 'business_foundation_test.dart' as fixtures;

import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/loyalty/loyalty_points_service.dart';
import 'package:tapix/core/services/unified_return_service.dart';
import 'package:tapix/core/services/void_impact_analyzer.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/customers/data/repositories/loyalty_repository_impl.dart';

void main() {
  late AppDatabase db;
  late UnifiedReturnService returns;
  late int product, customer, supplier, currency;
  late String other;
  late Map<String, int> local;
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
  Future<Map<String, int>> seed(
    String suffix, {
    int? invoiceVariantId,
    int? adjustmentVariantId,
    int adjustmentAllocatedQuantity = 0,
  }) async {
    final docs = <String, int>{};
    final now = DateTime.now().toIso8601String();
    for (final side in ['sale', 'purchase']) {
      final sale = side == 'sale';
      final header = await insert('${side}s', {
        sale ? 'invoice_number' : 'purchase_number': '$side-$suffix',
        sale ? 'customer_id' : 'supplier_id': sale ? customer : supplier,
        'currency_id': currency,
        'status': sale ? 'completed' : 'posted',
        '${side}_date': now,
        'subtotal_cents': 10000,
        'discount_cents': 200,
        'tax_cents': 100,
        'total_cents': 9900,
        'payment_method': 'cash',
      });
      final item = await insert('${side}_items', {
        '${side}_id': header,
        'product_id': product,
        'variant_id': ?invoiceVariantId,
        'quantity': 10,
        'qty_returned_adjustment': adjustmentAllocatedQuantity,
        sale ? 'unit_price_cents' : 'unit_cost_cents': 1000,
        'subtotal_cents': 10000,
        'discount_cents': 200,
        'tax_cents': 100,
        'total_cents': 9900,
      });
      final linked = await insert('${side}_returns', {
        '${side}_id': header,
        'return_number': '$side-LR-$suffix',
        'currency_id': currency,
        'return_date': now,
        'status': 'posted',
        'subtotal_cents': 1000,
        'discount_cents': 20,
        'tax_cents': 10,
        'total_cents': 990,
        'refund_method': 'cash',
        'reason': 'Test',
      });
      await insert('${side}_return_items', {
        'return_id': linked,
        '${side}_item_id': item,
        'quantity': 1,
        'subtotal_cents': 1000,
        'discount_cents': 20,
        'tax_cents': 10,
        'refund_cents': 990,
      });
      final adjustment = await insert('${side}_return_adjustments', {
        'return_number': '$side-AR-$suffix',
        sale ? 'customer_id' : 'supplier_id': sale ? customer : supplier,
        'currency_id': currency,
        'return_date': now,
        'status': 'posted',
        'subtotal_cents': 1000,
        'discount_cents': 20,
        'tax_cents': 10,
        'total_cents': 990,
        'refund_method': 'cash',
      });
      await insert('${side}_return_adjustment_items', {
        'return_id': adjustment,
        'product_id': product,
        'variant_id': ?adjustmentVariantId,
        'quantity': 1,
        'unit_price_cents': 1000,
        'unit_cost_cents': 500,
        'discount_cents': 20,
        'tax_cents': 10,
        'total_cents': 990,
      });
      docs.addAll({
        '${side}s': header,
        '${side}_returns': linked,
        '${side}_return_adjustments': adjustment,
      });
    }
    return docs;
  }

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
    currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    final category = await insert('product_categories', {'name': 'Category'});
    product = await insert('products', {
      'name': 'Product',
      'category_id': category,
      'cost_cents': 500,
      'price_cents': 1000,
    });
    customer = await insert('customers', {
      'name': 'Customer',
      'currency_id': currency,
    });
    supplier = await insert('suppliers', {
      'name': 'Supplier',
      'currency_id': currency,
    });
    final scope = await BusinessFoundationRepository(db).getScope();
    other = const Uuid().v4();
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
    local = await seed('LOCAL');
    await db.customStatement('DROP TRIGGER business_location_immutable');
  });
  tearDown(() => db.close());
  Future<void> move(Map<String, int> docs) => db.transaction(() async {
    for (final entry in docs.entries) {
      await db.customUpdate(
        'UPDATE business_document_locations SET warehouse_id = ? WHERE source_table = ? AND source_id = ?',
        variables: [
          Variable.withString(other),
          Variable.withString(entry.key),
          Variable.withInt(entry.value),
        ],
        updates: {db.businessDocumentLocations},
      );
    }
  });

  for (final side in ReturnSide.values) {
    final sale = side == ReturnSide.sale;
    final table = sale ? 'sales' : 'purchases';
    final base = sale ? 'sale' : 'purchase';
    Future<List<InvoiceSearchResult>> invoices() => sale
        ? returns.searchSaleInvoices('', customerId: customer)
        : returns.searchPurchaseInvoices('', supplierId: supplier);
    Future<List<ReturnableInvoiceItem>> candidates() =>
        returns.getReturnableInvoiceItems(
          productId: product,
          side: side,
          partyId: sale ? customer : supplier,
        );
    Future<VoidImpactReport> impact(int id) => sale
        ? VoidImpactAnalyzer(db).analyzeSaleVoid(id)
        : VoidImpactAnalyzer(db).analyzePurchaseVoid(id);

    test(
      '$side search and linkage exclude remote documents but retain disabled history',
      () async {
        await move(await seed('REMOTE'));
        expect((await invoices()).map((v) => v.invoiceId).toList(), [
          local[table],
        ]);
        final items = await candidates();
        expect(items, hasLength(1));
        expect(items.single.invoiceId, local[table]);
        expect(items.single.remainingQuantity, 9);
        await db.customStatement('UPDATE business_warehouses SET is_active=0');
        expect((await invoices()).single.invoiceId, local[table]);
        expect((await candidates()).single.remainingQuantity, 9);
      },
    );
    test('$side inaccessible invoice is not exposed by void preview', () async {
      await move(local);
      expect((await impact(local[table]!)).documentExists, isFalse);
      expect(await invoices(), isEmpty);
      expect(await candidates(), isEmpty);
    });
    test(
      '$side foreign linked return cannot be hidden from void safety checks',
      () async {
        await move({'${base}_returns': local['${base}_returns']!});
        await expectLater(impact(local[table]!), throwsStateError);
        // A location mismatch must not restore already-returned allowance.
        expect((await candidates()).single.remainingQuantity, 9);
      },
    );
    test('$side adjustment candidates exclude remote warehouse', () async {
      await db.customStatement(
        'UPDATE ${base}_items SET qty_returned_adjustment=1',
      );
      await move(await seed('REMOTE'));
      final report = await impact(local[table]!);
      expect(
        report.entangledAdjustmentReturns.map((v) => v.returnId).toList(),
        [local['${base}_return_adjustments']],
      );
      expect(report.linkedReturns.map((v) => v.returnId).toList(), [
        local['${base}_returns'],
      ]);
    });
    test(
      '$side recent remote price never replaces local invoice price',
      () async {
        final remote = await seed('REMOTE');
        await db.customStatement(
          'UPDATE ${base}_items SET ${sale ? 'unit_price_cents' : 'unit_cost_cents'}=9999 WHERE ${base}_id=?',
          [remote[table]],
        );
        await db
            .customStatement('UPDATE $table SET ${base}_date=? WHERE id=?', [
              DateTime.now().add(const Duration(days: 1)).toIso8601String(),
              remote[table],
            ]);
        await move(remote);
        final products = await returns.searchProducts(
          'Product',
          side: side,
          partyId: sale ? customer : supplier,
        );
        expect(products.single.lastPriceCents, 1000);
      },
    );

    for (final simple in [false, true]) {
      test(
        '$side adjustment candidate matches operational variant simple=$simple',
        () async {
          // Create the invoice and its return in their final form. The stock
          // source guard correctly rejects changing a posted sale line.
          product = await insert('products', {
            'name': 'Variant product $side $simple',
            'cost_cents': 500,
            'price_cents': 1000,
            if (!simple) 'has_variants': 1,
          });
          final a = await insert('product_variants', {
            'product_id': product,
            'cost_cents': 500,
            'price_cents': 1000,
          });
          int? b;
          if (!simple) {
            final size = await insert('sizes', {'name': 'Other size'});
            b = await insert('product_variants', {
              'size_id': size,
              'product_id': product,
              'cost_cents': 500,
              'price_cents': 1000,
            });
          }
          local = await seed(
            'VARIANT-$side-$simple',
            invoiceVariantId: simple ? null : a,
            adjustmentVariantId: simple ? a : b,
            adjustmentAllocatedQuantity: 1,
          );
          final report = await impact(local[table]!);
          expect(report.entangledAdjustmentReturns, hasLength(simple ? 1 : 0));
        },
      );
    }
  }
}
