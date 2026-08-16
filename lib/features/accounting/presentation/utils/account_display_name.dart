import 'package:easy_localization/easy_localization.dart';

import '../../../../core/database/app_database.dart';

String localizedAccountName(Account account) =>
    localizedAccountNameByCode(account.accountCode, account.accountName);

String localizedAccountNameByCode(String code, String fallback) {
  final key = 'financial_management.acct_${code}_name';
  final translated = key.tr();
  return translated == key ? fallback : translated;
}

String? localizedAccountDescription(Account account) {
  final key = 'financial_management.acct_${account.accountCode}_desc';
  final translated = key.tr();
  if (translated != key) return translated;
  final fallback = account.description?.trim();
  return fallback == null || fallback.isEmpty ? null : fallback;
}
