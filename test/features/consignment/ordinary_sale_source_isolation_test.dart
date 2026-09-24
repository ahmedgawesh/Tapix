import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/batch_service.dart';
import 'package:tapix/core/services/business/branch_consignment_policy_store.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/stock_service.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/consignment/data/consignment_agreement_service.dart';
import 'package:tapix/features/consignment/data/consignment_entitlement.dart';
import 'package:tapix/features/consignment/data/consignment_module_service.dart';
import 'package:tapix/features/consignment/data/consignment_receipt_service.dart';

class _Session extends SessionService {
  _Session(this.userId);

  final int userId;

  @override
  Future<int?> getCurrentUserId() async => userId;
}

AppDatabase _memoryDb() =>
    AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));

Future<
  ({
    int currency,
    int product,
    int variant,
    WarehouseOperationScope scope,
    String layerId,
    int? consignmentBatchId,
    int? ordinaryBatchId,
  })
>
_seedMixedStock(AppDatabase db, {required bool fifo}) async {
  final userId = await db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          username: fifo ? 'fifo-owner' : 'wac-owner',
          passwordHash: 'not-used',
          role: 'owner',
          createdAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
  final currency = (await (db.select(
    db.currencies,
  )..where((row) => row.code.equals('USD'))).getSingle()).id;
  final supplier = await db
      .into(db.suppliers)
      .insert(
        SuppliersCompanion.insert(
          name: fifo ? 'FIFO custody supplier' : 'WAC custody supplier',
          currencyId: currency,
        ),
      );
  final product = await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          name: fifo ? 'FIFO mixed ownership' : 'WAC mixed ownership',
          currencyId: Value(currency),
          costCents: Decimal.fromInt(100),
          priceCents: Decimal.fromInt(150),
          costingMethod: Value(fifo ? 'fifo' : 'wac'),
          inventoryTrackingType: Value(fifo ? 'batch' : 'standard'),
        ),
      );
  final variant = await db
      .into(db.productVariants)
      .insert(
        ProductVariantsCompanion.insert(
          productId: product,
          costCents: Decimal.fromInt(100),
          priceCents: Decimal.fromInt(150),
        ),
      );
  final module = ConsignmentModuleService(
    db,
    _Session(userId),
    const GrantedConsignmentEntitlement(),
    BranchConsignmentPolicyStore(db),
    isRemoteClient: () => false,
  );
  await module.initialize();
  await module.setEnabled(
    enabled: true,
    reason: 'mixed ownership isolation test',
  );
  final agreementService = ConsignmentAgreementService(db, module);
  final agreement = await agreementService.createDraft(
    supplierId: supplier,
    currencyId: currency,
    agreementNumber: fifo ? 'CON-FIFO-MIXED' : 'CON-WAC-MIXED',
    effectiveFrom: DateTime.utc(2026, 9, 1),
    terms: [
      ConsignmentAgreementTermInput.fixedCost(
        productId: product,
        variantId: variant,
        amountCents: 90,
      ),
    ],
  );
  await agreementService.activate(agreement.id);
  final scope = await WarehouseOperationScope.resolve(db);
  final receipt = await ConsignmentReceiptService(db, module).createDraft(
    requestKey: const Uuid().v4(),
    receiptNumber: fifo ? 'CR-FIFO-MIXED' : 'CR-WAC-MIXED',
    warehouseId: scope.warehouseId,
    supplierId: supplier,
    agreementId: agreement.id,
    currencyId: currency,
    receivedAt: DateTime.utc(2026, 9, 1),
    lines: [
      ConsignmentReceiptLineInput(
        productId: product,
        variantId: variant,
        quantity: 2,
        manufacturerLotNumber: fifo ? 'LOT-CONSIGNMENT' : null,
      ),
    ],
  );
  await ConsignmentReceiptService(
    db,
    module,
  ).post(receiptId: receipt.id, requestKey: const Uuid().v4());
  final layer = (await db.select(db.consignmentInventoryLayers).get()).single;

  int? ordinaryBatchId;
  if (fifo) {
    ordinaryBatchId = await BatchService.createOpeningBatch(
      db.saleDao,
      productId: product,
      variantId: variant,
      quantity: 3,
      unitCostCents: 100,
      source: 'opening',
      receivedDate: DateTime.utc(2026, 9, 2),
      scope: scope,
    );
  }
  await StockService.adjustStock(
    db.saleDao,
    origin: InventoryOriginIntent('opening', product),
    scope: scope,
    productId: product,
    variantId: variant,
    quantity: 3,
    direction: StockDirection.increase,
  );
  await StockService.syncProductStockFromVariants(
    db.saleDao,
    scope: scope,
    productId: product,
  );
  return (
    currency: currency,
    product: product,
    variant: variant,
    scope: scope,
    layerId: layer.id,
    consignmentBatchId: layer.batchId,
    ordinaryBatchId: ordinaryBatchId,
  );
}

Future<void> _postUnverifiedSale(
  AppDatabase db,
  ({
    int currency,
    int product,
    int variant,
    WarehouseOperationScope scope,
    String layerId,
    int? consignmentBatchId,
    int? ordinaryBatchId,
  })
  seed,
) async {
  final saleId = await db.saleDao.createSaleWithItems(
    SalesCompanion.insert(
      invoiceNumber: 'SI-${seed.product}-UNVERIFIED',
      subtotalCents: Decimal.fromInt(150),
      taxCents: Decimal.zero,
      totalCents: Decimal.fromInt(150),
      currencyId: seed.currency,
      paymentMethod: 'cash',
      status: const Value('draft'),
    ),
    [
      SaleItemsCompanion.insert(
        saleId: 0,
        productId: seed.product,
        variantId: Value(seed.variant),
        quantity: 1,
        unitPriceCents: Decimal.fromInt(150),
        subtotalCents: Decimal.fromInt(150),
        itemDiscountAtPostCents: Value(Decimal.zero),
        invoiceDiscountAtPostCents: Value(Decimal.zero),
        totalCents: Decimal.fromInt(150),
      ),
    ],
    scope: seed.scope,
  );
  await db.saleDao.postSale(saleId, scope: seed.scope);

  expect(await db.select(db.consignmentSaleAllocations).get(), isEmpty);
  expect(await db.select(db.consignmentObligationEvents).get(), isEmpty);
  final layer = await (db.select(
    db.consignmentInventoryLayers,
  )..where((row) => row.id.equals(seed.layerId))).getSingle();
  expect(layer.remainingQuantity, 2);
  final stock =
      await (db.select(db.businessWarehouseStocks)..where(
            (row) =>
                row.warehouseId.equals(seed.scope.warehouseId) &
                row.variantId.equals(seed.variant),
          ))
          .getSingle();
  expect(stock.quantity, 4);
  expect(stock.supplierOwnedQuantity, 2);
}

void main() {
  test('unverified WAC sale never consumes a consignment source', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final seed = await _seedMixedStock(db, fifo: false);

    await _postUnverifiedSale(db, seed);

    final event = await (db.select(
      db.inventoryOriginEvents,
    )..where((row) => row.eventKey.like('sale:%'))).getSingle();
    final allocations = (jsonDecode(event.allocations) as List)
        .cast<Map<String, dynamic>>();
    expect(
      allocations.any((allocation) => allocation['k'] == 'consignment_receipt'),
      isFalse,
    );
  });

  test('unverified FIFO sale skips the consignment batch', () async {
    final db = _memoryDb();
    addTearDown(db.close);
    final seed = await _seedMixedStock(db, fifo: true);

    await _postUnverifiedSale(db, seed);

    final consignmentBatch = await (db.select(
      db.productBatches,
    )..where((row) => row.id.equals(seed.consignmentBatchId!))).getSingle();
    final ordinaryBatch = await (db.select(
      db.productBatches,
    )..where((row) => row.id.equals(seed.ordinaryBatchId!))).getSingle();
    expect(consignmentBatch.remainingQuantity, 2);
    expect(ordinaryBatch.remainingQuantity, 2);
  });
}
