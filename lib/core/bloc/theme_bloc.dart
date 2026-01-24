import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/theme_service.dart';
import 'realtime_bloc.dart';

// Events
abstract class ThemeEvent extends RealtimeEvent {
  const ThemeEvent();
}

class ThemeChanged extends ThemeEvent {
  final ThemeMode mode;
  const ThemeChanged(this.mode);
}

class ThemeBloc extends RealtimeBloc<ThemeMode, ThemeEvent> {
  final ThemeService _themeService;

  ThemeBloc(this._themeService)
      : super(RealtimeSuccess(data: _themeService.getThemeMode()));

  @override
  Stream<ThemeMode> get dataStream => _themeService.themeModeStream;

  @override
  void registerEventHandlers() {
    on<ThemeChanged>(_onThemeChanged);
  }

  Future<void> _onThemeChanged(
    ThemeChanged event,
    Emitter<RealtimeState<ThemeMode>> emit,
  ) async {
    await performOptimisticUpdate(
      operationId: 'theme_change_${DateTime.now().millisecondsSinceEpoch}',
      optimisticData: event.mode,
      operation: () => _themeService.setThemeMode(event.mode),
    );
  }
}
