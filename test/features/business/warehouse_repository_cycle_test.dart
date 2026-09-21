import 'package:tapix/features/reports/presentation/bloc/supplier_sales_report_bloc.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/business/branch_currency_policy_store.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/loyalty/loyalty_points_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/customers/data/repositories/loyalty_repository_impl.dart';
import 'package:tapix/features/purchases/data/datasources/purchase_local_datasource.dart';
import 'package:tapix/features/purchases/data/repositories/purchase_repository_impl.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:tapix/features/sales/data/datasources/sale_local_datasource.dart';
import 'package:tapix/features/sales/data/repositories/sale_repository_impl.dart';
import 'package:tapix/features/sales/domain/repositories/sale_repository.dart';
import 'business_foundation_test.dart' as fixtures;

class _Session extends Fake implements SessionService {
  @override
  Future<int?> getCurrentUserId() async => null;
}

void main() {
  for (final method in ['wac', 'fifo']) {
    for (final measured in [false, true]) {
      for (final multi in [false, true]) {
        test(
          'repository cycle $method measured=$measured multi=$multi isolates stock and GL',
          () async {
            final db = fixtures.memoryDb();
            addTearDown(db.close);
            final local = await WarehouseOperationScope.resolve(db);
            await BranchCurrencyPolicyStore(db).bind('USD');
            final currency = (await (db.select(
              db.currencies,
            )..where((c) => c.code.equals('USD'))).getSingle()).id;
            final supplier = await db
                .into(db.suppliers)
                .insert(
                  SuppliersCompanion.insert(
                    name: 'Supplier',
                    currencyId: currency,
                  ),
                );
            final customer = await db
                .into(db.customers)
                .insert(
                  CustomersCompanion.insert(
                    name: 'Customer',
                    currencyId: currency,
                  ),
                );
            final product = await db
                .into(db.products)
                .insert(
                  ProductsCompanion.insert(
                    name: 'Product',
                    currencyId: Value(currency),
                    costingMethod: Value(method),
                    hasVariants: Value(multi),
                    measurementType: Value(measured ? 'weight' : 'piece'),
                    costCents: Decimal.fromInt(500),
                    priceCents: Decimal.fromInt(2000),
                  ),
                );
            final variant = await db
                .into(db.productVariants)
                .insert(
                  ProductVariantsCompanion.insert(
                    productId: product,
                    costCents: Decimal.fromInt(500),
                    priceCents: Decimal.fromInt(2000),
                  ),
                );
            if (multi) {
              final size = await db
                  .into(db.sizes)
                  .insert(SizesCompanion.insert(name: 'Large'));
              await db
                  .into(db.productVariants)
                  .insert(
                    ProductVariantsCompanion.insert(
                      productId: product,
                      sizeId: Value(size),
                      costCents: Decimal.fromInt(111),
                      priceCents: Decimal.fromInt(500),
                    ),
                  );
            }
            const other = '66666666-6666-4666-8666-666666666666';
            await db
                .into(db.businessWarehouses)
                .insert(
                  BusinessWarehousesCompanion.insert(
                    id: other,
                    organizationId: local.organizationId,
                    branchId: local.branchId,
                    code: 'REPO',
                  ),
                );
            await db
                .into(db.businessWarehouseStocks)
                .insert(
                  BusinessWarehouseStocksCompanion.insert(
                    warehouseId: other,
                    variantId: variant,
                    unitCostCents: const Value(500),
                  ),
                );
            final scope = await WarehouseOperationScope.resolve(
              db,
              warehouseId: other,
            );
            final journal = JournalEntryService(AccountingRepository(db));
            final adjustments = AdjustmentReturnDao(db);
            final loyalty = LoyaltyRepositoryImpl(db, journal);
            SaleRepositoryImpl sales(WarehouseOperationScope? selected) =>
                SaleRepositoryImpl(
                  SaleLocalDatasourceImpl(db.saleDao, adjustments),
                  db.saleDao,
                  journal,
                  AuditLogService(db),
                  _Session(),
                  loyalty,
                  CommissionService(db.employeeDao),
                  LoyaltyPointsService(loyalty, journal, db),
                  warehouseScope: selected,
                );
            final salesRepo = sales(scope);
            final purchases = PurchaseRepositoryImpl(
              PurchaseLocalDatasourceImpl(db.purchaseDao, adjustments),
              AuditLogService(db),
              _Session(),
              journal,
              db,
              warehouseScope: scope,
            );
            final scale = measured ? 1000 : 1;
            final unit = measured ? 'weight' : 'piece';
            final soldUnits = measured ? 0.5 : 1;
            final saleQuantity = measured ? 500 : 1;
            final saleCost = measured ? 450 : 900;
            final primaryBefore = (await db.select(db.productVariants).get())
                .map((v) => v.toJson())
                .toList();
            Future<void> expectLoyalty(int points) async {
              expect(
                (await db.customerDao.getCustomer(
                  customer,
                ))!.loyaltyPointsBalance,
                points,
              );
              final row = await db
                  .customSelect(
                    "SELECT COALESCE(SUM(l.credit_cents-l.debit_cents),0) AS value FROM journal_entry_lines l JOIN journal_entries j ON j.id=l.journal_entry_id JOIN accounts a ON a.id=l.account_id JOIN business_document_locations d ON d.source_table='journal_entries' AND d.source_id=j.id WHERE j.status='posted' AND a.account_code='2300' AND d.warehouse_id=?",
                    variables: [Variable.withString(other)],
                  )
                  .getSingle();
              expect(row.read<int>('value'), points);
            }

            Future<void> expectValue(num qty, int cents) async {
              final stock = await (db.select(
                db.businessWarehouseStocks,
              )..where((s) => s.warehouseId.equals(other))).getSingle();
              expect(stock.quantity, qty * scale);
              final value = await db
                  .customSelect(
                    "SELECT COALESCE(SUM(l.debit_cents-l.credit_cents),0) AS value FROM journal_entry_lines l JOIN journal_entries j ON j.id=l.journal_entry_id JOIN accounts a ON a.id=l.account_id JOIN business_document_locations d ON d.source_table='journal_entries' AND d.source_id=j.id WHERE j.status='posted' AND a.account_code='1200' AND d.warehouse_id=?",
                    variables: [Variable.withString(other)],
                  )
                  .getSingle();
              expect(value.read<int>('value'), cents);
              expect(
                (await db.select(db.productVariants).get())
                    .map((v) => v.toJson())
                    .toList(),
                primaryBefore,
              );
            }

            final purchase = await purchases.createPurchase(
              supplierId: supplier,
              currencyId: currency,
              subtotalCents: Decimal.fromInt(3000),
              discountCents: Decimal.fromInt(300),
              taxCents: Decimal.fromInt(378),
              totalCents: Decimal.fromInt(3078),
              paidAmountCents: Decimal.fromInt(3078),
              paymentMethod: 'cash',
              items: [
                PurchaseItemInput(
                  productId: product,
                  variantId: variant,
                  quantity: 3 * scale,
                  quantityScale: scale,
                  measurementType: unit,
                  unitCostCents: Decimal.fromInt(1000),
                  subtotalCents: Decimal.fromInt(3000),
                  discountCents: Decimal.fromInt(300),
                  taxCents: Decimal.fromInt(378),
                  totalCents: Decimal.fromInt(3078),
                ),
              ],
            );
            final primaryPurchases = PurchaseRepositoryImpl(
              PurchaseLocalDatasourceImpl(db.purchaseDao, adjustments),
              AuditLogService(db),
              _Session(),
              journal,
              db,
            );
            final draftSnapshot = await fixtures.legacySnapshot(db);
            await expectLater(
              primaryPurchases.deletePurchase(purchase),
              throwsStateError,
            );
            await expectLater(
              primaryPurchases.updatePurchaseStatus(purchase, 'pending'),
              throwsStateError,
            );
            await expectLater(
              purchases.updatePurchaseStatus(purchase, 'posted'),
              throwsStateError,
            );
            await expectLater(
              primaryPurchases.updatePurchase(
                purchaseId: purchase,
                supplierId: supplier,
                currencyId: currency,
                subtotalCents: Decimal.zero,
                discountCents: Decimal.zero,
                taxCents: Decimal.zero,
                totalCents: Decimal.zero,
                paidAmountCents: Decimal.zero,
                items: [],
              ),
              throwsStateError,
            );
            expect(await fixtures.legacySnapshot(db), draftSnapshot);
            await purchases.postPurchase(purchase);
            await expectValue(3, 2700);
            final beforePurchaseReplacement = await fixtures.legacySnapshot(db);
            await db.customStatement(
              "CREATE TRIGGER reject_replacement_purchase BEFORE INSERT ON purchases BEGIN SELECT RAISE(ABORT, 'injected replacement failure'); END",
            );
            await expectLater(
              purchases.editPostedPurchase(
                originalPurchaseId: purchase,
                supplierId: supplier,
                currencyId: currency,
                subtotalCents: Decimal.fromInt(3078),
                discountCents: Decimal.zero,
                taxCents: Decimal.zero,
                totalCents: Decimal.fromInt(3078),
                paidAmountCents: Decimal.zero,
                items: [],
              ),
              throwsA(anything),
            );
            expect(
              await fixtures.legacySnapshot(db),
              beforePurchaseReplacement,
            );
            await db.customStatement(
              'DROP TRIGGER reject_replacement_purchase',
            );

            final draftItems = [
              SaleItemInput(
                lineId: 'draft-line',
                productId: product,
                variantId: variant,
                quantity: saleQuantity,
                quantityScale: scale,
                measurementType: unit,
                unitPriceCents: Decimal.fromInt(measured ? 4000 : 2000),
                subtotalCents: Decimal.fromInt(2000),
                discountCents: Decimal.fromInt(200),
                taxCents: Decimal.fromInt(252),
                totalCents: Decimal.fromInt(2052),
              ),
            ];
            final draft = await db.saleDao.createSaleWithItems(
              SalesCompanion(
                invoiceNumber: const Value('DRAFT-ACCEPTANCE'),
                customerId: Value(customer),
                currencyId: Value(currency),
                status: const Value('draft'),
                subtotalCents: Value(Decimal.fromInt(2000)),
                discountCents: Value(Decimal.fromInt(200)),
                taxCents: Value(Decimal.fromInt(252)),
                totalCents: Value(Decimal.fromInt(2052)),
                paidAmountCents: Value(Decimal.zero),
                paymentMethod: const Value('cash'),
              ),
              [
                SaleItemsCompanion(
                  productId: Value(product),
                  variantId: Value(variant),
                  quantity: Value(saleQuantity),
                  quantityScale: Value(scale),
                  measurementType: Value(unit),
                  unitPriceCents: Value(
                    Decimal.fromInt(measured ? 4000 : 2000),
                  ),
                  subtotalCents: Value(Decimal.fromInt(2000)),
                  discountCents: Value(Decimal.fromInt(200)),
                  taxCents: Value(Decimal.fromInt(252)),
                  totalCents: Value(Decimal.fromInt(2052)),
                ),
              ],
              scope: scope,
            );
            await salesRepo.updateSale(
              saleId: draft,
              customerId: customer,
              currencyId: currency,
              subtotalCents: Decimal.fromInt(2000),
              discountCents: Decimal.fromInt(200),
              taxCents: Decimal.fromInt(252),
              totalCents: Decimal.fromInt(2052),
              paidAmountCents: Decimal.zero,
              paymentMethod: 'cash',
              items: draftItems,
            );
            expect(
              await (db.select(db.journalEntries)..where(
                    (j) =>
                        j.sourceTable.equals('sales') &
                        j.sourceId.equals(draft),
                  ))
                  .get(),
              isEmpty,
            );
            await expectValue(3, 2700);
            await expectLater(
              salesRepo.recordPayment(
                saleId: draft,
                amountCents: Decimal.fromInt(100),
                currencyId: currency,
                paymentMethod: 'cash',
              ),
              throwsStateError,
            );
            final beforeDraftFailure = await fixtures.legacySnapshot(db);
            await db.customStatement(
              "CREATE TRIGGER reject_draft_post BEFORE INSERT ON journal_entries BEGIN SELECT RAISE(ABORT, 'injected draft journal failure'); END",
            );
            await expectLater(salesRepo.postSale(draft), throwsA(anything));
            expect(await fixtures.legacySnapshot(db), beforeDraftFailure);
            await expectValue(3, 2700);
            await db.customStatement('DROP TRIGGER reject_draft_post');
            await salesRepo.postSale(draft);
            await expectValue(3 - soldUnits, 2700 - saleCost);
            await expectLoyalty(20);
            await salesRepo.voidSale(draft);
            await expectValue(3, 2700);
            await expectLoyalty(0);
            Future<int> sell(SaleRepositoryImpl repo) => repo.createSale(
              customerId: customer,
              currencyId: currency,
              subtotalCents: Decimal.fromInt(2000),
              discountCents: Decimal.fromInt(200),
              taxCents: Decimal.fromInt(252),
              totalCents: Decimal.fromInt(2052),
              paidAmountCents: Decimal.zero,
              paymentMethod: 'cash',
              idempotencyKey: 'WAREHOUSE-RETRY',
              items: [
                SaleItemInput(
                  lineId: 'one',
                  productId: product,
                  variantId: variant,
                  quantity: saleQuantity,
                  quantityScale: scale,
                  measurementType: unit,
                  unitPriceCents: Decimal.fromInt(measured ? 4000 : 2000),
                  subtotalCents: Decimal.fromInt(2000),
                  discountCents: Decimal.fromInt(200),
                  taxCents: Decimal.fromInt(252),
                  totalCents: Decimal.fromInt(2052),
                ),
              ],
            );
            final sale = await sell(salesRepo);
            Future<void> expectSupplierReport(
              int net,
              int sold,
              int returned,
            ) async {
              final report = SupplierSalesReportBloc(
                db,
                warehouseScope: await scope.forReading(db),
              );
              try {
                final result = await report.load();
                expect(result.netByCurrency['USD'] ?? 0, net);
                if (sold > 0) {
                  final row = result.rows.single;
                  expect(row.supplierId, method == 'fifo' ? supplier : -1);
                  expect(row.soldQuantity, sold);
                  expect(row.returnedQuantity, returned);
                } else {
                  expect(result.rows, isEmpty);
                }
              } finally {
                await report.close();
              }
            }

            await expectSupplierReport(2052, saleQuantity, 0);
            final beforeReplacementFailure = await fixtures.legacySnapshot(db);
            await db.customStatement(
              "CREATE TRIGGER reject_replacement_sale BEFORE INSERT ON sales BEGIN SELECT RAISE(ABORT, 'injected replacement failure'); END",
            );
            await expectLater(
              salesRepo.editPostedSale(
                originalSaleId: sale,
                customerId: customer,
                currencyId: currency,
                subtotalCents: Decimal.fromInt(2052),
                discountCents: Decimal.zero,
                taxCents: Decimal.zero,
                totalCents: Decimal.fromInt(2052),
                paidAmountCents: Decimal.zero,
                paymentMethod: 'cash',
                items: [],
              ),
              throwsA(anything),
            );
            expect(await fixtures.legacySnapshot(db), beforeReplacementFailure);
            await db.customStatement('DROP TRIGGER reject_replacement_sale');
            final beforeRejectedEdits = await fixtures.legacySnapshot(db);
            await expectLater(sales(null).deleteSale(sale), throwsStateError);
            await expectLater(
              sales(null).updateSale(
                saleId: sale,
                currencyId: currency,
                subtotalCents: Decimal.zero,
                discountCents: Decimal.zero,
                taxCents: Decimal.zero,
                totalCents: Decimal.zero,
                paidAmountCents: Decimal.zero,
                paymentMethod: 'cash',
                items: [],
              ),
              throwsStateError,
            );
            // Reversals performed before the DAO rejects deleting a posted
            // document must also roll back, including commissions and journals.
            await expectLater(salesRepo.deleteSale(sale), throwsA(anything));
            await expectLater(
              purchases.deletePurchase(purchase),
              throwsA(anything),
            );
            expect(await fixtures.legacySnapshot(db), beforeRejectedEdits);
            await expectLoyalty(20);
            final payment = await salesRepo.recordPayment(
              saleId: sale,
              currencyId: currency,
              amountCents: Decimal.fromInt(2052),
              paymentMethod: 'cash',
            );
            expect(await sales(null).getSaleById(sale), null);
            expect(await sales(null).getSaleItems(sale), isEmpty);
            expect(await sales(null).getSalePayments(sale), isEmpty);
            expect(await sales(null).watchAllSales().first, isEmpty);
            expect(
              (await salesRepo.watchAllSales().first)
                  .where((s) => s.status == 'completed')
                  .single
                  .id,
              sale,
            );
            await expectLater(
              sales(null).deletePayment(payment),
              throwsStateError,
            );
            await db.customStatement(
              "CREATE TRIGGER reject_payment_delete BEFORE DELETE ON sale_payments BEGIN SELECT RAISE(ABORT, 'injected delete failure'); END",
            );
            final beforePaymentDelete = await fixtures.legacySnapshot(db);
            await expectLater(
              salesRepo.deletePayment(payment),
              throwsA(anything),
            );
            expect(await fixtures.legacySnapshot(db), beforePaymentDelete);
            await db.customStatement('DROP TRIGGER reject_payment_delete');
            await salesRepo.deletePayment(payment);
            await salesRepo.recordPayment(
              saleId: sale,
              currencyId: currency,
              amountCents: Decimal.fromInt(2052),
              paymentMethod: 'cash',
            );

            await expectValue(3 - soldUnits, 2700 - saleCost);
            expect(await sell(salesRepo), sale);
            await expectLater(sell(sales(null)), throwsStateError);
            await expectValue(3 - soldUnits, 2700 - saleCost);
            final soldLine = (await db.saleDao.getSaleItems(sale)).single;
            Future<int> returnSale() => salesRepo.createSaleReturn(
              saleId: sale,
              currencyId: currency,
              subtotalCents: Decimal.fromInt(2000),
              discountCents: Decimal.fromInt(200),
              taxCents: Decimal.fromInt(252),
              totalCents: Decimal.fromInt(2052),
              refundMethod: 'cash',
              items: [
                SaleReturnItemInput(
                  saleItemId: soldLine.id,
                  quantity: saleQuantity,
                  quantityScale: scale,
                  measurementType: unit,
                  subtotalCents: Decimal.fromInt(2000),
                  discountCents: Decimal.fromInt(200),
                  taxCents: Decimal.fromInt(252),
                  refundCents: Decimal.fromInt(2052),
                ),
              ],
            );
            await db.customStatement(
              'UPDATE loyalty_settings SET points_per_currency_unit=50, point_value_cents=9',
            );
            await db.customStatement(
              "CREATE TRIGGER reject_return_loyalty BEFORE INSERT ON journal_entries WHEN NEW.entry_type='loyalty_return' BEGIN SELECT RAISE(ABORT, 'injected loyalty failure'); END",
            );
            final beforeLoyaltyFailure = await fixtures.legacySnapshot(db);
            await expectLater(returnSale(), throwsA(anything));
            expect(await fixtures.legacySnapshot(db), beforeLoyaltyFailure);
            await db.customStatement('DROP TRIGGER reject_return_loyalty');
            final saleReturn = await returnSale();
            await expectSupplierReport(0, saleQuantity, saleQuantity);
            await expectLoyalty(0);
            await expectValue(3, 2700);
            final selectedStats = await salesRepo.watchDashboardStats().first;
            expect(selectedStats.totalSalesCents, 2052);
            expect(selectedStats.totalReturnsCents, 2052);
            expect(
              (await sales(null).watchDashboardStats().first).totalCount,
              0,
            );
            expect(
              (await purchases.watchDashboardStats().first).postedCount,
              1,
            );
            expect(
              (await primaryPurchases.watchDashboardStats().first).postedCount,
              0,
            );
            expect(await sales(null).getSaleReturnById(saleReturn), null);
            expect(await sales(null).watchSaleIdsWithReturns().first, isEmpty);
            expect(
              await sales(null).watchSaleProductSearchTerms().first,
              isEmpty,
            );
            expect(
              await sales(null).watchSaleReturnProductSearchTerms().first,
              isEmpty,
            );
            expect(await salesRepo.watchSaleIdsWithReturns().first, {sale});
            expect(await sales(null).getReturnedQuantity(soldLine.id), 0);
            expect(
              (await salesRepo.getLinkedReturnHistory(soldLine.id)).quantity,
              saleQuantity,
            );
            await salesRepo.voidSaleReturn(saleReturn);
            expect(
              (await salesRepo.watchDashboardStats().first).totalReturnsCents,
              0,
            );
            await expectLoyalty(20);
            await expectValue(3 - soldUnits, 2700 - saleCost);
            await salesRepo.voidSale(sale);
            await expectLoyalty(0);
            await expectValue(3, 2700);
            final boughtLine = (await db.purchaseDao.getPurchaseItems(
              purchase,
            )).single;
            final purchaseReturn = await purchases.createPurchaseReturn(
              purchaseId: purchase,
              currencyId: currency,
              subtotalCents: Decimal.fromInt(1000),
              discountCents: Decimal.fromInt(100),
              taxCents: Decimal.fromInt(126),
              totalCents: Decimal.fromInt(1026),
              refundMethod: 'cash',
              items: [
                PurchaseReturnItemInput(
                  purchaseItemId: boughtLine.id,
                  quantity: scale,
                  quantityScale: scale,
                  measurementType: unit,
                  subtotalCents: Decimal.fromInt(1000),
                  discountCents: Decimal.fromInt(100),
                  taxCents: Decimal.fromInt(126),
                  refundCents: Decimal.fromInt(1026),
                ),
              ],
            );
            await expectValue(2, 1800);
            await purchases.voidPurchaseReturn(purchaseReturn);
            await expectValue(3, 2700);
            await purchases.voidPurchase(purchase);
            await expectValue(0, 0);
            await expectSupplierReport(0, 0, 0);
            final unbalanced = await db
                .customSelect(
                  'SELECT journal_entry_id FROM journal_entry_lines GROUP BY journal_entry_id HAVING SUM(debit_cents) != SUM(credit_cents)',
                )
                .get();
            expect(unbalanced, isEmpty);
            final residuals = await db
                .customSelect(
                  "SELECT l.account_id, l.currency_id, SUM(l.debit_cents-l.credit_cents) AS net FROM journal_entry_lines l JOIN journal_entries j ON j.id=l.journal_entry_id WHERE j.status='posted' GROUP BY l.account_id,l.currency_id HAVING SUM(l.debit_cents-l.credit_cents) != 0",
                )
                .get();
            expect(
              residuals.map((r) => r.data).toList(),
              isEmpty,
              reason:
                  'A completely voided cycle must leave no cash, AR, AP, tax, revenue, COGS or loyalty balance',
            );
            expect(
              (await db.customerDao.getCustomer(customer))!.balanceCents,
              Decimal.zero,
            );
            expect(
              (await (db.select(
                db.suppliers,
              )..where((s) => s.id.equals(supplier))).getSingle()).balanceCents,
              Decimal.zero,
            );
          },
        );
      }
    }
  }
}
