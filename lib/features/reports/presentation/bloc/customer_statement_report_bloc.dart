import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../services/party_statement_ledger_service.dart';
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

class CustomerStatementReportBloc
    extends RealtimeBloc<CustomerStatementData, CustomerStatementReportEvent> {
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
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.customers, _db.customerTransactions},
        )
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
    final snapshot = await PartyStatementLedgerService(_db).loadCustomer(
      customerId: _customerId,
      startDate: _dateRange.startDate,
      endDate: _dateRange.endDate,
    );
    final customers = snapshot.options
        .map(
          (option) => CustomerOption(
            id: option.id,
            name: option.name,
            phone: option.phone,
            balanceCents: option.balanceCents,
          ),
        )
        .toList();
    final customer = snapshot.party;
    if (customer == null) {
      return CustomerStatementData(dateRange: _dateRange, customers: customers);
    }

    return CustomerStatementData(
      customerId: customer.id,
      customerName: customer.name,
      customerPhone: customer.phone,
      customerEmail: customer.email,
      customerAddress: customer.address,
      customerSegment: customer.segment,
      openingBalanceCents: snapshot.openingBalanceCents,
      closingBalanceCents: snapshot.closingBalanceCents,
      totalDebitsCents: snapshot.totalDebitsCents,
      totalCreditsCents: snapshot.totalCreditsCents,
      transactions: snapshot.transactions
          .map(
            (transaction) => StatementTransaction(
              id: transaction.id,
              date: transaction.date,
              type: transaction.type,
              description: transaction.description,
              amountCents: transaction.amountCents,
              runningBalanceCents: transaction.runningBalanceCents,
              referenceId: transaction.referenceId,
              referenceType: transaction.referenceType,
            ),
          )
          .toList(),
      dateRange: _dateRange,
      customers: customers,
    );
  }
}
