import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/business/data/business_foundation_repository.dart';
import 'package:uuid/uuid.dart';

import 'business_foundation_test.dart' as fixtures;

void main() {
  late AppDatabase db;
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
  Future<void> seed(String method, bool optionalSize) async {
    db = fixtures.memoryDb();
    final currency = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
    final supplier = await insert('suppliers', {
      'name': 'Supplier',
      'currency_id': currency,
    });
    product = await insert('products', {
      'name': 'Simple',
      'currency_id': currency,
      'costing_method': method,
      'cost_cents': 500,
      'price_cents': 1200,
      'stock_quantity': 20,
    });
    final size = optionalSize
        ? await insert('sizes', {'name': 'Optional'})
        : null;
    variant = await insert('product_variants', {
      'product_id': product,
      'size_id': ?size,
      'cost_cents': 500,
      'price_cents': 1200,
      'stock_quantity': 20,
    });
    if (method == 'fifo') {
      await insert('product_batches', {
        'product_id': product,
        'variant_id': variant,
        'batch_number': 'OPENING',
        'source': 'opening',
        'received_quantity': 20,
        'remaining_quantity': 20,
        'unit_cost_cents': 500,
      });
    }
    warehouse = (await BusinessFoundationRepository(db).getScope()).warehouseId;
    purchase = await insert('purchases', {
      'purchase_number': 'MIRROR-1',
      'supplier_id': supplier,
      'currency_id': currency,
      'status': 'draft',
      'payment_method': 'cash',
      'subtotal_cents': 2000,
      'discount_cents': 200,
      'tax_cents': 0,
      'total_cents': 1800,
    });
    await insert('purchase_items', {
      'purchase_id': purchase,
      'product_id': product,
      'quantity': 2,
      'unit_cost_cents': 1000,
      'subtotal_cents': 2000,
      // Persisted line discount includes 100 line + 100 allocated invoice.
      'discount_cents': 200,
      'tax_cents': 0,
      'total_cents': 1800,
    });
  }

  Future<Object> snapshot() async => [
    await fixtures.legacySnapshot(db),
    for (final table in [
      'business_warehouse_stocks',
      'business_document_locations',
    ])
      (await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
          .map((r) => r.data)
          .toList(),
  ];

  for (final method in ['wac', 'fifo']) {
    test('$method voided purchase cannot be posted again', () async {
      await seed(method, false);
      addTearDown(db.close);
      await db.purchaseDao.postPurchase(purchase);
      await db.purchaseDao.voidPurchase(purchase);
      final before = await snapshot();
      await expectLater(
        db.purchaseDao.postPurchase(purchase),
        throwsStateError,
      );
      expect(await snapshot(), before);
    });
  }

  for (final status in ['voided', 'unexpected']) {
    test('purchase return in $status cannot change inventory', () async {
      await seed('wac', false);
      addTearDown(db.close);
      await db.purchaseDao.postPurchase(purchase);
      final header = (await db.purchaseDao.getPurchaseById(purchase))!;
      final item = (await db.purchaseDao.getPurchaseItems(purchase)).single;
      final id = await insert('purchase_returns', {
        'purchase_id': purchase,
        'return_number': 'RETURN-STATE',
        'currency_id': header.currencyId,
        'total_cents': 900,
        'status': status,
      });
      await insert('purchase_return_items', {
        'return_id': id,
        'purchase_item_id': item.id,
        'quantity': 1,
        'refund_cents': 900,
      });
      final before = await snapshot();
      await expectLater(
        db.purchaseDao.postPurchaseReturn(id),
        throwsStateError,
      );
      expect(await snapshot(), before);
    });
  }

  for (final method in ['wac', 'fifo']) {
    for (final status in ['draft', 'pending', 'voided', 'posted']) {
      test('$method linked return requires posted original: $status', () async {
        await seed(method, false);
        addTearDown(db.close);
        if (status == 'posted' || status == 'voided') {
          await db.purchaseDao.postPurchase(purchase);
        }
        if (status == 'voided') {
          await db.purchaseDao.voidPurchase(purchase);
        } else if (status == 'pending') {
          await db.purchaseDao.updatePurchaseStatus(purchase, status);
        }
        final header = (await db.purchaseDao.getPurchaseById(purchase))!;
        final item = (await db.purchaseDao.getPurchaseItems(purchase)).single;
        final id = await insert('purchase_returns', {
          'purchase_id': purchase,
          'return_number': 'RETURN-PARENT',
          'currency_id': header.currencyId,
          'total_cents': 900,
          'status': 'draft',
        });
        await insert('purchase_return_items', {
          'return_id': id,
          'purchase_item_id': item.id,
          'quantity': 1,
          'refund_cents': 900,
        });
        final before = await snapshot();
        if (status == 'posted') {
          await db.purchaseDao.postPurchaseReturn(id);
          expect(
            (await db.purchaseDao.getPurchaseReturnById(id))!.status,
            'posted',
          );
          expect(
            (await db.select(db.businessWarehouseStocks).getSingle()).quantity,
            21,
          );
        } else {
          await expectLater(
            db.purchaseDao.postPurchaseReturn(id),
            throwsStateError,
          );
          expect(await snapshot(), before);
        }
      });
    }
  }

  test(
    'linked return with different currency leaves all balances unchanged',
    () async {
      await seed('wac', false);
      addTearDown(db.close);
      await db.purchaseDao.postPurchase(purchase);
      final header = (await db.purchaseDao.getPurchaseById(purchase))!;
      final currencies = await db.select(db.currencies).get();
      final otherCurrency = currencies.firstWhere(
        (c) => c.id != header.currencyId,
      );
      final item = (await db.purchaseDao.getPurchaseItems(purchase)).single;
      final id = await insert('purchase_returns', {
        'purchase_id': purchase,
        'return_number': 'RETURN-CURRENCY',
        'currency_id': otherCurrency.id,
        'total_cents': 900,
        'status': 'draft',
      });
      await insert('purchase_return_items', {
        'return_id': id,
        'purchase_item_id': item.id,
        'quantity': 1,
        'refund_cents': 900,
      });
      final before = await snapshot();
      await expectLater(
        db.purchaseDao.postPurchaseReturn(id),
        throwsStateError,
      );
      expect(await snapshot(), before);
    },
  );

  for (final invalid in ['negative', 'zero', 'scale', 'measurement', 'empty']) {
    test(
      'invalid return $invalid leaves inventory and ledger unchanged',
      () async {
        await seed('wac', false);
        addTearDown(db.close);
        await db.purchaseDao.postPurchase(purchase);
        final header = (await db.purchaseDao.getPurchaseById(purchase))!;
        final item = (await db.purchaseDao.getPurchaseItems(purchase)).single;
        final id = await insert('purchase_returns', {
          'purchase_id': purchase,
          'return_number': 'RETURN-QUANTITY',
          'currency_id': header.currencyId,
          'total_cents': 900,
          'status': 'draft',
        });
        if (invalid != 'empty') {
          // A valid first line proves the whole document is rejected unchanged.
          await insert('purchase_return_items', {
            'return_id': id,
            'purchase_item_id': item.id,
            'quantity': 1,
            'refund_cents': 900,
          });
          await insert('purchase_return_items', {
            'return_id': id,
            'purchase_item_id': item.id,
            'quantity': invalid == 'negative'
                ? -1
                : invalid == 'zero'
                ? 0
                : 1,
            'quantity_scale': invalid == 'scale' ? 1000 : 1,
            'measurement_type': invalid == 'measurement' ? 'weight' : 'piece',
            'refund_cents': 900,
          });
        }
        final before = await snapshot();
        await expectLater(
          db.purchaseDao.postPurchaseReturn(id),
          throwsStateError,
        );
        expect(await snapshot(), before);
      },
    );
  }

  for (final action in ['post', 'void']) {
    test(
      'inactive warehouse rejects purchase $action without partial writes',
      () async {
        await seed('fifo', false);
        addTearDown(db.close);
        if (action == 'void') await db.purchaseDao.postPurchase(purchase);
        await (db.update(db.businessWarehouses)
              ..where((w) => w.id.equals(warehouse)))
            .write(const BusinessWarehousesCompanion(isActive: Value(false)));
        final before = await snapshot();
        await expectLater(
          action == 'post'
              ? db.purchaseDao.postPurchase(purchase)
              : db.purchaseDao.voidPurchase(purchase),
          throwsStateError,
        );
        expect(await snapshot(), before);
      },
    );
  }

  for (final explicitVariant in [false, true]) {
    test(
      'purchase WAC reads warehouse balance with stale mirror, explicit=$explicitVariant',
      () async {
        await seed('wac', false);
        addTearDown(db.close);
        if (explicitVariant) {
          await db.customStatement(
            'UPDATE purchase_items SET variant_id = ? WHERE purchase_id = ?',
            [variant, purchase],
          );
        }
        await db.customStatement('DROP TRIGGER business_stock_variant_update');
        await db.customStatement(
          'UPDATE product_variants SET cost_cents = 9999, stock_quantity = 200 WHERE id = ?',
          [variant],
        );
        await db.customStatement(
          'UPDATE products SET cost_cents = 9999, stock_quantity = 200 WHERE id = ?',
          [product],
        );
        await db.purchaseDao.postPurchase(purchase);
        final balance = await db.select(db.businessWarehouseStocks).getSingle();
        expect(balance.quantity, 22);
        expect(balance.unitCostCents, 536);
        await db.purchaseDao.voidPurchase(purchase);
        expect(
          (await db.select(db.businessWarehouseStocks).getSingle()).quantity,
          20,
        );
      },
    );
  }

  for (final action in ['void', 'return']) {
    for (final explicitVariant in [false, true]) {
      for (final shortage in [false, true]) {
        test(
          '$action uses warehouse quantity explicit=$explicitVariant shortage=$shortage',
          () async {
            await seed('wac', false);
            addTearDown(db.close);
            if (explicitVariant) {
              await db.customStatement(
                'UPDATE purchase_items SET variant_id = ? WHERE purchase_id = ?',
                [variant, purchase],
              );
            }
            await db.purchaseDao.postPurchase(purchase);
            int? returnId;
            if (action == 'return') {
              final header = (await db.purchaseDao.getPurchaseById(purchase))!;
              final item = (await db.purchaseDao.getPurchaseItems(
                purchase,
              )).single;
              returnId = await insert('purchase_returns', {
                'purchase_id': purchase,
                'return_number': 'RETURN-STOCK',
                'currency_id': header.currencyId,
                'total_cents': 900,
                'status': 'draft',
              });
              await insert('purchase_return_items', {
                'return_id': returnId,
                'purchase_item_id': item.id,
                'quantity': 1,
                'refund_cents': 900,
              });
            }
            await db.customStatement(
              'DROP TRIGGER business_stock_variant_update',
            );
            if (shortage) {
              await db.customStatement(
                'UPDATE business_warehouse_stocks SET quantity = 0',
              );
            }
            final mirror = shortage ? 200 : 0;
            await db.customStatement(
              'UPDATE product_variants SET stock_quantity = ? WHERE id = ?',
              [mirror, variant],
            );
            await db.customStatement(
              'UPDATE products SET stock_quantity = ? WHERE id = ?',
              [mirror, product],
            );
            final before = await snapshot();
            Future<void> perform() => action == 'void'
                ? db.purchaseDao.voidPurchase(purchase)
                : db.purchaseDao.postPurchaseReturn(returnId!);
            if (shortage) {
              await expectLater(perform(), throwsStateError);
              expect(await snapshot(), before);
            } else {
              await perform();
              expect(
                (await db.select(db.businessWarehouseStocks).getSingle())
                    .quantity,
                action == 'void' ? 20 : 21,
              );
            }
          },
        );
      }
    }
  }

  for (final method in ['wac', 'fifo']) {
    for (final corruptSource in [false, true]) {
      test(
        '$method void isolates foreign batches corrupt=$corruptSource',
        () async {
          await seed(method, false);
          addTearDown(db.close);
          await db.purchaseDao.postPurchase(purchase);
          final local = await BusinessFoundationRepository(db).getScope();
          final other = const Uuid().v4();
          await db
              .into(db.businessWarehouses)
              .insert(
                BusinessWarehousesCompanion.insert(
                  id: other,
                  organizationId: local.organizationId,
                  branchId: local.branchId,
                  code: 'BATCH-OTHER',
                ),
              );
          final batch = await insert('product_batches', {
            'product_id': product,
            'variant_id': variant,
            'warehouse_id': other,
            'batch_number': 'OTHER-OPENING',
            'source': 'opening',
            'received_quantity': 7,
            'remaining_quantity': 7,
            'unit_cost_cents': 321,
          });
          if (corruptSource) {
            final item = (await db.purchaseDao.getPurchaseItems(
              purchase,
            )).single;
            // Simulate a damaged imported/source reference without changing its
            // immutable warehouse. Normal batch creation rejects this linkage.
            await db.customStatement(
              'UPDATE product_batches SET purchase_item_id = ? WHERE id = ?',
              [item.id, batch],
            );
          }
          final foreignBefore =
              (await db
                      .customSelect(
                        'SELECT * FROM product_batches WHERE id = ?',
                        variables: [Variable.withInt(batch)],
                      )
                      .getSingle())
                  .data;
          final before = await snapshot();
          if (corruptSource) {
            await expectLater(
              db.purchaseDao.voidPurchase(purchase),
              throwsStateError,
            );
            expect(await snapshot(), before);
          } else {
            await db.purchaseDao.voidPurchase(purchase);
            expect(
              (await db.purchaseDao.getPurchaseById(purchase))!.status,
              'voided',
            );
          }
          expect(
            (await db
                    .customSelect(
                      'SELECT * FROM product_batches WHERE id = ?',
                      variables: [Variable.withInt(batch)],
                    )
                    .getSingle())
                .data,
            foreignBefore,
          );
        },
      );
    }
  }

  for (final corrupt in [false, true]) {
    test(
      'legacy FIFO return valuation checks batch ownership corrupt=$corrupt',
      () async {
        await seed('fifo', false);
        addTearDown(db.close);
        await db.purchaseDao.postPurchase(purchase);
        final header = (await db.purchaseDao.getPurchaseById(purchase))!;
        final item = (await db.purchaseDao.getPurchaseItems(purchase)).single;
        final id = await insert('purchase_returns', {
          'purchase_id': purchase,
          'return_number': 'RETURN-VALUATION',
          'currency_id': header.currencyId,
          'total_cents': 900,
          'status': 'draft',
        });
        final line = await insert('purchase_return_items', {
          'return_id': id,
          'purchase_item_id': item.id,
          'quantity': 1,
          'refund_cents': 900,
        });
        await db.purchaseDao.postPurchaseReturn(id);
        expect(
          await db.purchaseDao.computePurchaseReturnInventoryCostCents(id),
          500,
        );
        await db.customStatement(
          'UPDATE purchase_return_items SET inventory_value_at_post_cents = NULL WHERE id = ?',
          [line],
        );
        if (corrupt) {
          final local = await BusinessFoundationRepository(db).getScope();
          final other = const Uuid().v4();
          await db
              .into(db.businessWarehouses)
              .insert(
                BusinessWarehousesCompanion.insert(
                  id: other,
                  organizationId: local.organizationId,
                  branchId: local.branchId,
                  code: 'COST-OTHER',
                ),
              );
          final batch = await insert('product_batches', {
            'product_id': product,
            'variant_id': variant,
            'warehouse_id': other,
            'batch_number': 'COST-OTHER',
            'source': 'opening',
            'received_quantity': 7,
            'remaining_quantity': 7,
            'unit_cost_cents': 321,
          });
          await db.customStatement(
            'UPDATE batch_consumptions SET batch_id = ? WHERE purchase_return_item_id = ?',
            [batch, line],
          );
          final before = await snapshot();
          await expectLater(
            db.purchaseDao.computePurchaseReturnInventoryCostCents(id),
            throwsStateError,
          );
          expect(await snapshot(), before);
        } else {
          await (db.update(db.businessWarehouses)
                ..where((w) => w.id.equals(warehouse)))
              .write(const BusinessWarehousesCompanion(isActive: Value(false)));
          expect(
            await db.purchaseDao.computePurchaseReturnInventoryCostCents(id),
            500,
          );
        }
      },
    );
  }

  for (final scenario in [
    'frozen-wac',
    'frozen-fifo',
    'legacy-simple',
    'legacy-variant',
  ]) {
    test(
      'historical return cost is isolated from live mirrors: $scenario',
      () async {
        await seed(scenario == 'frozen-fifo' ? 'fifo' : 'wac', false);
        addTearDown(db.close);
        if (scenario == 'legacy-variant') {
          await db.customStatement(
            'UPDATE purchase_items SET variant_id = ? WHERE purchase_id = ?',
            [variant, purchase],
          );
        }
        await db.purchaseDao.postPurchase(purchase);
        final header = (await db.purchaseDao.getPurchaseById(purchase))!;
        final item = (await db.purchaseDao.getPurchaseItems(purchase)).single;
        final id = await insert('purchase_returns', {
          'purchase_id': purchase,
          'return_number': 'RETURN-HISTORICAL',
          'currency_id': header.currencyId,
          'total_cents': 900,
          'status': 'draft',
        });
        final line = await insert('purchase_return_items', {
          'return_id': id,
          'purchase_item_id': item.id,
          'quantity': 1,
          'refund_cents': 900,
        });
        await db.purchaseDao.postPurchaseReturn(id);
        final expected = scenario == 'frozen-fifo' ? 500 : 536;
        expect(
          await db.purchaseDao.computePurchaseReturnInventoryCostCents(id),
          expected,
        );
        if (scenario.startsWith('frozen')) {
          await db.customStatement(
            'UPDATE products SET track_inventory = 0 WHERE id = ?',
            [product],
          );
        } else {
          await db.customStatement(
            'UPDATE purchase_return_items SET inventory_value_at_post_cents = NULL, unit_cost_at_post_cents = NULL WHERE id = ?',
            [line],
          );
          await db.customStatement(
            'DROP TRIGGER business_stock_variant_update',
          );
          await db.customStatement(
            'UPDATE product_variants SET cost_cents = 9999 WHERE id = ?',
            [variant],
          );
          await db.customStatement(
            'UPDATE products SET cost_cents = 9999 WHERE id = ?',
            [product],
          );
        }
        await (db.update(db.businessWarehouses)
              ..where((w) => w.id.equals(warehouse)))
            .write(const BusinessWarehousesCompanion(isActive: Value(false)));
        final before = await snapshot();
        expect(
          await db.purchaseDao.computePurchaseReturnInventoryCostCents(id),
          expected,
        );
        expect(await snapshot(), before);
      },
    );
  }

  for (final method in ['wac', 'fifo']) {
    for (final change in ['tracking', 'method']) {
      test(
        'legacy $method return preserves posting evidence after $change change',
        () async {
          await seed(method, false);
          addTearDown(db.close);
          await db.purchaseDao.postPurchase(purchase);
          final header = (await db.purchaseDao.getPurchaseById(purchase))!;
          final item = (await db.purchaseDao.getPurchaseItems(purchase)).single;
          final id = await insert('purchase_returns', {
            'purchase_id': purchase,
            'return_number': 'RETURN-LEGACY-EVIDENCE',
            'currency_id': header.currencyId,
            'total_cents': 900,
            'status': 'draft',
          });
          final line = await insert('purchase_return_items', {
            'return_id': id,
            'purchase_item_id': item.id,
            'quantity': 1,
            'refund_cents': 900,
          });
          await db.purchaseDao.postPurchaseReturn(id);
          await db.customStatement(
            'UPDATE purchase_return_items SET inventory_value_at_post_cents = NULL WHERE id = ?',
            [line],
          );
          if (change == 'tracking') {
            await db.customStatement(
              'UPDATE products SET track_inventory = 0 WHERE id = ?',
              [product],
            );
          } else {
            // Model restored legacy configuration; not a UI costing-method change.
            await db.customStatement(
              'UPDATE products SET costing_method = ? WHERE id = ?',
              [method == 'fifo' ? 'wac' : 'fifo', product],
            );
          }
          final before = await snapshot();
          expect(
            await db.purchaseDao.computePurchaseReturnInventoryCostCents(id),
            method == 'fifo' ? 500 : 536,
          );
          expect(await snapshot(), before);
        },
      );
    }
  }

  for (final method in ['wac', 'fifo']) {
    for (final explicitVariant in [false, true]) {
      test(
        'secondary purchase-return-void cycle $method explicit=$explicitVariant',
        () async {
          await seed(method, false);
          addTearDown(db.close);
          final primaryProduct = (await db.select(db.products).getSingle())
              .toJson();
          final primaryVariant =
              (await db.select(db.productVariants).getSingle()).toJson();
          final local = await BusinessFoundationRepository(db).getScope();
          final other = const Uuid().v4();
          await db
              .into(db.businessWarehouses)
              .insert(
                BusinessWarehousesCompanion.insert(
                  id: other,
                  organizationId: local.organizationId,
                  branchId: local.branchId,
                  code: 'CYCLE',
                ),
              );
          await db
              .into(db.businessWarehouseStocks)
              .insert(
                BusinessWarehouseStocksCompanion.insert(
                  warehouseId: other,
                  variantId: variant,
                  quantity: const Value(0),
                  unitCostCents: const Value(321),
                ),
              );
          await BranchCurrencyPolicyStore(db).bind('USD');
          final scope = await WarehouseOperationScope.resolve(
            db,
            warehouseId: other,
          );
          final draft = (await db.purchaseDao.getPurchaseById(purchase))!;
          final line = (await db.purchaseDao.getPurchaseItems(purchase)).single;
          final id = await db.purchaseDao.createPurchase(
            draft
                .toCompanion(true)
                .copyWith(
                  id: const Value.absent(),
                  purchaseNumber: const Value('SECONDARY'),
                ),
            [
              line
                  .toCompanion(true)
                  .copyWith(
                    id: const Value.absent(),
                    variantId: Value(explicitVariant ? variant : null),
                  ),
            ],
            scope: scope,
          );
          await expectLater(db.purchaseDao.postPurchase(id), throwsStateError);
          final journal = JournalEntryService(AccountingRepository(db));
          Future<void> expectInventory(int expected) async {
            final row = await db
                .customSelect(
                  "SELECT COALESCE(SUM(l.debit_cents-l.credit_cents),0) AS value FROM journal_entry_lines l JOIN journal_entries j ON j.id=l.journal_entry_id JOIN accounts a ON a.id=l.account_id JOIN business_document_locations d ON d.source_table='journal_entries' AND d.source_id=j.id WHERE j.status='posted' AND a.account_code='1200' AND d.warehouse_id=?",
                  variables: [Variable.withString(other)],
                )
                .getSingle();
            expect(row.read<int>('value'), expected);
          }

          await db.transaction(() async {
            await db.purchaseDao.postPurchase(id, scope: scope);
            await journal.recordPurchaseJournalEntry(
              purchaseId: id,
              totalCents: 1800,
              paidAmountCents: 0,
              currencyId: draft.currencyId,
              inventoryNetCents: 1800,
            );
          });
          Future<int> qty() async => (await (db.select(
            db.businessWarehouseStocks,
          )..where((s) => s.warehouseId.equals(other))).getSingle()).quantity;
          expect(await qty(), 2);
          await expectInventory(1800);
          final sale = await db.saleDao.createSaleWithItems(
            SalesCompanion.insert(
              invoiceNumber: 'SECONDARY-SALE',
              subtotalCents: Decimal.fromInt(2000),
              discountCents: Value(Decimal.fromInt(200)),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(1800),
              currencyId: draft.currencyId,
              paymentMethod: 'cash',
              status: const Value('draft'),
            ),
            [
              SaleItemsCompanion.insert(
                saleId: 0,
                productId: product,
                variantId: Value(explicitVariant ? variant : null),
                quantity: 1,
                unitPriceCents: Decimal.fromInt(2000),
                subtotalCents: Decimal.fromInt(2000),
                discountCents: Value(Decimal.fromInt(200)),
                taxCents: Value(Decimal.zero),
                totalCents: Decimal.fromInt(1800),
              ),
            ],
            scope: scope,
          );
          await expectLater(db.saleDao.postSale(sale), throwsStateError);
          await db.transaction(() async {
            await db.saleDao.postSale(sale, scope: scope);
            await journal.recordSaleJournalEntry(
              saleId: sale,
              totalCents: 1800,
              paidAmountCents: 1800,
              currencyId: draft.currencyId,
            );
            await journal.recordSaleCOGSJournalEntry(
              saleId: sale,
              costCents: await db.saleDao.computeSaleCostCents(sale),
              currencyId: draft.currencyId,
            );
          });
          expect(await qty(), 1);
          await expectInventory(900);
          final saleLine = (await db.saleDao.getSaleItems(sale)).single;
          final saleReturn = await insert('sale_returns', {
            'sale_id': sale,
            'return_number': 'SECONDARY-SR',
            'total_cents': 1800,
            'currency_id': draft.currencyId,
            'status': 'draft',
          });
          await insert('sale_return_items', {
            'return_id': saleReturn,
            'sale_item_id': saleLine.id,
            'quantity': 1,
            'refund_cents': 1800,
          });
          await db.transaction(() async {
            await db.saleDao.postSaleReturn(saleReturn, scope: scope);
            await journal.recordSaleReturnJournalEntry(
              returnId: saleReturn,
              totalCents: 1800,
              currencyId: draft.currencyId,
            );
            await journal.recordSaleReturnCOGSReversalJournalEntry(
              returnId: saleReturn,
              costCents: await db.saleDao.computeSaleReturnCostCents(
                saleReturn,
              ),
              currencyId: draft.currencyId,
            );
          });
          expect(await qty(), 2);
          await expectInventory(1800);
          await db.transaction(() async {
            await journal.voidJournalEntriesForSource(
              sourceTable: 'sale_returns',
              sourceId: saleReturn,
              reason: 'Cycle',
            );
            await db.saleDao.voidSaleReturn(saleReturn, scope: scope);
          });
          expect(await qty(), 1);
          await expectInventory(900);
          await db.transaction(() async {
            await journal.voidJournalEntriesForSource(
              sourceTable: 'sales',
              sourceId: sale,
              reason: 'Cycle',
            );
            await db.saleDao.voidSale(
              sale,
              scope: scope,
              journalEntryService: journal,
            );
          });
          expect(await qty(), 2);
          await expectInventory(1800);
          final item = (await db.purchaseDao.getPurchaseItems(id)).single;
          final ret = await insert('purchase_returns', {
            'purchase_id': id,
            'return_number': 'SECONDARY-RETURN',
            'currency_id': draft.currencyId,
            'total_cents': 900,
            'status': 'draft',
            'refund_method': 'credit',
          });
          await insert('purchase_return_items', {
            'return_id': ret,
            'purchase_item_id': item.id,
            'quantity': 1,
            'refund_cents': 900,
          });
          await db.transaction(() async {
            await db.purchaseDao.postPurchaseReturn(ret, scope: scope);
            await journal.recordPurchaseReturnJournalEntry(
              returnId: ret,
              totalCents: 900,
              currencyId: draft.currencyId,
              inventoryCostCents: await db.purchaseDao
                  .computePurchaseReturnInventoryCostCents(ret),
              refundMethod: 'credit',
            );
          });
          expect(await qty(), 1);
          await expectInventory(900);
          await db.transaction(() async {
            await journal.voidJournalEntriesForSource(
              sourceTable: 'purchase_returns',
              sourceId: ret,
              reason: 'Cycle',
            );
            await db.purchaseDao.voidPurchaseReturn(ret, scope: scope);
          });
          expect(await qty(), 2);
          await expectInventory(1800);
          final adjustments = AdjustmentReturnDao(db);
          final purchaseAdjustment = await adjustments
              .createAndPostPurchaseAdjReturn(
                PurchaseReturnAdjustmentsCompanion.insert(
                  returnNumber: 'SCOPED-PA',
                  supplierId: draft.supplierId,
                  currencyId: draft.currencyId,
                  totalCents: Decimal.fromInt(900),
                  refundMethod: const Value('credit'),
                ),
                [
                  PurchaseReturnAdjustmentItemsCompanion.insert(
                    returnId: 0,
                    productId: product,
                    variantId: Value(explicitVariant ? variant : null),
                    quantity: 1,
                    unitPriceCents: Decimal.fromInt(900),
                    totalCents: Decimal.fromInt(900),
                  ),
                ],
                journalEntryService: journal,
                scope: scope,
              );
          expect(await qty(), 1);
          await expectInventory(900);
          expect(
            (await db.purchaseDao.getPurchaseItems(
              id,
            )).single.qtyReturnedAdjustment,
            1,
          );
          expect(
            (await db.purchaseDao.getPurchaseItems(
              purchase,
            )).single.qtyReturnedAdjustment,
            0,
          );
          await adjustments.voidPurchaseAdjReturn(
            purchaseAdjustment,
            journalEntryService: journal,
            scope: scope,
          );
          expect(await qty(), 2);
          await expectInventory(1800);
          expect(
            (await db.purchaseDao.getPurchaseItems(
              id,
            )).single.qtyReturnedAdjustment,
            0,
          );

          final adjustmentCost = method == 'fifo' ? 1200 : 900;
          if (method == 'fifo') {
            await db.customStatement(
              'UPDATE business_warehouse_stocks SET unit_cost_cents=1200 WHERE warehouse_id=?',
              [other],
            );
          }
          final saleAdjustment = await adjustments.createAndPostSaleAdjReturn(
            SaleReturnAdjustmentsCompanion.insert(
              returnNumber: 'SCOPED-SA',
              currencyId: draft.currencyId,
              totalCents: Decimal.fromInt(1500),
              refundMethod: const Value('cash'),
            ),
            [
              SaleReturnAdjustmentItemsCompanion.insert(
                sourceResolution: const Value('unverified'),
                sourceResolutionReason: const Value('test fixture'),
                returnId: 0,
                productId: product,
                variantId: Value(explicitVariant ? variant : null),
                quantity: 1,
                unitPriceCents: Decimal.fromInt(1500),
                totalCents: Decimal.fromInt(1500),
              ),
            ],
            journalEntryService: journal,
            scope: scope,
          );
          expect(await qty(), 3);
          await expectInventory(1800 + adjustmentCost);
          final adjustmentItem = (await adjustments.getSaleAdjReturnItems(
            saleAdjustment,
          )).single;
          await adjustments.voidSaleAdjReturn(
            saleAdjustment,
            journalEntryService: journal,
            scope: scope,
          );
          expect(await qty(), 2);
          await expectInventory(1800);
          if (method == 'fifo') {
            expect(adjustmentItem.returnBatchId, isNotNull);
            final returnedBatch =
                await (db.select(
                      db.productBatches,
                    )..where((b) => b.id.equals(adjustmentItem.returnBatchId!)))
                    .getSingle();
            expect(returnedBatch.remainingQuantity, 0);
            final purchasedBatches = await (db.select(
              db.productBatches,
            )..where((b) => b.purchaseItemId.equals(item.id))).get();
            expect(purchasedBatches.single.remainingQuantity, 2);
          }
          await db.transaction(() async {
            await journal.voidJournalEntriesForSource(
              sourceTable: 'purchases',
              sourceId: id,
              reason: 'Cycle',
            );
            await db.purchaseDao.voidPurchase(
              id,
              scope: scope,
              journalEntryService: journal,
            );
          });
          expect(await qty(), 0);
          await expectInventory(0);
          expect(
            (await db.select(db.products).getSingle()).toJson(),
            primaryProduct,
          );
          expect(
            (await db.select(db.productVariants).getSingle()).toJson(),
            primaryVariant,
          );
          final entries = await db
              .customSelect(
                "SELECT j.total_debit_cents, j.total_credit_cents, l.warehouse_id FROM journal_entries j JOIN business_document_locations l ON l.source_table = 'journal_entries' AND l.source_id = j.id",
              )
              .get();
          expect(entries, isNotEmpty);
          for (final entry in entries) {
            expect(entry.read<String>('warehouse_id'), other);
            expect(
              entry.read<int>('total_debit_cents'),
              entry.read<int>('total_credit_cents'),
            );
          }
        },
      );
    }
  }

  test('pending purchase still posts normally', () async {
    await seed('wac', false);
    addTearDown(db.close);
    await db.purchaseDao.updatePurchaseStatus(purchase, 'pending');
    await db.purchaseDao.postPurchase(purchase);
    expect((await db.purchaseDao.getPurchaseById(purchase))!.status, 'posted');
    expect(
      (await db.select(db.businessWarehouseStocks).getSingle()).quantity,
      22,
    );
  });

  for (final method in ['wac', 'fifo', 'last']) {
    for (final optionalSize in [false, true]) {
      test(
        '$method optionalSize=$optionalSize writes warehouse cost and supports void',
        () async {
          await seed(method, optionalSize);
          addTearDown(db.close);
          // Removing the legacy-to-warehouse cost mirror proves posting writes
          // the authoritative balance itself, not just its compatibility row.
          await db.customStatement(
            'DROP TRIGGER business_stock_variant_update',
          );
          final scope = await BusinessFoundationRepository(db).getScope();
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
                  quantity: const Value(7),
                  unitCostCents: const Value(321),
                ),
              );
          await db.purchaseDao.postPurchase(purchase);
          final stock =
              await (db.select(db.businessWarehouseStocks)..where(
                    (s) =>
                        s.warehouseId.equals(warehouse) &
                        s.variantId.equals(variant),
                  ))
                  .getSingle();
          expect(stock.quantity, 22);
          expect(stock.unitCostCents, method == 'wac' ? 536 : 900);
          final row = await (db.select(
            db.productVariants,
          )..where((v) => v.id.equals(variant))).getSingle();
          expect(row.costCents.toBigInt().toInt(), stock.unitCostCents);
          expect(row.previousCostCents!.toBigInt().toInt(), 500);
          expect(row.lastPurchasePriceCents!.toBigInt().toInt(), 1000);
          final remote = await (db.select(
            db.businessWarehouseStocks,
          )..where((s) => s.warehouseId.equals(other))).getSingle();
          expect(remote.quantity, 7);
          expect(remote.unitCostCents, 321);
          await db.purchaseDao.voidPurchase(purchase);
          final after =
              await (db.select(db.businessWarehouseStocks)..where(
                    (s) =>
                        s.warehouseId.equals(warehouse) &
                        s.variantId.equals(variant),
                  ))
                  .getSingle();
          expect(after.quantity, 20);
          final header = await db.purchaseDao.getPurchaseById(purchase);
          expect(header!.discountCents.toBigInt().toInt(), 200);
          expect(header.totalCents.toBigInt().toInt(), 1800);
        },
      );
    }
  }

  test(
    'warehouse cost write failure rolls back complete purchase posting',
    () async {
      await seed('wac', true);
      addTearDown(db.close);
      final before = await snapshot();
      await db.customStatement(
        "CREATE TRIGGER reject_cost BEFORE UPDATE OF unit_cost_cents ON business_warehouse_stocks BEGIN SELECT RAISE(ABORT, 'injected cost failure'); END",
      );
      await expectLater(
        db.purchaseDao.postPurchase(purchase),
        throwsA(anything),
      );
      expect(await snapshot(), before);
    },
  );

  test(
    'ambiguous simple FIFO variant refuses posting without partial writes',
    () async {
      await seed('fifo', true);
      addTearDown(db.close);
      await insert('product_variants', {
        'product_id': product,
        'cost_cents': 500,
        'price_cents': 1200,
      });
      final before = await snapshot();
      await expectLater(
        db.purchaseDao.postPurchase(purchase),
        throwsStateError,
      );
      expect(await snapshot(), before);
    },
  );
}
