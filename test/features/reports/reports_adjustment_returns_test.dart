import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/reports/presentation/bloc/sales_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/purchase_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_sales_returns_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/inventory_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

/// Regression: every report that considers sales / purchases / their returns
/// must aggregate BOTH linked (invoice-based) returns AND adjustment (unlinked,
/// product-based) returns. This end-to-end suite posts one real sale, one real
/// purchase, and one linked + one adjustment return on each side, then asserts:
///   • Sales report net = gross − (linked + adjustment) sale returns.
///   • Purchase report net = gross − (linked + adjustment) purchase returns.
///   • Customer sales returns report counts both return flows.
///   • Product movement returned-qty includes adjustment returns.
void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late AdjustmentReturnDao adjDao;

  late int currencyId;
  late int customerId;
  late int supplierId;
  late int productId;
  late int variantId;

  Future<T> firstSuccess<T>(Stream<RealtimeState<T>> stream) async {
    final state =
        await stream.firstWhere((s) => s is RealtimeSuccess<T>)
            as RealtimeSuccess<T>;
    return state.data;
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    final accounting = AccountingRepository(db);
    journal = JournalEntryService(accounting);
    adjDao = AdjustmentReturnDao(db);

    await db.customSelect('SELECT 1').get(); // force seed

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT OR IGNORE INTO users (id, username, password_hash, role, '
      'is_active, created_at, updated_at) '
      "VALUES (0, 'system', 'no-pin', 'owner', 1, $now, $now)",
    );

    final usd = await (db.select(db.currencies)
          ..where((c) => c.code.equals('USD')))
        .getSingle();
    currencyId = usd.id;

    customerId = await db.into(db.customers).insert(
          CustomersCompanion.insert(
            name: 'Report Customer',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );
    supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            name: 'Report Supplier',
            currencyId: currencyId,
            balanceCents: Value(Decimal.zero),
          ),
        );

    productId = await db.into(db.products).insert(
          ProductsCompanion.insert(
            sku: const Value('RPT-1'),
            name: 'Report Product',
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
            currencyId: Value(currencyId),
            stockQuantity: const Value(0),
            hasVariants: const Value(true),
          ),
        );
    variantId = await db.into(db.productVariants).insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(0),
            costCents: Decimal.fromInt(1000),
            priceCents: Decimal.fromInt(2000),
          ),
        );

    // ── Purchase 20 @ 1000 = 20000 ──
    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-1',
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(20000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(20000),
            paidAmountCents: Value(Decimal.zero),
            currencyId: currencyId,
            status: const Value('draft'),
            paymentMethod: const Value('credit'),
          ),
        );
    await db.into(db.purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            purchaseId: purchaseId,
            productId: productId,
            variantId: Value(variantId),
            quantity: 20,
            unitCostCents: Decimal.fromInt(1000),
            subtotalCents: Decimal.fromInt(20000),
            totalCents: Decimal.fromInt(20000),
          ),
        );
    await db.purchaseDao.postPurchase(purchaseId);

    // ── Sale 10 @ 2000 = 20000 ──
    final saleId = await db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-1',
            customerId: Value(customerId),
            subtotalCents: Decimal.fromInt(20000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(20000),
            paidAmountCents: Value(Decimal.fromInt(20000)),
            currencyId: currencyId,
            paymentMethod: 'cash',
            status: const Value('draft'),
          ),
        );
    await db.into(db.saleItems).insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            variantId: Value(variantId),
            quantity: 10,
            unitPriceCents: Decimal.fromInt(2000),
            subtotalCents: Decimal.fromInt(20000),
            totalCents: Decimal.fromInt(20000),
          ),
        );
    await db.saleDao.postSale(saleId);

    final saleItem = await (db.select(db.saleItems)
          ..where((i) => i.saleId.equals(saleId)))
        .getSingle();
    final purchaseItem = await (db.select(db.purchaseItems)
          ..where((i) => i.purchaseId.equals(purchaseId)))
        .getSingle();

    // ── Linked sale return: qty 3 @ 2000 = 6000 ──
    final linkedSaleRet = await db.saleDao.createSaleReturn(
      SaleReturnsCompanion.insert(
        returnNumber: 'SR-1',
        saleId: saleId,
        subtotalCents: Value(Decimal.fromInt(6000)),
        totalCents: Decimal.fromInt(6000),
        currencyId: currencyId,
        refundMethod: const Value('cash'),
      ),
      [
        SaleReturnItemsCompanion.insert(
          returnId: 0,
          saleItemId: saleItem.id,
          quantity: 3,
          subtotalCents: Value(Decimal.fromInt(6000)),
          refundCents: Decimal.fromInt(6000),
        ),
      ],
    );
    await db.saleDao.postSaleReturn(linkedSaleRet);

    // ── Adjustment sale return: qty 2 @ 2000 = 4000 ──
    final saleAdjRet = await adjDao.createSaleAdjReturn(
      SaleReturnAdjustmentsCompanion.insert(
        returnNumber: 'SAR-1',
        customerId: Value(customerId),
        currencyId: currencyId,
        totalCents: Decimal.fromInt(4000),
        refundMethod: const Value('cash'),
      ),
      [
        SaleReturnAdjustmentItemsCompanion.insert(
          returnId: 0,
          productId: productId,
          variantId: Value(variantId),
          quantity: 2,
          unitPriceCents: Decimal.fromInt(2000),
          totalCents: Decimal.fromInt(4000),
        ),
      ],
    );
    await adjDao.postSaleAdjReturn(saleAdjRet, journalEntryService: journal);

    // ── Linked purchase return: qty 4 @ 1000 = 4000 ──
    final linkedPurchRet = await db.purchaseDao.createPurchaseReturn(
      PurchaseReturnsCompanion.insert(
        returnNumber: 'PR-1',
        purchaseId: purchaseId,
        subtotalCents: Value(Decimal.fromInt(4000)),
        totalCents: Decimal.fromInt(4000),
        currencyId: currencyId,
      ),
      [
        PurchaseReturnItemsCompanion.insert(
          returnId: 0,
          purchaseItemId: purchaseItem.id,
          quantity: 4,
          subtotalCents: Value(Decimal.fromInt(4000)),
          refundCents: Decimal.fromInt(4000),
        ),
      ],
    );
    await db.purchaseDao.postPurchaseReturn(linkedPurchRet);

    // ── Adjustment purchase return: qty 5 @ 1000 = 5000 ──
    final purchAdjRet = await adjDao.createPurchaseAdjReturn(
      PurchaseReturnAdjustmentsCompanion.insert(
        returnNumber: 'PAR-1',
        supplierId: supplierId,
        currencyId: currencyId,
        totalCents: Decimal.fromInt(5000),
      ),
      [
        PurchaseReturnAdjustmentItemsCompanion.insert(
          returnId: 0,
          productId: productId,
          variantId: Value(variantId),
          quantity: 5,
          unitPriceCents: Decimal.fromInt(1000),
          totalCents: Decimal.fromInt(5000),
        ),
      ],
    );
    await adjDao.postPurchaseAdjReturn(purchAdjRet,
        journalEntryService: journal);
  });

  tearDown(() async => db.close());

  test('sales report net deducts linked AND adjustment returns', () async {
    final bloc = SalesReportsBloc(db);
    addTearDown(bloc.close);
    bloc.add(SalesReportsDateRangeChanged(ReportDateRange.allTime()));

    final data = await firstSuccess<SalesReportsData>(bloc.stream);

    expect(data.summary.totalSalesCents, 20000);
    expect(data.summary.totalReturnsCents, 10000); // 6000 linked + 4000 adj
    expect(data.summary.returnCount, 2);
    expect(data.summary.netSalesCents, 10000);
  });

  test('purchase report net deducts linked AND adjustment returns', () async {
    final bloc = PurchaseReportsBloc(db);
    addTearDown(bloc.close);
    bloc.add(PurchaseReportsDateRangeChanged(ReportDateRange.allTime()));

    final data = await firstSuccess<PurchaseReportsData>(bloc.stream);

    expect(data.summary.totalPurchasesCents, 20000);
    expect(data.summary.totalReturnsCents, 9000); // 4000 linked + 5000 adj
    expect(data.summary.returnCount, 2);
    expect(data.summary.netPurchasesCents, 11000);
  });

  test('customer sales returns report includes adjustment returns', () async {
    final bloc = CustomerSalesReturnsBloc(db);
    addTearDown(bloc.close);
    bloc.add(CustomerSalesReturnsDateRangeChanged(ReportDateRange.allTime()));

    final data = await firstSuccess<CustomerSalesReturnsData>(bloc.stream);

    expect(data.totalReturnCount, 2); // 1 linked + 1 adjustment
    expect(data.totalReturnsCents, 10000); // 6000 + 4000
    expect(data.returnDetails.length, 2);
    expect(
      data.returnDetails.any((d) => d.dispositionType == 'adjustment'),
      isTrue,
      reason: 'the adjustment return must appear in the details list',
    );
  });

  test('product movement returned-qty includes adjustment returns', () async {
    final bloc = InventoryReportsBloc(db);
    addTearDown(bloc.close);
    bloc.add(InventoryReportsDateRangeChanged(ReportDateRange.allTime()));

    final data = await firstSuccess<InventoryReportsData>(bloc.stream);

    final movement =
        data.productMovement.firstWhere((m) => m.productId == productId);
    expect(movement.purchasedQty, 20);
    expect(movement.soldQty, 10);
    expect(movement.saleReturnedQty, 5); // 3 linked + 2 adjustment
    expect(movement.purchaseReturnedQty, 9); // 4 linked + 5 adjustment
  });
}
