import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../services/party_aging_ledger_service.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class CustomerReportsEvent extends RealtimeEvent {
  const CustomerReportsEvent();
}

class CustomerReportsDateRangeChanged extends CustomerReportsEvent {
  final ReportDateRange dateRange;
  const CustomerReportsDateRangeChanged(this.dateRange);
}

class CustomerReportsSearchChanged extends CustomerReportsEvent {
  final String query;
  const CustomerReportsSearchChanged(this.query);
}

// ==================== DATA MODELS ====================

/// Per-customer balance breakdown for the report
class CustomerBalanceItem {
  final int customerId;
  final String customerName;
  final String segment;
  final int openingBalanceCents;
  final int totalSalesCents;
  final int totalPaymentsCents;
  final int totalDiscountsCents;
  final int totalReturnsCents;
  final int currentBalanceCents;

  const CustomerBalanceItem({
    required this.customerId,
    required this.customerName,
    required this.segment,
    required this.openingBalanceCents,
    required this.totalSalesCents,
    required this.totalPaymentsCents,
    required this.totalDiscountsCents,
    required this.totalReturnsCents,
    required this.currentBalanceCents,
  });
}

/// Aging data models (kept for aging tab)
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

/// Analytics data models (kept for analytics tab)
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
  final List<CustomerBalanceItem> customers;
  final List<CustomerAgingItem> agingItems;
  final List<CustomerAnalyticsItem> analyticsItems;
  final int totalReceivablesCents;
  final int totalPayablesCents;
  final int totalOpeningDebitCents;
  final int totalOpeningCreditCents;
  final int totalDiscountsCents;
  final int totalPaymentsCents;
  final int activeCustomerCount;
  final ReportDateRange dateRange;
  final String searchQuery;

  const CustomerReportsData({
    this.customers = const [],
    this.agingItems = const [],
    this.analyticsItems = const [],
    this.totalReceivablesCents = 0,
    this.totalPayablesCents = 0,
    this.totalOpeningDebitCents = 0,
    this.totalOpeningCreditCents = 0,
    this.totalDiscountsCents = 0,
    this.totalPaymentsCents = 0,
    this.activeCustomerCount = 0,
    required this.dateRange,
    this.searchQuery = '',
  });

  CustomerReportsData copyWith({
    List<CustomerBalanceItem>? customers,
    List<CustomerAgingItem>? agingItems,
    List<CustomerAnalyticsItem>? analyticsItems,
    int? totalReceivablesCents,
    int? totalPayablesCents,
    int? totalOpeningDebitCents,
    int? totalOpeningCreditCents,
    int? totalDiscountsCents,
    int? totalPaymentsCents,
    int? activeCustomerCount,
    ReportDateRange? dateRange,
    String? searchQuery,
  }) {
    return CustomerReportsData(
      customers: customers ?? this.customers,
      agingItems: agingItems ?? this.agingItems,
      analyticsItems: analyticsItems ?? this.analyticsItems,
      totalReceivablesCents:
          totalReceivablesCents ?? this.totalReceivablesCents,
      totalPayablesCents: totalPayablesCents ?? this.totalPayablesCents,
      totalOpeningDebitCents:
          totalOpeningDebitCents ?? this.totalOpeningDebitCents,
      totalOpeningCreditCents:
          totalOpeningCreditCents ?? this.totalOpeningCreditCents,
      totalDiscountsCents: totalDiscountsCents ?? this.totalDiscountsCents,
      totalPaymentsCents: totalPaymentsCents ?? this.totalPaymentsCents,
      activeCustomerCount: activeCustomerCount ?? this.activeCustomerCount,
      dateRange: dateRange ?? this.dateRange,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  /// Filtered customers based on search query
  List<CustomerBalanceItem> get filteredCustomers {
    if (searchQuery.isEmpty) return customers;
    final q = searchQuery.toLowerCase();
    return customers
        .where((c) => c.customerName.toLowerCase().contains(q))
        .toList();
  }
}

// ==================== BLOC ====================

class CustomerReportsBloc
    extends RealtimeBloc<CustomerReportsData, CustomerReportsEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  String _searchQuery = '';

  CustomerReportsBloc(this._db, {String defaultDateRange = 'month'})
    : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
      super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<CustomerReportsData> get dataStream => _buildStream();

  @override
  void registerEventHandlers() {
    on<CustomerReportsDateRangeChanged>(_onDateRangeChanged);
    on<CustomerReportsSearchChanged>(_onSearchChanged);
  }

  Stream<CustomerReportsData> _buildStream() {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.customers, _db.customerTransactions},
        )
        .watch()
        .asyncMap((_) => _loadAll());
  }

  Future<CustomerReportsData> _loadAll() async {
    final balances = await _loadCustomerBalances();
    final aging = await _loadAging();
    final analytics = await _loadAnalytics();

    // Calculate summary totals from customers.balance_cents (source of truth)
    int totalReceivables = 0;
    int totalPayables = 0;
    int totalOpeningDebit = 0;
    int totalOpeningCredit = 0;
    int totalDiscounts = 0;
    int totalPayments = 0;

    for (final c in balances) {
      if (c.currentBalanceCents > 0) {
        totalReceivables += c.currentBalanceCents;
      } else if (c.currentBalanceCents < 0) {
        totalPayables += c.currentBalanceCents.abs();
      }
      if (c.openingBalanceCents > 0) {
        totalOpeningDebit += c.openingBalanceCents;
      } else if (c.openingBalanceCents < 0) {
        totalOpeningCredit += c.openingBalanceCents.abs();
      }
      totalDiscounts += c.totalDiscountsCents;
      totalPayments += c.totalPaymentsCents;
    }

    return CustomerReportsData(
      customers: balances,
      agingItems: aging,
      analyticsItems: analytics,
      totalReceivablesCents: totalReceivables,
      totalPayablesCents: totalPayables,
      totalOpeningDebitCents: totalOpeningDebit,
      totalOpeningCreditCents: totalOpeningCredit,
      totalDiscountsCents: totalDiscounts,
      totalPaymentsCents: totalPayments,
      activeCustomerCount: balances.length,
      dateRange: _dateRange,
      searchQuery: _searchQuery,
    );
  }

  Future<void> _onDateRangeChanged(
    CustomerReportsDateRangeChanged event,
    Emitter<RealtimeState<CustomerReportsData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  void _onSearchChanged(
    CustomerReportsSearchChanged event,
    Emitter<RealtimeState<CustomerReportsData>> emit,
  ) {
    _searchQuery = event.query;
    final current = currentData;
    if (current != null) {
      emit(
        RealtimeSuccess<CustomerReportsData>(
          data: current.copyWith(searchQuery: event.query),
        ),
      );
    }
  }

  /// Load the balance as of the selected end date from opening balance plus
  /// all signed ledger movements. Activity columns remain period-specific.
  ///
  /// Transaction types in customer_transactions:
  ///   sale (+), payment (-), discount (-), credit_note (-), refund (-),
  ///   adjustment (+/-), opening_balance (+/-)
  Future<List<CustomerBalanceItem>> _loadCustomerBalances() async {
    final start = _dateRange.startDate;
    final end = _dateRange.endDate;

    final rows = await _db
        .customSelect(
          '''
      SELECT 
        c.id,
        c.name,
        c.segment,
        c.opening_balance_cents,
        c.opening_balance_cents + COALESCE((
          SELECT SUM(balance_tx.amount_cents)
          FROM customer_transactions balance_tx
          WHERE balance_tx.customer_id = c.id
            AND balance_tx.transaction_date <= ?
        ), 0) AS current_balance_cents,
        COALESCE((
          SELECT SUM(ct.amount_cents)
          FROM customer_transactions ct
          WHERE ct.customer_id = c.id
            AND ct.transaction_type = 'sale'
            AND ct.transaction_date >= ?
            AND ct.transaction_date <= ?
        ), 0) AS total_sales_cents,
        COALESCE((
          SELECT SUM(ABS(ct.amount_cents))
          FROM customer_transactions ct
          WHERE ct.customer_id = c.id
            AND ct.transaction_type = 'payment'
            AND ct.transaction_date >= ?
            AND ct.transaction_date <= ?
        ), 0) AS total_payments_cents,
        COALESCE((
          SELECT SUM(ABS(ct.amount_cents))
          FROM customer_transactions ct
          WHERE ct.customer_id = c.id
            AND ct.transaction_type = 'discount'
            AND ct.transaction_date >= ?
            AND ct.transaction_date <= ?
        ), 0) AS total_discounts_cents,
        COALESCE((
          SELECT SUM(ABS(ct.amount_cents))
          FROM customer_transactions ct
          WHERE ct.customer_id = c.id
            AND ct.transaction_type IN ('credit_note', 'refund')
            AND ct.transaction_date >= ?
            AND ct.transaction_date <= ?
        ), 0) AS total_returns_cents
      FROM customers c
      WHERE c.created_at <= ?
        AND (
          c.is_active = 1 OR
          c.opening_balance_cents + COALESCE((
            SELECT SUM(inactive_tx.amount_cents)
            FROM customer_transactions inactive_tx
            WHERE inactive_tx.customer_id = c.id
              AND inactive_tx.transaction_date <= ?
          ), 0) != 0
        )
      ORDER BY ABS(current_balance_cents) DESC
      ''',
          variables: [
            Variable.withDateTime(end),
            Variable.withDateTime(start),
            Variable.withDateTime(end),
            Variable.withDateTime(start),
            Variable.withDateTime(end),
            Variable.withDateTime(start),
            Variable.withDateTime(end),
            Variable.withDateTime(start),
            Variable.withDateTime(end),
            Variable.withDateTime(end),
            Variable.withDateTime(end),
          ],
          readsFrom: {_db.customers, _db.customerTransactions},
        )
        .get();

    return rows.map((row) {
      return CustomerBalanceItem(
        customerId: row.read<int>('id'),
        customerName: row.read<String>('name'),
        segment: row.read<String>('segment'),
        openingBalanceCents: row.read<int>('opening_balance_cents'),
        totalSalesCents: row.read<int>('total_sales_cents'),
        totalPaymentsCents: row.read<int>('total_payments_cents'),
        totalDiscountsCents: row.read<int>('total_discounts_cents'),
        totalReturnsCents: row.read<int>('total_returns_cents'),
        currentBalanceCents: row.read<int>('current_balance_cents'),
      );
    }).toList();
  }

  Future<List<CustomerAgingItem>> _loadAging() async {
    final rows = await PartyAgingLedgerService(
      _db,
    ).loadCustomers(asOf: _dateRange.endDate);
    return rows.map((row) {
      final buckets = row.buckets;
      return CustomerAgingItem(
        customerId: row.partyId,
        customerName: row.partyName,
        segment: row.segment ?? 'retail',
        currentCents: buckets.currentCents,
        days30Cents: buckets.days30Cents,
        days60Cents: buckets.days60Cents,
        days90Cents: buckets.days90Cents,
        over90Cents: buckets.over90Cents,
        totalCents: buckets.totalCents,
      );
    }).toList();
  }

  Future<List<CustomerAnalyticsItem>> _loadAnalytics() async {
    final rows = await _db
        .customSelect(
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
        )
        .get();

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
        lastTransactionAt: lastTxStr != null
            ? DateTime.tryParse(lastTxStr)
            : null,
      );
    }).toList();
  }
}
