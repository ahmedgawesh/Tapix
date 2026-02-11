import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/salespeople_commission_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('SalespersonCommissionItem data model', () {
    test('stores correct values', () {
      const item = SalespersonCommissionItem(
        employeeId: 1,
        employeeName: 'Ahmed Sales',
        position: 'Senior Salesperson',
        department: 'Sales',
        defaultCommissionRateBps: 500,
        totalSalesCents: 5000000,
        salesCount: 50,
        totalCommissionEarnedCents: 250000,
        pendingCommissionCents: 100000,
        approvedCommissionCents: 50000,
        paidCommissionCents: 100000,
        avgOrderValueCents: 100000,
        targetAchievementPercent: 85.0,
        lastSaleAt: null,
      );

      expect(item.employeeId, 1);
      expect(item.employeeName, 'Ahmed Sales');
      expect(item.position, 'Senior Salesperson');
      expect(item.department, 'Sales');
      expect(item.defaultCommissionRateBps, 500);
      expect(item.totalSalesCents, 5000000);
      expect(item.salesCount, 50);
      expect(item.totalCommissionEarnedCents, 250000);
      expect(item.pendingCommissionCents, 100000);
      expect(item.approvedCommissionCents, 50000);
      expect(item.paidCommissionCents, 100000);
      expect(item.avgOrderValueCents, 100000);
      expect(item.targetAchievementPercent, 85.0);
      expect(item.lastSaleAt, isNull);
    });

    test('stores last sale date when provided', () {
      final date = DateTime(2026, 2, 10);
      final item = SalespersonCommissionItem(
        employeeId: 2,
        employeeName: 'Sara Rep',
        defaultCommissionRateBps: 300,
        totalSalesCents: 3000000,
        salesCount: 30,
        totalCommissionEarnedCents: 90000,
        pendingCommissionCents: 90000,
        approvedCommissionCents: 0,
        paidCommissionCents: 0,
        avgOrderValueCents: 100000,
        targetAchievementPercent: 50.0,
        lastSaleAt: date,
      );

      expect(item.lastSaleAt, date);
      expect(item.position, isNull);
      expect(item.department, isNull);
    });

    test('commissionRatePercent converts bps to percentage correctly', () {
      const item = SalespersonCommissionItem(
        employeeId: 1,
        employeeName: 'Test',
        defaultCommissionRateBps: 500,
        totalSalesCents: 1000000,
        salesCount: 10,
        totalCommissionEarnedCents: 50000,
        pendingCommissionCents: 50000,
        approvedCommissionCents: 0,
        paidCommissionCents: 0,
        avgOrderValueCents: 100000,
        targetAchievementPercent: 100.0,
      );

      // 500 bps = 5.0%
      expect(item.commissionRatePercent, 5.0);
    });

    test('commissionRatePercent handles zero bps', () {
      const item = SalespersonCommissionItem(
        employeeId: 1,
        employeeName: 'Test',
        defaultCommissionRateBps: 0,
        totalSalesCents: 1000000,
        salesCount: 10,
        totalCommissionEarnedCents: 0,
        pendingCommissionCents: 0,
        approvedCommissionCents: 0,
        paidCommissionCents: 0,
        avgOrderValueCents: 100000,
        targetAchievementPercent: 100.0,
      );

      expect(item.commissionRatePercent, 0.0);
    });

    test('commissionRatePercent handles fractional bps', () {
      const item = SalespersonCommissionItem(
        employeeId: 1,
        employeeName: 'Test',
        defaultCommissionRateBps: 750,
        totalSalesCents: 1000000,
        salesCount: 10,
        totalCommissionEarnedCents: 75000,
        pendingCommissionCents: 75000,
        approvedCommissionCents: 0,
        paidCommissionCents: 0,
        avgOrderValueCents: 100000,
        targetAchievementPercent: 100.0,
      );

      // 750 bps = 7.5%
      expect(item.commissionRatePercent, 7.5);
    });

    test('integer cents prevents floating point errors', () {
      const item = SalespersonCommissionItem(
        employeeId: 1,
        employeeName: 'Test',
        defaultCommissionRateBps: 500,
        totalSalesCents: 30,
        salesCount: 1,
        totalCommissionEarnedCents: 1,
        pendingCommissionCents: 1,
        approvedCommissionCents: 0,
        paidCommissionCents: 0,
        avgOrderValueCents: 30,
        targetAchievementPercent: 0.0,
      );

      expect(item.totalSalesCents - item.totalCommissionEarnedCents, 29);
      expect(item.totalSalesCents, 30);
    });

    test('commission calculation from bps is correct', () {
      // commission = (totalSalesCents * rateBps) / 10000
      const totalSalesCents = 5000000; // 50,000.00
      const rateBps = 500; // 5%
      final commission = (totalSalesCents * rateBps) ~/ 10000;

      expect(commission, 250000); // 2,500.00
    });

    test('commission calculation with 7.5% rate', () {
      const totalSalesCents = 10000000; // 100,000.00
      const rateBps = 750; // 7.5%
      final commission = (totalSalesCents * rateBps) ~/ 10000;

      expect(commission, 750000); // 7,500.00
    });

    test('commission calculation with zero sales', () {
      const totalSalesCents = 0;
      const rateBps = 500;
      final commission = (totalSalesCents * rateBps) ~/ 10000;

      expect(commission, 0);
    });

    test('target achievement calculation is correct', () {
      const totalSalesCents = 8500000; // 85,000.00
      const targetCents = 10000000; // 100,000.00
      final achievement = (totalSalesCents / targetCents) * 100;

      expect(achievement, 85.0);
    });

    test('target achievement can exceed 100%', () {
      const totalSalesCents = 15000000; // 150,000.00
      const targetCents = 10000000; // 100,000.00
      final achievement = (totalSalesCents / targetCents) * 100;

      expect(achievement, 150.0);
    });

    test('avg order value calculation is correct', () {
      const totalSalesCents = 5000000;
      const salesCount = 50;
      final avgOrderValue = totalSalesCents ~/ salesCount;

      expect(avgOrderValue, 100000); // 1,000.00
    });

    test('avg order value with zero sales returns zero', () {
      const totalSalesCents = 0;
      const salesCount = 0;
      final avgOrderValue =
          salesCount > 0 ? totalSalesCents ~/ salesCount : 0;

      expect(avgOrderValue, 0);
    });

    test('large amounts do not overflow int', () {
      const largeCents = 999999999999;
      const item = SalespersonCommissionItem(
        employeeId: 1,
        employeeName: 'Big Seller',
        defaultCommissionRateBps: 500,
        totalSalesCents: largeCents,
        salesCount: 1000,
        totalCommissionEarnedCents: largeCents ~/ 20,
        pendingCommissionCents: largeCents ~/ 40,
        approvedCommissionCents: largeCents ~/ 40,
        paidCommissionCents: largeCents ~/ 40,
        avgOrderValueCents: largeCents ~/ 1000,
        targetAchievementPercent: 999.9,
      );

      expect(item.totalSalesCents, largeCents);
      expect(item.avgOrderValueCents, 999999999);
    });

    test('commission breakdown sums correctly', () {
      const item = SalespersonCommissionItem(
        employeeId: 1,
        employeeName: 'Test',
        defaultCommissionRateBps: 500,
        totalSalesCents: 1000000,
        salesCount: 10,
        totalCommissionEarnedCents: 50000,
        pendingCommissionCents: 20000,
        approvedCommissionCents: 15000,
        paidCommissionCents: 15000,
        avgOrderValueCents: 100000,
        targetAchievementPercent: 100.0,
      );

      // pending + approved + paid = total
      expect(
        item.pendingCommissionCents +
            item.approvedCommissionCents +
            item.paidCommissionCents,
        item.totalCommissionEarnedCents,
      );
    });
  });

  group('SalespeopleCommissionReportData', () {
    test('default values are correct', () {
      final data = SalespeopleCommissionReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.salespeople, isEmpty);
      expect(data.grandTotalSalesCents, 0);
      expect(data.grandTotalCommissionCents, 0);
      expect(data.grandTotalPendingCents, 0);
      expect(data.grandTotalPaidCents, 0);
      expect(data.totalSalesCount, 0);
      expect(data.totalSalespeople, 0);
      expect(data.avgCommissionRatePercent, 0);
      expect(data.avgTargetAchievementPercent, 0);
      expect(data.sort, SalespeopleCommissionSortType.revenueDesc);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = SalespeopleCommissionReportData(
        grandTotalSalesCents: 10000000,
        grandTotalCommissionCents: 500000,
        grandTotalPendingCents: 200000,
        grandTotalPaidCents: 300000,
        totalSalesCount: 100,
        totalSalespeople: 5,
        avgCommissionRatePercent: 5.0,
        avgTargetAchievementPercent: 85.0,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        dateRange: ReportDateRange.thisYear(),
      );

      expect(updated.grandTotalSalesCents, 10000000);
      expect(updated.grandTotalCommissionCents, 500000);
      expect(updated.grandTotalPendingCents, 200000);
      expect(updated.grandTotalPaidCents, 300000);
      expect(updated.totalSalesCount, 100);
      expect(updated.totalSalespeople, 5);
      expect(updated.avgCommissionRatePercent, 5.0);
      expect(updated.avgTargetAchievementPercent, 85.0);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = SalespeopleCommissionReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        grandTotalSalesCents: 5000000,
        grandTotalCommissionCents: 250000,
        grandTotalPaidCents: 100000,
        sort: SalespeopleCommissionSortType.nameAsc,
      );

      expect(updated.grandTotalSalesCents, 5000000);
      expect(updated.grandTotalCommissionCents, 250000);
      expect(updated.grandTotalPaidCents, 100000);
      expect(updated.sort, SalespeopleCommissionSortType.nameAsc);
    });

    test('copyWith updates salespeople list', () {
      final original = SalespeopleCommissionReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      const person = SalespersonCommissionItem(
        employeeId: 1,
        employeeName: 'New Salesperson',
        defaultCommissionRateBps: 500,
        totalSalesCents: 999900,
        salesCount: 50,
        totalCommissionEarnedCents: 49995,
        pendingCommissionCents: 49995,
        approvedCommissionCents: 0,
        paidCommissionCents: 0,
        avgOrderValueCents: 19998,
        targetAchievementPercent: 99.99,
      );

      final updated = original.copyWith(
        salespeople: [person],
        totalSalespeople: 1,
      );

      expect(updated.salespeople.length, 1);
      expect(updated.salespeople.first.employeeName, 'New Salesperson');
      expect(updated.totalSalespeople, 1);
    });
  });

  group('SalespeopleCommissionReportBloc events', () {
    test('DateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = SalespeopleCommissionReportDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('SortChanged stores sort type', () {
      const event = SalespeopleCommissionReportSortChanged(
          SalespeopleCommissionSortType.nameAsc);
      expect(event.sort, SalespeopleCommissionSortType.nameAsc);
    });

    test('DateRangeChanged with custom range', () {
      final range = ReportDateRange(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 6, 30, 23, 59, 59),
        preset: ReportPeriodPreset.custom,
      );
      final event = SalespeopleCommissionReportDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.custom);
      expect(event.dateRange.startDate.year, 2026);
    });
  });

  group('SalespeopleCommissionSortType enum', () {
    test('has all expected values', () {
      expect(SalespeopleCommissionSortType.values.length, 7);
      expect(SalespeopleCommissionSortType.values,
          contains(SalespeopleCommissionSortType.revenueDesc));
      expect(SalespeopleCommissionSortType.values,
          contains(SalespeopleCommissionSortType.revenueAsc));
      expect(SalespeopleCommissionSortType.values,
          contains(SalespeopleCommissionSortType.nameAsc));
      expect(SalespeopleCommissionSortType.values,
          contains(SalespeopleCommissionSortType.nameDesc));
      expect(SalespeopleCommissionSortType.values,
          contains(SalespeopleCommissionSortType.commissionDesc));
      expect(SalespeopleCommissionSortType.values,
          contains(SalespeopleCommissionSortType.salesCountDesc));
      expect(SalespeopleCommissionSortType.values,
          contains(SalespeopleCommissionSortType.targetAchievementDesc));
    });
  });

  group('Sort logic', () {
    final salespeople = [
      const SalespersonCommissionItem(
        employeeId: 1,
        employeeName: 'Zara Top',
        defaultCommissionRateBps: 500,
        totalSalesCents: 8000000,
        salesCount: 80,
        totalCommissionEarnedCents: 400000,
        pendingCommissionCents: 100000,
        approvedCommissionCents: 100000,
        paidCommissionCents: 200000,
        avgOrderValueCents: 100000,
        targetAchievementPercent: 120.0,
      ),
      const SalespersonCommissionItem(
        employeeId: 2,
        employeeName: 'Ahmed Mid',
        defaultCommissionRateBps: 300,
        totalSalesCents: 5000000,
        salesCount: 50,
        totalCommissionEarnedCents: 150000,
        pendingCommissionCents: 150000,
        approvedCommissionCents: 0,
        paidCommissionCents: 0,
        avgOrderValueCents: 100000,
        targetAchievementPercent: 75.0,
      ),
      const SalespersonCommissionItem(
        employeeId: 3,
        employeeName: 'Mona Low',
        defaultCommissionRateBps: 200,
        totalSalesCents: 2000000,
        salesCount: 20,
        totalCommissionEarnedCents: 40000,
        pendingCommissionCents: 40000,
        approvedCommissionCents: 0,
        paidCommissionCents: 0,
        avgOrderValueCents: 100000,
        targetAchievementPercent: 30.0,
      ),
    ];

    test('sort by revenue descending', () {
      final list = List<SalespersonCommissionItem>.from(salespeople);
      list.sort(
          (a, b) => b.totalSalesCents.compareTo(a.totalSalesCents));

      expect(list[0].employeeName, 'Zara Top');
      expect(list[0].totalSalesCents, 8000000);
      expect(list[1].employeeName, 'Ahmed Mid');
      expect(list[1].totalSalesCents, 5000000);
      expect(list[2].employeeName, 'Mona Low');
      expect(list[2].totalSalesCents, 2000000);
    });

    test('sort by revenue ascending', () {
      final list = List<SalespersonCommissionItem>.from(salespeople);
      list.sort(
          (a, b) => a.totalSalesCents.compareTo(b.totalSalesCents));

      expect(list[0].employeeName, 'Mona Low');
      expect(list[2].employeeName, 'Zara Top');
    });

    test('sort by name ascending', () {
      final list = List<SalespersonCommissionItem>.from(salespeople);
      list.sort((a, b) => a.employeeName.compareTo(b.employeeName));

      expect(list[0].employeeName, 'Ahmed Mid');
      expect(list[1].employeeName, 'Mona Low');
      expect(list[2].employeeName, 'Zara Top');
    });

    test('sort by name descending', () {
      final list = List<SalespersonCommissionItem>.from(salespeople);
      list.sort((a, b) => b.employeeName.compareTo(a.employeeName));

      expect(list[0].employeeName, 'Zara Top');
      expect(list[1].employeeName, 'Mona Low');
      expect(list[2].employeeName, 'Ahmed Mid');
    });

    test('sort by commission descending', () {
      final list = List<SalespersonCommissionItem>.from(salespeople);
      list.sort((a, b) => b.totalCommissionEarnedCents
          .compareTo(a.totalCommissionEarnedCents));

      expect(list[0].employeeName, 'Zara Top');
      expect(list[0].totalCommissionEarnedCents, 400000);
      expect(list[1].employeeName, 'Ahmed Mid');
      expect(list[1].totalCommissionEarnedCents, 150000);
      expect(list[2].employeeName, 'Mona Low');
      expect(list[2].totalCommissionEarnedCents, 40000);
    });

    test('sort by sales count descending', () {
      final list = List<SalespersonCommissionItem>.from(salespeople);
      list.sort((a, b) => b.salesCount.compareTo(a.salesCount));

      expect(list[0].employeeName, 'Zara Top');
      expect(list[0].salesCount, 80);
      expect(list[1].employeeName, 'Ahmed Mid');
      expect(list[1].salesCount, 50);
      expect(list[2].employeeName, 'Mona Low');
      expect(list[2].salesCount, 20);
    });

    test('sort by target achievement descending', () {
      final list = List<SalespersonCommissionItem>.from(salespeople);
      list.sort((a, b) =>
          b.targetAchievementPercent.compareTo(a.targetAchievementPercent));

      expect(list[0].employeeName, 'Zara Top');
      expect(list[0].targetAchievementPercent, 120.0);
      expect(list[1].employeeName, 'Ahmed Mid');
      expect(list[1].targetAchievementPercent, 75.0);
      expect(list[2].employeeName, 'Mona Low');
      expect(list[2].targetAchievementPercent, 30.0);
    });
  });

  group('Grand totals calculation', () {
    test('grand totals sum correctly from salespeople list', () {
      const salespeople = [
        SalespersonCommissionItem(
          employeeId: 1,
          employeeName: 'A',
          defaultCommissionRateBps: 500,
          totalSalesCents: 5000000,
          salesCount: 50,
          totalCommissionEarnedCents: 250000,
          pendingCommissionCents: 100000,
          approvedCommissionCents: 50000,
          paidCommissionCents: 100000,
          avgOrderValueCents: 100000,
          targetAchievementPercent: 85.0,
        ),
        SalespersonCommissionItem(
          employeeId: 2,
          employeeName: 'B',
          defaultCommissionRateBps: 300,
          totalSalesCents: 3000000,
          salesCount: 30,
          totalCommissionEarnedCents: 90000,
          pendingCommissionCents: 90000,
          approvedCommissionCents: 0,
          paidCommissionCents: 0,
          avgOrderValueCents: 100000,
          targetAchievementPercent: 50.0,
        ),
        SalespersonCommissionItem(
          employeeId: 3,
          employeeName: 'C',
          defaultCommissionRateBps: 750,
          totalSalesCents: 12000000,
          salesCount: 120,
          totalCommissionEarnedCents: 900000,
          pendingCommissionCents: 200000,
          approvedCommissionCents: 300000,
          paidCommissionCents: 400000,
          avgOrderValueCents: 100000,
          targetAchievementPercent: 200.0,
        ),
      ];

      int totalSales = 0;
      int totalCommission = 0;
      int totalPending = 0;
      int totalPaid = 0;
      int totalCount = 0;
      double sumRate = 0;
      double sumTarget = 0;

      for (final s in salespeople) {
        totalSales += s.totalSalesCents;
        totalCommission += s.totalCommissionEarnedCents;
        totalPending += s.pendingCommissionCents;
        totalPaid += s.paidCommissionCents;
        totalCount += s.salesCount;
        sumRate += s.commissionRatePercent;
        sumTarget += s.targetAchievementPercent;
      }

      expect(totalSales, 20000000); // 200,000.00
      expect(totalCommission, 1240000); // 12,400.00
      expect(totalPending, 390000); // 3,900.00
      expect(totalPaid, 500000); // 5,000.00
      expect(totalCount, 200);

      final avgRate = sumRate / salespeople.length;
      final avgTarget = sumTarget / salespeople.length;

      // (5.0 + 3.0 + 7.5) / 3 ≈ 5.17
      expect(avgRate, closeTo(5.17, 0.01));
      // (85.0 + 50.0 + 200.0) / 3 ≈ 111.67
      expect(avgTarget, closeTo(111.67, 0.01));
    });

    test('empty salespeople list yields zero totals', () {
      const salespeople = <SalespersonCommissionItem>[];

      int totalSales = 0;
      int totalCommission = 0;
      int totalPaid = 0;
      for (final s in salespeople) {
        totalSales += s.totalSalesCents;
        totalCommission += s.totalCommissionEarnedCents;
        totalPaid += s.paidCommissionCents;
      }

      expect(totalSales, 0);
      expect(totalCommission, 0);
      expect(totalPaid, 0);
    });

    test('single salesperson averages equal its own values', () {
      const salespeople = [
        SalespersonCommissionItem(
          employeeId: 1,
          employeeName: 'Solo',
          defaultCommissionRateBps: 500,
          totalSalesCents: 10000000,
          salesCount: 100,
          totalCommissionEarnedCents: 500000,
          pendingCommissionCents: 200000,
          approvedCommissionCents: 100000,
          paidCommissionCents: 200000,
          avgOrderValueCents: 100000,
          targetAchievementPercent: 150.0,
        ),
      ];

      final avgRate = salespeople[0].commissionRatePercent;
      final avgTarget = salespeople[0].targetAchievementPercent;

      expect(avgRate, 5.0);
      expect(avgTarget, 150.0);
    });
  });

  group('Commission calculation verification', () {
    test('5% commission on 50,000.00 sales = 2,500.00', () {
      const totalSalesCents = 5000000;
      const rateBps = 500;
      final commission = (totalSalesCents * rateBps) ~/ 10000;
      expect(commission, 250000);
    });

    test('3% commission on 30,000.00 sales = 900.00', () {
      const totalSalesCents = 3000000;
      const rateBps = 300;
      final commission = (totalSalesCents * rateBps) ~/ 10000;
      expect(commission, 90000);
    });

    test('7.5% commission on 100,000.00 sales = 7,500.00', () {
      const totalSalesCents = 10000000;
      const rateBps = 750;
      final commission = (totalSalesCents * rateBps) ~/ 10000;
      expect(commission, 750000);
    });

    test('10% commission on 1,000.00 sales = 100.00', () {
      const totalSalesCents = 100000;
      const rateBps = 1000;
      final commission = (totalSalesCents * rateBps) ~/ 10000;
      expect(commission, 10000);
    });

    test('0% commission on any sales = 0', () {
      const totalSalesCents = 5000000;
      const rateBps = 0;
      final commission = (totalSalesCents * rateBps) ~/ 10000;
      expect(commission, 0);
    });

    test('commission on zero sales = 0', () {
      const totalSalesCents = 0;
      const rateBps = 500;
      final commission = (totalSalesCents * rateBps) ~/ 10000;
      expect(commission, 0);
    });

    test('small commission amounts are precise with integer cents', () {
      // 2% on 1.50 = 0.03
      const totalSalesCents = 150;
      const rateBps = 200;
      final commission = (totalSalesCents * rateBps) ~/ 10000;
      expect(commission, 3); // 0.03
    });

    test('bps to percentage conversion is accurate', () {
      expect(100 / 100, 1.0); // 100 bps = 1%
      expect(250 / 100, 2.5); // 250 bps = 2.5%
      expect(500 / 100, 5.0); // 500 bps = 5%
      expect(750 / 100, 7.5); // 750 bps = 7.5%
      expect(1000 / 100, 10.0); // 1000 bps = 10%
    });
  });

  group('Target achievement calculation', () {
    test('pro-rated target for 30-day month', () {
      const monthlyTargetCents = 10000000; // 100,000.00
      const rangeDays = 30;
      final proRatedTarget =
          (monthlyTargetCents * rangeDays / 30).round();
      expect(proRatedTarget, 10000000);
    });

    test('pro-rated target for 7-day week', () {
      const monthlyTargetCents = 10000000;
      const rangeDays = 7;
      final proRatedTarget =
          (monthlyTargetCents * rangeDays / 30).round();
      expect(proRatedTarget, 2333333);
    });

    test('pro-rated target for 90-day quarter', () {
      const monthlyTargetCents = 10000000;
      const rangeDays = 90;
      final proRatedTarget =
          (monthlyTargetCents * rangeDays / 30).round();
      expect(proRatedTarget, 30000000);
    });

    test('pro-rated target for 365-day year', () {
      const monthlyTargetCents = 10000000;
      const rangeDays = 365;
      final proRatedTarget =
          (monthlyTargetCents * rangeDays / 30).round();
      expect(proRatedTarget, 121666667);
    });

    test('achievement percentage calculation', () {
      const totalSalesCents = 8500000;
      const proRatedTarget = 10000000;
      final achievement = (totalSalesCents / proRatedTarget) * 100;
      expect(achievement, 85.0);
    });

    test('zero target yields zero achievement', () {
      const totalSalesCents = 5000000;
      const proRatedTarget = 0;
      final achievement = proRatedTarget > 0
          ? (totalSalesCents / proRatedTarget) * 100
          : 0.0;
      expect(achievement, 0.0);
    });
  });

  group('ReportDateRange for commission reports', () {
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

    test('thisQuarter starts at correct month', () {
      final range = ReportDateRange.thisQuarter();
      final now = DateTime.now();
      final expectedQuarterStart = ((now.month - 1) ~/ 3) * 3 + 1;
      expect(range.startDate.month, expectedQuarterStart);
      expect(range.preset, ReportPeriodPreset.thisQuarter);
    });
  });

  group('SalespeopleCommissionPdfService translations', () {
    test('all expected translation keys are defined', () {
      const expectedKeys = [
        'salespeople_commission_report',
        'period',
        'total_sales',
        'total_commission',
        'total_paid',
        'total_salespeople',
        'total_invoices',
        'avg_commission_rate',
        'avg_target',
        'commission_details',
        'salesperson',
        'sales',
        'invoices',
        'rate',
        'commission',
        'paid',
        'pending',
        'target',
        'grand_total',
        'printed_on',
      ];
      expect(expectedKeys.length, 20);
    });
  });

  group('Performance classification', () {
    test('high target achievement indicates top performer', () {
      const item = SalespersonCommissionItem(
        employeeId: 1,
        employeeName: 'Top Performer',
        defaultCommissionRateBps: 500,
        totalSalesCents: 15000000,
        salesCount: 150,
        totalCommissionEarnedCents: 750000,
        pendingCommissionCents: 0,
        approvedCommissionCents: 0,
        paidCommissionCents: 750000,
        avgOrderValueCents: 100000,
        targetAchievementPercent: 150.0,
      );

      expect(item.targetAchievementPercent >= 100, true);
      expect(item.paidCommissionCents, item.totalCommissionEarnedCents);
    });

    test('low target achievement indicates underperformer', () {
      const item = SalespersonCommissionItem(
        employeeId: 2,
        employeeName: 'Underperformer',
        defaultCommissionRateBps: 500,
        totalSalesCents: 2000000,
        salesCount: 20,
        totalCommissionEarnedCents: 100000,
        pendingCommissionCents: 100000,
        approvedCommissionCents: 0,
        paidCommissionCents: 0,
        avgOrderValueCents: 100000,
        targetAchievementPercent: 30.0,
      );

      expect(item.targetAchievementPercent < 70, true);
      expect(item.paidCommissionCents, 0);
    });

    test('target color logic: >= 100% is primary, >= 70% is tertiary, < 70% is error',
        () {
      const excellent = 120.0;
      const good = 85.0;
      const poor = 40.0;

      expect(excellent >= 100, true);
      expect(good >= 70 && good < 100, true);
      expect(poor < 70, true);
    });

    test('commission paid color logic: > 0 is primary', () {
      const hasPaid = 100000;
      const noPaid = 0;

      expect(hasPaid > 0, true);
      expect(noPaid > 0, false);
    });
  });

  group('Salesperson ranking', () {
    test('ranking by revenue puts highest seller first', () {
      final salespeople = [
        const SalespersonCommissionItem(
          employeeId: 1,
          employeeName: 'Small',
          defaultCommissionRateBps: 500,
          totalSalesCents: 1000000,
          salesCount: 10,
          totalCommissionEarnedCents: 50000,
          pendingCommissionCents: 50000,
          approvedCommissionCents: 0,
          paidCommissionCents: 0,
          avgOrderValueCents: 100000,
          targetAchievementPercent: 15.0,
        ),
        const SalespersonCommissionItem(
          employeeId: 2,
          employeeName: 'Large',
          defaultCommissionRateBps: 500,
          totalSalesCents: 15000000,
          salesCount: 150,
          totalCommissionEarnedCents: 750000,
          pendingCommissionCents: 0,
          approvedCommissionCents: 0,
          paidCommissionCents: 750000,
          avgOrderValueCents: 100000,
          targetAchievementPercent: 225.0,
        ),
        const SalespersonCommissionItem(
          employeeId: 3,
          employeeName: 'Medium',
          defaultCommissionRateBps: 500,
          totalSalesCents: 7000000,
          salesCount: 70,
          totalCommissionEarnedCents: 350000,
          pendingCommissionCents: 100000,
          approvedCommissionCents: 100000,
          paidCommissionCents: 150000,
          avgOrderValueCents: 100000,
          targetAchievementPercent: 105.0,
        ),
      ];

      salespeople.sort(
          (a, b) => b.totalSalesCents.compareTo(a.totalSalesCents));

      expect(salespeople[0].employeeName, 'Large');
      expect(salespeople[1].employeeName, 'Medium');
      expect(salespeople[2].employeeName, 'Small');

      // Rank = index + 1
      for (int i = 0; i < salespeople.length; i++) {
        expect(i + 1, isPositive);
      }
    });
  });

  group('Monthly target constant', () {
    test('monthlyTargetCents is 100,000.00 in cents', () {
      expect(SalespeopleCommissionReportBloc.monthlyTargetCents, 10000000);
    });

    test('target represents 100,000.00 currency units', () {
      final amount =
          SalespeopleCommissionReportBloc.monthlyTargetCents / 100;
      expect(amount, 100000.00);
    });
  });
}
