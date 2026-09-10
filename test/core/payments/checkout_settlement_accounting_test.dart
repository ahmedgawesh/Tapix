import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/adjustment_return_dao.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';
import 'package:tapix/core/database/daos/cheque_instrument_dao.dart';
import 'package:tapix/core/payments/checkout_settlement.dart';
import 'package:tapix/core/services/audit_log_service.dart';
import 'package:tapix/core/services/commissions/commission_service.dart';
import 'package:tapix/core/services/cheque_lifecycle_service.dart';
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

class _SessionService extends Mock implements SessionService {}

void main() {
  late AppDatabase db;
  late JournalEntryService journal;
  late _SessionService session;
  late SaleRepositoryImpl sales;
  late PurchaseRepositoryImpl purchases;
  late ChequeLifecycleService lifecycle;
  late int currencyId;
  late int productId;
  late int userId;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.seedInitialDataForTest();
    currencyId = (await (db.select(
      db.currencies,
    )..where((row) => row.isBase.equals(true))).getSingle()).id;
    userId = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            username: 'settlement-test',
            passwordHash: 'test-only',
            role: 'owner',
            createdAt: DateTime(2026, 9, 7),
            updatedAt: DateTime(2026, 9, 7),
          ),
        );
    session = _SessionService();
    when(() => session.getCurrentUserId()).thenAnswer((_) async => userId);

    journal = JournalEntryService(AccountingRepository(db));
    final audit = AuditLogService(db);
    final loyalty = LoyaltyRepositoryImpl(db, journal);
    sales = SaleRepositoryImpl(
      SaleLocalDatasourceImpl(db.saleDao, AdjustmentReturnDao(db)),
      db.saleDao,
      journal,
      audit,
      session,
      loyalty,
      CommissionService(db.employeeDao),
      LoyaltyPointsService(loyalty, journal, db),
    );
    purchases = PurchaseRepositoryImpl(
      PurchaseLocalDatasourceImpl(db.purchaseDao, AdjustmentReturnDao(db)),
      audit,
      session,
      journal,
      db,
    );
    lifecycle = ChequeLifecycleService(
      db: db,
      confirmationDao: ChequeConfirmationDao(db),
      instrumentDao: ChequeInstrumentDao(db),
      purchaseRepository: purchases,
      saleRepository: sales,
      journalEntryService: journal,
      auditLogService: audit,
    );

    productId = await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            sku: const Value('SETTLEMENT-1'),
            name: 'Settlement item',
            costCents: Decimal.fromInt(6000),
            priceCents: Decimal.fromInt(10000),
            currencyId: Value(currencyId),
            stockQuantity: const Value(20),
          ),
        );
    await db
        .into(db.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            productId: productId,
            stockQuantity: const Value(20),
            costCents: Decimal.fromInt(6000),
            priceCents: Decimal.fromInt(10000),
          ),
        );
  });

  tearDown(() => db.close());

  final allocations = [
    CheckoutPaymentAllocation(
      method: 'cheque',
      amountCents: 4000,
      reference: 'CHK-4000',
      bankName: 'Test Bank',
      issueDate: DateTime(2026, 9, 7),
      dueDate: DateTime(2026, 10, 7),
    ),
    const CheckoutPaymentAllocation(method: 'cash', amountCents: 3000),
  ];

  Future<int> accountNet(
    String sourceTable,
    int sourceId,
    String accountCode,
  ) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(SUM(jel.debit_cents - jel.credit_cents), 0) AS net '
          'FROM journal_entries je '
          'JOIN journal_entry_lines jel ON jel.journal_entry_id = je.id '
          'JOIN accounts a ON a.id = jel.account_id '
          'WHERE je.source_table = ? AND je.source_id = ? '
          "AND je.status = 'posted' AND je.is_reversed = 0 "
          'AND a.account_code = ?',
          variables: [
            Variable.withString(sourceTable),
            Variable.withInt(sourceId),
            Variable.withString(accountCode),
          ],
        )
        .getSingle();
    return row.read<int>('net');
  }

  test('settlement allocates a cheque without counting it as paid', () {
    final settlement = CheckoutSettlement(allocations);
    settlement.validate(invoiceTotalCents: 10000);
    expect(settlement.totalAllocatedCents, 7000);
    expect(settlement.totalSettledCents, 3000);
    expect(settlement.totalPaidCents, 3000);
    expect(settlement.headerPaymentMethod, 'mixed');
  });

  test('sale records a cheque payment only after bank clearance', () async {
    final customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(name: 'Customer', currencyId: currencyId),
        );
    final saleId = await sales.createSale(
      customerId: customerId,
      currencyId: currencyId,
      subtotalCents: Decimal.fromInt(10000),
      discountCents: Decimal.zero,
      taxCents: Decimal.zero,
      totalCents: Decimal.fromInt(10000),
      paidAmountCents: Decimal.fromInt(3000),
      paymentMethod: 'mixed',
      items: [
        SaleItemInput(
          lineId: 'settlement-line-1',
          productId: productId,
          quantity: 1,
          unitPriceCents: Decimal.fromInt(10000),
          subtotalCents: Decimal.fromInt(10000),
          discountCents: Decimal.zero,
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(10000),
        ),
      ],
      actorUserId: userId,
      initialPayments: allocations,
    );

    final sale = await (db.select(
      db.sales,
    )..where((row) => row.id.equals(saleId))).getSingle();
    final customer = await (db.select(
      db.customers,
    )..where((row) => row.id.equals(customerId))).getSingle();
    final payments = await db.saleDao.getSalePayments(saleId);
    final cheques = await (db.select(
      db.chequeInstruments,
    )..where((row) => row.sourceId.equals(saleId))).get();
    expect(sale.paidAmountCents, Decimal.fromInt(3000));
    expect(customer.balanceCents, Decimal.fromInt(7000));
    expect(payments.map((row) => row.paymentMethod), ['cash']);
    expect(cheques.single.amountCents, Decimal.fromInt(4000));
    expect(cheques.single.chequeNumber, 'CHK-4000');
    expect(cheques.single.settlementPaymentId, isNull);
    final cashPayment = payments.singleWhere(
      (row) => row.paymentMethod == 'cash',
    );
    expect(await accountNet('sales', saleId, '1100'), 10000);
    expect(await accountNet('sale_payments', cashPayment.id, '1000'), 3000);
    expect(
      await accountNet('cheque_instruments', cheques.single.id, '1020'),
      0,
    );

    final cleared = await lifecycle.markCleared(
      sourceTable: ChequeSourceTables.sale,
      sourceId: saleId,
    );
    expect(cleared.settledAmountCents, 4000);
    final clearedSale = await (db.select(
      db.sales,
    )..where((row) => row.id.equals(saleId))).getSingle();
    final clearedCustomer = await (db.select(
      db.customers,
    )..where((row) => row.id.equals(customerId))).getSingle();
    final clearedPayment = (await db.saleDao.getSalePayments(
      saleId,
    )).singleWhere((row) => row.paymentMethod == 'cheque');
    expect(clearedSale.paidAmountCents, Decimal.fromInt(7000));
    expect(clearedCustomer.balanceCents, Decimal.fromInt(3000));
    expect(await accountNet('sale_payments', clearedPayment.id, '1020'), 4000);
    expect(
      await accountNet('cheque_instruments', cheques.single.id, '1010'),
      4000,
    );
    expect(
      await accountNet('cheque_instruments', cheques.single.id, '1020'),
      -4000,
    );

    await lifecycle.markBounced(
      sourceTable: ChequeSourceTables.sale,
      sourceId: saleId,
      bounceReason: 'Test bounce',
    );
    final bouncedSale = await (db.select(
      db.sales,
    )..where((row) => row.id.equals(saleId))).getSingle();
    final bouncedCustomer = await (db.select(
      db.customers,
    )..where((row) => row.id.equals(customerId))).getSingle();
    expect(bouncedSale.paidAmountCents, Decimal.fromInt(7000));
    expect(bouncedCustomer.balanceCents, Decimal.fromInt(7000));
    final bouncedCheque = await ChequeInstrumentDao(
      db,
    ).getById(cheques.single.id);
    expect(bouncedCheque?.settlementPaymentId, clearedPayment.id);
    expect(
      await accountNet('cheque_instruments', cheques.single.id, '1030'),
      4000,
    );
    expect(
      await accountNet('cheque_instruments', cheques.single.id, '1020'),
      -4000,
    );

    final resolution = await lifecycle.resolveBounced(
      instrumentId: cheques.single.id,
      resolutionType: ChequeResolutionType.cash,
      note: 'Collected in cash',
      userId: userId,
    );
    final resolvedCheque = await ChequeInstrumentDao(
      db,
    ).getById(cheques.single.id);
    final resolvedCustomer = await (db.select(
      db.customers,
    )..where((row) => row.id.equals(customerId))).getSingle();
    expect(resolution.journalEntryId, isNotNull);
    expect(resolvedCheque?.resolutionType, ChequeResolutionType.cash);
    expect(resolvedCheque?.resolvedAt, isNotNull);
    expect(resolvedCustomer.balanceCents, Decimal.fromInt(3000));
    expect(
      await accountNet('cheque_instruments', cheques.single.id, '1030'),
      0,
    );
    expect(
      await accountNet('cheque_instruments', cheques.single.id, '1000'),
      4000,
    );
    await expectLater(
      lifecycle.resolveBounced(
        instrumentId: cheques.single.id,
        resolutionType: ChequeResolutionType.cash,
        userId: userId,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('purchase records a cheque payment only after bank clearance', () async {
    final supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(name: 'Supplier', currencyId: currencyId),
        );
    final purchaseId = await purchases.createPurchase(
      supplierId: supplierId,
      currencyId: currencyId,
      subtotalCents: Decimal.fromInt(10000),
      discountCents: Decimal.zero,
      taxCents: Decimal.zero,
      totalCents: Decimal.fromInt(10000),
      paidAmountCents: Decimal.fromInt(3000),
      paymentMethod: 'mixed',
      items: [
        PurchaseItemInput(
          productId: productId,
          quantity: 1,
          unitCostCents: Decimal.fromInt(10000),
          discountCents: Decimal.zero,
          subtotalCents: Decimal.fromInt(10000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(10000),
        ),
      ],
      initialPayments: allocations,
    );
    await purchases.postPurchase(purchaseId);

    final purchase = await (db.select(
      db.purchases,
    )..where((row) => row.id.equals(purchaseId))).getSingle();
    final supplier = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingle();
    final payments = await db.purchaseDao.getPurchasePayments(purchaseId);
    final cheques =
        await (db.select(db.chequeInstruments)..where(
              (row) =>
                  row.sourceTable.equals('purchase') &
                  row.sourceId.equals(purchaseId),
            ))
            .get();
    final ledger = await (db.select(
      db.supplierTransactions,
    )..where((row) => row.referenceType.equals('purchase_payment'))).get();
    expect(purchase.paidAmountCents, Decimal.fromInt(3000));
    expect(supplier.balanceCents, Decimal.fromInt(7000));
    expect(payments.map((row) => row.paymentMethod), ['cash']);
    expect(cheques.single.amountCents, Decimal.fromInt(4000));
    expect(cheques.single.settlementPaymentId, isNull);
    expect(ledger, hasLength(1));
    final cashPayment = payments.singleWhere(
      (row) => row.paymentMethod == 'cash',
    );
    expect(await accountNet('purchases', purchaseId, '2000'), -10000);
    expect(
      await accountNet('purchase_payments', cashPayment.id, '1000'),
      -3000,
    );
    expect(
      await accountNet('cheque_instruments', cheques.single.id, '2020'),
      0,
    );

    final cleared = await lifecycle.markCleared(
      sourceTable: ChequeSourceTables.purchase,
      sourceId: purchaseId,
    );
    expect(cleared.settledAmountCents, 4000);
    final clearedPurchase = await (db.select(
      db.purchases,
    )..where((row) => row.id.equals(purchaseId))).getSingle();
    final clearedSupplier = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingle();
    final clearedPayment = (await db.purchaseDao.getPurchasePayments(
      purchaseId,
    )).singleWhere((row) => row.paymentMethod == 'cheque');
    expect(clearedPurchase.paidAmountCents, Decimal.fromInt(7000));
    expect(clearedSupplier.balanceCents, Decimal.fromInt(3000));
    expect(
      await accountNet('purchase_payments', clearedPayment.id, '2020'),
      -4000,
    );
    expect(
      await accountNet('cheque_instruments', cheques.single.id, '2020'),
      4000,
    );
    expect(
      await accountNet('cheque_instruments', cheques.single.id, '1010'),
      -4000,
    );

    await lifecycle.markBounced(
      sourceTable: ChequeSourceTables.purchase,
      sourceId: purchaseId,
      bounceReason: 'Stopped payment',
    );
    final bouncedPurchase = await (db.select(
      db.purchases,
    )..where((row) => row.id.equals(purchaseId))).getSingle();
    final bouncedSupplier = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingle();
    expect(bouncedPurchase.paidAmountCents, Decimal.fromInt(3000));
    expect(bouncedSupplier.balanceCents, Decimal.fromInt(7000));

    await lifecycle.resolveBounced(
      instrumentId: cheques.single.id,
      resolutionType: ChequeResolutionType.bank,
      note: 'Paid by transfer',
      userId: userId,
    );
    final resolvedPurchase = await (db.select(
      db.purchases,
    )..where((row) => row.id.equals(purchaseId))).getSingle();
    final resolvedSupplier = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingle();
    final resolvedCheque = await ChequeInstrumentDao(
      db,
    ).getById(cheques.single.id);
    expect(resolvedPurchase.paidAmountCents, Decimal.fromInt(7000));
    expect(resolvedSupplier.balanceCents, Decimal.fromInt(3000));
    expect(resolvedCheque?.resolutionType, ChequeResolutionType.bank);
    expect(resolvedCheque?.resolvedAt, isNotNull);
  });

  test('replacement cheque can be cancelled back to customer credit', () async {
    final customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'Pure cheque customer',
            currencyId: currencyId,
          ),
        );
    final saleId = await sales.createSale(
      customerId: customerId,
      currencyId: currencyId,
      subtotalCents: Decimal.fromInt(6500),
      discountCents: Decimal.zero,
      taxCents: Decimal.zero,
      totalCents: Decimal.fromInt(6500),
      paidAmountCents: Decimal.zero,
      paymentMethod: 'cheque',
      dueDate: DateTime(2026, 10, 7),
      items: [
        SaleItemInput(
          lineId: 'pure-sale-cheque',
          productId: productId,
          quantity: 1,
          unitPriceCents: Decimal.fromInt(6500),
          subtotalCents: Decimal.fromInt(6500),
          discountCents: Decimal.zero,
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(6500),
        ),
      ],
      actorUserId: userId,
    );

    final sale = await (db.select(
      db.sales,
    )..where((row) => row.id.equals(saleId))).getSingle();
    final customer = await (db.select(
      db.customers,
    )..where((row) => row.id.equals(customerId))).getSingle();
    final payments = await db.saleDao.getSalePayments(saleId);
    final cheque =
        await (db.select(db.chequeInstruments)..where(
              (row) =>
                  row.sourceTable.equals(ChequeSourceTables.sale) &
                  row.sourceId.equals(saleId),
            ))
            .getSingle();
    expect(sale.paidAmountCents, Decimal.zero);
    expect(customer.balanceCents, Decimal.fromInt(6500));
    expect(payments, isEmpty);
    expect(cheque.settlementPaymentId, isNull);
    expect(await accountNet('sales', saleId, '1100'), 6500);
    expect(await accountNet('cheque_instruments', cheque.id, '1020'), 0);

    await lifecycle.markBounced(
      sourceTable: ChequeSourceTables.sale,
      sourceId: saleId,
      instrumentId: cheque.id,
      bounceReason: 'Insufficient funds',
      userId: userId,
    );
    final resolution = await lifecycle.resolveBounced(
      instrumentId: cheque.id,
      resolutionType: ChequeResolutionType.replacement,
      replacementChequeNumber: 'REPL-6500',
      replacementBankName: 'Replacement Bank',
      replacementIssueDate: DateTime(2026, 9, 9),
      replacementDueDate: DateTime(2026, 10, 9),
      userId: userId,
    );
    final original = await ChequeInstrumentDao(db).getById(cheque.id);
    final replacement = await ChequeInstrumentDao(
      db,
    ).getById(resolution.replacementChequeId!);
    final afterReplacement = await (db.select(
      db.customers,
    )..where((row) => row.id.equals(customerId))).getSingle();
    expect(original?.resolutionType, ChequeResolutionType.replacement);
    expect(original?.replacementChequeId, replacement?.id);
    expect(replacement?.status, ChequeInstrumentStatus.received);
    expect(replacement?.chequeNumber, 'REPL-6500');
    expect(replacement?.settlementPaymentId, isNull);
    expect(afterReplacement.balanceCents, Decimal.fromInt(6500));
    expect(await accountNet('cheque_instruments', cheque.id, '1030'), 0);

    await lifecycle.markCancelled(
      sourceTable: ChequeSourceTables.sale,
      sourceId: saleId,
      instrumentId: replacement!.id,
      userId: userId,
    );
    final afterCancellation = await (db.select(
      db.customers,
    )..where((row) => row.id.equals(customerId))).getSingle();
    final cancelledReplacement = await ChequeInstrumentDao(
      db,
    ).getById(replacement.id);
    expect(cancelledReplacement?.status, ChequeInstrumentStatus.cancelled);
    expect(afterCancellation.balanceCents, Decimal.fromInt(6500));
    expect(await accountNet('cheque_instruments', replacement.id, '1100'), 0);
  });

  test('pure purchase cheque remains due until clearance', () async {
    final supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Pure cheque supplier',
            currencyId: currencyId,
          ),
        );
    final purchaseId = await purchases.createPurchase(
      supplierId: supplierId,
      currencyId: currencyId,
      subtotalCents: Decimal.fromInt(6550),
      discountCents: Decimal.zero,
      taxCents: Decimal.zero,
      totalCents: Decimal.fromInt(6550),
      paidAmountCents: Decimal.zero,
      paymentMethod: 'cheque',
      dueDate: DateTime(2026, 10, 7),
      items: [
        PurchaseItemInput(
          productId: productId,
          quantity: 1,
          unitCostCents: Decimal.fromInt(6550),
          discountCents: Decimal.zero,
          subtotalCents: Decimal.fromInt(6550),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(6550),
        ),
      ],
    );
    await purchases.postPurchase(purchaseId);

    final purchase = await (db.select(
      db.purchases,
    )..where((row) => row.id.equals(purchaseId))).getSingle();
    final supplier = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingle();
    final payments = await db.purchaseDao.getPurchasePayments(purchaseId);
    final cheque =
        await (db.select(db.chequeInstruments)..where(
              (row) =>
                  row.sourceTable.equals(ChequeSourceTables.purchase) &
                  row.sourceId.equals(purchaseId),
            ))
            .getSingle();
    expect(purchase.paidAmountCents, Decimal.zero);
    expect(supplier.balanceCents, Decimal.fromInt(6550));
    expect(payments, isEmpty);
    expect(cheque.settlementPaymentId, isNull);
    expect(await accountNet('purchases', purchaseId, '2000'), -6550);
    expect(await accountNet('cheque_instruments', cheque.id, '2020'), 0);

    final cleared = await lifecycle.markCleared(
      sourceTable: ChequeSourceTables.purchase,
      sourceId: purchaseId,
      instrumentId: cheque.id,
      userId: userId,
    );
    expect(cleared.settledAmountCents, 6550);
    final afterClear = await (db.select(
      db.purchases,
    )..where((row) => row.id.equals(purchaseId))).getSingle();
    final supplierAfterClear = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingle();
    final paymentsAfterClear = await db.purchaseDao.getPurchasePayments(
      purchaseId,
    );
    expect(afterClear.paidAmountCents, Decimal.fromInt(6550));
    expect(supplierAfterClear.balanceCents, Decimal.zero);
    expect(paymentsAfterClear, hasLength(1));
  });

  test('two cheques on one purchase post as independent instruments', () async {
    final supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Two cheque supplier',
            currencyId: currencyId,
          ),
        );
    final twoCheques = [
      CheckoutPaymentAllocation(
        method: 'cheque',
        amountCents: 4000,
        reference: 'PCHK-A',
        dueDate: DateTime(2026, 10, 7),
      ),
      CheckoutPaymentAllocation(
        method: 'cheque',
        amountCents: 3000,
        reference: 'PCHK-B',
        dueDate: DateTime(2026, 11, 7),
      ),
    ];
    final purchaseId = await purchases.createPurchase(
      supplierId: supplierId,
      currencyId: currencyId,
      subtotalCents: Decimal.fromInt(10000),
      discountCents: Decimal.zero,
      taxCents: Decimal.zero,
      totalCents: Decimal.fromInt(10000),
      paidAmountCents: Decimal.zero,
      paymentMethod: 'cheque',
      dueDate: DateTime(2026, 11, 7),
      items: [
        PurchaseItemInput(
          productId: productId,
          quantity: 1,
          unitCostCents: Decimal.fromInt(10000),
          discountCents: Decimal.zero,
          subtotalCents: Decimal.fromInt(10000),
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(10000),
        ),
      ],
      initialPayments: twoCheques,
    );

    await purchases.postPurchase(purchaseId);

    final purchase = await (db.select(
      db.purchases,
    )..where((row) => row.id.equals(purchaseId))).getSingle();
    final supplier = await (db.select(
      db.suppliers,
    )..where((row) => row.id.equals(supplierId))).getSingle();
    final payments = await db.purchaseDao.getPurchasePayments(purchaseId);
    final instruments = await ChequeInstrumentDao(db).getBySource(
      sourceTable: ChequeSourceTables.purchase,
      sourceId: purchaseId,
    );

    expect(purchase.status, 'posted');
    expect(purchase.paidAmountCents, Decimal.zero);
    expect(supplier.balanceCents, Decimal.fromInt(10000));
    expect(payments, isEmpty);
    expect(instruments, hasLength(2));
    expect(instruments.map((row) => row.chequeNumber).toSet(), {
      'PCHK-A',
      'PCHK-B',
    });
    expect(instruments.every((row) => row.settlementPaymentId == null), isTrue);

    final firstInstrument = instruments.singleWhere(
      (row) => row.chequeNumber == 'PCHK-A',
    );
    await lifecycle.markCleared(
      sourceTable: ChequeSourceTables.purchase,
      sourceId: purchaseId,
      instrumentId: firstInstrument.id,
      userId: userId,
    );
    final afterFirstClear = await (db.select(
      db.purchases,
    )..where((row) => row.id.equals(purchaseId))).getSingle();
    expect(afterFirstClear.paidAmountCents, Decimal.fromInt(4000));
    expect(await db.purchaseDao.getPurchasePayments(purchaseId), hasLength(1));
  });

  test('two cheques on one sale keep independent lifecycles', () async {
    final customerId = await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            name: 'Two cheque customer',
            currencyId: currencyId,
          ),
        );
    final twoCheques = [
      CheckoutPaymentAllocation(
        method: 'cheque',
        amountCents: 4000,
        reference: 'CHK-A',
        dueDate: DateTime(2026, 10, 7),
      ),
      CheckoutPaymentAllocation(
        method: 'cheque',
        amountCents: 3000,
        reference: 'CHK-B',
        dueDate: DateTime(2026, 11, 7),
      ),
    ];
    final saleId = await sales.createSale(
      customerId: customerId,
      currencyId: currencyId,
      subtotalCents: Decimal.fromInt(10000),
      discountCents: Decimal.zero,
      taxCents: Decimal.zero,
      totalCents: Decimal.fromInt(10000),
      paidAmountCents: Decimal.zero,
      paymentMethod: 'cheque',
      items: [
        SaleItemInput(
          lineId: 'two-cheque-line',
          productId: productId,
          quantity: 1,
          unitPriceCents: Decimal.fromInt(10000),
          subtotalCents: Decimal.fromInt(10000),
          discountCents: Decimal.zero,
          taxCents: Decimal.zero,
          totalCents: Decimal.fromInt(10000),
        ),
      ],
      actorUserId: userId,
      initialPayments: twoCheques,
    );
    final instruments =
        await (db.select(db.chequeInstruments)..where(
              (row) =>
                  row.sourceTable.equals(ChequeSourceTables.sale) &
                  row.sourceId.equals(saleId),
            ))
            .get();
    expect(instruments, hasLength(2));

    final second = instruments.singleWhere(
      (instrument) => instrument.chequeNumber == 'CHK-B',
    );
    await lifecycle.markCleared(
      sourceTable: ChequeSourceTables.sale,
      sourceId: saleId,
      instrumentId: second.id,
      userId: userId,
    );

    final first = instruments.singleWhere(
      (instrument) => instrument.chequeNumber == 'CHK-A',
    );
    await lifecycle.markBounced(
      sourceTable: ChequeSourceTables.sale,
      sourceId: saleId,
      instrumentId: first.id,
      bounceReason: 'Insufficient funds',
      userId: userId,
    );

    final sale = await (db.select(
      db.sales,
    )..where((row) => row.id.equals(saleId))).getSingle();
    final customer = await (db.select(
      db.customers,
    )..where((row) => row.id.equals(customerId))).getSingle();
    final resolved = await ChequeInstrumentDao(
      db,
    ).getBySource(sourceTable: ChequeSourceTables.sale, sourceId: saleId);
    expect(sale.paidAmountCents, Decimal.fromInt(3000));
    expect(customer.balanceCents, Decimal.fromInt(7000));
    expect(
      resolved.singleWhere((c) => c.chequeNumber == 'CHK-A').status,
      ChequeInstrumentStatus.bounced,
    );
    expect(
      resolved.singleWhere((c) => c.chequeNumber == 'CHK-B').status,
      ChequeInstrumentStatus.cleared,
    );
    final bouncedInstrument = resolved.singleWhere(
      (c) => c.chequeNumber == 'CHK-A',
    );
    expect(bouncedInstrument.settlementPaymentId, isNull);
    expect(
      await accountNet('cheque_instruments', bouncedInstrument.id, '1030'),
      4000,
    );
  });
}
