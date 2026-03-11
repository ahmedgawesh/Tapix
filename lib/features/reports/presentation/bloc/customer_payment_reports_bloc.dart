import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class CustomerPaymentReportsEvent extends RealtimeEvent {
  const CustomerPaymentReportsEvent();
}

class CustomerPaymentReportsDateRangeChanged
    extends CustomerPaymentReportsEvent {
  final ReportDateRange dateRange;
  const CustomerPaymentReportsDateRangeChanged(this.dateRange);
}

class CustomerPaymentReportsMethodFilterChanged
    extends CustomerPaymentReportsEvent {
  final String? method;
  const CustomerPaymentReportsMethodFilterChanged(this.method);
}

// ==================== DATA MODELS ====================

class PaymentMethodSummary {
  final String method;
  final int amountCents;
  final int transactionCount;
  final double percentage;

  const PaymentMethodSummary({
    required this.method,
    required this.amountCents,
    required this.transactionCount,
    required this.percentage,
  });
}

class CustomerPaymentDetail {
  final int transactionId;
  final int customerId;
  final String customerName;
  final String transactionType;
  final int amountCents;
  final DateTime transactionDate;
  final String? description;
  final String? referenceType;
  final int? referenceId;

  const CustomerPaymentDetail({
    required this.transactionId,
    required this.customerId,
    required this.customerName,
    required this.transactionType,
    required this.amountCents,
    required this.transactionDate,
    this.description,
    this.referenceType,
    this.referenceId,
  });
}

class CustomerPaymentReportsData {
  final List<PaymentMethodSummary> methodSummaries;
  final List<CustomerPaymentDetail> details;
  final int totalAmountCents;
  final int transactionCount;
  final int uniqueCustomerCount;
  final ReportDateRange dateRange;
  final String? methodFilter;

  const CustomerPaymentReportsData({
    this.methodSummaries = const [],
    this.details = const [],
    this.totalAmountCents = 0,
    this.transactionCount = 0,
    this.uniqueCustomerCount = 0,
    required this.dateRange,
    this.methodFilter,
  });

  CustomerPaymentReportsData copyWith({
    List<PaymentMethodSummary>? methodSummaries,
    List<CustomerPaymentDetail>? details,
    int? totalAmountCents,
    int? transactionCount,
    int? uniqueCustomerCount,
    ReportDateRange? dateRange,
    String? methodFilter,
    bool clearMethodFilter = false,
  }) {
    return CustomerPaymentReportsData(
      methodSummaries: methodSummaries ?? this.methodSummaries,
      details: details ?? this.details,
      totalAmountCents: totalAmountCents ?? this.totalAmountCents,
      transactionCount: transactionCount ?? this.transactionCount,
      uniqueCustomerCount: uniqueCustomerCount ?? this.uniqueCustomerCount,
      dateRange: dateRange ?? this.dateRange,
      methodFilter: clearMethodFilter ? null : (methodFilter ?? this.methodFilter),
    );
  }
}

// ==================== BLOC ====================

class CustomerPaymentReportsBloc extends RealtimeBloc<
    CustomerPaymentReportsData, CustomerPaymentReportsEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  String? _methodFilter;

  CustomerPaymentReportsBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<CustomerPaymentReportsData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<CustomerPaymentReportsDateRangeChanged>(_onDateRangeChanged);
    on<CustomerPaymentReportsMethodFilterChanged>(_onMethodFilterChanged);
  }

  Stream<CustomerPaymentReportsData> _buildCombinedStream() {
    // Watch customer_transactions for real-time changes.
    // Note: This watches ALL transactions (not date-filtered) because Drift
    // table-level watches don't support WHERE clauses. The asyncMap re-queries
    // with the current date range, so data is always correct. For large datasets,
    // consider debouncing or pagination if performance becomes an issue.
    return _db.select(_db.customerTransactions).watch().asyncMap((_) async {
      final summaries = await _loadMethodSummaries();
      final details = await _loadPaymentDetails();

      int totalAmount = 0;
      int totalCount = 0;
      for (final s in summaries) {
        totalAmount += s.amountCents;
        totalCount += s.transactionCount;
      }

      final uniqueCustomers = <int>{};
      for (final d in details) {
        uniqueCustomers.add(d.customerId);
      }

      return CustomerPaymentReportsData(
        methodSummaries: summaries,
        details: details,
        totalAmountCents: totalAmount,
        transactionCount: totalCount,
        uniqueCustomerCount: uniqueCustomers.length,
        dateRange: _dateRange,
        methodFilter: _methodFilter,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    CustomerPaymentReportsDateRangeChanged event,
    Emitter<RealtimeState<CustomerPaymentReportsData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onMethodFilterChanged(
    CustomerPaymentReportsMethodFilterChanged event,
    Emitter<RealtimeState<CustomerPaymentReportsData>> emit,
  ) {
    _methodFilter = event.method;
    refresh();
  }

  Future<List<PaymentMethodSummary>> _loadMethodSummaries() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    // Query payment transactions grouped by description (which contains payment method info)
    // transaction_type for payments is typically 'payment', 'receipt', or 'settlement'
    final rows = await _db.customSelect(
      '''
      SELECT 
        COALESCE(ct.reference_type, ct.transaction_type) AS payment_method,
        COALESCE(SUM(ABS(ct.amount_cents)), 0) AS total_amount_cents,
        COUNT(*) AS transaction_count
      FROM customer_transactions ct
      WHERE ct.transaction_type IN ('payment', 'receipt', 'settlement')
        AND ct.transaction_date >= ?
        AND ct.transaction_date <= ?
      GROUP BY payment_method
      ORDER BY total_amount_cents DESC
      ''',
      variables: [
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.customerTransactions},
    ).get();

    // Calculate grand total for percentage
    int grandTotal = 0;
    for (final row in rows) {
      grandTotal += row.read<int>('total_amount_cents');
    }

    return rows.map((row) {
      final amount = row.read<int>('total_amount_cents');
      return PaymentMethodSummary(
        method: row.read<String>('payment_method'),
        amountCents: amount,
        transactionCount: row.read<int>('transaction_count'),
        percentage: grandTotal > 0 ? (amount / grandTotal) * 100 : 0,
      );
    }).toList();
  }

  Future<List<CustomerPaymentDetail>> _loadPaymentDetails() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    String whereClause =
        'ct.transaction_type IN (\'payment\', \'receipt\', \'settlement\')'
        ' AND ct.transaction_date >= ?'
        ' AND ct.transaction_date <= ?';

    final variables = <Variable>[
      Variable.withString(startIso),
      Variable.withString(endIso),
    ];

    if (_methodFilter != null) {
      whereClause +=
          ' AND COALESCE(ct.reference_type, ct.transaction_type) = ?';
      variables.add(Variable.withString(_methodFilter!));
    }

    final rows = await _db.customSelect(
      '''
      SELECT 
        ct.id AS transaction_id,
        ct.customer_id AS customer_id,
        c.name AS customer_name,
        ct.transaction_type AS transaction_type,
        ct.amount_cents AS amount_cents,
        ct.transaction_date AS transaction_date,
        ct.description AS description,
        ct.reference_type AS reference_type,
        ct.reference_id AS reference_id
      FROM customer_transactions ct
      INNER JOIN customers c ON c.id = ct.customer_id
      WHERE $whereClause
      ORDER BY ct.transaction_date DESC, ct.id DESC
      ''',
      variables: variables,
      readsFrom: {_db.customerTransactions, _db.customers},
    ).get();

    return rows.map((row) {
      return CustomerPaymentDetail(
        transactionId: row.read<int>('transaction_id'),
        customerId: row.read<int>('customer_id'),
        customerName: row.read<String>('customer_name'),
        transactionType: row.read<String>('transaction_type'),
        amountCents: row.read<int>('amount_cents'),
        transactionDate:
            DateTime.parse(row.read<String>('transaction_date')),
        description: row.readNullable<String>('description'),
        referenceType: row.readNullable<String>('reference_type'),
        referenceId: row.readNullable<int>('reference_id'),
      );
    }).toList();
  }
}
