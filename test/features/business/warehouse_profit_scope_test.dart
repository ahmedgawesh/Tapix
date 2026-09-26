import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:tapix/features/reports/presentation/bloc/profit_reports_bloc.dart';
import 'package:uuid/uuid.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int product, customer, currency;
  late String other;
  late Map<String, int> docs;
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
  Future<Map<String, int>> seed(String suffix) async {
    final now = DateTime.now().toIso8601String();
    final sale = await insert('sales', {
      'invoice_number': 'SALE-$suffix',
      'customer_id': customer,
      'currency_id': currency,
      'status': 'completed',
      'sale_date': now,
      'subtotal_cents': 10000,
      'discount_cents': 200,
      'tax_cents': 100,
      'total_cents': 9900,
      'payment_method': 'cash',
    });
    final item = await insert('sale_items', {
      'sale_id': sale,
      'product_id': product,
      'quantity': 10,
      'unit_price_cents': 1000,
      'cost_cents': 500,
      'subtotal_cents': 10000,
      'discount_cents': 200,
      'tax_cents': 100,
      'total_cents': 9900,
    });
    final linked = await insert('sale_returns', {
      'sale_id': sale,
      'return_number': 'RETURN-$suffix',
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
    await insert('sale_return_items', {
      'return_id': linked,
      'sale_item_id': item,
      'quantity': 1,
      'unit_cost_at_post_cents': 500,
      'subtotal_cents': 1000,
      'discount_cents': 20,
      'tax_cents': 10,
      'refund_cents': 990,
    });
    final adjustment = await insert('sale_return_adjustments', {
      'return_number': 'ADJUST-$suffix',
      'customer_id': customer,
      'currency_id': currency,
      'return_date': now,
      'status': 'draft',
      'subtotal_cents': 1000,
      'discount_cents': 20,
      'tax_cents': 10,
      'total_cents': 990,
      'refund_method': 'cash',
    });
    await insert('sale_return_adjustment_items', {
      'return_id': adjustment,
      'product_id': product,
      'quantity': 1,
      'unit_price_cents': 1000,
      'unit_cost_cents': 400,
      'unit_cost_at_post_cents': 400,
      'discount_cents': 20,
      'tax_cents': 10,
      'total_cents': 990,
    });
    await db.customUpdate(
      'UPDATE sale_return_adjustments SET status = ? WHERE id = ?',
      variables: [Variable.withString('posted'), Variable.withInt(adjustment)],
      updates: {db.saleReturnAdjustments},
    );
    return {
      'sales': sale,
      'sale_returns': linked,
      'sale_return_adjustments': adjustment,
    };
  }

  setUp(() async {
    db = fixtures.memoryDb();
    currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    final category = await insert('product_categories', {'name': 'Category'});
    product = await insert('products', {
      'name': 'Product',
      'category_id': category,
      'cost_cents': 9999,
      'price_cents': 12000,
    });
    customer = await insert('customers', {
      'name': 'Customer',
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
    docs = await seed('LOCAL');
    // Test-only reassignment simulates separately located document history.
    await db.customStatement('DROP TRIGGER business_location_immutable');
  });
  tearDown(() => db.close());
  Future<void> move(String table, int id) async {
    await db.customUpdate(
      'UPDATE business_document_locations SET warehouse_id = ? WHERE source_table = ? AND source_id = ?',
      variables: [
        Variable.withString(other),
        Variable.withString(table),
        Variable.withInt(id),
      ],
      updates: {db.businessDocumentLocations},
    );
  }

  Future<ProfitReportsData> report() async {
    final bloc = ProfitReportsBloc(db);
    try {
      return await bloc.dataStream.first;
    } finally {
      await bloc.close();
    }
  }

  void expectTotals(
    ProfitReportsData value,
    int revenue,
    int cost,
    int tax,
    int discount,
    int count,
  ) {
    expect(value.summary.totalRevenueCents, revenue);
    expect(value.summary.totalCostCents, cost);
    expect(value.summary.totalTaxCents, tax);
    expect(value.summary.totalDiscountCents, discount);
    expect(value.summary.totalProfitCents, revenue - cost);
    expect(value.byInvoice, hasLength(count));
    for (final pair in [
      (
        value.byProduct.single.totalRevenueCents,
        value.byProduct.single.totalCostCents,
      ),
      (
        value.byCategory.single.totalRevenueCents,
        value.byCategory.single.totalCostCents,
      ),
      (
        value.byCustomer.single.totalRevenueCents,
        value.byCustomer.single.totalCostCents,
      ),
    ]) {
      expect(pair, (revenue, cost));
    }
  }

  test(
    'local frozen costs, discounts and both return kinds reconcile',
    () async {
      expectTotals(await report(), 7840, 4100, 80, 160, 3);
    },
  );
  test(
    'foreign duplicate documents cannot inflate any profit breakdown',
    () async {
      final foreign = await seed('REMOTE');
      for (final entry in foreign.entries) {
        await move(entry.key, entry.value);
      }
      expectTotals(await report(), 7840, 4100, 80, 160, 3);
    },
  );
  for (final kind in ['sales', 'sale_returns', 'sale_return_adjustments']) {
    test('exclude foreign $kind consistently from every breakdown', () async {
      await move(kind, docs[kind]!);
      switch (kind) {
        case 'sales':
          expectTotals(await report(), -1960, -900, -20, -40, 2);
        case 'sale_returns':
          expectTotals(await report(), 8820, 4600, 90, 180, 2);
        case 'sale_return_adjustments':
          expectTotals(await report(), 8820, 4500, 90, 180, 2);
      }
    });
  }
  test('disabled primary warehouse retains financial history', () async {
    await db.customStatement('UPDATE business_warehouses SET is_active = 0');
    expectTotals(await report(), 7840, 4100, 80, 160, 3);
  });
  test('location-only change refreshes report stream', () async {
    final bloc = ProfitReportsBloc(db);
    final stream = StreamIterator(bloc.dataStream);
    try {
      expect(await stream.moveNext(), isTrue);
      expectTotals(stream.current, 7840, 4100, 80, 160, 3);
      await move('sale_return_adjustments', docs['sale_return_adjustments']!);
      expect(
        await stream.moveNext().timeout(const Duration(seconds: 10)),
        isTrue,
      );
      expectTotals(stream.current, 8820, 4500, 90, 180, 2);
    } finally {
      await stream.cancel();
      await bloc.close();
    }
  });
}
