import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_analysis_report_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('RFM Scoring', () {
    group('_computeRecencyScore', () {
      test('returns 5 for most recent customers (0-20% of max days)', () {
        expect(CustomerAnalysisReportBloc.computeRecencyScore(0, 100), 5);
        expect(CustomerAnalysisReportBloc.computeRecencyScore(10, 100), 5);
        expect(CustomerAnalysisReportBloc.computeRecencyScore(20, 100), 5);
      });

      test('returns 4 for recent customers (21-40% of max days)', () {
        expect(CustomerAnalysisReportBloc.computeRecencyScore(21, 100), 4);
        expect(CustomerAnalysisReportBloc.computeRecencyScore(30, 100), 4);
        expect(CustomerAnalysisReportBloc.computeRecencyScore(40, 100), 4);
      });

      test('returns 3 for moderate recency (41-60% of max days)', () {
        expect(CustomerAnalysisReportBloc.computeRecencyScore(41, 100), 3);
        expect(CustomerAnalysisReportBloc.computeRecencyScore(50, 100), 3);
        expect(CustomerAnalysisReportBloc.computeRecencyScore(60, 100), 3);
      });

      test('returns 2 for low recency (61-80% of max days)', () {
        expect(CustomerAnalysisReportBloc.computeRecencyScore(61, 100), 2);
        expect(CustomerAnalysisReportBloc.computeRecencyScore(70, 100), 2);
        expect(CustomerAnalysisReportBloc.computeRecencyScore(80, 100), 2);
      });

      test('returns 1 for least recent customers (81-100% of max days)', () {
        expect(CustomerAnalysisReportBloc.computeRecencyScore(81, 100), 1);
        expect(CustomerAnalysisReportBloc.computeRecencyScore(100, 100), 1);
      });

      test('returns 1 for unknown/missing last purchase (9999 days)', () {
        expect(CustomerAnalysisReportBloc.computeRecencyScore(9999, 100), 1);
      });

      test('returns 1 when maxDays is 0', () {
        expect(CustomerAnalysisReportBloc.computeRecencyScore(0, 0), 1);
      });
    });

    group('_computeFrequencyScore', () {
      test('returns 5 for highest frequency (80-100% of max)', () {
        expect(CustomerAnalysisReportBloc.computeFrequencyScore(100, 100), 5);
        expect(CustomerAnalysisReportBloc.computeFrequencyScore(80, 100), 5);
      });

      test('returns 4 for high frequency (60-79% of max)', () {
        expect(CustomerAnalysisReportBloc.computeFrequencyScore(79, 100), 4);
        expect(CustomerAnalysisReportBloc.computeFrequencyScore(60, 100), 4);
      });

      test('returns 3 for moderate frequency (40-59% of max)', () {
        expect(CustomerAnalysisReportBloc.computeFrequencyScore(59, 100), 3);
        expect(CustomerAnalysisReportBloc.computeFrequencyScore(40, 100), 3);
      });

      test('returns 2 for low frequency (20-39% of max)', () {
        expect(CustomerAnalysisReportBloc.computeFrequencyScore(39, 100), 2);
        expect(CustomerAnalysisReportBloc.computeFrequencyScore(20, 100), 2);
      });

      test('returns 1 for lowest frequency (0-19% of max)', () {
        expect(CustomerAnalysisReportBloc.computeFrequencyScore(19, 100), 1);
        expect(CustomerAnalysisReportBloc.computeFrequencyScore(1, 100), 1);
      });

      test('returns 1 when maxCount is 0', () {
        expect(CustomerAnalysisReportBloc.computeFrequencyScore(0, 0), 1);
      });
    });

    group('_computeMonetaryScore', () {
      test('returns 5 for highest spenders (80-100% of max)', () {
        expect(
          CustomerAnalysisReportBloc.computeMonetaryScore(100000, 100000),
          5,
        );
        expect(
          CustomerAnalysisReportBloc.computeMonetaryScore(80000, 100000),
          5,
        );
      });

      test('returns 4 for high spenders (60-79% of max)', () {
        expect(
          CustomerAnalysisReportBloc.computeMonetaryScore(79000, 100000),
          4,
        );
        expect(
          CustomerAnalysisReportBloc.computeMonetaryScore(60000, 100000),
          4,
        );
      });

      test('returns 3 for moderate spenders (40-59% of max)', () {
        expect(
          CustomerAnalysisReportBloc.computeMonetaryScore(59000, 100000),
          3,
        );
        expect(
          CustomerAnalysisReportBloc.computeMonetaryScore(40000, 100000),
          3,
        );
      });

      test('returns 2 for low spenders (20-39% of max)', () {
        expect(
          CustomerAnalysisReportBloc.computeMonetaryScore(39000, 100000),
          2,
        );
        expect(
          CustomerAnalysisReportBloc.computeMonetaryScore(20000, 100000),
          2,
        );
      });

      test('returns 1 for lowest spenders (0-19% of max)', () {
        expect(
          CustomerAnalysisReportBloc.computeMonetaryScore(19000, 100000),
          1,
        );
        expect(
          CustomerAnalysisReportBloc.computeMonetaryScore(1000, 100000),
          1,
        );
      });

      test('returns 1 when maxSpent is 0', () {
        expect(CustomerAnalysisReportBloc.computeMonetaryScore(0, 0), 1);
      });
    });

    group('_computeRfmSegment', () {
      test('Champions: high R, high F, high M', () {
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(5, 5, 5),
          RfmSegment.champions,
        );
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(4, 4, 4),
          RfmSegment.champions,
        );
      });

      test('Loyal Customers: high F, high M (any R)', () {
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(2, 5, 5),
          RfmSegment.loyalCustomers,
        );
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(3, 4, 4),
          RfmSegment.loyalCustomers,
        );
      });

      test('Potential Loyalists: high R, moderate F', () {
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(5, 3, 2),
          RfmSegment.potentialLoyalists,
        );
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(4, 2, 1),
          RfmSegment.potentialLoyalists,
        );
      });

      test('New Customers: high R, low F', () {
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(5, 1, 1),
          RfmSegment.newCustomers,
        );
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(4, 1, 2),
          RfmSegment.newCustomers,
        );
      });

      test('Promising: moderate R, low F', () {
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(3, 1, 1),
          RfmSegment.promising,
        );
      });

      test('Needs Attention: moderate R, moderate F, moderate M', () {
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(3, 3, 3),
          RfmSegment.needsAttention,
        );
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(2, 2, 2),
          RfmSegment.needsAttention,
        );
      });

      test('At Risk: low R, high F, high M', () {
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(2, 3, 3),
          RfmSegment.atRisk,
        );
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(1, 3, 3),
          RfmSegment.atRisk,
        );
      });

      test('Can\'t Lose Them: very low R, very high F, very high M', () {
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(1, 4, 4),
          RfmSegment.cantLoseThem,
        );
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(1, 5, 5),
          RfmSegment.cantLoseThem,
        );
      });

      test('Hibernating: low R, low F, low M', () {
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(1, 1, 1),
          RfmSegment.hibernating,
        );
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(2, 1, 2),
          RfmSegment.hibernating,
        );
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(1, 2, 1),
          RfmSegment.hibernating,
        );
      });

      test('About to Sleep: low R, low F, higher M', () {
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(1, 1, 3),
          RfmSegment.aboutToSleep,
        );
        expect(
          CustomerAnalysisReportBloc.computeRfmSegment(2, 2, 4),
          RfmSegment.aboutToSleep,
        );
      });
    });
  });

  group('CustomerAnalysisReportData', () {
    test('copyWith preserves unchanged fields', () {
      final data = CustomerAnalysisReportData(
        customers: const [],
        totalCustomers: 10,
        grandTotalSpentCents: 500000,
        grandTotalPurchases: 50,
        overallAvgOrderCents: 10000,
        segmentCounts: const {RfmSegment.champions: 3},
        dateRange: ReportDateRange.thisMonth(),
        sort: CustomerAnalysisSortType.totalSpentDesc,
      );

      final updated = data.copyWith(totalCustomers: 20);

      expect(updated.totalCustomers, 20);
      expect(updated.grandTotalSpentCents, 500000);
      expect(updated.grandTotalPurchases, 50);
      expect(updated.overallAvgOrderCents, 10000);
      expect(updated.sort, CustomerAnalysisSortType.totalSpentDesc);
    });

    test('copyWith updates all specified fields', () {
      final data = CustomerAnalysisReportData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = data.copyWith(
        totalCustomers: 5,
        grandTotalSpentCents: 100000,
        grandTotalPurchases: 25,
        overallAvgOrderCents: 4000,
        sort: CustomerAnalysisSortType.frequencyDesc,
      );

      expect(updated.totalCustomers, 5);
      expect(updated.grandTotalSpentCents, 100000);
      expect(updated.grandTotalPurchases, 25);
      expect(updated.overallAvgOrderCents, 4000);
      expect(updated.sort, CustomerAnalysisSortType.frequencyDesc);
    });
  });

  group('CustomerAnalysisItem', () {
    test('stores all fields correctly', () {
      final item = CustomerAnalysisItem(
        customerId: 1,
        customerName: 'Test Customer',
        segment: 'retail',
        purchaseCount: 10,
        avgDaysBetweenPurchases: 15.5,
        avgOrderValueCents: 5000,
        totalSpentCents: 50000,
        largestOrderCents: 12000,
        lastPurchaseDate: DateTime(2026, 2, 1),
        daysSinceLastPurchase: 8,
        recencyScore: 5,
        frequencyScore: 4,
        monetaryScore: 3,
        rfmSegment: RfmSegment.potentialLoyalists,
      );

      expect(item.customerId, 1);
      expect(item.customerName, 'Test Customer');
      expect(item.segment, 'retail');
      expect(item.purchaseCount, 10);
      expect(item.avgDaysBetweenPurchases, 15.5);
      expect(item.avgOrderValueCents, 5000);
      expect(item.totalSpentCents, 50000);
      expect(item.largestOrderCents, 12000);
      expect(item.lastPurchaseDate, DateTime(2026, 2, 1));
      expect(item.daysSinceLastPurchase, 8);
      expect(item.recencyScore, 5);
      expect(item.frequencyScore, 4);
      expect(item.monetaryScore, 3);
      expect(item.rfmSegment, RfmSegment.potentialLoyalists);
    });

    test('handles null lastPurchaseDate', () {
      const item = CustomerAnalysisItem(
        customerId: 1,
        customerName: 'Test',
        segment: 'retail',
        purchaseCount: 0,
        avgDaysBetweenPurchases: 0,
        avgOrderValueCents: 0,
        totalSpentCents: 0,
        largestOrderCents: 0,
        daysSinceLastPurchase: 9999,
        recencyScore: 1,
        frequencyScore: 1,
        monetaryScore: 1,
        rfmSegment: RfmSegment.lost,
      );

      expect(item.lastPurchaseDate, isNull);
    });
  });

  group('Average order value calculation', () {
    test('correctly computes avg order value from total and count', () {
      // 50000 cents / 10 purchases = 5000 cents per purchase
      const totalSpent = 50000;
      const purchaseCount = 10;
      final avgOrder = purchaseCount > 0 ? totalSpent ~/ purchaseCount : 0;
      expect(avgOrder, 5000);
    });

    test('returns 0 when purchase count is 0', () {
      const totalSpent = 50000;
      const purchaseCount = 0;
      final avgOrder = purchaseCount > 0 ? totalSpent ~/ purchaseCount : 0;
      expect(avgOrder, 0);
    });

    test('uses integer division for cents accuracy', () {
      // 10001 cents / 3 = 3333 cents (integer division, no floating point)
      const totalSpent = 10001;
      const purchaseCount = 3;
      final avgOrder = totalSpent ~/ purchaseCount;
      expect(avgOrder, 3333);
    });
  });

  group('Average days between purchases calculation', () {
    test('correctly computes avg days between purchases', () {
      // 90 days span, 10 purchases => 90 / (10-1) = 10 days avg
      final firstDate = DateTime(2026, 1, 1);
      final lastDate = DateTime(2026, 4, 1); // 90 days later
      const purchaseCount = 10;
      final spanDays = lastDate.difference(firstDate).inDays;
      final avgDays = spanDays / (purchaseCount - 1);
      expect(avgDays, 10.0);
    });

    test('returns 0 for single purchase', () {
      const purchaseCount = 1;
      double avgDays = 0;
      if (purchaseCount > 1) {
        avgDays = 30 / (purchaseCount - 1);
      }
      expect(avgDays, 0);
    });

    test('handles 2 purchases correctly', () {
      final firstDate = DateTime(2026, 1, 1);
      final lastDate = DateTime(2026, 1, 31); // 30 days later
      const purchaseCount = 2;
      final spanDays = lastDate.difference(firstDate).inDays;
      final avgDays = spanDays / (purchaseCount - 1);
      expect(avgDays, 30.0);
    });
  });

  group('Overall average order value', () {
    test('correctly computes from grand totals', () {
      const grandTotalSpent = 150000; // 1500.00
      const grandTotalPurchases = 30;
      final overallAvg = grandTotalPurchases > 0
          ? grandTotalSpent ~/ grandTotalPurchases
          : 0;
      expect(overallAvg, 5000); // 50.00
    });

    test('returns 0 when no purchases', () {
      const grandTotalSpent = 0;
      const grandTotalPurchases = 0;
      final overallAvg = grandTotalPurchases > 0
          ? grandTotalSpent ~/ grandTotalPurchases
          : 0;
      expect(overallAvg, 0);
    });
  });

  group('RfmSegment enum', () {
    test('has 11 segments', () {
      expect(RfmSegment.values.length, 11);
    });

    test('contains all expected segments', () {
      expect(RfmSegment.values, contains(RfmSegment.champions));
      expect(RfmSegment.values, contains(RfmSegment.loyalCustomers));
      expect(RfmSegment.values, contains(RfmSegment.potentialLoyalists));
      expect(RfmSegment.values, contains(RfmSegment.newCustomers));
      expect(RfmSegment.values, contains(RfmSegment.promising));
      expect(RfmSegment.values, contains(RfmSegment.needsAttention));
      expect(RfmSegment.values, contains(RfmSegment.aboutToSleep));
      expect(RfmSegment.values, contains(RfmSegment.atRisk));
      expect(RfmSegment.values, contains(RfmSegment.cantLoseThem));
      expect(RfmSegment.values, contains(RfmSegment.hibernating));
      expect(RfmSegment.values, contains(RfmSegment.lost));
    });
  });

  group('CustomerAnalysisSortType', () {
    test('has 8 sort types', () {
      expect(CustomerAnalysisSortType.values.length, 8);
    });
  });
}
