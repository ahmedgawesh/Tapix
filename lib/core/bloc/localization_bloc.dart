import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/localization_service.dart';
import 'realtime_bloc.dart';

// Events
abstract class LocalizationEvent extends RealtimeEvent {
  const LocalizationEvent();
}

class LocaleChanged extends LocalizationEvent {
  final Locale locale;
  const LocaleChanged(this.locale);
}

class LocalizationBloc extends RealtimeBloc<Locale, LocalizationEvent> {
  final LocalizationService _localizationService;

  LocalizationBloc(this._localizationService)
      : super(RealtimeSuccess(data: _localizationService.getLocale()));

  @override
  Stream<Locale> get dataStream => _localizationService.localeStream;

  @override
  void registerEventHandlers() {
    on<LocaleChanged>(_onLocaleChanged);
  }

  Future<void> _onLocaleChanged(
    LocaleChanged event,
    Emitter<RealtimeState<Locale>> emit,
  ) async {
    await performOptimisticUpdate(
      operationId: 'locale_change_${DateTime.now().millisecondsSinceEpoch}',
      optimisticData: event.locale,
      operation: () => _localizationService.setLocale(event.locale),
    );
  }
}
