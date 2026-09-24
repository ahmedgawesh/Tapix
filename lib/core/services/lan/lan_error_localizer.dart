import 'package:easy_localization/easy_localization.dart';

import 'lan_business_models.dart';

/// Converts stable LAN error codes into user-facing text in the current app
/// language. Server messages remain diagnostic details and are never shown as
/// the fallback because a master and client may run with different locales.
String localizeLanBusinessError(
  LanBusinessException error, {
  String fallbackKey = 'settings.network.request_failed',
}) {
  final direct = error.code.tr();
  if (direct != error.code) return direct;

  final networkKey = 'settings.network.errors.${error.code}';
  final networkMessage = networkKey.tr();
  if (networkMessage != networkKey) return networkMessage;

  return fallbackKey.tr();
}
