import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class CustomerReportsEvent extends RealtimeEvent {
  const CustomerReportsEvent();
}

class CustomerReportsDateRangeChanged extends CustomerReportsEvent {
  final ReportDateRange dateRange;
  const CustomerReportsDateRangeChanged(this.dateRange);
}

class CustomerReportsTabChanged extends CustomerReportsEvent {
  final int tabIndex;
  const CustomerReportsTabChanged(this.tabIndex);
}

// ==================== DATA MODELS ====================

class CustomerStatementItem {
  final int transactionId;
  final DateTime date;
  final String type;
  final String? description;
  final int amountCents;
  final int runningBalanceCents;

  const CustomerStatementItem({
    required this.transactionId,
    required this.date,
    required this.type,
    this.description,
    required this.amountCents,
    required this.runningBalanceCents,
  });
}

class CustomerStatementData {
  final int customerId;
  final String customerName;
  final int openingBalanceCents;
  final int closingBalanceCents;
  final int totalDebitCents;
  final int totalCreditCents;
  final List<CustomerStatementItem> items;

  const CustomerStatementData({
    required this.customerId,
    required this.customerName,
    required this.openingBalanceCents,
    required this.closingBalanceCents,
    required this.totalDebitCents,
    required this.totalCreditCents,
    required this.items,
  });
}

class CustomerAgingItem {
  final int customerId;
  final String customerName;
  final String segment;
  final int currentCents;
  final int days30Cents;
  final int days60Cents;
  final int days90Cents;
  final int over90Cents;
  final int totalCents;

  const CustomerAgingItem({
    required this.customerId,
    required this.customerName,
    required this.segment,
    required this.currentCents,
    required this.days30Cents,
    required this.days60Cents,
    required this.days90Cents,
    required this.over90Cents,
    required this.totalCents,
  });
}

class CustomerAnalyticsItem {
  final int customerId;
  final String customerName;
  final String segment;
  final int totalSpentCents;
  final int totalTransactions;
  final int averageOrderCents;
  final int balanceCents;
  final DateTime? lastTransactionAt;

  const CustomerAnalyticsItem({
    required this.customerId,
    required this.customerName,
    required this.segment,
    required this.totalSpentCents,
    required this.totalTransactions,
    required this.averageOrderCents,
    required this.balanceCents,
    this.lastTransactionAt,
  });
}

class CustomerReportsData {
  final List<CustomerStatementData> statements;
  final List<CustomerAgingItem> agingItems;
  final List<CustomerAnalyticsItem> analyticsItems;
  final int totalReceivablesCents;
  final int totalCustomers;
  final int totalOverdueCents;
  final ReportDateRange dateRange;
  final int activeTab;

  const CustomerReportsData({
    this.statements = const [],
    this.agingItems = const [],
    this.analyticsItems = const [],
    this.totalReceivablesCents = 0,
    this.totalCustomers = 0,
    this.totalOverdueCents = 0,
    required this.dateRange,
    this.activeTab = 0,
  });

  CustomerReportsData copyWith({
    List<CustomerStatementData>? statements,
    List<CustomerAgingItem>? agingItems,
    List<CustomerAnalyticsItem>? analyticsItems,
    int? totalReceivablesCents,
    int? totalCustomers,
    int? totalOverdueCents,
    ReportDateRange? dateRange,
    int? activeTab,
  }) {
    return CustomerReportsData(
      statements: statements ?? this.statements,
      agingItems: agingItems ?? this.agingItems,
      analyticsItems: analyticsItems ?? this.analyticsItems,
      totalReceivablesCents: totalReceivablesCents ?? this.totalReceivablesCents,
      totalCustomers: totalCustomers ?? this.totalCustomers,
      totalOverdueCents: totalOverdueCents ?? this.totalOverdueCents,
      dateRange: dateRange ?? this.dateRange,
      activeTab: activeTab ?? this.activeTab,
    );
  }
}

// ==================== BLOC ====================

class CustomerReportsBloc
    extends RealtimeBloc<CustomerReportsData, CustomerReportsEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();

  CustomerReportsBloc(this._db) : super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<CustomerReportsData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<CustomerReportsDateRangeChanged>(_onDateRangeChanged);
    on<CustomerReportsTabChanged>(_onTabChanged);
  }

  Stream<CustomerReportsData> _buildCombinedStream() {
    // Watch customer_transactions for real-time changes
    return _db.select(_db.customerTransactions).watch().asyncMap((_) async {
      final statements = await _loadStatements();
      final aging = await _loadAging();
      final analytics = await _loadAnalytics();

      int totalReceivables = 0;
      int totalOverdue = 0;
      for (final item in aging) {
        totalReceivables += item.totalCents;
        totalOverdue += item.days30Cents + item.days60Cents + item.days90Cents + item.over90Cents;
      }

      return CustomerReportsData(
        statements: statements,
        agingItems: aging,
        analyticsItems: analytics,
        totalReceivablesCents: totalReceivables,
        totalCustomers: analytics.length,
        totalOverdueCents: totalOverdue,
        dateRange: _dateRange,
        activeTab: currentData?.activeTab ?? 0,
      );
    });
  }

  Future<void> _onDateRangeChanged(
    CustomerReportsDateRangeChanged event,
    Emitter<RealtimeState<CustomerReportsData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onTabChanged(
    CustomerReportsTabChanged event,
    Emitter<RealtimeState<CustomerReportsData>> emit,
  ) {
    final current = currentData;
    if (current != null) {
      emit(RealtimeSuccess<CustomerReportsData>(
        data: current.copyWith(activeTab: event.tabIndex),
      ));
    }
  }

  Future<List<CustomerStatementData>> _loadStatements() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    // Get all active customers with transactions in the date range
    final customers = await _db.select(_db.customers).get();
    final statements = <CustomerStatementData>[];

    for (final customer in customers) {
      if (!customer.isActive) continue;

      // Get transactions before the start date for opening balance
      final priorRows = await _db.customSelect(
        'SELECT COALESCE(SUM(amount_cents), 0) AS total '
        'FROM customer_transactions '
        'WHERE customer_id = ? AND transaction_date < ?',
        variables: [
          Variable.withInt(customer.id),
          Variable.withString(startIso),
        ],
        readsFrom: {_db.customerTransactions},
      ).getSingle();
      final openingBalance = priorRows.read<int>('total');

      // Get transactions in the date range
      final txRows = await _db.customSelect(
        'SELECT id, transaction_type, amount_cents, description, transaction_date '
        'FROM customer_transactions '
        'WHERE customer_id = ? AND transaction_date >= ? AND transaction_date <= ? '
        'ORDER BY transaction_date ASC, id ASC',
        variables: [
          Variable.withInt(customer.id),
          Variable.withString(startIso),
          Variable.withString(endIso),
        ],
        readsFrom: {_db.customerTransactions},
      ).get();

      if (txRows.isEmpty) continue;

      int runningBalance = openingBalance;
      int totalDebit = 0;
      int totalCredit = 0;
      final items = <CustomerStatementItem>[];

      for (final row in txRows) {
        final amount = row.read<int>('amount_cents');
        runningBalance += amount;

        if (amount > 0) {
          totalDebit += amount;
        } else {
          totalCredit += amount.abs();
        }

        items.add(CustomerStatementItem(
          transactionId: row.read<int>('id'),
          date: DateTime.parse(row.read<String>('transaction_date')),
          type: row.read<String>('transaction_type'),
          description: row.readNullable<String>('description'),
          amountCents: amount,
          runningBalanceCents: runningBalance,
        ));
      }

      statements.add(CustomerStatementData(
        customerId: customer.id,
        customerName: customer.name,
        openingBalanceCents: openingBalance,
        closingBalanceCents: runningBalance,
        totalDebitCents: totalDebit,
        totalCreditCents: totalCredit,
        items: items,
      ));
    }

    return statements;
  }

  Future<List<CustomerAgingItem>> _loadAging() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final days30 = today.subtract(const Duration(days: 30));
    final days60 = today.subtract(const Duration(days: 60));
    final days90 = today.subtract(const Duration(days: 90));

    final rows = await _db.customSelect(
      '''
      SELECT 
        c.id AS customer_id,
        c.name AS customer_name,
        c.segment AS segment,
        COALESCE(SUM(CASE WHEN ct.transaction_date >= ? THEN ct.amount_cents ELSE 0 END), 0) AS current_cents,
        COALESCE(SUM(CASE WHEN ct.transaction_date >= ? AND ct.transaction_date < ? THEN ct.amount_cents ELSE 0 END), 0) AS days_30_cents,
        COALESCE(SUM(CASE WHEN ct.transaction_date >= ? AND ct.transaction_date < ? THEN ct.amount_cents ELSE 0 END), 0) AS days_60_cents,
        COALESCE(SUM(CASE WHEN ct.transaction_date >= ? AND ct.transaction_date < ? THEN ct.amount_cents ELSE 0 END), 0) AS days_90_cents,
        COALESCE(SUM(CASE WHEN ct.transaction_date < ? THEN ct.amount_cents ELSE 0 END), 0) AS over_90_cents,
        COALESCE(SUM(ct.amount_cents), 0) AS total_cents
      FROM customers c
      LEFT JOIN customer_transactions ct ON ct.customer_id = c.id
      WHERE c.is_active = 1
      GROUP BY c.id
      HAVING total_cents > 0
      ORDER BY total_cents DESC
      ''',
      variables: [
        Variable.withString(days30.toIso8601String()),
        Variable.withString(days60.toIso8601String()),
        Variable.withString(days30.toIso8601String()),
        Variable.withString(days90.toIso8601String()),
        Variable.withString(days60.toIso8601String()),
        Variable.withString(days90.toIso8601String()),
        Variable.withString(days90.toIso8601String()),
        Variable.withString(days90.toIso8601String()),
      ],
      readsFrom: {_db.customers, _db.customerTransactions},
    ).get();

    return rows.map((row) {
      return CustomerAgingItem(
        customerId: row.read<int>('customer_id'),
        customerName: row.read<String>('customer_name'),
        segment: row.read<String>('segment'),
        currentCents: row.read<int>('current_cents'),
        days30Cents: row.read<int>('days_30_cents'),
        days60Cents: row.read<int>('days_60_cents'),
        days90Cents: row.read<int>('days_90_cents'),
        over90Cents: row.read<int>('over_90_cents'),
        totalCents: row.read<int>('total_cents'),
      );
    }).toList();
  }

  Future<List<CustomerAnalyticsItem>> _loadAnalytics() async {
    final rows = await _db.customSelect(
      '''
      SELECT 
        c.id AS customer_id,
        c.name AS customer_name,
        c.segment AS segment,
        c.total_spent_cents AS total_spent_cents,
        c.total_transactions AS total_transactions,
        c.balance_cents AS balance_cents,
        c.last_transaction_at AS last_transaction_at
      FROM customers c
      WHERE c.is_active = 1
      ORDER BY c.total_spent_cents DESC
      ''',
      readsFrom: {_db.customers},
    ).get();

    return rows.map((row) {
      final totalSpent = row.read<int>('total_spent_cents');
      final totalTx = row.read<int>('total_transactions');
      final avgOrder = totalTx > 0 ? totalSpent ~/ totalTx : 0;
      final lastTxStr = row.readNullable<String>('last_transaction_at');

      return CustomerAnalyticsItem(
        customerId: row.read<int>('customer_id'),
        customerName: row.read<String>('customer_name'),
        segment: row.read<String>('segment'),
        totalSpentCents: totalSpent,
        totalTransactions: totalTx,
        averageOrderCents: avgOrder,
        balanceCents: row.read<int>('balance_cents'),
        lastTransactionAt: lastTxStr != null ? DateTime.tryParse(lastTxStr) : null,
      );
    }).toList();
  }
}
