// Pins the customer-profile "Store Credit" visibility contract.
//
// Credit-refund adjustment returns settle to GL 2400 Customer Credit
// Liability and are tracked in `customer_credit_notes`; they deliberately
// never touch `customer_transactions` (keeps AR / 1100 clean). Before this
// fix the customer profile only rendered `customer_transactions`, so such a
// store-credit note was invisible on the customer's page.
//
// `CustomerCreditNoteService.watchForCustomer` is the reactive source that
// powers the new `_StoreCreditSection`. This test verifies it:
//   1. Emits non-voided notes for the customer (newest first).
//   2. Excludes voided notes.
//   3. Excludes other customers' notes.
//   4. Reacts to inserts.
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/services/compliance/customer_credit_note_service.dart';
import 'package:tapix/features/accounting/data/repositories/accounting_repository.dart';

void main() {
  late AppDatabase db;
  late CustomerCreditNoteService service;
  late int currencyId;
  late int customerA;
  late int customerB;

  Decimal d(int n) => Decimal.fromInt(n);

  Future<int> insertNote({
    required int customerId,
    required String number,
    required int amount,
    String status = 'open',
    required DateTime issuedAt,
  }) {
    return db.into(db.customerCreditNotes).insert(
          CustomerCreditNotesCompanion.insert(
            noteNumber: number,
            customerId: customerId,
            currencyId: currencyId,
            originalAmountCents: d(amount),
            balanceCents: d(amount),
            status: Value(status),
            sourceTable: 'sale_return_adjustments',
            sourceId: 1,
            issuedAt: Value(issuedAt),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    service = CustomerCreditNoteService(
      db: db,
      accountingRepo: AccountingRepository(db),
    );
    currencyId = (await db.select(db.currencies).get()).first.id;
    customerA = await db.into(db.customers).insert(
          CustomersCompanion.insert(name: 'A', currencyId: currencyId),
        );
    customerB = await db.into(db.customers).insert(
          CustomersCompanion.insert(name: 'B', currencyId: currencyId),
        );
  });

  tearDown(() async => db.close());

  test('emits non-voided notes newest-first, excludes voided + other customers',
      () async {
    final base = DateTime(2026, 6, 30);
    await insertNote(
        customerId: customerA,
        number: 'CCN-1',
        amount: 20099,
        issuedAt: base);
    await insertNote(
        customerId: customerA,
        number: 'CCN-2',
        amount: 5000,
        status: 'partially_applied',
        issuedAt: base.add(const Duration(days: 1)));
    await insertNote(
        customerId: customerA,
        number: 'CCN-VOID',
        amount: 9999,
        status: 'voided',
        issuedAt: base.add(const Duration(days: 2)));
    await insertNote(
        customerId: customerB,
        number: 'CCN-OTHER',
        amount: 1234,
        issuedAt: base);

    final notes = await service.watchForCustomer(customerA).first;

    expect(notes.map((n) => n.noteNumber), ['CCN-2', 'CCN-1']);
    expect(notes.any((n) => n.status == 'voided'), isFalse);
    expect(notes.any((n) => n.customerId == customerB), isFalse);
  });

  test('reacts to a newly inserted note', () async {
    final stream = service.watchForCustomer(customerA);
    expect((await stream.first).isEmpty, isTrue);

    await insertNote(
        customerId: customerA,
        number: 'CCN-NEW',
        amount: 7000,
        issuedAt: DateTime(2026, 7, 1));

    final after = await stream.firstWhere((rows) => rows.isNotEmpty);
    expect(after.single.noteNumber, 'CCN-NEW');
    expect(after.single.balanceCents.toBigInt().toInt(), 7000);
  });
}
