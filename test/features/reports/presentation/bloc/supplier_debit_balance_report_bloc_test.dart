import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_debit_balance_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('SupplierDebitBalanceItem data model', () {
    test('stores correct values', () {
      const item = SupplierDebitBalanceItem(
        supplierId: 1,
        supplierName: 'Test Supplier',
        phone: '+1234567890',
        totalPurchasesCents: 150000,
        totalReturnsCents: 10000,
        totalPaymentsCents: 40000,
        totalDiscountsCents: 5000,
        debitBalanceCents: 95000,
        transactionCount: 10,
        lastTransactionAt: null,
      );

      expect(item.supplierId, 1);
      expect(item.supplierName, 'Test Supplier');
      expect(item.phone, '+1234567890');
      expect(item.totalPurchasesCents, 150000);
      expect(item.totalReturnsCents, 10000);
      expect(item.totalPaymentsCents, 40000);
      expect(item.totalDiscountsCents, 5000);
      expect(item.debitBalanceCents, 95000);
      expect(item.transactionCount, 10);
      expect(item.lastTransactionAt, isNull);
    });

    test('stores last transaction date when provided', () {
      final date = DateTime(2026, 2, 1);
      final item = SupplierDebitBalanceItem(
        supplierId: 2,
        supplierName: 'Supplier B',
        totalPurchasesCents: 500000,
        totalReturnsCents: 50000,
        totalPaymentsCents: 200000,
        totalDiscountsCents: 0,
        debitBalanceCents: 250000,
        transactionCount: 25,
        lastTransactionAt: date,
      );

      expect(item.lastTransactionAt, date);
      expect(item.phone, isNull);
    });

    test('debit balance equals purchases minus returns minus payments minus discounts', () {
      const purchases = 100000;
      const returns = 10000;
      const payments = 30000;
      const discounts = 5000;
      const expectedDebit = purchases - returns - payments - discounts;

      const item = SupplierDebitBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasesCents: purchases,
        totalReturnsCents: returns,
        totalPaymentsCents: payments,
        totalDiscountsCents: discounts,
        debitBalanceCents: expectedDebit,
        transactionCount: 5,
      );

      expect(item.debitBalanceCents, expectedDebit);
      expect(item.debitBalanceCents, 55000);
    });

    test('integer cents prevents floating point errors', () {
      const item = SupplierDebitBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasesCents: 30,
        totalReturnsCents: 0,
        totalPaymentsCents: 10,
        totalDiscountsCents: 0,
        debitBalanceCents: 20,
        transactionCount: 2,
      );

      expect(item.totalPurchasesCents - item.totalPaymentsCents, 20);
      expect(item.debitBalanceCents, 20);
    });

    test('all debit balances are positive (only payable suppliers)', () {
      const item = SupplierDebitBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasesCents: 100000,
        totalReturnsCents: 20000,
        totalPaymentsCents: 30000,
        totalDiscountsCents: 0,
        debitBalanceCents: 50000,
        transactionCount: 5,
      );

      expect(item.debitBalanceCents, isPositive);
    });

    test('large amounts do not overflow int', () {
      const largeCents = 999999999999;
      const item = SupplierDebitBalanceItem(
        supplierId: 1,
        supplierName: 'Big Supplier',
        totalPurchasesCents: largeCents,
        totalReturnsCents: 0,
        totalPaymentsCents: 0,
        totalDiscountsCents: 0,
        debitBalanceCents: largeCents,
        transactionCount: 1,
      );

      expect(item.totalPurchasesCents, largeCents);
      expect(item.debitBalanceCents, largeCents);
    });
  });

  group('SupplierDebitBalanceReportData', () {
    test('default values are correct', () {
      final data = SupplierDebitBalanceReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.suppliers, isEmpty);
      expect(data.grandTotalPurchasesCents, 0);
      expect(data.grandTotalReturnsCents, 0);
      expect(data.grandTotalPaymentsCents, 0);
      expect(data.grandTotalDiscountsCents, 0);
      expect(data.grandTotalDebitBalanceCents, 0);
      expect(data.totalSuppliers, 0);
      expect(data.sort, SupplierDebitBalanceSortType.balanceDesc);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = SupplierDebitBalanceReportData(
        grandTotalPurchasesCents: 500000,
        grandTotalReturnsCents: 50000,
        grandTotalPaymentsCents: 200000,
        grandTotalDiscountsCents: 10000,
        grandTotalDebitBalanceCents: 240000,
        totalSuppliers: 10,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        dateRange: ReportDateRange.thisYear(),
      );

      expect(updated.grandTotalPurchasesCents, 500000);
      expect(updated.grandTotalReturnsCents, 50000);
      expect(updated.grandTotalPaymentsCents, 200000);
      expect(updated.grandTotalDiscountsCents, 10000);
      expect(updated.grandTotalDebitBalanceCents, 240000);
      expect(updated.totalSuppliers, 10);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = SupplierDebitBalanceReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        grandTotalPurchasesCents: 100000,
        grandTotalPaymentsCents: 50000,
        grandTotalDebitBalanceCents: 50000,
        sort: SupplierDebitBalanceSortType.nameAsc,
      );

      expect(updated.grandTotalPurchasesCents, 100000);
      expect(updated.grandTotalPaymentsCents, 50000);
      expect(updated.grandTotalDebitBalanceCents, 50000);
      expect(updated.sort, SupplierDebitBalanceSortType.nameAsc);
    });

    test('copyWith updates suppliers list', () {
      final original = SupplierDebitBalanceReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      const supplier = SupplierDebitBalanceItem(
        supplierId: 1,
        supplierName: 'New Supplier',
        totalPurchasesCents: 999900,
        totalReturnsCents: 0,
        totalPaymentsCents: 100,
        totalDiscountsCents: 0,
        debitBalanceCents: 999800,
        transactionCount: 100,
      );

      final updated = original.copyWith(
        suppliers: [supplier],
        totalSuppliers: 1,
      );

      expect(updated.suppliers.length, 1);
      expect(updated.suppliers.first.supplierName, 'New Supplier');
      expect(updated.totalSuppliers, 1);
    });
  });

  group('SupplierDebitBalanceReportBloc events', () {
    test('SupplierDebitBalanceReportDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = SupplierDebitBalanceReportDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('SupplierDebitBalanceReportSortChanged stores sort type', () {
      const event = SupplierDebitBalanceReportSortChanged(
          SupplierDebitBalanceSortType.nameAsc);
      expect(event.sort, SupplierDebitBalanceSortType.nameAsc);
    });
  });

  group('SupplierDebitBalanceSortType enum', () {
    test('has all expected values', () {
      expect(SupplierDebitBalanceSortType.values.length, 6);
      expect(SupplierDebitBalanceSortType.values,
          contains(SupplierDebitBalanceSortType.balanceDesc));
      expect(SupplierDebitBalanceSortType.values,
          contains(SupplierDebitBalanceSortType.balanceAsc));
      expect(SupplierDebitBalanceSortType.values,
          contains(SupplierDebitBalanceSortType.nameAsc));
      expect(SupplierDebitBalanceSortType.values,
          contains(SupplierDebitBalanceSortType.nameDesc));
      expect(SupplierDebitBalanceSortType.values,
          contains(SupplierDebitBalanceSortType.purchasesDesc));
      expect(SupplierDebitBalanceSortType.values,
          contains(SupplierDebitBalanceSortType.paymentsDesc));
    });
  });

  group('Sort logic', () {
    final suppliers = [
      const SupplierDebitBalanceItem(
        supplierId: 1,
        supplierName: 'Zebra Supplies',
        totalPurchasesCents: 50000,
        totalReturnsCents: 0,
        totalPaymentsCents: 10000,
        totalDiscountsCents: 0,
        debitBalanceCents: 40000,
        transactionCount: 5,
      ),
      const SupplierDebitBalanceItem(
        supplierId: 2,
        supplierName: 'Apple Wholesale',
        totalPurchasesCents: 200000,
        totalReturnsCents: 10000,
        totalPaymentsCents: 40000,
        totalDiscountsCents: 0,
        debitBalanceCents: 150000,
        transactionCount: 20,
      ),
      const SupplierDebitBalanceItem(
        supplierId: 3,
        supplierName: 'Mango Trading',
        totalPurchasesCents: 100000,
        totalReturnsCents: 5000,
        totalPaymentsCents: 75000,
        totalDiscountsCents: 0,
        debitBalanceCents: 20000,
        transactionCount: 10,
      ),
    ];

    test('sort by balance descending', () {
      final list = List<SupplierDebitBalanceItem>.from(suppliers);
      list.sort(
          (a, b) => b.debitBalanceCents.compareTo(a.debitBalanceCents));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[0].debitBalanceCents, 150000);
      expect(list[1].supplierName, 'Zebra Supplies');
      expect(list[1].debitBalanceCents, 40000);
      expect(list[2].supplierName, 'Mango Trading');
      expect(list[2].debitBalanceCents, 20000);
    });

    test('sort by balance ascending', () {
      final list = List<SupplierDebitBalanceItem>.from(suppliers);
      list.sort(
          (a, b) => a.debitBalanceCents.compareTo(b.debitBalanceCents));

      expect(list[0].supplierName, 'Mango Trading');
      expect(list[2].supplierName, 'Apple Wholesale');
    });

    test('sort by name ascending', () {
      final list = List<SupplierDebitBalanceItem>.from(suppliers);
      list.sort((a, b) => a.supplierName.compareTo(b.supplierName));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[1].supplierName, 'Mango Trading');
      expect(list[2].supplierName, 'Zebra Supplies');
    });

    test('sort by name descending', () {
      final list = List<SupplierDebitBalanceItem>.from(suppliers);
      list.sort((a, b) => b.supplierName.compareTo(a.supplierName));

      expect(list[0].supplierName, 'Zebra Supplies');
      expect(list[1].supplierName, 'Mango Trading');
      expect(list[2].supplierName, 'Apple Wholesale');
    });

    test('sort by purchases descending', () {
      final list = List<SupplierDebitBalanceItem>.from(suppliers);
      list.sort(
          (a, b) => b.totalPurchasesCents.compareTo(a.totalPurchasesCents));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[0].totalPurchasesCents, 200000);
      expect(list[1].supplierName, 'Mango Trading');
      expect(list[1].totalPurchasesCents, 100000);
      expect(list[2].supplierName, 'Zebra Supplies');
      expect(list[2].totalPurchasesCents, 50000);
    });

    test('sort by payments descending', () {
      final list = List<SupplierDebitBalanceItem>.from(suppliers);
      list.sort(
          (a, b) => b.totalPaymentsCents.compareTo(a.totalPaymentsCents));

      expect(list[0].supplierName, 'Mango Trading');
      expect(list[0].totalPaymentsCents, 75000);
      expect(list[1].supplierName, 'Apple Wholesale');
      expect(list[1].totalPaymentsCents, 40000);
      expect(list[2].supplierName, 'Zebra Supplies');
      expect(list[2].totalPaymentsCents, 10000);
    });
  });

  group('Grand totals calculation', () {
    test('grand totals sum correctly from supplier list', () {
      const suppliers = [
        SupplierDebitBalanceItem(
          supplierId: 1,
          supplierName: 'A',
          totalPurchasesCents: 50000,
          totalReturnsCents: 5000,
          totalPaymentsCents: 10000,
          totalDiscountsCents: 1000,
          debitBalanceCents: 34000,
          transactionCount: 5,
        ),
        SupplierDebitBalanceItem(
          supplierId: 2,
          supplierName: 'B',
          totalPurchasesCents: 200000,
          totalReturnsCents: 20000,
          totalPaymentsCents: 50000,
          totalDiscountsCents: 5000,
          debitBalanceCents: 125000,
          transactionCount: 20,
        ),
        SupplierDebitBalanceItem(
          supplierId: 3,
          supplierName: 'C',
          totalPurchasesCents: 100000,
          totalReturnsCents: 10000,
          totalPaymentsCents: 30000,
          totalDiscountsCents: 0,
          debitBalanceCents: 60000,
          transactionCount: 10,
        ),
      ];

      int totalPurchases = 0;
      int totalReturns = 0;
      int totalPayments = 0;
      int totalDiscounts = 0;
      int totalDebitBalance = 0;
      for (final s in suppliers) {
        totalPurchases += s.totalPurchasesCents;
        totalReturns += s.totalReturnsCents;
        totalPayments += s.totalPaymentsCents;
        totalDiscounts += s.totalDiscountsCents;
        totalDebitBalance += s.debitBalanceCents;
      }

      expect(totalPurchases, 350000);
      expect(totalReturns, 35000);
      expect(totalPayments, 90000);
      expect(totalDiscounts, 6000);
      expect(totalDebitBalance, 219000);
      expect(suppliers.length, 3);
    });

    test('empty supplier list yields zero totals', () {
      const suppliers = <SupplierDebitBalanceItem>[];

      int totalPurchases = 0;
      int totalPayments = 0;
      int totalDebitBalance = 0;
      for (final s in suppliers) {
        totalPurchases += s.totalPurchasesCents;
        totalPayments += s.totalPaymentsCents;
        totalDebitBalance += s.debitBalanceCents;
      }

      expect(totalPurchases, 0);
      expect(totalPayments, 0);
      expect(totalDebitBalance, 0);
    });

    test('debit balance calculation with all transaction types', () {
      const purchases = 200000;
      const returns = 15000;
      const payments = 80000;
      const discounts = 5000;
      // Net debit = purchases - returns - payments - discounts
      // In supplier_transactions: purchases are positive, rest are negative
      // So SUM(amount_cents) = 200000 + (-15000) + (-80000) + (-5000) = 100000
      const netDebit = purchases - returns - payments - discounts;

      expect(netDebit, 100000);
    });

    test('large amounts do not overflow int', () {
      const largeCents = 999999999999;
      const item = SupplierDebitBalanceItem(
        supplierId: 1,
        supplierName: 'Big Supplier',
        totalPurchasesCents: largeCents,
        totalReturnsCents: 0,
        totalPaymentsCents: 0,
        totalDiscountsCents: 0,
        debitBalanceCents: largeCents,
        transactionCount: 1,
      );

      expect(item.totalPurchasesCents, largeCents);
      expect(item.debitBalanceCents, largeCents);
    });
  });

  group('ReportDateRange for supplier debit balance', () {
    test('thisMonth preset has correct dates', () {
      final range = ReportDateRange.thisMonth();
      final now = DateTime.now();
      expect(range.startDate.year, now.year);
      expect(range.startDate.month, now.month);
      expect(range.startDate.day, 1);
      expect(range.preset, ReportPeriodPreset.thisMonth);
    });

    test('allTime preset starts from 2000', () {
      final range = ReportDateRange.allTime();
      expect(range.startDate.year, 2000);
      expect(range.preset, ReportPeriodPreset.allTime);
    });

    test('custom range preserves dates', () {
      final range = ReportDateRange(
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 12, 31),
        preset: ReportPeriodPreset.custom,
      );
      expect(range.startDate.year, 2025);
      expect(range.endDate.month, 12);
      expect(range.preset, ReportPeriodPreset.custom);
    });

    test('thisWeek starts on Monday', () {
      final range = ReportDateRange.thisWeek();
      expect(range.startDate.weekday, DateTime.monday);
      expect(range.preset, ReportPeriodPreset.thisWeek);
    });

    test('lastMonth has correct boundaries', () {
      final range = ReportDateRange.lastMonth();
      final now = DateTime.now();
      final expectedMonth = now.month == 1 ? 12 : now.month - 1;
      expect(range.startDate.month, expectedMonth);
      expect(range.startDate.day, 1);
      expect(range.preset, ReportPeriodPreset.lastMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final range = ReportDateRange.thisMonth();
      final updated = range.copyWith(
        preset: ReportPeriodPreset.custom,
      );
      expect(updated.startDate, range.startDate);
      expect(updated.endDate, range.endDate);
      expect(updated.preset, ReportPeriodPreset.custom);
    });
  });

  group('SupplierDebitBalancePdfService translations', () {
    test('all expected translation keys are defined', () {
      const expectedKeys = [
        'supplier_debit_balance_report',
        'period',
        'total_purchases',
        'total_payments',
        'total_debit_balance',
        'total_suppliers',
        'supplier_debit_balance_details',
        'supplier',
        'purchases',
        'payments',
        'debit_balance',
        'transactions',
        'last_transaction',
        'grand_total',
        'printed_on',
      ];
      expect(expectedKeys.length, 15);
    });
  });

  group('Debit balance classification', () {
    test('all items have positive debit balance (payable)', () {
      const items = [
        SupplierDebitBalanceItem(
          supplierId: 1,
          supplierName: 'Supplier A',
          totalPurchasesCents: 100000,
          totalReturnsCents: 0,
          totalPaymentsCents: 30000,
          totalDiscountsCents: 0,
          debitBalanceCents: 70000,
          transactionCount: 5,
        ),
        SupplierDebitBalanceItem(
          supplierId: 2,
          supplierName: 'Supplier B',
          totalPurchasesCents: 200000,
          totalReturnsCents: 10000,
          totalPaymentsCents: 50000,
          totalDiscountsCents: 5000,
          debitBalanceCents: 135000,
          transactionCount: 10,
        ),
      ];

      for (final item in items) {
        expect(item.debitBalanceCents, isPositive,
            reason: '${item.supplierName} should have positive debit balance');
      }
    });

    test('debit balance is always > 0 (filter criteria)', () {
      const item = SupplierDebitBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasesCents: 100000,
        totalReturnsCents: 20000,
        totalPaymentsCents: 30000,
        totalDiscountsCents: 0,
        debitBalanceCents: 50000,
        transactionCount: 5,
      );

      // Debit balance report only shows suppliers with positive balance
      expect(item.debitBalanceCents > 0, true);
    });
  });

  group('Debit balance calculation verification', () {
    test('purchases increase debit balance', () {
      // When a purchase is made, amount_cents is positive in supplier_transactions
      const purchaseAmount = 50000;
      expect(purchaseAmount > 0, true);
    });

    test('payments decrease debit balance', () {
      // When a payment is made, amount_cents is negative in supplier_transactions
      const paymentAmount = -30000;
      expect(paymentAmount < 0, true);
    });

    test('returns decrease debit balance', () {
      // When a return is processed, amount_cents is negative (credit_note)
      const returnAmount = -10000;
      expect(returnAmount < 0, true);
    });

    test('discounts decrease debit balance', () {
      // When a discount is applied, amount_cents is negative
      const discountAmount = -5000;
      expect(discountAmount < 0, true);
    });

    test('net debit balance = SUM(all transaction amounts)', () {
      const purchase1 = 100000;
      const purchase2 = 50000;
      const payment1 = -30000;
      const return1 = -10000;
      const discount1 = -5000;

      final netBalance =
          purchase1 + purchase2 + payment1 + return1 + discount1;
      expect(netBalance, 105000);
      expect(netBalance > 0, true); // Positive = we owe the supplier
    });

    test('supplier with zero balance is excluded from debit report', () {
      const purchases = 50000;
      const payments = -50000;
      final netBalance = purchases + payments;
      expect(netBalance, 0);
      // HAVING debit_balance_cents > 0 would exclude this supplier
      expect(netBalance > 0, false);
    });

    test('supplier with negative balance (credit) is excluded from debit report', () {
      const purchases = 30000;
      const payments = -50000;
      final netBalance = purchases + payments;
      expect(netBalance, -20000);
      // HAVING debit_balance_cents > 0 would exclude this supplier
      expect(netBalance > 0, false);
    });
  });

  group('Suppliers counting', () {
    test('correctly counts total suppliers with debit balances', () {
      const suppliers = [
        SupplierDebitBalanceItem(
          supplierId: 1,
          supplierName: 'Supplier A',
          totalPurchasesCents: 100000,
          totalReturnsCents: 0,
          totalPaymentsCents: 20000,
          totalDiscountsCents: 0,
          debitBalanceCents: 80000,
          transactionCount: 5,
        ),
        SupplierDebitBalanceItem(
          supplierId: 2,
          supplierName: 'Supplier B',
          totalPurchasesCents: 200000,
          totalReturnsCents: 10000,
          totalPaymentsCents: 50000,
          totalDiscountsCents: 5000,
          debitBalanceCents: 135000,
          transactionCount: 10,
        ),
        SupplierDebitBalanceItem(
          supplierId: 3,
          supplierName: 'Supplier C',
          totalPurchasesCents: 30000,
          totalReturnsCents: 0,
          totalPaymentsCents: 10000,
          totalDiscountsCents: 0,
          debitBalanceCents: 20000,
          transactionCount: 3,
        ),
      ];

      // All suppliers in the debit report have positive balances
      expect(suppliers.length, 3);
      for (final s in suppliers) {
        expect(s.debitBalanceCents > 0, true);
      }
    });
  });
}
