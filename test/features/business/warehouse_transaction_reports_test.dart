import 'package:tapix/core/services/business/warehouse_read_scope.dart';
import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:tapix/features/reports/presentation/bloc/sales_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/purchase_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_sales_returns_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_returns_report_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_invoices_report_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_invoices_report_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/sales_tax_report_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/purchase_tax_report_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/discount_reports_bloc.dart';
import 'package:uuid/uuid.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
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
  Future<Map<String, int>> seed(String suffix) async {
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
        'quantity': 10,
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
  Future<dynamic> open(String kind, {WarehouseReadScope? scope}) async {
    final dynamic bloc = switch (kind) {
      'sales_tax' => SalesTaxReportBloc(db, warehouseScope: scope),
      'purchase_tax' => PurchaseTaxReportBloc(db, warehouseScope: scope),
      'discounts' => DiscountReportsBloc(db, warehouseScope: scope),
      'sales' => SalesReportsBloc(db, warehouseScope: scope),
      'purchases' => PurchaseReportsBloc(db, warehouseScope: scope),
      'customer_returns' => CustomerSalesReturnsBloc(db, warehouseScope: scope),
      'supplier_returns' => SupplierReturnsReportBloc(
        db,
        warehouseScope: scope,
      ),
      'customer_invoices' => CustomerInvoicesReportBloc(
        db,
        warehouseScope: scope,
      ),
      _ => SupplierInvoicesReportBloc(db, warehouseScope: scope),
    };
    if (kind == 'customer_invoices') {
      final ready = (bloc.stream as Stream).firstWhere(
        (s) =>
            s is RealtimeSuccess &&
            (s.data as CustomerInvoicesData).customerId == customer,
      );
      bloc.add(CustomerInvoicesCustomerChanged(customer));
      await ready;
    } else if (kind == 'supplier_invoices') {
      final ready = (bloc.stream as Stream).firstWhere(
        (s) =>
            s is RealtimeSuccess &&
            (s.data as SupplierInvoicesData).supplierId == supplier,
      );
      bloc.add(SupplierInvoicesSupplierChanged(supplier));
      await ready;
    } else if (kind == 'supplier_returns') {
      final ready = (bloc.stream as Stream).firstWhere(
        (s) =>
            s is RealtimeSuccess &&
            (s.data as SupplierReturnsData).supplierId == supplier,
      );
      bloc.add(SupplierReturnsSupplierChanged(supplier));
      await ready;
    }
    return bloc;
  }

  List<Object> project(dynamic data) {
    if (data is SalesTaxReportData) {
      return [
        data.invoiceCount,
        data.totalSalesCents,
        data.totalSubtotalCents,
        data.totalDiscountCents,
        data.totalTaxableCents,
        data.totalTaxCollectedCents,
        data.returnCount,
        data.returnTaxCents,
        data.netTaxCents,
        data.invoices
            .map((v) => [v.invoiceNumber, v.taxableCents, v.taxCents])
            .toList(),
        data.returns.map((v) => [v.returnNumber, v.taxCents]).toList(),
      ];
    }
    if (data is PurchaseTaxReportData) {
      return [
        data.invoiceCount,
        data.totalPurchasesCents,
        data.totalSubtotalCents,
        data.totalDiscountCents,
        data.totalTaxableCents,
        data.totalTaxPaidCents,
        data.returnCount,
        data.returnTaxCents,
        data.netTaxCents,
        data.invoices
            .map((v) => [v.purchaseNumber, v.taxableCents, v.taxCents])
            .toList(),
        data.returns.map((v) => [v.returnNumber, v.taxCents]).toList(),
      ];
    }
    if (data is DiscountReportsData) {
      return [
        data.summary.invoiceCount,
        data.summary.totalSalesCents,
        data.summary.totalDiscountCents,
        data.summary.averageDiscountPercent,
        data.byProduct
            .map(
              (v) => [
                v.productId,
                v.totalQuantity,
                v.totalDiscountCents,
                v.discountPercent,
              ],
            )
            .toList(),
        data.byCategory
            .map((v) => [v.categoryId, v.totalDiscountCents])
            .toList(),
        data.byCustomer
            .map((v) => [v.customerId, v.totalDiscountCents])
            .toList(),
        data.byInvoice.map((v) => [v.saleId, v.discountCents]).toList(),
      ];
    }
    if (data is SalesReportsData) {
      return [
        data.allSales.length,
        data.summary.totalSalesCents,
        data.summary.totalReturnsCents,
        data.summary.totalDiscountCents,
        data.summary.totalTaxCents,
        data.byProduct
            .map((v) => [v.totalQuantity, v.totalSalesCents])
            .toList(),
        data.byCategory.map((v) => v.totalSalesCents).toList(),
        data.byCustomer.map((v) => v.totalSalesCents).toList(),
        data.taxByProduct.map((v) => v.totalTaxCents).toList(),
      ];
    }
    if (data is PurchaseReportsData) {
      return [
        data.allPurchases.length,
        data.summary.totalPurchasesCents,
        data.summary.totalReturnsCents,
        data.summary.totalDiscountCents,
        data.summary.totalTaxCents,
        data.byProduct
            .map((v) => [v.totalQuantity, v.totalPurchasesCents])
            .toList(),
        data.byCategory.map((v) => v.totalPurchasesCents).toList(),
        data.bySupplier.map((v) => v.totalPurchasesCents).toList(),
      ];
    }
    if (data is CustomerSalesReturnsData) {
      return [
        data.totalReturnCount,
        data.totalReturnsCents,
        data.totalItemsReturned,
        data.returnDetails.length,
        data.returnedProducts.length,
      ];
    }
    if (data is SupplierReturnsData) {
      return [
        data.returns.length,
        data.totalAmountCents,
        data.totalDiscountCents,
        data.totalQuantity,
        data.linkedCount,
        data.adjustmentCount,
        data.returns.map((r) => r.items.length).toList(),
      ];
    }
    if (data is CustomerInvoicesData) {
      return [
        data.invoices.length,
        data.totalAmountCents,
        data.totalDiscountCents,
        data.totalQuantity,
        data.invoices.map((r) => r.items.length).toList(),
      ];
    }
    if (data is SupplierInvoicesData) {
      return [
        data.invoices.length,
        data.totalAmountCents,
        data.totalDiscountCents,
        data.totalQuantity,
        data.invoices.map((r) => r.items.length).toList(),
      ];
    }
    throw StateError('Unexpected report');
  }

  for (final kind in [
    'sales_tax',
    'purchase_tax',
    'discounts',
    'sales',
    'purchases',
    'customer_returns',
    'supplier_returns',
    'customer_invoices',
    'supplier_invoices',
  ]) {
    test(
      '$kind excludes foreign duplicates and retains disabled local history',
      () async {
        final dynamic bloc = await open(kind);
        try {
          final baseline = project(await (bloc.dataStream as Stream).first);
          expect(baseline[0], kind.endsWith('returns') ? 2 : 1);
          expect(
            baseline[1],
            kind.endsWith('returns')
                ? 1980
                : kind == 'discounts'
                ? 10000
                : 9900,
          );
          if (kind.endsWith('_tax')) {
            expect(baseline.sublist(2, 9), [10000, 200, 9800, 100, 2, 20, 80]);
          }
          if (kind == 'discounts') {
            expect(baseline.sublist(2, 4), [200, 2.0]);
          }
          final foreign = await seed('REMOTE');
          await move(foreign);
          expect(project(await (bloc.dataStream as Stream).first), baseline);
          await db.customStatement(
            'UPDATE business_warehouses SET is_active = 0',
          );
          expect(project(await (bloc.dataStream as Stream).first), baseline);
        } finally {
          await bloc.close();
        }
      },
    );
    test('$kind refreshes on location-only change', () async {
      final dynamic bloc = await open(kind);
      final stream = StreamIterator<dynamic>(bloc.dataStream as Stream);
      try {
        expect(await stream.moveNext(), isTrue);
        expect(project(stream.current).first, greaterThan(0));
        await move(local);
        do {
          expect(
            await stream.moveNext().timeout(const Duration(seconds: 10)),
            isTrue,
          );
        } while (project(stream.current).first != 0);
        expect(project(stream.current)[1], 0);
      } finally {
        await stream.cancel();
        await bloc.close();
      }
    });
  }

  for (final side in ['sale', 'purchase']) {
    for (final source in ['invoice', 'linked', 'adjustment']) {
      test(
        '$side tax scopes $source independently of related documents',
        () async {
          final dynamic bloc = await open(
            side == 'sale' ? 'sales_tax' : 'purchase_tax',
          );
          try {
            final table = switch (source) {
              'invoice' => '${side}s',
              'linked' => '${side}_returns',
              _ => '${side}_return_adjustments',
            };
            await move({table: local[table]!});
            final data = project(await (bloc.dataStream as Stream).first);
            expect(data[0], source == 'invoice' ? 0 : 1);
            expect(data[6], source == 'invoice' ? 2 : 1);
            expect(data[7], source == 'invoice' ? 20 : 10);
            expect(data[8], source == 'invoice' ? -20 : 90);
          } finally {
            await bloc.close();
          }
        },
      );
    }
  }

  test('discount product and category refresh on item-only change', () async {
    final bloc = DiscountReportsBloc(db);
    final stream = StreamIterator<DiscountReportsData>(bloc.dataStream);
    try {
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.byProduct.single.totalDiscountCents, 200);
      await db.customUpdate(
        'UPDATE sale_items SET discount_cents = 300 WHERE sale_id = ?',
        variables: [Variable.withInt(local['sales']!)],
        updates: {db.saleItems},
      );
      do {
        expect(
          await stream.moveNext().timeout(const Duration(seconds: 10)),
          isTrue,
        );
      } while (stream.current.byProduct.single.totalDiscountCents != 300);
      expect(stream.current.byCategory.single.totalDiscountCents, 300);
      expect(stream.current.byProduct.single.discountPercent, 3.0);
    } finally {
      await stream.cancel();
      await bloc.close();
    }
  });
  for (final kind in [
    'sales_tax',
    'purchase_tax',
    'discounts',
    'sales',
    'purchases',
    'customer_returns',
    'supplier_returns',
    'customer_invoices',
    'supplier_invoices',
  ]) {
    test(
      '$kind selected warehouse matches source history after disabling',
      () async {
        final primaryBloc = await open(kind);
        final before = project(await (primaryBloc.dataStream as Stream).first);
        await primaryBloc.close();
        await move(local);
        // Add another identical cycle in the primary warehouse: selected totals
        // must still equal exactly one cycle, including discounts and both returns.
        await seed('PRIMARY-EXTRA');
        await db.customStatement(
          'UPDATE business_warehouses SET is_active = 0 WHERE id = ?',
          [other],
        );
        final scope = await WarehouseReadScope.resolve(db, warehouseId: other);
        final bloc = await open(kind, scope: scope);
        try {
          expect(project(await (bloc.dataStream as Stream).first), before);
        } finally {
          await bloc.close();
        }
      },
    );
  }
}
