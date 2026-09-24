import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/platform_utils.dart';
import 'push_notification_service.dart';

class LocalizationService {
  final SharedPreferences _prefs;
  static const String _localeKey = 'locale_code';
  final _localeController = StreamController<Locale>.broadcast();

  LocalizationService(this._prefs);

  Stream<Locale> get localeStream => _localeController.stream;

  static const supportedLocales = [Locale('en'), Locale('ar'), Locale('fr')];

  Locale getLocale() {
    final localeCode = _prefs.getString(_localeKey);
    if (localeCode != null) {
      return Locale(localeCode);
    }
    return const Locale('en');
  }

  Future<void> setLocale(Locale locale) async {
    await _prefs.setString(_localeKey, locale.languageCode);
    _localeController.add(locale);

    // Keep the standalone notifications profile in sync with the language
    // selected inside TapBix. This does not touch licensing or subscriptions.
    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      unawaited(PushNotificationService.instance.refreshRegistration());
    }
  }

  bool isRTL(Locale locale) {
    return locale.languageCode == 'ar';
  }

  Future<void> dispose() async {
    await _localeController.close();
  }
}
