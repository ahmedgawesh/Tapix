import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
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
  final int balanceCents;

  const SupplierDrilldownOption({
    required this.id,
    required this.name,
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

class SupplierBalanceDrilldownBloc extends RealtimeBloc<
    SupplierBalanceDrilldownData, SupplierBalanceDrilldownEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  int? _supplierId;

  SupplierBalanceDrilldownBloc(this._db) : super(const RealtimeLoading());

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
        .select(_db.supplierTransactions)
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
    // Load supplier list for the selector
    final supplierRows = await _db.customSelect(
      '''
      SELECT s.id, s.name, s.balance_cents
      FROM suppliers s
      WHERE s.is_active = 1
      ORDER BY s.name ASC
      ''',
      readsFrom: {_db.suppliers},
    ).get();

    final suppliers = supplierRows
        .map((row) => SupplierDrilldownOption(
              id: row.read<int>('id'),
              name: row.read<String>('name'),
              balanceCents: row.read<int>('balance_cents'),
            ))
        .toList();

    if (_supplierId == null) {
      return SupplierBalanceDrilldownData(
        dateRange: _dateRange,
        suppliers: suppliers,
      );
    }

    // Load supplier info
    final supplierInfoRows = await _db.customSelect(
      '''
      SELECT s.id, s.name, s.phone, s.email, s.address
      FROM suppliers s
      WHERE s.id = ?
      ''',
      variables: [Variable.withInt(_supplierId!)],
      readsFrom: {_db.suppliers},
    ).get();

    if (supplierInfoRows.isEmpty) {
      return SupplierBalanceDrilldownData(
        dateRange: _dateRange,
        suppliers: suppliers,
      );
    }

    final sInfo = supplierInfoRows.first;

    // Calculate opening balance:
    // The suppliers.balance_cents includes an initial balance set at creation
    // which is NOT recorded as a supplier_transaction. So we must derive it:
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
        s.balance_cents AS current_balance,
        COALESCE(all_txn.total, 0) AS all_txn_total,
        COALESCE(before_txn.total, 0) AS before_txn_total
      FROM suppliers s
      LEFT JOIN (
        SELECT COALESCE(SUM(amount_cents), 0) AS total
        FROM supplier_transactions WHERE supplier_id = ?
      ) all_txn ON 1=1
      LEFT JOIN (
        SELECT COALESCE(SUM(amount_cents), 0) AS total
        FROM supplier_transactions WHERE supplier_id = ? AND transaction_date < ?
      ) before_txn ON 1=1
      WHERE s.id = ?
      ''',
      variables: [
        Variable.withInt(_supplierId!),
        Variable.withInt(_supplierId!),
        Variable.withString(startIso),
        Variable.withInt(_supplierId!),
      ],
      readsFrom: {_db.suppliers, _db.supplierTransactions},
    ).get();

    final int openingBalanceCents;
    if (openingRows.isNotEmpty) {
      final row = openingRows.first;
      final currentBalance = row.read<int>('current_balance');
      final allTxnTotal = row.read<int>('all_txn_total');
      final beforeTxnTotal = row.read<int>('before_txn_total');
      // initial_balance = current_balance - all_transactions
      // opening = initial_balance + transactions_before_period
      openingBalanceCents = (currentBalance - allTxnTotal) + beforeTxnTotal;
    } else {
      openingBalanceCents = 0;
    }

    // Load transactions within date range
    final txnRows = await _db.customSelect(
      '''
      SELECT id, transaction_type, amount_cents, description,
             reference_id, reference_type, transaction_date
      FROM supplier_transactions
      WHERE supplier_id = ? AND transaction_date >= ? AND transaction_date <= ?
      ORDER BY transaction_date ASC, id ASC
      ''',
      variables: [
        Variable.withInt(_supplierId!),
        Variable.withString(startIso),
        Variable.withString(endIso),
      ],
      readsFrom: {_db.supplierTransactions},
    ).get();

    int runningBalance = openingBalanceCents;
    int totalDebits = 0;
    int totalCredits = 0;
    final transactions = <DrilldownTransaction>[];
    final typeMap = <String, _TypeAccumulator>{};

    for (final row in txnRows) {
      final amountCents = row.read<int>('amount_cents');
      final type = row.read<String>('transaction_type');
      runningBalance += amountCents;

      if (amountCents > 0) {
        totalDebits += amountCents;
      } else {
        totalCredits += amountCents.abs();
      }

      // Accumulate per-type summary
      final acc = typeMap.putIfAbsent(type, () => _TypeAccumulator());
      acc.count++;
      if (amountCents > 0) {
        acc.totalDebitCents += amountCents;
      } else {
        acc.totalCreditCents += amountCents.abs();
      }
      acc.netCents += amountCents;

      transactions.add(DrilldownTransaction(
        id: row.read<int>('id'),
        date: DateTime.parse(row.read<String>('transaction_date')),
        type: type,
        description: row.readNullable<String>('description'),
        amountCents: amountCents,
        runningBalanceCents: runningBalance,
        referenceId: row.readNullable<int>('reference_id'),
        referenceType: row.readNullable<String>('reference_type'),
      ));
    }

    // Build type summaries sorted by absolute net descending
    final typeSummaries = typeMap.entries
        .map((e) => DrilldownTypeSummary(
              type: e.key,
              count: e.value.count,
              totalDebitCents: e.value.totalDebitCents,
              totalCreditCents: e.value.totalCreditCents,
              netCents: e.value.netCents,
            ))
        .toList()
      ..sort((a, b) => b.netCents.abs().compareTo(a.netCents.abs()));

    final closingBalanceCents =
        openingBalanceCents + totalDebits - totalCredits;

    return SupplierBalanceDrilldownData(
      supplierId: _supplierId,
      supplierName: sInfo.read<String>('name'),
      supplierPhone: sInfo.readNullable<String>('phone'),
      supplierEmail: sInfo.readNullable<String>('email'),
      supplierAddress: sInfo.readNullable<String>('address'),
      openingBalanceCents: openingBalanceCents,
      closingBalanceCents: closingBalanceCents,
      totalDebitsCents: totalDebits,
      totalCreditsCents: totalCredits,
      transactions: transactions,
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
