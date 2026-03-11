import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/app_settings.dart';

const _kAppSettingsKey = 'app_settings_v1';

class AppSettingsService {
  final SharedPreferences _prefs;
  final StreamController<AppSettings> _controller = StreamController<AppSettings>.broadcast();

  late AppSettings _current;

  AppSettingsService(this._prefs) {
    _current = _load();
  }

  AppSettings get current => _current;

  Stream<AppSettings> get stream => _controller.stream;

  AppSettings _load() {
    final json = _prefs.getString(_kAppSettingsKey);
    if (json == null) return const AppSettings();
    return AppSettings.fromJson(json);
  }

  Future<void> update(AppSettings settings) async {
    _current = settings;
    await _prefs.setString(_kAppSettingsKey, settings.toJson());
    _controller.add(_current);
  }

  /// Convenience: update a single field via copyWith callback.
  Future<void> patch(AppSettings Function(AppSettings current) patcher) async {
    await update(patcher(_current));
  }

  void dispose() {
    _controller.close();
  }
}
