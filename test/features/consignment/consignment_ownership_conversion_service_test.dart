import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/branch_consignment_policy_store.dart';
import 'package:tapix/core/services/business/local_branch_scope.dart';
import 'package:tapix/core/services/business/warehouse_operation_scope.dart';
import 'package:tapix/core/services/inventory/inventory_stock_source_service.dart';
import 'package:tapix/core/services/inventory/supplier_product_identity_service.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/core/services/stock_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/consignment/data/consignment_agreement_service.dart';
import 'package:tapix/features/consignment/data/consignment_entitlement.dart';
import 'package:tapix/features/consignment/data/consignment_module_service.dart';
import 'package:tapix/features/consignment/data/consignment_ownership_conversion_service.dart';
import 'package:tapix/features/consignment/data/consignment_receipt_service.dart';

class _Session extends SessionService {
  _Session(this.id);
  final int id;

  @override
  Future<int?> getCurrentUserId() async => id;
}

void main() {
  test(
    'conversion preserves physical quantity, moves exact ownership and void restores all ledgers',
    () async {
      final db = AppDatabase.connect(
        DatabaseConnection(NativeDatabase.memory()),
      );
      addTearDown(db.close);
      final owner = await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              username: 'conversion-owner',
              passwordHash: 'test',
              role: 'owner',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
          );
      final currency = (await (db.select(
        db.currencies,
      )..where((row) => row.code.equals('USD'))).getSingle()).id;
      final supplier = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Conversion supplier',
              productCode: const Value('CVS'),
              balanceCents: Value(Decimal.fromInt(5000)),
              currencyId: currency,
            ),
          );
      final product = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Convertible WAC item',
              sku: const Value('CV-WAC-1'),
              currencyId: Value(currency),
              costCents: Decimal.fromInt(1000),
              priceCents: Decimal.fromInt(1500),
            ),
          );
      final variant = await db
          .into(db.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              productId: product,
              costCents: Decimal.fromInt(1000),
              priceCents: Decimal.fromInt(1500),
            ),
          );
      final identity = await SupplierProductIdentityService(db).ensureIssued(
        supplierId: supplier,
        productId: product,
        variantId: variant,
      );
      final local = await LocalBranchScope.read(db);
      final scope = await WarehouseOperationScope.resolve(
        db,
        warehouseId: local.warehouseId,
      );
      await StockService.adjustStock(
        db.productDao,
        productId: product,
        variantId: variant,
        quantity: 5,
        direction: StockDirection.increase,
        scope: scope,
        origin: InventoryOriginIntent.keyed(
          'adjustment',
          'conversion-test-opening',
          supplierIdentityId: identity.id,
        ),
      );
      await (db.update(db.businessWarehouseStocks)..where(
            (row) =>
                row.warehouseId.equals(local.warehouseId) &
                row.variantId.equals(variant),
          ))
          .write(
            const BusinessWarehouseStocksCompanion(unitCostCents: Value(1000)),
          );

      final module = ConsignmentModuleService(
        db,
        _Session(owner),
        const GrantedConsignmentEntitlement(),
        BranchConsignmentPolicyStore(db),
        isRemoteClient: () => false,
      );
      await module.initialize();
      await module.setEnabled(enabled: true, reason: 'conversion test');
      final agreementService = ConsignmentAgreementService(db, module);
      final agreement = await agreementService.createDraft(
        supplierId: supplier,
        currencyId: currency,
        agreementNumber: 'CON-CONVERSION',
        effectiveFrom: DateTime.utc(2026, 9, 1),
        terms: [
          ConsignmentAgreementTermInput.fixedCost(
            productId: product,
            variantId: variant,
            amountCents: 900,
          ),
        ],
      );
      await agreementService.activate(agreement.id);
      final service = ConsignmentOwnershipConversionService(
        db,
        module,
        ConsignmentReceiptService(db, module),
        JournalEntryService(AccountingRepository(db)),
      );

      final conversion = await service.convert(
        requestKey: const Uuid().v4(),
        conversionNumber: 'CO-000001',
        evidenceReference: 'SUP-CN-2026-17',
        warehouseId: local.warehouseId,
        supplierId: supplier,
        agreementId: agreement.id,
        currencyId: currency,
        convertedAt: DateTime.utc(2026, 9, 24),
        lines: [
          ConsignmentOwnershipConversionLineInput(
            productId: product,
            variantId: variant,
            quantity: 2,
            supplierIdentityId: identity.id,
          ),
        ],
      );
      expect(conversion.status, 'posted');
      expect(conversion.inventoryValueCents, 2000);
      var stock =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(local.warehouseId) &
                    row.variantId.equals(variant),
              ))
              .getSingle();
      expect(stock.quantity, 5);
      expect(stock.supplierOwnedQuantity, 2);
      var sources = await InventoryStockSourceService(
        db,
      ).loadProduct(product, variantId: variant, scope: scope);
      expect(sources.physicalQuantity, 5);
      expect(sources.enterpriseQuantity, 3);
      expect(sources.consignmentQuantity, 2);
      expect(
        (await (db.select(
          db.suppliers,
        )..where((row) => row.id.equals(supplier))).getSingle()).balanceCents,
        Decimal.fromInt(3000),
      );
      final postingLines =
          await (db.select(db.journalEntryLines).join([
                innerJoin(
                  db.accounts,
                  db.accounts.id.equalsExp(db.journalEntryLines.accountId),
                ),
              ])..where(
                db.journalEntryLines.journalEntryId.equals(
                  conversion.journalEntryId!,
                ),
              ))
              .get();
      final byCode = {
        for (final row in postingLines)
          row.readTable(db.accounts).accountCode: row.readTable(
            db.journalEntryLines,
          ),
      };
      expect(byCode['2000']!.debitCents.toBigInt().toInt(), 2000);
      expect(byCode['1200']!.creditCents.toBigInt().toInt(), 2000);

      final voided = await service.voidConversion(
        conversionId: conversion.id,
        requestKey: const Uuid().v4(),
        reason: 'Supplier withdrew the approved ownership amendment',
      );
      expect(voided.status, 'voided');
      stock =
          await (db.select(db.businessWarehouseStocks)..where(
                (row) =>
                    row.warehouseId.equals(local.warehouseId) &
                    row.variantId.equals(variant),
              ))
              .getSingle();
      expect(stock.quantity, 5);
      expect(stock.supplierOwnedQuantity, 0);
      sources = await InventoryStockSourceService(
        db,
      ).loadProduct(product, variantId: variant, scope: scope);
      expect(sources.enterpriseQuantity, 5);
      expect(sources.consignmentQuantity, 0);
      expect(
        (await (db.select(
          db.suppliers,
        )..where((row) => row.id.equals(supplier))).getSingle()).balanceCents,
        Decimal.fromInt(5000),
      );
    },
  );
}
