import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tapix/core/bloc/realtime_bloc.dart';
import 'package:tapix/core/database/app_database.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_balance_report_bloc.dart'
    as balance_report;
import 'package:tapix/features/reports/presentation/bloc/supplier_credit_balance_report_bloc.dart'
    as credit_report;
import 'package:tapix/features/reports/presentation/bloc/supplier_debit_balance_report_bloc.dart'
    as debit_report;
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';
import 'package:tapix/features/reports/services/supplier_balance_ledger_service.dart';

void main() {
  late AppDatabase db;
  late int currencyId;
  final startDate = DateTime(2026, 8, 1);
  final endDate = DateTime(2026, 8, 8, 23, 59, 59);

  setUp(() async {
    db = AppDatabase.connect(DatabaseConnection(NativeDatabase.memory()));
    await db.customSelect('SELECT 1').get();
    currencyId = (await (db.select(
      db.currencies,
    )..where((c) => c.code.equals('USD'))).getSingle()).id;
  });

  tearDown(() => db.close());

  Future<int> createSupplier({
    required String name,
    required int openingBalanceCents,
    bool isActive = true,
  }) {
    return db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            name: name,
            currencyId: currencyId,
            openingBalanceCents: Value(Decimal.fromInt(openingBalanceCents)),
            // Deliberately stale: reports must derive from the signed ledger.
            balanceCents: Value(Decimal.fromInt(7)),
            isActive: Value(isActive),
            createdAt: Value(DateTime(2025, 1, 1)),
          ),
        );
  }

  Future<void> addTransaction({
    required int supplierId,
    required String type,
    required int amountCents,
    required DateTime date,
  }) async {
    await db
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
  }

  test(
    'snapshot includes prior history, excludes future, and nets reversals',
    () async {
      final payableId = await createSupplier(
        name: 'Inactive payable supplier',
        openingBalanceCents: 1000,
        isActive: false,
      );
      await addTransaction(
        supplierId: payableId,
        type: 'purchase',
        amountCents: 10000,
        date: DateTime(2026, 7, 15),
      );
      await addTransaction(
        supplierId: payableId,
        type: 'payment',
        amountCents: -3000,
        date: DateTime(2026, 8, 2),
      );
      await addTransaction(
        supplierId: payableId,
        type: 'purchase_return',
        amountCents: -1000,
        date: DateTime(2026, 8, 3),
      );
      await addTransaction(
        supplierId: payableId,
        type: 'adjustment',
        amountCents: 500,
        date: DateTime(2026, 8, 4),
      );
      await addTransaction(
        supplierId: payableId,
        type: 'payment_reversal',
        amountCents: 500,
        date: DateTime(2026, 8, 5),
      );
      await addTransaction(
        supplierId: payableId,
        type: 'purchase',
        amountCents: 2000,
        date: endDate,
      );
      await addTransaction(
        supplierId: payableId,
        type: 'payment',
        amountCents: -9999,
        date: endDate.add(const Duration(seconds: 1)),
      );

      final receivableId = await createSupplier(
        name: 'Supplier receivable',
        openingBalanceCents: -1000,
      );
      await addTransaction(
        supplierId: receivableId,
        type: 'adjustment',
        amountCents: -2000,
        date: DateTime(2026, 7, 20),
      );
      await addTransaction(
        supplierId: receivableId,
        type: 'purchase',
        amountCents: 1000,
        date: DateTime(2026, 8, 2),
      );
      await addTransaction(
        supplierId: receivableId,
        type: 'payment',
        amountCents: -3000,
        date: DateTime(2026, 8, 6),
      );

      await createSupplier(name: 'Unused supplier', openingBalanceCents: 0);

      final records = await SupplierBalanceLedgerService(
        db,
      ).load(startDate: startDate, endDate: endDate);
      expect(records, hasLength(2));

      final payable = records.singleWhere(
        (record) => record.supplierId == payableId,
      );
      expect(payable.netBalanceCents, 10000);
      expect(payable.totalPurchasesCents, 2000);
      expect(payable.totalPaymentsCents, 2500);
      expect(payable.totalReturnsCents, 1000);
      expect(payable.totalDiscountsCents, 0);
      expect(payable.transactionCount, 6);
      expect(payable.lastTransactionAt, endDate);

      final receivable = records.singleWhere(
        (record) => record.supplierId == receivableId,
      );
      expect(receivable.netBalanceCents, -5000);
      expect(receivable.totalPurchasesCents, 1000);
      expect(receivable.totalPaymentsCents, 3000);

      final range = ReportDateRange(startDate: startDate, endDate: endDate);

      final balanceBloc = balance_report.SupplierBalanceReportBloc(db);
      addTearDown(balanceBloc.close);
      balanceBloc.add(
        balance_report.SupplierBalanceReportDateRangeChanged(range),
      );
      final balanceState =
          await balanceBloc.stream.firstWhere((state) {
                return state
                        is RealtimeSuccess<
                          balance_report.SupplierBalanceReportData
                        > &&
                    state.data.dateRange.endDate == endDate;
              })
              as RealtimeSuccess<balance_report.SupplierBalanceReportData>;
      expect(balanceState.data.suppliers, hasLength(2));
      expect(balanceState.data.summary.totalPayablesCents, 10000);
      expect(balanceState.data.summary.totalReceivablesCents, 5000);
      expect(balanceState.data.summary.netBalanceCents, 5000);

      final debitBloc = debit_report.SupplierDebitBalanceReportBloc(db);
      addTearDown(debitBloc.close);
      debitBloc.add(
        debit_report.SupplierDebitBalanceReportDateRangeChanged(range),
      );
      final debitState =
          await debitBloc.stream.firstWhere((state) {
                return state
                        is RealtimeSuccess<
                          debit_report.SupplierDebitBalanceReportData
                        > &&
                    state.data.dateRange.endDate == endDate;
              })
              as RealtimeSuccess<debit_report.SupplierDebitBalanceReportData>;
      expect(debitState.data.suppliers.single.supplierId, payableId);
      expect(debitState.data.grandTotalDebitBalanceCents, 10000);

      final creditBloc = credit_report.SupplierCreditBalanceReportBloc(db);
      addTearDown(creditBloc.close);
      creditBloc.add(
        credit_report.SupplierCreditBalanceReportDateRangeChanged(range),
      );
      final creditState =
          await creditBloc.stream.firstWhere((state) {
                return state
                        is RealtimeSuccess<
                          credit_report.SupplierCreditBalanceReportData
                        > &&
                    state.data.dateRange.endDate == endDate;
              })
              as RealtimeSuccess<credit_report.SupplierCreditBalanceReportData>;
      expect(creditState.data.suppliers.single.supplierId, receivableId);
      expect(creditState.data.grandTotalCreditBalanceCents, 5000);
    },
  );
}
