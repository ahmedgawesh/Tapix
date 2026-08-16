import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../services/party_statement_ledger_service.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SupplierStatementReportEvent extends RealtimeEvent {
  const SupplierStatementReportEvent();
}

class SupplierStatementReportDateRangeChanged
    extends SupplierStatementReportEvent {
  final ReportDateRange dateRange;
  const SupplierStatementReportDateRangeChanged(this.dateRange);
}

class SupplierStatementReportSupplierChanged
    extends SupplierStatementReportEvent {
  final int? supplierId;
  const SupplierStatementReportSupplierChanged(this.supplierId);
}

// ==================== DATA MODELS ====================

class SupplierStatementTransaction {
  final int id;
  final DateTime date;
  final String type;
  final String? transactionNumber;
  final String? discountType;
  final String? description;
  final int amountCents;
  final int runningBalanceCents;
  final int? referenceId;
  final String? referenceType;

  const SupplierStatementTransaction({
    required this.id,
    required this.date,
    required this.type,
    this.transactionNumber,
    this.discountType,
    this.description,
    required this.amountCents,
    required this.runningBalanceCents,
    this.referenceId,
    this.referenceType,
  });
}

class SupplierStatementData {
  final int? supplierId;
  final String? supplierName;
  final String? supplierPhone;
  final String? supplierEmail;
  final String? supplierAddress;
  final int openingBalanceCents;
  final int closingBalanceCents;
  final int totalDebitsCents;
  final int totalCreditsCents;
  final List<SupplierStatementTransaction> transactions;
  final ReportDateRange dateRange;
  final List<SupplierOption> suppliers;

  const SupplierStatementData({
    this.supplierId,
    this.supplierName,
    this.supplierPhone,
    this.supplierEmail,
    this.supplierAddress,
    this.openingBalanceCents = 0,
    this.closingBalanceCents = 0,
    this.totalDebitsCents = 0,
    this.totalCreditsCents = 0,
    this.transactions = const [],
    required this.dateRange,
    this.suppliers = const [],
  });

  int get transactionCount => transactions.length;

  SupplierStatementData copyWith({
    int? supplierId,
    String? supplierName,
    String? supplierPhone,
    String? supplierEmail,
    String? supplierAddress,
    int? openingBalanceCents,
    int? closingBalanceCents,
    int? totalDebitsCents,
    int? totalCreditsCents,
    List<SupplierStatementTransaction>? transactions,
    ReportDateRange? dateRange,
    List<SupplierOption>? suppliers,
  }) {
    return SupplierStatementData(
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      supplierPhone: supplierPhone ?? this.supplierPhone,
      supplierEmail: supplierEmail ?? this.supplierEmail,
      supplierAddress: supplierAddress ?? this.supplierAddress,
      openingBalanceCents: openingBalanceCents ?? this.openingBalanceCents,
      closingBalanceCents: closingBalanceCents ?? this.closingBalanceCents,
      totalDebitsCents: totalDebitsCents ?? this.totalDebitsCents,
      totalCreditsCents: totalCreditsCents ?? this.totalCreditsCents,
      transactions: transactions ?? this.transactions,
      dateRange: dateRange ?? this.dateRange,
      suppliers: suppliers ?? this.suppliers,
    );
  }
}

class SupplierOption {
  final int id;
  final String name;
  final String? phone;
  final int balanceCents;

  const SupplierOption({
    required this.id,
    required this.name,
    this.phone,
    required this.balanceCents,
  });
}

// ==================== BLOC ====================

class SupplierStatementReportBloc
    extends RealtimeBloc<SupplierStatementData, SupplierStatementReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  int? _supplierId;

  SupplierStatementReportBloc(this._db, {String defaultDateRange = 'month'})
    : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
      super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;
  int? get supplierId => _supplierId;

  @override
  Stream<SupplierStatementData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<SupplierStatementReportDateRangeChanged>(_onDateRangeChanged);
    on<SupplierStatementReportSupplierChanged>(_onSupplierChanged);
  }

  Stream<SupplierStatementData> _buildCombinedStream() {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.suppliers, _db.supplierTransactions},
        )
        .watch()
        .asyncMap((_) async => _loadStatementData());
  }

  Future<void> _onDateRangeChanged(
    SupplierStatementReportDateRangeChanged event,
    Emitter<RealtimeState<SupplierStatementData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onSupplierChanged(
    SupplierStatementReportSupplierChanged event,
    Emitter<RealtimeState<SupplierStatementData>> emit,
  ) async {
    _supplierId = event.supplierId;
    refresh();
  }

  Future<SupplierStatementData> _loadStatementData() async {
    final snapshot = await PartyStatementLedgerService(_db).loadSupplier(
      supplierId: _supplierId,
      startDate: _dateRange.startDate,
      endDate: _dateRange.endDate,
    );
    final suppliers = snapshot.options
        .map(
          (option) => SupplierOption(
            id: option.id,
            name: option.name,
            phone: option.phone,
            balanceCents: option.balanceCents,
          ),
        )
        .toList();
    final supplier = snapshot.party;
    if (supplier == null) {
      return SupplierStatementData(dateRange: _dateRange, suppliers: suppliers);
    }

    return SupplierStatementData(
      supplierId: supplier.id,
      supplierName: supplier.name,
      supplierPhone: supplier.phone,
      supplierEmail: supplier.email,
      supplierAddress: supplier.address,
      openingBalanceCents: snapshot.openingBalanceCents,
      closingBalanceCents: snapshot.closingBalanceCents,
      totalDebitsCents: snapshot.totalDebitsCents,
      totalCreditsCents: snapshot.totalCreditsCents,
      transactions: snapshot.transactions
          .map(
            (transaction) => SupplierStatementTransaction(
              id: transaction.id,
              date: transaction.date,
              type: transaction.type,
              transactionNumber: transaction.transactionNumber,
              discountType: transaction.discountType,
              description: transaction.description,
              amountCents: transaction.amountCents,
              runningBalanceCents: transaction.runningBalanceCents,
              referenceId: transaction.referenceId,
              referenceType: transaction.referenceType,
            ),
          )
          .toList(),
      dateRange: _dateRange,
      suppliers: suppliers,
    );
  }
}
