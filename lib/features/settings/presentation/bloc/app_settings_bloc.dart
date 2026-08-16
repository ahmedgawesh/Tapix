import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/app_settings_service.dart';
import '../../domain/entities/app_settings.dart';

// ── Events ──

abstract class AppSettingsEvent {
  const AppSettingsEvent();
}

class AppSettingsLoaded extends AppSettingsEvent {
  const AppSettingsLoaded();
}

class AppSettingsUpdated extends AppSettingsEvent {
  final AppSettings settings;
  const AppSettingsUpdated(this.settings);
}

class AppSettingsPatched extends AppSettingsEvent {
  final AppSettings Function(AppSettings current) patcher;
  const AppSettingsPatched(this.patcher);
}

// ── State ──

class AppSettingsState {
  final AppSettings settings;
  final bool isSaving;

  const AppSettingsState({required this.settings, this.isSaving = false});

  AppSettingsState copyWith({AppSettings? settings, bool? isSaving}) {
    return AppSettingsState(
      settings: settings ?? this.settings,
      isSaving: isSaving ?? this.isSaving,
    );
  }
}

// ── Bloc ──

class AppSettingsBloc extends Bloc<AppSettingsEvent, AppSettingsState> {
  final AppSettingsService _service;
  StreamSubscription<AppSettings>? _subscription;

  AppSettingsBloc(this._service)
    : super(AppSettingsState(settings: _service.current)) {
    on<AppSettingsLoaded>(_onLoaded);
    on<AppSettingsUpdated>(_onUpdated);
    on<AppSettingsPatched>(_onPatched);

    _subscription = _service.stream.listen((s) {
      add(const AppSettingsLoaded());
    });
  }

  void _onLoaded(AppSettingsLoaded event, Emitter<AppSettingsState> emit) {
    emit(state.copyWith(settings: _service.current));
  }

  Future<void> _onUpdated(
    AppSettingsUpdated event,
    Emitter<AppSettingsState> emit,
  ) async {
    emit(state.copyWith(isSaving: true));
    await _service.update(event.settings);
    emit(state.copyWith(settings: event.settings, isSaving: false));
  }

  Future<void> _onPatched(
    AppSettingsPatched event,
    Emitter<AppSettingsState> emit,
  ) async {
    final patched = event.patcher(state.settings);
    emit(state.copyWith(isSaving: true));
    await _service.update(patched);
    emit(state.copyWith(settings: patched, isSaving: false));
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
