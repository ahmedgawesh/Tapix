import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/bloc/realtime_bloc.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/repositories/journal_repository.dart';

/// Events for AccountsBloc
abstract class AccountsEvent extends RealtimeEvent {
  const AccountsEvent();
}

class AccountsInitialized extends AccountsEvent {
  const AccountsInitialized();
}

class AccountFilterByTypeRequested extends AccountsEvent {
  final String? accountType;
  const AccountFilterByTypeRequested(this.accountType);
}

class AccountCreateRequested extends AccountsEvent {
  final String accountCode;
  final String accountName;
  final String accountType;
  final int currencyId;
  final int? parentAccountId;
  final String? description;

  const AccountCreateRequested({
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    required this.currencyId,
    this.parentAccountId,
    this.description,
  });
}

class AccountUpdateRequested extends AccountsEvent {
  final Account account;
  const AccountUpdateRequested(this.account);
}

class AccountDeleteRequested extends AccountsEvent {
  final int accountId;
  const AccountDeleteRequested(this.accountId);
}

/// State data for accounts
class AccountsData {
  final List<Account> accounts;
  final String? filterType;

  const AccountsData({
    required this.accounts,
    this.filterType,
  });
}

/// Bloc for managing accounts list with real-time updates
class AccountsBloc extends RealtimeBloc<AccountsData, AccountsEvent> {
  final JournalRepository _repository;
  String? _currentFilterType;

  AccountsBloc(this._repository) : super(const RealtimeLoading());

  @override
  Stream<AccountsData> get dataStream {
    if (_currentFilterType != null) {
      return _repository.watchAccountsByType(_currentFilterType!).map(
        (accounts) => AccountsData(
          accounts: accounts,
          filterType: _currentFilterType,
        ),
      );
    }
    return _repository.watchAllAccounts().map(
      (accounts) => AccountsData(accounts: accounts),
    );
  }

  @override
  void registerEventHandlers() {
    on<AccountFilterByTypeRequested>(_onFilterByType);
    on<AccountCreateRequested>(_onCreateRequested);
    on<AccountUpdateRequested>(_onUpdateRequested);
    on<AccountDeleteRequested>(_onDeleteRequested);
  }

  Future<void> _onFilterByType(
    AccountFilterByTypeRequested event,
    Emitter<RealtimeState<AccountsData>> emit,
  ) async {
    _currentFilterType = event.accountType;
    refresh();
  }

  Future<void> _onCreateRequested(
    AccountCreateRequested event,
    Emitter<RealtimeState<AccountsData>> emit,
  ) async {
    try {
      await _repository.createAccount(
        accountCode: event.accountCode,
        accountName: event.accountName,
        accountType: event.accountType,
        currencyId: event.currencyId,
        parentAccountId: event.parentAccountId,
        description: event.description,
      );
    } catch (e, st) {
      emit(RealtimeError<AccountsData>(error: e, stackTrace: st, previousData: currentData));
    }
  }

  Future<void> _onUpdateRequested(
    AccountUpdateRequested event,
    Emitter<RealtimeState<AccountsData>> emit,
  ) async {
    try {
      await _repository.updateAccount(event.account);
    } catch (e, st) {
      emit(RealtimeError<AccountsData>(error: e, stackTrace: st, previousData: currentData));
    }
  }

  Future<void> _onDeleteRequested(
    AccountDeleteRequested event,
    Emitter<RealtimeState<AccountsData>> emit,
  ) async {
    try {
      await _repository.deleteAccount(event.accountId);
    } catch (e, st) {
      emit(RealtimeError<AccountsData>(error: e, stackTrace: st, previousData: currentData));
    }
  }
}
