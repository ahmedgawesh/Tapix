import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';
import 'business_foundation_test.dart' as fixtures;

import 'package:tapix/features/reports/presentation/bloc/product_movement_detail_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/stock_movement_report_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/product_variant_movement_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/category_movement_bloc.dart';

void main() {
  late AppDatabase db;
  late int product, customer, supplier, currency, category;
  int? variant;
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
        if (variant != null) 'variant_id': variant!,
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
        'status': sale ? 'draft' : 'posted',
        'subtotal_cents': 1000,
        'discount_cents': 20,
        'tax_cents': 10,
        'total_cents': 990,
        'refund_method': 'cash',
      });
      await insert('${side}_return_adjustment_items', {
        'return_id': adjustment,
        'product_id': product,
        if (variant != null) 'variant_id': variant!,
        'quantity': 1,
        'unit_price_cents': 1000,
        'unit_cost_cents': 500,
        'discount_cents': 20,
        'tax_cents': 10,
        'total_cents': 990,
      });
      if (sale) {
        await db.customUpdate(
          'UPDATE sale_return_adjustments SET status = ? WHERE id = ?',
          variables: [
            Variable.withString('posted'),
            Variable.withInt(adjustment),
          ],
          updates: {db.saleReturnAdjustments},
        );
      }
      docs.addAll({
        '${side}s': header,
        '${side}_returns': linked,
        '${side}_return_adjustments': adjustment,
      });
    }
    return docs;
  }

  setUp(() async {
    variant = null;
    db = fixtures.memoryDb();
    currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    category = await insert('product_categories', {'name': 'Category'});
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

  Future<dynamic> open(String kind) async {
    final dynamic bloc = switch (kind) {
      'detail' => ProductMovementDetailBloc(db),
      'stock' => StockMovementReportBloc(db),
      'variant' => ProductVariantMovementBloc(db),
      _ => CategoryMovementBloc(db),
    };
    final ready = (bloc.stream as Stream).firstWhere((s) {
      if (s is! RealtimeSuccess) return false;
      final dynamic data = s.data;
      return kind == 'category'
          ? data.selectedCategoryId == category
          : data.selectedProductId == product;
    });
    bloc.add(switch (kind) {
      'detail' => ProductMovementDetailProductSelected(product),
      'stock' => StockMovementProductSelected(product),
      'variant' => VariantMovementProductSelected(product),
      _ => CategoryMovementCategorySelected(category),
    });
    await ready.timeout(const Duration(seconds: 10));
    return bloc;
  }

  List<Object?> project(dynamic data) {
    final dynamic totals =
        data is CategoryMovementData || data is ProductVariantMovementData
        ? data.totals
        : data.summary;
    final movements =
        (data.movements as List)
            .map(
              (dynamic m) => [
                m.reference,
                m.quantity,
                m.totalCents,
                m.measurementType,
                m.counterpartyName,
              ],
            )
            .toList()
          ..sort((a, b) => (a[0] as String).compareTo(b[0] as String));
    return [
      movements,
      totals.totalPurchased,
      totals.totalSold,
      totals.totalSaleReturned,
      totals.totalPurchaseReturned,
      totals.totalPurchaseCents,
      totals.totalSalesCents,
      totals.totalSaleReturnCents,
      totals.totalPurchaseReturnCents,
      if (data is StockMovementReportData)
        [
          data.summary.totalSaleReturnAdj,
          data.summary.totalPurchaseReturnAdj,
          data.summary.totalSaleReturnAdjCents,
          data.summary.totalPurchaseReturnAdjCents,
        ],
      if (data is ProductVariantMovementData)
        data.variantSummaries
            .map(
              (v) => [
                v.label,
                v.purchasedQty,
                v.soldQty,
                v.saleReturnedQty,
                v.purchaseReturnedQty,
                v.purchaseCents,
                v.salesCents,
              ],
            )
            .toList(),
      if (data is CategoryMovementData)
        data.productSummaries
            .map(
              (v) => [
                v.productId,
                v.purchasedQty,
                v.soldQty,
                v.saleReturnedQty,
                v.purchaseReturnedQty,
                v.variants
                    .map(
                      (v) => [
                        v.label,
                        v.purchasedQty,
                        v.soldQty,
                        v.saleReturnedQty,
                        v.purchaseReturnedQty,
                      ],
                    )
                    .toList(),
              ],
            )
            .toList(),
    ];
  }

  for (final kind in ['detail', 'stock', 'variant', 'category']) {
    for (final mode in ['simple', 'optional_size', 'variants']) {
      test(
        '$kind isolates $mode movements and preserves disabled history',
        () async {
          if (mode != 'simple') {
            // Build the final document shape before posting. Posted sale lines
            // are immutable because changing their product/variant would break
            // the saved stock-source allocation.
            category = await insert('product_categories', {
              'name': 'Category $mode',
            });
            product = await insert('products', {
              'name': 'Product $mode',
              'category_id': category,
              'cost_cents': 500,
              'price_cents': 1000,
              if (mode == 'variants') 'has_variants': 1,
            });
            final size = await insert('sizes', {'name': 'Large'});
            variant = await insert('product_variants', {
              'product_id': product,
              'size_id': size,
              'sku': 'LOCAL-L-$mode',
              'cost_cents': 500,
              'price_cents': 1000,
            });
            local = await seed('LOCAL-$mode');
          }
          final dynamic bloc = await open(kind);
          try {
            final dynamic initial = await (bloc.dataStream as Stream).first;
            final baseline = project(initial);
            expect((baseline[0] as List).length, 6);
            expect(baseline.sublist(1, 7), [
              10,
              10,
              kind == 'stock' ? 1 : 2,
              kind == 'stock' ? 1 : 2,
              9900,
              9900,
            ]);
            if (mode != 'simple' && (kind == 'variant' || kind == 'category')) {
              expect(
                (initial.movements as List).every(
                  (dynamic m) => m.sizeName == 'Large',
                ),
                isTrue,
              );
            }
            if (mode == 'variants') {
              variant = await insert('product_variants', {
                'product_id': product,
                'sku': 'REMOTE-OTHER',
                'cost_cents': 500,
                'price_cents': 1000,
              });
            }
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
    }
    test('$kind refreshes on location-only changes', () async {
      final dynamic bloc = await open(kind);
      final stream = StreamIterator<dynamic>(bloc.dataStream as Stream);
      try {
        expect(await stream.moveNext(), isTrue);
        expect((stream.current.movements as List).length, 6);
        await move(local);
        do {
          expect(
            await stream.moveNext().timeout(const Duration(seconds: 10)),
            isTrue,
          );
        } while ((stream.current.movements as List).isNotEmpty);
        expect(project(stream.current).sublist(1, 9), List.filled(8, 0));
      } finally {
        await stream.cancel();
        await bloc.close();
      }
    });
    test(
      '$kind retains local returns when original invoices are outside scope',
      () async {
        await move({
          'sales': local['sales']!,
          'purchases': local['purchases']!,
        });
        final dynamic bloc = await open(kind);
        try {
          final dynamic data = await (bloc.dataStream as Stream).first;
          expect((data.movements as List).length, 4);
          expect(project(data).sublist(1, 7), [
            0,
            0,
            kind == 'stock' ? 1 : 2,
            kind == 'stock' ? 1 : 2,
            0,
            0,
          ]);
          expect(
            (data.movements as List).every((dynamic m) => m.totalCents == 990),
            isTrue,
          );
        } finally {
          await bloc.close();
        }
      },
    );
    test(
      '$kind refreshes after purchase return is voided without a sale change',
      () async {
        final dynamic bloc = await open(kind);
        final stream = StreamIterator<dynamic>(bloc.dataStream as Stream);
        try {
          expect(await stream.moveNext(), isTrue);
          await db.customUpdate(
            "UPDATE purchase_return_adjustments SET status = 'voided' WHERE id = ?",
            variables: [
              Variable.withInt(local['purchase_return_adjustments']!),
            ],
            updates: {db.purchaseReturnAdjustments},
          );
          do {
            expect(
              await stream.moveNext().timeout(const Duration(seconds: 10)),
              isTrue,
            );
          } while ((stream.current.movements as List).length != 5);
          final dynamic data = stream.current;
          if (data is StockMovementReportData) {
            expect(data.summary.totalPurchaseReturnAdj, 0);
            expect(data.summary.totalPurchaseReturnAdjCents, 0);
          } else {
            expect(project(data)[4], 1);
            expect(project(data)[8], 990);
          }
        } finally {
          await stream.cancel();
          await bloc.close();
        }
      },
    );
  }
}
