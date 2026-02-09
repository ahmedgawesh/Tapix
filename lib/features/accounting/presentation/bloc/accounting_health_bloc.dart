import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/models/trial_balance.dart';
import '../../domain/models/reconciliation_result.dart';
import '../../domain/repositories/journal_repository.dart';

// ==================== EVENTS ====================

abstract class AccountingHealthEvent {
  const AccountingHealthEvent();
}

class AccountingHealthCheckRequested extends AccountingHealthEvent {
  const AccountingHealthCheckRequested();
}

// ==================== STATE ====================

class AccountingHealthState {
  final bool isLoading;
  final TrialBalance? trialBalance;
  final ReconciliationResult? reconciliation;
  final String? error;

  const AccountingHealthState({
    this.isLoading = false,
    this.trialBalance,
    this.reconciliation,
    this.error,
  });

  bool get isHealthy =>
      trialBalance != null &&
      reconciliation != null &&
      trialBalance!.isBalanced &&
      reconciliation!.isHealthy;

  int get issueCount => reconciliation?.issues.length ?? 0;

  AccountingHealthState copyWith({
    bool? isLoading,
    TrialBalance? trialBalance,
    ReconciliationResult? reconciliation,
    String? error,
  }) {
    return AccountingHealthState(
      isLoading: isLoading ?? this.isLoading,
      trialBalance: trialBalance ?? this.trialBalance,
      reconciliation: reconciliation ?? this.reconciliation,
      error: error,
    );
  }
}

// ==================== BLOC ====================

class AccountingHealthBloc
    extends Bloc<AccountingHealthEvent, AccountingHealthState> {
  final JournalRepository _repository;

  AccountingHealthBloc(this._repository)
      : super(const AccountingHealthState()) {
    on<AccountingHealthCheckRequested>(_onCheckRequested);
  }

  Future<void> _onCheckRequested(
    AccountingHealthCheckRequested event,
    Emitter<AccountingHealthState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, error: null));

    try {
      final trialBalance = await _repository.getTrialBalance();
      final reconciliation = await _repository.reconcileBalances();

      emit(state.copyWith(
        isLoading: false,
        trialBalance: trialBalance,
        reconciliation: reconciliation,
      ));
    } catch (e) {
      emit(state.copyWith(
        isLoading: false,
        error: e.toString(),
      ));
    }
  }
}
