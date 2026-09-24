import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:decimal/decimal.dart';
import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/reports/presentation/bloc/sales_tax_report_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/purchase_tax_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

/// Regression: the sales / purchase tax reports must aggregate the VAT of BOTH
/// linked (invoice-based) returns AND adjustment (unlinked, product-based)
/// returns. Before this fix only the linked returns were read, so the
/// "ضريبة المرتجعات" figure understated the real VAT reduction whenever an
/// unlinked return existed.
void main() {
  late AppDatabase db;
  late int currencyId;
  late int supplierId;

  final now = DateTime.now();

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get(); // force seed

    final usd = await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle();
    currencyId = usd.id;

    supplierId = await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: 'Test Supplier',
            currencyId: currencyId,
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Future<T> firstSuccess<T>(Stream<RealtimeState<T>> stream) async {
    final state =
        await stream.firstWhere((s) => s is RealtimeSuccess<T>)
            as RealtimeSuccess<T>;
    return state.data;
  }

  test('sales tax report sums VAT of linked AND adjustment returns', () async {
    // Linked sale + linked return (tax 500).
    final saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            invoiceNumber: 'INV-1',
            subtotalCents: Decimal.fromInt(10000),
            taxCents: Decimal.fromInt(1000),
            totalCents: Decimal.fromInt(11000),
            currencyId: currencyId,
            paymentMethod: 'cash',
            saleDate: Value(now),
          ),
        );
    await db
        .into(db.saleReturns)
        .insert(
          SaleReturnsCompanion.insert(
            saleId: saleId,
            returnNumber: 'SR-1',
            totalCents: Decimal.fromInt(5500),
            currencyId: currencyId,
            status: const Value('posted'),
            taxCents: Value(Decimal.fromInt(500)),
            returnDate: Value(now),
          ),
        );

    // Adjustment (unlinked) sale return (tax 300).
    await db
        .into(db.saleReturnAdjustments)
        .insert(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SAR-1',
            currencyId: currencyId,
            totalCents: Decimal.fromInt(3300),
            status: const Value('posted'),
            taxCents: Value(Decimal.fromInt(300)),
            returnDate: Value(now),
          ),
        );

    final bloc = SalesTaxReportBloc(db);
    addTearDown(bloc.close);
    bloc.add(SalesTaxReportDateRangeChanged(ReportDateRange.allTime()));

    final data = await firstSuccess<SalesTaxReportData>(bloc.stream);

    expect(data.returnCount, 2);
    expect(data.returnTaxCents, 800); // 500 linked + 300 adjustment
    expect(data.netTaxCents, 1000 - 800);
  });

  test(
    'purchase tax report sums VAT of linked AND adjustment returns',
    () async {
      final purchaseId = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              purchaseNumber: 'PO-1',
              supplierId: supplierId,
              subtotalCents: Decimal.fromInt(10000),
              taxCents: Decimal.fromInt(1000),
              totalCents: Decimal.fromInt(11000),
              currencyId: currencyId,
              status: const Value('posted'),
              purchaseDate: Value(now),
            ),
          );
      await db
          .into(db.purchaseReturns)
          .insert(
            PurchaseReturnsCompanion.insert(
              purchaseId: purchaseId,
              returnNumber: 'PR-1',
              totalCents: Decimal.fromInt(5500),
              currencyId: currencyId,
              status: const Value('posted'),
              taxCents: Value(Decimal.fromInt(500)),
              returnDate: Value(now),
            ),
          );
      await db
          .into(db.purchaseReturnAdjustments)
          .insert(
            PurchaseReturnAdjustmentsCompanion.insert(
              returnNumber: 'PAR-1',
              supplierId: supplierId,
              currencyId: currencyId,
              totalCents: Decimal.fromInt(3300),
              status: const Value('posted'),
              taxCents: Value(Decimal.fromInt(300)),
              returnDate: Value(now),
            ),
          );

      final bloc = PurchaseTaxReportBloc(db);
      addTearDown(bloc.close);
      bloc.add(PurchaseTaxReportDateRangeChanged(ReportDateRange.allTime()));

      final data = await firstSuccess<PurchaseTaxReportData>(bloc.stream);

      expect(data.returnCount, 2);
      expect(data.returnTaxCents, 800); // 500 linked + 300 adjustment
      expect(data.netTaxCents, 1000 - 800);
    },
  );

  test('draft / voided adjustment returns are excluded', () async {
    await db
        .into(db.saleReturnAdjustments)
        .insert(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SAR-DRAFT',
            currencyId: currencyId,
            totalCents: Decimal.fromInt(3300),
            status: const Value('draft'),
            taxCents: Value(Decimal.fromInt(300)),
            returnDate: Value(now),
          ),
        );
    await db
        .into(db.saleReturnAdjustments)
        .insert(
          SaleReturnAdjustmentsCompanion.insert(
            returnNumber: 'SAR-VOID',
            currencyId: currencyId,
            totalCents: Decimal.fromInt(3300),
            status: const Value('voided'),
            taxCents: Value(Decimal.fromInt(300)),
            returnDate: Value(now),
          ),
        );

    final bloc = SalesTaxReportBloc(db);
    addTearDown(bloc.close);
    bloc.add(SalesTaxReportDateRangeChanged(ReportDateRange.allTime()));

    final data = await firstSuccess<SalesTaxReportData>(bloc.stream);

    expect(data.returnCount, 0);
    expect(data.returnTaxCents, 0);
  });
}
