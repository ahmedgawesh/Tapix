import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';
import 'package:tapix/core/database/daos/cheque_instrument_dao.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/cheque_management_service.dart';
import 'package:tapix/features/purchases/domain/repositories/purchase_repository.dart';
import 'package:tapix/features/sales/domain/entities/sale_entity.dart';
import 'package:tapix/features/sales/domain/repositories/sale_repository.dart';

class _SaleRepository extends Mock implements SaleRepository {}

class _PurchaseRepository extends Mock implements PurchaseRepository {}

void main() {
  late AppDatabase db;
  late ChequeInstrumentDao instruments;
  late _SaleRepository sales;
  late _PurchaseRepository purchases;
  late ChequeManagementService service;

  setUpAll(() {
    registerFallbackValue(Decimal.zero);
    registerFallbackValue(DateTime(2026, 1, 1));
  });

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.seedInitialDataForTest();
    instruments = ChequeInstrumentDao(db);
    sales = _SaleRepository();
    purchases = _PurchaseRepository();
    service = ChequeManagementService(
      db: db,
      instrumentDao: instruments,
      saleRepository: sales,
      purchaseRepository: purchases,
      auditLogService: AuditLogService(db),
    );
    when(
      () => sales.recordPayment(
        saleId: any(named: 'saleId'),
        amountCents: any(named: 'amountCents'),
        currencyId: any(named: 'currencyId'),
        paymentMethod: any(named: 'paymentMethod'),
        reference: any(named: 'reference'),
        notes: any(named: 'notes'),
        paymentDate: any(named: 'paymentDate'),
      ),
    ).thenAnswer((_) async => 501);
    when(
      () => purchases.recordPayment(
        purchaseId: any(named: 'purchaseId'),
        amountCents: any(named: 'amountCents'),
        currencyId: any(named: 'currencyId'),
        paymentMethod: any(named: 'paymentMethod'),
        reference: any(named: 'reference'),
        notes: any(named: 'notes'),
        paymentDate: any(named: 'paymentDate'),
      ),
    ).thenAnswer((_) async => 601);
  });

  tearDown(() => db.close());

  SaleEntity sale({int total = 10000, int paid = 0}) => SaleEntity(
    id: 10,
    invoiceNumber: 'SI-PARTIAL',
    customerId: 3,
    subtotalCents: Decimal.fromInt(total),
    taxCents: Decimal.zero,
    discountCents: Decimal.zero,
    totalCents: Decimal.fromInt(total),
    paidAmountCents: Decimal.fromInt(paid),
    currencyId: 1,
    paymentMethod: 'credit',
    status: 'completed',
    saleDate: DateTime(2026, 9, 1),
    createdAt: DateTime(2026, 9, 1),
    updatedAt: DateTime(2026, 9, 1),
  );

  ChequeOutstandingDocument saleDocument({int outstanding = 10000}) =>
      ChequeOutstandingDocument(
        sourceTable: ChequeSourceTables.sale,
        sourceId: 10,
        referenceNumber: 'SI-PARTIAL',
        partyName: 'Customer',
        partyId: 3,
        currencyId: 1,
        currencyCode: 'USD',
        currencySymbol: r'$',
        outstandingCents: outstanding,
      );

  test('partial sale cheque stays pending without creating a payment', () async {
    when(() => sales.getSaleById(10)).thenAnswer((_) async => sale());

    final id = await service.createPartialCheque(
      document: saleDocument(),
      amountCents: 3500,
      chequeNumber: 'CHK-3500',
      bankName: 'Test Bank',
      accountNumber: 'A-1',
      issueDate: DateTime(2026, 9, 2),
      dueDate: DateTime(2026, 9, 20),
    );

    final cheque = await instruments.getById(id);
    expect(cheque, isNotNull);
    expect(cheque!.amountCents, Decimal.fromInt(3500));
    expect(cheque.settlementPaymentId, isNull);
    expect(cheque.chequeNumber, 'CHK-3500');
    expect(cheque.status, ChequeInstrumentStatus.received);
    verifyNever(
      () => sales.recordPayment(
        saleId: 10,
        amountCents: Decimal.fromInt(3500),
        currencyId: 1,
        paymentMethod: 'cheque',
        reference: 'CHK-3500',
        notes: 'Incoming cheque received',
        paymentDate: DateTime(2026, 9, 2),
      ),
    );

    final audit = await db
        .customSelect(
          "SELECT COUNT(*) AS c FROM audit_logs WHERE target_table = 'cheque_instrument' AND record_id = ?",
          variables: [Variable.withInt(id)],
        )
        .getSingle();
    expect(audit.read<int>('c'), 1);
  });

  test('partial cheque cannot exceed live outstanding balance', () async {
    when(
      () => sales.getSaleById(10),
    ).thenAnswer((_) async => sale(total: 10000, paid: 8000));

    await expectLater(
      service.createPartialCheque(
        document: saleDocument(outstanding: 10000),
        amountCents: 2500,
        chequeNumber: 'TOO-MUCH',
        issueDate: DateTime(2026, 9, 2),
        dueDate: DateTime(2026, 9, 20),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'cheque_amount_exceeds_outstanding',
        ),
      ),
    );
    verifyNever(
      () => sales.recordPayment(
        saleId: any(named: 'saleId'),
        amountCents: any(named: 'amountCents'),
        currencyId: any(named: 'currencyId'),
        paymentMethod: any(named: 'paymentMethod'),
        reference: any(named: 'reference'),
        notes: any(named: 'notes'),
        paymentDate: any(named: 'paymentDate'),
      ),
    );
  });

  test('open cheque allocations cannot exceed the same live balance', () async {
    when(() => sales.getSaleById(10)).thenAnswer((_) async => sale());

    await service.createPartialCheque(
      document: saleDocument(),
      amountCents: 7000,
      chequeNumber: 'ALLOC-7000',
      issueDate: DateTime(2026, 9, 2),
      dueDate: DateTime(2026, 9, 20),
    );

    await expectLater(
      service.createPartialCheque(
        document: saleDocument(),
        amountCents: 4000,
        chequeNumber: 'ALLOC-4000',
        issueDate: DateTime(2026, 9, 2),
        dueDate: DateTime(2026, 9, 20),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'cheque_amount_exceeds_outstanding',
        ),
      ),
    );
  });

  test('same cheque number is rejected for the same bank account', () async {
    when(() => sales.getSaleById(10)).thenAnswer((_) async => sale());
    await instruments.create(
      direction: ChequeDirectionValue.incoming,
      sourceTable: ChequeSourceTables.sale,
      sourceId: 99,
      amountCents: 1000,
      currencyId: 1,
      dueDate: DateTime(2026, 9, 20),
      chequeNumber: 'DUP-1',
      bankName: 'Same Bank',
      accountNumber: '123',
    );

    await expectLater(
      service.createPartialCheque(
        document: saleDocument(),
        amountCents: 1000,
        chequeNumber: 'dup-1',
        bankName: 'same bank',
        accountNumber: '123',
        issueDate: DateTime(2026, 9, 2),
        dueDate: DateTime(2026, 9, 20),
      ),
      throwsA(isA<StateError>()),
    );
    verifyNever(
      () => sales.recordPayment(
        saleId: any(named: 'saleId'),
        amountCents: any(named: 'amountCents'),
        currencyId: any(named: 'currencyId'),
        paymentMethod: any(named: 'paymentMethod'),
        reference: any(named: 'reference'),
        notes: any(named: 'notes'),
        paymentDate: any(named: 'paymentDate'),
      ),
    );
  });

  test(
    'outstanding register includes both posted sales and purchases',
    () async {
      final customerId = await db
          .into(db.customers)
          .insert(CustomersCompanion.insert(name: 'C', currencyId: 1));
      final supplierId = await db
          .into(db.suppliers)
          .insert(SuppliersCompanion.insert(name: 'S', currencyId: 1));
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNumber: 'SI-OPEN',
              customerId: Value(customerId),
              subtotalCents: Decimal.fromInt(5000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(5000),
              paidAmountCents: Value(Decimal.fromInt(1000)),
              currencyId: 1,
              paymentMethod: 'credit',
            ),
          );
      await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'PO-OPEN',
              supplierId: supplierId,
              subtotalCents: Decimal.fromInt(7000),
              taxCents: Decimal.zero,
              totalCents: Decimal.fromInt(7000),
              paidAmountCents: Value(Decimal.fromInt(2000)),
              currencyId: 1,
              status: const Value('posted'),
            ),
          );

      final rows = await service.watchOutstandingDocuments().first;
      expect(
        rows.map((e) => e.referenceNumber),
        containsAll(['SI-OPEN', 'PO-OPEN']),
      );
      expect(
        rows.firstWhere((e) => e.referenceNumber == 'SI-OPEN').outstandingCents,
        4000,
      );
      expect(
        rows.firstWhere((e) => e.referenceNumber == 'PO-OPEN').outstandingCents,
        5000,
      );
    },
  );

  test('supplier due reminder follows the physical cheque lifecycle', () async {
    final supplierId = await db
        .into(db.suppliers)
        .insert(SuppliersCompanion.insert(name: 'Due supplier', currencyId: 1));
    final purchaseId = await db
        .into(db.purchases)
        .insert(
          PurchasesCompanion.insert(
            purchaseNumber: 'PO-CHEQUE-DUE',
            supplierId: supplierId,
            subtotalCents: Decimal.fromInt(10000),
            taxCents: Decimal.zero,
            totalCents: Decimal.fromInt(10000),
            paidAmountCents: Value(Decimal.zero),
            currencyId: 1,
            paymentMethod: const Value('cheque'),
            status: const Value('posted'),
            dueDate: Value(DateTime(2026, 9, 9)),
          ),
        );
    final chequeId = await instruments.create(
      direction: ChequeDirectionValue.outgoing,
      sourceTable: ChequeSourceTables.purchase,
      sourceId: purchaseId,
      amountCents: 10000,
      currencyId: 1,
      dueDate: DateTime(2026, 9, 9),
      partyType: 'supplier',
      partyId: supplierId,
      chequeNumber: 'DUE-1',
    );

    expect(
      await db.purchaseDao.watchUpcomingDuePurchases(supplierId).first,
      hasLength(1),
    );

    await instruments.writeLifecycle(
      id: chequeId,
      status: ChequeInstrumentStatus.bounced,
      bounceReason: 'Rejected by bank',
    );

    expect(
      await db.purchaseDao.watchUpcomingDuePurchases(supplierId).first,
      isEmpty,
    );
  });
}
