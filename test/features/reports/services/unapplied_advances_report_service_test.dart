import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/core/database/daos/cheque_confirmation_dao.dart';
import 'package:tapix/core/database/daos/cheque_instrument_dao.dart';
import 'package:tapix/features/reports/services/unapplied_advances_report_service.dart';

void main() {
  late AppDatabase db;
  late ChequeInstrumentDao instruments;
  late UnappliedAdvancesReportService report;

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.seedInitialDataForTest();
    instruments = ChequeInstrumentDao(db);
    report = UnappliedAdvancesReportService(db);
  });

  tearDown(() => db.close());

  test(
    'reports only live unapplied values and summarizes by party type',
    () async {
      final customerId = await db
          .into(db.customers)
          .insert(CustomersCompanion.insert(name: 'Customer A', currencyId: 1));
      final supplierId = await db
          .into(db.suppliers)
          .insert(SuppliersCompanion.insert(name: 'Supplier A', currencyId: 1));

      final customerCheque = await _cheque(
        instruments,
        partyType: 'customer',
        partyId: customerId,
        direction: ChequeDirectionValue.incoming,
        number: 'C-ADV-1',
        amountCents: 10000,
      );
      final supplierCheque = await _cheque(
        instruments,
        partyType: 'supplier',
        partyId: supplierId,
        direction: ChequeDirectionValue.outgoing,
        number: 'S-ADV-1',
        amountCents: 5000,
      );
      final reversedCheque = await _cheque(
        instruments,
        partyType: 'customer',
        partyId: customerId,
        direction: ChequeDirectionValue.incoming,
        number: 'C-REVERSED',
        amountCents: 9000,
      );

      await db
          .into(db.partyAccountPayments)
          .insert(
            PartyAccountPaymentsCompanion.insert(
              chequeInstrumentId: customerCheque,
              partyType: 'customer',
              partyId: customerId,
              direction: ChequeDirectionValue.incoming,
              amountCents: Decimal.fromInt(10000),
              appliedCents: Value(Decimal.fromInt(3000)),
              currencyId: 1,
              status: const Value('partially_applied'),
              recognizedAt: DateTime(2026, 9, 10),
            ),
          );
      await db
          .into(db.partyAccountPayments)
          .insert(
            PartyAccountPaymentsCompanion.insert(
              chequeInstrumentId: supplierCheque,
              partyType: 'supplier',
              partyId: supplierId,
              direction: ChequeDirectionValue.outgoing,
              amountCents: Decimal.fromInt(5000),
              currencyId: 1,
              recognizedAt: DateTime(2026, 9, 11),
            ),
          );
      await db
          .into(db.partyAccountPayments)
          .insert(
            PartyAccountPaymentsCompanion.insert(
              chequeInstrumentId: reversedCheque,
              partyType: 'customer',
              partyId: customerId,
              direction: ChequeDirectionValue.incoming,
              amountCents: Decimal.fromInt(9000),
              currencyId: 1,
              status: const Value('reversed'),
              recognizedAt: DateTime(2026, 9, 12),
            ),
          );

      final rows = await report.getRows();
      expect(rows, hasLength(2));
      expect(rows.first.chequeNumber, 'S-ADV-1');
      expect(rows.last.unappliedCents, 7000);

      final summaries = report.summarize(rows);
      expect(summaries, hasLength(1));
      expect(summaries.single.customerCents, 7000);
      expect(summaries.single.supplierCents, 5000);
    },
  );
}

Future<int> _cheque(
  ChequeInstrumentDao instruments, {
  required String partyType,
  required int partyId,
  required String direction,
  required String number,
  required int amountCents,
}) => instruments.create(
  direction: direction,
  sourceTable: partyType == 'customer'
      ? ChequeSourceTables.customerAccount
      : ChequeSourceTables.supplierAccount,
  sourceId: partyId,
  amountCents: amountCents,
  currencyId: 1,
  dueDate: DateTime(2026, 9, 20),
  partyType: partyType,
  partyId: partyId,
  chequeNumber: number,
);
