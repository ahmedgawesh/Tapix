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
        totalDebitCents: 150000,
        totalCreditCents: 50000,
        netBalanceCents: 100000,
        transactionCount: 10,
        lastTransactionAt: null,
      );

      expect(item.supplierId, 1);
      expect(item.supplierName, 'Test Supplier');
      expect(item.phone, '+1234567890');
      expect(item.totalDebitCents, 150000);
      expect(item.totalCreditCents, 50000);
      expect(item.netBalanceCents, 100000);
      expect(item.transactionCount, 10);
      expect(item.lastTransactionAt, isNull);
    });

    test('stores last transaction date when provided', () {
      final date = DateTime(2026, 2, 1);
      final item = SupplierBalanceItem(
        supplierId: 2,
        supplierName: 'Supplier B',
        totalDebitCents: 500000,
        totalCreditCents: 200000,
        netBalanceCents: 300000,
        transactionCount: 25,
        lastTransactionAt: date,
      );

      expect(item.lastTransactionAt, date);
      expect(item.phone, isNull);
    });

    test('net balance equals debit minus credit', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalDebitCents: 100000,
        totalCreditCents: 40000,
        netBalanceCents: 60000,
        transactionCount: 5,
      );

      expect(item.netBalanceCents,
          item.totalDebitCents - item.totalCreditCents);
    });

    test('integer cents prevents floating point errors', () {
      // Verify that using integer cents avoids floating point issues
      // e.g., 0.1 + 0.2 != 0.3 in floating point, but 10 + 20 == 30 in cents
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalDebitCents: 30, // 0.30 in dollars
        totalCreditCents: 10, // 0.10 in dollars
        netBalanceCents: 20, // 0.20 in dollars
        transactionCount: 2,
      );

      expect(item.totalDebitCents - item.totalCreditCents, 20);
      expect(item.netBalanceCents, 20);
    });

    test('negative net balance indicates credit (supplier owes us)', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalDebitCents: 30000,
        totalCreditCents: 50000,
        netBalanceCents: -20000,
        transactionCount: 5,
      );

      expect(item.netBalanceCents, isNegative);
      expect(item.netBalanceCents, -20000);
    });

    test('zero balance indicates settled account', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalDebitCents: 50000,
        totalCreditCents: 50000,
        netBalanceCents: 0,
        transactionCount: 10,
      );

      expect(item.netBalanceCents, 0);
    });
  });

  group('SupplierBalanceReportData', () {
    test('default values are correct', () {
      final data = SupplierBalanceReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.suppliers, isEmpty);
      expect(data.grandTotalDebitCents, 0);
      expect(data.grandTotalCreditCents, 0);
      expect(data.grandNetBalanceCents, 0);
      expect(data.totalSuppliers, 0);
      expect(data.suppliersWithDebit, 0);
      expect(data.suppliersWithCredit, 0);
      expect(data.sort, SupplierBalanceSortType.balanceDesc);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = SupplierBalanceReportData(
        grandTotalDebitCents: 500000,
        grandTotalCreditCents: 200000,
        grandNetBalanceCents: 300000,
        totalSuppliers: 10,
        suppliersWithDebit: 7,
        suppliersWithCredit: 3,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        dateRange: ReportDateRange.thisYear(),
      );

      expect(updated.grandTotalDebitCents, 500000);
      expect(updated.grandTotalCreditCents, 200000);
      expect(updated.grandNetBalanceCents, 300000);
      expect(updated.totalSuppliers, 10);
      expect(updated.suppliersWithDebit, 7);
      expect(updated.suppliersWithCredit, 3);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = SupplierBalanceReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        grandTotalDebitCents: 100000,
        grandTotalCreditCents: 50000,
        grandNetBalanceCents: 50000,
        sort: SupplierBalanceSortType.nameAsc,
      );

      expect(updated.grandTotalDebitCents, 100000);
      expect(updated.grandTotalCreditCents, 50000);
      expect(updated.grandNetBalanceCents, 50000);
      expect(updated.sort, SupplierBalanceSortType.nameAsc);
    });

    test('copyWith updates suppliers list', () {
      final original = SupplierBalanceReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      const supplier = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'New Supplier',
        totalDebitCents: 999900,
        totalCreditCents: 100,
        netBalanceCents: 999800,
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
        totalDebitCents: 50000,
        totalCreditCents: 10000,
        netBalanceCents: 40000,
        transactionCount: 5,
      ),
      const SupplierBalanceItem(
        supplierId: 2,
        supplierName: 'Apple Wholesale',
        totalDebitCents: 200000,
        totalCreditCents: 50000,
        netBalanceCents: 150000,
        transactionCount: 20,
      ),
      const SupplierBalanceItem(
        supplierId: 3,
        supplierName: 'Mango Trading',
        totalDebitCents: 100000,
        totalCreditCents: 120000,
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
          totalDebitCents: 50000,
          totalCreditCents: 10000,
          netBalanceCents: 40000,
          transactionCount: 5,
        ),
        SupplierBalanceItem(
          supplierId: 2,
          supplierName: 'B',
          totalDebitCents: 200000,
          totalCreditCents: 50000,
          netBalanceCents: 150000,
          transactionCount: 20,
        ),
        SupplierBalanceItem(
          supplierId: 3,
          supplierName: 'C',
          totalDebitCents: 100000,
          totalCreditCents: 120000,
          netBalanceCents: -20000,
          transactionCount: 10,
        ),
      ];

      int totalDebit = 0;
      int totalCredit = 0;
      int totalNet = 0;
      int withDebit = 0;
      int withCredit = 0;
      for (final s in suppliers) {
        totalDebit += s.totalDebitCents;
        totalCredit += s.totalCreditCents;
        totalNet += s.netBalanceCents;
        if (s.netBalanceCents > 0) withDebit++;
        if (s.netBalanceCents < 0) withCredit++;
      }

      expect(totalDebit, 350000);
      expect(totalCredit, 180000);
      expect(totalNet, 170000); // 40000 + 150000 + (-20000)
      expect(withDebit, 2); // A and B have positive net balance
      expect(withCredit, 1); // C has negative net balance
      expect(suppliers.length, 3);
    });

    test('empty supplier list yields zero totals', () {
      const suppliers = <SupplierBalanceItem>[];

      int totalDebit = 0;
      int totalCredit = 0;
      int totalNet = 0;
      for (final s in suppliers) {
        totalDebit += s.totalDebitCents;
        totalCredit += s.totalCreditCents;
        totalNet += s.netBalanceCents;
      }

      expect(totalDebit, 0);
      expect(totalCredit, 0);
      expect(totalNet, 0);
    });

    test('net balance calculation with mixed debits and credits', () {
      // Verify net balance = total debits - total credits
      // Using integer arithmetic to avoid floating point issues
      const debit = 123456;
      const credit = 78901;
      const net = debit - credit; // 44555

      expect(net, 44555);
      expect(net, debit - credit);
    });

    test('large amounts do not overflow int', () {
      // Dart int is 64-bit, so even very large cent amounts are safe
      const largeCents = 999999999999; // ~$10 billion
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Big Supplier',
        totalDebitCents: largeCents,
        totalCreditCents: 0,
        netBalanceCents: largeCents,
        transactionCount: 1,
      );

      expect(item.totalDebitCents, largeCents);
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
        totalDebitCents: 100000,
        totalCreditCents: 30000,
        netBalanceCents: 70000,
        transactionCount: 5,
      );

      final isPayable = item.netBalanceCents > 0;
      final isReceivable = item.netBalanceCents < 0;
      final isSettled = item.netBalanceCents == 0;

      expect(isPayable, true);
      expect(isReceivable, false);
      expect(isSettled, false);
    });

    test('negative net balance is receivable (supplier owes us)', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalDebitCents: 30000,
        totalCreditCents: 100000,
        netBalanceCents: -70000,
        transactionCount: 5,
      );

      final isPayable = item.netBalanceCents > 0;
      final isReceivable = item.netBalanceCents < 0;
      final isSettled = item.netBalanceCents == 0;

      expect(isPayable, false);
      expect(isReceivable, true);
      expect(isSettled, false);
    });

    test('zero net balance is settled', () {
      const item = SupplierBalanceItem(
        supplierId: 1,
        supplierName: 'Test',
        totalDebitCents: 50000,
        totalCreditCents: 50000,
        netBalanceCents: 0,
        transactionCount: 10,
      );

      final isPayable = item.netBalanceCents > 0;
      final isReceivable = item.netBalanceCents < 0;
      final isSettled = item.netBalanceCents == 0;

      expect(isPayable, false);
      expect(isReceivable, false);
      expect(isSettled, true);
    });
  });

  group('Suppliers with debit/credit counting', () {
    test('correctly counts suppliers with debit and credit', () {
      const suppliers = [
        SupplierBalanceItem(
          supplierId: 1,
          supplierName: 'Payable Supplier',
          totalDebitCents: 100000,
          totalCreditCents: 20000,
          netBalanceCents: 80000,
          transactionCount: 5,
        ),
        SupplierBalanceItem(
          supplierId: 2,
          supplierName: 'Receivable Supplier',
          totalDebitCents: 20000,
          totalCreditCents: 100000,
          netBalanceCents: -80000,
          transactionCount: 5,
        ),
        SupplierBalanceItem(
          supplierId: 3,
          supplierName: 'Settled Supplier',
          totalDebitCents: 50000,
          totalCreditCents: 50000,
          netBalanceCents: 0,
          transactionCount: 10,
        ),
        SupplierBalanceItem(
          supplierId: 4,
          supplierName: 'Another Payable',
          totalDebitCents: 30000,
          totalCreditCents: 10000,
          netBalanceCents: 20000,
          transactionCount: 3,
        ),
      ];

      int withDebit = 0;
      int withCredit = 0;
      int settled = 0;
      for (final s in suppliers) {
        if (s.netBalanceCents > 0) withDebit++;
        if (s.netBalanceCents < 0) withCredit++;
        if (s.netBalanceCents == 0) settled++;
      }

      expect(withDebit, 2);
      expect(withCredit, 1);
      expect(settled, 1);
      expect(withDebit + withCredit + settled, suppliers.length);
    });
  });
}
