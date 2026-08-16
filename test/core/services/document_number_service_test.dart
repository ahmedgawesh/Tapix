import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/document_number_service.dart';

void main() {
  late AppDatabase db;
  late DocumentNumberService numbers;

  setUp(() {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    numbers = DocumentNumberService(db, clock: () => DateTime(2026, 8, 15));
  });

  tearDown(() => db.close());

  test('uses the requested prefixes for every business document', () async {
    expect(await numbers.nextSaleInvoice(), 'SI-202608-000001');
    expect(await numbers.nextSaleReturn(), 'SR-202608-000001');
    expect(await numbers.nextSaleAdjustmentReturn(), 'SRS-202608-000001');
    expect(await numbers.nextPurchaseInvoice(), 'PI-202608-000001');
    expect(await numbers.nextPurchaseReturn(), 'PR-202608-000001');
    expect(await numbers.nextPurchaseAdjustmentReturn(), 'PRS-202608-000001');
    expect(await numbers.nextCustomerTransaction('CPC'), 'CPC-202608-000001');
    expect(await numbers.nextSupplierTransaction('CPS'), 'CPS-202608-000001');
    expect(await numbers.nextCustomerTransaction('DC'), 'DC-202608-000001');
    expect(await numbers.nextSupplierTransaction('DS'), 'DS-202608-000001');
  });

  test('sequence never reuses a number when no business row remains', () async {
    expect(await numbers.nextSaleInvoice(), 'SI-202608-000001');
    expect(await numbers.nextSaleInvoice(), 'SI-202608-000002');

    final rows = await db
        .customSelect(
          "SELECT last_number FROM document_sequences WHERE prefix = 'SI-2026'",
        )
        .getSingle();
    expect(rows.read<int>('last_number'), 2);
    expect(await numbers.nextSaleInvoice(), 'SI-202608-000003');
  });

  test('continues across months and restarts on a new year', () async {
    var now = DateTime(2026, 8, 15);
    final annual = DocumentNumberService(db, clock: () => now);

    expect(await annual.nextSaleInvoice(), 'SI-202608-000001');
    now = DateTime(2026, 12, 31);
    expect(await annual.nextSaleInvoice(), 'SI-202612-000002');
    now = DateTime(2027, 1, 1);
    expect(await annual.nextSaleInvoice(), 'SI-202701-000001');
  });

  test(
    'customer and supplier DAOs number cash and discounts correctly',
    () async {
      final currency = (await db.select(db.currencies).get()).first;
      final customerId = await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              name: 'Customer',
              currencyId: currency.id,
            ),
          );
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Supplier',
              currencyId: currency.id,
            ),
          );

      await db.customerDao.createTransaction(
        CustomerTransactionsCompanion.insert(
          customerId: customerId,
          transactionType: 'payment',
          amountCents: Decimal.fromInt(-100),
          currencyId: currency.id,
        ),
      );
      await db.customerDao.createTransaction(
        CustomerTransactionsCompanion.insert(
          customerId: customerId,
          transactionType: 'discount',
          amountCents: Decimal.fromInt(-10),
          currencyId: currency.id,
        ),
      );
      await db.supplierDao.createTransaction(
        SupplierTransactionsCompanion.insert(
          supplierId: supplierId,
          transactionType: 'payment',
          amountCents: Decimal.fromInt(-100),
          currencyId: currency.id,
        ),
      );
      await db.supplierDao.createTransaction(
        SupplierTransactionsCompanion.insert(
          supplierId: supplierId,
          transactionType: 'discount',
          amountCents: Decimal.fromInt(-10),
          currencyId: currency.id,
        ),
      );

      final customerTransactions = await db
          .select(db.customerTransactions)
          .get();
      final supplierTransactions = await db
          .select(db.supplierTransactions)
          .get();
      expect(
        customerTransactions.map((tx) => tx.transactionNumber),
        containsAll(<String?>['CPC-202608-000001', 'DC-202608-000001']),
      );
      expect(
        supplierTransactions.map((tx) => tx.transactionNumber),
        containsAll(<String?>['CPS-202608-000001', 'DS-202608-000001']),
      );
    },
  );
}
