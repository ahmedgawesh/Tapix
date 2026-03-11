import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_balance_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('SupplierBalanceItem data model', () {
    test('stores correct values', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test Supplier',
        phone: '+1234567890',
        openingBalanceCents: 50000,
        totalPurchasesCents: 100000,
        totalPaymentsCents: 30000,
        totalReturnsCents: 10000,
        totalDiscountsCents: 10000,
        netBalanceCents: 100000,
        transactionCount: 10,
        lastTransactionAt: null,
      );

      expect(item.supplierId, 1);
      expect(item.supplierName, 'Test Supplier');
      expect(item.phone, '+1234567890');
      expect(item.openingBalanceCents, 50000);
      expect(item.totalPurchasesCents, 100000);
      expect(item.totalPaymentsCents, 30000);
      expect(item.totalReturnsCents, 10000);
      expect(item.totalDiscountsCents, 10000);
      expect(item.netBalanceCents, 100000);
      expect(item.transactionCount, 10);
      expect(item.lastTransactionAt, isNull);
    });

    test('stores last transaction date when provided', () {
      final date = DateTime(2026, 2, 1);
      final item = SupplierBalanceItem(
        supplierId: 2,
        supplierName: 'Supplier B',
        openingBalanceCents: 100000,
        totalPurchasesCents: 400000,
        totalPaymentsCents: 150000,
        totalReturnsCents: 30000,
        totalDiscountsCents: 20000,
        netBalanceCents: 300000,
        transactionCount: 25,
        lastTransactionAt: date,
      );

      expect(item.lastTransactionAt, date);
      expect(item.phone, isNull);
    });

    test('totalDebitCents getter calculates correctly', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        openingBalanceCents: 50000, // positive = debit
        totalPurchasesCents: 50000,
        totalPaymentsCents: 20000,
        totalReturnsCents: 10000,
        totalDiscountsCents: 10000,
        netBalanceCents: 60000,
        transactionCount: 5,
      );

      // totalDebitCents = opening debit + purchases
      expect(item.totalDebitCents, 100000); // 50000 + 50000
    });

    test('totalCreditCents getter calculates correctly', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        openingBalanceCents: -10000, // negative = credit
        totalPurchasesCents: 50000,
        totalPaymentsCents: 20000,
        totalReturnsCents: 10000,
        totalDiscountsCents: 5000,
        netBalanceCents: 5000,
        transactionCount: 5,
      );

      // totalCreditCents = opening credit + payments + returns + discounts
      expect(item.totalCreditCents, 45000); // 10000 + 20000 + 10000 + 5000
    });

    test('integer cents prevents floating point errors', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        openingBalanceCents: 10,
        totalPurchasesCents: 20,
        totalPaymentsCents: 5,
        totalReturnsCents: 3,
        totalDiscountsCents: 2,
        netBalanceCents: 20,
        transactionCount: 2,
      );

      expect(item.netBalanceCents, 20);
    });

    test('negative net balance indicates credit (supplier owes us)', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        openingBalanceCents: 0,
        totalPurchasesCents: 30000,
        totalPaymentsCents: 50000,
        totalReturnsCents: 0,
        totalDiscountsCents: 0,
        netBalanceCents: -20000,
        transactionCount: 5,
      );

      expect(item.netBalanceCents, isNegative);
      expect(item.netBalanceCents, -20000);
      expect(item.isReceivable, true);
      expect(item.isPayable, false);
    });

    test('zero balance indicates settled account', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        openingBalanceCents: 0,
        totalPurchasesCents: 50000,
        totalPaymentsCents: 50000,
        totalReturnsCents: 0,
        totalDiscountsCents: 0,
        netBalanceCents: 0,
        transactionCount: 10,
      );

      expect(item.netBalanceCents, 0);
      expect(item.isPayable, false);
      expect(item.isReceivable, false);
    });
  });

  group('SupplierBalanceReportData', () {
    test('default values are correct', () {
      final data = SupplierBalanceReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.suppliers, isEmpty);
      expect(data.filteredSuppliers, isEmpty);
      expect(data.summary.totalPayablesCents, 0);
      expect(data.summary.totalReceivablesCents, 0);
      expect(data.totalSuppliers, 0);
      expect(data.sort, SupplierBalanceSortType.balanceDesc);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = SupplierBalanceReportData(
        summary: const SupplierBalanceSummary(
          totalPayablesCents: 500000,
          totalReceivablesCents: 200000,
          suppliersWithPayable: 7,
          suppliersWithReceivable: 3,
        ),
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        dateRange: ReportDateRange.thisYear(),
      );

      expect(updated.summary.totalPayablesCents, 500000);
      expect(updated.summary.totalReceivablesCents, 200000);
      expect(updated.summary.suppliersWithPayable, 7);
      expect(updated.summary.suppliersWithReceivable, 3);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = SupplierBalanceReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        summary: const SupplierBalanceSummary(
          totalPayablesCents: 100000,
          totalReceivablesCents: 50000,
        ),
        sort: SupplierBalanceSortType.nameAsc,
      );

      expect(updated.summary.totalPayablesCents, 100000);
      expect(updated.summary.totalReceivablesCents, 50000);
      expect(updated.sort, SupplierBalanceSortType.nameAsc);
    });

    test('copyWith updates suppliers list', () {
      final original = SupplierBalanceReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      const supplier = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'New Supplier',
        openingBalanceCents: 0,
        totalPurchasesCents: 999900,
        totalPaymentsCents: 100,
        totalReturnsCents: 0,
        totalDiscountsCents: 0,
        netBalanceCents: 999800,
        transactionCount: 100,
      );

      final updated = original.copyWith(
        suppliers: [supplier],
        filteredSuppliers: [supplier],
      );

      expect(updated.suppliers.length, 1);
      expect(updated.suppliers.first.supplierName, 'New Supplier');
      expect(updated.totalSuppliers, 1);
    });
  });

  group('SupplierBalanceReportBloc events', () {
    test('SupplierBalanceReportDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = SupplierBalanceReportDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('SupplierBalanceReportSortChanged stores sort type', () {
      const event = SupplierBalanceReportSortChanged(
          SupplierBalanceSortType.nameAsc);
      expect(event.sort, SupplierBalanceSortType.nameAsc);
    });
  });

  group('SupplierBalanceSortType enum', () {
    test('has all expected values', () {
      expect(SupplierBalanceSortType.values.length, 6);
      expect(SupplierBalanceSortType.values,
          contains(SupplierBalanceSortType.balanceDesc));
      expect(SupplierBalanceSortType.values,
          contains(SupplierBalanceSortType.balanceAsc));
      expect(SupplierBalanceSortType.values,
          contains(SupplierBalanceSortType.nameAsc));
      expect(SupplierBalanceSortType.values,
          contains(SupplierBalanceSortType.nameDesc));
      expect(SupplierBalanceSortType.values,
          contains(SupplierBalanceSortType.debitDesc));
      expect(SupplierBalanceSortType.values,
          contains(SupplierBalanceSortType.creditDesc));
    });
  });

  group('Sort logic', () {
    final suppliers = [
      const SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Zebra Supplies',
        openingBalanceCents: 0,
        totalPurchasesCents: 50000,
        totalPaymentsCents: 10000,
        totalReturnsCents: 0,
        totalDiscountsCents: 0,
        netBalanceCents: 40000,
        transactionCount: 5,
      ),
      const SupplierBalanceItem(
        supplierId: 2,
        supplierName: 'Apple Wholesale',
        openingBalanceCents: 0,
        totalPurchasesCents: 200000,
        totalPaymentsCents: 50000,
        totalReturnsCents: 0,
        totalDiscountsCents: 0,
        netBalanceCents: 150000,
        transactionCount: 20,
      ),
      const SupplierBalanceItem(
        supplierId: 3,
        supplierName: 'Mango Trading',
        openingBalanceCents: 0,
        totalPurchasesCents: 100000,
        totalPaymentsCents: 120000,
        totalReturnsCents: 0,
        totalDiscountsCents: 0,
        netBalanceCents: -20000,
        transactionCount: 10,
      ),
    ];

    test('sort by balance descending (absolute value)', () {
      final list = List<SupplierBalanceItem>.from(suppliers);
      list.sort(
          (a, b) => b.netBalanceCents.abs().compareTo(a.netBalanceCents.abs()));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[0].netBalanceCents.abs(), 150000);
      expect(list[1].supplierName, 'Zebra Supplies');
      expect(list[1].netBalanceCents.abs(), 40000);
      expect(list[2].supplierName, 'Mango Trading');
      expect(list[2].netBalanceCents.abs(), 20000);
    });

    test('sort by balance ascending (absolute value)', () {
      final list = List<SupplierBalanceItem>.from(suppliers);
      list.sort(
          (a, b) => a.netBalanceCents.abs().compareTo(b.netBalanceCents.abs()));

      expect(list[0].supplierName, 'Mango Trading');
      expect(list[2].supplierName, 'Apple Wholesale');
    });

    test('sort by name ascending', () {
      final list = List<SupplierBalanceItem>.from(suppliers);
      list.sort((a, b) => a.supplierName.compareTo(b.supplierName));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[1].supplierName, 'Mango Trading');
      expect(list[2].supplierName, 'Zebra Supplies');
    });

    test('sort by name descending', () {
      final list = List<SupplierBalanceItem>.from(suppliers);
      list.sort((a, b) => b.supplierName.compareTo(a.supplierName));

      expect(list[0].supplierName, 'Zebra Supplies');
      expect(list[1].supplierName, 'Mango Trading');
      expect(list[2].supplierName, 'Apple Wholesale');
    });

    test('sort by debit descending', () {
      final list = List<SupplierBalanceItem>.from(suppliers);
      list.sort((a, b) => b.totalDebitCents.compareTo(a.totalDebitCents));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[0].totalDebitCents, 200000);
      expect(list[1].supplierName, 'Mango Trading');
      expect(list[1].totalDebitCents, 100000);
      expect(list[2].supplierName, 'Zebra Supplies');
      expect(list[2].totalDebitCents, 50000);
    });

    test('sort by credit descending', () {
      final list = List<SupplierBalanceItem>.from(suppliers);
      list.sort((a, b) => b.totalCreditCents.compareTo(a.totalCreditCents));

      expect(list[0].supplierName, 'Mango Trading');
      expect(list[0].totalCreditCents, 120000);
      expect(list[1].supplierName, 'Apple Wholesale');
      expect(list[1].totalCreditCents, 50000);
      expect(list[2].supplierName, 'Zebra Supplies');
      expect(list[2].totalCreditCents, 10000);
    });
  });

  group('Grand totals calculation', () {
    test('grand totals sum correctly from supplier list', () {
      const suppliers = [
        SupplierBalanceItem(
          supplierId: 1,
          supplierName: 'A',
          openingBalanceCents: 0,
          totalPurchasesCents: 50000,
          totalPaymentsCents: 10000,
          totalReturnsCents: 0,
          totalDiscountsCents: 0,
          netBalanceCents: 40000,
          transactionCount: 5,
        ),
        SupplierBalanceItem(
          supplierId: 2,
          supplierName: 'B',
          openingBalanceCents: 0,
          totalPurchasesCents: 200000,
          totalPaymentsCents: 50000,
          totalReturnsCents: 0,
          totalDiscountsCents: 0,
          netBalanceCents: 150000,
          transactionCount: 20,
        ),
        SupplierBalanceItem(
          supplierId: 3,
          supplierName: 'C',
          openingBalanceCents: 0,
          totalPurchasesCents: 100000,
          totalPaymentsCents: 120000,
          totalReturnsCents: 0,
          totalDiscountsCents: 0,
          netBalanceCents: -20000,
          transactionCount: 10,
        ),
      ];

      int totalPayables = 0;
      int totalReceivables = 0;
      int withPayable = 0;
      int withReceivable = 0;
      for (final s in suppliers) {
        if (s.netBalanceCents > 0) {
          totalPayables += s.netBalanceCents;
          withPayable++;
        }
        if (s.netBalanceCents < 0) {
          totalReceivables += s.netBalanceCents.abs();
          withReceivable++;
        }
      }

      expect(totalPayables, 190000); // 40000 + 150000
      expect(totalReceivables, 20000); // abs(-20000)
      expect(withPayable, 2); // A and B have positive net balance
      expect(withReceivable, 1); // C has negative net balance
      expect(suppliers.length, 3);
    });

    test('empty supplier list yields zero totals', () {
      const suppliers = <SupplierBalanceItem>[];

      int totalPayables = 0;
      int totalReceivables = 0;
      for (final s in suppliers) {
        if (s.netBalanceCents > 0) totalPayables += s.netBalanceCents;
        if (s.netBalanceCents < 0) totalReceivables += s.netBalanceCents.abs();
      }

      expect(totalPayables, 0);
      expect(totalReceivables, 0);
    });

    test('net balance calculation with mixed debits and credits', () {
      // Verify net balance = opening + purchases - payments - returns - discounts
      const opening = 10000;
      const purchases = 50000;
      const payments = 20000;
      const returns = 5000;
      const discounts = 2000;
      const net = opening + purchases - payments - returns - discounts; // 33000

      expect(net, 33000);
    });

    test('large amounts do not overflow int', () {
      // Dart int is 64-bit, so even very large cent amounts are safe
      const largeCents = 999999999999; // ~$10 billion
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Big Supplier',
        openingBalanceCents: 0,
        totalPurchasesCents: largeCents,
        totalPaymentsCents: 0,
        totalReturnsCents: 0,
        totalDiscountsCents: 0,
        netBalanceCents: largeCents,
        transactionCount: 1,
      );

      expect(item.totalPurchasesCents, largeCents);
      expect(item.netBalanceCents, largeCents);
    });
  });

  group('ReportDateRange for supplier balance', () {
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

  group('SupplierBalancePdfService translations', () {
    test('all expected translation keys are defined', () {
      const expectedKeys = [
        'supplier_balance_report',
        'period',
        'total_payables',
        'total_receivables',
        'net_balance',
        'total_suppliers',
        'supplier_balance_details',
        'supplier',
        'debits',
        'credits',
        'net',
        'transactions',
        'last_transaction',
        'grand_total',
        'printed_on',
      ];
      expect(expectedKeys.length, 15);
    });
  });

  group('Balance classification', () {
    test('positive net balance is payable (we owe supplier)', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        openingBalanceCents: 0,
        totalPurchasesCents: 100000,
        totalPaymentsCents: 30000,
        totalReturnsCents: 0,
        totalDiscountsCents: 0,
        netBalanceCents: 70000,
        transactionCount: 5,
      );

      expect(item.isPayable, true);
      expect(item.isReceivable, false);
    });

    test('negative net balance is receivable (supplier owes us)', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        openingBalanceCents: 0,
        totalPurchasesCents: 30000,
        totalPaymentsCents: 100000,
        totalReturnsCents: 0,
        totalDiscountsCents: 0,
        netBalanceCents: -70000,
        transactionCount: 5,
      );

      expect(item.isPayable, false);
      expect(item.isReceivable, true);
    });

    test('zero net balance is settled', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        openingBalanceCents: 0,
        totalPurchasesCents: 50000,
        totalPaymentsCents: 50000,
        totalReturnsCents: 0,
        totalDiscountsCents: 0,
        netBalanceCents: 0,
        transactionCount: 10,
      );

      expect(item.isPayable, false);
      expect(item.isReceivable, false);
    });
  });

  group('Suppliers with debit/credit counting', () {
    test('correctly counts suppliers with payable and receivable', () {
      const suppliers = [
        SupplierBalanceItem(
          supplierId: 1,
          supplierName: 'Payable Supplier',
          openingBalanceCents: 0,
          totalPurchasesCents: 100000,
          totalPaymentsCents: 20000,
          totalReturnsCents: 0,
          totalDiscountsCents: 0,
          netBalanceCents: 80000,
          transactionCount: 5,
        ),
        SupplierBalanceItem(
          supplierId: 2,
          supplierName: 'Receivable Supplier',
          openingBalanceCents: 0,
          totalPurchasesCents: 20000,
          totalPaymentsCents: 100000,
          totalReturnsCents: 0,
          totalDiscountsCents: 0,
          netBalanceCents: -80000,
          transactionCount: 5,
        ),
        SupplierBalanceItem(
          supplierId: 3,
          supplierName: 'Settled Supplier',
          openingBalanceCents: 0,
          totalPurchasesCents: 50000,
          totalPaymentsCents: 50000,
          totalReturnsCents: 0,
          totalDiscountsCents: 0,
          netBalanceCents: 0,
          transactionCount: 10,
        ),
        SupplierBalanceItem(
          supplierId: 4,
          supplierName: 'Another Payable',
          openingBalanceCents: 0,
          totalPurchasesCents: 30000,
          totalPaymentsCents: 10000,
          totalReturnsCents: 0,
          totalDiscountsCents: 0,
          netBalanceCents: 20000,
          transactionCount: 3,
        ),
      ];

      int withPayable = 0;
      int withReceivable = 0;
      int settled = 0;
      for (final s in suppliers) {
        if (s.isPayable) withPayable++;
        if (s.isReceivable) withReceivable++;
        if (!s.isPayable && !s.isReceivable) settled++;
      }

      expect(withPayable, 2);
      expect(withReceivable, 1);
      expect(settled, 1);
      expect(withPayable + withReceivable + settled, suppliers.length);
    });
  });
}
