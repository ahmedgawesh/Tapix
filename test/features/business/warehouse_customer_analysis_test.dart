import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';
import 'business_foundation_test.dart' as fixtures;

import 'package:tapix/features/reports/presentation/bloc/customer_sales_report_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_analysis_report_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/top_customers_bloc.dart';
import 'package:tapix/features/reports/services/party_statement_ledger_service.dart';

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

  dynamic open(String kind) => switch (kind) {
    'sales' => CustomerSalesReportBloc(db),
    'analysis' => CustomerAnalysisReportBloc(db),
    _ => TopCustomersBloc(db),
  };
  List<Object?> project(dynamic data) {
    if (data is CustomerSalesReportData) {
      return [
        data.grandTotalSalesCents,
        data.grandTotalInvoices,
        data.grandTotalQuantity,
        data.customers
            .map(
              (v) => [
                v.customerId,
                v.customerName,
                v.totalSalesCents,
                v.invoiceCount,
                v.totalQuantity,
                v.averageOrderCents,
              ],
            )
            .toList(),
      ];
    }
    if (data is TopCustomersData) {
      return [
        data.grandTotalRevenueCents,
        data.grandTotalTransactions,
        data.grandTotalQuantity,
        data.customers
            .map(
              (v) => [
                v.customerId,
                v.customerName,
                v.totalRevenueCents,
                v.transactionCount,
                v.totalQuantity,
                v.averageOrderCents,
              ],
            )
            .toList(),
      ];
    }
    final analysis = data as CustomerAnalysisReportData;
    return [
      analysis.grandTotalSpentCents,
      analysis.grandTotalPurchases,
      analysis.totalCustomers,
      analysis.customers
          .map(
            (v) => [
              v.customerId,
              v.customerName,
              v.totalSpentCents,
              v.purchaseCount,
              v.avgOrderValueCents,
              v.largestOrderCents,
              v.recencyScore,
              v.frequencyScore,
              v.monetaryScore,
              v.rfmSegment,
            ],
          )
          .toList(),
    ];
  }

  for (final kind in ['sales', 'analysis', 'top']) {
    test(
      '$kind excludes remote customer activity and retains disabled history',
      () async {
        final dynamic bloc = open(kind);
        try {
          final baseline = project(await (bloc.dataStream as Stream).first);
          expect(baseline.take(2).toList(), [9900, 1]);
          await move(await seed('REMOTE'));
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
    test('$kind refreshes when sale leaves local scope', () async {
      final dynamic bloc = open(kind);
      final stream = StreamIterator<dynamic>(bloc.dataStream as Stream);
      try {
        expect(await stream.moveNext(), isTrue);
        expect(project(stream.current).first, 9900);
        await move(local);
        do {
          expect(
            await stream.moveNext().timeout(const Duration(seconds: 10)),
            isTrue,
          );
        } while (project(stream.current).first != 0);
        expect(stream.current.customers, isEmpty);
      } finally {
        await stream.cancel();
        await bloc.close();
      }
    });
    test('$kind refreshes customer labels without sale changes', () async {
      final dynamic bloc = open(kind);
      final stream = StreamIterator<dynamic>(bloc.dataStream as Stream);
      try {
        expect(await stream.moveNext(), isTrue);
        await db.customUpdate(
          "UPDATE customers SET name = 'Updated' WHERE id = ?",
          variables: [Variable.withInt(customer)],
          updates: {db.customers},
        );
        do {
          expect(
            await stream.moveNext().timeout(const Duration(seconds: 10)),
            isTrue,
          );
        } while (stream.current.customers.single.customerName != 'Updated');
        expect(project(stream.current).first, 9900);
      } finally {
        await stream.cancel();
        await bloc.close();
      }
    });
    if (kind != 'analysis') {
      test('$kind refreshes quantity on item-only changes', () async {
        final dynamic bloc = open(kind);
        final stream = StreamIterator<dynamic>(bloc.dataStream as Stream);
        try {
          expect(await stream.moveNext(), isTrue);
          expect(project(stream.current)[2], 10);
          await db.customUpdate(
            'UPDATE sale_items SET quantity = 12 WHERE sale_id = ?',
            variables: [Variable.withInt(local['sales']!)],
            updates: {db.saleItems},
          );
          do {
            expect(
              await stream.moveNext().timeout(const Duration(seconds: 10)),
              isTrue,
            );
          } while (project(stream.current)[2] != 12);
          expect(project(stream.current).first, 9900);
        } finally {
          await stream.cancel();
          await bloc.close();
        }
      });
    }
  }
  for (final side in ['customer', 'supplier']) {
    test(
      '$side ledger reconciles full account across document locations',
      () async {
        final sale = side == 'customer';
        final table = sale ? 'sales' : 'purchases';
        final party = sale ? customer : supplier;
        final foreign = await seed('REMOTE');
        await move(foreign);
        final now = DateTime.now();
        for (final doc in [local[table]!, foreign[table]!]) {
          await insert('${side}_transactions', {
            '${side}_id': party,
            'transaction_type': sale ? 'sale' : 'purchase',
            'amount_cents': 9900,
            'currency_id': currency,
            'reference_id': doc,
            'reference_type': sale ? 'sale' : 'purchase',
            'transaction_date': now.toUtc().toIso8601String(),
          });
        }
        await insert('${side}_transactions', {
          '${side}_id': party,
          'transaction_type': 'payment',
          'amount_cents': -3000,
          'currency_id': currency,
          'transaction_date': now.toUtc().toIso8601String(),
        });
        final service = PartyStatementLedgerService(db);
        Future<PartyStatementLedgerSnapshot> snapshot() => sale
            ? service.loadCustomer(
                customerId: party,
                startDate: DateTime(now.year, now.month, 1),
                endDate: now,
              )
            : service.loadSupplier(
                supplierId: party,
                startDate: DateTime(now.year, now.month, 1),
                endDate: now,
              );
        final before = await snapshot();
        expect(before.transactions.length, 3);
        expect(before.closingBalanceCents, 16800);
        expect(before.options.single.balanceCents, 16800);
        await move(local);
        final after = await snapshot();
        expect(after.closingBalanceCents, before.closingBalanceCents);
        expect(after.totalDebitsCents, before.totalDebitsCents);
        expect(after.totalCreditsCents, before.totalCreditsCents);
        expect(
          after.transactions.map((v) => v.runningBalanceCents).toList(),
          before.transactions.map((v) => v.runningBalanceCents).toList(),
        );
      },
    );
  }
}
