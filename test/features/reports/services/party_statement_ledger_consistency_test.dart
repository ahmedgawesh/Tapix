import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_ledger_report_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_statement_report_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_balance_drilldown_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_ledger_report_bloc.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_statement_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';
import 'package:tapix/features/reports/services/party_aging_ledger_service.dart';
import 'package:tapix/features/reports/services/party_statement_ledger_service.dart';
import 'package:tapix/features/reports/services/supplier_balance_ledger_service.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  final startDate = DateTime(2026, 8, 1);
  final endDate = DateTime(2026, 8, 8, 23, 59, 59);
  final range = ReportDateRange(startDate: startDate, endDate: endDate);

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((currency) => currency.code.equals('USD'))).getSingle()).id;
  });

  tearDown(() => db.close());

  Future<int> createCustomer() => db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          name: 'Ledger customer',
          currencyId: currencyId,
          openingBalanceCents: Value(Decimal.fromInt(1000)),
          balanceCents: Value(Decimal.fromInt(7)),
          createdAt: Value(DateTime(2025, 1, 1)),
        ),
      );

  Future<int> createSupplier() => db
      .into(db.suppliers)
      .insert(
        SuppliersCompanion.insert(
          name: 'Ledger supplier',
          currencyId: currencyId,
          openingBalanceCents: Value(Decimal.fromInt(-500)),
          balanceCents: Value(Decimal.fromInt(9)),
          createdAt: Value(DateTime(2025, 1, 1)),
        ),
      );

  Future<void> addCustomerTransaction({
    required int customerId,
    required String type,
    required int amountCents,
    required DateTime date,
  }) => db
      .into(db.customerTransactions)
      .insert(
        CustomerTransactionsCompanion.insert(
          customerId: customerId,
          transactionType: type,
          amountCents: Decimal.fromInt(amountCents),
          currencyId: currencyId,
          transactionDate: Value(date),
        ),
      );

  Future<void> addSupplierTransaction({
    required int supplierId,
    required String type,
    required int amountCents,
    required DateTime date,
  }) => db
      .into(db.supplierTransactions)
      .insert(
        SupplierTransactionsCompanion.insert(
          supplierId: supplierId,
          transactionType: type,
          amountCents: Decimal.fromInt(amountCents),
          currencyId: currencyId,
          transactionDate: Value(date),
        ),
      );

  test(
    'statements, ledgers, drilldown, balance and aging share one snapshot',
    () async {
      final customerId = await createCustomer();
      await addCustomerTransaction(
        customerId: customerId,
        type: 'sale',
        amountCents: 10000,
        date: DateTime(2026, 7, 15),
      );
      for (final movement in <(String, int, DateTime)>[
        ('sale', 2000, DateTime(2026, 8, 2)),
        ('payment', -3000, DateTime(2026, 8, 3)),
        ('credit_note', -1000, DateTime(2026, 8, 4)),
        ('payment_reversal', 500, DateTime(2026, 8, 5)),
        ('sale_void', -2000, DateTime(2026, 8, 6)),
        ('credit_note_reversal', 1000, DateTime(2026, 8, 7)),
        // Audit-only cash refund: must not change accounts receivable.
        ('refund', -9000, DateTime(2026, 8, 7, 12)),
        ('adjustment', 250, DateTime(2026, 8, 8, 23, 59, 59, 999)),
        ('sale', 9999, DateTime(2026, 8, 9)),
      ]) {
        await addCustomerTransaction(
          customerId: customerId,
          type: movement.$1,
          amountCents: movement.$2,
          date: movement.$3,
        );
      }

      final supplierId = await createSupplier();
      await addSupplierTransaction(
        supplierId: supplierId,
        type: 'purchase',
        amountCents: 6000,
        date: DateTime(2026, 7, 15),
      );
      for (final movement in <(String, int, DateTime)>[
        ('purchase', 4000, DateTime(2026, 8, 2)),
        ('payment', -1500, DateTime(2026, 8, 3)),
        ('credit_note', -500, DateTime(2026, 8, 4)),
        ('purchase_void', -4000, DateTime(2026, 8, 5)),
        ('payment_reversal', 1500, DateTime(2026, 8, 6)),
        ('credit_note_reversal', 500, DateTime(2026, 8, 7)),
        ('adjustment', -250, DateTime(2026, 8, 7, 12)),
        // Audit-only cash refund: must not change accounts payable.
        ('refund', -8000, DateTime(2026, 8, 8, 12)),
        ('discount', -250, DateTime(2026, 8, 8, 23, 59, 59, 999)),
        ('purchase', 7777, DateTime(2026, 8, 9)),
      ]) {
        await addSupplierTransaction(
          supplierId: supplierId,
          type: movement.$1,
          amountCents: movement.$2,
          date: movement.$3,
        );
      }

      final service = PartyStatementLedgerService(db);
      final customerSnapshot = await service.loadCustomer(
        customerId: customerId,
        startDate: startDate,
        endDate: endDate,
      );
      expect(customerSnapshot.openingBalanceCents, 11000);
      expect(customerSnapshot.closingBalanceCents, 8750);
      expect(customerSnapshot.totalDebitsCents, 3750);
      expect(customerSnapshot.totalCreditsCents, 6000);
      expect(customerSnapshot.transactions, hasLength(7));
      expect(customerSnapshot.transactions.last.amountCents, 250);
      expect(customerSnapshot.options.single.balanceCents, 8750);

      final supplierSnapshot = await service.loadSupplier(
        supplierId: supplierId,
        startDate: startDate,
        endDate: endDate,
      );
      expect(supplierSnapshot.openingBalanceCents, 5500);
      expect(supplierSnapshot.closingBalanceCents, 5000);
      expect(supplierSnapshot.totalDebitsCents, 6000);
      expect(supplierSnapshot.totalCreditsCents, 6500);
      expect(supplierSnapshot.transactions, hasLength(8));
      expect(supplierSnapshot.transactions.last.amountCents, -250);
      expect(supplierSnapshot.options.single.balanceCents, 5000);

      final customerStatementBloc = CustomerStatementReportBloc(db);
      addTearDown(customerStatementBloc.close);
      customerStatementBloc.add(CustomerStatementReportDateRangeChanged(range));
      customerStatementBloc.add(
        CustomerStatementReportCustomerChanged(customerId),
      );
      final customerStatementState =
          await customerStatementBloc.stream.firstWhere(
                (state) =>
                    state is RealtimeSuccess<CustomerStatementData> &&
                    state.data.customerId == customerId &&
                    state.data.dateRange.endDate == endDate,
              )
              as RealtimeSuccess<CustomerStatementData>;
      expect(customerStatementState.data.openingBalanceCents, 11000);
      expect(customerStatementState.data.closingBalanceCents, 8750);

      final customerLedgerBloc = CustomerLedgerReportBloc(db);
      addTearDown(customerLedgerBloc.close);
      customerLedgerBloc.add(CustomerLedgerDateRangeChanged(range));
      customerLedgerBloc.add(CustomerLedgerCustomerChanged(customerId));
      final customerLedgerState =
          await customerLedgerBloc.stream.firstWhere(
                (state) =>
                    state is RealtimeSuccess<CustomerLedgerData> &&
                    state.data.customerId == customerId &&
                    state.data.dateRange.endDate == endDate,
              )
              as RealtimeSuccess<CustomerLedgerData>;
      expect(customerLedgerState.data.closingBalanceCents, 8750);
      expect(customerLedgerState.data.totalSalesCents, 250);
      expect(customerLedgerState.data.totalReturnsCents, 0);
      expect(customerLedgerState.data.totalPaymentsCents, 2500);

      final supplierStatementBloc = SupplierStatementReportBloc(db);
      addTearDown(supplierStatementBloc.close);
      supplierStatementBloc.add(SupplierStatementReportDateRangeChanged(range));
      supplierStatementBloc.add(
        SupplierStatementReportSupplierChanged(supplierId),
      );
      final supplierStatementState =
          await supplierStatementBloc.stream.firstWhere(
                (state) =>
                    state is RealtimeSuccess<SupplierStatementData> &&
                    state.data.supplierId == supplierId &&
                    state.data.dateRange.endDate == endDate,
              )
              as RealtimeSuccess<SupplierStatementData>;
      expect(supplierStatementState.data.openingBalanceCents, 5500);
      expect(supplierStatementState.data.closingBalanceCents, 5000);

      final supplierLedgerBloc = SupplierLedgerReportBloc(db);
      addTearDown(supplierLedgerBloc.close);
      supplierLedgerBloc.add(SupplierLedgerDateRangeChanged(range));
      supplierLedgerBloc.add(SupplierLedgerSupplierChanged(supplierId));
      final supplierLedgerState =
          await supplierLedgerBloc.stream.firstWhere(
                (state) =>
                    state is RealtimeSuccess<SupplierLedgerData> &&
                    state.data.supplierId == supplierId &&
                    state.data.dateRange.endDate == endDate,
              )
              as RealtimeSuccess<SupplierLedgerData>;
      expect(supplierLedgerState.data.closingBalanceCents, 5000);
      expect(supplierLedgerState.data.totalPurchasesCents, 0);
      expect(supplierLedgerState.data.totalReturnsCents, 0);
      expect(supplierLedgerState.data.totalPaymentsCents, 250);
      expect(supplierLedgerState.data.totalDiscountsCents, 250);

      final drilldownBloc = SupplierBalanceDrilldownBloc(db);
      addTearDown(drilldownBloc.close);
      drilldownBloc.add(SupplierBalanceDrilldownDateRangeChanged(range));
      drilldownBloc.add(SupplierBalanceDrilldownSupplierChanged(supplierId));
      final drilldownState =
          await drilldownBloc.stream.firstWhere(
                (state) =>
                    state is RealtimeSuccess<SupplierBalanceDrilldownData> &&
                    state.data.supplierId == supplierId &&
                    state.data.dateRange.endDate == endDate,
              )
              as RealtimeSuccess<SupplierBalanceDrilldownData>;
      expect(drilldownState.data.openingBalanceCents, 5500);
      expect(drilldownState.data.closingBalanceCents, 5000);
      expect(drilldownState.data.transactions, hasLength(8));

      final supplierBalance = (await SupplierBalanceLedgerService(
        db,
      ).load(startDate: startDate, endDate: endDate)).single;
      expect(supplierBalance.netBalanceCents, 5000);

      final aging = PartyAgingLedgerService(db);
      expect(
        (await aging.loadCustomers(asOf: endDate)).single.buckets.totalCents,
        8750,
      );
      expect(
        (await aging.loadSuppliers(asOf: endDate)).single.buckets.totalCents,
        5000,
      );

      // Rebuild must follow the same balance-effect policy. Future financial
      // movements are included in the current cached balance; cash-refund
      // audit rows are not.
      expect(await db.customerDao.recalculateBalance(customerId), 18749);
      expect(await db.supplierDao.recalculateBalance(supplierId), 12777);
    },
  );
}
