import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
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
  final int balanceCents;

  const SupplierOption({
    required this.id,
    required this.name,
    required this.balanceCents,
  });
}

// ==================== BLOC ====================

class SupplierStatementReportBloc extends RealtimeBloc<SupplierStatementData,
    SupplierStatementReportEvent> {
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();
  int? _supplierId;

  SupplierStatementReportBloc(this._db) : super(const RealtimeLoading());

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
        .select(_db.supplierTransactions)
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
        .map((row) => SupplierOption(
              id: row.read<int>('id'),
              name: row.read<String>('name'),
              balanceCents: row.read<int>('balance_cents'),
            ))
        .toList();

    if (_supplierId == null) {
      return SupplierStatementData(
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
      return SupplierStatementData(
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
      openingBalanceCents = (currentBalance - allTxnTotal) + beforeTxnTotal;
    } else {
      openingBalanceCents = 0;
    }

    // Load transactions within date range
    final txnRows = await _db.customSelect(
      '''
      SELECT id, transaction_type, transaction_number, discount_type,
             amount_cents, description,
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
    final transactions = <SupplierStatementTransaction>[];

    for (final row in txnRows) {
      final amountCents = row.read<int>('amount_cents');
      runningBalance += amountCents;

      if (amountCents > 0) {
        totalDebits += amountCents;
      } else {
        totalCredits += amountCents.abs();
      }

      transactions.add(SupplierStatementTransaction(
        id: row.read<int>('id'),
        date: DateTime.parse(row.read<String>('transaction_date')),
        type: row.read<String>('transaction_type'),
        transactionNumber: row.readNullable<String>('transaction_number'),
        discountType: row.readNullable<String>('discount_type'),
        description: row.readNullable<String>('description'),
        amountCents: amountCents,
        runningBalanceCents: runningBalance,
        referenceId: row.readNullable<int>('reference_id'),
        referenceType: row.readNullable<String>('reference_type'),
      ));
    }

    final closingBalanceCents = openingBalanceCents + totalDebits - totalCredits;

    return SupplierStatementData(
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
      dateRange: _dateRange,
      suppliers: suppliers,
    );
  }
}
