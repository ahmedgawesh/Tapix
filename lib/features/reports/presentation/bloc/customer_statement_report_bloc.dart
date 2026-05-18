import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/ledger/ledger_running_balance.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class CustomerStatementReportEvent extends RealtimeEvent {
  const CustomerStatementReportEvent();
}

class CustomerStatementReportDateRangeChanged
    extends CustomerStatementReportEvent {
  final ReportDateRange dateRange;
  const CustomerStatementReportDateRangeChanged(this.dateRange);
}

class CustomerStatementReportCustomerChanged
    extends CustomerStatementReportEvent {
  final int? customerId;
  const CustomerStatementReportCustomerChanged(this.customerId);
}

// ==================== DATA MODELS ====================

class StatementTransaction {
  final int id;
  final DateTime date;
  final String type;
  final String? description;
  final int amountCents;
  final int runningBalanceCents;
  final int? referenceId;
  final String? referenceType;

  const StatementTransaction({
    required this.id,
    required this.date,
    required this.type,
    this.description,
    required this.amountCents,
    required this.runningBalanceCents,
    this.referenceId,
    this.referenceType,
  });
}

class CustomerStatementData {
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String? customerAddress;
  final String? customerSegment;
  final int openingBalanceCents;
  final int closingBalanceCents;
  final int totalDebitsCents;
  final int totalCreditsCents;
  final List<StatementTransaction> transactions;
  final ReportDateRange dateRange;
  final List<CustomerOption> customers;

  const CustomerStatementData({
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.customerAddress,
    this.customerSegment,
    this.openingBalanceCents = 0,
    this.closingBalanceCents = 0,
    this.totalDebitsCents = 0,
    this.totalCreditsCents = 0,
    this.transactions = const [],
    required this.dateRange,
    this.customers = const [],
  });

  int get transactionCount => transactions.length;

  CustomerStatementData copyWith({
    int? customerId,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? customerAddress,
    String? customerSegment,
    int? openingBalanceCents,
    int? closingBalanceCents,
    int? totalDebitsCents,
    int? totalCreditsCents,
    List<StatementTransaction>? transactions,
    ReportDateRange? dateRange,
    List<CustomerOption>? customers,
  }) {
    return CustomerStatementData(
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerEmail: customerEmail ?? this.customerEmail,
      customerAddress: customerAddress ?? this.customerAddress,
      customerSegment: customerSegment ?? this.customerSegment,
      openingBalanceCents: openingBalanceCents ?? this.openingBalanceCents,
      closingBalanceCents: closingBalanceCents ?? this.closingBalanceCents,
      totalDebitsCents: totalDebitsCents ?? this.totalDebitsCents,
      totalCreditsCents: totalCreditsCents ?? this.totalCreditsCents,
      transactions: transactions ?? this.transactions,
      dateRange: dateRange ?? this.dateRange,
      customers: customers ?? this.customers,
    );
  }
}

class CustomerOption {
  final int id;
  final String name;
  final String? phone;
  final int balanceCents;

  const CustomerOption({
    required this.id,
    required this.name,
    this.phone,
    required this.balanceCents,
  });
}

// ==================== BLOC ====================

class CustomerStatementReportBloc extends RealtimeBloc<CustomerStatementData,
    CustomerStatementReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  int? _customerId;

  CustomerStatementReportBloc(this._db, {String defaultDateRange = 'month'})
      : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
        super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;
  int? get customerId => _customerId;

  @override
  Stream<CustomerStatementData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<CustomerStatementReportDateRangeChanged>(_onDateRangeChanged);
    on<CustomerStatementReportCustomerChanged>(_onCustomerChanged);
  }

  Stream<CustomerStatementData> _buildCombinedStream() {
    return _db
        .select(_db.customerTransactions)
        .watch()
        .asyncMap((_) async => _loadStatementData());
  }

  Future<void> _onDateRangeChanged(
    CustomerStatementReportDateRangeChanged event,
    Emitter<RealtimeState<CustomerStatementData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onCustomerChanged(
    CustomerStatementReportCustomerChanged event,
    Emitter<RealtimeState<CustomerStatementData>> emit,
  ) async {
    _customerId = event.customerId;
    refresh();
  }

  Future<CustomerStatementData> _loadStatementData() async {
    // Load customer list for the selector
    final customerRows = await _db.customSelect(
      '''
      SELECT c.id, c.name, c.phone, c.balance_cents
      FROM customers c
      WHERE c.is_active = 1
      ORDER BY c.name ASC
      ''',
      readsFrom: {_db.customers},
    ).get();

    final customers = customerRows
        .map((row) => CustomerOption(
              id: row.read<int>('id'),
              name: row.read<String>('name'),
              phone: row.readNullable<String>('phone'),
              balanceCents: row.read<int>('balance_cents'),
            ))
        .toList();

    if (_customerId == null) {
      return CustomerStatementData(
        dateRange: _dateRange,
        customers: customers,
      );
    }

    // Load customer info
    final customerInfoRows = await _db.customSelect(
      '''
      SELECT c.id, c.name, c.phone, c.email, c.address, c.segment
      FROM customers c
      WHERE c.id = ?
      ''',
      variables: [Variable.withInt(_customerId!)],
      readsFrom: {_db.customers},
    ).get();

    if (customerInfoRows.isEmpty) {
      return CustomerStatementData(
        dateRange: _dateRange,
        customers: customers,
      );
    }

    final cInfo = customerInfoRows.first;

    // Calculate opening balance:
    // The customers.balance_cents includes an initial balance set at creation
    // which is NOT recorded as a customer_transaction. So we must derive it:
    //   initial_balance = balance_cents - SUM(all transactions)
    //   opening_balance = initial_balance + SUM(transactions before start date)
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = DateTime(
      _dateRange.endDate.year,
      _dateRange.endDate.month,
      _dateRange.endDate.day,
      23,
      59,
      59,
    ).toIso8601String();

    final openingRows = await _db.customSelect(
      '''
      SELECT
        c.balance_cents AS current_balance,
        COALESCE(all_txn.total, 0) AS all_txn_total,
        COALESCE(before_txn.total, 0) AS before_txn_total
      FROM customers c
      LEFT JOIN (
        SELECT COALESCE(SUM(amount_cents), 0) AS total
        FROM customer_transactions WHERE customer_id = ?
      ) all_txn ON 1=1
      LEFT JOIN (
        SELECT COALESCE(SUM(amount_cents), 0) AS total
        FROM customer_transactions WHERE customer_id = ? AND transaction_date < ?
      ) before_txn ON 1=1
      WHERE c.id = ?
      ''',
      variables: [
        Variable.withInt(_customerId!),
        Variable.withInt(_customerId!),
        Variable.withString(startIso),
        Variable.withInt(_customerId!),
      ],
      readsFrom: {_db.customers, _db.customerTransactions},
    ).get();

    final int openingBalanceCents;
    if (openingRows.isNotEmpty) {
      final row = openingRows.first;
      final currentBalance = row.read<int>('current_balance');
      final allTxnTotal = row.read<int>('all_txn_total');
      final beforeTxnTotal = row.read<int>('before_txn_total');
      openingBalanceCents = (currentBalance - allTxnTotal) + beforeTxnTotal;
    } else {
      openingBalanceCents = 0;
    }

    // Load transactions within date range
    final txnRows = await _db.customSelect(
      '''
      SELECT id, transaction_type, amount_cents, description,
             reference_id, reference_type, transaction_date
      FROM customer_transactions
      WHERE customer_id = ? AND transaction_date >= ? AND transaction_date <= ?
      ORDER BY transaction_date ASC, id ASC
      ''',
      variables: [
        Variable.withInt(_customerId!),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.customerTransactions},
    ).get();

    // Phase 7 — running balance via SoT helper.
    final running = LedgerRunningBalance(openingBalanceCents);
    int totalDebits = 0;
    int totalCredits = 0;
    final transactions = <StatementTransaction>[];

    for (final row in txnRows) {
      final amountCents = row.read<int>('amount_cents');
      final runningBalance = running.apply(amountCents);

      if (amountCents > 0) {
        totalDebits += amountCents;
      } else {
        totalCredits += amountCents.abs();
      }

      transactions.add(StatementTransaction(
        id: row.read<int>('id'),
        date: DateTime.parse(row.read<String>('transaction_date')),
        type: row.read<String>('transaction_type'),
        description: row.readNullable<String>('description'),
        amountCents: amountCents,
        runningBalanceCents: runningBalance,
        referenceId: row.readNullable<int>('reference_id'),
        referenceType: row.readNullable<String>('reference_type'),
      ));
    }

    final closingBalanceCents = openingBalanceCents + totalDebits - totalCredits;

    return CustomerStatementData(
      customerId: _customerId,
      customerName: cInfo.read<String>('name'),
      customerPhone: cInfo.readNullable<String>('phone'),
      customerEmail: cInfo.readNullable<String>('email'),
      customerAddress: cInfo.readNullable<String>('address'),
      customerSegment: cInfo.readNullable<String>('segment'),
      openingBalanceCents: openingBalanceCents,
      closingBalanceCents: closingBalanceCents,
      totalDebitsCents: totalDebits,
      totalCreditsCents: totalCredits,
      transactions: transactions,
      dateRange: _dateRange,
      customers: customers,
    );
  }
}
