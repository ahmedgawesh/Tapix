import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/localization_service.dart';

// ==================== STATES ====================

abstract class LocalizationState {
  final Locale locale;
  const LocalizationState(this.locale);
}

class LocalizationReady extends LocalizationState {
  const LocalizationReady(super.locale);
}

// ==================== EVENTS ====================

abstract class LocalizationEvent {
  const LocalizationEvent();
}

class LocaleChanged extends LocalizationEvent {
  final Locale locale;
  const LocaleChanged(this.locale);
}

class _LocaleStreamUpdated extends LocalizationEvent {
  final Locale locale;
  const _LocaleStreamUpdated(this.locale);
}

// ==================== BLOC ====================

class LocalizationBloc extends Bloc<LocalizationEvent, LocalizationState> {
  final LocalizationService _localizationService;
  StreamSubscription<Locale>? _streamSub;

  LocalizationBloc(this._localizationService)
      : super(LocalizationReady(_localizationService.getLocale())) {
    on<LocaleChanged>(_onLocaleChanged);
    on<_LocaleStreamUpdated>(_onStreamUpdated);

    // Listen to stream for external changes (e.g. another isolate)
    _streamSub = _localizationService.localeStream.listen((locale) {
      add(_LocaleStreamUpdated(locale));
    });
  }

  void _onLocaleChanged(
    LocaleChanged event,
    Emitter<LocalizationState> emit,
  ) {
    // Emit immediately so UI updates instantly
    emit(LocalizationReady(event.locale));
    // Persist in background (fire-and-forget, SharedPreferences is fast)
    _localizationService.setLocale(event.locale);
  }

  void _onStreamUpdated(
    _LocaleStreamUpdated event,
    Emitter<LocalizationState> emit,
  ) {
    // Only emit if actually different from current to avoid unnecessary rebuilds
    if (state.locale.languageCode != event.locale.languageCode) {
      emit(LocalizationReady(event.locale));
    }
  }

  @override
  Future<void> close() {
    _streamSub?.cancel();
    return super.close();
  }
}
