import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/document_posting_scope.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:tapix/features/reports/presentation/bloc/inventory_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_stocktake_report_bloc.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int currency, supplier, customer, product, variant;
  var sequence = 0;

  Future<int> insert(
    String table,
    Map<String, Object?> data,
  ) => db.customInsert(
    'INSERT INTO $table (${data.keys.join(',')}) VALUES (${List.filled(data.length, '?').join(',')})',
    variables: data.values
        .map(
          (value) => switch (value) {
            int n => Variable.withInt(n),
            String s => Variable.withString(s),
            _ => const Variable<int>(null),
          },
        )
        .toList(),
  );

  setUp(() async {
    db = fixtures.memoryDb();
    currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    supplier = await insert('suppliers', {
      'name': 'Supplier',
      'currency_id': currency,
    });
    customer = await insert('customers', {
      'name': 'Customer',
      'currency_id': currency,
    });
    product = await insert('products', {
      'name': 'Simple with optional size',
      'has_variants': 0,
      'cost_cents': 500,
      'price_cents': 1000,
      'stock_quantity': 20,
    });
    final size = await insert('sizes', {'name': 'Size'});
    variant = await insert('product_variants', {
      'product_id': product,
      'size_id': size,
      'cost_cents': 500,
      'price_cents': 1000,
      'stock_quantity': 20,
    });
  });
  tearDown(() => db.close());

  Future<int> create(
    InventoryPostingDocument kind, {
    bool explicit = false,
    int quantity = 2,
    String? status,
  }) async {
    final sale = kind == InventoryPostingDocument.sale;
    final purchase = kind == InventoryPostingDocument.purchase;
    final original = switch (kind) {
      InventoryPostingDocument.saleReturn => InventoryPostingDocument.sale,
      InventoryPostingDocument.purchaseReturn =>
        InventoryPostingDocument.purchase,
      _ => null,
    };
    int? parent, item;
    if (original != null) {
      parent = await create(original, explicit: explicit);
      item =
          (await db
                  .customSelect(
                    'SELECT id FROM ${original.items} WHERE ${original.parentKey} = $parent',
                  )
                  .getSingle())
              .read<int>('id');
    }
    final id = await insert(kind.table, {
      sale
              ? 'invoice_number'
              : purchase
              ? 'purchase_number'
              : 'return_number':
          'HISTORY-${sequence++}',
      'currency_id': currency,
      if (sale || purchase)
        'payment_method': 'cash'
      else
        'refund_method': 'cash',
      'status': status ?? (sale ? 'completed' : 'posted'),
      'subtotal_cents': quantity * 1000,
      'discount_cents': 200,
      'tax_cents': 0,
      'total_cents': quantity * 1000 - 200,
      sale
          ? 'sale_date'
          : purchase
          ? 'purchase_date'
          : 'return_date': DateTime.now()
          .toIso8601String(),
      if (original != null) original.parentKey: parent,
      if (original != null) 'reason': 'Return',
      if (original == null)
        (sale || kind == InventoryPostingDocument.saleAdjustment)
                ? 'customer_id'
                : 'supplier_id':
            (sale || kind == InventoryPostingDocument.saleAdjustment)
            ? customer
            : supplier,
    });
    await insert(kind.items, {
      kind.parentKey: id,
      'quantity': quantity,
      if (original != null)
        original == InventoryPostingDocument.sale
                ? 'sale_item_id'
                : 'purchase_item_id':
            item,
      if (original == null) ...{
        'product_id': product,
        'variant_id': explicit ? variant : null,
        purchase ? 'unit_cost_cents' : 'unit_price_cents': 1000,
        if (!sale && !purchase) 'unit_cost_cents': 500,
      },
      if (sale) 'cost_cents': 500,
      if (original != null || sale || purchase)
        'subtotal_cents': quantity * 1000,
      'discount_cents': 100,
      'tax_cents': 0,
      original != null ? 'refund_cents' : 'total_cents': quantity * 1000 - 100,
    });
    return id;
  }

  Future<void> relocate(InventoryPostingDocument kind, int id) async {
    final scope = await BusinessFoundationRepository(db).getScope();
    final other = const Uuid().v4();
    await insert('business_warehouses', {
      'id': other,
      'organization_id': scope.organizationId,
      'branch_id': scope.branchId,
      'code': other,
    });
    // Test only: emulate a future imported document; production locations stay immutable.
    await db.customStatement(
      'DROP TRIGGER IF EXISTS business_location_immutable',
    );
    await db.customUpdate(
      'UPDATE business_document_locations SET warehouse_id = ? WHERE source_table = ? AND source_id = ?',
      variables: [
        Variable.withString(other),
        Variable.withString(kind.table),
        Variable.withInt(id),
      ],
      updates: {db.businessDocumentLocations},
    );
  }

  Future<InventoryReportsData> inventory() async {
    final bloc = InventoryReportsBloc(db);
    try {
      return await bloc.dataStream.first.timeout(const Duration(seconds: 10));
    } finally {
      await bloc.close();
    }
  }

  int movementQuantity(
    InventoryReportsData data,
    InventoryPostingDocument kind,
  ) => data.productMovement.fold(
    0,
    (sum, item) =>
        sum +
        switch (kind) {
          InventoryPostingDocument.sale => item.soldQty,
          InventoryPostingDocument.purchase => item.purchasedQty,
          InventoryPostingDocument.saleReturn ||
          InventoryPostingDocument.saleAdjustment => item.saleReturnedQty,
          InventoryPostingDocument.purchaseReturn ||
          InventoryPostingDocument.purchaseAdjustment =>
            item.purchaseReturnedQty,
        },
  );

  Future<SupplierStocktakeReportData> supplierReport() async {
    final bloc = SupplierStocktakeReportBloc(db);
    try {
      final next = bloc.stream.firstWhere(
        (s) =>
            s is RealtimeSuccess<SupplierStocktakeReportData> &&
            s.data.supplierId == supplier,
      );
      bloc.add(SupplierStocktakeReportSupplierChanged(supplier));
      return (await next.timeout(const Duration(seconds: 10))
              as RealtimeSuccess<SupplierStocktakeReportData>)
          .data;
    } finally {
      await bloc.close();
    }
  }

  for (final kind in InventoryPostingDocument.values) {
    for (final explicit in [false, true]) {
      test(
        '${kind.name}: scoped movement, explicit variant=$explicit',
        () async {
          if (explicit) {
            await db.customStatement(
              'UPDATE products SET has_variants = 1 WHERE id = ?',
              [product],
            );
            final size = await insert('sizes', {'name': 'Other size'});
            await insert('product_variants', {
              'product_id': product,
              'size_id': size,
              'cost_cents': 800,
              'price_cents': 1500,
            });
          }
          final id = await create(kind, explicit: explicit);
          final before = await inventory();
          expect(movementQuantity(before, kind), 2);
          expect(before.productMovement.single.variantId, variant);
          await relocate(kind, id);
          expect(movementQuantity(await inventory(), kind), 0);
        },
      );
    }
    test('${kind.name}: supplier activity ignores foreign document', () async {
      await create(InventoryPostingDocument.purchase, quantity: 20);
      final id = await create(kind);
      int amount(SupplierStocktakeReportData data) => data.products.fold(
        0,
        (sum, item) =>
            sum +
            switch (kind) {
              InventoryPostingDocument.sale => item.soldQuantity,
              InventoryPostingDocument.purchase => item.purchasedQuantity,
              InventoryPostingDocument.saleReturn ||
              InventoryPostingDocument.saleAdjustment =>
                item.saleReturnedQuantity,
              InventoryPostingDocument.purchaseReturn ||
              InventoryPostingDocument.purchaseAdjustment =>
                item.purchaseReturnedQuantity,
            },
      );
      final before = amount(await supplierReport());
      final hasDirectSupplierFact =
          kind == InventoryPostingDocument.purchase ||
          kind == InventoryPostingDocument.purchaseReturn ||
          kind == InventoryPostingDocument.purchaseAdjustment;
      expect(
        before,
        hasDirectSupplierFact
            ? (kind == InventoryPostingDocument.purchase ? 22 : 2)
            : 0,
      );
      await relocate(kind, id);
      expect(
        amount(await supplierReport()),
        hasDirectSupplierFact && kind == InventoryPostingDocument.purchase
            ? 20
            : 0,
      );
    });
  }

  test(
    'mixed null and explicit simple lines aggregate once despite optional size',
    () async {
      await create(InventoryPostingDocument.sale);
      await create(InventoryPostingDocument.sale, explicit: true, quantity: 3);
      final data = await inventory();
      expect(data.productMovement, hasLength(1));
      expect(movementQuantity(data, InventoryPostingDocument.sale), 5);
      expect(data.productMovement.single.hasVariants, isFalse);
    },
  );

  test('draft and voided invoices do not count as physical movement', () async {
    for (final kind in [
      InventoryPostingDocument.sale,
      InventoryPostingDocument.purchase,
    ]) {
      await create(kind, status: 'draft');
      await create(kind, status: 'voided');
    }
    expect((await inventory()).productMovement, isEmpty);
  });

  test('disabled local warehouse keeps its movement history', () async {
    await create(InventoryPostingDocument.sale);
    await db.customStatement('UPDATE business_warehouses SET is_active = 0');
    expect(
      movementQuantity(await inventory(), InventoryPostingDocument.sale),
      2,
    );
  });

  test(
    'document-only status change refreshes inventory movement stream',
    () async {
      final sale = await create(InventoryPostingDocument.sale, status: 'draft');
      final bloc = InventoryReportsBloc(db);
      final events = StreamIterator(bloc.dataStream);
      try {
        expect(await events.moveNext(), isTrue);
        expect(events.current.productMovement, isEmpty);
        await (db.update(db.sales)..where((s) => s.id.equals(sale))).write(
          const SalesCompanion(status: Value('completed')),
        );
        do {
          expect(
            await events.moveNext().timeout(const Duration(seconds: 10)),
            isTrue,
          );
        } while (events.current.productMovement.isEmpty);
        expect(
          movementQuantity(events.current, InventoryPostingDocument.sale),
          2,
        );
      } finally {
        await events.cancel();
        await bloc.close();
      }
    },
  );

  test(
    'historic purchases cannot manufacture a WAC supplier balance',
    () async {
      await create(InventoryPostingDocument.purchase, quantity: 20);
      final localSupplier = supplier;
      supplier = await insert('suppliers', {
        'name': 'Other supplier',
        'currency_id': currency,
      });
      final otherPurchase = await create(
        InventoryPostingDocument.purchase,
        quantity: 20,
      );
      supplier = localSupplier;
      expect((await supplierReport()).products.single.remainingQuantity, 0);
      await relocate(InventoryPostingDocument.purchase, otherPurchase);
      final local = (await supplierReport()).products.single;
      expect(local.remainingQuantity, 0);
      expect(local.remainingValueCents, 0);
    },
  );

  test(
    'supplier filter does not match a foreign purchase of the same product',
    () async {
      final purchase = await create(InventoryPostingDocument.purchase);
      await relocate(InventoryPostingDocument.purchase, purchase);
      await create(InventoryPostingDocument.sale);
      expect((await inventory()).productMovement, hasLength(1));
      final bloc = InventoryReportsBloc(db);
      try {
        final next = bloc.stream.firstWhere(
          (s) =>
              s is RealtimeSuccess<InventoryReportsData> &&
              s.data.movementSupplierId == supplier,
        );
        bloc.add(InventoryMovementSupplierFilterChanged(supplier, 'Supplier'));
        final state =
            await next.timeout(const Duration(seconds: 10))
                as RealtimeSuccess<InventoryReportsData>;
        expect(state.data.productMovement, isEmpty);
      } finally {
        await bloc.close();
      }
    },
  );

  test(
    'location-only changes refresh movement without stock changes',
    () async {
      final sale = await create(InventoryPostingDocument.sale);
      final bloc = InventoryReportsBloc(db);
      final events = StreamIterator(bloc.dataStream);
      try {
        expect(await events.moveNext(), isTrue);
        expect(
          movementQuantity(events.current, InventoryPostingDocument.sale),
          2,
        );
        await relocate(InventoryPostingDocument.sale, sale);
        do {
          expect(
            await events.moveNext().timeout(const Duration(seconds: 10)),
            isTrue,
          );
        } while (events.current.productMovement.isNotEmpty);
        expect(events.current.totalStockUnits, 20);
      } finally {
        await events.cancel();
        await bloc.close();
      }
    },
  );
}
