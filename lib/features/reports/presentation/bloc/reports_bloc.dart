import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../../accounting/domain/models/trial_balance.dart';
import '../../../accounting/domain/models/reconciliation_result.dart';
import '../../../accounting/domain/repositories/journal_repository.dart';
import '../widgets/report_date_range.dart';

// ==================== EVENTS ====================

abstract class ReportsEvent extends RealtimeEvent {
  const ReportsEvent();
}

class ReportsReconciliationRequested extends ReportsEvent {
  const ReportsReconciliationRequested();
}

class ReportsDateRangeChanged extends ReportsEvent {
  final ReportDateRange dateRange;
  const ReportsDateRangeChanged(this.dateRange);
}

// ==================== DATA ====================

class ReportsData {
  final TrialBalance trialBalance;
  final ReconciliationResult? reconciliation;
  final ReportDateRange dateRange;

  const ReportsData({
    required this.trialBalance,
    this.reconciliation,
    required this.dateRange,
  });

  bool get isHealthy =>
      trialBalance.isBalanced &&
      (reconciliation == null || reconciliation!.isHealthy);

  int get issueCount => reconciliation?.issues.length ?? 0;

  ReportsData copyWith({
    TrialBalance? trialBalance,
    ReconciliationResult? reconciliation,
    ReportDateRange? dateRange,
  }) {
    return ReportsData(
      trialBalance: trialBalance ?? this.trialBalance,
      reconciliation: reconciliation ?? this.reconciliation,
      dateRange: dateRange ?? this.dateRange,
    );
  }
}

// ==================== BLOC ====================

class ReportsBloc extends RealtimeBloc<ReportsData, ReportsEvent> {
  final JournalRepository _repository;
  final AppDatabase _db;
  ReportDateRange _dateRange = ReportDateRange.thisMonth();

  ReportsBloc(this._repository, this._db) : super(const RealtimeLoading());

  ReportDateRange get dateRange => _dateRange;

  @override
  Stream<ReportsData> get dataStream {
    // Watch the sales table for changes and recompute from transaction tables.
    // We watch sales as a trigger; any insert/update there causes a re-query.
    return _db.select(_db.sales).watch().asyncMap((_) => _computeFromTransactions());
  }

  @override
  void registerEventHandlers() {
    on<ReportsReconciliationRequested>(_onReconciliationRequested);
    on<ReportsDateRangeChanged>(_onDateRangeChanged);
  }

  Future<void> _onDateRangeChanged(
    ReportsDateRangeChanged event,
    Emitter<RealtimeState<ReportsData>> emit,
  ) async {
    _dateRange = event.dateRange;
    // Re-subscribe to the new date range stream
    refresh();
  }

  Future<void> _onReconciliationRequested(
    ReportsReconciliationRequested event,
    Emitter<RealtimeState<ReportsData>> emit,
  ) async {
    try {
      final reconciliation = await _repository.reconcileBalances();
      final current = currentData;
      if (current != null) {
        emit(RealtimeSuccess<ReportsData>(
          data: current.copyWith(reconciliation: reconciliation),
        ));
      }
    } catch (e, st) {
      emit(RealtimeError<ReportsData>(
        error: e,
        stackTrace: st,
        previousData: currentData,
      ));
    }
  }

  /// Compute trial balance directly from transaction tables
  /// (sales, purchases, expenses, sale_returns, purchase_returns).
  /// Maps to the same TrialBalance model so all screens work unchanged.
  Future<ReportsData> _computeFromTransactions() async {
    final startIso = _dateRange.startDate.toIso8601String();
    final endIso = _dateRange.endDate.toIso8601String();

    // ── Sales Revenue ──
    final salesRow = await _db.customSelect(
      '''
      SELECT
        COALESCE(SUM(s.total_cents), 0) AS total,
        COALESCE(SUM(s.total_cents - s.tax_cents), 0) AS net_revenue,
        COALESCE(SUM(s.tax_cents), 0) AS tax,
        COALESCE(SUM(s.paid_amount_cents), 0) AS paid
      FROM sales s
      WHERE s.status != 'voided'
        AND s.sale_date >= ? AND s.sale_date <= ?
      ''',
      variables: [Variable.withString(startIso), Variable.withString(endIso)],
      readsFrom: {_db.sales},
    ).getSingle();

    final salesTotal = salesRow.read<int>('total');
    final salesNetRevenue = salesRow.read<int>('net_revenue');
    final salesTax = salesRow.read<int>('tax');
    final salesPaid = salesRow.read<int>('paid');

    // ── Sale Returns ──
    final saleRetRow = await _db.customSelect(
      '''
      SELECT
        COALESCE(SUM(sr.total_cents), 0) AS total,
        COALESCE(SUM(sr.total_cents - sr.tax_cents), 0) AS net_return,
        COALESCE(SUM(sr.tax_cents), 0) AS tax
      FROM sale_returns sr
      WHERE sr.status = 'posted'
        AND sr.return_date >= ? AND sr.return_date <= ?
      ''',
      variables: [Variable.withString(startIso), Variable.withString(endIso)],
      readsFrom: {_db.saleReturns},
    ).getSingle();

    final saleReturnTotal = saleRetRow.read<int>('total');
    final saleReturnNet = saleRetRow.read<int>('net_return');

    // ── Purchases (COGS / Inventory) ──
    final purchRow = await _db.customSelect(
      '''
      SELECT
        COALESCE(SUM(p.total_cents), 0) AS total,
        COALESCE(SUM(p.total_cents - p.tax_cents), 0) AS net_cost,
        COALESCE(SUM(p.tax_cents), 0) AS tax,
        COALESCE(SUM(p.paid_amount_cents), 0) AS paid
      FROM purchases p
      WHERE p.status != 'voided'
        AND p.purchase_date >= ? AND p.purchase_date <= ?
      ''',
      variables: [Variable.withString(startIso), Variable.withString(endIso)],
      readsFrom: {_db.purchases},
    ).getSingle();

    final purchTotal = purchRow.read<int>('total');
    final purchNetCost = purchRow.read<int>('net_cost');
    final purchPaid = purchRow.read<int>('paid');

    // ── Purchase Returns ──
    final purchRetRow = await _db.customSelect(
      '''
      SELECT
        COALESCE(SUM(pr.total_cents), 0) AS total,
        COALESCE(SUM(pr.total_cents - pr.tax_cents), 0) AS net_return
      FROM purchase_returns pr
      WHERE pr.status = 'posted'
        AND pr.return_date >= ? AND pr.return_date <= ?
      ''',
      variables: [Variable.withString(startIso), Variable.withString(endIso)],
      readsFrom: {_db.purchaseReturns},
    ).getSingle();

    final purchReturnTotal = purchRetRow.read<int>('total');
    final purchReturnNet = purchRetRow.read<int>('net_return');

    // ── Expenses ──
    final expRow = await _db.customSelect(
      '''
      SELECT COALESCE(SUM(e.amount_cents), 0) AS total
      FROM expenses e
      WHERE e.expense_date >= ? AND e.expense_date <= ?
      ''',
      variables: [Variable.withString(startIso), Variable.withString(endIso)],
      readsFrom: {_db.expenses},
    ).getSingle();

    final expenseTotal = expRow.read<int>('total');

    // ── Build Trial Balance Items ──
    // Revenue = net sales revenue - net sale returns
    final netRevenue = salesNetRevenue - saleReturnNet;

    // COGS = net purchase cost - net purchase returns
    final netCOGS = purchNetCost - purchReturnNet;

    // Cash = sales paid - purchases paid - expenses + purchase return refunds - sale return refunds
    final cashBalance = salesPaid - purchPaid - expenseTotal
        + purchReturnTotal - saleReturnTotal;

    // Accounts Receivable = sales total - sales paid
    final receivables = salesTotal - salesPaid;

    // Inventory (purchases added, sales COGS deducted)
    // Simplified: purchases net cost - purchase returns + (no direct COGS tracking)
    // Since we don't track COGS separately, inventory = purchases - purchase returns
    final inventory = purchNetCost - purchReturnNet;

    // Accounts Payable = purchases total - purchases paid
    final payables = purchTotal - purchPaid;

    // Tax Payable = sales tax collected - sale return tax refunded
    final saleReturnTax = saleRetRow.read<int>('tax');
    final netTaxPayable = salesTax - saleReturnTax;

    final items = <TrialBalanceItem>[];
    int totalDebits = 0;
    int totalCredits = 0;

    void addItem(int id, String code, String name, String type, int amount) {
      if (amount == 0) return;
      final typeLower = type.toLowerCase();
      int debit = 0;
      int credit = 0;

      if (typeLower == 'asset' || typeLower == 'expense') {
        if (amount >= 0) {
          debit = amount;
        } else {
          credit = -amount;
        }
      } else {
        // liability, equity, revenue
        if (amount >= 0) {
          credit = amount;
        } else {
          debit = -amount;
        }
      }

      totalDebits += debit;
      totalCredits += credit;

      items.add(TrialBalanceItem(
        accountId: id,
        accountCode: code,
        accountName: name,
        accountType: typeLower,
        debitCents: debit,
        creditCents: credit,
      ));
    }

    // Asset accounts
    addItem(1, '1000', 'Cash', 'Asset', cashBalance);
    addItem(2, '1100', 'Accounts Receivable', 'Asset', receivables);
    addItem(3, '1200', 'Inventory', 'Asset', inventory);

    // Liability accounts
    addItem(4, '2000', 'Accounts Payable', 'Liability', payables);
    addItem(5, '2100', 'Tax Payable', 'Liability', netTaxPayable);

    // Revenue accounts
    addItem(6, '4000', 'Sales Revenue', 'Revenue', netRevenue);

    // Expense accounts
    addItem(7, '5000', 'Cost of Goods Sold', 'Expense', netCOGS);
    addItem(8, '5100', 'Operating Expenses', 'Expense', expenseTotal);

    // Equity = Assets - Liabilities (retained earnings / balancing)
    final totalAssets = cashBalance + receivables + inventory;
    final totalLiabilities = payables + netTaxPayable;
    final equity = totalAssets - totalLiabilities - netRevenue + netCOGS + expenseTotal;
    addItem(9, '3000', 'Equity', 'Equity', equity);

    items.sort((a, b) => a.accountCode.compareTo(b.accountCode));

    final trialBalance = TrialBalance(
      asOfDate: _dateRange.endDate,
      items: items,
      totalDebitCents: totalDebits,
      totalCreditCents: totalCredits,
      isBalanced: totalDebits == totalCredits,
    );

    final existingReconciliation = currentData?.reconciliation;

    return ReportsData(
      trialBalance: trialBalance,
      reconciliation: existingReconciliation,
      dateRange: _dateRange,
    );
  }

}
