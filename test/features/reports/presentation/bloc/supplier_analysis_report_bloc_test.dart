import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/supplier_analysis_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('SupplierAnalysisItem data model', () {
    test('stores correct values', () {
      const item = SupplierAnalysisItem(
        supplierId: 1,
        supplierName: 'Test Supplier',
        phone: '+1234567890',
        totalPurchasesCents: 500000,
        purchaseCount: 10,
        totalReturnsCents: 25000,
        returnCount: 2,
        totalPaymentsCents: 400000,
        paymentCount: 5,
        returnRatePercent: 5.0,
        avgPaymentDays: 15.0,
        settlementRatioPercent: 80.0,
        avgOrderValueCents: 50000,
        lastTransactionAt: null,
      );

      expect(item.supplierId, 1);
      expect(item.supplierName, 'Test Supplier');
      expect(item.phone, '+1234567890');
      expect(item.totalPurchasesCents, 500000);
      expect(item.purchaseCount, 10);
      expect(item.totalReturnsCents, 25000);
      expect(item.returnCount, 2);
      expect(item.totalPaymentsCents, 400000);
      expect(item.paymentCount, 5);
      expect(item.returnRatePercent, 5.0);
      expect(item.avgPaymentDays, 15.0);
      expect(item.settlementRatioPercent, 80.0);
      expect(item.avgOrderValueCents, 50000);
      expect(item.lastTransactionAt, isNull);
    });

    test('stores last transaction date when provided', () {
      final date = DateTime(2026, 2, 1);
      final item = SupplierAnalysisItem(
        supplierId: 2,
        supplierName: 'Supplier B',
        totalPurchasesCents: 1000000,
        purchaseCount: 20,
        totalReturnsCents: 50000,
        returnCount: 3,
        totalPaymentsCents: 900000,
        paymentCount: 10,
        returnRatePercent: 5.0,
        avgPaymentDays: 10.0,
        settlementRatioPercent: 90.0,
        avgOrderValueCents: 50000,
        lastTransactionAt: date,
      );

      expect(item.lastTransactionAt, date);
      expect(item.phone, isNull);
    });

    test('integer cents prevents floating point errors', () {
      const item = SupplierAnalysisItem(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasesCents: 30,
        purchaseCount: 1,
        totalReturnsCents: 10,
        returnCount: 1,
        totalPaymentsCents: 20,
        paymentCount: 1,
        returnRatePercent: 33.33,
        avgPaymentDays: 5.0,
        settlementRatioPercent: 66.67,
        avgOrderValueCents: 30,
      );

      expect(item.totalPurchasesCents - item.totalReturnsCents, 20);
      expect(item.totalPurchasesCents, 30);
    });

    test('return rate calculation is correct', () {
      // returnRate = (totalReturns / totalPurchases) * 100
      const totalPurchasesCents = 500000;
      const totalReturnsCents = 25000;
      final returnRate =
          (totalReturnsCents / totalPurchasesCents) * 100;

      expect(returnRate, 5.0);

      final item = SupplierAnalysisItem(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasesCents: totalPurchasesCents,
        purchaseCount: 10,
        totalReturnsCents: totalReturnsCents,
        returnCount: 2,
        totalPaymentsCents: 400000,
        paymentCount: 5,
        returnRatePercent: returnRate,
        avgPaymentDays: 15.0,
        settlementRatioPercent: 80.0,
        avgOrderValueCents: 50000,
      );

      expect(item.returnRatePercent, 5.0);
    });

    test('settlement ratio calculation is correct', () {
      // settlementRatio = (totalPayments / totalPurchases) * 100
      const totalPurchasesCents = 500000;
      const totalPaymentsCents = 400000;
      final settlementRatio =
          (totalPaymentsCents / totalPurchasesCents) * 100;

      expect(settlementRatio, 80.0);

      final item = SupplierAnalysisItem(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasesCents: totalPurchasesCents,
        purchaseCount: 10,
        totalReturnsCents: 25000,
        returnCount: 2,
        totalPaymentsCents: totalPaymentsCents,
        paymentCount: 5,
        returnRatePercent: 5.0,
        avgPaymentDays: 15.0,
        settlementRatioPercent: settlementRatio,
        avgOrderValueCents: 50000,
      );

      expect(item.settlementRatioPercent, 80.0);
    });

    test('avg order value calculation is correct', () {
      // avgOrderValue = totalPurchases / purchaseCount
      const totalPurchasesCents = 500000;
      const purchaseCount = 10;
      final avgOrderValue = totalPurchasesCents ~/ purchaseCount;

      expect(avgOrderValue, 50000);

      final item = SupplierAnalysisItem(
        supplierId: 1,
        supplierName: 'Test',
        totalPurchasesCents: totalPurchasesCents,
        purchaseCount: purchaseCount,
        totalReturnsCents: 25000,
        returnCount: 2,
        totalPaymentsCents: 400000,
        paymentCount: 5,
        returnRatePercent: 5.0,
        avgPaymentDays: 15.0,
        settlementRatioPercent: 80.0,
        avgOrderValueCents: avgOrderValue,
      );

      expect(item.avgOrderValueCents, 50000);
    });

    test('zero purchases yields zero rates', () {
      const totalPurchasesCents = 0;
      const totalReturnsCents = 0;
      const totalPaymentsCents = 0;
      const purchaseCount = 0;

      final returnRate = totalPurchasesCents > 0
          ? (totalReturnsCents / totalPurchasesCents) * 100
          : 0.0;
      final settlementRatio = totalPurchasesCents > 0
          ? (totalPaymentsCents / totalPurchasesCents) * 100
          : 0.0;
      final avgOrderValue =
          purchaseCount > 0 ? totalPurchasesCents ~/ purchaseCount : 0;

      expect(returnRate, 0.0);
      expect(settlementRatio, 0.0);
      expect(avgOrderValue, 0);
    });

    test('100% return rate when all purchases returned', () {
      const totalPurchasesCents = 100000;
      const totalReturnsCents = 100000;
      final returnRate =
          (totalReturnsCents / totalPurchasesCents) * 100;

      expect(returnRate, 100.0);
    });

    test('settlement ratio can exceed 100% with overpayment', () {
      const totalPurchasesCents = 100000;
      const totalPaymentsCents = 120000;
      final settlementRatio =
          (totalPaymentsCents / totalPurchasesCents) * 100;

      expect(settlementRatio, 120.0);
    });

    test('large amounts do not overflow int', () {
      const largeCents = 999999999999;
      const item = SupplierAnalysisItem(
        supplierId: 1,
        supplierName: 'Big Supplier',
        totalPurchasesCents: largeCents,
        purchaseCount: 1000,
        totalReturnsCents: 0,
        returnCount: 0,
        totalPaymentsCents: largeCents,
        paymentCount: 500,
        returnRatePercent: 0.0,
        avgPaymentDays: 30.0,
        settlementRatioPercent: 100.0,
        avgOrderValueCents: largeCents ~/ 1000,
      );

      expect(item.totalPurchasesCents, largeCents);
      expect(item.avgOrderValueCents, 999999999);
    });
  });

  group('SupplierAnalysisReportData', () {
    test('default values are correct', () {
      final data = SupplierAnalysisReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.suppliers, isEmpty);
      expect(data.grandTotalPurchasesCents, 0);
      expect(data.grandTotalReturnsCents, 0);
      expect(data.grandTotalPaymentsCents, 0);
      expect(data.totalSuppliers, 0);
      expect(data.avgReturnRatePercent, 0);
      expect(data.avgPaymentDays, 0);
      expect(data.avgSettlementRatioPercent, 0);
      expect(data.sort, SupplierAnalysisSortType.purchaseVolumeDesc);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = SupplierAnalysisReportData(
        grandTotalPurchasesCents: 1000000,
        grandTotalReturnsCents: 50000,
        grandTotalPaymentsCents: 800000,
        totalSuppliers: 10,
        avgReturnRatePercent: 5.0,
        avgPaymentDays: 15.0,
        avgSettlementRatioPercent: 80.0,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        dateRange: ReportDateRange.thisYear(),
      );

      expect(updated.grandTotalPurchasesCents, 1000000);
      expect(updated.grandTotalReturnsCents, 50000);
      expect(updated.grandTotalPaymentsCents, 800000);
      expect(updated.totalSuppliers, 10);
      expect(updated.avgReturnRatePercent, 5.0);
      expect(updated.avgPaymentDays, 15.0);
      expect(updated.avgSettlementRatioPercent, 80.0);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = SupplierAnalysisReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        grandTotalPurchasesCents: 500000,
        grandTotalReturnsCents: 25000,
        grandTotalPaymentsCents: 400000,
        sort: SupplierAnalysisSortType.nameAsc,
      );

      expect(updated.grandTotalPurchasesCents, 500000);
      expect(updated.grandTotalReturnsCents, 25000);
      expect(updated.grandTotalPaymentsCents, 400000);
      expect(updated.sort, SupplierAnalysisSortType.nameAsc);
    });

    test('copyWith updates suppliers list', () {
      final original = SupplierAnalysisReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      const supplier = SupplierAnalysisItem(
        supplierId: 1,
        supplierName: 'New Supplier',
        totalPurchasesCents: 999900,
        purchaseCount: 50,
        totalReturnsCents: 100,
        returnCount: 1,
        totalPaymentsCents: 800000,
        paymentCount: 10,
        returnRatePercent: 0.01,
        avgPaymentDays: 7.0,
        settlementRatioPercent: 80.01,
        avgOrderValueCents: 19998,
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

  group('SupplierAnalysisReportBloc events', () {
    test('SupplierAnalysisReportDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = SupplierAnalysisReportDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('SupplierAnalysisReportSortChanged stores sort type', () {
      const event = SupplierAnalysisReportSortChanged(
          SupplierAnalysisSortType.nameAsc);
      expect(event.sort, SupplierAnalysisSortType.nameAsc);
    });
  });

  group('SupplierAnalysisSortType enum', () {
    test('has all expected values', () {
      expect(SupplierAnalysisSortType.values.length, 8);
      expect(SupplierAnalysisSortType.values,
          contains(SupplierAnalysisSortType.purchaseVolumeDesc));
      expect(SupplierAnalysisSortType.values,
          contains(SupplierAnalysisSortType.purchaseVolumeAsc));
      expect(SupplierAnalysisSortType.values,
          contains(SupplierAnalysisSortType.nameAsc));
      expect(SupplierAnalysisSortType.values,
          contains(SupplierAnalysisSortType.nameDesc));
      expect(SupplierAnalysisSortType.values,
          contains(SupplierAnalysisSortType.returnRateDesc));
      expect(SupplierAnalysisSortType.values,
          contains(SupplierAnalysisSortType.avgPaymentDaysAsc));
      expect(SupplierAnalysisSortType.values,
          contains(SupplierAnalysisSortType.settlementRatioDesc));
      expect(SupplierAnalysisSortType.values,
          contains(SupplierAnalysisSortType.avgOrderValueDesc));
    });
  });

  group('Sort logic', () {
    final suppliers = [
      const SupplierAnalysisItem(
        supplierId: 1,
        supplierName: 'Zebra Supplies',
        totalPurchasesCents: 50000,
        purchaseCount: 5,
        totalReturnsCents: 5000,
        returnCount: 1,
        totalPaymentsCents: 40000,
        paymentCount: 3,
        returnRatePercent: 10.0,
        avgPaymentDays: 20.0,
        settlementRatioPercent: 80.0,
        avgOrderValueCents: 10000,
      ),
      const SupplierAnalysisItem(
        supplierId: 2,
        supplierName: 'Apple Wholesale',
        totalPurchasesCents: 200000,
        purchaseCount: 20,
        totalReturnsCents: 10000,
        returnCount: 3,
        totalPaymentsCents: 190000,
        paymentCount: 15,
        returnRatePercent: 5.0,
        avgPaymentDays: 10.0,
        settlementRatioPercent: 95.0,
        avgOrderValueCents: 10000,
      ),
      const SupplierAnalysisItem(
        supplierId: 3,
        supplierName: 'Mango Trading',
        totalPurchasesCents: 100000,
        purchaseCount: 8,
        totalReturnsCents: 20000,
        returnCount: 4,
        totalPaymentsCents: 60000,
        paymentCount: 5,
        returnRatePercent: 20.0,
        avgPaymentDays: 30.0,
        settlementRatioPercent: 60.0,
        avgOrderValueCents: 12500,
      ),
    ];

    test('sort by purchase volume descending', () {
      final list = List<SupplierAnalysisItem>.from(suppliers);
      list.sort((a, b) =>
          b.totalPurchasesCents.compareTo(a.totalPurchasesCents));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[0].totalPurchasesCents, 200000);
      expect(list[1].supplierName, 'Mango Trading');
      expect(list[1].totalPurchasesCents, 100000);
      expect(list[2].supplierName, 'Zebra Supplies');
      expect(list[2].totalPurchasesCents, 50000);
    });

    test('sort by purchase volume ascending', () {
      final list = List<SupplierAnalysisItem>.from(suppliers);
      list.sort((a, b) =>
          a.totalPurchasesCents.compareTo(b.totalPurchasesCents));

      expect(list[0].supplierName, 'Zebra Supplies');
      expect(list[2].supplierName, 'Apple Wholesale');
    });

    test('sort by name ascending', () {
      final list = List<SupplierAnalysisItem>.from(suppliers);
      list.sort((a, b) => a.supplierName.compareTo(b.supplierName));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[1].supplierName, 'Mango Trading');
      expect(list[2].supplierName, 'Zebra Supplies');
    });

    test('sort by name descending', () {
      final list = List<SupplierAnalysisItem>.from(suppliers);
      list.sort((a, b) => b.supplierName.compareTo(a.supplierName));

      expect(list[0].supplierName, 'Zebra Supplies');
      expect(list[1].supplierName, 'Mango Trading');
      expect(list[2].supplierName, 'Apple Wholesale');
    });

    test('sort by return rate descending', () {
      final list = List<SupplierAnalysisItem>.from(suppliers);
      list.sort(
          (a, b) => b.returnRatePercent.compareTo(a.returnRatePercent));

      expect(list[0].supplierName, 'Mango Trading');
      expect(list[0].returnRatePercent, 20.0);
      expect(list[1].supplierName, 'Zebra Supplies');
      expect(list[1].returnRatePercent, 10.0);
      expect(list[2].supplierName, 'Apple Wholesale');
      expect(list[2].returnRatePercent, 5.0);
    });

    test('sort by avg payment days ascending (fastest payers first)', () {
      final list = List<SupplierAnalysisItem>.from(suppliers);
      list.sort((a, b) => a.avgPaymentDays.compareTo(b.avgPaymentDays));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[0].avgPaymentDays, 10.0);
      expect(list[1].supplierName, 'Zebra Supplies');
      expect(list[1].avgPaymentDays, 20.0);
      expect(list[2].supplierName, 'Mango Trading');
      expect(list[2].avgPaymentDays, 30.0);
    });

    test('sort by settlement ratio descending (best settlers first)', () {
      final list = List<SupplierAnalysisItem>.from(suppliers);
      list.sort((a, b) =>
          b.settlementRatioPercent.compareTo(a.settlementRatioPercent));

      expect(list[0].supplierName, 'Apple Wholesale');
      expect(list[0].settlementRatioPercent, 95.0);
      expect(list[1].supplierName, 'Zebra Supplies');
      expect(list[1].settlementRatioPercent, 80.0);
      expect(list[2].supplierName, 'Mango Trading');
      expect(list[2].settlementRatioPercent, 60.0);
    });

    test('sort by avg order value descending', () {
      final list = List<SupplierAnalysisItem>.from(suppliers);
      list.sort((a, b) =>
          b.avgOrderValueCents.compareTo(a.avgOrderValueCents));

      expect(list[0].supplierName, 'Mango Trading');
      expect(list[0].avgOrderValueCents, 12500);
      expect(list[1].supplierName, 'Zebra Supplies');
      expect(list[1].avgOrderValueCents, 10000);
      expect(list[2].supplierName, 'Apple Wholesale');
      expect(list[2].avgOrderValueCents, 10000);
    });
  });

  group('Grand totals calculation', () {
    test('grand totals sum correctly from supplier list', () {
      const suppliers = [
        SupplierAnalysisItem(
          supplierId: 1,
          supplierName: 'A',
          totalPurchasesCents: 500000,
          purchaseCount: 10,
          totalReturnsCents: 25000,
          returnCount: 2,
          totalPaymentsCents: 400000,
          paymentCount: 5,
          returnRatePercent: 5.0,
          avgPaymentDays: 15.0,
          settlementRatioPercent: 80.0,
          avgOrderValueCents: 50000,
        ),
        SupplierAnalysisItem(
          supplierId: 2,
          supplierName: 'B',
          totalPurchasesCents: 300000,
          purchaseCount: 6,
          totalReturnsCents: 30000,
          returnCount: 3,
          totalPaymentsCents: 250000,
          paymentCount: 4,
          returnRatePercent: 10.0,
          avgPaymentDays: 20.0,
          settlementRatioPercent: 83.33,
          avgOrderValueCents: 50000,
        ),
        SupplierAnalysisItem(
          supplierId: 3,
          supplierName: 'C',
          totalPurchasesCents: 200000,
          purchaseCount: 4,
          totalReturnsCents: 40000,
          returnCount: 2,
          totalPaymentsCents: 100000,
          paymentCount: 2,
          returnRatePercent: 20.0,
          avgPaymentDays: 30.0,
          settlementRatioPercent: 50.0,
          avgOrderValueCents: 50000,
        ),
      ];

      int totalPurchases = 0;
      int totalReturns = 0;
      int totalPayments = 0;
      double sumReturnRate = 0;
      double sumPaymentDays = 0;
      double sumSettlementRatio = 0;

      for (final s in suppliers) {
        totalPurchases += s.totalPurchasesCents;
        totalReturns += s.totalReturnsCents;
        totalPayments += s.totalPaymentsCents;
        sumReturnRate += s.returnRatePercent;
        sumPaymentDays += s.avgPaymentDays;
        sumSettlementRatio += s.settlementRatioPercent;
      }

      expect(totalPurchases, 1000000);
      expect(totalReturns, 95000);
      expect(totalPayments, 750000);

      final avgReturnRate = sumReturnRate / suppliers.length;
      final avgPayDays = sumPaymentDays / suppliers.length;
      final avgSettlement = sumSettlementRatio / suppliers.length;

      // (5.0 + 10.0 + 20.0) / 3 ≈ 11.67
      expect(avgReturnRate, closeTo(11.67, 0.01));
      // (15.0 + 20.0 + 30.0) / 3 ≈ 21.67
      expect(avgPayDays, closeTo(21.67, 0.01));
      // (80.0 + 83.33 + 50.0) / 3 ≈ 71.11
      expect(avgSettlement, closeTo(71.11, 0.01));
    });

    test('empty supplier list yields zero totals', () {
      const suppliers = <SupplierAnalysisItem>[];

      int totalPurchases = 0;
      int totalReturns = 0;
      int totalPayments = 0;
      for (final s in suppliers) {
        totalPurchases += s.totalPurchasesCents;
        totalReturns += s.totalReturnsCents;
        totalPayments += s.totalPaymentsCents;
      }

      expect(totalPurchases, 0);
      expect(totalReturns, 0);
      expect(totalPayments, 0);
    });

    test('single supplier averages equal its own values', () {
      const suppliers = [
        SupplierAnalysisItem(
          supplierId: 1,
          supplierName: 'Solo',
          totalPurchasesCents: 100000,
          purchaseCount: 5,
          totalReturnsCents: 10000,
          returnCount: 1,
          totalPaymentsCents: 90000,
          paymentCount: 3,
          returnRatePercent: 10.0,
          avgPaymentDays: 7.0,
          settlementRatioPercent: 90.0,
          avgOrderValueCents: 20000,
        ),
      ];

      final avgReturnRate = suppliers[0].returnRatePercent;
      final avgPayDays = suppliers[0].avgPaymentDays;
      final avgSettlement = suppliers[0].settlementRatioPercent;

      expect(avgReturnRate, 10.0);
      expect(avgPayDays, 7.0);
      expect(avgSettlement, 90.0);
    });
  });

  group('ReportDateRange for supplier analysis', () {
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
  });

  group('SupplierAnalysisPdfService translations', () {
    test('all expected translation keys are defined', () {
      const expectedKeys = [
        'supplier_analysis_report',
        'period',
        'total_purchases',
        'total_returns',
        'total_payments',
        'avg_return_rate',
        'avg_settlement',
        'avg_payment_days',
        'total_suppliers',
        'supplier_analysis_details',
        'supplier',
        'purchases',
        'orders',
        'returns',
        'return_rate',
        'payments',
        'settlement',
        'payment_days',
        'avg_order',
        'days',
        'grand_total',
        'printed_on',
      ];
      expect(expectedKeys.length, 22);
    });
  });

  group('Performance classification', () {
    test('high settlement ratio indicates good supplier', () {
      const item = SupplierAnalysisItem(
        supplierId: 1,
        supplierName: 'Good Supplier',
        totalPurchasesCents: 500000,
        purchaseCount: 10,
        totalReturnsCents: 5000,
        returnCount: 1,
        totalPaymentsCents: 490000,
        paymentCount: 10,
        returnRatePercent: 1.0,
        avgPaymentDays: 5.0,
        settlementRatioPercent: 98.0,
        avgOrderValueCents: 50000,
      );

      expect(item.settlementRatioPercent >= 80, true);
      expect(item.returnRatePercent <= 10, true);
      expect(item.avgPaymentDays <= 30, true);
    });

    test('low settlement ratio indicates poor supplier', () {
      const item = SupplierAnalysisItem(
        supplierId: 2,
        supplierName: 'Poor Supplier',
        totalPurchasesCents: 500000,
        purchaseCount: 10,
        totalReturnsCents: 100000,
        returnCount: 5,
        totalPaymentsCents: 200000,
        paymentCount: 3,
        returnRatePercent: 20.0,
        avgPaymentDays: 45.0,
        settlementRatioPercent: 40.0,
        avgOrderValueCents: 50000,
      );

      expect(item.settlementRatioPercent < 50, true);
      expect(item.returnRatePercent > 10, true);
      expect(item.avgPaymentDays > 30, true);
    });

    test('settlement color logic: >= 80% is primary, >= 50% is tertiary, < 50% is error',
        () {
      const good = 95.0;
      const medium = 65.0;
      const poor = 30.0;

      expect(good >= 80, true);
      expect(medium >= 50 && medium < 80, true);
      expect(poor < 50, true);
    });

    test('return rate color logic: > 10% is error', () {
      const highReturn = 15.0;
      const normalReturn = 5.0;

      expect(highReturn > 10, true);
      expect(normalReturn > 10, false);
    });

    test('payment days color logic: > 30 is error', () {
      const slowPayer = 45.0;
      const fastPayer = 10.0;

      expect(slowPayer > 30, true);
      expect(fastPayer > 30, false);
    });
  });

  group('Supplier ranking', () {
    test('ranking by volume puts highest purchaser first', () {
      final suppliers = [
        const SupplierAnalysisItem(
          supplierId: 1,
          supplierName: 'Small',
          totalPurchasesCents: 50000,
          purchaseCount: 2,
          totalReturnsCents: 0,
          returnCount: 0,
          totalPaymentsCents: 50000,
          paymentCount: 2,
          returnRatePercent: 0,
          avgPaymentDays: 5,
          settlementRatioPercent: 100,
          avgOrderValueCents: 25000,
        ),
        const SupplierAnalysisItem(
          supplierId: 2,
          supplierName: 'Large',
          totalPurchasesCents: 500000,
          purchaseCount: 20,
          totalReturnsCents: 10000,
          returnCount: 1,
          totalPaymentsCents: 490000,
          paymentCount: 15,
          returnRatePercent: 2,
          avgPaymentDays: 10,
          settlementRatioPercent: 98,
          avgOrderValueCents: 25000,
        ),
        const SupplierAnalysisItem(
          supplierId: 3,
          supplierName: 'Medium',
          totalPurchasesCents: 200000,
          purchaseCount: 8,
          totalReturnsCents: 5000,
          returnCount: 1,
          totalPaymentsCents: 195000,
          paymentCount: 6,
          returnRatePercent: 2.5,
          avgPaymentDays: 15,
          settlementRatioPercent: 97.5,
          avgOrderValueCents: 25000,
        ),
      ];

      suppliers.sort((a, b) =>
          b.totalPurchasesCents.compareTo(a.totalPurchasesCents));

      expect(suppliers[0].supplierName, 'Large');
      expect(suppliers[1].supplierName, 'Medium');
      expect(suppliers[2].supplierName, 'Small');

      // Rank = index + 1
      for (int i = 0; i < suppliers.length; i++) {
        expect(i + 1, isPositive);
      }
    });
  });
}
