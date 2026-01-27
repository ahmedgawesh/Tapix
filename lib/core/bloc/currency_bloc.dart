import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/currency_service.dart';
import 'realtime_bloc.dart';

// Events
abstract class CurrencyEvent extends RealtimeEvent {
  const CurrencyEvent();
}

class CurrencyChanged extends CurrencyEvent {
  final String code;
  const CurrencyChanged(this.code);
}

class CurrencyBloc extends RealtimeBloc<Currency, CurrencyEvent> {
  final CurrencyService _currencyService;

  CurrencyBloc(this._currencyService)
      : super(RealtimeSuccess(data: _currencyService.getCurrency()));

  @override
  Stream<Currency> get dataStream => _currencyService.currencyStream;

  @override
  void registerEventHandlers() {
    on<CurrencyChanged>(_onCurrencyChanged);
  }

  Future<void> _onCurrencyChanged(
    CurrencyChanged event,
    Emitter<RealtimeState<Currency>> emit,
  ) async {
    // We get the full Currency object for the optimistic update
    final newCurrency = Currency.fromCode(event.code);
    
    await performOptimisticUpdate(
      operationId: 'currency_change_${DateTime.now().millisecondsSinceEpoch}',
      optimisticData: newCurrency,
      operation: () => _currencyService.setCurrency(event.code),
    );
  }
}
