import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/business/warehouse_transfer_preflight.dart';
import 'package:tapix/features/business/data/warehouse_transfer_dispatch_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_receipt_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_recall_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_reporting_service.dart';
import 'package:tapix/features/business/data/warehouse_transfer_repository.dart';
import 'package:uuid/uuid.dart';
import 'package:tapix/core/services/inventory/supplier_identity_rules.dart';
import 'package:tapix/core/services/inventory/inventory_stock_source_service.dart';
import 'package:tapix/core/services/stock_service.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_stocktake_report_bloc.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_sales_report_bloc.dart';
import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
  late int currency, product, variant, supplier, second, customer;
  var serial = 0;
  var quantityScale = 1;
  var measurementType = 'piece';
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
    serial = 0;
    quantityScale = 1;
    measurementType = 'piece';
    currency = (await db.select(db.currencies).get()).first.id;
    supplier = await insert('suppliers', {
      'name': 'A',
      'currency_id': currency,
    });
    second = await insert('suppliers', {'name': 'B', 'currency_id': currency});
    customer = await insert('customers', {
      'name': 'Buyer',
      'currency_id': currency,
    });
    product = await insert('products', {
      'name': 'WAC shoe',
      'currency_id': currency,
      'cost_cents': 100,
      'price_cents': 200,
    });
    variant = await insert('product_variants', {
      'product_id': product,
      'cost_cents': 100,
      'price_cents': 200,
    });
  });
  tearDown(() => db.close());
  Future<int> buy(
    int vendor,
    int qty, {
    int cost = 100,
    int? supplierIdentityId,
  }) async {
    final id = await insert('purchases', {
      'purchase_number': 'P-${serial++}',
      'supplier_id': vendor,
      'currency_id': currency,
      'status': 'draft',
      'payment_method': 'credit',
      'subtotal_cents': (qty * cost ~/ quantityScale),
      'total_cents': (qty * cost ~/ quantityScale),
      'tax_cents': 0,
    });
    final line = await insert('purchase_items', {
      'purchase_id': id,
      'product_id': product,
      'variant_id': variant,
      'supplier_identity_requested': supplierIdentityId == null ? 0 : 1,
      'supplier_identity_id': ?supplierIdentityId,
      'quantity': qty,
      'quantity_scale': quantityScale,
      'measurement_type': measurementType,
      'unit_cost_cents': cost,
      'subtotal_cents': (qty * cost ~/ quantityScale),
      'total_cents': (qty * cost ~/ quantityScale),
    });
    await db.purchaseDao.postPurchase(id);
    return line;
  }

  Future<int> sell(int qty, {int? supplierIdentityId}) async {
    final id = await insert('sales', {
      'invoice_number': 'S-${serial++}',
      'customer_id': customer,
      'currency_id': currency,
      'status': 'draft',
      'payment_method': 'credit',
      'subtotal_cents': (qty * 200 ~/ quantityScale),
      'total_cents': (qty * 200 ~/ quantityScale),
      'tax_cents': 0,
    });
    final line = await insert('sale_items', {
      'sale_id': id,
      'product_id': product,
      'variant_id': variant,
      'supplier_identity_id': ?supplierIdentityId,
      'quantity': qty,
      'quantity_scale': quantityScale,
      'measurement_type': measurementType,
      'unit_price_cents': 200,
      'subtotal_cents': (qty * 200 ~/ quantityScale),
      'total_cents': (qty * 200 ~/ quantityScale),
    });
    await db.saleDao.postSale(id);
    return line;
  }

  Future<int> returnSale(int line, int qty) async {
    final sale = (await (db.select(
      db.saleItems,
    )..where((r) => r.id.equals(line))).getSingle()).saleId;
    final id = await insert('sale_returns', {
      'return_number': 'R-${serial++}',
      'sale_id': sale,
      'currency_id': currency,
      'status': 'draft',
      'refund_method': 'credit',
      'subtotal_cents': (qty * 200 ~/ quantityScale),
      'total_cents': (qty * 200 ~/ quantityScale),
    });
    await insert('sale_return_items', {
      'return_id': id,
      'sale_item_id': line,
      'quantity': qty,
      'quantity_scale': quantityScale,
      'measurement_type': measurementType,
      'subtotal_cents': (qty * 200 ~/ quantityScale),
      'refund_cents': (qty * 200 ~/ quantityScale),
    });
    await db.saleDao.postSaleReturn(id);
    return id;
  }

  Future<SupplierSalesReportData> report() async {
    final bloc = SupplierSalesReportBloc(db);
    try {
      return await bloc.load();
    } finally {
      await bloc.close();
    }
  }

  Future<SupplierStocktakeReportData> stocktake(int vendor) async {
    final bloc = SupplierStocktakeReportBloc(db);
    try {
      final result = bloc.stream.firstWhere(
        (state) =>
            state is RealtimeSuccess<SupplierStocktakeReportData> &&
            state.data.supplierId == vendor,
      );
      bloc.add(SupplierStocktakeReportSupplierChanged(vendor));
      return ((await result) as RealtimeSuccess<SupplierStocktakeReportData>)
          .data;
    } finally {
      await bloc.close();
    }
  }

  Future<List<dynamic>> parts(String key) async =>
      jsonDecode(
            (await db
                    .customSelect(
                      'SELECT allocations FROM inventory_origin_events WHERE event_key=?',
                      variables: [Variable.withString(key)],
                    )
                    .getSingle())
                .read<String>('allocations'),
          )
          as List;
  Future<void> balanced() async {
    final rows = await db.customSelect(
      '''SELECT o.quantity,o.layers,s.quantity AS stock FROM inventory_origin_states o
      JOIN business_warehouse_stocks s ON s.warehouse_id=o.warehouse_id AND s.variant_id=o.variant_id WHERE o.dirty=0''',
    ).get();
    for (final r in rows) {
      expect(r.read<int>('quantity'), r.read<int>('stock'));
      expect(
        (jsonDecode(r.read<String>('layers')) as List).fold<int>(
          0,
          (n, e) => n + (e['q'] as int),
        ),
        r.read<int>('stock'),
      );
    }
  }

  test(
    'new WAC sales allocate receipts while preserving WAC cost and empty consumption ledger',
    () async {
      final first = await buy(supplier, 5, cost: 100);
      final next = await buy(second, 5, cost: 300);
      final line = await sell(7);
      final saved = (await (db.select(
        db.saleItems,
      )..where((r) => r.id.equals(line))).getSingle());
      expect(saved.costCents!.toBigInt().toInt(), 200);
      expect(await db.select(db.batchConsumptions).get(), isEmpty);
      expect(
        (await parts('sale:$line')).map((e) => [e['p'], e['q']]).toList(),
        [
          [first, 5],
          [next, 2],
        ],
      );
      final rows = (await report()).rows;
      expect(rows.singleWhere((r) => r.supplierId == supplier).soldQuantity, 5);
      expect(rows.singleWhere((r) => r.supplierId == second).soldQuantity, 2);
      expect(rows.every((r) => r.sourceQuality == 'allocated'), isTrue);
      expect(rows.fold<int>(0, (n, r) => n + r.netCents), 1400);
      final firstStocktake = await stocktake(supplier);
      final secondStocktake = await stocktake(second);
      expect(firstStocktake.products.single.soldQuantity, 5);
      expect(firstStocktake.products.single.remainingQuantity, 0);
      expect(secondStocktake.products.single.soldQuantity, 2);
      expect(secondStocktake.products.single.remainingQuantity, 3);
      await balanced();
    },
  );
  test(
    'partial linked returns and their cancellation restore original sources without overclaiming',
    () async {
      final a = await buy(supplier, 2);
      final b = await buy(second, 3);
      final sale = await sell(4);
      final r1 = await returnSale(sale, 1);
      await returnSale(sale, 2);
      var rows = (await report()).rows;
      expect(
        rows.singleWhere((r) => r.supplierId == supplier).returnedQuantity,
        2,
      );
      expect(
        rows.singleWhere((r) => r.supplierId == second).returnedQuantity,
        1,
      );
      await db.saleDao.voidSaleReturn(r1);
      await returnSale(sale, 1);
      rows = (await report()).rows;
      expect(
        rows.singleWhere((r) => r.supplierId == supplier).returnedQuantity,
        2,
      );
      expect(
        rows.singleWhere((r) => r.supplierId == second).returnedQuantity,
        1,
      );
      expect((await parts('sale:$sale')).map((e) => e['p']).toList(), [a, b]);
      await balanced();
    },
  );
  test(
    'opening stock and direct stock edits never acquire a guessed vendor',
    () async {
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity=2 WHERE id=?',
        [variant],
      );
      await buy(supplier, 3);
      final first = await sell(3);
      expect((await parts('sale:$first')).map((e) => e['q']).toList(), [2, 1]);
      expect(
        (await report()).rows
            .singleWhere((r) => r.supplierId == -1)
            .soldQuantity,
        2,
      );
      await db.customStatement(
        'UPDATE product_variants SET stock_quantity=4 WHERE id=?',
        [variant],
      );
      final second = await sell(1);
      expect((await parts('sale:$second')).single['k'], 'unknown');
      await balanced();
    },
  );
  test(
    'sale cancellation restores sources and a new sale reuses their quantities',
    () async {
      final purchase = await buy(supplier, 5);
      final sale = await sell(2);
      final header = (await (db.select(
        db.saleItems,
      )..where((r) => r.id.equals(sale))).getSingle()).saleId;
      await db.saleDao.voidSale(header);
      final replacement = await sell(5);
      expect(
        (await parts(
          'sale:$replacement',
        )).fold<int>(0, (n, e) => n + (e['q'] as int)),
        5,
      );
      expect(
        (await parts('sale:$replacement')).every((e) => e['p'] == purchase),
        isTrue,
      );
      expect((await report()).rows.single.soldQuantity, 5);
      await balanced();
    },
  );
  test(
    'unlinked customer return remains a distinct origin when sold again',
    () async {
      await buy(supplier, 1);
      await sell(1);
      final id = await insert('sale_return_adjustments', {
        'return_number': 'SAR-1',
        'customer_id': customer,
        'currency_id': currency,
        'status': 'draft',
        'refund_method': 'credit',
        'subtotal_cents': 200,
        'total_cents': 200,
      });
      await insert('sale_return_adjustment_items', {
        'return_id': id,
        'product_id': product,
        'variant_id': variant,
        'quantity': 1,
        'unit_price_cents': 200,
        'unit_cost_cents': 100,
        'total_cents': 200,
      });
      await db.adjustmentReturnDao.postSaleAdjReturn(
        id,
        journalEntryService: JournalEntryService(AccountingRepository(db)),
      );
      await sell(1);
      final row = (await report()).rows.singleWhere((r) => r.supplierId == -2);
      expect(row.supplierId, -2);
      expect(row.returnedQuantity, 1);
      expect(row.soldQuantity, 1);
      expect(row.netCents, 0);
      await balanced();
    },
  );
  test(
    'verified identity links WAC sale and standalone return without borrowing another supplier',
    () async {
      await db.customStatement(
        "UPDATE suppliers SET product_code='SUPA' WHERE id=?",
        [supplier],
      );
      final identity = await insert('supplier_product_identities', {
        'supplier_id': supplier,
        'product_id': product,
        'canonical_variant_id': variant,
        'supplier_code_snapshot': 'SUPA',
        'base_sku_snapshot': 'WAC-SHOE',
        'source_sku': 'SUPA-WAC-SHOE',
      });
      await buy(supplier, 2, supplierIdentityId: identity);
      await buy(second, 2);

      final snapshot = await InventoryStockSourceService(
        db,
      ).loadProduct(product, variantId: variant);
      final exactSource = snapshot.sources.singleWhere(
        (source) => source.supplierIdentityId == identity,
      );
      expect(exactSource.supplierId, supplier);
      expect(exactSource.supplierName, 'A');
      expect(exactSource.sourceCode, 'SUPA-WAC-SHOE');
      expect(exactSource.quantity, 2);

      final saleLine = await sell(2, supplierIdentityId: identity);
      expect(await parts('sale:$saleLine'), [
        {'k': 'purchase', 'p': isA<int>(), 'i': identity, 'q': 2},
      ]);

      final returnId = await insert('sale_return_adjustments', {
        'return_number': 'SAR-IDENTITY',
        'customer_id': customer,
        'currency_id': currency,
        'status': 'draft',
        'refund_method': 'credit',
        'subtotal_cents': 200,
        'total_cents': 200,
      });
      final returnLine = await insert('sale_return_adjustment_items', {
        'return_id': returnId,
        'product_id': product,
        'variant_id': variant,
        'supplier_identity_id': identity,
        'quantity': 1,
        'unit_price_cents': 200,
        'unit_cost_cents': 100,
        'total_cents': 200,
      });
      await db.adjustmentReturnDao.postSaleAdjReturn(
        returnId,
        journalEntryService: JournalEntryService(AccountingRepository(db)),
      );

      final rows = (await report()).rows;
      final supplierRow = rows.singleWhere((row) => row.supplierId == supplier);
      expect(supplierRow.soldQuantity, 2);
      expect(supplierRow.returnedQuantity, 1);
      expect(supplierRow.netCents, 200);
      expect(supplierRow.sourceQuality, 'identity');
      expect(rows.where((row) => row.supplierId < 0), isEmpty);
      expect(await parts('adjustment:$returnLine'), [
        {'k': 'supplier_identity_return', 'p': null, 'i': identity, 'q': 1},
      ]);

      await expectLater(
        sell(2, supplierIdentityId: identity),
        throwsA(
          isA<SupplierIdentityException>().having(
            (error) => error.messageKey,
            'messageKey',
            'supplier_identity.insufficient_source_quantity',
          ),
        ),
      );
      expect((await report()).rows.single.soldQuantity, 2);
      await balanced();
    },
  );
  test('origin write failure rolls back financial posting and stock', () async {
    await buy(supplier, 3);
    final before =
        (await db.select(db.productVariants).get()).single.stockQuantity;
    await db.customStatement(
      "CREATE TRIGGER origin_fail BEFORE INSERT ON inventory_origin_events WHEN NEW.delta<0 BEGIN SELECT RAISE(ABORT,'injected'); END",
    );
    await expectLater(sell(1), throwsA(anything));
    expect(
      (await db.select(db.productVariants).get()).single.stockQuantity,
      before,
    );
    expect((await db.select(db.sales).get()).single.status, 'draft');
    expect(
      await db
          .customSelect(
            "SELECT * FROM inventory_origin_events WHERE event_key LIKE 'sale:%'",
          )
          .get(),
      isEmpty,
    );
    await balanced();
  });
  test('warehouse origins cannot leak into another site', () async {
    await buy(supplier, 4);
    final local = await WarehouseOperationScope.resolve(db);
    const warehouse = '11111111-1111-4111-8111-111111111111';
    await insert('business_warehouses', {
      'id': warehouse,
      'organization_id': local.organizationId,
      'branch_id': local.branchId,
      'code': 'OTHER',
    });
    await insert('business_warehouse_stocks', {
      'warehouse_id': warehouse,
      'variant_id': variant,
      'quantity': 2,
      'unit_cost_cents': 100,
    });
    await StockService.adjustStock(
      db.saleDao,
      scope: await WarehouseOperationScope.resolve(db, warehouseId: warehouse),
      productId: product,
      variantId: variant,
      quantity: 1,
      direction: StockDirection.decrease,
      origin: const InventoryOriginIntent('sale', 999),
    );
    expect((await parts('sale:999')).single['k'], 'unknown');
    await balanced();
  });
  test('measured WAC keeps thousandths in provenance and report', () async {
    quantityScale = 1000;
    measurementType = 'weight';
    await db.customStatement(
      "UPDATE products SET measurement_type='weight' WHERE id=?",
      [product],
    );
    final purchase = await buy(supplier, 2500);
    final sale = await sell(1250);
    expect((await parts('sale:$sale')).single['q'], 1250);
    expect((await parts('sale:$sale')).single['p'], purchase);
    final row = (await report()).rows.single;
    expect(row.soldQuantity, 1250);
    expect(row.quantityScale, 1000);
    expect(row.netCents, 250);
    await balanced();
  });
  test(
    'linked purchase return and void preserve source availability',
    () async {
      await buy(supplier, 2);
      final line = await buy(second, 3);
      final purchase = (await (db.select(
        db.purchaseItems,
      )..where((p) => p.id.equals(line))).getSingle()).purchaseId;
      final id = await insert('purchase_returns', {
        'purchase_id': purchase,
        'return_number': 'PR',
        'currency_id': currency,
        'status': 'draft',
        'refund_method': 'credit',
        'subtotal_cents': 200,
        'total_cents': 200,
      });
      await insert('purchase_return_items', {
        'return_id': id,
        'purchase_item_id': line,
        'quantity': 2,
        'subtotal_cents': 200,
        'refund_cents': 200,
      });
      await db.purchaseDao.postPurchaseReturn(id);
      await db.purchaseDao.voidPurchaseReturn(id);
      await sell(5);
      final rows = (await report()).rows;
      expect(rows.singleWhere((r) => r.supplierId == supplier).soldQuantity, 2);
      expect(rows.singleWhere((r) => r.supplierId == second).soldQuantity, 3);
      await balanced();
    },
  );
  test(
    'posted warehouse transfer preserves WAC supplier at destination and report',
    () async {
      final purchase = await buy(supplier, 4);
      final source = await WarehouseOperationScope.resolve(db);
      const destinationId = '22222222-2222-4222-8222-222222222222';
      await insert('business_warehouses', {
        'id': destinationId,
        'organization_id': source.organizationId,
        'branch_id': source.branchId,
        'code': 'DEST',
        'name': 'Destination',
      });
      await insert('business_warehouse_stocks', {
        'warehouse_id': destinationId,
        'variant_id': variant,
        'quantity': 0,
        'unit_cost_cents': 100,
      });
      final destination = await WarehouseOperationScope.resolve(
        db,
        warehouseId: destinationId,
      );
      final user = await insert('users', {
        'username': 'origin-transfer-owner',
        'password_hash': 'test',
        'role': 'owner',
        'created_at': 1790208000000,
        'updated_at': 1790208000000,
      });
      final code = (await (db.select(
        db.currencies,
      )..where((row) => row.id.equals(currency))).getSingle()).code;
      await BranchCurrencyPolicyStore(db).bind(code);
      Future<int> authorize(
        TransferDraftAction action,
        String from,
        String to,
      ) async => user;
      final preflight = WarehouseTransferPreflight(
        db,
        authorizeWarehouse: (_) async {},
      );
      final repository = WarehouseTransferRepository(
        db,
        preflight: preflight,
        authorize: authorize,
      );
      final preview = await preflight.preview(
        source: source,
        destination: destination,
        lines: [
          WarehouseTransferRequestLine(
            productId: product,
            variantId: variant,
            quantity: 2,
          ),
        ],
      );
      final draft = await repository.create(
        requestKey: const Uuid().v4(),
        preview: preview,
      );
      final dispatched = await WarehouseTransferDispatchService(
        db,
        preflight: preflight,
        authorize: authorize,
      ).dispatch(transferId: draft.header.id, requestKey: const Uuid().v4());
      await WarehouseTransferReceiptService(db, authorize: authorize).receive(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
        items: [
          WarehouseTransferReceiptRequestItem(
            allocationId: dispatched.allocations.single.id,
            acceptedQuantity: 2,
          ),
        ],
      );

      final destinationLayers =
          jsonDecode(
                (await db
                        .customSelect(
                          'SELECT layers FROM inventory_origin_states WHERE warehouse_id=? AND variant_id=?',
                          variables: [
                            Variable.withString(destinationId),
                            Variable.withInt(variant),
                          ],
                        )
                        .getSingle())
                    .read<String>('layers'),
              )
              as List;
      expect(destinationLayers, [
        {'q': 2, 'p': purchase, 'k': 'purchase'},
      ]);
      final transferReport =
          await WarehouseTransferReportingService(
            db,
            authorizeWarehouse: (_) async {},
          ).report(
            warehouseId: destinationId,
            from: DateTime.utc(2026, 9, 23),
            toExclusive: DateTime.utc(2026, 9, 26),
            supplierId: supplier,
          );
      expect(transferReport.rows, hasLength(1));
      expect(transferReport.rows.single.acceptedQuantity, 2);
      expect(transferReport.rows.single.sources.single.supplierId, supplier);
      expect(transferReport.rows.single.sources.single.purchaseNumber, 'P-0');

      await StockService.adjustStock(
        db.saleDao,
        scope: destination,
        productId: product,
        variantId: variant,
        quantity: 1,
        direction: StockDirection.decrease,
        origin: const InventoryOriginIntent('sale', 999),
      );
      final destinationSale = await db
          .customSelect(
            'SELECT allocations FROM inventory_origin_events WHERE warehouse_id=? AND event_key=?',
            variables: [
              Variable.withString(destinationId),
              const Variable<String>('sale:999'),
            ],
          )
          .getSingle();
      expect(
        (jsonDecode(destinationSale.read<String>('allocations')) as List)
            .single['p'],
        purchase,
      );
      await balanced();
    },
  );
  test(
    'partial WAC receipt and recall preserve each supplier origin across warehouses',
    () async {
      final firstPurchase = await buy(supplier, 1);
      final secondPurchase = await buy(second, 1);
      final source = await WarehouseOperationScope.resolve(db);
      const destinationId = '33333333-3333-4333-8333-333333333333';
      await insert('business_warehouses', {
        'id': destinationId,
        'organization_id': source.organizationId,
        'branch_id': source.branchId,
        'code': 'PARTIAL-DEST',
        'name': 'Partial destination',
      });
      await insert('business_warehouse_stocks', {
        'warehouse_id': destinationId,
        'variant_id': variant,
        'quantity': 0,
        'unit_cost_cents': 100,
      });
      final destination = await WarehouseOperationScope.resolve(
        db,
        warehouseId: destinationId,
      );
      final user = await insert('users', {
        'username': 'partial-origin-transfer-owner',
        'password_hash': 'test',
        'role': 'owner',
        'created_at': 1790208000000,
        'updated_at': 1790208000000,
      });
      final code = (await (db.select(
        db.currencies,
      )..where((row) => row.id.equals(currency))).getSingle()).code;
      await BranchCurrencyPolicyStore(db).bind(code);
      Future<int> authorize(
        TransferDraftAction action,
        String from,
        String to,
      ) async => user;
      final preflight = WarehouseTransferPreflight(
        db,
        authorizeWarehouse: (_) async {},
      );
      final repository = WarehouseTransferRepository(
        db,
        preflight: preflight,
        authorize: authorize,
      );
      final preview = await preflight.preview(
        source: source,
        destination: destination,
        lines: [
          WarehouseTransferRequestLine(
            productId: product,
            variantId: variant,
            quantity: 2,
          ),
        ],
      );
      final draft = await repository.create(
        requestKey: const Uuid().v4(),
        preview: preview,
      );
      final dispatched = await WarehouseTransferDispatchService(
        db,
        preflight: preflight,
        authorize: authorize,
      ).dispatch(transferId: draft.header.id, requestKey: const Uuid().v4());
      final allocation = dispatched.allocations.single;
      await WarehouseTransferReceiptService(db, authorize: authorize).receive(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
        items: [
          WarehouseTransferReceiptRequestItem(
            allocationId: allocation.id,
            acceptedQuantity: 1,
          ),
        ],
      );
      await WarehouseTransferRecallService(db, authorize: authorize).recall(
        transferId: draft.header.id,
        requestKey: const Uuid().v4(),
        reason: 'Return the unreceived unit to its source warehouse',
      );

      Future<List<Map<String, dynamic>>> warehouseLayers(
        String warehouseId,
      ) async {
        final row = await db
            .customSelect(
              'SELECT layers FROM inventory_origin_states '
              'WHERE warehouse_id=? AND variant_id=?',
              variables: [
                Variable.withString(warehouseId),
                Variable.withInt(variant),
              ],
            )
            .getSingle();
        return (jsonDecode(row.read<String>('layers')) as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }

      final sourceLayers = await warehouseLayers(source.warehouseId);
      final destinationLayers = await warehouseLayers(destinationId);
      expect(destinationLayers, [
        {'q': 1, 'p': firstPurchase, 'k': 'purchase'},
      ]);
      expect(sourceLayers, [
        {'q': 1, 'p': secondPurchase, 'k': 'purchase'},
      ]);
      final combinedByPurchase = <int, int>{};
      for (final layer in [...sourceLayers, ...destinationLayers]) {
        final purchaseItemId = layer['p'] as int;
        combinedByPurchase.update(
          purchaseItemId,
          (quantity) => quantity + (layer['q'] as int),
          ifAbsent: () => layer['q'] as int,
        );
      }
      expect(combinedByPurchase, {firstPurchase: 1, secondPurchase: 1});
      await balanced();
    },
  );
  test('origin events cannot be modified, deleted or replaced', () async {
    await buy(supplier, 1);
    for (final sql in [
      "UPDATE inventory_origin_events SET allocations='[]'",
      'DELETE FROM inventory_origin_events',
      'INSERT OR REPLACE INTO inventory_origin_events SELECT * FROM inventory_origin_events',
    ]) {
      await expectLater(db.customStatement(sql), throwsA(anything));
    }
    expect(await db.select(db.inventoryOriginEvents).get(), hasLength(1));
  });
}
