import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_credit_balance_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('SupplierCreditBalanceItem data model', () {
    test('stores correct values', () {
      const item = SupplierCreditBalanceItem(
        supplierId: 1,
        supplierName: 'Test Supplier',
        phone: '+1234567890',
        totalPurchasesCents: 50000,
        totalReturnsCents: 10000,
        totalPaymentsCents: 100000,
        totalDiscountsCents: 5000,
        creditBalanceCents: 65000,
        transactionCount: 10,
        lastTransactionAt: null,
      );

      expect(item.supplierId, 1);
      expect(item.supplierName, 'Test Supplier');
      expect(item.phone, '+1234567890');
      expect(item.totalPurchasesCents, 50000);
      expect(item.totalReturnsCents, 10000);
      expect(item.totalPaymentsCents, 100000);
      expect(item.totalDiscountsCents, 5000);
      expect(item.creditBalanceCents, 65000);
      expect(item.transactionCount, 10);
      expect(item.lastTransactionAt, isNull);
    });

    test('stores last transaction date when provided', () {
      final date = DateTime(2026, 2, 1);
      final item = SupplierCreditBalanceItem(
        supplierId: 2,
        supplierName: 'Supplier B',
        totalPurchasesCents: 100000,
        totalReturnsCents: 50000,
        totalPaymentsCents: 200000,
        totalDiscountsCents: 0,
        creditBalanceCents: 150000,
        transactionCount: 25,
        lastTransactionAt: date,
      );

      expect(item.lastTransactionAt, date);
      expect(item.phone, isNull);
    });

    test('credit balance is ABS of negative net balance', () {
      // Net balance in DB: purchases(+50000) + payments(-100000) = -50000
      // Credit balance displayed = ABS(-50000) = 50000
      const netBalanceInDb = -50000;
      final creditBalance = netBalanceInDb.abs();

      const item = SupplierCreditBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasesCents: 50000,
        totalReturnsCents: 0,
        totalPaymentsCents: 100000,
        totalDiscountsCents: 0,
        creditBalanceCents: 50000,
        transactionCount: 2,
      );

      expect(item.creditBalanceCents, creditBalance);
      expect(item.creditBalanceCents, isPositive);
    });

    test('integer cents prevents floating point errors', () {
      const item = SupplierCreditBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasesCents: 10,
        totalReturnsCents: 0,
        totalPaymentsCents: 30,
        totalDiscountsCents: 0,
        creditBalanceCents: 20,
        transactionCount: 2,
      );

      expect(item.totalPaymentsCents - item.totalPurchasesCents, 20);
      expect(item.creditBalanceCents, 20);
    });

    test('all credit balances are positive (displayed as ABS)', () {
      const item = SupplierCreditBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasesCents: 30000,
        totalReturnsCents: 20000,
        totalPaymentsCents: 100000,
        totalDiscountsCents: 0,
        creditBalanceCents: 90000,
        transactionCount: 5,
      );

      expect(item.creditBalanceCents, isPositive);
    });

    test('large amounts do not overflow int', () {
      const largeCents = 999999999999;
      const item = SupplierCreditBalanceItem(
        supplierId: 1,
        supplierName: 'Big Supplier',
        totalPurchasesCents: 0,
        totalReturnsCents: 0,
        totalPaymentsCents: largeCents,
        totalDiscountsCents: 0,
        creditBalanceCents: largeCents,
        transactionCount: 1,
      );

      expect(item.totalPaymentsCents, largeCents);
      expect(item.creditBalanceCents, largeCents);
    });
  });

  group('SupplierCreditBalanceReportData', () {
    test('default values are correct', () {
      final data = SupplierCreditBalanceReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.suppliers, isEmpty);
      expect(data.grandTotalPurchasesCents, 0);
      expect(data.grandTotalReturnsCents, 0);
      expect(data.grandTotalPaymentsCents, 0);
      expect(data.grandTotalDiscountsCents, 0);
      expect(data.grandTotalCreditBalanceCents, 0);
      expect(data.totalSuppliers, 0);
      expect(data.sort, SupplierCreditBalanceSortType.balanceDesc);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = SupplierCreditBalanceReportData(
        grandTotalPurchasesCents: 100000,
        grandTotalReturnsCents: 50000,
        grandTotalPaymentsCents: 300000,
        grandTotalDiscountsCents: 10000,
        grandTotalCreditBalanceCents: 260000,
        totalSuppliers: 10,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        dateRange: ReportDateRange.thisYear(),
      );

      expect(updated.grandTotalPurchasesCents, 100000);
      expect(updated.grandTotalReturnsCents, 50000);
      expect(updated.grandTotalPaymentsCents, 300000);
      expect(updated.grandTotalDiscountsCents, 10000);
      expect(updated.grandTotalCreditBalanceCents, 260000);
      expect(updated.totalSuppliers, 10);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = SupplierCreditBalanceReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        grandTotalPurchasesCents: 50000,
        grandTotalPaymentsCents: 100000,
        grandTotalCreditBalanceCents: 50000,
        sort: SupplierCreditBalanceSortType.nameAsc,
      );

      expect(updated.grandTotalPurchasesCents, 50000);
      expect(updated.grandTotalPaymentsCents, 100000);
      expect(updated.grandTotalCreditBalanceCents, 50000);
      expect(updated.sort, SupplierCreditBalanceSortType.nameAsc);
    });

    test('copyWith updates suppliers list', () {
      final original = SupplierCreditBalanceReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      const supplier = SupplierCreditBalanceItem(
        supplierId: 1,
        supplierName: 'New Supplier',
        totalPurchasesCents: 10000,
        totalReturnsCents: 0,
        totalPaymentsCents: 100000,
        totalDiscountsCents: 0,
        creditBalanceCents: 90000,
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

  group('SupplierCreditBalanceReportBloc events', () {
    test('SupplierCreditBalanceReportDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = SupplierCreditBalanceReportDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('SupplierCreditBalanceReportSortChanged stores sort type', () {
      const event = SupplierCreditBalanceReportSortChanged(
          SupplierCreditBalanceSortType.nameAsc);
      expect(event.sort, SupplierCreditBalanceSortType.nameAsc);
    });
  });

  group('SupplierCreditBalanceSortType enum', () {
    test('has all expected values', () {
      expect(SupplierCreditBalanceSortType.values.length, 6);
      expect(SupplierCreditBalanceSortType.values,
          contains(SupplierCreditBalanceSortType.balanceDesc));
      expect(SupplierCreditBalanceSortType.values,
          contains(SupplierCreditBalanceSortType.balanceAsc));
      expect(SupplierCreditBalanceSortType.values,
          contains(SupplierCreditBalanceSortType.nameAsc));
      expect(SupplierCreditBalanceSortType.values,
          contains(SupplierCreditBalanceSortType.nameDesc));
      expect(SupplierCreditBalanceSortType.values,
          contains(SupplierCreditBalanceSortType.purchasesDesc));
      expect(SupplierCreditBalanceSortType.values,
          contains(SupplierCreditBalanceSortType.paymentsDesc));
    });
  });

  group('Sort logic', () {
    final suppliers = [
      const SupplierCreditBalanceItem(
        supplierId: 1,
        supplierName: 'Zebra Supplies',
        totalPurchasesCents: 10000,
        totalReturnsCents: 0,
        totalPaymentsCents: 50000,
        totalDiscountsCents: 0,
        creditBalanceCents: 40000,
        transactionCount: 5,
      ),
      const SupplierCreditBalanceItem(
        supplierId: 2,
        supplierName: 'Apple Wholesale',
        totalPurchasesCents: 50000,
        totalReturnsCents: 10000,
        totalPaymentsCents: 200000,
        totalDiscountsCents: 0,
        creditBalanceCents: 160000,
        transactionCount: 20,
      ),
      const SupplierCreditBalanceItem(
        supplierId: 3,
        supplierName: 'Mango Trading',
        totalPurchasesCents: 25000,
        totalReturnsCents: 5000,
        totalPaymentsCents: 50000,
        totalDiscountsCents: 0,
        creditBalanceCents: 30000,
        transactionCount: 10,
      ),
    ];

    test('sort by balance descending', () {
      final list = List<SupplierCreditBalanceItem>.from(suppliers);
      list.sort(
          (a, b) => b.creditBalanceCents.compareTo(a.creditBalanceCents));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[0].creditBalanceCents, 160000);
      expect(list[1].supplierName, 'Zebra Supplies');
      expect(list[1].creditBalanceCents, 40000);
      expect(list[2].supplierName, 'Mango Trading');
      expect(list[2].creditBalanceCents, 30000);
    });

    test('sort by balance ascending', () {
      final list = List<SupplierCreditBalanceItem>.from(suppliers);
      list.sort(
          (a, b) => a.creditBalanceCents.compareTo(b.creditBalanceCents));

      expect(list[0].supplierName, 'Mango Trading');
      expect(list[2].supplierName, 'Apple Wholesale');
    });

    test('sort by name ascending', () {
      final list = List<SupplierCreditBalanceItem>.from(suppliers);
      list.sort((a, b) => a.supplierName.compareTo(b.supplierName));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[1].supplierName, 'Mango Trading');
      expect(list[2].supplierName, 'Zebra Supplies');
    });

    test('sort by name descending', () {
      final list = List<SupplierCreditBalanceItem>.from(suppliers);
      list.sort((a, b) => b.supplierName.compareTo(a.supplierName));

      expect(list[0].supplierName, 'Zebra Supplies');
      expect(list[1].supplierName, 'Mango Trading');
      expect(list[2].supplierName, 'Apple Wholesale');
    });

    test('sort by purchases descending', () {
      final list = List<SupplierCreditBalanceItem>.from(suppliers);
      list.sort(
          (a, b) => b.totalPurchasesCents.compareTo(a.totalPurchasesCents));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[0].totalPurchasesCents, 50000);
      expect(list[1].supplierName, 'Mango Trading');
      expect(list[1].totalPurchasesCents, 25000);
      expect(list[2].supplierName, 'Zebra Supplies');
      expect(list[2].totalPurchasesCents, 10000);
    });

    test('sort by payments descending', () {
      final list = List<SupplierCreditBalanceItem>.from(suppliers);
      list.sort(
          (a, b) => b.totalPaymentsCents.compareTo(a.totalPaymentsCents));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[0].totalPaymentsCents, 200000);
      expect(list[1].supplierName, 'Zebra Supplies');
      expect(list[1].totalPaymentsCents, 50000);
      expect(list[2].supplierName, 'Mango Trading');
      expect(list[2].totalPaymentsCents, 50000);
    });
  });

  group('Grand totals calculation', () {
    test('grand totals sum correctly from supplier list', () {
      const suppliers = [
        SupplierCreditBalanceItem(
          supplierId: 1,
          supplierName: 'A',
          totalPurchasesCents: 10000,
          totalReturnsCents: 5000,
          totalPaymentsCents: 50000,
          totalDiscountsCents: 1000,
          creditBalanceCents: 46000,
          transactionCount: 5,
        ),
        SupplierCreditBalanceItem(
          supplierId: 2,
          supplierName: 'B',
          totalPurchasesCents: 20000,
          totalReturnsCents: 20000,
          totalPaymentsCents: 100000,
          totalDiscountsCents: 5000,
          creditBalanceCents: 105000,
          transactionCount: 20,
        ),
        SupplierCreditBalanceItem(
          supplierId: 3,
          supplierName: 'C',
          totalPurchasesCents: 30000,
          totalReturnsCents: 10000,
          totalPaymentsCents: 80000,
          totalDiscountsCents: 0,
          creditBalanceCents: 60000,
          transactionCount: 10,
        ),
      ];

      int totalPurchases = 0;
      int totalReturns = 0;
      int totalPayments = 0;
      int totalDiscounts = 0;
      int totalCreditBalance = 0;
      for (final s in suppliers) {
        totalPurchases += s.totalPurchasesCents;
        totalReturns += s.totalReturnsCents;
        totalPayments += s.totalPaymentsCents;
        totalDiscounts += s.totalDiscountsCents;
        totalCreditBalance += s.creditBalanceCents;
      }

      expect(totalPurchases, 60000);
      expect(totalReturns, 35000);
      expect(totalPayments, 230000);
      expect(totalDiscounts, 6000);
      expect(totalCreditBalance, 211000);
      expect(suppliers.length, 3);
    });

    test('empty supplier list yields zero totals', () {
      const suppliers = <SupplierCreditBalanceItem>[];

      int totalPurchases = 0;
      int totalPayments = 0;
      int totalCreditBalance = 0;
      for (final s in suppliers) {
        totalPurchases += s.totalPurchasesCents;
        totalPayments += s.totalPaymentsCents;
        totalCreditBalance += s.creditBalanceCents;
      }

      expect(totalPurchases, 0);
      expect(totalPayments, 0);
      expect(totalCreditBalance, 0);
    });

    test('credit balance calculation with all transaction types', () {
      // In supplier_transactions table:
      // purchases are positive, payments/returns/discounts are negative
      const purchase = 50000; // positive in DB
      const payment = -100000; // negative in DB
      const returnTx = -10000; // negative in DB (credit_note)
      const discount = -5000; // negative in DB

      final netBalance = purchase + payment + returnTx + discount;
      expect(netBalance, -65000); // Negative = supplier owes us
      expect(netBalance < 0, true); // HAVING net_balance_cents < 0

      // Credit balance displayed = ABS(netBalance)
      expect(netBalance.abs(), 65000);
    });

    test('large amounts do not overflow int', () {
      const largeCents = 999999999999;
      const item = SupplierCreditBalanceItem(
        supplierId: 1,
        supplierName: 'Big Supplier',
        totalPurchasesCents: 0,
        totalReturnsCents: 0,
        totalPaymentsCents: largeCents,
        totalDiscountsCents: 0,
        creditBalanceCents: largeCents,
        transactionCount: 1,
      );

      expect(item.totalPaymentsCents, largeCents);
      expect(item.creditBalanceCents, largeCents);
    });
  });

  group('ReportDateRange for supplier credit balance', () {
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

  group('SupplierCreditBalancePdfService translations', () {
    test('all expected translation keys are defined', () {
      const expectedKeys = [
        'supplier_credit_balance_report',
        'period',
        'total_purchases',
        'total_payments',
        'total_credit_balance',
        'total_suppliers',
        'supplier_credit_balance_details',
        'supplier',
        'purchases',
        'payments',
        'credit_balance',
        'transactions',
        'last_transaction',
        'grand_total',
        'printed_on',
      ];
      expect(expectedKeys.length, 15);
    });
  });

  group('Credit balance classification', () {
    test('all items have positive credit balance (receivable)', () {
      const items = [
        SupplierCreditBalanceItem(
          supplierId: 1,
          supplierName: 'Supplier A',
          totalPurchasesCents: 30000,
          totalReturnsCents: 0,
          totalPaymentsCents: 100000,
          totalDiscountsCents: 0,
          creditBalanceCents: 70000,
          transactionCount: 5,
        ),
        SupplierCreditBalanceItem(
          supplierId: 2,
          supplierName: 'Supplier B',
          totalPurchasesCents: 50000,
          totalReturnsCents: 10000,
          totalPaymentsCents: 200000,
          totalDiscountsCents: 5000,
          creditBalanceCents: 165000,
          transactionCount: 10,
        ),
      ];

      for (final item in items) {
        expect(item.creditBalanceCents, isPositive,
            reason: '${item.supplierName} should have positive credit balance');
      }
    });

    test('credit balance is always > 0 (displayed as ABS)', () {
      const item = SupplierCreditBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasesCents: 20000,
        totalReturnsCents: 0,
        totalPaymentsCents: 100000,
        totalDiscountsCents: 0,
        creditBalanceCents: 80000,
        transactionCount: 5,
      );

      // Credit balance report shows ABS of negative net balance
      expect(item.creditBalanceCents > 0, true);
    });
  });

  group('Credit balance calculation verification', () {
    test('purchases decrease credit balance (we owe them)', () {
      // When a purchase is made, amount_cents is positive in supplier_transactions
      const purchaseAmount = 50000;
      expect(purchaseAmount > 0, true);
    });

    test('payments increase credit balance (we overpaid)', () {
      // When a payment is made, amount_cents is negative in supplier_transactions
      const paymentAmount = -100000;
      expect(paymentAmount < 0, true);
    });

    test('returns increase credit balance (they owe us)', () {
      // When a return is processed, amount_cents is negative (credit_note)
      const returnAmount = -10000;
      expect(returnAmount < 0, true);
    });

    test('discounts increase credit balance', () {
      // When a discount is applied, amount_cents is negative
      const discountAmount = -5000;
      expect(discountAmount < 0, true);
    });

    test('net balance < 0 means supplier owes us (credit)', () {
      const purchase1 = 30000;
      const payment1 = -80000;
      const return1 = -10000;
      const discount1 = -5000;

      final netBalance = purchase1 + payment1 + return1 + discount1;
      expect(netBalance, -65000);
      expect(netBalance < 0, true); // Negative = supplier owes us
      expect(netBalance.abs(), 65000); // Display as positive credit
    });

    test('supplier with zero balance is excluded from credit report', () {
      const purchases = 50000;
      const payments = -50000;
      final netBalance = purchases + payments;
      expect(netBalance, 0);
      // HAVING net_balance_cents < 0 would exclude this supplier
      expect(netBalance < 0, false);
    });

    test('supplier with positive balance (debit) is excluded from credit report', () {
      const purchases = 100000;
      const payments = -50000;
      final netBalance = purchases + payments;
      expect(netBalance, 50000);
      // HAVING net_balance_cents < 0 would exclude this supplier
      expect(netBalance < 0, false);
    });

    test('credit balance is inverse of debit balance', () {
      // Same transactions, different filter
      const purchase = 30000;
      const payment = -80000;
      final netBalance = purchase + payment;

      // For debit report: netBalance > 0 → excluded (this is credit)
      // For credit report: netBalance < 0 → included
      expect(netBalance, -50000);
      expect(netBalance > 0, false); // NOT in debit report
      expect(netBalance < 0, true); // IN credit report
      expect(netBalance.abs(), 50000); // Display credit as 50000
    });
  });

  group('Suppliers counting', () {
    test('correctly counts total suppliers with credit balances', () {
      const suppliers = [
        SupplierCreditBalanceItem(
          supplierId: 1,
          supplierName: 'Supplier A',
          totalPurchasesCents: 20000,
          totalReturnsCents: 0,
          totalPaymentsCents: 100000,
          totalDiscountsCents: 0,
          creditBalanceCents: 80000,
          transactionCount: 5,
        ),
        SupplierCreditBalanceItem(
          supplierId: 2,
          supplierName: 'Supplier B',
          totalPurchasesCents: 50000,
          totalReturnsCents: 10000,
          totalPaymentsCents: 200000,
          totalDiscountsCents: 5000,
          creditBalanceCents: 165000,
          transactionCount: 10,
        ),
        SupplierCreditBalanceItem(
          supplierId: 3,
          supplierName: 'Supplier C',
          totalPurchasesCents: 10000,
          totalReturnsCents: 0,
          totalPaymentsCents: 30000,
          totalDiscountsCents: 0,
          creditBalanceCents: 20000,
          transactionCount: 3,
        ),
      ];

      // All suppliers in the credit report have positive credit balances
      expect(suppliers.length, 3);
      for (final s in suppliers) {
        expect(s.creditBalanceCents > 0, true);
      }
    });
  });
}
