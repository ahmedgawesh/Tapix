import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/warehouse_read_scope.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_sales_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int currency, supplier, second, product, variant, category, customer;
  var serial = 0;
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
  Future<int> batch(
    int vendor, {
    int quantity = 5,
    String? warehouse,
    int? forProduct,
    int? forVariant,
  }) async {
    final batchProduct = forProduct ?? product;
    final batchVariant = forVariant ?? variant;
    final purchase = await insert('purchases', {
      'purchase_number': 'P-${serial++}',
      'supplier_id': vendor,
      'currency_id': currency,
      'status': 'posted',
      'payment_method': 'cash',
      'subtotal_cents': 500,
      'tax_cents': 0,
      'total_cents': 500,
      'warehouse_id': ?warehouse,
    });
    final item = await insert('purchase_items', {
      'purchase_id': purchase,
      'product_id': batchProduct,
      'variant_id': batchVariant,
      'quantity': quantity,
      'unit_cost_cents': 100,
      'subtotal_cents': 500,
      'total_cents': 500,
    });
    return insert('product_batches', {
      'product_id': batchProduct,
      'variant_id': batchVariant,
      'purchase_item_id': item,
      'supplier_id': vendor,
      'batch_number': 'B-${serial++}',
      'received_quantity': quantity,
      'remaining_quantity': quantity,
      'unit_cost_cents': 100,
      'warehouse_id': ?warehouse,
    });
  }

  Future<int> sale({
    int quantity = 2,
    int total = 200,
    String status = 'completed',
    String? warehouse,
    DateTime? date,
    int? forProduct,
    int? forVariant,
  }) async {
    final saleProduct = forProduct ?? product;
    final saleVariant = forVariant ?? variant;
    final id = await insert('sales', {
      'invoice_number': 'S-${serial++}',
      'customer_id': customer,
      'currency_id': currency,
      'status': status,
      'payment_method': 'cash',
      'subtotal_cents': total,
      'tax_cents': 0,
      'total_cents': total,
      'sale_date': (date ?? DateTime.now()).toUtc().toIso8601String(),
      'warehouse_id': ?warehouse,
    });
    return insert('sale_items', {
      'sale_id': id,
      'product_id': saleProduct,
      'variant_id': saleVariant,
      'quantity': quantity,
      'unit_price_cents': 100,
      'subtotal_cents': total,
      'total_cents': total,
    });
  }

  Future<void> consume(int batch, int line, int qty) =>
      insert('batch_consumptions', {
        'batch_id': batch,
        'sale_item_id': line,
        'consumption_type': 'sale',
        'direction': 'out',
        'quantity': qty,
        'unit_cost_cents': 100,
      });
  Future<SupplierSalesReportData> report({WarehouseReadScope? scope}) async {
    final bloc = SupplierSalesReportBloc(db, warehouseScope: scope);
    try {
      return await bloc.load();
    } finally {
      await bloc.close();
    }
  }

  setUp(() async {
    db = fixtures.memoryDb();
    await db.customSelect('SELECT 1').get();
    currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    supplier = await insert('suppliers', {
      'name': 'Shoes',
      'currency_id': currency,
    });
    second = await insert('suppliers', {
      'name': 'Other',
      'currency_id': currency,
    });
    customer = await insert('customers', {
      'name': 'Customer',
      'currency_id': currency,
    });
    category = await insert('product_categories', {'name': 'Footwear'});
    product = await insert('products', {
      'name': 'Shoe',
      'cost_cents': 100,
      'price_cents': 100,
      'currency_id': currency,
      'category_id': category,
      'supplier_id': second,
    });
    variant = await insert('product_variants', {
      'product_id': product,
      'sku': 'SHOE-40',
      'cost_cents': 100,
      'price_cents': 100,
    });
  });
  tearDown(() async => db.close());
  test(
    'five purchased, two sold follow purchase supplier not current product supplier',
    () async {
      final b = await batch(supplier), line = await sale();
      await consume(b, line, 2);
      final data = await report();
      final row = data.rows.single;
      expect(row.supplierId, supplier);
      expect(row.purchasedQuantity, 5);
      expect(row.soldQuantity, 2);
      expect(row.netCents, 200);
      expect(row.purchaseNumber, isNotEmpty);
      expect(row.purchaseInvoices, hasLength(1));
    },
  );
  test(
    'same supplier product aggregates sales and lists every purchase invoice',
    () async {
      final first = await batch(supplier);
      final secondBatch = await batch(supplier);
      final line = await sale(quantity: 2);
      await consume(first, line, 1);
      await consume(secondBatch, line, 1);

      final data = await report();
      final row = data.rows.single;
      expect(row.supplierId, supplier);
      expect(row.soldQuantity, 2);
      expect(row.purchasedQuantity, 10);
      expect(row.purchaseInvoices, hasLength(2));
      expect(
        row.purchaseInvoices.map((invoice) => invoice.purchaseNumber).toSet(),
        hasLength(2),
      );
      expect(data.products[product], contains('SHOE-40'));
    },
  );
  test('product choices follow the selected supplier', () async {
    final firstBatch = await batch(supplier);
    final firstLine = await sale();
    await consume(firstBatch, firstLine, 2);

    final otherProduct = await insert('products', {
      'name': 'Bag',
      'sku': 'BAG',
      'cost_cents': 100,
      'price_cents': 100,
      'currency_id': currency,
      'category_id': category,
      'supplier_id': second,
    });
    final otherVariant = await insert('product_variants', {
      'product_id': otherProduct,
      'sku': 'BAG-1',
      'cost_cents': 100,
      'price_cents': 100,
    });
    final secondBatch = await batch(
      second,
      forProduct: otherProduct,
      forVariant: otherVariant,
    );
    final secondLine = await sale(
      forProduct: otherProduct,
      forVariant: otherVariant,
    );
    await consume(secondBatch, secondLine, 2);

    final unsoldProduct = await insert('products', {
      'name': 'Unsold shoe',
      'sku': 'UNSOLD',
      'cost_cents': 100,
      'price_cents': 100,
      'currency_id': currency,
      'category_id': category,
      'supplier_id': supplier,
    });
    final unsoldVariant = await insert('product_variants', {
      'product_id': unsoldProduct,
      'sku': 'UNSOLD-1',
      'cost_cents': 100,
      'price_cents': 100,
    });
    await batch(supplier, forProduct: unsoldProduct, forVariant: unsoldVariant);

    final bloc = SupplierSalesReportBloc(db);
    addTearDown(bloc.close);
    final loaded = bloc.stream.firstWhere(
      (state) =>
          state is RealtimeSuccess<SupplierSalesReportData> &&
          state.data.supplierId == supplier,
    );
    bloc.add(
      SupplierSalesFilterChanged(
        range: ReportDateRange.thisMonth(),
        supplierId: supplier,
      ),
    );
    final data =
        (await loaded as RealtimeSuccess<SupplierSalesReportData>).data;
    expect(data.products.keys, {product, unsoldProduct});
    expect(data.products[product], contains('SHOE-40'));
    expect(data.products[unsoldProduct], contains('UNSOLD-1'));
    expect(
      data.rows.map((row) => row.productId),
      isNot(contains(unsoldProduct)),
    );
    expect(data.rows.every((row) => row.supplierId == supplier), isTrue);
  });
  test(
    'two suppliers split one line once and unknown remainder is visible',
    () async {
      final a = await batch(supplier),
          b = await batch(second),
          line = await sale(quantity: 3, total: 1001);
      await consume(a, line, 1);
      await consume(b, line, 1);
      final data = await report();
      expect(data.rows.length, 3);
      expect(data.netByCurrency, {'USD': 1001});
      expect(data.rows.singleWhere((r) => r.supplierId == -1).soldQuantity, 1);
      expect(data.rows.map((r) => r.salesCents).toList()..sort(), [
        333,
        334,
        334,
      ]);
    },
  );
  test(
    'untracked history never inferred from purchases or current supplier',
    () async {
      await batch(supplier);
      await sale();
      final data = await report();
      expect(data.rows.single.supplierId, -1);
      expect(data.rows.single.purchaseItemId, -1);
    },
  );
  test('only completed sales within selected local dates contribute', () async {
    await sale(status: 'draft');
    await sale(status: 'voided');
    await sale(date: DateTime(2020));
    await sale();
    expect((await report()).rows.single.salesCents, 200);
  });
  test('linked return uses actual restored batch and return date', () async {
    final b = await batch(supplier), line = await sale();
    await consume(b, line, 2);
    final saleId =
        (await db
                .customSelect(
                  'SELECT sale_id FROM sale_items WHERE id=?',
                  variables: [Variable.withInt(line)],
                )
                .getSingle())
            .read<int>('sale_id');
    final ret = await insert('sale_returns', {
      'return_number': 'R-1',
      'sale_id': saleId,
      'currency_id': currency,
      'status': 'posted',
      'refund_method': 'cash',
      'subtotal_cents': 100,
      'tax_cents': 0,
      'total_cents': 100,
      'reason': 'test',
      'return_date': DateTime.now().toUtc().toIso8601String(),
    });
    final item = await insert('sale_return_items', {
      'return_id': ret,
      'sale_item_id': line,
      'quantity': 1,
      'subtotal_cents': 100,
      'refund_cents': 100,
    });
    await insert('batch_consumptions', {
      'batch_id': b,
      'sale_return_item_id': item,
      'consumption_type': 'sale_return_reverse',
      'direction': 'in',
      'quantity': 1,
      'unit_cost_cents': 100,
    });
    final row = (await report()).rows.single;
    expect(row.soldQuantity, 2);
    expect(row.returnedQuantity, 1);
    expect(row.netCents, 100);
    await db.customStatement(
      "UPDATE sale_returns SET status='voided' WHERE id=?",
      [ret],
    );
    expect((await report()).rows.single.netCents, 200);
  });
  test(
    'legacy invoice discounts reconcile before supplier filtering',
    () async {
      final a = await batch(supplier),
          b = await batch(second),
          line = await sale(quantity: 2, total: 200);
      await consume(a, line, 1);
      await consume(b, line, 1);
      await db.customStatement(
        'UPDATE sales SET total_cents=189, discount_cents=20,tax_cents=9',
      );
      final data = await report();
      expect(data.netByCurrency, {'USD': 189});
      expect(data.rows.fold<int>(0, (a, r) => a + r.discountCents), 20);
      expect(data.rows.fold<int>(0, (a, r) => a + r.taxCents), 9);
      final bloc = SupplierSalesReportBloc(db);
      addTearDown(bloc.close);
      final loaded = bloc.stream.firstWhere(
        (s) =>
            s is RealtimeSuccess<SupplierSalesReportData> &&
            (s).data.supplierId == supplier,
      );
      bloc.add(
        SupplierSalesFilterChanged(
          range: ReportDateRange.thisMonth(),
          supplierId: supplier,
          categoryId: category,
          productId: product,
        ),
      );
      final filtered =
          (await loaded as RealtimeSuccess<SupplierSalesReportData>).data;
      expect(filtered.rows.single.supplierId, supplier);
      expect(filtered.netByCurrency['USD'], 95);
    },
  );
  test(
    'secondary warehouse documents are isolated and not reassigned to primary purchase',
    () async {
      final local = await (db.select(db.businessContexts)).getSingle();
      await insert('business_warehouses', {
        'id': 'other',
        'organization_id': local.organizationId,
        'branch_id': local.branchId,
        'name': 'Other',
        'code': 'OTH',
      });
      final b = await batch(supplier, warehouse: 'other'),
          line = await sale(warehouse: 'other');
      await consume(b, line, 2);
      expect((await report()).rows, isEmpty);
      expect(
        (await report(
          scope: await WarehouseReadScope.resolve(db, warehouseId: 'other'),
        )).rows.single.salesCents,
        200,
      );
    },
  );
  test(
    'measured quantities retain their scale and currencies are never combined',
    () async {
      final b = await batch(supplier, quantity: 5000),
          line = await sale(quantity: 500, total: 125);
      await db.customStatement(
        "UPDATE products SET measurement_type='weight' WHERE id=?",
        [product],
      );
      await db.customStatement(
        "UPDATE purchase_items SET quantity_scale=1000,measurement_type='weight'",
      );
      await db.customStatement(
        "UPDATE sale_items SET quantity_scale=1000,measurement_type='weight'",
      );
      await consume(b, line, 500);
      final data = await report();
      expect(data.rows.single.soldQuantity, 500);
      expect(data.rows.single.quantityScale, 1000);
      final euro = await insert('currencies', {
        'code': 'ZZZ',
        'name': 'Other currency',
        'symbol': 'Z',
        'exchange_rate': 100,
      });
      final unknown = await sale(total: 300);
      await db.customStatement(
        'UPDATE sales SET currency_id=? WHERE id=(SELECT sale_id FROM sale_items WHERE id=?)',
        [euro, unknown],
      );
      expect((await report()).netByCurrency, {'USD': 125, 'ZZZ': 300});
    },
  );
  test(
    'unlinked adjustment return stays unknown and reduces net once',
    () async {
      final id = await insert('sale_return_adjustments', {
        'return_number': 'ADJ',
        'customer_id': customer,
        'currency_id': currency,
        'status': 'posted',
        'total_cents': 80,
        'subtotal_cents': 80,
        'return_date': DateTime.now().toUtc().toIso8601String(),
      });
      await insert('sale_return_adjustment_items', {
        'return_id': id,
        'product_id': product,
        'variant_id': variant,
        'quantity': 1,
        'unit_price_cents': 80,
        'total_cents': 80,
      });
      final data = await report();
      expect(data.rows.single.supplierId, -2);
      expect(data.rows.single.returnedQuantity, 1);
      expect(data.netByCurrency, {'USD': -80});
    },
  );
  test('integer allocation preserves large and negative minor units', () {
    for (final amount in [1, 1001, 9007199254740991, -9007199254740991]) {
      expect(
        allocateReportCents(amount, [1, 2, 3]).fold<int>(0, (a, b) => a + b),
        amount,
      );
    }
  });
  for (final source in ['sale_return', 'opening']) {
    test(
      'batch source $source is classified by saved type, never SAR name',
      () async {
        final lot = await insert('product_batches', {
          'product_id': product,
          'variant_id': variant,
          'batch_number': 'SAR-old-name',
          'source': source,
          'received_quantity': 2,
          'remaining_quantity': 1,
          'unit_cost_cents': 100,
        });
        final line = await sale(quantity: 1, total: 100);
        await consume(lot, line, 1);
        final row = (await report()).rows.single;
        expect(row.supplierId, source == 'sale_return' ? -2 : -1);
        expect(
          row.sourceQuality,
          source == 'sale_return' ? 'customer_return' : 'unknown',
        );
        expect(row.netCents, 100);
      },
    );
  }
}
