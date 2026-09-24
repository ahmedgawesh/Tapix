import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/business/branch_consignment_policy_store.dart';
import 'package:tapix/core/services/business/local_branch_scope.dart';
import 'package:tapix/core/services/journal_entry_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';
import 'package:tapix/features/auth/data/services/session_service.dart';
import 'package:tapix/features/consignment/data/consignment_agreement_service.dart';
import 'package:tapix/features/consignment/data/consignment_custody_service.dart';
import 'package:tapix/features/consignment/data/consignment_entitlement.dart';
import 'package:tapix/features/consignment/data/consignment_module_service.dart';
import 'package:tapix/features/consignment/data/consignment_receipt_service.dart';
import 'package:tapix/features/consignment/data/consignment_settlement_service.dart';

class _Session extends SessionService {
  _Session(this.id);
  final int id;

  @override
  Future<int?> getCurrentUserId() async => id;
}

Future<
  ({
    AppDatabase db,
    ConsignmentModuleService module,
    ConsignmentCustodyService custody,
    int owner,
    int currency,
    int supplier,
    int product,
    int variant,
    String agreementId,
    String warehouseId,
    String layerId,
  })
>
_fixture({bool percentage = false}) async {
  final db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
  final owner = await db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          username: 'custody-owner',
          passwordHash: 'test',
          role: 'owner',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );
  final currency = (await (db.select(
    db.currencies,
  )..where((c) => c.code.equals('USD'))).getSingle()).id;
  final supplier = await db
      .into(db.suppliers)
      .insert(
        SuppliersCompanion.insert(
          name: 'Custody supplier',
          currencyId: currency,
        ),
      );
  final product = await db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          name: 'Custody product',
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
  final module = ConsignmentModuleService(
    db,
    _Session(owner),
    const GrantedConsignmentEntitlement(),
    BranchConsignmentPolicyStore(db),
    isRemoteClient: () => false,
  );
  await module.initialize();
  await module.setEnabled(enabled: true, reason: 'custody test');
  final agreements = ConsignmentAgreementService(db, module);
  final agreement = await agreements.createDraft(
    supplierId: supplier,
    currencyId: currency,
    agreementNumber: percentage ? 'CON-PCT' : 'CON-FIXED',
    effectiveFrom: DateTime.utc(2026, 9, 1),
    terms: [
      if (percentage)
        ConsignmentAgreementTermInput.salesPercentage(
          productId: product,
          variantId: variant,
          shareBps: 6000,
        )
      else
        ConsignmentAgreementTermInput.fixedCost(
          productId: product,
          variantId: variant,
          amountCents: 900,
        ),
    ],
  );
  await agreements.activate(agreement.id);
  final warehouseId = (await LocalBranchScope.read(db)).warehouseId;
  final receiptService = ConsignmentReceiptService(db, module);
  final receipt = await receiptService.createDraft(
    requestKey: const Uuid().v4(),
    receiptNumber: percentage ? 'CR-PCT' : 'CR-FIXED',
    warehouseId: warehouseId,
    supplierId: supplier,
    agreementId: agreement.id,
    currencyId: currency,
    receivedAt: DateTime.utc(2026, 9, 24),
    lines: [
      ConsignmentReceiptLineInput(
        productId: product,
        variantId: variant,
        quantity: 5,
      ),
    ],
  );
  await receiptService.post(
    receiptId: receipt.id,
    requestKey: const Uuid().v4(),
  );
  final layer = (await db.select(db.consignmentInventoryLayers).get()).single;
  final journal = JournalEntryService(AccountingRepository(db));
  return (
    db: db,
    module: module,
    custody: ConsignmentCustodyService(db, module, journal),
    owner: owner,
    currency: currency,
    supplier: supplier,
    product: product,
    variant: variant,
    agreementId: agreement.id,
    warehouseId: warehouseId,
    layerId: layer.id,
  );
}

void main() {
  test('supplier return removes and void restores physical custody', () async {
    final f = await _fixture();
    addTearDown(f.db.close);

    final draft = await f.custody.createDraft(
      requestKey: const Uuid().v4(),
      documentNumber: 'CCR-000001',
      documentType: 'supplier_return',
      responsibility: 'supplier',
      warehouseId: f.warehouseId,
      supplierId: f.supplier,
      agreementId: f.agreementId,
      currencyId: f.currency,
      occurredAt: DateTime.utc(2026, 9, 24),
      reason: 'Unsold goods returned in good condition',
      lines: [ConsignmentCustodyLineInput(layerId: f.layerId, quantity: 2)],
    );
    expect(draft.status, 'draft');

    final posted = await f.custody.post(
      documentId: draft.id,
      requestKey: const Uuid().v4(),
    );
    expect(posted.status, 'posted');
    var stock =
        await (f.db.select(f.db.businessWarehouseStocks)..where(
              (s) =>
                  s.warehouseId.equals(f.warehouseId) &
                  s.variantId.equals(f.variant),
            ))
            .getSingle();
    expect(stock.quantity, 3);
    expect(stock.supplierOwnedQuantity, 3);
    expect(
      (await f.db.select(f.db.consignmentInventoryLayers).getSingle())
          .remainingQuantity,
      3,
    );
    final postedEvent = await f.db
        .select(f.db.consignmentCustodyEvents)
        .getSingle();
    expect(postedEvent.signedAmountCents, 0);
    expect(postedEvent.journalEntryId, isNull);
    expect(postedEvent.settlementStatus, 'not_applicable');

    final voided = await f.custody.voidDocument(
      documentId: draft.id,
      requestKey: const Uuid().v4(),
      reason: 'Supplier rejected the physical handover',
    );
    expect(voided.status, 'voided');
    stock =
        await (f.db.select(f.db.businessWarehouseStocks)..where(
              (s) =>
                  s.warehouseId.equals(f.warehouseId) &
                  s.variantId.equals(f.variant),
            ))
            .getSingle();
    expect(stock.quantity, 5);
    expect(stock.supplierOwnedQuantity, 5);
    expect(
      (await f.db.select(f.db.consignmentInventoryLayers).getSingle())
          .remainingQuantity,
      5,
    );
  });

  test('company-borne damage accrues 5800 against 2050 and settles', () async {
    final f = await _fixture();
    addTearDown(f.db.close);

    final draft = await f.custody.createDraft(
      requestKey: const Uuid().v4(),
      documentNumber: 'CCD-000001',
      documentType: 'damage',
      responsibility: 'company',
      warehouseId: f.warehouseId,
      supplierId: f.supplier,
      agreementId: f.agreementId,
      currencyId: f.currency,
      occurredAt: DateTime.utc(2026, 9, 24, 10),
      reason: 'Broken while under store custody',
      lines: [ConsignmentCustodyLineInput(layerId: f.layerId, quantity: 1)],
    );
    await f.custody.post(documentId: draft.id, requestKey: const Uuid().v4());

    final event = await f.db.select(f.db.consignmentCustodyEvents).getSingle();
    expect(event.signedQuantity, 1);
    expect(event.signedAmountCents, 900);
    expect(event.journalEntryId, isNotNull);
    expect(event.settlementStatus, 'unassigned');
    final lines =
        await (f.db.select(f.db.journalEntryLines).join([
              innerJoin(
                f.db.accounts,
                f.db.accounts.id.equalsExp(f.db.journalEntryLines.accountId),
              ),
            ])..where(
              f.db.journalEntryLines.journalEntryId.equals(
                event.journalEntryId!,
              ),
            ))
            .get();
    final byCode = {
      for (final row in lines)
        row.readTable(f.db.accounts).accountCode: row.readTable(
          f.db.journalEntryLines,
        ),
    };
    expect(byCode['5800']!.debitCents.toBigInt().toInt(), 900);
    expect(byCode['2050']!.creditCents.toBigInt().toInt(), 900);

    final settlement =
        await ConsignmentSettlementService(
          f.db,
          f.module,
          JournalEntryService(AccountingRepository(f.db)),
        ).createDraft(
          requestKey: const Uuid().v4(),
          agreementId: f.agreementId,
          periodStart: DateTime.utc(2026, 9, 24),
          periodEnd: DateTime.utc(2026, 9, 25),
        );
    final item =
        (await f.db.select(f.db.consignmentSettlementItems).get()).single;
    expect(item.statementId, settlement.id);
    expect(item.sourceLedger, 'custody_loss');
    expect(item.signedAmountCents, 900);
    expect(
      (await f.db.select(f.db.consignmentCustodyEvents).getSingle())
          .settlementStatus,
      'assigned',
    );
    await expectLater(
      f.custody.voidDocument(
        documentId: draft.id,
        requestKey: const Uuid().v4(),
        reason: 'Cannot void after settlement reservation',
      ),
      throwsA(isA<ConsignmentUserException>()),
    );
  });

  test('percentage agreement requires explicit unsold-loss value', () async {
    final f = await _fixture(percentage: true);
    addTearDown(f.db.close);

    await expectLater(
      f.custody.createDraft(
        requestKey: const Uuid().v4(),
        documentNumber: 'CCL-000001',
        documentType: 'loss',
        responsibility: 'company',
        warehouseId: f.warehouseId,
        supplierId: f.supplier,
        agreementId: f.agreementId,
        currencyId: f.currency,
        occurredAt: DateTime.utc(2026, 9, 24),
        reason: 'Missing during count',
        lines: [ConsignmentCustodyLineInput(layerId: f.layerId, quantity: 1)],
      ),
      throwsA(
        isA<ConsignmentUserException>().having(
          (error) => error.messageKey,
          'messageKey',
          'consignment.custody_liability_cost_required',
        ),
      ),
    );

    final draft = await f.custody.createDraft(
      requestKey: const Uuid().v4(),
      documentNumber: 'CCL-000002',
      documentType: 'loss',
      responsibility: 'company',
      warehouseId: f.warehouseId,
      supplierId: f.supplier,
      agreementId: f.agreementId,
      currencyId: f.currency,
      occurredAt: DateTime.utc(2026, 9, 24),
      reason: 'Missing during count',
      lines: [
        ConsignmentCustodyLineInput(
          layerId: f.layerId,
          quantity: 1,
          liabilityUnitCents: 850,
        ),
      ],
    );
    expect(
      (await (f.db.select(
            f.db.consignmentCustodyItems,
          )..where((i) => i.documentId.equals(draft.id))).getSingle())
          .liabilityAmountCents,
      850,
    );
  });

  test('draft refuses quantity above the exact custody layer', () async {
    final f = await _fixture();
    addTearDown(f.db.close);

    await expectLater(
      f.custody.createDraft(
        requestKey: const Uuid().v4(),
        documentNumber: 'CCR-OVER',
        documentType: 'supplier_return',
        responsibility: 'supplier',
        warehouseId: f.warehouseId,
        supplierId: f.supplier,
        agreementId: f.agreementId,
        currencyId: f.currency,
        occurredAt: DateTime.utc(2026, 9, 24),
        reason: 'Attempted over-return',
        lines: [ConsignmentCustodyLineInput(layerId: f.layerId, quantity: 6)],
      ),
      throwsA(isA<ConsignmentUserException>()),
    );
  });
}
