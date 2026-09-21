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
  final String? errorMessageKey;

  const AppSettingsState({
    required this.settings,
    this.isSaving = false,
    this.errorMessageKey,
  });

  AppSettingsState copyWith({
    AppSettings? settings,
    bool? isSaving,
    String? errorMessageKey,
    bool clearError = false,
  }) {
    return AppSettingsState(
      settings: settings ?? this.settings,
      isSaving: isSaving ?? this.isSaving,
      errorMessageKey: clearError
          ? null
          : errorMessageKey ?? this.errorMessageKey,
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
    await _save(() => _service.update(event.settings), emit);
  }

  Future<void> _onPatched(
    AppSettingsPatched event,
    Emitter<AppSettingsState> emit,
  ) async {
    await _save(() => _service.patch(event.patcher), emit);
  }

  Future<void> _save(
    Future<void> Function() action,
    Emitter<AppSettingsState> emit,
  ) async {
    emit(state.copyWith(isSaving: true, clearError: true));
    try {
      await action();
      emit(state.copyWith(settings: _service.current, isSaving: false));
    } catch (_) {
      emit(
        state.copyWith(
          settings: _service.current,
          isSaving: false,
          errorMessageKey: 'app_settings.save_error',
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
