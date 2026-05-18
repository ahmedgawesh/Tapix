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

class CustomCurrencyAdded extends CurrencyEvent {
  final Currency currency;
  final bool setAsActive;
  const CustomCurrencyAdded(this.currency, {this.setAsActive = true});
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
    on<CustomCurrencyAdded>(_onCustomCurrencyAdded);
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

  Future<void> _onCustomCurrencyAdded(
    CustomCurrencyAdded event,
    Emitter<RealtimeState<Currency>> emit,
  ) async {
    await _currencyService.addCustomCurrency(event.currency);
    if (event.setAsActive) {
      await performOptimisticUpdate(
        operationId: 'currency_custom_${DateTime.now().millisecondsSinceEpoch}',
        optimisticData: event.currency,
        operation: () => _currencyService.setCurrency(event.currency.code),
      );
    }
  }
}
