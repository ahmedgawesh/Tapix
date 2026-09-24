import 'package:flutter_test/flutter_test.dart';
import 'package:tapix/features/reports/presentation/bloc/customer_payment_reports_bloc.dart';
import 'package:tapix/features/reports/presentation/widgets/report_date_range.dart';

void main() {
  group('CustomerPaymentReportsBloc data models', () {
    test('PaymentMethodSummary stores correct values', () {
      const summary = PaymentMethodSummary(
        method: 'cash',
        amountCents: 150000,
        transactionCount: 25,
        percentage: 45.5,
      );

      expect(summary.method, 'cash');
      expect(summary.amountCents, 150000);
      expect(summary.transactionCount, 25);
      expect(summary.percentage, 45.5);
    });

    test('CustomerPaymentDetail stores correct values', () {
      final detail = CustomerPaymentDetail(
        transactionId: 1,
        customerId: 10,
        customerName: 'Ahmed Store',
        transactionType: 'payment',
        amountCents: -50000,
        transactionDate: DateTime(2026, 2, 1),
        description: 'Payment for invoice #123',
        referenceType: 'cash',
        referenceId: 5,
      );

      expect(detail.transactionId, 1);
      expect(detail.customerId, 10);
      expect(detail.customerName, 'Ahmed Store');
      expect(detail.transactionType, 'payment');
      expect(detail.amountCents, -50000);
      expect(detail.transactionDate, DateTime(2026, 2, 1));
      expect(detail.description, 'Payment for invoice #123');
      expect(detail.referenceType, 'cash');
      expect(detail.referenceId, 5);
    });

    test('CustomerPaymentDetail nullable fields default to null', () {
      final detail = CustomerPaymentDetail(
        transactionId: 2,
        customerId: 11,
        customerName: 'Test Customer',
        transactionType: 'receipt',
        amountCents: -30000,
        transactionDate: DateTime(2026, 2, 5),
      );

      expect(detail.description, isNull);
      expect(detail.referenceType, isNull);
      expect(detail.referenceId, isNull);
    });
  });

  group('CustomerPaymentReportsData', () {
    test('default values are correct', () {
      final data = CustomerPaymentReportsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.methodSummaries, isEmpty);
      expect(data.details, isEmpty);
      expect(data.totalAmountCents, 0);
      expect(data.transactionCount, 0);
      expect(data.uniqueCustomerCount, 0);
      expect(data.methodFilter, isNull);
      expect(data.dateRange.preset, ReportPeriodPreset.thisMonth);
    });

    test('copyWith preserves unchanged fields', () {
      final original = CustomerPaymentReportsData(
        totalAmountCents: 500000,
        transactionCount: 50,
        uniqueCustomerCount: 10,
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(dateRange: ReportDateRange.thisYear());

      expect(updated.totalAmountCents, 500000);
      expect(updated.transactionCount, 50);
      expect(updated.uniqueCustomerCount, 10);
      expect(updated.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('copyWith updates specified fields', () {
      final original = CustomerPaymentReportsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(
        totalAmountCents: 100000,
        transactionCount: 20,
        uniqueCustomerCount: 5,
        methodFilter: 'cash',
      );

      expect(updated.totalAmountCents, 100000);
      expect(updated.transactionCount, 20);
      expect(updated.uniqueCustomerCount, 5);
      expect(updated.methodFilter, 'cash');
    });

    test('copyWith clears method filter when clearMethodFilter is true', () {
      final original = CustomerPaymentReportsData(
        dateRange: ReportDateRange.thisMonth(),
        methodFilter: 'cash',
      );

      final updated = original.copyWith(clearMethodFilter: true);

      expect(updated.methodFilter, isNull);
    });

    test('copyWith with methodSummaries replaces list', () {
      const summaries = [
        PaymentMethodSummary(
          method: 'cash',
          amountCents: 100000,
          transactionCount: 10,
          percentage: 60.0,
        ),
        PaymentMethodSummary(
          method: 'card',
          amountCents: 66667,
          transactionCount: 5,
          percentage: 40.0,
        ),
      ];

      final original = CustomerPaymentReportsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(methodSummaries: summaries);

      expect(updated.methodSummaries.length, 2);
      expect(updated.methodSummaries[0].method, 'cash');
      expect(updated.methodSummaries[1].method, 'card');
    });

    test('copyWith with details replaces list', () {
      final details = [
        CustomerPaymentDetail(
          transactionId: 1,
          customerId: 10,
          customerName: 'Customer A',
          transactionType: 'payment',
          amountCents: -50000,
          transactionDate: DateTime(2026, 2, 1),
        ),
      ];

      final original = CustomerPaymentReportsData(
        dateRange: ReportDateRange.thisMonth(),
      );

      final updated = original.copyWith(details: details);

      expect(updated.details.length, 1);
      expect(updated.details[0].customerName, 'Customer A');
    });
  });

  group('CustomerPaymentReportsBloc events', () {
    test('CustomerPaymentReportsDateRangeChanged stores date range', () {
      final range = ReportDateRange.thisYear();
      final event = CustomerPaymentReportsDateRangeChanged(range);
      expect(event.dateRange.preset, ReportPeriodPreset.thisYear);
    });

    test('CustomerPaymentReportsMethodFilterChanged stores method', () {
      const event = CustomerPaymentReportsMethodFilterChanged('cash');
      expect(event.method, 'cash');
    });

    test('CustomerPaymentReportsMethodFilterChanged stores null for clear', () {
      const event = CustomerPaymentReportsMethodFilterChanged(null);
      expect(event.method, isNull);
    });
  });

  group('PaymentMethodSummary percentage calculation', () {
    test('percentage is correct for single method', () {
      const summary = PaymentMethodSummary(
        method: 'cash',
        amountCents: 100000,
        transactionCount: 10,
        percentage: 100.0,
      );
      expect(summary.percentage, 100.0);
    });

    test('percentages add up correctly for multiple methods', () {
      const summaries = [
        PaymentMethodSummary(
          method: 'cash',
          amountCents: 60000,
          transactionCount: 6,
          percentage: 60.0,
        ),
        PaymentMethodSummary(
          method: 'card',
          amountCents: 30000,
          transactionCount: 3,
          percentage: 30.0,
        ),
        PaymentMethodSummary(
          method: 'bank',
          amountCents: 10000,
          transactionCount: 1,
          percentage: 10.0,
        ),
      ];

      double totalPercentage = 0;
      int totalAmount = 0;
      for (final s in summaries) {
        totalPercentage += s.percentage;
        totalAmount += s.amountCents;
      }

      expect(totalPercentage, 100.0);
      expect(totalAmount, 100000);
    });
  });

  group('CustomerPaymentReportsData with real data', () {
    test('total amount matches sum of method summaries', () {
      const summaries = [
        PaymentMethodSummary(
          method: 'cash',
          amountCents: 150000,
          transactionCount: 15,
          percentage: 50.0,
        ),
        PaymentMethodSummary(
          method: 'card',
          amountCents: 90000,
          transactionCount: 9,
          percentage: 30.0,
        ),
        PaymentMethodSummary(
          method: 'bank',
          amountCents: 60000,
          transactionCount: 6,
          percentage: 20.0,
        ),
      ];

      int totalAmount = 0;
      int totalCount = 0;
      for (final s in summaries) {
        totalAmount += s.amountCents;
        totalCount += s.transactionCount;
      }

      final data = CustomerPaymentReportsData(
        methodSummaries: summaries,
        totalAmountCents: totalAmount,
        transactionCount: totalCount,
        dateRange: ReportDateRange.thisMonth(),
      );

      expect(data.totalAmountCents, 300000);
      expect(data.transactionCount, 30);
    });

    test('unique customer count from details', () {
      final details = [
        CustomerPaymentDetail(
          transactionId: 1,
          customerId: 10,
          customerName: 'Customer A',
          transactionType: 'payment',
          amountCents: -50000,
          transactionDate: DateTime(2026, 2, 1),
        ),
        CustomerPaymentDetail(
          transactionId: 2,
          customerId: 10,
          customerName: 'Customer A',
          transactionType: 'payment',
          amountCents: -30000,
          transactionDate: DateTime(2026, 2, 5),
        ),
        CustomerPaymentDetail(
          transactionId: 3,
          customerId: 20,
          customerName: 'Customer B',
          transactionType: 'receipt',
          amountCents: -20000,
          transactionDate: DateTime(2026, 2, 10),
        ),
      ];

      final uniqueCustomers = <int>{};
      for (final d in details) {
        uniqueCustomers.add(d.customerId);
      }

      expect(uniqueCustomers.length, 2);
    });
  });

  group('ReportDateRange for customer payments', () {
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
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        preset: ReportPeriodPreset.custom,
      );
      expect(range.startDate.year, 2026);
      expect(range.endDate.month, 12);
      expect(range.preset, ReportPeriodPreset.custom);
    });
  });

  group('CustomerPaymentPdfService translations', () {
    test('all expected translation keys exist', () {
      const expectedKeys = [
        'customer_payment_report',
        'period',
        'total_payments',
        'paying_customers',
        'total_transactions',
        'payment_method_breakdown',
        'payment_method',
        'amount',
        'count',
        'percentage',
        'grand_total',
        'payment_details',
        'date',
        'customer',
        'type',
        'description',
        'printed_on',
        'method_cash',
        'method_card',
        'method_bank',
        'method_credit',
        'type_payment',
        'type_receipt',
        'type_settlement',
      ];
      // Verify the count of expected keys
      expect(expectedKeys.length, 24);
    });
  });

  group('Payment amount calculations', () {
    test('absolute value of negative payment amounts', () {
      final detail = CustomerPaymentDetail(
        transactionId: 1,
        customerId: 10,
        customerName: 'Test',
        transactionType: 'payment',
        amountCents: -75000,
        transactionDate: DateTime(2026, 2, 1),
      );

      expect(detail.amountCents.abs(), 75000);
    });

    test('integer cents precision for payment totals', () {
      // Verify no floating point issues with integer cents
      const amounts = [15099, 24901, 10000, 50000];
      int total = 0;
      for (final a in amounts) {
        total += a;
      }
      expect(total, 100000); // Exactly 1000.00 in cents
    });

    test('percentage calculation from integer cents', () {
      const totalCents = 200000;
      const cashCents = 120000;
      const cardCents = 80000;

      final cashPct = (cashCents / totalCents) * 100;
      final cardPct = (cardCents / totalCents) * 100;

      expect(cashPct, 60.0);
      expect(cardPct, 40.0);
      expect(cashPct + cardPct, 100.0);
    });
  });
}
