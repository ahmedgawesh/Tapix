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
    try {
      await _currencyService.setCurrency(event.code);
      emit(RealtimeSuccess(data: _currencyService.getCurrency()));
    } catch (error, stackTrace) {
      emit(
        RealtimeError(
          error: error,
          stackTrace: stackTrace,
          previousData: _currencyService.getCurrency(),
        ),
      );
    }
  }

  Future<void> _onCustomCurrencyAdded(
    CustomCurrencyAdded event,
    Emitter<RealtimeState<Currency>> emit,
  ) async {
    try {
      if (event.setAsActive) {
        await _currencyService.validateCurrencyChange?.call(
          event.currency.code,
        );
      }
      await _currencyService.addCustomCurrency(event.currency);
      if (event.setAsActive) {
        await _currencyService.setCurrency(event.currency.code);
      }
      emit(RealtimeSuccess(data: _currencyService.getCurrency()));
    } catch (error, stackTrace) {
      emit(
        RealtimeError(
          error: error,
          stackTrace: stackTrace,
          previousData: _currencyService.getCurrency(),
        ),
      );
    }
  }
}
