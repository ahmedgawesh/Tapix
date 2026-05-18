// Phase 15.0 — pins the orchestration contract of `ChequeLifecycleService`.
//
// Closes the field-reported P0: confirming a cheque as `cleared` in the
// dashboard previously wrote only to `cheque_confirmations` (lifecycle
// sidecar) and did NOT settle the AP/AR balance, did NOT update
// `purchases.paid_amount_cents`, did NOT insert a payment row, and did
// NOT post the Dr/Cr Bank journal entry. The supplier/customer profile
// kept showing the original balance and the reconciliation engine
// surfaced this gap immediately.
//
// These tests assert — at the orchestration boundary — that the service:
//
//   1. On `pending → cleared` for a sale/purchase with outstanding > 0:
//      • calls `repo.recordPayment(amount = outstanding, method='cheque')`
//      • stamps the returned `paymentId` on `cheque_confirmations.cleared_payment_id`
//      • returns `settledAmountCents = outstanding`
//   2. Is idempotent: a second `markCleared` does NOT call `recordPayment`
//      again (the dashboard double-click bug).
//   3. On `pending → cleared` with `outstanding == 0`: does NOT call
//      `recordPayment` — only the lifecycle row flips.
//   4. On `cleared → bounced`: calls `repo.deletePayment(stampedId)` to
//      reverse the settlement and NULLs the `cleared_payment_id` pointer.
//      Requires a non-empty bounceReason.
//   5. On `cleared → cancelled`: same reversal as #4, without a reason.
//   6. For return source tables (`sale_return`, `purchase_return`, …):
//      lifecycle row flips but NO payment is recorded (the refund leg was
//      already booked when the return was posted).
//
// The end-to-end JE/balance side-effects of `recordPayment` and
// `deletePayment` are already pinned by the SaleRepository/
// PurchaseRepository test packs from earlier phases; this file owns the
// orchestration contract only — that is the actual root cause of the
// field bug.

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';
import 'package:tapix/core/services/cheque_lifecycle_service.dart';
import 'package:tapix/features/purchases/domain/entities/purchase_entity.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:tapix/features/sales/domain/entities/sale_entity.dart';
import 'package:tapix/features/sales/domain/repositories/sale_repository.dart';

class _MockPurchaseRepository extends Mock implements PurchaseRepository {}

class _MockSaleRepository extends Mock implements SaleRepository {}

void main() {
  late AppDatabase db;
  late ChequeConfirmationDao dao;
  late _MockPurchaseRepository purchaseRepo;
  late _MockSaleRepository saleRepo;
  late ChequeLifecycleService service;

  setUpAll(() {
    registerFallbackValue(DateTime(2026, 1, 1));
    registerFallbackValue(Decimal.zero);
  });

  setUp(() {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    dao = ChequeConfirmationDao(db);
    purchaseRepo = _MockPurchaseRepository();
    saleRepo = _MockSaleRepository();
    service = ChequeLifecycleService(
      db: db,
      confirmationDao: dao,
      purchaseRepository: purchaseRepo,
      saleRepository: saleRepo,
    );
  });

  tearDown(() async => db.close());

  // ── shared fixtures ────────────────────────────────────────────────────

  PurchaseEntity buildPurchase({
    int id = 100,
    int totalCents = 59394,
    int paidCents = 0,
    String status = 'posted',
  }) {
    return PurchaseEntity(
      id: id,
      purchaseNumber: 'PO-TEST-$id',
      supplierId: 1,
      subtotalCents: Decimal.fromInt(totalCents),
      taxCents: Decimal.zero,
      totalCents: Decimal.fromInt(totalCents),
      paidAmountCents: Decimal.fromInt(paidCents),
      currencyId: 1,
      status: status,
      paymentMethod: 'cheque',
      purchaseDate: DateTime(2026, 5, 18),
      createdAt: DateTime(2026, 5, 18),
      updatedAt: DateTime(2026, 5, 18),
    );
  }

  SaleEntity buildSale({
    int id = 200,
    int totalCents = 12345,
    int paidCents = 0,
    String status = 'completed',
  }) {
    return SaleEntity(
      id: id,
      invoiceNumber: 'INV-TEST-$id',
      customerId: 1,
      subtotalCents: Decimal.fromInt(totalCents),
      taxCents: Decimal.zero,
      discountCents: Decimal.zero,
      totalCents: Decimal.fromInt(totalCents),
      paidAmountCents: Decimal.fromInt(paidCents),
      currencyId: 1,
      paymentMethod: 'cheque',
      status: status,
      saleDate: DateTime(2026, 5, 18),
      createdAt: DateTime(2026, 5, 18),
      updatedAt: DateTime(2026, 5, 18),
    );
  }

  // ── 1. cleared on purchase with outstanding > 0 ────────────────────────

  group('markCleared — purchase, outstanding > 0', () {
    test('records a real cheque payment and stamps cleared_payment_id',
        () async {
      // ARRANGE
      const purchaseId = 2;
      const outstanding = 59394; // matches the field-reported case
      when(() => purchaseRepo.getPurchaseById(purchaseId))
          .thenAnswer((_) async => buildPurchase(id: purchaseId));
      when(() => purchaseRepo.recordPayment(
            purchaseId: any(named: 'purchaseId'),
            currencyId: any(named: 'currencyId'),
            amountCents: any(named: 'amountCents'),
            paymentMethod: any(named: 'paymentMethod'),
            notes: any(named: 'notes'),
            paymentDate: any(named: 'paymentDate'),
          )).thenAnswer((_) async => 777);

      // ACT
      final result = await service.markCleared(
        sourceTable: ChequeSourceTables.purchase,
        sourceId: purchaseId,
      );

      // ASSERT — orchestration
      expect(result.status, ChequeConfirmationStatus.cleared);
      expect(result.settledAmountCents, outstanding);
      expect(result.createdPaymentId, 777);

      // ASSERT — exactly one payment recorded with cheque method + full
      // outstanding amount.
      final captured = verify(() => purchaseRepo.recordPayment(
            purchaseId: captureAny(named: 'purchaseId'),
            currencyId: captureAny(named: 'currencyId'),
            amountCents: captureAny(named: 'amountCents'),
            paymentMethod: captureAny(named: 'paymentMethod'),
            notes: captureAny(named: 'notes'),
            paymentDate: captureAny(named: 'paymentDate'),
          )).captured;
      expect(captured[0], purchaseId);
      expect(captured[1], 1);
      expect(captured[2], Decimal.fromInt(outstanding));
      expect(captured[3], 'cheque');

      // ASSERT — DB sidecar stamped with the payment id.
      final row = await dao.getBySource(
        sourceTable: ChequeSourceTables.purchase,
        sourceId: purchaseId,
      );
      expect(row, isNotNull);
      expect(row!.status, ChequeConfirmationStatus.cleared);
      expect(row.clearedPaymentId, 777);
    });

    test('idempotent — repeating markCleared does NOT post a second payment',
        () async {
      const purchaseId = 5;
      when(() => purchaseRepo.getPurchaseById(purchaseId))
          .thenAnswer((_) async => buildPurchase(id: purchaseId));
      when(() => purchaseRepo.recordPayment(
            purchaseId: any(named: 'purchaseId'),
            currencyId: any(named: 'currencyId'),
            amountCents: any(named: 'amountCents'),
            paymentMethod: any(named: 'paymentMethod'),
            notes: any(named: 'notes'),
            paymentDate: any(named: 'paymentDate'),
          )).thenAnswer((_) async => 42);

      await service.markCleared(
        sourceTable: ChequeSourceTables.purchase,
        sourceId: purchaseId,
      );
      final second = await service.markCleared(
        sourceTable: ChequeSourceTables.purchase,
        sourceId: purchaseId,
      );

      // First call recorded payment 42; second call returned cached result.
      verify(() => purchaseRepo.recordPayment(
            purchaseId: any(named: 'purchaseId'),
            currencyId: any(named: 'currencyId'),
            amountCents: any(named: 'amountCents'),
            paymentMethod: any(named: 'paymentMethod'),
            notes: any(named: 'notes'),
            paymentDate: any(named: 'paymentDate'),
          )).called(1);
      expect(second.status, ChequeConfirmationStatus.cleared);
      expect(second.createdPaymentId, 42);
      // settledAmountCents on the second call is null — nothing settled
      // this time; the first call did the work.
      expect(second.settledAmountCents, isNull);
    });
  });

  // ── 2. cleared on already-paid invoice — no payment recorded ──────────

  test('markCleared on a fully-paid sale only flips lifecycle, no payment',
      () async {
    const saleId = 9;
    when(() => saleRepo.getSaleById(saleId))
        .thenAnswer((_) async => buildSale(
              id: saleId,
              totalCents: 1000,
              paidCents: 1000,
            ));

    final result = await service.markCleared(
      sourceTable: ChequeSourceTables.sale,
      sourceId: saleId,
    );

    expect(result.status, ChequeConfirmationStatus.cleared);
    expect(result.settledAmountCents, isNull);
    expect(result.createdPaymentId, isNull);

    verifyNever(() => saleRepo.recordPayment(
          saleId: any(named: 'saleId'),
          amountCents: any(named: 'amountCents'),
          currencyId: any(named: 'currencyId'),
          paymentMethod: any(named: 'paymentMethod'),
          notes: any(named: 'notes'),
          paymentDate: any(named: 'paymentDate'),
        ));
    final row = await dao.getBySource(
      sourceTable: ChequeSourceTables.sale,
      sourceId: saleId,
    );
    expect(row!.clearedPaymentId, isNull);
  });

  // ── 3. cleared on return source — no payment recorded ─────────────────

  test('markCleared on a sale_return only flips lifecycle, no payment',
      () async {
    final result = await service.markCleared(
      sourceTable: ChequeSourceTables.saleReturn,
      sourceId: 11,
    );

    expect(result.status, ChequeConfirmationStatus.cleared);
    expect(result.settledAmountCents, isNull);
    expect(result.createdPaymentId, isNull);
    verifyZeroInteractions(saleRepo);
    verifyZeroInteractions(purchaseRepo);
  });

  // ── 4. cleared → bounced reverses the prior settlement ────────────────

  test('markBounced after markCleared reverses the settlement payment',
      () async {
    // Seed a real purchase + cheque payment row so the service's
    // amount-snapshot read can recover the reversed cents from
    // `purchase_payments`. The mocked repository simulates the
    // `recordPayment` / `deletePayment` side-effects.
    final supplierId = await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(name: 'S', currencyId: 1),
        );
    final purchaseId = await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-T-1',
            supplierId: supplierId,
            currencyId: 1,
            subtotalCents: Decimal.fromInt(59394),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(59394),
            paymentMethod: const Value('cheque'),
            status: const Value('posted'),
          ),
        );
    final paymentId = await db.into(db.purchasePayments).insert(
          PurchasePaymentsCompanion.insert(
            purchaseId: purchaseId,
            amountCents: Decimal.fromInt(59394),
            currencyId: 1,
            paymentMethod: 'cheque',
          ),
        );

    when(() => purchaseRepo.getPurchaseById(purchaseId))
        .thenAnswer((_) async => buildPurchase(id: purchaseId));
    when(() => purchaseRepo.recordPayment(
          purchaseId: any(named: 'purchaseId'),
          currencyId: any(named: 'currencyId'),
          amountCents: any(named: 'amountCents'),
          paymentMethod: any(named: 'paymentMethod'),
          notes: any(named: 'notes'),
          paymentDate: any(named: 'paymentDate'),
        )).thenAnswer((_) async => paymentId);
    when(() => purchaseRepo.deletePayment(paymentId))
        .thenAnswer((_) async {});

    await service.markCleared(
      sourceTable: ChequeSourceTables.purchase,
      sourceId: purchaseId,
    );

    final bounced = await service.markBounced(
      sourceTable: ChequeSourceTables.purchase,
      sourceId: purchaseId,
      bounceReason: 'NSF',
    );

    expect(bounced.status, ChequeConfirmationStatus.bounced);
    expect(bounced.reversedAmountCents, 59394);
    verify(() => purchaseRepo.deletePayment(paymentId)).called(1);

    // Sidecar row is now bounced, cleared_payment_id was NULLed, and
    // bounceReason was captured for audit.
    final row = await dao.getBySource(
      sourceTable: ChequeSourceTables.purchase,
      sourceId: purchaseId,
    );
    expect(row!.status, ChequeConfirmationStatus.bounced);
    expect(row.clearedPaymentId, isNull);
    expect(row.bounceReason, 'NSF');
  });

  test('markBounced requires a non-empty reason', () async {
    expect(
      () => service.markBounced(
        sourceTable: ChequeSourceTables.sale,
        sourceId: 1,
        bounceReason: '   ',
      ),
      throwsArgumentError,
    );
  });

  // ── 5. cleared → cancelled reverses the prior settlement ──────────────

  test('markCancelled after markCleared reverses the settlement payment',
      () async {
    final customerId = await db.into(db.customers).insert(
          CustomersCompanion.insert(name: 'C', currencyId: 1),
        );
    final saleId = await db.into(db.sales).insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-T-1',
            customerId: Value(customerId),
            currencyId: 1,
            subtotalCents: Decimal.fromInt(5000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(5000),
            paymentMethod: 'cheque',
            status: const Value('completed'),
          ),
        );
    final paymentId = await db.into(db.salePayments).insert(
          SalePaymentsCompanion.insert(
            saleId: saleId,
            amountCents: Decimal.fromInt(5000),
            currencyId: 1,
            paymentMethod: 'cheque',
          ),
        );

    when(() => saleRepo.getSaleById(saleId)).thenAnswer(
        (_) async => buildSale(id: saleId, totalCents: 5000));
    when(() => saleRepo.recordPayment(
          saleId: any(named: 'saleId'),
          amountCents: any(named: 'amountCents'),
          currencyId: any(named: 'currencyId'),
          paymentMethod: any(named: 'paymentMethod'),
          notes: any(named: 'notes'),
          paymentDate: any(named: 'paymentDate'),
        )).thenAnswer((_) async => paymentId);
    when(() => saleRepo.deletePayment(paymentId)).thenAnswer((_) async {});

    await service.markCleared(
      sourceTable: ChequeSourceTables.sale,
      sourceId: saleId,
    );
    final cancelled = await service.markCancelled(
      sourceTable: ChequeSourceTables.sale,
      sourceId: saleId,
    );

    expect(cancelled.status, ChequeConfirmationStatus.cancelled);
    expect(cancelled.reversedAmountCents, 5000);
    verify(() => saleRepo.deletePayment(paymentId)).called(1);

    final row = await dao.getBySource(
      sourceTable: ChequeSourceTables.sale,
      sourceId: saleId,
    );
    expect(row!.status, ChequeConfirmationStatus.cancelled);
    expect(row.clearedPaymentId, isNull);
  });

  // ── 6. pending → bounced does NOT call deletePayment ──────────────────

  test('markBounced from pending — no payment was created, so no reversal',
      () async {
    final result = await service.markBounced(
      sourceTable: ChequeSourceTables.purchase,
      sourceId: 42,
      bounceReason: 'NSF',
    );

    expect(result.status, ChequeConfirmationStatus.bounced);
    expect(result.reversedAmountCents, isNull);
    verifyNever(() => purchaseRepo.deletePayment(any()));
  });

  // ── 7. unknown source on settle path raises a typed exception ─────────

  test('markCleared throws when the source document is missing', () async {
    const purchaseId = 999;
    when(() => purchaseRepo.getPurchaseById(purchaseId))
        .thenAnswer((_) async => null);

    expect(
      () => service.markCleared(
        sourceTable: ChequeSourceTables.purchase,
        sourceId: purchaseId,
      ),
      throwsA(isA<ChequeSourceNotFoundException>()),
    );
  });
}
