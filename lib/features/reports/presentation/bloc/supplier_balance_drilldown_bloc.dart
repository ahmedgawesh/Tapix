import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../services/party_statement_ledger_service.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class SupplierBalanceDrilldownEvent extends RealtimeEvent {
  const SupplierBalanceDrilldownEvent();
}

class SupplierBalanceDrilldownDateRangeChanged
    extends SupplierBalanceDrilldownEvent {
  final ReportDateRange dateRange;
  const SupplierBalanceDrilldownDateRangeChanged(this.dateRange);
}

class SupplierBalanceDrilldownSupplierChanged
    extends SupplierBalanceDrilldownEvent {
  final int? supplierId;
  const SupplierBalanceDrilldownSupplierChanged(this.supplierId);
}

// ==================== DATA MODELS ====================

class DrilldownTransaction {
  final int id;
  final DateTime date;
  final String type;
  final String? description;
  final int amountCents;
  final int runningBalanceCents;
  final int? referenceId;
  final String? referenceType;

  const DrilldownTransaction({
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

class DrilldownTypeSummary {
  final String type;
  final int count;
  final int totalDebitCents;
  final int totalCreditCents;
  final int netCents;

  const DrilldownTypeSummary({
    required this.type,
    this.count = 0,
    this.totalDebitCents = 0,
    this.totalCreditCents = 0,
    this.netCents = 0,
  });
}

class SupplierDrilldownOption {
  final int id;
  final String name;
  final String? phone;
  final int balanceCents;

  const SupplierDrilldownOption({
    required this.id,
    required this.name,
    this.phone,
    required this.balanceCents,
  });
}

class SupplierBalanceDrilldownData {
  final int? supplierId;
  final String? supplierName;
  final String? supplierPhone;
  final String? supplierEmail;
  final String? supplierAddress;
  final int openingBalanceCents;
  final int closingBalanceCents;
  final int totalDebitsCents;
  final int totalCreditsCents;
  final List<DrilldownTransaction> transactions;
  final List<DrilldownTypeSummary> typeSummaries;
  final ReportDateRange dateRange;
  final List<SupplierDrilldownOption> suppliers;

  const SupplierBalanceDrilldownData({
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
    this.typeSummaries = const [],
    required this.dateRange,
    this.suppliers = const [],
  });

  int get transactionCount => transactions.length;

  SupplierBalanceDrilldownData copyWith({
    int? supplierId,
    String? supplierName,
    String? supplierPhone,
    String? supplierEmail,
    String? supplierAddress,
    int? openingBalanceCents,
    int? closingBalanceCents,
    int? totalDebitsCents,
    int? totalCreditsCents,
    List<DrilldownTransaction>? transactions,
    List<DrilldownTypeSummary>? typeSummaries,
    ReportDateRange? dateRange,
    List<SupplierDrilldownOption>? suppliers,
  }) {
    return SupplierBalanceDrilldownData(
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
      typeSummaries: typeSummaries ?? this.typeSummaries,
      dateRange: dateRange ?? this.dateRange,
      suppliers: suppliers ?? this.suppliers,
    );
  }
}

// ==================== BLOC ====================

class SupplierBalanceDrilldownBloc
    extends
        RealtimeBloc<
          SupplierBalanceDrilldownData,
          SupplierBalanceDrilldownEvent
        > {
  final AppDatabase _db;
  ReportDateRange _dateRange;
  int? _supplierId;

  SupplierBalanceDrilldownBloc(this._db, {String defaultDateRange = 'month'})
    : _dateRange = ReportDateRange.fromSettingsDefault(defaultDateRange),
      super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;
  int? get supplierId => _supplierId;

  @override
  Stream<SupplierBalanceDrilldownData> get dataStream {
    return _buildCombinedStream();
  }

  @override
  void registerEventHandlers() {
    on<SupplierBalanceDrilldownDateRangeChanged>(_onDateRangeChanged);
    on<SupplierBalanceDrilldownSupplierChanged>(_onSupplierChanged);
  }

  Stream<SupplierBalanceDrilldownData> _buildCombinedStream() {
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.suppliers, _db.supplierTransactions},
        )
        .watch()
        .asyncMap((_) async => _loadDrilldownData());
  }

  Future<void> _onDateRangeChanged(
    SupplierBalanceDrilldownDateRangeChanged event,
    Emitter<RealtimeState<SupplierBalanceDrilldownData>> emit,
  ) async {
    _dateRange = event.dateRange;
    refresh();
  }

  Future<void> _onSupplierChanged(
    SupplierBalanceDrilldownSupplierChanged event,
    Emitter<RealtimeState<SupplierBalanceDrilldownData>> emit,
  ) async {
    _supplierId = event.supplierId;
    refresh();
  }

  Future<SupplierBalanceDrilldownData> _loadDrilldownData() async {
    final snapshot = await PartyStatementLedgerService(_db).loadSupplier(
      supplierId: _supplierId,
      startDate: _dateRange.startDate,
      endDate: _dateRange.endDate,
    );
    final suppliers = snapshot.options
        .map(
          (option) => SupplierDrilldownOption(
            id: option.id,
            name: option.name,
            phone: option.phone,
            balanceCents: option.balanceCents,
          ),
        )
        .toList();
    final supplier = snapshot.party;
    if (supplier == null) {
      return SupplierBalanceDrilldownData(
        dateRange: _dateRange,
        suppliers: suppliers,
      );
    }

    final typeMap = <String, _TypeAccumulator>{};
    for (final transaction in snapshot.transactions) {
      final accumulator = typeMap.putIfAbsent(
        transaction.type,
        _TypeAccumulator.new,
      );
      accumulator.count++;
      if (transaction.amountCents > 0) {
        accumulator.totalDebitCents += transaction.amountCents;
      } else if (transaction.amountCents < 0) {
        accumulator.totalCreditCents += -transaction.amountCents;
      }
      accumulator.netCents += transaction.amountCents;
    }
    final typeSummaries =
        typeMap.entries
            .map(
              (entry) => DrilldownTypeSummary(
                type: entry.key,
                count: entry.value.count,
                totalDebitCents: entry.value.totalDebitCents,
                totalCreditCents: entry.value.totalCreditCents,
                netCents: entry.value.netCents,
              ),
            )
            .toList()
          ..sort((a, b) => b.netCents.abs().compareTo(a.netCents.abs()));

    return SupplierBalanceDrilldownData(
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
            (transaction) => DrilldownTransaction(
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
      typeSummaries: typeSummaries,
      dateRange: _dateRange,
      suppliers: suppliers,
    );
  }
}

class _TypeAccumulator {
  int count = 0;
  int totalDebitCents = 0;
  int totalCreditCents = 0;
  int netCents = 0;
}
